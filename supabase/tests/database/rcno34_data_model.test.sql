-- RCNO-34 の受け入れ条件
-- 2グループ、各グループに開催中1件と終了済み1件のボードを保存し、
-- 別グループのボードを混ぜずに取得できる。同じグループに開催中を2件は登録できない。
begin;
select plan(12);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-0000000000a1', 'tester-a@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'tester-b@example.com');

insert into public.profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000000a1', 'テスターA'),
  ('00000000-0000-0000-0000-0000000000b1', 'テスターB')
on conflict (id) do nothing;

insert into public.groups (id, name, created_by, create_request_id)
values
  ('10000000-0000-0000-0000-000000000001', 'グループ1', '00000000-0000-0000-0000-0000000000a1', gen_random_uuid()),
  ('10000000-0000-0000-0000-000000000002', 'グループ2', '00000000-0000-0000-0000-0000000000b1', gen_random_uuid());

insert into public.boards (group_id, topic, opens_at, closes_at, status, closed_at)
values
  ('10000000-0000-0000-0000-000000000001', '先週のお題1', '2026-11-09T00:00:00Z', '2026-11-16T00:00:00Z', 'closed', '2026-11-16T00:00:00Z'),
  ('10000000-0000-0000-0000-000000000001', '今週のお題1', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z', 'open', null),
  ('10000000-0000-0000-0000-000000000002', '先週のお題2', '2026-11-09T00:00:00Z', '2026-11-16T00:00:00Z', 'closed', '2026-11-16T00:00:00Z'),
  ('10000000-0000-0000-0000-000000000002', '今週のお題2', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z', 'open', null);

-- 別グループのボードを混ぜずに取得できる
select is(
  (select count(*)::int from public.boards where group_id = '10000000-0000-0000-0000-000000000001'),
  2, 'グループ1のボードは2件');
select is(
  (select array_agg(topic order by opens_at) from public.boards where group_id = '10000000-0000-0000-0000-000000000002'),
  array['先週のお題2', '今週のお題2'], 'グループ2のボードにはグループ2のお題だけが入る');
select is(
  (select topic from public.boards where group_id = '10000000-0000-0000-0000-000000000001' and status = 'open'),
  '今週のお題1', 'グループ1の開催中ボードは1件に決まる');

-- 開催中のボードを同じグループに2件登録しようとすると拒否する
select throws_ok(
  $$ insert into public.boards (group_id, topic, opens_at, closes_at)
     values ('10000000-0000-0000-0000-000000000001', '二重', '2026-11-23T00:00:00Z', '2026-11-30T00:00:00Z') $$,
  '23505', null, '同じグループに開催中ボードを2件は登録できない');

-- 同じ期間のボードを二重に作れない（週次切替の再実行）
select throws_ok(
  $$ insert into public.boards (group_id, topic, opens_at, closes_at, status, closed_at)
     values ('10000000-0000-0000-0000-000000000001', '同じ週', '2026-11-09T00:00:00Z', '2026-11-16T00:00:00Z', 'closed', now()) $$,
  '23505', null, '同じグループ・同じ開始日時のボードは作れない');

-- 締切が開始より前のボードは作れない
select throws_ok(
  $$ insert into public.boards (group_id, topic, opens_at, closes_at, status, closed_at)
     values ('10000000-0000-0000-0000-000000000002', '逆転', '2026-12-07T00:00:00Z', '2026-12-01T00:00:00Z', 'closed', now()) $$,
  '23514', null, '締切は開始より後でなければならない');

-- 状態と closed_at は食い違わない
select throws_ok(
  $$ insert into public.boards (group_id, topic, opens_at, closes_at, status)
     values ('10000000-0000-0000-0000-000000000002', '不整合', '2026-10-05T00:00:00Z', '2026-10-12T00:00:00Z', 'closed') $$,
  '23514', null, '終了済みには closed_at が必要');

-- 空白だけのグループ名は保存できない
select throws_ok(
  $$ insert into public.groups (name, created_by, create_request_id)
     values ('   ', '00000000-0000-0000-0000-0000000000a1', gen_random_uuid()) $$,
  '23514', null, '空白だけのグループ名は拒否する');

-- 同じ作成要求の再送で、グループを二重に作れない
select throws_ok(
  $$ insert into public.groups (name, created_by, create_request_id)
     select 'もう一度', created_by, create_request_id from public.groups
     where id = '10000000-0000-0000-0000-000000000001' $$,
  '23505', null, '同じ作成要求IDでは二重に作れない');

-- 装飾の種類は文字・スタンプ・ペンだけ
select throws_ok(
  $$ insert into public.decorations (id, board_id, created_by, kind)
     select gen_random_uuid(), id, '00000000-0000-0000-0000-0000000000a1', 'sticker'
     from public.boards where topic = '今週のお題1' $$,
  '23514', null, '未知の装飾の種類は拒否する');

-- 有効なAPNsトークンは1端末にだけ結び付く
insert into public.devices (installation_id, user_id, apns_token)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', repeat('ab', 32));
select throws_ok(
  $$ insert into public.devices (installation_id, user_id, apns_token)
     values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', repeat('ab', 32)) $$,
  '23505', null, '同じAPNsトークンを2つの端末登録に使えない');

-- Publishable key（anon）からは読めない
set local role anon;
select throws_ok(
  $$ select * from public.boards $$,
  '42501', null, '未ログインではボードを読めない');
reset role;

select * from finish();
rollback;
