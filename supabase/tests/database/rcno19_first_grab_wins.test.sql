-- RCNO-19 同じ写真を同時に動かしたときの結果をそろえる（先につかんだ人が勝つ）
-- 定量目標: 先につかんだ人だけが動かせ、ほかの人は RC012 で誰がつかんでいるかを受け取る。
-- 離すか期限が切れたら、ほかの人がつかめる。保存した位置と revision が戻り値・配信・スナップショットでそろう。
-- つかむ・離すは locked / unlocked で配信し、期限の延長だけでは配信しない。
begin;
select plan(55);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000019a1', 'grab-a@example.com'),
  ('00000000-0000-0000-0000-0000000019b1', 'grab-b@example.com'),
  ('00000000-0000-0000-0000-0000000019c1', 'grab-c@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('19000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000019a1', gen_random_uuid()),
  ('19000000-0000-0000-0000-000000000002', 'べつの班', '00000000-0000-0000-0000-0000000019c1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('19000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000019a1', 'owner'),
  ('19000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000019b1', 'member'),
  ('19000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000019c1', 'owner');
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('19100000-0000-0000-0000-000000000001', '19000000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('19100000-0000-0000-0000-000000000002', '19000000-0000-0000-0000-000000000001', '先週',
   now() - interval '14 days', now() - interval '7 days', 'closed', now() - interval '7 days');

-- P1: Aの写真（下）、P2: Bの写真（上）、P3: 取り下げ済み、P4: Bの投稿途中、P5: 締切後のボード
insert into public.photos (id, board_id, posted_by, storage_path, status, z_index, posted_at, withdrawn_at) values
  ('19200000-0000-0000-0000-000000000001', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019a1', 'g/b/19200000-0000-0000-0000-000000000001', 'posted', 1, now(), null),
  ('19200000-0000-0000-0000-000000000002', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019b1', 'g/b/19200000-0000-0000-0000-000000000002', 'posted', 2, now(), null),
  ('19200000-0000-0000-0000-000000000003', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019a1', 'g/b/19200000-0000-0000-0000-000000000003', 'withdrawn', 0, now(), now()),
  ('19200000-0000-0000-0000-000000000004', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019b1', 'g/b/19200000-0000-0000-0000-000000000004', 'pending', 0, null, null),
  ('19200000-0000-0000-0000-000000000005', '19100000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000019a1', 'g/b/19200000-0000-0000-0000-000000000005', 'posted', 1, now(), null);

-- D1: 文字（下）、D2: スタンプ（上）、D3: ペン、D4: 締切後のボードの文字
insert into public.decorations (id, board_id, created_by, kind, content, z_index) values
  ('19300000-0000-0000-0000-000000000001', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019a1', 'text', '{"text": "hello"}', 1),
  ('19300000-0000-0000-0000-000000000002', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019b1', 'stamp', '{"stamp": "star"}', 2),
  ('19300000-0000-0000-0000-000000000003', '19100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019a1', 'pen', '{"points": []}', 0),
  ('19300000-0000-0000-0000-000000000004', '19100000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000019a1', 'text', '{"text": "old"}', 1);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- エラーのコードと DETAIL を取り出す
create function pg_temp.err(p_sql text) returns jsonb language plpgsql as $$
declare
  v_state text;
  v_detail text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return jsonb_build_object('code', v_state, 'detail', nullif(v_detail, ''));
end;
$$;

-- 配信されたメッセージ（postgres で数える）
create function pg_temp.sent(p_event text, p_id uuid) returns setof realtime.messages
language sql security definer as $$
  select * from realtime.messages m
  where m.event = p_event and m.extension = 'broadcast' and m.payload ->> 'id' = p_id::text
  order by m.inserted_at, m.id;
$$;

-- 期限の期待値（10秒後、UTCの秒単位）
create function pg_temp.lease() returns text
language sql security definer as $$
  select private.ruuuto_ts(now() + interval '10 seconds');
$$;

create function pg_temp.photo(p_id uuid) returns public.photos
language sql security definer as $$
  select * from public.photos where id = p_id;
$$;

set local role authenticated;

-- 写真: Aがつかむ
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
create temp table g1 as select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000001')::jsonb as r;
select is((select r ->> 'locked_by' from g1), '00000000-0000-0000-0000-0000000019a1', 'つかむと locked_by が自分になる');
select is((select r ->> 'lock_expires_at' from g1), pg_temp.lease(), '期限は10秒後');
select is((select (r ->> 'z_index')::int from g1), 3, '下にあった写真は一番上に出る（最大 + 1）');
select is((select (r ->> 'revision')::int from g1), 2, '重なり順が変わったので revision が1増える');
select is((select r ->> 'status' from g1), 'posted', '戻り値は写真の形');

-- つかみ直し（延長）
select is((public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000001')::jsonb ->> 'z_index')::int, 3,
  'つかみ直しても重なり順は変わらない');

-- Bは動かせない
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
create temp table e1 as select pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000001') $$) as e;
select is((select e ->> 'code' from e1), 'RC012', 'ほかの人がつかんでいると RC012');
select is((select (e ->> 'detail')::jsonb ->> 'locked_by' from e1), '00000000-0000-0000-0000-0000000019a1',
  'DETAIL の locked_by でつかんでいる人がわかる');
select is((select (e ->> 'detail')::jsonb ->> 'lock_expires_at' from e1), pg_temp.lease(),
  'DETAIL の lock_expires_at でいつ空くかわかる');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 1, 1, 0, 1) $$) ->> 'code',
  'RC012', 'つかんでいない人の移動は RC012');
select is(public.ruuuto_release_photo('19200000-0000-0000-0000-000000000001')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000019a1', 'つかんでいない人が離してもエラーにならず、つかみは残る');

-- Aが動かす
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
create temp table m1 as select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 10.5, -20, 15, 1.5)::jsonb as r;
select is((select (r ->> 'revision')::int from m1), 3, '移動すると revision が1増える');
select is((select jsonb_build_object('x', r -> 'x', 'y', r -> 'y', 'rotation', r -> 'rotation', 'scale', r -> 'scale') from m1),
  '{"x": 10.5, "y": -20, "rotation": 15, "scale": 1.5}'::jsonb, '保存した位置が返る');
select is((select r ->> 'locked_by' from m1), '00000000-0000-0000-0000-0000000019a1', 'p_release なしならつかんだまま');
select is((select (x, y, revision, updated_by)::text from pg_temp.photo('19200000-0000-0000-0000-000000000001')),
  '(10.5,-20,3,00000000-0000-0000-0000-0000000019a1)', '位置・revision・更新者が保存される');

-- 離すと、ほかの人がつかめる
select is(public.ruuuto_release_photo('19200000-0000-0000-0000-000000000001')::jsonb -> 'locked_by', 'null'::jsonb,
  '離すと locked_by が null になる');
select is(public.ruuuto_release_photo('19200000-0000-0000-0000-000000000001')::jsonb -> 'locked_by', 'null'::jsonb,
  'もう一度離してもエラーにならない');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
create temp table g2 as select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000001')::jsonb as r;
select is((select r ->> 'locked_by' from g2), '00000000-0000-0000-0000-0000000019b1', '離したあとは、ほかの人がつかめる');
select is((select (r ->> 'revision')::int from g2), 3, 'すでに一番上なら重なり順も revision も変わらない');

-- 期限切れ
reset role;
update public.photos set lock_expires_at = now() - interval '1 second' where id = '19200000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 1, 1, 0, 1) $$) ->> 'code',
  'RC013', '期限が切れたあとの移動は RC013');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
select is(public.ruuuto_release_photo('19200000-0000-0000-0000-000000000001')::jsonb -> 'lock_expires_at', 'null'::jsonb,
  '期限切れのつかみは null で返す');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
select is(public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000001')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000019a1', '期限が切れたつかみは、ほかの人がつかめる');

-- 保存と同時に離す
create temp table m2 as select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 200, 300, -5, 0.8, true)::jsonb as r;
select is((select jsonb_build_object('x', r -> 'x', 'revision', r -> 'revision', 'locked_by', r -> 'locked_by') from m2),
  '{"x": 200, "revision": 4, "locked_by": null}'::jsonb, 'p_release = true なら保存して離す');
select is((select (x, y, revision, locked_by is null)::text from pg_temp.photo('19200000-0000-0000-0000-000000000001')),
  '(200,300,4,t)', '読み直しても同じ位置で、誰もつかんでいない');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 1, 1, 0, 1) $$) ->> 'code',
  'RC013', 'つかまずに動かすと RC013');

-- 入力の検査
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 1, 1, 0, 0) $$) ->> 'code',
  'RC008', 'scale が0なら RC008');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 'NaN', 1, 0, 1) $$) ->> 'code',
  'RC008', 'NaN は RC008');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', 1, 1, 'Infinity', 1) $$) ->> 'code',
  'RC008', '無限大は RC008');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000001', null, 1, 0, 1) $$) ->> 'code',
  'RC008', 'null は RC008');

-- 締切・取り下げ・投稿途中
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000005') $$) ->> 'code',
  'RC002', '締切後のボードの写真はつかめない');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19200000-0000-0000-0000-000000000005', 1, 1, 0, 1) $$) ->> 'code',
  'RC002', '締切後のボードの写真は動かせない');
select is(pg_temp.err($$ select public.ruuuto_release_photo('19200000-0000-0000-0000-000000000005') $$), null,
  '締切後でも離すことはできる');
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000003') $$) ->> 'code',
  'RC010', '取り下げ済みの写真は RC010');
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000004') $$) ->> 'code',
  '42501', 'ほかの人の投稿途中の写真は、ないものとして 42501');
select is(pg_temp.err($$ select public.ruuuto_grab_photo(gen_random_uuid()) $$) ->> 'code',
  '42501', 'ない写真は 42501');

-- 所属していない・未ログイン
select pg_temp.act_as('00000000-0000-0000-0000-0000000019c1');
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000002') $$) ->> 'code',
  '42501', '別グループの参加者はつかめない');
select is(pg_temp.err($$ select public.ruuuto_release_photo('19200000-0000-0000-0000-000000000002') $$) ->> 'code',
  '42501', '別グループの参加者は離す操作もできない');
reset role;
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000002') $$) ->> 'code',
  '42501', '未ログインはつかめない');
reset role;

-- 配信
select is((select count(*) from pg_temp.sent('photo_locked', '19200000-0000-0000-0000-000000000001')), 3::bigint,
  '新しくつかんだ3回だけ photo_locked を送り、延長では送らない');
select is((select payload from pg_temp.sent('photo_locked', '19200000-0000-0000-0000-000000000001') limit 1),
  jsonb_build_object('id', '19200000-0000-0000-0000-000000000001', 'board_id', '19100000-0000-0000-0000-000000000001',
    'locked_by', '00000000-0000-0000-0000-0000000019a1', 'lock_expires_at', pg_temp.lease()),
  'photo_locked は {id, board_id, locked_by, lock_expires_at}');
select is((select count(*) from pg_temp.sent('photo_unlocked', '19200000-0000-0000-0000-000000000001')), 2::bigint,
  '離した2回だけ photo_unlocked を送る（つかんでいない人の release では送らない）');
select is((select payload from pg_temp.sent('photo_unlocked', '19200000-0000-0000-0000-000000000001') limit 1),
  '{"id": "19200000-0000-0000-0000-000000000001", "board_id": "19100000-0000-0000-0000-000000000001"}'::jsonb,
  'photo_unlocked は {id, board_id}');
select is((select array_agg((payload ->> 'revision')::int) from pg_temp.sent('photo_saved', '19200000-0000-0000-0000-000000000001')),
  array[1, 2, 3, 4], 'photo_saved は用意した1件のあと、重なり順と位置の保存だけ（つかむ・離すだけでは送らない）');
select is((select topic from pg_temp.sent('photo_locked', '19200000-0000-0000-0000-000000000001') limit 1),
  'board:19100000-0000-0000-0000-000000000001', 'つかみはボードの保存済みのチャネルに配信する');

-- スナップショットにつかみの状態が入る
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
select public.ruuuto_grab_photo('19200000-0000-0000-0000-000000000002');
create temp table snap as select public.ruuuto_board_snapshot('19100000-0000-0000-0000-000000000001')::jsonb as s;
select is(
  (select jsonb_object_agg(e ->> 'id', jsonb_build_object('locked_by', e -> 'locked_by', 'x', e -> 'x'))
     from snap, jsonb_array_elements(s -> 'photos') e),
  jsonb_build_object(
    '19200000-0000-0000-0000-000000000001', jsonb_build_object('locked_by', null, 'x', 200),
    '19200000-0000-0000-0000-000000000002', jsonb_build_object('locked_by', '00000000-0000-0000-0000-0000000019b1', 'x', 0)),
  'スナップショットは保存済みの位置と、誰がつかんでいるかを返す');

-- 装飾
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
create temp table dg as select public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000001')::jsonb as r;
select is((select jsonb_build_object('locked_by', r -> 'locked_by', 'z_index', r -> 'z_index', 'kind', r -> 'kind') from dg),
  '{"locked_by": "00000000-0000-0000-0000-0000000019a1", "z_index": 3, "kind": "text"}'::jsonb,
  '装飾もつかむと自分のものになり、一番上に出る');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
create temp table de as select pg_temp.err($$ select public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000001') $$) as e;
select is((select jsonb_build_object('code', e -> 'code', 'locked_by', (e ->> 'detail')::jsonb -> 'locked_by') from de),
  '{"code": "RC012", "locked_by": "00000000-0000-0000-0000-0000000019a1"}'::jsonb, 'ほかの人がつかんだ装飾は RC012');
select is(pg_temp.err($$ select public.ruuuto_move_decoration('19300000-0000-0000-0000-000000000002', 1, 1, 0, 1) $$) ->> 'code',
  'RC013', 'つかまずに装飾を動かすと RC013');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019a1');
create temp table dm as select public.ruuuto_move_decoration('19300000-0000-0000-0000-000000000001', 5, 6, 0, 2)::jsonb as r;
select is((select jsonb_build_object('x', r -> 'x', 'revision', r -> 'revision', 'updated_by', r -> 'updated_by') from dm),
  '{"x": 5, "revision": 3, "updated_by": "00000000-0000-0000-0000-0000000019a1"}'::jsonb, '装飾の位置を保存し revision が増える');
select is(public.ruuuto_move_decoration('19300000-0000-0000-0000-000000000001', 7, 8, 0, 2, true)::jsonb -> 'locked_by',
  'null'::jsonb, '装飾も保存と同時に離せる');
select is(pg_temp.err($$ select public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000003') $$) ->> 'code',
  'RC008', 'ペンの装飾は RC008');
select is(pg_temp.err($$ select public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000004') $$) ->> 'code',
  'RC002', '締切後のボードの装飾は RC002');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019b1');
select is(public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000001')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000019b1', '離した装飾はほかの人がつかめる');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019c1');
select is(pg_temp.err($$ select public.ruuuto_grab_decoration('19300000-0000-0000-0000-000000000001') $$) ->> 'code',
  '42501', '別グループの参加者は装飾をつかめない');
reset role;
select is(
  (select jsonb_build_array(
     (select count(*) from pg_temp.sent('decoration_locked', '19300000-0000-0000-0000-000000000001')),
     (select count(*) from pg_temp.sent('decoration_unlocked', '19300000-0000-0000-0000-000000000001')),
     (select count(*) from pg_temp.sent('decoration_saved', '19300000-0000-0000-0000-000000000001')))),
  '[2, 1, 4]'::jsonb, '装飾も locked 2回・unlocked 1回・saved（追加、重なり順、移動2回）4回を配信する');

select * from finish();
rollback;
