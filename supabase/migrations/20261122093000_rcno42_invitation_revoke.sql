-- RCNO-42 招待を一覧して取り消せるようにする（無期限の招待を止めるため）
--
--   ruuuto_issue_invitation(p_group_id, p_expires_in)  -> {id, token, expires_at, expires_in}  ※ id を追加
--   ruuuto_list_invitations(p_group_id)                -> [{id, created_by, created_by_name, created_at, expires_at, expires_in}]
--   ruuuto_revoke_invitation(p_invitation_id)          -> {id, revoked_at}
--
-- 誰が見られる・取り消せるか
--   オーナー: グループの全部の招待
--   メンバー: 自分が作った招待だけ
-- 一覧に出るのは、まだ使える招待（取り消しておらず、期限が切れていない）だけ。トークンは出さない（DBにはハッシュしかない）。
-- 取り消した招待で参加しようとすると、これまでどおり RC003（無効）。
-- 権限のない招待・存在しない招待の取り消しは、どちらも 42501（あるかどうかを見せない）。

-- 一覧で期限の種類を出すため、選んだ期限を保存する（以前の招待は null）
alter table public.invitations add column expires_in text
  check (expires_in in ('30m', '1h', '6h', '12h', '1d', '7d', 'never'));

create or replace function public.ruuuto_issue_invitation(p_group_id uuid, p_expires_in text default '7d')
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
  v_id uuid;
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

  insert into public.invitations (group_id, token_hash, created_by, expires_at, expires_in)
  values (p_group_id, extensions.digest(v_token, 'sha256'), v_user_id, v_expires_at, v_expires_in)
  returning id into v_id;

  return json_build_object('id', v_id, 'token', v_token, 'expires_at', v_expires_at, 'expires_in', v_expires_in);
end;
$$;

-- まだ使える招待の一覧（新しい順）
create function public.ruuuto_list_invitations(p_group_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_is_owner boolean;
begin
  v_user_id := private.ruuuto_require_member(p_group_id);
  select m.role = 'owner' into v_is_owner
  from public.group_members m
  where m.group_id = p_group_id and m.user_id = v_user_id;

  return coalesce((
    select json_agg(json_build_object(
             'id', i.id,
             'created_by', i.created_by,
             'created_by_name', p.display_name,
             'created_at', private.ruuuto_ts(i.created_at),
             'expires_at', case when i.expires_at is null then null else private.ruuuto_ts(i.expires_at) end,
             'expires_in', i.expires_in)
           order by i.created_at desc, i.id)
    from public.invitations i
    left join public.profiles p on p.id = i.created_by
    where i.group_id = p_group_id
      and i.revoked_at is null
      and (i.expires_at is null or i.expires_at > now())
      and (v_is_owner or i.created_by = v_user_id)
  ), '[]'::json);
end;
$$;

-- 取り消す。送り直しても同じ結果（最初に取り消した日時を返す）
create function public.ruuuto_revoke_invitation(p_invitation_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_invitation public.invitations%rowtype;
begin
  select * into v_invitation from public.invitations i where i.id = p_invitation_id for update;

  if not found or not (
    v_invitation.created_by = v_user_id
    or exists (
      select 1 from public.group_members m
      where m.group_id = v_invitation.group_id and m.user_id = v_user_id and m.role = 'owner'
    )
  ) then
    raise exception 'この招待を取り消す権限がありません' using errcode = '42501';
  end if;

  -- 作った人がもうグループにいない場合は取り消せない（オーナーは取り消せる）
  if not exists (
    select 1 from public.group_members m
    where m.group_id = v_invitation.group_id and m.user_id = v_user_id
  ) then
    raise exception 'この招待を取り消す権限がありません' using errcode = '42501';
  end if;

  if v_invitation.revoked_at is null then
    update public.invitations i set revoked_at = now()
     where i.id = p_invitation_id
    returning * into v_invitation;
  end if;

  return json_build_object('id', v_invitation.id, 'revoked_at', private.ruuuto_ts(v_invitation.revoked_at));
end;
$$;

revoke execute on function public.ruuuto_list_invitations(uuid) from public, anon;
revoke execute on function public.ruuuto_revoke_invitation(uuid) from public, anon;
grant execute on function public.ruuuto_list_invitations(uuid) to authenticated;
grant execute on function public.ruuuto_revoke_invitation(uuid) to authenticated;
