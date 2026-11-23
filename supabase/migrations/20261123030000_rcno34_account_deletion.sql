-- RCNO-34 グループを作った利用者もアカウントを削除できるようにする
--
-- Authユーザーを消すと profiles が消え、groups.created_by（on delete restrict）が
-- それを止めていた。プロフィールが消える直前に、その人が持つグループを次のように片付ける。
--
-- 2026-11-23 の判断
-- * ほかのメンバーが残るグループ: 所有権を、残るメンバーのうち最も早く参加した人へ移す。
--   groups.created_by と group_members の role = 'owner' の両方を移す。
--   ほかに owner が残っている場合は、その中で最も早く参加した人を使う。
-- * ほかのメンバーがいないグループ: グループを消す（ボード・写真・装飾・招待も一緒に消える）。
-- * 本人の写真・装飾・端末・招待・配信記録は、これまでどおり外部キーの cascade で消える。
--   通知イベントの actor_id、写真・装飾の updated_by と locked_by は null になる。
--
-- 画像の片付け（RCNO-35 の photo-cleanup）
--   写真の行が消えても、Storage の画像は SQL からは消せない（storage.protect_delete）。
--   ruuuto_admin_photo_cleanup_targets が、photos バケットにあって対応する写真の行がない画像
--   （作成から p_pending_older_than 以上たったもの）も paths に含めるようにする。
--   アップロードは投稿途中の行があるときだけ許可しているため、行のない画像は、
--   アカウント削除やグループ削除で行が消えたものに限られる。
--   戻り値の形 {removed_rows, paths} と Edge Function の呼び方は変えない。

-- プロフィールが消える前に、その人が持つグループを片付ける
create function private.ruuuto_release_owned_groups()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group record;
  v_next uuid;
begin
  for v_group in
    select g.id, g.created_by
    from public.groups g
    where g.created_by = old.id
       or exists (select 1 from public.group_members m
                  where m.group_id = g.id and m.user_id = old.id and m.role = 'owner')
    order by g.id
    for update of g
  loop
    -- 次の所有者: ほかに owner がいればその中で、いなければ残るメンバーの中で最も早く参加した人
    select m.user_id into v_next
    from public.group_members m
    where m.group_id = v_group.id and m.user_id <> old.id
    order by (m.role = 'owner') desc, m.joined_at, m.user_id
    limit 1;

    if v_next is null then
      delete from public.groups g where g.id = v_group.id;
    else
      update public.group_members m
         set role = 'owner'
       where m.group_id = v_group.id and m.user_id = v_next and m.role <> 'owner';
      if v_group.created_by = old.id then
        update public.groups g set created_by = v_next where g.id = v_group.id;
      end if;
    end if;
  end loop;

  return old;
end;
$$;

revoke execute on function private.ruuuto_release_owned_groups() from public, anon, authenticated;

create trigger profiles_release_owned_groups
  before delete on public.profiles
  for each row execute function private.ruuuto_release_owned_groups();

-- 消し残した画像の対象に、写真の行がない画像も含める（RCNO-35 の関数を置き換え。引数と戻り値の形は同じ）
create or replace function public.ruuuto_admin_photo_cleanup_targets(p_pending_older_than interval default interval '1 hour')
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed_rows int;
begin
  -- 画像がない投稿途中の行は、そのまま消す
  delete from public.photos p
   where p.status = 'pending'
     and p.created_at < now() - p_pending_older_than
     and not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = p.storage_path);
  get diagnostics v_removed_rows = row_count;

  return json_build_object(
    'removed_rows', v_removed_rows,
    'paths', coalesce((
      select json_agg(t.path order by t.path)
      from (
        -- 取り下げた写真と、放置された投稿途中の写真の画像
        select p.storage_path as path
        from public.photos p
        where (p.status = 'withdrawn'
               or (p.status = 'pending' and p.created_at < now() - p_pending_older_than))
          and exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = p.storage_path)
        union
        -- 写真の行が消えた画像（アカウント削除・グループ削除の後に残ったもの）
        select o.name
        from storage.objects o
        where o.bucket_id = 'photos'
          and o.created_at < now() - p_pending_older_than
          and not exists (select 1 from public.photos p where p.storage_path = o.name)
      ) t
    ), '[]'::json));
end;
$$;
