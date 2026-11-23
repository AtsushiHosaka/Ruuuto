-- RCNO-5 グループ外からの操作を拒否する
-- A: グループ1の所属者、B: グループ2の所属者、C: どこにも所属していない
begin;
select plan(22);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000005a1', 'rls-a@example.com'),
  ('00000000-0000-0000-0000-0000000005b1', 'rls-b@example.com'),
  ('00000000-0000-0000-0000-0000000005c1', 'rls-c@example.com'),
  ('00000000-0000-0000-0000-0000000005d1', 'rls-d@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('50000000-0000-0000-0000-000000000001', 'グループ1', '00000000-0000-0000-0000-0000000005a1', gen_random_uuid()),
  ('50000000-0000-0000-0000-000000000002', 'グループ2', '00000000-0000-0000-0000-0000000005b1', gen_random_uuid());

-- D はグループ1の2人目の所属者
insert into public.group_members (group_id, user_id, role) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005a1', 'owner'),
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005d1', 'member'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000005b1', 'owner');

insert into public.boards (id, group_id, topic, opens_at, closes_at) values
  ('51000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'お題1', now() - interval '1 day', now() + interval '6 days'),
  ('51000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', 'お題2', now() - interval '1 day', now() + interval '6 days');

insert into public.photos (id, board_id, posted_by, storage_path, status) values
  ('52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005a1', 'g1/posted.jpg', 'posted'),
  ('52000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005a1', 'g1/pending.jpg', 'pending'),
  ('52000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005a1', 'g1/withdrawn.jpg', 'withdrawn'),
  ('52000000-0000-0000-0000-000000000004', '51000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000005b1', 'g2/posted.jpg', 'posted');

insert into public.decorations (id, board_id, created_by, kind, content) values
  ('53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005a1', 'text', '{"text": "さむっ！"}'),
  ('53000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000005b1', 'stamp', '{"stamp": "snow"}');

insert into public.devices (installation_id, user_id, apns_token) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000005a1', repeat('a1', 32)),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000005b1', repeat('b1', 32));

insert into public.invitations (group_id, token_hash, created_by, expires_at) values
  ('50000000-0000-0000-0000-000000000001', extensions.digest('test-token', 'sha256'),
   '00000000-0000-0000-0000-0000000005a1', now() + interval '7 days');

-- RCNO-4 の48件を外し、このテストのお題だけにする
delete from public.topic_prompts;
insert into public.topic_prompts (month, week, body) values (11, 4, '窓の外');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

-- A（グループ1の所属者）
select pg_temp.act_as('00000000-0000-0000-0000-0000000005a1');
select is((select array_agg(name) from public.groups), array['グループ1'], 'A: 所属グループだけが見える');
select is((select array_agg(topic) from public.boards), array['お題1'], 'A: 所属グループのボードだけが見える');
select is((select count(*)::int from public.group_members), 2, 'A: 所属グループの参加者2人が見える');
select is(
  (select array_agg(storage_path order by storage_path) from public.photos),
  array['g1/pending.jpg', 'g1/posted.jpg'],
  'A: 自分の投稿途中と投稿済みの写真が見え、取り下げた写真とグループ2の写真は見えない');
select is((select count(*)::int from public.decorations), 1, 'A: 所属グループの装飾だけが見える');
select is((select count(*)::int from public.profiles), 2, 'A: 自分と同じグループのDのプロフィールだけが見える');
select is((select count(*)::int from public.devices), 1, 'A: 自分の端末登録だけが見える');
select throws_ok($$ select count(*) from public.invitations $$, '42501', null, 'A: 招待テーブルは直接読めない（SELECT権限がない）');
select is((select count(*)::int from public.topic_prompts), 1, 'A: 固定のお題は読める');

-- A でも、テーブルを直接書き換えることはできない
select throws_ok(
  $$ update public.photos set x = 10 where id = '52000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'A: 写真の位置を直接は変えられない（保存はRPC経由）');
select throws_ok(
  $$ insert into public.group_members (group_id, user_id) values
     ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000005a1') $$,
  '42501', null, 'A: 自分を別グループの所属に直接追加できない');

-- D（グループ1の別の参加者）は、A の投稿途中の写真を見られない
select pg_temp.act_as('00000000-0000-0000-0000-0000000005d1');
select is(
  (select array_agg(storage_path) from public.photos),
  array['g1/posted.jpg'], 'D: 他人の投稿途中の写真は見えない');

-- B（グループ2の所属者）から見たグループ1
select pg_temp.act_as('00000000-0000-0000-0000-0000000005b1');
select is(
  (select count(*)::int from public.boards where group_id = '50000000-0000-0000-0000-000000000001'),
  0, 'B（非メンバー）: グループ1のボードを閲覧できない');
select is(
  (select count(*)::int from public.photos where board_id = '51000000-0000-0000-0000-000000000001'),
  0, 'B（非メンバー）: グループ1の写真を取得できない');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000005a1'),
  0, 'B: 同じグループでない A のプロフィールは見えない');
select throws_ok(
  $$ update public.photos set x = 10 where board_id = '51000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'B（非メンバー）: グループ1の写真を移動できない');
select throws_ok(
  $$ delete from public.decorations where board_id = '51000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'B（非メンバー）: グループ1の装飾を消せない');

-- C（どこにも所属していない）
select pg_temp.act_as('00000000-0000-0000-0000-0000000005c1');
select is((select count(*)::int from public.groups), 0, 'C: グループは1件も見えない');
select is((select count(*)::int from public.boards), 0, 'C: ボードは1件も見えない');
select throws_ok(
  $$ insert into public.boards (group_id, topic, opens_at, closes_at)
     values ('50000000-0000-0000-0000-000000000001', '乗っ取り', now(), now() + interval '1 day') $$,
  '42501', null, 'C: ボードを直接作れない');

-- 未ログイン（anon）
reset role;
set local role anon;
select throws_ok($$ select * from public.groups $$, '42501', null, 'anon: グループを読めない');
select throws_ok($$ select * from public.photos $$, '42501', null, 'anon: 写真を読めない');
reset role;

select * from finish();
rollback;
