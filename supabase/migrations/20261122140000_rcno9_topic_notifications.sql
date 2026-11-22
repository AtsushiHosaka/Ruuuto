-- RCNO-9 お題変更をプッシュで知らせる
--
-- 2026-11-22 の判断
-- * v1 で送る通知は「お題が変わった」の1種類。きっかけは2つ。
--     topic_published  週の切替で新しいボードが公開された（RCNO-10）
--     topic_changed    メンバーが手動でお題を変えた（RCNO-41）
-- * 手動で変えた本人には送らない。
-- * 手動の変更が続いたときは、最後の変更から2分間ほかの変更がなければ、最新のお題だけを送る。
--   それより前の変更は送らずに処理済みにする（skipped_reason = 'superseded'）。
-- * 送り先は、いまグループに所属していて、通知を許可した有効な端末を登録している人。
--   グループの通知をオフにした人には送らない（グループごとの通知設定。既定はオン）。
-- * 文面の言語は端末登録の locale で選ぶ。ja・en の文面を用意し、それ以外は日本語。
--   固定のお題（RCNO-4）は日本語だけ。手動のお題は入力されたまま送る。
--
-- 処理（Edge Function push-dispatch が1分ごとに ruuuto_admin_push_fanout() を呼ぶ）
--   1. 6時間を過ぎた未処理のイベントは送らない（stale）
--   2. 同じボードに新しい手動変更があるものは送らない（superseded）
--   3. 締め切られたボードの手動変更は送らない（board_closed）
--   4. 公開はすぐ、手動変更は2分たったら、送り先の端末ごとに配信行を作って処理済みにする
--   何度実行しても配信行は増えない（(event_id, device_id) が一意、on conflict do nothing）。
--
-- グループごとの通知設定（iOS の画面は任意。なくても既定のオンのまま動く）
--   ruuuto_set_group_notifications(p_group_id, p_enabled) → {group_id, notifications_enabled}
--   ruuuto_list_groups() の各要素に notifications_enabled を足す
--   所属していない 42501 / p_enabled が null 22023

alter table public.notification_events
  add column skipped_reason text
    check (skipped_reason is null or skipped_reason in ('stale', 'superseded', 'board_closed'));

create index notification_events_board_kind_idx
  on public.notification_events (board_id, kind, created_at);

alter table public.group_members
  add column notifications_enabled boolean not null default true;

-- グループの通知をオン・オフする（自分の設定だけ）
create function public.ruuuto_set_group_notifications(p_group_id uuid, p_enabled boolean)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_member(p_group_id);
  v_enabled boolean;
begin
  if p_enabled is null then
    raise exception '通知の設定を指定してください' using errcode = '22023';
  end if;

  update public.group_members m
     set notifications_enabled = p_enabled
   where m.group_id = p_group_id and m.user_id = v_user_id
  returning m.notifications_enabled into v_enabled;

  return json_build_object('group_id', p_group_id, 'notifications_enabled', v_enabled);
end;
$$;

revoke execute on function public.ruuuto_set_group_notifications(uuid, boolean) from public, anon;
grant execute on function public.ruuuto_set_group_notifications(uuid, boolean) to authenticated;

-- 所属グループの一覧に通知設定を足す（RCNO-42 の関数を置き換え。既存のキーと並び順は同じ）
create or replace function public.ruuuto_list_groups()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
begin
  return coalesce(
    (select json_agg(json_build_object(
              'id', g.id,
              'name', g.name,
              'notifications_enabled', m.notifications_enabled)
            order by m.joined_at, g.id)
     from public.group_members m
     join public.groups g on g.id = m.group_id
     where m.user_id = v_user_id),
    '[]'::json);
end;
$$;

-- 送ってよい端末か（RCNO-37 の関数を置き換え）。グループの通知をオフにした人にも送らない。
-- 配信行を作った後にオフにした場合も、送る直前のこの確認で止まる。
create or replace function private.ruuuto_push_target_ok(p_device_id uuid, p_user_id uuid, p_group_id uuid)
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
      and dv.invalidated_at is null
      and m.notifications_enabled);
$$;

-- 通知の文面。locale の言語部分（en-US なら en）が en なら英語、それ以外は日本語。
create function private.ruuuto_push_text(p_kind text, p_locale text, p_topic text, p_actor text)
returns table (title text, body text)
language sql
immutable
set search_path = ''
as $$
  select
    case when l.lang = 'en' then
      case p_kind when 'topic_published' then 'This week''s topic' else 'Topic changed' end
    else
      case p_kind when 'topic_published' then '今週のお題' else 'お題が変わりました' end
    end,
    case
      when p_kind = 'topic_published' then p_topic
      when l.lang = 'en' and p_actor is not null then p_actor || ' changed it to “' || p_topic || '”'
      when l.lang = 'en' then 'The topic is now “' || p_topic || '”'
      when p_actor is not null then p_actor || 'さんが「' || p_topic || '」に変えました'
      else 'お題が「' || p_topic || '」に変わりました'
    end
  from (select lower(split_part(replace(coalesce(p_locale, ''), '_', '-'), '-', 1)) as lang) l;
$$;

revoke execute on function private.ruuuto_push_text(text, text, text, text) from public, anon, authenticated;

-- 通知イベントから配信行を作る（RCNO-37 の仮の関数を置き換え）
-- 戻り値: {"events": 配信行を作ったイベント数, "deliveries": 作った配信行数, "skipped": 送らずに処理したイベント数}
create or replace function public.ruuuto_admin_push_fanout()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_skipped int := 0;
  v_count int;
  v_events int;
  v_deliveries int;
begin
  -- 1. 古すぎるイベント
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'stale'
   where e.processed_at is null and e.created_at < now() - interval '6 hours';
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 2. 同じボードに、より新しい手動変更がある
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'superseded'
   where e.processed_at is null and e.kind = 'topic_changed'
     and exists (
       select 1 from public.notification_events n
       where n.board_id = e.board_id and n.kind = 'topic_changed' and n.id <> e.id
         and (n.created_at > e.created_at or (n.created_at = e.created_at and n.id > e.id)));
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 3. 締め切られたボードの手動変更
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'board_closed'
    from public.boards b
   where e.processed_at is null and e.kind = 'topic_changed'
     and b.id = e.board_id and (b.status <> 'open' or b.closes_at <= now());
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 4. 送る時刻になったイベントの配信行を作る
  with ready as (
    select e.id, e.kind, e.group_id, e.topic, e.actor_id
    from public.notification_events e
    where e.processed_at is null
      and (e.kind = 'topic_published' or e.created_at <= now() - interval '2 minutes')
    order by e.created_at, e.id
    limit 200
    for update skip locked
  ), inserted as (
    insert into public.notification_deliveries (event_id, device_id, user_id, title, body)
    select r.id, dv.installation_id, dv.user_id, t.title, t.body
    from ready r
    join public.group_members m on m.group_id = r.group_id and m.notifications_enabled
    join public.devices dv on dv.user_id = m.user_id
                          and dv.apns_token is not null and dv.invalidated_at is null
    left join public.profiles actor on actor.id = r.actor_id
    cross join lateral private.ruuuto_push_text(r.kind, dv.locale, r.topic, actor.display_name) t
    where r.kind = 'topic_published' or m.user_id is distinct from r.actor_id
    on conflict (event_id, device_id) do nothing
    returning 1
  ), done as (
    update public.notification_events e
       set processed_at = now()
      from ready r
     where e.id = r.id
    returning 1
  )
  select (select count(*) from done), (select count(*) from inserted)
    into v_events, v_deliveries;

  return json_build_object('events', v_events, 'deliveries', v_deliveries, 'skipped', v_skipped);
end;
$$;
