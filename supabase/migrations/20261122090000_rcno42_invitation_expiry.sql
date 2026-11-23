-- RCNO-42 招待の有効期限を、発行する人が選べるようにする
--
--   ruuuto_issue_invitation(p_group_id, p_expires_in default '7d') -> {token, expires_at, expires_in}
--
-- p_expires_in で選べる値（Discordの招待と同じ並び）
--   '30m' 30分 / '1h' 1時間 / '6h' 6時間 / '12h' 12時間 / '1d' 1日 / '7d' 7日（既定） / 'never' 無期限
-- 無期限のとき expires_at は null。これ以外の値は RC011。
-- p_expires_in を送らなければ、これまでどおり7日になる（今のiOSの呼び出しはそのまま動く）。

alter table public.invitations alter column expires_at drop not null;

-- 選べる期限と長さ。null は無期限
create function private.ruuuto_invitation_lifetime(p_expires_in text)
returns interval
language plpgsql
immutable
set search_path = ''
as $$
begin
  case p_expires_in
    when '30m' then return interval '30 minutes';
    when '1h' then return interval '1 hour';
    when '6h' then return interval '6 hours';
    when '12h' then return interval '12 hours';
    when '1d' then return interval '1 day';
    when '7d' then return interval '7 days';
    when 'never' then return null;
    else
      raise exception '招待の有効期限の指定が正しくありません' using errcode = 'RC011';
  end case;
end;
$$;

-- 引数が増えるので、1引数の版を消してから作り直す（同じ名前が2つあると呼び出しが曖昧になる）
drop function public.ruuuto_issue_invitation(uuid);

create function public.ruuuto_issue_invitation(p_group_id uuid, p_expires_in text default '7d')
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_expires_in text := coalesce(p_expires_in, '7d');
  v_lifetime interval;
  v_token text;
  v_expires_at timestamptz;
begin
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_user_id
  ) then
    raise exception 'このグループの招待を発行する権限がありません' using errcode = '42501';
  end if;

  v_lifetime := private.ruuuto_invitation_lifetime(v_expires_in);
  if v_lifetime is not null then
    v_expires_at := date_trunc('second', now()) + v_lifetime;
  end if;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');

  insert into public.invitations (group_id, token_hash, created_by, expires_at)
  values (p_group_id, extensions.digest(v_token, 'sha256'), v_user_id, v_expires_at);

  return json_build_object('token', v_token, 'expires_at', v_expires_at, 'expires_in', v_expires_in);
end;
$$;

-- 参加: 無期限（expires_at が null）の招待は期限切れにならない
create or replace function public.ruuuto_accept_invitation(p_token text)
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
  if v_invitation.expires_at is not null and v_invitation.expires_at <= now() then
    raise exception '招待リンクの有効期限が切れています' using errcode = 'RC004';
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_invitation.group_id, v_user_id, 'member')
  on conflict (group_id, user_id) do nothing;
  get diagnostics v_inserted = row_count;

  return json_build_object('group_id', v_invitation.group_id, 'joined', v_inserted = 1);
end;
$$;

revoke execute on function private.ruuuto_invitation_lifetime(text) from public, anon, authenticated;
revoke execute on function public.ruuuto_issue_invitation(uuid, text) from public, anon;
grant execute on function public.ruuuto_issue_invitation(uuid, text) to authenticated;
