-- RCNO-43 開催中・履歴・都市別のボード参照
-- 定量目標: 2グループ、2か月、2都市、都市未設定のデータで、
-- 開催中・月別履歴・都市別一覧の3種類の結果と件数を確認する。
begin;
select plan(20);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000043a1', 'tokyo@example.com'),
  ('00000000-0000-0000-0000-0000000043b1', 'vancouver@example.com'),
  ('00000000-0000-0000-0000-0000000043c1', 'other@example.com');
update public.profiles set display_name = 'A' where id = '00000000-0000-0000-0000-0000000043a1';
update public.profiles set display_name = 'S' where id = '00000000-0000-0000-0000-0000000043b1';

insert into public.groups (id, name, created_by, create_request_id) values
  ('43000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000043a1', gen_random_uuid()),
  ('43000000-0000-0000-0000-000000000002', '別の班', '00000000-0000-0000-0000-0000000043c1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('43000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000043a1', 'owner'),
  ('43000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000043b1', 'member'),
  ('43000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000043c1', 'owner');

-- グループ1: 10月に終了済み1件、11月に終了済み1件と開催中1件。グループ2: 11月に開催中1件
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('43100000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001', 'ハロウィン',
   '2026-10-26T00:00:00+09:00', '2026-11-02T00:00:00+09:00', 'closed', '2026-11-02T00:00:00+09:00'),
  ('43100000-0000-0000-0000-000000000002', '43000000-0000-0000-0000-000000000001', '紅葉',
   '2026-11-09T00:00:00+09:00', '2026-11-16T00:00:00+09:00', 'closed', '2026-11-16T00:00:00+09:00'),
  ('43100000-0000-0000-0000-000000000003', '43000000-0000-0000-0000-000000000001', '窓の外',
   '2026-11-16T00:00:00+09:00', '2026-11-23T00:00:00+09:00', 'open', null),
  ('43100000-0000-0000-0000-000000000004', '43000000-0000-0000-0000-000000000002', '別のお題',
   '2026-11-16T00:00:00+09:00', '2026-11-23T00:00:00+09:00', 'open', null);

-- 開催中ボードの写真: 東京2枚、バンクーバー1枚、都市なし1枚、投稿途中1枚、取り下げ1枚
insert into public.photos (id, board_id, posted_by, storage_path, status, city, created_at, posted_at) values
  ('43200000-0000-0000-0000-000000000001', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043a1', 'p/1.jpg', 'posted', '東京', '2026-11-17T10:00:00+09:00', '2026-11-17T10:00:00+09:00'),
  ('43200000-0000-0000-0000-000000000002', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043b1', 'p/2.jpg', 'posted', 'バンクーバー', '2026-11-17T11:00:00+09:00', '2026-11-17T11:00:00+09:00'),
  ('43200000-0000-0000-0000-000000000003', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043a1', 'p/3.jpg', 'posted', '東京', '2026-11-18T10:00:00+09:00', '2026-11-18T10:00:00+09:00'),
  ('43200000-0000-0000-0000-000000000004', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043b1', 'p/4.jpg', 'posted', null, '2026-11-19T10:00:00+09:00', '2026-11-19T10:00:00+09:00'),
  ('43200000-0000-0000-0000-000000000005', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043a1', 'p/5.jpg', 'pending', '東京', '2026-11-20T10:00:00+09:00', null),
  ('43200000-0000-0000-0000-000000000006', '43100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000043b1', 'p/6.jpg', 'withdrawn', 'バンクーバー', '2026-11-20T11:00:00+09:00', null),
  ('43200000-0000-0000-0000-000000000007', '43100000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000000043c1', 'p/7.jpg', 'posted', '東京', '2026-11-17T10:00:00+09:00', '2026-11-17T10:00:00+09:00');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000043b1');

-- 開催中
select is(
  public.ruuuto_current_board('43000000-0000-0000-0000-000000000001')::jsonb,
  '{"id": "43100000-0000-0000-0000-000000000003", "group_id": "43000000-0000-0000-0000-000000000001",
    "topic": "窓の外", "topic_texts": {}, "opens_at": "2026-11-15T15:00:00Z", "closes_at": "2026-11-22T15:00:00Z", "status": "open"}'::jsonb,
  '開催中のボードをiOSが読む形（UTCの秒単位）で返す。手動のお題の topic_texts は空（RCNO-4）');
select throws_ok(
  $$ select public.ruuuto_current_board('43000000-0000-0000-0000-000000000002') $$,
  '42501', null, '所属していないグループの開催中ボードは 42501');

-- 月別履歴
create temp table nov as select public.ruuuto_board_history('43000000-0000-0000-0000-000000000001', 2026, 11)::jsonb as h;
select is((select jsonb_array_length(h) from nov), 2, '11月はグループ1のボード2件（別グループは混ざらない）');
select is((select jsonb_agg(x ->> 'topic') from nov, jsonb_array_elements(h) x), '["紅葉", "窓の外"]'::jsonb, '開始日時の古い順');
select is((select jsonb_agg(x ->> 'status') from nov, jsonb_array_elements(h) x), '["closed", "open"]'::jsonb, '終了済みと開催中を status で区別できる');
select is((select (h -> 1 ->> 'photo_count')::int from nov), 4, '開催中ボードの写真数は投稿済みの4枚（投稿途中と取り下げは数えない）');
select is((select h -> 1 -> 'preview_paths' from nov), '["p/1.jpg", "p/2.jpg", "p/3.jpg"]'::jsonb, 'プレビューは投稿の古い順に3件');
select is((select h -> 0 -> 'preview_paths' from nov), '[]'::jsonb, '写真のないボードのプレビューは空の配列');
select is(
  (select jsonb_agg(x ->> 'topic') from jsonb_array_elements(public.ruuuto_board_history('43000000-0000-0000-0000-000000000001', 2026, 10)::jsonb) x),
  '["ハロウィン"]'::jsonb, '10月はハロウィンの1件（11月2日に締め切ったボードも開始月の10月）');
select is(
  public.ruuuto_board_history('43000000-0000-0000-0000-000000000001', 2026, 12)::jsonb,
  '[]'::jsonb, 'ボードのない月は空の配列');
select throws_ok(
  $$ select public.ruuuto_board_history('43000000-0000-0000-0000-000000000001', 2026, 13) $$,
  '22023', null, '13月は 22023');
select throws_ok(
  $$ select public.ruuuto_board_history('43000000-0000-0000-0000-000000000002', 2026, 11) $$,
  '42501', null, '所属していないグループの履歴は 42501');

-- 都市別
select is(
  public.ruuuto_board_cities('43100000-0000-0000-0000-000000000003')::jsonb,
  '[{"city": "東京", "photo_count": 2}, {"city": "バンクーバー", "photo_count": 1}]'::jsonb,
  '都市別の件数（都市なし・投稿途中・取り下げは含めない、多い順）');
select is(
  (select jsonb_agg(x ->> 'id') from jsonb_array_elements(public.ruuuto_city_photos('43100000-0000-0000-0000-000000000003', '東京')::jsonb) x),
  '["43200000-0000-0000-0000-000000000001", "43200000-0000-0000-0000-000000000003"]'::jsonb,
  '東京の写真は投稿の古い順に2枚（投稿途中は含めない）');
select is(
  public.ruuuto_city_photos('43100000-0000-0000-0000-000000000003', 'バンクーバー')::jsonb -> 0 ->> 'display_name',
  'S', '写真に投稿者の表示名が付く');
select is(
  public.ruuuto_city_photos('43100000-0000-0000-0000-000000000003', 'パリ')::jsonb,
  '[]'::jsonb, '写真のない都市は空の配列');
select throws_ok(
  $$ select public.ruuuto_board_cities('43100000-0000-0000-0000-000000000004') $$,
  '42501', null, '所属していないグループのボードの都市一覧は 42501');
select throws_ok(
  $$ select public.ruuuto_city_photos('43100000-0000-0000-0000-000000000099', '東京') $$,
  '42501', null, '存在しないボードも 42501（存在を漏らさない）');

-- 開催中のボードがない場合
reset role;
update public.boards set status = 'closed', closed_at = now() where id = '43100000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000043a1');
select throws_ok(
  $$ select public.ruuuto_current_board('43000000-0000-0000-0000-000000000001') $$,
  'P0002', null, '開催中のボードがなければ P0002');

reset role;
set local role anon;
select throws_ok($$ select public.ruuuto_current_board('43000000-0000-0000-0000-000000000001') $$, '42501', null, 'anon は呼べない');
reset role;

select * from finish();
rollback;
