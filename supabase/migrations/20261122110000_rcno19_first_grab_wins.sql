-- RCNO-19 同じ写真を同時に動かしたときの結果をそろえる（先につかんだ人が勝つ）
--
-- 決まり: 写真・装飾は「先につかんだ人」だけが動かせる。
--   指が触れた時点で ruuuto_grab_* を呼び、つかめた人だけがドラッグできる。
--   ほかの人は、つかんだ人が離すか、つかみが期限切れになるまで動かせない。
--   2人が引っ張り合って位置が行き来し続けるのを防ぐため、後勝ち（最後の保存が勝つ）にはしない。
--
-- つかみ（ロック）: photos / decorations の locked_by と lock_expires_at。
--   lock_expires_at > now() のときだけ有効。期限切れは「誰もつかんでいない」と同じ扱いで、
--   定期処理では消さない（次につかむ人が上書きする）。
--   期限は10秒。つかみ直し（同じ人の grab）と位置の保存のたびに now() + 10秒へ延ばす。
--
-- RPC（写真と装飾で同じ形。装飾は ruuuto_grab_decoration(p_decoration_id) など）
--   ruuuto_grab_photo(p_photo_id)
--     つかむ。空いている・期限切れ・自分がつかんでいるなら成功し、期限を延ばす。
--     新しくつかんだときは、ほかより下にあれば一番上に出す（z_index = ボードの最大 + 1、revision も1増やす）。
--     自分がつかみ続けている間の grab（延長）では重なり順を変えない。
--   ruuuto_move_photo(p_photo_id, p_x, p_y, p_rotation, p_scale, p_release default false)
--     自分がつかんでいるときだけ位置を保存し、revision を1増やす。
--     p_release = true なら保存と同時に離す（指を離したときはこれ1回でよい）。
--   ruuuto_release_photo(p_photo_id)
--     離す。自分がつかんでいなければ何もせず、今の状態を返す（何度呼んでもよい）。締切後も呼べる。
--   戻り値: 写真（ruuuto_begin_photo などと同じ形）または装飾（decoration_saved と同じ形）に
--           locked_by, lock_expires_at を足したもの。期限切れのつかみは両方 null で返す。
--           revision と x, y, rotation, scale, z_index が保存済みの値なので、iOSはこれに表示を合わせる。
--
-- エラー（コードは表示言語に依存しない。表示する文言はiOS側で決める）
--   RC002 締切後（ボードが open でない、または closes_at を過ぎた）。grab と move のみ
--   RC008 入力が不正（数値が NaN・無限大・null、scale <= 0、ペンの装飾、投稿途中の自分の写真）
--   RC010 取り下げ済みの写真
--   RC012 ほかの人がつかんでいる。DETAIL は JSON {"locked_by": "<uuid>", "lock_expires_at": "<UTC>"}
--   RC013 つかんでいない（つかまずに move した、または期限が切れた）。grab からやり直す
--   42501 未ログイン・所属していない・対象がない（ほかの人の投稿途中の写真も、ないものとして扱う）
--
-- board:<board_id> のイベント（RCNO-36 の保存済みチャネルにデータベースが送る）
--   photo_locked       {id, board_id, locked_by, lock_expires_at}  新しい人がつかんだとき
--   photo_unlocked     {id, board_id}                              離したとき
--   decoration_locked / decoration_unlocked も同じ形。
--   期限の延長だけでは送らない。期限切れでは何も送らないので、受け取った側は
--   lock_expires_at を過ぎたら空いたものとして扱う。
--   位置の保存は従来どおり photo_saved / decoration_saved で届く（つかみの列は写真・装飾の形に含めないので、
--   つかむ・離すだけでは saved は送らない）。
--   ruuuto_board_snapshot の photos / decorations にも locked_by, lock_expires_at を足す。
--
-- iOSの流れ（ドラッグ中の位置はサーバーで検査しない、推奨の形）
--   1. 指が触れたら grab。RC012 ならその写真は動かさず、DETAIL の人がつかんでいると表示する。
--   2. ドラッグ中は board:<id>:live に Broadcast "photo_dragging"（装飾は "decoration_dragging"）を
--      {id, user_id, x, y, rotation, scale} で10回/秒程度に間引いて送る。
--      受け取った側は、user_id が今つかんでいる人のときだけ表示に反映する。
--   3. 保存せずに長くドラッグするときは、4秒ごとに grab を呼んで期限を延ばす。
--   4. 指を離したら move(p_release: true)。戻り値（または photo_saved）の位置に表示を合わせる。
--      RC013 なら期限切れなので、snapshot か photo_saved の位置に戻す。

alter table public.photos
  add column locked_by uuid references public.profiles (id) on delete set null,
  add column lock_expires_at timestamptz;

alter table public.decorations
  add column locked_by uuid references public.profiles (id) on delete set null,
  add column lock_expires_at timestamptz;

-- つかみの期限（10秒）
create function private.ruuuto_lock_lease()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '10 seconds';
$$;

-- 戻り値・スナップショット用のつかみの状態（期限切れは null）
create function private.ruuuto_lock_json(p_locked_by uuid, p_lock_expires_at timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select case
    when p_locked_by is not null and p_lock_expires_at > now()
      then jsonb_build_object('locked_by', p_locked_by, 'lock_expires_at', private.ruuuto_ts(p_lock_expires_at))
    else jsonb_build_object('locked_by', null, 'lock_expires_at', null)
  end;
$$;

-- ほかの人がつかんでいる（RC012）。DETAIL に誰がいつまでつかんでいるかを JSON で入れる。
create function private.ruuuto_raise_locked(p_locked_by uuid, p_lock_expires_at timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ほかの人が動かしています'
    using errcode = 'RC012',
          detail = private.ruuuto_lock_json(p_locked_by, p_lock_expires_at)::text;
end;
$$;

-- 締切前のボードか（RC002）
create function private.ruuuto_require_open_board(p_board_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.boards b
    where b.id = p_board_id and b.status = 'open' and b.closes_at > now()
  ) then
    raise exception '締切を過ぎたため動かせません' using errcode = 'RC002';
  end if;
end;
$$;

-- 配置の値が有限で、scale が正か（RC008）
create function private.ruuuto_require_position(
  p_x double precision, p_y double precision, p_rotation double precision, p_scale double precision)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_x is null or p_y is null or p_rotation is null or p_scale is null
     or p_x in ('NaN', 'Infinity', '-Infinity')
     or p_y in ('NaN', 'Infinity', '-Infinity')
     or p_rotation in ('NaN', 'Infinity', '-Infinity')
     or p_scale in ('NaN', 'Infinity', '-Infinity')
     or p_scale <= 0 then
    raise exception '位置の指定が正しくありません' using errcode = 'RC008';
  end if;
end;
$$;

-- 操作する写真を行ロック付きで取り出す（同時につかんでも1人だけが勝つよう、ここで順番に並べる）
--   p_editing = true なら投稿済みで締切前であることも確かめる（grab と move）。
create function private.ruuuto_lock_photo_row(p_photo_id uuid, p_editing boolean)
returns public.photos
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype;
begin
  select * into v_photo from public.photos p where p.id = p_photo_id for update;
  if not found then
    raise exception 'この写真を動かす権限がありません' using errcode = '42501';
  end if;
  perform private.ruuuto_require_board_member(v_photo.board_id);

  if v_photo.status = 'pending' then
    if v_photo.posted_by <> v_user_id then
      raise exception 'この写真を動かす権限がありません' using errcode = '42501';
    end if;
    if p_editing then
      raise exception '投稿が終わっていない写真は動かせません' using errcode = 'RC008';
    end if;
  elsif v_photo.status = 'withdrawn' and p_editing then
    raise exception 'この写真は取り下げ済みです' using errcode = 'RC010';
  end if;

  if p_editing then
    perform private.ruuuto_require_open_board(v_photo.board_id);
  end if;
  return v_photo;
end;
$$;

-- 操作する装飾を行ロック付きで取り出す。ペンは動かせない（RC008）。
create function private.ruuuto_lock_decoration_row(p_decoration_id uuid, p_editing boolean)
returns public.decorations
language plpgsql
set search_path = ''
as $$
declare
  v_decoration public.decorations%rowtype;
begin
  perform private.ruuuto_require_user();
  select * into v_decoration from public.decorations d where d.id = p_decoration_id for update;
  if not found then
    raise exception 'この装飾を動かす権限がありません' using errcode = '42501';
  end if;
  perform private.ruuuto_require_board_member(v_decoration.board_id);

  if p_editing then
    if v_decoration.kind = 'pen' then
      raise exception 'ペンの装飾は動かせません' using errcode = 'RC008';
    end if;
    perform private.ruuuto_require_open_board(v_decoration.board_id);
  end if;
  return v_decoration;
end;
$$;

-- 写真: つかむ
create function public.ruuuto_grab_photo(p_photo_id uuid)
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
  if v_held and v_photo.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_photo.locked_by, v_photo.lock_expires_at);
  end if;

  -- 新しくつかんだときだけ一番上に出す（延長のたびに重なり順が入れ替わらないようにする）
  if not (v_held and v_photo.locked_by = v_user_id) then
    perform pg_advisory_xact_lock(hashtextextended('ruuuto_z:' || v_photo.board_id, 0));
    if exists (
      select 1 from public.photos p
      where p.board_id = v_photo.board_id and p.status = 'posted'
        and p.id <> v_photo.id and p.z_index >= v_photo.z_index
    ) then
      select max(p.z_index) + 1 into v_z
      from public.photos p where p.board_id = v_photo.board_id and p.status = 'posted';
    end if;
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

-- 写真: 位置を保存する（つかんでいる人だけ）。p_release = true なら同時に離す。
create function public.ruuuto_move_photo(
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

-- 写真: 離す（自分がつかんでいなければ何もしない。締切後も可）
create function public.ruuuto_release_photo(p_photo_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_photo public.photos%rowtype := private.ruuuto_lock_photo_row(p_photo_id, false);
begin
  if v_photo.locked_by = v_user_id then
    update public.photos p
       set locked_by = null, lock_expires_at = null
     where p.id = v_photo.id
    returning * into v_photo;
  end if;

  return (private.ruuuto_photo_json(v_photo)::jsonb
          || private.ruuuto_lock_json(v_photo.locked_by, v_photo.lock_expires_at))::json;
end;
$$;

-- 装飾: つかむ
create function public.ruuuto_grab_decoration(p_decoration_id uuid)
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
  if v_held and v_decoration.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_decoration.locked_by, v_decoration.lock_expires_at);
  end if;

  if not (v_held and v_decoration.locked_by = v_user_id) then
    perform pg_advisory_xact_lock(hashtextextended('ruuuto_dz:' || v_decoration.board_id, 0));
    if exists (
      select 1 from public.decorations d
      where d.board_id = v_decoration.board_id
        and d.id <> v_decoration.id and d.z_index >= v_decoration.z_index
    ) then
      select max(d.z_index) + 1 into v_z
      from public.decorations d where d.board_id = v_decoration.board_id;
    end if;
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

-- 装飾: 位置を保存する（つかんでいる人だけ）
create function public.ruuuto_move_decoration(
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

-- 装飾: 離す
create function public.ruuuto_release_decoration(p_decoration_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_decoration public.decorations%rowtype := private.ruuuto_lock_decoration_row(p_decoration_id, false);
begin
  if v_decoration.locked_by = v_user_id then
    update public.decorations d
       set locked_by = null, lock_expires_at = null
     where d.id = v_decoration.id
    returning * into v_decoration;
  end if;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- つかむ・離すを配信する（写真と装飾で共通。TG_ARGV[0] は 'photo' か 'decoration'）
--   locked:   つかんでいる人が変わった、または期限切れから同じ人がつかみ直した
--   unlocked: つかみが外れた
--   期限の延長だけ（同じ人で、前の期限が切れていない）は送らない。
create function private.ruuuto_broadcast_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text := tg_argv[0];
  v_topic text := 'board:' || new.board_id;
begin
  -- 写真は投稿済みのときだけ（装飾には status がないので、行を JSON にして読む）
  if v_kind = 'photo' and to_jsonb(new) ->> 'status' <> 'posted' then
    return null;
  end if;

  if new.locked_by is not null
     and (old.locked_by is distinct from new.locked_by
          or old.lock_expires_at is null or old.lock_expires_at <= now()) then
    perform realtime.send(
      jsonb_build_object('id', new.id, 'board_id', new.board_id,
                         'locked_by', new.locked_by,
                         'lock_expires_at', private.ruuuto_ts(new.lock_expires_at)),
      v_kind || '_locked', v_topic, true);
  elsif new.locked_by is null and old.locked_by is not null then
    perform realtime.send(
      jsonb_build_object('id', new.id, 'board_id', new.board_id),
      v_kind || '_unlocked', v_topic, true);
  end if;
  return null;
end;
$$;

-- photos_broadcast（photo_saved）より後に動くよう、名前の順で後ろにする
create trigger photos_lock_broadcast
  after update of locked_by, lock_expires_at on public.photos
  for each row execute function private.ruuuto_broadcast_lock('photo');

create trigger decorations_lock_broadcast
  after update of locked_by, lock_expires_at on public.decorations
  for each row execute function private.ruuuto_broadcast_lock('decoration');

-- 再接続・初回表示用のスナップショットに、つかみの状態を足す
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
               order by p.z_index, p.posted_at, p.id)
      from public.photos p
      where p.board_id = p_board_id and p.status = 'posted'), '[]'::json),
    'decorations', coalesce((
      select json_agg(
               private.ruuuto_decoration_json(d) || private.ruuuto_lock_json(d.locked_by, d.lock_expires_at)
               order by d.z_index, d.created_at, d.id)
      from public.decorations d
      where d.board_id = p_board_id), '[]'::json));
end;
$$;

revoke execute on function private.ruuuto_lock_lease() from public, anon, authenticated;
revoke execute on function private.ruuuto_lock_json(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function private.ruuuto_raise_locked(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_open_board(uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_position(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;
revoke execute on function private.ruuuto_lock_photo_row(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.ruuuto_lock_decoration_row(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.ruuuto_broadcast_lock() from public, anon, authenticated;

revoke execute on function public.ruuuto_grab_photo(uuid) from public, anon;
revoke execute on function public.ruuuto_move_photo(uuid, double precision, double precision, double precision, double precision, boolean) from public, anon;
revoke execute on function public.ruuuto_release_photo(uuid) from public, anon;
revoke execute on function public.ruuuto_grab_decoration(uuid) from public, anon;
revoke execute on function public.ruuuto_move_decoration(uuid, double precision, double precision, double precision, double precision, boolean) from public, anon;
revoke execute on function public.ruuuto_release_decoration(uuid) from public, anon;
grant execute on function public.ruuuto_grab_photo(uuid) to authenticated;
grant execute on function public.ruuuto_move_photo(uuid, double precision, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.ruuuto_release_photo(uuid) to authenticated;
grant execute on function public.ruuuto_grab_decoration(uuid) to authenticated;
grant execute on function public.ruuuto_move_decoration(uuid, double precision, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.ruuuto_release_decoration(uuid) to authenticated;
