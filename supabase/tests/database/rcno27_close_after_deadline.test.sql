-- RCNO-27 【履歴】締切後の投稿と編集を閉じる
-- 定量目標: 締切前は投稿・写真の移動・装飾の追加ができ、締切後（保存時点のサーバー時刻で判定）は
-- 3つとも RC002 で断る。締切後も閲覧と本人の写真の取り下げはできる。
-- 締切をまたいだ操作（締切前につかむ・投稿を始める → 締切後に保存）も保存時点で判定する。
-- あわせて装飾の追加・変更・削除の RPC（送り直し、RC009、RC014、重なり順、つかみ、本人だけの削除、配信）を確かめる。
begin;
select plan(84);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000027a1', 'close-a@example.com'),
  ('00000000-0000-0000-0000-0000000027b1', 'close-b@example.com'),
  ('00000000-0000-0000-0000-0000000027c1', 'close-c@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('27000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000027a1', gen_random_uuid()),
  ('27000000-0000-0000-0000-000000000002', 'ふたつめの班', '00000000-0000-0000-0000-0000000027a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('27000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000027a1', 'owner'),
  ('27000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000027b1', 'member'),
  ('27000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000027a1', 'owner');
-- B1: 締切時刻を過ぎさせるボード、B2: status を closed にするボード
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('27100000-0000-0000-0000-000000000001', '27000000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('27100000-0000-0000-0000-000000000002', '27000000-0000-0000-0000-000000000002', '夕焼け',
   now() - interval '1 day', now() + interval '6 days', 'open', null);

-- P1: Aの投稿済みの写真（画像あり）
insert into public.photos (id, board_id, posted_by, storage_path, status, z_index, posted_at) values
  ('27200000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000027a1',
   '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000001',
   'posted', 1, now());
insert into storage.objects (bucket_id, name) values
  ('photos', '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000001');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.sent(p_event text, p_id uuid) returns setof realtime.messages
language sql security definer as $$
  select * from realtime.messages m
  where m.event = p_event and m.extension = 'broadcast' and m.payload ->> 'id' = p_id::text
  order by m.inserted_at, m.id;
$$;

create function pg_temp.decoration(p_id uuid) returns public.decorations
language sql security definer as $$
  select * from public.decorations where id = p_id;
$$;

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');

-- ===== 締切前: 装飾の追加 =====
create temp table d1 as select public.ruuuto_add_decoration(
  '27300000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000001',
  'text', '{"text": "こんにちは", "color": "#FF3366"}', 10, 20)::jsonb as r;
select is((select r ->> 'kind' from d1), 'text', '締切前は装飾を追加できる');
select is((select (r ->> 'z_index')::int from d1), 1, '最初の装飾は z_index = 1');
select is((select jsonb_build_object('revision', r -> 'revision', 'rotation', r -> 'rotation', 'scale', r -> 'scale',
                                     'created_by', r -> 'created_by', 'updated_by', r -> 'updated_by') from d1),
  '{"revision": 1, "rotation": 0, "scale": 1, "created_by": "00000000-0000-0000-0000-0000000027a1",
    "updated_by": "00000000-0000-0000-0000-0000000027a1"}'::jsonb,
  'rotation と scale は省略時 0 と 1、revision は 1、作成者と更新者は自分');
select is((select r -> 'locked_by' from d1), 'null'::jsonb, '追加しただけではつかんでいない（lock の項目も返す）');
select is(
  public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000001',
    'text', '{"text": "こんにちは", "color": "#FF3366"}', 10, 20)::jsonb ->> 'id',
  '27300000-0000-0000-0000-000000000001', '送り直しは同じ装飾を返す');
select is(
  public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000002', '27100000-0000-0000-0000-000000000001',
    'stamp', '{"stamp_id": "star"}', 0, 0, 30, 2)::jsonb -> 'z_index', '2'::jsonb, '次の装飾は一番上（z_index = 2）');
select is(
  public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000003', '27100000-0000-0000-0000-000000000001',
    'pen', '{"strokes": [{"points": [[0, 0], [10, 10]], "color": "#000000", "width": 4}]}', 0, 0)::jsonb -> 'z_index',
  '3'::jsonb, 'ペンも追加でき、z_index = 3');
select is(
  public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000004', '27100000-0000-0000-0000-000000000001',
    'text', jsonb_build_object('text', repeat('あ', 200)), 0, 0)::jsonb ->> 'kind',
  'text', '200文字の文字は追加できる');
select is((select count(*)::int from public.decorations where board_id = '27100000-0000-0000-0000-000000000001'), 4,
  '送り直しで行は増えない');
select throws_ok(
  $$ select public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000002',
       'text', '{"text": "x"}', 0, 0) $$,
  'RC009', null, '同じIDをほかのボードで使うと RC009');

select pg_temp.act_as('00000000-0000-0000-0000-0000000027b1');
select throws_ok(
  $$ select public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000001',
       'text', '{"text": "x"}', 0, 0) $$,
  'RC009', null, 'ほかの人と同じIDでは追加できない（RC009）');

-- 内容の検査（RC014）
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'video', '{"text": "x"}', 0, 0) $$, 'RC014', null, '種類が text / stamp / pen 以外は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', '["x"]', 0, 0) $$, 'RC014', null, 'content がオブジェクトでなければ RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', null, 0, 0) $$, 'RC014', null, 'content が null なら RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', '{"color": "#000000"}', 0, 0) $$, 'RC014', null, '文字に text がなければ RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', '{"text": "   "}', 0, 0) $$, 'RC014', null, '空白だけの文字は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', '{"text": 123}', 0, 0) $$, 'RC014', null, '文字列でない text は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'text', jsonb_build_object('text', repeat('あ', 201)), 0, 0) $$, 'RC014', null, '201文字の文字は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": ""}', 0, 0) $$, 'RC014', null, 'スタンプに stamp_id がなければ RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'pen', '{"strokes": {}}', 0, 0) $$, 'RC014', null, 'ペンの strokes が配列でなければ RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'pen', jsonb_build_object('strokes', '[]'::jsonb, 'pad', repeat('a', 70000)), 0, 0) $$,
  'RC014', null, '64KB を超える content は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 0, 0, 0, 0) $$, 'RC014', null, 'scale が 0 なら RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 'NaN', 0) $$, 'RC014', null, 'NaN の座標は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 0, 'Infinity') $$, 'RC014', null, '無限大の座標は RC014');
select throws_ok($$ select public.ruuuto_add_decoration(null, '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 0, 0) $$, 'RC014', null, 'ID が null なら RC014');

select pg_temp.act_as('00000000-0000-0000-0000-0000000027c1');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 0, 0) $$, '42501', null, '所属していなければ装飾を追加できない');
select throws_ok($$ select public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000001') $$,
  '42501', null, '所属していなければ装飾を消せない');

-- ===== 締切前: 装飾の中身の変更（つかんでいる人だけ） =====
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000001', '{"text": "やあ"}') $$,
  'RC013', null, 'つかまずに中身を変えると RC013');
select is(public.ruuuto_grab_decoration('27300000-0000-0000-0000-000000000001')::jsonb -> 'z_index', '5'::jsonb,
  'つかむと一番上に出る（追加した装飾と同じ並び）');

select pg_temp.act_as('00000000-0000-0000-0000-0000000027b1');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000001', '{"text": "横取り"}') $$,
  'RC012', null, 'ほかの人がつかんでいると中身を変えられない（RC012）');

select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
create temp table e1 as select public.ruuuto_edit_decoration(
  '27300000-0000-0000-0000-000000000001', '{"text": "やあ", "color": "#000000"}')::jsonb as r;
select is((select r -> 'content' from e1), '{"text": "やあ", "color": "#000000"}'::jsonb, '中身を変えられる');
select is((select (r ->> 'revision')::int from e1), 3, '中身を変えると revision が1増える（grab で1、edit で1）');
select is((select r ->> 'locked_by' from e1), '00000000-0000-0000-0000-0000000027a1', '変更後もつかんだまま');
select is(public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000001', '{"text": "やあ", "color": "#000000"}')::jsonb -> 'revision',
  '3'::jsonb, '同じ中身の送り直しでは revision は変わらない');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000001', '{"stamp_id": "star"}') $$,
  'RC014', null, '種類に合わない中身へは変えられない（RC014）');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000003', '{"strokes": []}') $$,
  'RC014', null, 'ペンの中身は変えられない（RC014）');
select is((select count(*)::int from pg_temp.sent('decoration_saved', '27300000-0000-0000-0000-000000000001')), 3,
  'decoration_saved は追加・重なり順の変更・中身の変更の3回（送り直しでは送らない）');
select is((select payload -> 'content' ->> 'text' from pg_temp.sent('decoration_saved', '27300000-0000-0000-0000-000000000001')
           offset 2 limit 1), 'やあ', '配信された中身は変更後の値');

-- ===== 締切前: 装飾を消す（追加した本人だけ） =====
select pg_temp.act_as('00000000-0000-0000-0000-0000000027b1');
select throws_ok($$ select public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000002') $$,
  '42501', null, '追加した本人以外は消せない');
select ok((public.ruuuto_grab_decoration('27300000-0000-0000-0000-000000000002')::jsonb ->> 'locked_by') is not null,
  'Bが Aのスタンプをつかむ');
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
select throws_ok($$ select public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000002') $$,
  'RC012', null, 'ほかの人がつかんでいる間は本人でも消せない（RC012）');
select pg_temp.act_as('00000000-0000-0000-0000-0000000027b1');
select is(public.ruuuto_release_decoration('27300000-0000-0000-0000-000000000002')::jsonb -> 'locked_by', 'null'::jsonb,
  'Bが離す');
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
select is(public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000002')::jsonb,
  '{"id": "27300000-0000-0000-0000-000000000002", "deleted": true}'::jsonb, '離されたあとは本人が消せる');
select is(public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000002')::jsonb,
  '{"id": "27300000-0000-0000-0000-000000000002", "deleted": false}'::jsonb, '消した装飾をもう一度消してもエラーにならない');
select is((select payload from pg_temp.sent('decoration_deleted', '27300000-0000-0000-0000-000000000002')),
  '{"id": "27300000-0000-0000-0000-000000000002", "board_id": "27100000-0000-0000-0000-000000000001"}'::jsonb,
  'decoration_deleted {id, board_id} を1回だけ配信する');
select is(public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000004')::jsonb ->> 'deleted', 'true',
  '自分がつかんでいなくても、誰もつかんでいなければ消せる');

-- ===== 締切前: 投稿と写真の移動 =====
-- P2: 締切前に始めてアップロードまで済ませ、確定は締切後に送る
create temp table p2 as select public.ruuuto_begin_photo(
  '27200000-0000-0000-0000-000000000002', '27100000-0000-0000-0000-000000000001')::jsonb as r;
select is((select r ->> 'status' from p2), 'pending', '締切前は投稿を始められる');
insert into storage.objects (bucket_id, name, owner_id) values ('photos',
  '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-0000000027a1');
select is((select count(*)::int from storage.objects
           where name like '27000000-0000-0000-0000-000000000001/%/27200000-0000-0000-0000-000000000002'), 1,
  '締切前は画像をアップロードできる');
-- P3: 締切前に始めたが、アップロードは締切後
select is(public.ruuuto_begin_photo('27200000-0000-0000-0000-000000000003', '27100000-0000-0000-0000-000000000001')::jsonb ->> 'status',
  'pending', 'もう1枚投稿を始める');
-- P4: 締切前に投稿を確定できることも確かめる
select public.ruuuto_begin_photo('27200000-0000-0000-0000-000000000004', '27100000-0000-0000-0000-000000000001');
insert into storage.objects (bucket_id, name, owner_id) values ('photos',
  '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-0000000027a1');
select is(public.ruuuto_finish_photo('27200000-0000-0000-0000-000000000004')::jsonb ->> 'status', 'posted',
  '締切前は投稿を確定できる');

select is(public.ruuuto_grab_photo('27200000-0000-0000-0000-000000000001')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000027a1', '締切前は写真をつかめる');
select is(public.ruuuto_move_photo('27200000-0000-0000-0000-000000000001', 5, 6, 0, 1)::jsonb -> 'x', '5'::jsonb,
  '締切前は写真を動かせる（つかんだまま締切を迎える）');
select is(public.ruuuto_grab_decoration('27300000-0000-0000-0000-000000000001')::jsonb ->> 'locked_by',
  '00000000-0000-0000-0000-0000000027a1', '文字の装飾もつかんだまま締切を迎える');

-- B2 にも装飾を置いてつかんでおく（status = closed の確認用）
select is(public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000005', '27100000-0000-0000-0000-000000000002',
  'stamp', '{"stamp_id": "heart"}', 0, 0)::jsonb ->> 'kind', 'stamp', 'B2 にも装飾を追加する');
select ok((public.ruuuto_grab_decoration('27300000-0000-0000-0000-000000000005')::jsonb ->> 'locked_by') is not null,
  'B2 の装飾をつかむ');

-- ===== 締切: closes_at を過ぎさせる（status は open のまま） =====
reset role;
update public.boards set closes_at = now() - interval '1 second' where id = '27100000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');

-- 投稿
select throws_ok($$ select public.ruuuto_begin_photo(gen_random_uuid(), '27100000-0000-0000-0000-000000000001') $$,
  'RC002', null, '締切時刻を過ぎたら投稿を始められない（status が open のままでも）');
select throws_ok($$ select public.ruuuto_finish_photo('27200000-0000-0000-0000-000000000002') $$,
  'RC002', null, '締切前に始めた投稿も、締切後の確定は RC002');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values ('photos',
     '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000003',
     '00000000-0000-0000-0000-0000000027a1') $$,
  '42501', null, '締切後は締切前に始めた投稿でも画像をアップロードできない');
select is(public.ruuuto_begin_photo('27200000-0000-0000-0000-000000000002', '27100000-0000-0000-0000-000000000001')::jsonb ->> 'status',
  'pending', '始めた投稿の送り直しは、書き込まずに今の状態を返す');
select is(public.ruuuto_finish_photo('27200000-0000-0000-0000-000000000004')::jsonb ->> 'status', 'posted',
  '確定済みの送り直しは、書き込まずに今の状態を返す');

-- 写真の移動
select throws_ok($$ select public.ruuuto_move_photo('27200000-0000-0000-0000-000000000001', 7, 8, 0, 1) $$,
  'RC002', null, '締切前につかんだ写真も、締切後の移動は RC002（RC013 ではない）');
select throws_ok($$ select public.ruuuto_grab_photo('27200000-0000-0000-0000-000000000001') $$,
  'RC002', null, '締切後は写真をつかめない');
select is(public.ruuuto_release_photo('27200000-0000-0000-0000-000000000001')::jsonb -> 'locked_by', 'null'::jsonb,
  '締切後も写真を離せる');

-- 装飾
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000001',
  'stamp', '{"stamp_id": "star"}', 0, 0) $$, 'RC002', null, '締切後は装飾を追加できない');
select is(public.ruuuto_add_decoration('27300000-0000-0000-0000-000000000001', '27100000-0000-0000-0000-000000000001',
    'text', '{"text": "こんにちは"}', 10, 20)::jsonb -> 'content' ->> 'text',
  'やあ', '追加済みの装飾の送り直しは、書き込まずに今の状態を返す');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000001', '{"text": "締切後"}') $$,
  'RC002', null, '締切前につかんだ装飾も、締切後は中身を変えられない');
select throws_ok($$ select public.ruuuto_move_decoration('27300000-0000-0000-0000-000000000001', 1, 1, 0, 1) $$,
  'RC002', null, '締切前につかんだ装飾も、締切後は動かせない');
select throws_ok($$ select public.ruuuto_delete_decoration('27300000-0000-0000-0000-000000000001') $$,
  'RC002', null, '締切後は本人でも装飾を消せない');
select is(public.ruuuto_release_decoration('27300000-0000-0000-0000-000000000001')::jsonb -> 'locked_by', 'null'::jsonb,
  '締切後も装飾を離せる');
select is((select (content ->> 'text', revision)::text from pg_temp.decoration('27300000-0000-0000-0000-000000000001')),
  '(やあ,3)', '締切後の操作で装飾の中身と revision は変わっていない');

-- お題
select throws_ok($$ select public.ruuuto_save_topic('27100000-0000-0000-0000-000000000001', '朝ごはん') $$,
  'RC002', null, '締切後はお題を変えられない');

-- 閲覧
select is(
  (select jsonb_build_object('photos', jsonb_array_length(s -> 'photos'), 'decorations', jsonb_array_length(s -> 'decorations'))
   from (select public.ruuuto_board_snapshot('27100000-0000-0000-0000-000000000001')::jsonb as s) x),
  '{"photos": 2, "decorations": 2}'::jsonb, '締切後もスナップショットを読める');
select is(
  (select e ->> 'photo_count'
   from jsonb_array_elements(public.ruuuto_board_history('27000000-0000-0000-0000-000000000001',
          extract(year from (now() - interval '1 day') at time zone 'Asia/Tokyo')::int,
          extract(month from (now() - interval '1 day') at time zone 'Asia/Tokyo')::int)::jsonb) e
   where e ->> 'id' = '27100000-0000-0000-0000-000000000001'),
  '2', '締切後も履歴に載り、投稿済みの写真の枚数を読める');
select pg_temp.act_as('00000000-0000-0000-0000-0000000027b1');
select is((select count(*)::int from storage.objects
           where name = '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000001'),
  1, '締切後もほかのメンバーは投稿済みの画像を読める');

-- 本人の取り下げ
select throws_ok($$ select public.ruuuto_withdraw_photo('27200000-0000-0000-0000-000000000001') $$,
  '42501', null, '締切後も本人以外は取り下げられない');
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
select is(public.ruuuto_withdraw_photo('27200000-0000-0000-0000-000000000001')::jsonb ->> 'status', 'withdrawn',
  '締切後も本人は写真を取り下げられる');
select ok(private.ruuuto_can_delete_photo_object(
  '27000000-0000-0000-0000-000000000001/27100000-0000-0000-0000-000000000001/27200000-0000-0000-0000-000000000001'),
  '締切後も取り下げた本人は画像を消せる（Storage の削除権限）');

-- ===== status = 'closed'（closes_at はまだ先）でも同じ =====
reset role;
update public.boards set status = 'closed', closed_at = now() where id = '27100000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000027a1');
select throws_ok($$ select public.ruuuto_begin_photo(gen_random_uuid(), '27100000-0000-0000-0000-000000000002') $$,
  'RC002', null, 'status が closed なら締切時刻の前でも投稿を始められない');
select throws_ok($$ select public.ruuuto_add_decoration(gen_random_uuid(), '27100000-0000-0000-0000-000000000002',
  'stamp', '{"stamp_id": "star"}', 0, 0) $$, 'RC002', null, 'status が closed なら装飾を追加できない');
select throws_ok($$ select public.ruuuto_move_decoration('27300000-0000-0000-0000-000000000005', 1, 1, 0, 1) $$,
  'RC002', null, 'status が closed なら、つかんでいた装飾も動かせない');
select throws_ok($$ select public.ruuuto_edit_decoration('27300000-0000-0000-0000-000000000005', '{"stamp_id": "star"}') $$,
  'RC002', null, 'status が closed なら装飾の中身を変えられない');
select throws_ok($$ select public.ruuuto_save_topic('27100000-0000-0000-0000-000000000002', '朝ごはん') $$,
  'RC002', null, 'status が closed ならお題を変えられない');
reset role;

-- 権限
select ok(not has_function_privilege('anon', 'public.ruuuto_add_decoration(uuid, uuid, text, jsonb, double precision, double precision, double precision, double precision)', 'execute')
          and not has_function_privilege('anon', 'public.ruuuto_edit_decoration(uuid, jsonb)', 'execute')
          and not has_function_privilege('anon', 'public.ruuuto_delete_decoration(uuid)', 'execute'),
  'anon は装飾の RPC を呼べない');
select ok(not has_function_privilege('authenticated', 'private.ruuuto_require_decoration_content(text, jsonb)', 'execute')
          and not has_function_privilege('authenticated', 'private.ruuuto_require_open_board(uuid)', 'execute'),
  'アプリから内部の検査関数は呼べない');

select * from finish();
rollback;
