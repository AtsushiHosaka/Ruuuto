-- RCNO-37 プッシュの配信処理と無効な端末登録の処理を用意する
--
-- 流れ（1分ごと）
--   Cron → private.ruuuto_request_push_dispatch() → Edge Function push-dispatch
--     1. ruuuto_admin_push_fanout()   通知イベントから配信行（端末ごとに1行）を作る
--                                     （この課題では何もしない。RCNO-9 で中身を入れる）
--     2. ruuuto_admin_push_claim()    送る時刻になった配信行を「送信中」にして受け取る
--     3. APNs へ送る（HTTP/2・トークン認証）
--     4. ruuuto_admin_push_record()   結果を記録する。無効な端末はこの時点で無効にする
--
-- 二重送信を防ぐしくみ
--   * 配信行は (event_id, device_id) で一意。同じイベントを同じ端末へ2回は作らない。
--   * 受け取りは for update skip locked。同時に2つ動いても同じ行は片方だけが受け取る。
--   * APNs の apns-collapse-id にイベントIDを入れる。万一2回届いても通知は1件にまとまる。
--
-- 結果の扱い
--   200                                      → sent
--   410、400 の BadDeviceToken / Unregistered / DeviceTokenNotForTopic
--                                            → invalid（端末を無効にし、以後は送らない）
--   429・5xx・通信エラー・403（署名トークンの期限切れなど）
--                                            → 1・5・15・30分後に再送。5回失敗したら failed
--   そのほかの 4xx                            → failed
--   送る前に端末の登録が外れた・別の利用者へ移った → skipped
--   イベントから6時間を過ぎても送れなかった    → skipped（古い通知は送らない）
--
-- iOS（RCNO-11 NotificationDeviceAPI）が呼ぶ形
--   ruuuto_sync_device(p_installation_id, p_apns_token
--                      [, p_environment, p_locale, p_enabled])
--   入力が不正 RC015 / 未ログイン 42501

-- 端末登録に、送り先の環境と表示言語を足す
--   environment  sandbox（Xcode のデバッグ実行）/ production（TestFlight・App Store）
--   locale       端末の言語（例: ja, en, en-US, ja_JP）。通知の文面を選ぶのに使う
--   apns_token が null の行と、invalidated_at が入っている行には送らない
alter table public.devices
  add column environment text not null default 'production'
    check (environment in ('sandbox', 'production')),
  add column locale text
    check (locale is null or (char_length(locale) <= 35
      and locale ~ '^[A-Za-z]{2,3}([_-][A-Za-z0-9]{1,8})*$')),
  add column synced_at timestamptz;

-- 自分の端末を登録・更新・解除する（iOS RCNO-11 から呼ぶ）
--   * p_apns_token に16進のトークンを渡すと登録・更新。null なら解除（通知を止める）。
--   * p_enabled = false も解除として扱う。
--   * 同じ installation_id を別の利用者が登録していた場合（同じ端末でアカウントを
--     切り替えた場合）は、呼んだ利用者の端末に移す。
--   * 同じトークンがほかのインストールに残っていたら、そちらからは外す。
--   * p_environment・p_locale が null なら、前回の値を残す（初回は production・未設定）。
--   * 登録し直すと、無効にした印（invalidated_at）は消える。
create function public.ruuuto_sync_device(
  p_installation_id uuid,
  p_apns_token text,
  p_environment text default null,
  p_locale text default null,
  p_enabled boolean default true
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_token text := lower(btrim(p_apns_token));
  v_locale text := nullif(btrim(p_locale), '');
  v_device public.devices%rowtype;
begin
  if p_installation_id is null
     or (p_apns_token is not null and v_token !~ '^[0-9a-f]{64,200}$')
     or (p_environment is not null and p_environment not in ('sandbox', 'production'))
     or (v_locale is not null and (char_length(v_locale) > 35
         or v_locale !~ '^[A-Za-z]{2,3}([_-][A-Za-z0-9]{1,8})*$')) then
    raise exception '端末の登録内容が正しくありません' using errcode = 'RC015';
  end if;

  if p_enabled is false then
    v_token := null;
  end if;

  if v_token is not null then
    update public.devices d
       set apns_token = null
     where d.apns_token = v_token and d.installation_id <> p_installation_id;
  end if;

  insert into public.devices as d
    (installation_id, user_id, apns_token, environment, locale, invalidated_at, synced_at)
  values
    (p_installation_id, v_user_id, v_token, coalesce(p_environment, 'production'), v_locale, null, now())
  on conflict (installation_id) do update
     set user_id = excluded.user_id,
         apns_token = excluded.apns_token,
         environment = coalesce(p_environment, d.environment),
         locale = coalesce(v_locale, d.locale),
         invalidated_at = null,
         synced_at = now()
  returning * into v_device;

  return json_build_object(
    'installation_id', v_device.installation_id,
    'enabled', v_device.apns_token is not null,
    'environment', v_device.environment,
    'locale', v_device.locale);
end;
$$;

revoke execute on function public.ruuuto_sync_device(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.ruuuto_sync_device(uuid, text, text, text, boolean) to authenticated;

-- 配信行: 1つの通知イベントを1台の端末へ送る記録
create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.notification_events (id) on delete cascade,
  device_id uuid not null references public.devices (installation_id) on delete cascade,
  -- 配信行を作った時点の端末の持ち主。送る前に別の人へ移っていたら送らない
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null,
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed', 'invalid', 'skipped')),
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  -- 受け取った時点のトークン。無効の判定はこのトークンに対して行う
  apns_token text,
  environment text,
  last_status_code int,
  last_reason text,
  apns_id text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, device_id)
);

create index notification_deliveries_due_idx
  on public.notification_deliveries (next_attempt_at) where status in ('pending', 'sending');
create index notification_deliveries_device_idx on public.notification_deliveries (device_id);

create trigger notification_deliveries_touch before update on public.notification_deliveries
  for each row execute function public.ruuuto_touch_updated_at();

alter table public.notification_deliveries enable row level security;
-- アプリからは読み書きさせない（ポリシーなし）
revoke all on public.notification_deliveries from anon, authenticated;

-- 送ってよい端末か。登録中で無効になっておらず、配信行を作ったときと同じ人の端末で、
-- その人がまだグループに所属していること。
-- RCNO-9 でグループごとの通知設定を足すときは、この関数を置き換える。
create function private.ruuuto_push_target_ok(p_device_id uuid, p_user_id uuid, p_group_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.devices dv
    join public.group_members m on m.user_id = dv.user_id and m.group_id = p_group_id
    where dv.installation_id = p_device_id
      and dv.user_id = p_user_id
      and dv.apns_token is not null
      and dv.invalidated_at is null);
$$;

revoke execute on function private.ruuuto_push_target_ok(uuid, uuid, uuid) from public, anon, authenticated;

-- 通知イベントから配信行を作る。RCNO-9 で置き換える（この課題では何もしない）。
create function public.ruuuto_admin_push_fanout()
returns json
language plpgsql
security definer
set search_path = ''
as $$
begin
  return json_build_object('events', 0, 'deliveries', 0);
end;
$$;

-- 送る時刻になった配信行を受け取る
--   * 送信中のまま10分たった行（Edge Function が途中で止まった）も受け取り直す。
--     その場合 APNs には届いている可能性があるが、apns-collapse-id で1件にまとまる。
--   * 送れない端末の行と、イベントから6時間を過ぎた行は skipped にする。
--   * 戻り値: [{id, event_id, kind, group_id, board_id, title, body,
--              apns_token, environment, attempts}]
create function public.ruuuto_admin_push_claim(p_limit int default 100)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_result json;
begin
  select array_agg(x.id) into v_ids
  from (
    select d.id
    from public.notification_deliveries d
    where (d.status = 'pending' and d.next_attempt_at <= now())
       or (d.status = 'sending' and d.updated_at < now() - interval '10 minutes')
    order by d.next_attempt_at, d.id
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    for update skip locked
  ) x;

  if v_ids is null then
    return '[]'::json;
  end if;

  update public.notification_deliveries d
     set status = 'skipped', last_reason = 'Expired'
    from public.notification_events e
   where d.id = any (v_ids) and e.id = d.event_id
     and e.created_at < now() - interval '6 hours';

  update public.notification_deliveries d
     set status = 'skipped', last_reason = 'DeviceUnavailable'
    from public.notification_events e
   where d.id = any (v_ids) and e.id = d.event_id and d.status <> 'skipped'
     and not private.ruuuto_push_target_ok(d.device_id, d.user_id, e.group_id);

  with claimed as (
    update public.notification_deliveries d
       set status = 'sending',
           attempts = d.attempts + 1,
           apns_token = dv.apns_token,
           environment = dv.environment
      from public.devices dv
     where d.id = any (v_ids) and d.status in ('pending', 'sending')
       and dv.installation_id = d.device_id
    returning d.*
  )
  select coalesce(json_agg(json_build_object(
             'id', c.id,
             'event_id', c.event_id,
             'kind', e.kind,
             'group_id', e.group_id,
             'board_id', e.board_id,
             'title', c.title,
             'body', c.body,
             'apns_token', c.apns_token,
             'environment', c.environment,
             'attempts', c.attempts)
           order by c.next_attempt_at, c.id), '[]'::json)
    into v_result
    from claimed c
    join public.notification_events e on e.id = c.event_id;

  return v_result;
end;
$$;

-- 送った結果を記録する
--   p_results: [{"id": 配信行ID, "outcome": "sent"|"retry"|"invalid"|"failed",
--                "status_code": 数値か null, "reason": 文字列か null, "apns_id": 文字列か null}]
--   * retry は回数に応じて 1・5・15・30 分後に送り直す。5回目で failed にする。
--   * invalid は、送ったときと同じトークンのままの端末を無効にする（以後は送らない）。
--   * 送信中でない行は変えない（受け取り直された古い結果で上書きしない）。
-- 戻り値: {"sent", "retry", "invalid", "failed"} の件数
create function public.ruuuto_admin_push_record(p_results jsonb)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_outcome text;
  v_row public.notification_deliveries%rowtype;
  v_counts jsonb := '{"sent": 0, "retry": 0, "invalid": 0, "failed": 0}'::jsonb;
  v_backoff interval[] := array[interval '1 minute', interval '5 minutes',
                                interval '15 minutes', interval '30 minutes'];
begin
  if p_results is null or jsonb_typeof(p_results) <> 'array' then
    raise exception '結果の形式が正しくありません' using errcode = '22023';
  end if;

  for v_item in select * from jsonb_array_elements(p_results) loop
    v_outcome := v_item ->> 'outcome';
    if v_outcome is null or v_outcome not in ('sent', 'retry', 'invalid', 'failed') then
      raise exception '結果の形式が正しくありません' using errcode = '22023';
    end if;

    select * into v_row from public.notification_deliveries d
     where d.id = (v_item ->> 'id')::uuid and d.status = 'sending'
     for update;
    if not found then
      continue;
    end if;

    if v_outcome = 'retry' and v_row.attempts >= 5 then
      v_outcome := 'failed';
    end if;

    update public.notification_deliveries d
       set status = case v_outcome when 'retry' then 'pending' else v_outcome end,
           next_attempt_at = case when v_outcome = 'retry'
                                  then now() + v_backoff[least(v_row.attempts, 4)]
                                  else d.next_attempt_at end,
           last_status_code = (v_item ->> 'status_code')::int,
           last_reason = left(v_item ->> 'reason', 200),
           apns_id = coalesce(left(v_item ->> 'apns_id', 64), d.apns_id),
           sent_at = case when v_outcome = 'sent' then now() else d.sent_at end
     where d.id = v_row.id;

    if v_outcome = 'invalid' then
      update public.devices dv
         set invalidated_at = now()
       where dv.installation_id = v_row.device_id
         and dv.apns_token = v_row.apns_token
         and dv.invalidated_at is null;
    end if;

    v_counts := jsonb_set(v_counts, array[v_outcome], to_jsonb((v_counts ->> v_outcome)::int + 1));
  end loop;

  return v_counts::json;
end;
$$;

revoke execute on function public.ruuuto_admin_push_fanout() from public, anon, authenticated;
revoke execute on function public.ruuuto_admin_push_claim(int) from public, anon, authenticated;
revoke execute on function public.ruuuto_admin_push_record(jsonb) from public, anon, authenticated;
grant execute on function public.ruuuto_admin_push_fanout() to service_role;
grant execute on function public.ruuuto_admin_push_claim(int) to service_role;
grant execute on function public.ruuuto_admin_push_record(jsonb) to service_role;

-- Cron から Edge Function push-dispatch を呼ぶ
-- 接続先と合言葉は Vault に置く（リポジトリには書かない）。未設定なら何もしない。
--   select vault.create_secret('https://<project-ref>.supabase.co', 'ruuuto_project_url');  -- RCNO-35 で設定済みなら不要
--   select vault.create_secret('<ランダムな文字列>', 'ruuuto_push_secret');
-- 同じ合言葉を Edge Function の環境変数 PUSH_DISPATCH_SECRET に設定する。
create function private.ruuuto_request_push_dispatch()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'ruuuto_project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'ruuuto_push_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/push-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-ruuuto-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000);
end;
$$;

revoke execute on function private.ruuuto_request_push_dispatch() from public, anon, authenticated;

select cron.schedule(
  'ruuuto-push-dispatch',
  '* * * * *',
  $$select private.ruuuto_request_push_dispatch()$$
);
