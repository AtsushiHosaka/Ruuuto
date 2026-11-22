-- RCNO-42 グループ作成と招待参加
--
-- iOSのドラフトPR（#6 #8 #10）が呼ぶRPCを用意する。
--   ruuuto_list_groups()                         -> [{id, name}]
--   ruuuto_create_group(p_name, p_request_id)    -> {id, name}
--   ruuuto_issue_invitation(p_group_id)          -> {token, expires_at}
--   ruuuto_accept_invitation(p_token)            -> {group_id, joined}
-- 招待はリンク方式（2026年11月21日の決定）。

-- 週の区切り（暫定）
-- 週の開始曜日と時刻はまだ決まっていない（RCNO-10）。決まるまでは
-- 「日本時間の月曜0時に始まり、7日後に締め切る」とする。変えるときはこの関数だけを直す。
create function private.ruuuto_week_window(p_at timestamptz)
returns table (opens_at timestamptz, closes_at timestamptz)
language sql
stable
set search_path = ''
as $$
  select w.start_at, w.start_at + interval '7 days'
  from (
    select (date_trunc('week', p_at at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo') as start_at
  ) w;
$$;

-- その週の固定のお題。月と「その月の第何週か」で topic_prompts を引く。
-- 初期データ（RCNO-4）が入るまでは、既定の文言を使う。
create function private.ruuuto_weekly_prompt(p_opens_at timestamptz)
returns table (prompt_id uuid, topic text)
language sql
stable
set search_path = ''
as $$
  with local_day as (
    select (p_opens_at at time zone 'Asia/Tokyo')::date as d
  )
  select p.id, coalesce(p.body, '今週の一枚')
  from local_day
  left join public.topic_prompts p
    on p.month = extract(month from local_day.d)::smallint
   and p.week = least(5, ((extract(day from local_day.d)::int - 1) / 7) + 1)::smallint;
$$;

-- グループ1件を {id, name} で返す
create function private.ruuuto_group_json(p_group_id uuid)
returns json
language sql
stable
set search_path = ''
as $$
  select json_build_object('id', g.id, 'name', g.name)
  from public.groups g
  where g.id = p_group_id;
$$;

-- 所属グループの一覧。参加した順。
create function public.ruuuto_list_groups()
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
    (select json_agg(json_build_object('id', g.id, 'name', g.name) order by m.joined_at, g.id)
     from public.group_members m
     join public.groups g on g.id = m.group_id
     where m.user_id = v_user_id),
    '[]'::json);
end;
$$;

-- グループを作る。作成者を owner として所属させ、今週のボードも作る。
-- 同じ p_request_id で送り直したときは、前回作ったグループを返す（二重に作らない）。
-- グループ名は前後の空白を除いて1〜40文字。不正なら RC006。
create function public.ruuuto_create_group(p_name text, p_request_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_name text := btrim(coalesce(p_name, ''));
  v_group_id uuid;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_prompt_id uuid;
  v_topic text;
begin
  if p_request_id is null then
    raise exception '作成要求のIDが必要です' using errcode = '22004';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'グループ名は1〜40文字で入力してください' using errcode = 'RC006';
  end if;

  insert into public.groups (name, created_by, create_request_id)
  values (v_name, v_user_id, p_request_id)
  on conflict (created_by, create_request_id) do nothing
  returning id into v_group_id;

  if v_group_id is null then
    -- 送り直し。前回のグループを返す
    select g.id into v_group_id
    from public.groups g
    where g.created_by = v_user_id and g.create_request_id = p_request_id;
    return private.ruuuto_group_json(v_group_id);
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_user_id, 'owner');

  select w.opens_at, w.closes_at into v_opens_at, v_closes_at
  from private.ruuuto_week_window(now()) w;
  select p.prompt_id, p.topic into v_prompt_id, v_topic
  from private.ruuuto_weekly_prompt(v_opens_at) p;

  insert into public.boards (group_id, topic, topic_source, prompt_id, opens_at, closes_at)
  values (v_group_id, v_topic, 'weekly', v_prompt_id, v_opens_at, v_closes_at);

  return private.ruuuto_group_json(v_group_id);
end;
$$;

-- 招待トークンを発行する。所属している人だけ。有効期限は暫定で7日。
-- トークンは32バイトの乱数をURLで使える文字（A-Z a-z 0-9 - _）にしたもの。
-- DBにはSHA-256のハッシュだけを保存する。
create function public.ruuuto_issue_invitation(p_group_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_token text;
  v_expires_at timestamptz := date_trunc('second', now()) + interval '7 days';
begin
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_user_id
  ) then
    raise exception 'このグループの招待を発行する権限がありません' using errcode = '42501';
  end if;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');

  insert into public.invitations (group_id, token_hash, created_by, expires_at)
  values (p_group_id, extensions.digest(v_token, 'sha256'), v_user_id, v_expires_at);

  return json_build_object('token', v_token, 'expires_at', v_expires_at);
end;
$$;

-- 招待から参加する。
--   見つからない・取り消し済み → RC003（無効）
--   有効期限切れ               → RC004
--   すでに所属している         → 成功（joined = false）。所属は重複しない
create function public.ruuuto_accept_invitation(p_token text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_invitation public.invitations%rowtype;
  v_inserted int;
begin
  if p_token is null or char_length(p_token) not between 1 and 512 then
    raise exception '招待リンクが無効です' using errcode = 'RC003';
  end if;

  select * into v_invitation
  from public.invitations i
  where i.token_hash = extensions.digest(p_token, 'sha256');

  if not found or v_invitation.revoked_at is not null then
    raise exception '招待リンクが無効です' using errcode = 'RC003';
  end if;
  if v_invitation.expires_at <= now() then
    raise exception '招待リンクの有効期限が切れています' using errcode = 'RC004';
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_invitation.group_id, v_user_id, 'member')
  on conflict (group_id, user_id) do nothing;
  get diagnostics v_inserted = row_count;

  return json_build_object('group_id', v_invitation.group_id, 'joined', v_inserted = 1);
end;
$$;

revoke execute on function private.ruuuto_week_window(timestamptz) from public, anon, authenticated;
revoke execute on function private.ruuuto_weekly_prompt(timestamptz) from public, anon, authenticated;
revoke execute on function private.ruuuto_group_json(uuid) from public, anon, authenticated;
revoke execute on function public.ruuuto_list_groups() from public, anon;
revoke execute on function public.ruuuto_create_group(text, uuid) from public, anon;
revoke execute on function public.ruuuto_issue_invitation(uuid) from public, anon;
revoke execute on function public.ruuuto_accept_invitation(text) from public, anon;
grant execute on function public.ruuuto_list_groups() to authenticated;
grant execute on function public.ruuuto_create_group(text, uuid) to authenticated;
grant execute on function public.ruuuto_issue_invitation(uuid) to authenticated;
grant execute on function public.ruuuto_accept_invitation(text) to authenticated;
