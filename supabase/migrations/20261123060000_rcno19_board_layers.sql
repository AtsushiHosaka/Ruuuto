-- RCNO-19 写真と装飾を3つのレイヤーに分ける
--
-- 背景のつもりで置いた写真が、誰かが動かすと前に出てしまっていた（RCNO-19 の先勝ちで
-- 「つかむと最前面」にしていたため）。ボードを3つの固定のレイヤーに分け、
-- つかんだときに前へ出すかは各自の設定にする。
--
-- レイヤー（photos.layer / decorations.layer、smallint）
--   0 = 背景、1 = 写真、2 = 装飾。どのレイヤーにも写真・装飾（ペンを含む）を置ける。
--   新しい写真は 1、新しい装飾は 2 に入る。既存の行も同じ値にした。
--   描く順番は layer の昇順、同じ layer の中は z_index の昇順（大きいほど手前）。
--   z_index は (ボード, レイヤー) ごとに写真と装飾で1つの並びを共有する。
--   同じ (layer, z_index) は作らない（並びを変える操作は (ボード, レイヤー) ごとの
--   advisory lock で順番に処理する）。z_index は負の値にもなる（最背面へ送ると最小 - 1）。
--   万一同じ値が並んだら、写真 → 装飾、id の順に描く。
--   既存の行の z_index は、レイヤーごとに今の順番のまま 1, 2, 3... に振り直した
--   （写真は投稿済みだけ、z_index・posted_at・id の順。装飾は z_index・created_at・id の順）。
--
-- 背景レイヤーのものは固定する
--   ruuuto_grab_* / ruuuto_move_* は RC016。動かしたいときは先に ruuuto_set_item_layer で
--   写真・装飾レイヤーへ移す。ruuuto_release_* はこれまでどおり呼べる。
--   自分がつかんでいるものを背景へ移したときは、つかみを外す（photo_unlocked などが届く）。
--
-- つかんだら前に出すか（各自の設定 profiles.auto_bring_to_front、既定 false）
--   グループ共通ではなく、操作する人ごとの好み。grab はつかんだ人（呼び出した人）の設定を使う。
--   false: つかんでも z_index と revision は変わらない。
--   true : 新しくつかんだとき、そのレイヤーの中で一番手前に出す（z_index = レイヤーの最大 + 1、
--          revision + 1）。上のレイヤーより前には出ない。延長の grab では変えない。
--          新しい並びは photo_saved / decoration_saved で全員に届く（その人の操作として共有される）。
--   設定を変えても配信はしない（ほかの人の表示には関係しないため）。
--
-- RPC（いずれも所属メンバーだけ。未ログイン・所属していない・対象がないときは 42501）
--   ruuuto_set_item_layer(p_kind text, p_id uuid, p_layer smallint) -> 写真または装飾
--     p_kind は 'photo' か 'decoration'。対象を p_layer のレイヤーの一番手前へ移し、revision + 1。
--     すでにそのレイヤーの一番手前なら何も変えずに今の状態を返す。
--   ruuuto_reorder_item(p_kind text, p_id uuid, p_position text) -> 写真または装飾
--     p_position は 'front'（最前面へ）か 'back'（最背面へ）。今のレイヤーの中で並べ替え、revision + 1。
--     すでに一番手前（奥）なら何も変えずに今の状態を返す。
--   ruuuto_set_my_preferences(p_auto_bring_to_front boolean default null) -> {auto_bring_to_front}
--     自分の設定を変える。null なら今の値のまま（今の値を読むだけにも使える）。
--   ruuuto_my_profile() の戻り値に auto_bring_to_front を足す（id, display_name はそのまま）。
--   set_item_layer / reorder_item は、ほかの人がつかんでいる間は RC012（DETAIL は grab と同じ JSON）。
--   自分がつかんでいるものは変えられる。締切後は RC002。取り下げ済みの写真は RC010、
--   自分の投稿途中の写真は RC008（ほかの人の投稿途中の写真は 42501）。
--   戻り値は grab と同じ形（写真・装飾の形に locked_by, lock_expires_at を足したもの）。
--   PostgREST からは p_layer に数値（0, 1, 2）を渡す。SQL から呼ぶときは 0::smallint のように書く。
--
-- 写真・装飾の形（photo_saved / decoration_saved、snapshot、各 RPC の戻り値）に layer を足す。
-- ruuuto_board_snapshot の photos / decorations は layer、z_index の昇順で返す。
--
-- エラー
--   RC016 背景レイヤーのものは動かせない（grab / move）
--   RC017 並べ替えの指定が正しくない（p_kind・p_layer・p_position が不正や null）

alter table public.profiles
  add column auto_bring_to_front boolean not null default false;

alter table public.photos
  add column layer smallint not null default 1 check (layer between 0 and 2);

alter table public.decorations
  add column layer smallint not null default 2 check (layer between 0 and 2);

-- 既存の重なり順をレイヤーごとに振り直す（配信や updated_at の更新は起こさない）
alter table public.photos disable trigger user;
update public.photos p
   set z_index = s.z
  from (select p2.id,
               row_number() over (partition by p2.board_id, p2.layer
                                  order by p2.z_index, p2.posted_at, p2.id)::int as z
          from public.photos p2
         where p2.status = 'posted') s
 where p.id = s.id and p.z_index <> s.z;
alter table public.photos enable trigger user;

alter table public.decorations disable trigger user;
update public.decorations d
   set z_index = s.z
  from (select d2.id,
               row_number() over (partition by d2.board_id, d2.layer
                                  order by d2.z_index, d2.created_at, d2.id)::int as z
          from public.decorations d2) s
 where d.id = s.id and d.z_index <> s.z;
alter table public.decorations enable trigger user;

create index photos_board_layer_z_idx on public.photos (board_id, layer, z_index)
  where status = 'posted';
create index decorations_board_layer_z_idx on public.decorations (board_id, layer, z_index);

-- (ボード, レイヤー) の重なり順の変更を順番に並べる
create function private.ruuuto_lock_layer(p_board_id uuid, p_layer smallint)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('ruuuto_layer_z:' || p_board_id || ':' || p_layer, 0));
$$;

-- レイヤーにあるほかのもの（投稿済みの写真と装飾。p_kind / p_id の自分は除く）の z_index の最大・最小
create function private.ruuuto_layer_z_bounds(
  p_board_id uuid, p_layer smallint, p_kind text, p_id uuid,
  out max_z integer, out min_z integer)
language sql
stable
set search_path = ''
as $$
  select max(s.z), min(s.z)
  from (
    select p.z_index as z from public.photos p
    where p.board_id = p_board_id and p.layer = p_layer and p.status = 'posted'
      and not (p_kind = 'photo' and p.id = p_id)
    union all
    select d.z_index from public.decorations d
    where d.board_id = p_board_id and d.layer = p_layer
      and not (p_kind = 'decoration' and d.id = p_id)
  ) s;
$$;

-- p_layer の一番手前に置くときの z_index。同じレイヤーですでに一番手前なら今の値を返す。
-- 呼ぶ側が ruuuto_lock_layer(p_board_id, p_layer) を持っていること。
create function private.ruuuto_front_z(
  p_board_id uuid, p_layer smallint, p_kind text, p_id uuid,
  p_current_layer smallint, p_current_z integer)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_max integer;
begin
  select b.max_z into v_max from private.ruuuto_layer_z_bounds(p_board_id, p_layer, p_kind, p_id) b;
  if p_layer is distinct from p_current_layer then
    return coalesce(v_max, 0) + 1;
  end if;
  if v_max is null or p_current_z > v_max then
    return p_current_z;
  end if;
  return v_max + 1;
end;
$$;

-- 今のレイヤーの一番奥に置くときの z_index。すでに一番奥なら今の値を返す。
create function private.ruuuto_back_z(
  p_board_id uuid, p_layer smallint, p_kind text, p_id uuid, p_current_z integer)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_min integer;
begin
  select b.min_z into v_min from private.ruuuto_layer_z_bounds(p_board_id, p_layer, p_kind, p_id) b;
  if v_min is null or p_current_z < v_min then
    return p_current_z;
  end if;
  return v_min - 1;
end;
$$;

-- 背景レイヤーのものは動かせない（RC016）
create function private.ruuuto_require_movable_layer(p_layer smallint)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_layer = 0 then
    raise exception '背景レイヤーのものは動かせません' using errcode = 'RC016';
  end if;
end;
$$;

-- ほかの人がつかんでいれば RC012（自分がつかんでいる・空いている・期限切れなら通す）
create function private.ruuuto_require_not_locked_by_other(
  p_locked_by uuid, p_lock_expires_at timestamptz, p_user_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_locked_by is not null and p_lock_expires_at > now() and p_locked_by <> p_user_id then
    perform private.ruuuto_raise_locked(p_locked_by, p_lock_expires_at);
  end if;
end;
$$;

-- 自分の「つかんだら前に出す」設定
create function private.ruuuto_my_auto_bring_to_front(p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((select p.auto_bring_to_front from public.profiles p where p.id = p_user_id), false);
$$;

-- 写真1件を返す形に layer を足す（RCNO-35 の関数を置き換え。ほかのキーは同じ）
create or replace function private.ruuuto_photo_json(p_photo public.photos)
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
    'layer', p_photo.layer,
    'z_index', p_photo.z_index,
    'revision', p_photo.revision,
    'posted_at', case when p_photo.posted_at is null then null else private.ruuuto_ts(p_photo.posted_at) end);
$$;

-- 装飾1件を返す形に layer を足す（RCNO-36 の関数を置き換え。ほかのキーは同じ）
create or replace function private.ruuuto_decoration_json(p_decoration public.decorations)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_decoration.id,
    'board_id', p_decoration.board_id,
    'created_by', p_decoration.created_by,
    'kind', p_decoration.kind,
    'content', p_decoration.content,
    'x', p_decoration.x,
    'y', p_decoration.y,
    'rotation', p_decoration.rotation,
    'scale', p_decoration.scale,
    'layer', p_decoration.layer,
    'z_index', p_decoration.z_index,
    'revision', p_decoration.revision,
    'updated_by', p_decoration.updated_by,
    'created_at', private.ruuuto_ts(p_decoration.created_at),
    'updated_at', private.ruuuto_ts(p_decoration.updated_at));
$$;

-- 投稿を確定する（RCNO-35 の関数を置き換え）。重なり順は写真の層（投稿時の layer）の一番手前。
create or replace function public.ruuuto_finish_photo(p_photo_id uuid)
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

  perform private.ruuuto_lock_layer(v_photo.board_id, v_photo.layer);
  update public.photos p
     set status = 'posted',
         posted_at = now(),
         z_index = coalesce((select b.max_z from private.ruuuto_layer_z_bounds(
                               v_photo.board_id, v_photo.layer, 'photo', v_photo.id) b), 0) + 1,
         updated_by = v_user_id
   where p.id = p_photo_id
  returning * into v_photo;

  return private.ruuuto_photo_json(v_photo);
end;
$$;

-- 装飾を追加する（RCNO-27 の関数を置き換え）。重なり順は装飾のレイヤー（2）の一番手前。
create or replace function public.ruuuto_add_decoration(
  p_decoration_id uuid,
  p_board_id uuid,
  p_kind text,
  p_content jsonb,
  p_x double precision,
  p_y double precision,
  p_rotation double precision default 0,
  p_scale double precision default 1
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_decoration public.decorations%rowtype;
  v_layer smallint := 2;
begin
  v_user_id := private.ruuuto_require_board_member(p_board_id);

  if p_decoration_id is null
     or p_x is null or p_y is null or p_rotation is null or p_scale is null
     or p_x in ('NaN', 'Infinity', '-Infinity')
     or p_y in ('NaN', 'Infinity', '-Infinity')
     or p_rotation in ('NaN', 'Infinity', '-Infinity')
     or p_scale in ('NaN', 'Infinity', '-Infinity')
     or p_scale <= 0 then
    raise exception '装飾の内容が正しくありません' using errcode = 'RC014';
  end if;
  perform private.ruuuto_require_decoration_content(p_kind, p_content);

  -- 送り直し: 同じ人が同じボードに追加した行があれば、それを返す
  select * into v_decoration from public.decorations d where d.id = p_decoration_id;
  if found then
    if v_decoration.created_by <> v_user_id or v_decoration.board_id <> p_board_id then
      raise exception '同じIDの別の装飾があります' using errcode = 'RC009';
    end if;
    return (private.ruuuto_decoration_json(v_decoration)
            || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
  end if;

  perform private.ruuuto_require_open_board(p_board_id);

  -- 重なり順を決める間、同じ (ボード, レイヤー) の z_index の更新を順番に並べる
  perform private.ruuuto_lock_layer(p_board_id, v_layer);

  insert into public.decorations
    (id, board_id, created_by, kind, content, x, y, rotation, scale, layer, z_index, updated_by)
  values
    (p_decoration_id, p_board_id, v_user_id, p_kind, p_content, p_x, p_y, p_rotation, p_scale, v_layer,
     coalesce((select b.max_z from private.ruuuto_layer_z_bounds(p_board_id, v_layer, 'decoration', p_decoration_id) b), 0) + 1,
     v_user_id)
  on conflict (id) do nothing
  returning * into v_decoration;

  -- 同じIDで同時に追加された（同じ人の送り直しが重なった等）: 先に入った行で判定し直す
  if v_decoration.id is null then
    select * into v_decoration from public.decorations d where d.id = p_decoration_id;
    if v_decoration.created_by <> v_user_id or v_decoration.board_id <> p_board_id then
      raise exception '同じIDの別の装飾があります' using errcode = 'RC009';
    end if;
  end if;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- 写真: つかむ（RCNO-19 の関数を置き換え）。背景は RC016。前に出すのは設定が true のときだけ。
create or replace function public.ruuuto_grab_photo(p_photo_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype := private.ruuuto_lock_photo_row(p_photo_id, true);
  v_held boolean := v_photo.locked_by is not null and v_photo.lock_expires_at > now();
  v_z integer := v_photo.z_index;
begin
  perform private.ruuuto_require_movable_layer(v_photo.layer);
  if v_held and v_photo.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_photo.locked_by, v_photo.lock_expires_at);
  end if;

  -- 新しくつかんだときだけ、つかんだ人の設定が true ならレイヤーの一番手前に出す
  if not (v_held and v_photo.locked_by = v_user_id)
     and private.ruuuto_my_auto_bring_to_front(v_user_id) then
    perform private.ruuuto_lock_layer(v_photo.board_id, v_photo.layer);
    v_z := private.ruuuto_front_z(v_photo.board_id, v_photo.layer, 'photo', v_photo.id,
                                  v_photo.layer, v_photo.z_index);
  end if;

  update public.photos p
     set locked_by = v_user_id,
         lock_expires_at = now() + private.ruuuto_lock_lease(),
         z_index = v_z,
         revision = p.revision + case when v_z <> p.z_index then 1 else 0 end
   where p.id = v_photo.id
  returning * into v_photo;

  return (private.ruuuto_photo_json(v_photo)::jsonb
          || private.ruuuto_lock_json(v_photo.locked_by, v_photo.lock_expires_at))::json;
end;
$$;

-- 写真: 位置を保存する（RCNO-19 の関数を置き換え）。背景は RC016。
create or replace function public.ruuuto_move_photo(
  p_photo_id uuid,
  p_x double precision,
  p_y double precision,
  p_rotation double precision,
  p_scale double precision,
  p_release boolean default false
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype := private.ruuuto_lock_photo_row(p_photo_id, true);
  v_release boolean := coalesce(p_release, false);
begin
  perform private.ruuuto_require_movable_layer(v_photo.layer);
  perform private.ruuuto_require_position(p_x, p_y, p_rotation, p_scale);

  if v_photo.locked_by is null or v_photo.lock_expires_at <= now() then
    raise exception 'この写真をつかんでいません' using errcode = 'RC013';
  end if;
  if v_photo.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_photo.locked_by, v_photo.lock_expires_at);
  end if;

  update public.photos p
     set x = p_x, y = p_y, rotation = p_rotation, scale = p_scale,
         revision = p.revision + 1,
         updated_by = v_user_id,
         locked_by = case when v_release then null else v_user_id end,
         lock_expires_at = case when v_release then null else now() + private.ruuuto_lock_lease() end
   where p.id = v_photo.id
  returning * into v_photo;

  return (private.ruuuto_photo_json(v_photo)::jsonb
          || private.ruuuto_lock_json(v_photo.locked_by, v_photo.lock_expires_at))::json;
end;
$$;

-- 装飾: つかむ（RCNO-19 の関数を置き換え）
create or replace function public.ruuuto_grab_decoration(p_decoration_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_decoration public.decorations%rowtype := private.ruuuto_lock_decoration_row(p_decoration_id, true);
  v_held boolean := v_decoration.locked_by is not null and v_decoration.lock_expires_at > now();
  v_z integer := v_decoration.z_index;
begin
  perform private.ruuuto_require_movable_layer(v_decoration.layer);
  if v_held and v_decoration.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_decoration.locked_by, v_decoration.lock_expires_at);
  end if;

  if not (v_held and v_decoration.locked_by = v_user_id)
     and private.ruuuto_my_auto_bring_to_front(v_user_id) then
    perform private.ruuuto_lock_layer(v_decoration.board_id, v_decoration.layer);
    v_z := private.ruuuto_front_z(v_decoration.board_id, v_decoration.layer, 'decoration', v_decoration.id,
                                  v_decoration.layer, v_decoration.z_index);
  end if;

  update public.decorations d
     set locked_by = v_user_id,
         lock_expires_at = now() + private.ruuuto_lock_lease(),
         z_index = v_z,
         revision = d.revision + case when v_z <> d.z_index then 1 else 0 end
   where d.id = v_decoration.id
  returning * into v_decoration;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- 装飾: 位置を保存する（RCNO-19 の関数を置き換え）。背景は RC016。
create or replace function public.ruuuto_move_decoration(
  p_decoration_id uuid,
  p_x double precision,
  p_y double precision,
  p_rotation double precision,
  p_scale double precision,
  p_release boolean default false
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_decoration public.decorations%rowtype := private.ruuuto_lock_decoration_row(p_decoration_id, true);
  v_release boolean := coalesce(p_release, false);
begin
  perform private.ruuuto_require_movable_layer(v_decoration.layer);
  perform private.ruuuto_require_position(p_x, p_y, p_rotation, p_scale);

  if v_decoration.locked_by is null or v_decoration.lock_expires_at <= now() then
    raise exception 'この装飾をつかんでいません' using errcode = 'RC013';
  end if;
  if v_decoration.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_decoration.locked_by, v_decoration.lock_expires_at);
  end if;

  update public.decorations d
     set x = p_x, y = p_y, rotation = p_rotation, scale = p_scale,
         revision = d.revision + 1,
         updated_by = v_user_id,
         locked_by = case when v_release then null else v_user_id end,
         lock_expires_at = case when v_release then null else now() + private.ruuuto_lock_lease() end
   where d.id = v_decoration.id
  returning * into v_decoration;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- レイヤー・並べ替えの入力を確かめる（RC017）
create function private.ruuuto_raise_bad_order()
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception '並べ替えの指定が正しくありません' using errcode = 'RC017';
end;
$$;

-- 対象を新しい (layer, z_index) に置く。変わらなければ何もしない。
-- 背景へ移すときは、つかみを外す（背景のものはつかめないため）。
create function private.ruuuto_place_item(
  p_kind text, p_id uuid, p_layer smallint, p_z integer, p_user_id uuid)
returns json
language plpgsql
set search_path = ''
as $$
declare
  v_photo public.photos%rowtype;
  v_decoration public.decorations%rowtype;
begin
  if p_kind = 'photo' then
    update public.photos p
       set layer = p_layer,
           z_index = p_z,
           revision = p.revision + 1,
           updated_by = p_user_id,
           locked_by = case when p_layer = 0 then null else p.locked_by end,
           lock_expires_at = case when p_layer = 0 then null else p.lock_expires_at end
     where p.id = p_id and (p.layer <> p_layer or p.z_index <> p_z);
    select * into v_photo from public.photos p where p.id = p_id;
    return (private.ruuuto_photo_json(v_photo)::jsonb
            || private.ruuuto_lock_json(v_photo.locked_by, v_photo.lock_expires_at))::json;
  end if;

  update public.decorations d
     set layer = p_layer,
         z_index = p_z,
         revision = d.revision + 1,
         updated_by = p_user_id,
         locked_by = case when p_layer = 0 then null else d.locked_by end,
         lock_expires_at = case when p_layer = 0 then null else d.lock_expires_at end
   where d.id = p_id and (d.layer <> p_layer or d.z_index <> p_z);
  select * into v_decoration from public.decorations d where d.id = p_id;
  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- 並べ替える対象を行ロック付きで取り出し、(board_id, layer, z_index) を返す。
-- 所属・締切・取り下げ・投稿途中・ほかの人のつかみを確かめる。ペンの装飾も対象にできる。
create function private.ruuuto_lock_item_for_order(
  p_kind text, p_id uuid, p_user_id uuid,
  out board_id uuid, out layer smallint, out z_index integer)
language plpgsql
set search_path = ''
as $$
declare
  v_photo public.photos%rowtype;
  v_decoration public.decorations%rowtype;
begin
  if p_kind = 'photo' then
    v_photo := private.ruuuto_lock_photo_row(p_id, true);
    perform private.ruuuto_require_not_locked_by_other(v_photo.locked_by, v_photo.lock_expires_at, p_user_id);
    board_id := v_photo.board_id;
    layer := v_photo.layer;
    z_index := v_photo.z_index;
  else
    v_decoration := private.ruuuto_lock_decoration_row(p_id, false);
    perform private.ruuuto_require_open_board(v_decoration.board_id);
    perform private.ruuuto_require_not_locked_by_other(
      v_decoration.locked_by, v_decoration.lock_expires_at, p_user_id);
    board_id := v_decoration.board_id;
    layer := v_decoration.layer;
    z_index := v_decoration.z_index;
  end if;
end;
$$;

-- レイヤーを変える。移した先のレイヤーの一番手前に置く。
create function public.ruuuto_set_item_layer(p_kind text, p_id uuid, p_layer smallint)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_item record;
  v_z integer;
begin
  if p_kind is null or p_kind not in ('photo', 'decoration') or p_id is null
     or p_layer is null or p_layer not between 0 and 2 then
    perform private.ruuuto_raise_bad_order();
  end if;

  select * into v_item from private.ruuuto_lock_item_for_order(p_kind, p_id, v_user_id);
  perform private.ruuuto_lock_layer(v_item.board_id, p_layer);
  v_z := private.ruuuto_front_z(v_item.board_id, p_layer, p_kind, p_id, v_item.layer, v_item.z_index);
  return private.ruuuto_place_item(p_kind, p_id, p_layer, v_z, v_user_id);
end;
$$;

-- 今のレイヤーの中で最前面（front）・最背面（back）へ移す
create function public.ruuuto_reorder_item(p_kind text, p_id uuid, p_position text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_item record;
  v_z integer;
begin
  if p_kind is null or p_kind not in ('photo', 'decoration') or p_id is null
     or p_position is null or p_position not in ('front', 'back') then
    perform private.ruuuto_raise_bad_order();
  end if;

  select * into v_item from private.ruuuto_lock_item_for_order(p_kind, p_id, v_user_id);
  perform private.ruuuto_lock_layer(v_item.board_id, v_item.layer);
  if p_position = 'front' then
    v_z := private.ruuuto_front_z(v_item.board_id, v_item.layer, p_kind, p_id, v_item.layer, v_item.z_index);
  else
    v_z := private.ruuuto_back_z(v_item.board_id, v_item.layer, p_kind, p_id, v_item.z_index);
  end if;
  return private.ruuuto_place_item(p_kind, p_id, v_item.layer, v_z, v_user_id);
end;
$$;

-- 自分のプロフィールに auto_bring_to_front を足す（RCNO-40 の関数を置き換え。既存のキーは同じ）
create or replace function public.ruuuto_my_profile()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_result json;
begin
  select json_build_object('id', p.id, 'display_name', p.display_name,
                           'auto_bring_to_front', p.auto_bring_to_front)
    into v_result
  from public.profiles p
  where p.id = v_user_id;

  if v_result is null then
    -- Authにはいるがプロフィールがない（削除直後など）。iOSはサインアウトして扱う。
    raise exception 'プロフィールが見つかりません' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 自分の設定を変える。null の項目は今の値のまま。
create function public.ruuuto_set_my_preferences(p_auto_bring_to_front boolean default null)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_value boolean;
begin
  update public.profiles p
     set auto_bring_to_front = coalesce(p_auto_bring_to_front, p.auto_bring_to_front)
   where p.id = v_user_id
     and p.auto_bring_to_front is distinct from coalesce(p_auto_bring_to_front, p.auto_bring_to_front);

  select p.auto_bring_to_front into v_value from public.profiles p where p.id = v_user_id;
  if not found then
    raise exception 'プロフィールが見つかりません' using errcode = 'P0002';
  end if;
  return json_build_object('auto_bring_to_front', v_value);
end;
$$;

-- スナップショットをレイヤー、重なり順の順に返す（RCNO-19 の関数を置き換え）
create or replace function public.ruuuto_board_snapshot(p_board_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_board public.boards%rowtype;
begin
  perform private.ruuuto_require_board_member(p_board_id);
  select * into v_board from public.boards b where b.id = p_board_id;

  return json_build_object(
    'board', private.ruuuto_board_json(v_board),
    'photos', coalesce((
      select json_agg(
               private.ruuuto_photo_json(p)::jsonb || private.ruuuto_lock_json(p.locked_by, p.lock_expires_at)
               order by p.layer, p.z_index, p.posted_at, p.id)
      from public.photos p
      where p.board_id = p_board_id and p.status = 'posted'), '[]'::json),
    'decorations', coalesce((
      select json_agg(
               private.ruuuto_decoration_json(d) || private.ruuuto_lock_json(d.locked_by, d.lock_expires_at)
               order by d.layer, d.z_index, d.created_at, d.id)
      from public.decorations d
      where d.board_id = p_board_id), '[]'::json));
end;
$$;

revoke execute on function private.ruuuto_lock_layer(uuid, smallint) from public, anon, authenticated;
revoke execute on function private.ruuuto_layer_z_bounds(uuid, smallint, text, uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_front_z(uuid, smallint, text, uuid, smallint, integer) from public, anon, authenticated;
revoke execute on function private.ruuuto_back_z(uuid, smallint, text, uuid, integer) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_movable_layer(smallint) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_not_locked_by_other(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_my_auto_bring_to_front(uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_raise_bad_order() from public, anon, authenticated;
revoke execute on function private.ruuuto_place_item(text, uuid, smallint, integer, uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_lock_item_for_order(text, uuid, uuid) from public, anon, authenticated;

revoke execute on function public.ruuuto_set_item_layer(text, uuid, smallint) from public, anon;
revoke execute on function public.ruuuto_reorder_item(text, uuid, text) from public, anon;
revoke execute on function public.ruuuto_set_my_preferences(boolean) from public, anon;
grant execute on function public.ruuuto_set_item_layer(text, uuid, smallint) to authenticated;
grant execute on function public.ruuuto_reorder_item(text, uuid, text) to authenticated;
grant execute on function public.ruuuto_set_my_preferences(boolean) to authenticated;
