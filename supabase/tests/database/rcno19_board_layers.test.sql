-- RCNO-19 写真と装飾を3つのレイヤーに分ける
-- 定量目標: 描く順番は layer → z_index。新しい写真は 1、装飾は 2。z_index はレイヤーごとに写真と装飾で共有し、
-- 最前面・最背面・レイヤーの変更で重ならない。背景（0）のものは grab / move が RC016。
-- ほかの人がつかんでいる間は RC012、締切後は RC002、所属していなければ 42501、指定の誤りは RC017。
-- つかんだら前に出すかは各自の設定（既定オフ）。オンの人がつかむと、そのレイヤーの中だけで一番手前に出る。
begin;
select plan(71);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000019d1', 'layer-a@example.com'),
  ('00000000-0000-0000-0000-0000000019e1', 'layer-b@example.com'),
  ('00000000-0000-0000-0000-0000000019f1', 'layer-c@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('19400000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000019d1', gen_random_uuid()),
  ('19400000-0000-0000-0000-000000000002', 'べつの班', '00000000-0000-0000-0000-0000000019f1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('19400000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000019d1', 'owner'),
  ('19400000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000019e1', 'member'),
  ('19400000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000019f1', 'owner');
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('19500000-0000-0000-0000-000000000001', '19400000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('19500000-0000-0000-0000-000000000002', '19400000-0000-0000-0000-000000000001', '先週',
   now() - interval '14 days', now() - interval '7 days', 'closed', now() - interval '7 days');

-- P1, P2: 投稿済み（z 1, 2）、P3: 取り下げ済み、P4: Bの投稿途中、P5: 締切後のボード
insert into public.photos (id, board_id, posted_by, storage_path, status, z_index, posted_at, withdrawn_at) values
  ('19600000-0000-0000-0000-000000000001', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019d1', 'g/b/19600000-0000-0000-0000-000000000001', 'posted', 1, now(), null),
  ('19600000-0000-0000-0000-000000000002', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019e1', 'g/b/19600000-0000-0000-0000-000000000002', 'posted', 2, now(), null),
  ('19600000-0000-0000-0000-000000000003', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019d1', 'g/b/19600000-0000-0000-0000-000000000003', 'withdrawn', 0, now(), now()),
  ('19600000-0000-0000-0000-000000000004', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019e1', 'g/b/19600000-0000-0000-0000-000000000004', 'pending', 0, null, null),
  ('19600000-0000-0000-0000-000000000005', '19500000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000019d1', 'g/b/19600000-0000-0000-0000-000000000005', 'posted', 1, now(), null);

-- D1: 文字（z 1）、D2: スタンプ（z 2）、D3: ペン（z 3）、D4: 締切後のボードの文字
insert into public.decorations (id, board_id, created_by, kind, content, z_index) values
  ('19700000-0000-0000-0000-000000000001', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019d1', 'text', '{"text": "hello"}', 1),
  ('19700000-0000-0000-0000-000000000002', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019e1', 'stamp', '{"stamp_id": "star"}', 2),
  ('19700000-0000-0000-0000-000000000003', '19500000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000019d1', 'pen', '{"strokes": []}', 3),
  ('19700000-0000-0000-0000-000000000004', '19500000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000019d1', 'text', '{"text": "old"}', 1);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

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

-- 保存済みの (layer, z_index, revision)
create function pg_temp.pos(p_id uuid) returns text
language sql security definer as $$
  select coalesce(
    (select (layer, z_index, revision)::text from public.photos where id = p_id),
    (select (layer, z_index, revision)::text from public.decorations where id = p_id));
$$;

-- ボードの描く順番（snapshot の写真と装飾を layer → z_index で並べた id の短縮名）
create function pg_temp.draw_order(p_snap jsonb) returns text[]
language sql as $$
  select array_agg(e ->> 'name' order by (e ->> 'layer')::int, (e ->> 'z_index')::int)
  from (
    select x || jsonb_build_object('name', 'P' || right(x ->> 'id', 1)) as e
      from jsonb_array_elements(p_snap -> 'photos') x
    union all
    select x || jsonb_build_object('name', 'D' || right(x ->> 'id', 1))
      from jsonb_array_elements(p_snap -> 'decorations') x
  ) s;
$$;

create function pg_temp.sent(p_event text, p_id uuid) returns setof realtime.messages
language sql security definer as $$
  select * from realtime.messages m
  where m.event = p_event and m.extension = 'broadcast' and m.payload ->> 'id' = p_id::text
  order by m.inserted_at, m.id;
$$;

-- ===== 既定値と制約 =====
select is((select layer from public.photos where id = '19600000-0000-0000-0000-000000000001'), 1::smallint,
  '写真の既定のレイヤーは 1（写真）');
select is((select layer from public.decorations where id = '19700000-0000-0000-0000-000000000003'), 2::smallint,
  '装飾（ペンも）の既定のレイヤーは 2（装飾）');
select is((select auto_bring_to_front from public.profiles where id = '00000000-0000-0000-0000-0000000019d1'), false,
  'つかんだら前に出す設定の既定はオフ');
select throws_ok($$ update public.photos set layer = 3 where id = '19600000-0000-0000-0000-000000000001' $$,
  '23514', null, 'レイヤーは 0〜2 だけ');
select throws_ok($$ update public.decorations set layer = -1 where id = '19700000-0000-0000-0000-000000000001' $$,
  '23514', null, '装飾のレイヤーも 0〜2 だけ');

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');

-- ===== 形と描く順番 =====
create temp table s0 as select public.ruuuto_board_snapshot('19500000-0000-0000-0000-000000000001')::jsonb as s;
select is((select s -> 'photos' -> 0 -> 'layer' from s0), '1'::jsonb, 'snapshot の写真に layer が入る');
select is((select s -> 'decorations' -> 0 -> 'layer' from s0), '2'::jsonb, 'snapshot の装飾に layer が入る');
select is((select pg_temp.draw_order(s) from s0), array['P1', 'P2', 'D1', 'D2', 'D3'],
  '描く順番は写真レイヤー → 装飾レイヤー、それぞれ z_index の昇順');
select ok((select (s -> 'board') ? 'topic_texts' and not ((s -> 'board') ? 'auto_bring_to_front') from s0),
  'ボードの形は変えない（設定はボードに入れない）');

-- ===== 新しい装飾はレイヤー 2 の一番手前 =====
create temp table d5 as select public.ruuuto_add_decoration(
  '19700000-0000-0000-0000-000000000005', '19500000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "moon"}', 0, 0)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from d5),
  '{"layer": 2, "z_index": 4}'::jsonb, '新しい装飾はレイヤー 2 の一番手前（最大 + 1）');

-- ===== 新しい写真はレイヤー 1 の一番手前（装飾が写真レイヤーにあれば、それより手前） =====
select public.ruuuto_begin_photo('19600000-0000-0000-0000-000000000006', '19500000-0000-0000-0000-000000000001');
reset role;
insert into storage.objects (bucket_id, name)
  select 'photos', storage_path from public.photos where id = '19600000-0000-0000-0000-000000000006';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');

-- D1 を写真レイヤーへ: 移した先の一番手前（写真 z 2 の上）
create temp table l1 as select public.ruuuto_set_item_layer(
  'decoration', '19700000-0000-0000-0000-000000000001', 1::smallint)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index', 'revision', r -> 'revision',
                                     'kind', r -> 'kind', 'locked_by', r -> 'locked_by') from l1),
  '{"layer": 1, "z_index": 3, "revision": 2, "kind": "text", "locked_by": null}'::jsonb,
  'レイヤーを変えると、移した先の一番手前に置かれ revision が1増える（戻り値は装飾の形 + つかみ）');
select is((select r ->> 'updated_by' from l1), '00000000-0000-0000-0000-0000000019d1', '更新者は変えた人');

create temp table f6 as select public.ruuuto_finish_photo('19600000-0000-0000-0000-000000000006')::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from f6),
  '{"layer": 1, "z_index": 4}'::jsonb, '投稿を確定した写真はレイヤー 1 の一番手前（写真レイヤーの装飾より手前）');

-- ===== 同じレイヤーで写真と装飾をまたいで最前面・最背面 =====
create temp table r1 as select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000001', 'front')::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index', 'revision', r -> 'revision') from r1),
  '{"layer": 1, "z_index": 5, "revision": 2}'::jsonb, '最前面へ: 同じレイヤーの写真・装飾より手前に出て revision + 1');
select is((public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000001', 'front')::jsonb ->> 'revision')::int, 2,
  'すでに最前面なら何も変えない（revision も同じ）');
create temp table r2 as select public.ruuuto_reorder_item('decoration', '19700000-0000-0000-0000-000000000001', 'back')::jsonb as r;
select is((select jsonb_build_object('z_index', r -> 'z_index', 'revision', r -> 'revision') from r2),
  '{"z_index": 1, "revision": 3}'::jsonb, '最背面へ: 同じレイヤーの写真より奥（最小 - 1）');
select is((public.ruuuto_reorder_item('decoration', '19700000-0000-0000-0000-000000000001', 'back')::jsonb ->> 'revision')::int, 3,
  'すでに最背面なら何も変えない');
create temp table r3 as select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000002', 'back')::jsonb as r;
select is((select (r ->> 'z_index')::int from r3), 0, '最背面へ送ると z_index は 0 以下にもなる');
select is(pg_temp.draw_order(public.ruuuto_board_snapshot('19500000-0000-0000-0000-000000000001')::jsonb),
  array['P2', 'D1', 'P6', 'P1', 'D2', 'D3', 'D5'], '写真レイヤーの中で写真と装飾が混ざって並ぶ');
select is((select (s -> 'decorations' -> 0 ->> 'id') from (select public.ruuuto_board_snapshot('19500000-0000-0000-0000-000000000001')::jsonb as s) x),
  '19700000-0000-0000-0000-000000000001', 'snapshot の装飾も layer → z_index の順');

-- ===== 背景レイヤー =====
create temp table bg as select public.ruuuto_set_item_layer(
  'decoration', '19700000-0000-0000-0000-000000000003', 0::smallint)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from bg),
  '{"layer": 0, "z_index": 1}'::jsonb, 'ペンも背景へ移せる（空のレイヤーなら z_index = 1）');
create temp table bg2 as select public.ruuuto_set_item_layer(
  'photo', '19600000-0000-0000-0000-000000000002', 0::smallint)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from bg2),
  '{"layer": 0, "z_index": 2}'::jsonb, '写真を背景へ移すと背景の一番手前');
select is(pg_temp.draw_order(public.ruuuto_board_snapshot('19500000-0000-0000-0000-000000000001')::jsonb),
  array['D3', 'P2', 'D1', 'P6', 'P1', 'D2', 'D5'], '背景のものは一番奥に描く');

select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
select is(pg_temp.err($$ select public.ruuuto_grab_photo('19600000-0000-0000-0000-000000000002') $$) ->> 'code',
  'RC016', '背景の写真はつかめない（RC016）');
select is(pg_temp.err($$ select public.ruuuto_move_photo('19600000-0000-0000-0000-000000000002', 1, 1, 0, 1) $$) ->> 'code',
  'RC016', '背景の写真は動かせない（RC016）');
select is(public.ruuuto_release_photo('19600000-0000-0000-0000-000000000002')::jsonb -> 'locked_by', 'null'::jsonb,
  '背景のものでも離す操作はエラーにならない');
select public.ruuuto_set_item_layer('decoration', '19700000-0000-0000-0000-000000000002', 0::smallint);
select is(pg_temp.err($$ select public.ruuuto_grab_decoration('19700000-0000-0000-0000-000000000002') $$) ->> 'code',
  'RC016', '背景の装飾もつかめない（RC016）');
select is(pg_temp.err($$ select public.ruuuto_move_decoration('19700000-0000-0000-0000-000000000002', 1, 1, 0, 1) $$) ->> 'code',
  'RC016', '背景の装飾も動かせない（RC016）');

-- 別の人が背景から出せば動かせる
create temp table out1 as select public.ruuuto_set_item_layer(
  'photo', '19600000-0000-0000-0000-000000000002', 1::smallint)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from out1),
  '{"layer": 1, "z_index": 6}'::jsonb, '背景から写真レイヤーへ出すと、その一番手前');
select is(public.ruuuto_grab_photo('19600000-0000-0000-0000-000000000002')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000019e1', '背景から出した写真はつかめる');

-- ===== ほかの人のつかみ =====
select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');
create temp table lk as select pg_temp.err($$
  select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000002', 2::smallint) $$) as e;
select is((select jsonb_build_object('code', e -> 'code', 'locked_by', (e ->> 'detail')::jsonb -> 'locked_by') from lk),
  '{"code": "RC012", "locked_by": "00000000-0000-0000-0000-0000000019e1"}'::jsonb,
  'ほかの人がつかんでいる間はレイヤーを変えられない（RC012、DETAIL は grab と同じ）');
select ok((select (e ->> 'detail')::jsonb ? 'lock_expires_at' from lk), 'DETAIL に lock_expires_at も入る');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000002', 'back') $$) ->> 'code',
  'RC012', 'ほかの人がつかんでいる間は並べ替えられない（RC012）');
select is(pg_temp.pos('19600000-0000-0000-0000-000000000002'), '(1,6,4)', '断られた操作では何も変わらない');

-- つかんでいる本人は並べ替えられる。背景へ移すと、つかみが外れる
select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
select is((public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000002', 'back')::jsonb ->> 'locked_by'),
  '00000000-0000-0000-0000-0000000019e1', 'つかんでいる本人は並べ替えられ、つかんだまま');
create temp table own_bg as select public.ruuuto_set_item_layer(
  'photo', '19600000-0000-0000-0000-000000000002', 0::smallint)::jsonb as r;
select is((select jsonb_build_object('layer', r -> 'layer', 'locked_by', r -> 'locked_by') from own_bg),
  '{"layer": 0, "locked_by": null}'::jsonb, '自分がつかんでいるものを背景へ移すと、つかみが外れる');

-- 期限切れのつかみは邪魔しない
select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000002', 1::smallint);
select public.ruuuto_grab_photo('19600000-0000-0000-0000-000000000002');
reset role;
update public.photos set lock_expires_at = now() - interval '1 second' where id = '19600000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');
select is((public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000002', 'back')::jsonb ->> 'layer')::int, 1,
  '期限切れのつかみなら、ほかの人も並べ替えられる');

-- ===== 締切後・状態・所属・入力 =====
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000005', 0::smallint) $$) ->> 'code',
  'RC002', '締切後のボードの写真はレイヤーを変えられない（RC002）');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000005', 'front') $$) ->> 'code',
  'RC002', '締切後のボードの写真は並べ替えられない（RC002）');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('decoration', '19700000-0000-0000-0000-000000000004', 0::smallint) $$) ->> 'code',
  'RC002', '締切後のボードの装飾もレイヤーを変えられない（RC002）');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('decoration', '19700000-0000-0000-0000-000000000004', 'back') $$) ->> 'code',
  'RC002', '締切後のボードの装飾も並べ替えられない（RC002）');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000003', 'front') $$) ->> 'code',
  'RC010', '取り下げ済みの写真は RC010');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000004', 'front') $$) ->> 'code',
  '42501', 'ほかの人の投稿途中の写真は、ないものとして 42501');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000004', 0::smallint) $$) ->> 'code',
  'RC008', '自分の投稿途中の写真は RC008');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', gen_random_uuid(), 0::smallint) $$) ->> 'code',
  '42501', 'ない写真は 42501');

select is(pg_temp.err($$ select public.ruuuto_set_item_layer('sticker', '19600000-0000-0000-0000-000000000001', 0::smallint) $$) ->> 'code',
  'RC017', '種類の誤りは RC017');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000001', 3::smallint) $$) ->> 'code',
  'RC017', 'レイヤーの誤りは RC017');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000001', null) $$) ->> 'code',
  'RC017', 'レイヤーが null なら RC017');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000001', 'top') $$) ->> 'code',
  'RC017', '並べ替えの位置の誤りは RC017');
select is(pg_temp.err($$ select public.ruuuto_reorder_item(null, '19600000-0000-0000-0000-000000000001', 'front') $$) ->> 'code',
  'RC017', '種類が null なら RC017');

select pg_temp.act_as('00000000-0000-0000-0000-0000000019f1');
select is(pg_temp.err($$ select public.ruuuto_set_item_layer('photo', '19600000-0000-0000-0000-000000000001', 0::smallint) $$) ->> 'code',
  '42501', '別グループの参加者はレイヤーを変えられない');
select is(pg_temp.err($$ select public.ruuuto_reorder_item('decoration', '19700000-0000-0000-0000-000000000001', 'front') $$) ->> 'code',
  '42501', '別グループの参加者は並べ替えられない');
reset role;
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select is(pg_temp.err($$ select public.ruuuto_reorder_item('photo', '19600000-0000-0000-0000-000000000001', 'front') $$) ->> 'code',
  '42501', '未ログインは並べ替えられない');
select is(pg_temp.err($$ select public.ruuuto_set_my_preferences(true) $$) ->> 'code',
  '42501', '未ログインは設定を変えられない');
reset role;

-- ===== つかんだら前に出す（各自の設定） =====
-- B（オフ）が写真レイヤーの一番奥寄りの D1 をつかんでも並びは変わらない
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
create temp table before_b as select pg_temp.pos('19700000-0000-0000-0000-000000000001') as p;
select public.ruuuto_grab_decoration('19700000-0000-0000-0000-000000000001');
select is(pg_temp.pos('19700000-0000-0000-0000-000000000001'), (select p from before_b),
  '設定がオフの人がつかんでも z_index と revision は変わらない');
select public.ruuuto_release_decoration('19700000-0000-0000-0000-000000000001');

select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');
select is(public.ruuuto_set_my_preferences(true)::jsonb, '{"auto_bring_to_front": true}'::jsonb,
  '自分の設定をオンにできる');
select is(public.ruuuto_set_my_preferences(null)::jsonb, '{"auto_bring_to_front": true}'::jsonb,
  'null なら今の値のまま');
select is(public.ruuuto_my_profile()::jsonb -> 'auto_bring_to_front', 'true'::jsonb,
  'ruuuto_my_profile に自分の設定が入る');
select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
select is(public.ruuuto_my_profile()::jsonb -> 'auto_bring_to_front', 'false'::jsonb,
  'ほかの人の設定には影響しない');

select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');
create temp table ga as select public.ruuuto_grab_decoration('19700000-0000-0000-0000-000000000001')::jsonb as r;
create temp table snap_a as select public.ruuuto_board_snapshot('19500000-0000-0000-0000-000000000001')::jsonb as s;
select is((select jsonb_build_object('layer', r -> 'layer', 'z_index', r -> 'z_index') from ga),
  jsonb_build_object('layer', 1, 'z_index',
    (select max((e ->> 'z_index')::int) from snap_a,
       lateral (select x from jsonb_array_elements(s -> 'photos') x
                union all select x from jsonb_array_elements(s -> 'decorations') x) t(e)
     where (e ->> 'layer')::int = 1)),
  '設定がオンの人がつかむと、そのレイヤーの一番手前に出る');
select is((select (r ->> 'revision')::int from ga) - (select split_part(trim(both '()' from p), ',', 3)::int from before_b), 1,
  '前に出たら revision が1増える');
select is((select pg_temp.draw_order(s) from snap_a), array['D3', 'D2', 'P2', 'P6', 'P1', 'D1', 'D5'],
  '写真レイヤーの一番手前に並び、上のレイヤー（装飾の D5）より前には出ない');

-- 延長の grab では動かない
select is((public.ruuuto_grab_decoration('19700000-0000-0000-0000-000000000001')::jsonb ->> 'z_index'),
  (select r ->> 'z_index' from ga), '延長の grab では重なり順を変えない');
select public.ruuuto_release_decoration('19700000-0000-0000-0000-000000000001');

-- B（オフ）がつかんでも並びは変わらない（同じボードでも、つかんだ人の設定で決まる）
select pg_temp.act_as('00000000-0000-0000-0000-0000000019e1');
create temp table before_b2 as select pg_temp.pos('19600000-0000-0000-0000-000000000006') as p;
select public.ruuuto_grab_photo('19600000-0000-0000-0000-000000000006');
select is(pg_temp.pos('19600000-0000-0000-0000-000000000006'), (select p from before_b2),
  'オンの人がいても、オフの人のつかみでは並びは変わらない');
select public.ruuuto_release_photo('19600000-0000-0000-0000-000000000006');

select pg_temp.act_as('00000000-0000-0000-0000-0000000019d1');
select is(public.ruuuto_set_my_preferences(false)::jsonb, '{"auto_bring_to_front": false}'::jsonb,
  '設定をオフに戻せる');
reset role;

-- ===== 配信 =====
select is(
  (select array_agg(jsonb_build_object('layer', payload -> 'layer', 'z_index', payload -> 'z_index') order by inserted_at, id)
     from pg_temp.sent('decoration_saved', '19700000-0000-0000-0000-000000000003')),
  array['{"layer": 2, "z_index": 3}'::jsonb, '{"layer": 0, "z_index": 1}'::jsonb],
  'レイヤーの変更は decoration_saved で layer と z_index が届く');
select ok((select bool_and(payload ? 'layer') from pg_temp.sent('photo_saved', '19600000-0000-0000-0000-000000000002')),
  'photo_saved に layer が入る');
select is((select count(*) from pg_temp.sent('photo_unlocked', '19600000-0000-0000-0000-000000000002')
           where payload ->> 'board_id' = '19500000-0000-0000-0000-000000000001'), 1::bigint,
  '背景へ移してつかみが外れたら photo_unlocked が届く');
select is((select count(*) from realtime.messages m where m.payload ? 'auto_bring_to_front'), 0::bigint,
  '各自の設定の変更は配信しない');

-- ===== 重なり順の重複と排他 =====
select is(
  (select count(*) from (
     select layer, z_index from public.photos where board_id = '19500000-0000-0000-0000-000000000001' and status = 'posted'
     union all
     select layer, z_index from public.decorations where board_id = '19500000-0000-0000-0000-000000000001') s
   group by layer, z_index having count(*) > 1), null::bigint,
  '同じレイヤーに同じ z_index は作られない');
select ok(exists (
  select 1 from pg_locks l
  where l.locktype = 'advisory' and l.pid = pg_backend_pid()
    and l.classid::bigint = ((hashtextextended('ruuuto_layer_z:19500000-0000-0000-0000-000000000001:1', 0) >> 32) & 4294967295)
    and l.objid::bigint = (hashtextextended('ruuuto_layer_z:19500000-0000-0000-0000-000000000001:1', 0) & 4294967295)),
  '重なり順を変える操作は (ボード, レイヤー) の advisory lock を取る');

select * from finish();
rollback;
