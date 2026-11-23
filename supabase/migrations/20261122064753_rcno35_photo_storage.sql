-- RCNO-35 非公開の画像ストレージと削除処理
--
-- 投稿の流れ（iOS: RCNO-13〜16）
--   1. ruuuto_begin_photo(p_photo_id, p_board_id, p_city, p_width, p_height)
--        写真の行を「投稿途中（pending）」で作り、保存先のパスを返す。
--        p_photo_id はiOSが投稿前に決めるUUID。送り直しても同じ行を返す。
--   2. Storage API で photos バケットの storage_path にアップロードする。
--   3. ruuuto_finish_photo(p_photo_id)
--        画像が保存されていることを確かめて「投稿済み（posted）」にする。送り直しても同じ結果。
-- 取り下げ（RCNO-14）
--   ruuuto_withdraw_photo(p_photo_id) で取り下げ、続けて Storage API で画像を消す。
--   締切後でも本人は取り下げられる。消し残しは定期処理（photo-cleanup）が消す。
--
-- エラー: 締切後 RC002 / 画像が未アップロード RC007 / 入力が不正 RC008 /
--         同じIDの別の写真 RC009 / 取り下げ済み RC010 / 権限なし 42501
--
-- Storage の行は SQL から直接は消せない（storage.protect_delete）。画像の削除は必ず Storage API で行う。

-- 非公開バケット（10MBまで、JPEG・PNG・HEIC）
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 写真1枚をiOSに返す形
create function private.ruuuto_photo_json(p_photo public.photos)
returns json
language sql
stable
set search_path = ''
as $$
  select json_build_object(
    'id', p_photo.id,
    'board_id', p_photo.board_id,
    'posted_by', p_photo.posted_by,
    'bucket', 'photos',
    'storage_path', p_photo.storage_path,
    'status', p_photo.status,
    'city', p_photo.city,
    'width', p_photo.width,
    'height', p_photo.height,
    'x', p_photo.x,
    'y', p_photo.y,
    'rotation', p_photo.rotation,
    'scale', p_photo.scale,
    'z_index', p_photo.z_index,
    'revision', p_photo.revision,
    'posted_at', case when p_photo.posted_at is null then null else private.ruuuto_ts(p_photo.posted_at) end);
$$;

-- 1. 投稿を始める
create function public.ruuuto_begin_photo(
  p_photo_id uuid,
  p_board_id uuid,
  p_city text default null,
  p_width int default null,
  p_height int default null
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_board public.boards%rowtype;
  v_photo public.photos%rowtype;
  v_city text := nullif(btrim(coalesce(p_city, '')), '');
begin
  v_user_id := private.ruuuto_require_board_member(p_board_id);

  if p_photo_id is null
     or (v_city is not null and char_length(v_city) > 60)
     or (p_width is not null and p_width <= 0)
     or (p_height is not null and p_height <= 0) then
    raise exception '写真の情報が正しくありません' using errcode = 'RC008';
  end if;

  -- 送り直し: 同じIDの行があれば、それを返す
  select * into v_photo from public.photos p where p.id = p_photo_id;
  if found then
    if v_photo.posted_by <> v_user_id or v_photo.board_id <> p_board_id then
      raise exception '同じIDの別の写真があります' using errcode = 'RC009';
    end if;
    if v_photo.status = 'withdrawn' then
      raise exception 'この写真は取り下げ済みです' using errcode = 'RC010';
    end if;
    return private.ruuuto_photo_json(v_photo);
  end if;

  select * into v_board from public.boards b where b.id = p_board_id;
  if v_board.status <> 'open' or v_board.closes_at <= now() then
    raise exception '締切を過ぎたため投稿できません' using errcode = 'RC002';
  end if;

  insert into public.photos (id, board_id, posted_by, storage_path, status, city, width, height)
  values (p_photo_id, p_board_id, v_user_id,
          v_board.group_id || '/' || v_board.id || '/' || p_photo_id,
          'pending', v_city, p_width, p_height)
  returning * into v_photo;

  return private.ruuuto_photo_json(v_photo);
end;
$$;

-- 3. 投稿を確定する
create function public.ruuuto_finish_photo(p_photo_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype;
  v_board public.boards%rowtype;
begin
  select * into v_photo from public.photos p where p.id = p_photo_id for update;
  if not found or v_photo.posted_by <> v_user_id then
    raise exception 'この写真を投稿する権限がありません' using errcode = '42501';
  end if;
  perform private.ruuuto_require_board_member(v_photo.board_id);

  if v_photo.status = 'posted' then
    return private.ruuuto_photo_json(v_photo);
  end if;
  if v_photo.status = 'withdrawn' then
    raise exception 'この写真は取り下げ済みです' using errcode = 'RC010';
  end if;

  select * into v_board from public.boards b where b.id = v_photo.board_id;
  if v_board.status <> 'open' or v_board.closes_at <= now() then
    raise exception '締切を過ぎたため投稿できません' using errcode = 'RC002';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'photos' and o.name = v_photo.storage_path
  ) then
    raise exception '画像がまだアップロードされていません' using errcode = 'RC007';
  end if;

  update public.photos p
     set status = 'posted',
         posted_at = now(),
         z_index = coalesce((select max(p2.z_index) from public.photos p2
                             where p2.board_id = v_photo.board_id and p2.status = 'posted'), 0) + 1,
         updated_by = v_user_id
   where p.id = p_photo_id
  returning * into v_photo;

  return private.ruuuto_photo_json(v_photo);
end;
$$;

-- 取り下げる（本人だけ。締切後も可）
create function public.ruuuto_withdraw_photo(p_photo_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype;
begin
  select * into v_photo from public.photos p where p.id = p_photo_id for update;
  if not found or v_photo.posted_by <> v_user_id then
    raise exception 'この写真を取り下げる権限がありません' using errcode = '42501';
  end if;

  if v_photo.status <> 'withdrawn' then
    update public.photos p
       set status = 'withdrawn', withdrawn_at = now(), updated_by = v_user_id
     where p.id = p_photo_id
    returning * into v_photo;
  end if;

  return private.ruuuto_photo_json(v_photo);
end;
$$;

-- Storage の権限（photos バケット）
-- 読める: 所属グループの投稿済みの写真と、自分の写真（投稿途中・取り下げ済みを含む）。
-- Storage API は削除の前に読めるかを確かめるので、取り下げた本人が消すには本人が読める必要がある。
create function private.ruuuto_can_read_photo_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.photos p
    where p.storage_path = p_name
      and (
        p.posted_by = (select auth.uid())
        or (p.status = 'posted' and private.ruuuto_is_board_member(p.board_id))
      )
  );
$$;

-- 書ける: 自分の投稿途中の写真で、ボードが締切前のもの
create function private.ruuuto_can_write_photo_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.photos p
    join public.boards b on b.id = p.board_id
    where p.storage_path = p_name
      and p.posted_by = (select auth.uid())
      and p.status = 'pending'
      and b.status = 'open' and b.closes_at > now()
      and private.ruuuto_is_member(b.group_id)
  );
$$;

-- 消せる: 自分の写真で、投稿途中か取り下げ済みのもの
create function private.ruuuto_can_delete_photo_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.photos p
    where p.storage_path = p_name
      and p.posted_by = (select auth.uid())
      and p.status in ('pending', 'withdrawn')
  );
$$;

grant execute on function private.ruuuto_can_read_photo_object(text) to authenticated;
grant execute on function private.ruuuto_can_write_photo_object(text) to authenticated;
grant execute on function private.ruuuto_can_delete_photo_object(text) to authenticated;
revoke execute on function private.ruuuto_can_read_photo_object(text) from public, anon;
revoke execute on function private.ruuuto_can_write_photo_object(text) from public, anon;
revoke execute on function private.ruuuto_can_delete_photo_object(text) from public, anon;

create policy "photos: 所属グループの写真を読める"
  on storage.objects for select to authenticated
  using (bucket_id = 'photos' and private.ruuuto_can_read_photo_object(name));

create policy "photos: 投稿途中の自分の写真をアップロードできる"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and private.ruuuto_can_write_photo_object(name));

create policy "photos: 投稿途中の自分の写真を上書きできる"
  on storage.objects for update to authenticated
  using (bucket_id = 'photos' and private.ruuuto_can_write_photo_object(name))
  with check (bucket_id = 'photos' and private.ruuuto_can_write_photo_object(name));

create policy "photos: 投稿途中か取り下げた自分の写真を消せる"
  on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and private.ruuuto_can_delete_photo_object(name));

revoke execute on function private.ruuuto_photo_json(public.photos) from public, anon, authenticated;
revoke execute on function public.ruuuto_begin_photo(uuid, uuid, text, int, int) from public, anon;
revoke execute on function public.ruuuto_finish_photo(uuid) from public, anon;
revoke execute on function public.ruuuto_withdraw_photo(uuid) from public, anon;
grant execute on function public.ruuuto_begin_photo(uuid, uuid, text, int, int) to authenticated;
grant execute on function public.ruuuto_finish_photo(uuid) to authenticated;
grant execute on function public.ruuuto_withdraw_photo(uuid) to authenticated;
