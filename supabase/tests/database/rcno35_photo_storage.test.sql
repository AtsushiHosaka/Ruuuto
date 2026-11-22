-- RCNO-35 非公開の画像ストレージと削除処理
-- 定量目標: 投稿成功・非メンバーによる取得拒否・アップロード途中の失敗・本人の取り下げ後の取得拒否。
-- 失敗時に孤立した画像が残らない（片付けの対象になる）。
-- 画像の削除は Storage API でしかできないので、削除そのものはAPIの通し確認で見る。
begin;
select plan(31);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000035a1', 'poster@example.com'),
  ('00000000-0000-0000-0000-0000000035b1', 'member35@example.com'),
  ('00000000-0000-0000-0000-0000000035c1', 'outsider35@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('35000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000035a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('35000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000035a1', 'owner'),
  ('35000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000035b1', 'member');
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('35100000-0000-0000-0000-000000000001', '35000000-0000-0000-0000-000000000001', '先週',
   now() - interval '14 days', now() - interval '7 days', 'closed', now() - interval '7 days'),
  ('35100000-0000-0000-0000-000000000002', '35000000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days', 'open', null);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

select is((select public from storage.buckets where id = 'photos'), false, 'photos バケットは非公開');

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');

-- 投稿を始める
create temp table begun as select public.ruuuto_begin_photo(
  '35200000-0000-0000-0000-000000000001', '35100000-0000-0000-0000-000000000002', ' 東京 ', 1200, 900)::jsonb as p;
select is((select p ->> 'status' from begun), 'pending', '始めた写真は投稿途中');
select is(
  (select p ->> 'storage_path' from begun),
  '35000000-0000-0000-0000-000000000001/35100000-0000-0000-0000-000000000002/35200000-0000-0000-0000-000000000001',
  '保存先は グループID/ボードID/写真ID');
select is((select p ->> 'city' from begun), '東京', '都市は前後の空白を除いて保存する');
select is(
  public.ruuuto_begin_photo('35200000-0000-0000-0000-000000000001', '35100000-0000-0000-0000-000000000002', '東京', 1200, 900)::jsonb ->> 'id',
  '35200000-0000-0000-0000-000000000001', '送り直しは同じ写真を返す');
select throws_ok(
  $$ select public.ruuuto_begin_photo(gen_random_uuid(), '35100000-0000-0000-0000-000000000001') $$,
  'RC002', null, '締切後のボードには投稿を始められない');
select throws_ok(
  $$ select public.ruuuto_begin_photo(gen_random_uuid(), '35100000-0000-0000-0000-000000000002', repeat('都', 61)) $$,
  'RC008', null, '61文字の都市は RC008');

-- アップロード前に確定しようとする（アップロード途中の失敗）
select throws_ok(
  $$ select public.ruuuto_finish_photo('35200000-0000-0000-0000-000000000001') $$,
  'RC007', null, '画像がまだないと確定できない');

-- 別の参加者は、他人の投稿途中の保存先にアップロードできない
select pg_temp.act_as('00000000-0000-0000-0000-0000000035b1');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values ('photos',
     '35000000-0000-0000-0000-000000000001/35100000-0000-0000-0000-000000000002/35200000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000035b1') $$,
  '42501', null, '他人の投稿途中の保存先にはアップロードできない');
select throws_ok(
  $$ select public.ruuuto_begin_photo('35200000-0000-0000-0000-000000000001', '35100000-0000-0000-0000-000000000002') $$,
  'RC009', null, '他人と同じ写真IDでは始められない');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values ('photos',
     '35000000-0000-0000-0000-000000000001/35100000-0000-0000-0000-000000000002/not-reserved',
     '00000000-0000-0000-0000-0000000035b1') $$,
  '42501', null, '始めていない保存先にはアップロードできない');

-- 本人がアップロードする
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');
insert into storage.objects (bucket_id, name, owner_id) values ('photos',
  '35000000-0000-0000-0000-000000000001/35100000-0000-0000-0000-000000000002/35200000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000035a1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 1, '本人は投稿途中の写真をアップロードして読める');

-- 確定前は、他の参加者からは見えない
select pg_temp.act_as('00000000-0000-0000-0000-0000000035b1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, '確定前の画像は他の参加者に見えない');

-- 確定する（投稿成功）
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');
create temp table finished as select public.ruuuto_finish_photo('35200000-0000-0000-0000-000000000001')::jsonb as p;
select is((select p ->> 'status' from finished), 'posted', '確定すると投稿済みになる');
select is((select (p ->> 'z_index')::int from finished), 1, '最初の写真は一番下（z_index = 1）');
select ok((select p ->> 'posted_at' is not null from finished), '投稿日時が入る');
select is(
  public.ruuuto_finish_photo('35200000-0000-0000-0000-000000000001')::jsonb ->> 'status',
  'posted', '確定の送り直しも成功する');

-- 他の参加者は読める。非メンバーは読めない
select pg_temp.act_as('00000000-0000-0000-0000-0000000035b1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 1, '投稿済みの画像は同じグループの参加者が読める');
select pg_temp.act_as('00000000-0000-0000-0000-0000000035c1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, '非メンバーは画像を取得できない');
select throws_ok(
  $$ select public.ruuuto_finish_photo('35200000-0000-0000-0000-000000000001') $$,
  '42501', null, '非メンバーは他人の写真を確定できない');

-- 取り下げ
select pg_temp.act_as('00000000-0000-0000-0000-0000000035b1');
select throws_ok(
  $$ select public.ruuuto_withdraw_photo('35200000-0000-0000-0000-000000000001') $$,
  '42501', null, '投稿者以外は取り下げられない');

-- 締切を過ぎても本人は取り下げられる
reset role;
update public.boards set status = 'closed', closed_at = now(), closes_at = now(), opens_at = now() - interval '7 days'
 where id = '35100000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');
select is(
  public.ruuuto_withdraw_photo('35200000-0000-0000-0000-000000000001')::jsonb ->> 'status',
  'withdrawn', '締切後でも本人は取り下げられる');
select is(
  public.ruuuto_withdraw_photo('35200000-0000-0000-0000-000000000001')::jsonb ->> 'status',
  'withdrawn', '取り下げの送り直しも成功する');
select throws_ok(
  $$ select public.ruuuto_finish_photo('35200000-0000-0000-0000-000000000001') $$,
  'RC010', null, '取り下げた写真は確定できない');

-- 取り下げ後は、画像がまだ残っていても他の参加者は取得できない。本人は消すために読める
select pg_temp.act_as('00000000-0000-0000-0000-0000000035b1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, '取り下げた画像は他の参加者が取得できない');
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 1, '取り下げた本人は、消すために自分の画像を読める');

-- 片付け（service_role）
reset role;
-- 放置された投稿途中の写真: 画像あり1件・画像なし1件（2時間前に始めたもの）
insert into public.photos (id, board_id, posted_by, storage_path, status, created_at) values
  ('35200000-0000-0000-0000-000000000002', '35100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000035a1', 'x/abandoned-with-image', 'pending', now() - interval '2 hours'),
  ('35200000-0000-0000-0000-000000000003', '35100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000035a1', 'x/abandoned-without-image', 'pending', now() - interval '2 hours'),
  ('35200000-0000-0000-0000-000000000004', '35100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000035a1', 'x/fresh-pending', 'pending', now());
insert into storage.objects (bucket_id, name) values ('photos', 'x/abandoned-with-image'), ('photos', 'x/fresh-pending');

set local role service_role;
create temp table targets as select public.ruuuto_admin_photo_cleanup_targets()::jsonb as t;
select is(
  (select t -> 'paths' from targets),
  '["35000000-0000-0000-0000-000000000001/35100000-0000-0000-0000-000000000002/35200000-0000-0000-0000-000000000001", "x/abandoned-with-image"]'::jsonb,
  '片付けの対象は、取り下げた画像と放置された投稿途中の画像（始めたばかりのものは除く）');
select is((select (t ->> 'removed_rows')::int from targets), 1, '画像のない放置された投稿途中の行は、その場で消す');
select is(
  public.ruuuto_admin_photo_cleanup_finish(array['x/abandoned-with-image'])::jsonb ->> 'removed_rows',
  '0', '画像がまだ残っている行は消さない（Storage API で消したあとに消す）');
reset role;

-- アプリからは片付けの関数を呼べない
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000035a1');
select throws_ok($$ select public.ruuuto_admin_photo_cleanup_targets() $$, '42501', null, 'アプリから片付けの対象は取得できない');
reset role;
set local role anon;
select throws_ok($$ select public.ruuuto_begin_photo(gen_random_uuid(), gen_random_uuid()) $$, '42501', null, 'anon は投稿を始められない');
reset role;

select * from finish();
rollback;
