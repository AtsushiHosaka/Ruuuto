-- RCNO-5 所属メンバーが読むテーブルにSELECT権限を付ける
-- M: グループの所属者、N: どこにも所属していない
begin;
select plan(40);

-- 読み取りのRLSポリシーがあり、authenticated に SELECT を付けるテーブル
create temp table member_readable (tbl text primary key) on commit drop;
insert into member_readable values
  ('public.profiles'), ('public.groups'), ('public.group_members'), ('public.topic_prompts'),
  ('public.boards'), ('public.photos'), ('public.decorations'), ('public.devices');
-- SELECT を付けないテーブル（RPCとサーバー処理からだけ使う）
create temp table server_only (tbl text primary key) on commit drop;
insert into server_only values
  ('public.invitations'), ('public.notification_events'), ('public.notification_deliveries');

-- RLSはRuuutoの全テーブルで有効
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
  null, 'public の全テーブルでRLSが有効');
select is(
  (select count(*)::int from pg_class c
   where c.oid in (select tbl::regclass from member_readable union all select tbl::regclass from server_only)
     and c.relrowsecurity),
  11, 'Ruuutoの11テーブルすべてでRLSが有効');

-- 権限の一覧
select ok(
  (select bool_and(has_table_privilege('authenticated', tbl, 'select')) from member_readable),
  'authenticated: 所属メンバーが読むテーブルにSELECT権限がある');
select ok(
  (select bool_and(not has_table_privilege('authenticated', tbl, 'select')) from server_only),
  'authenticated: 招待・通知のテーブルにはSELECT権限がない');
select ok(
  (select bool_and(not has_table_privilege('authenticated', tbl, p))
   from (select tbl from member_readable union all select tbl from server_only) t,
        unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger', 'maintain']) p),
  'authenticated: どのテーブルにも書き込み系の権限がない');
select ok(
  (select bool_and(not has_table_privilege('anon', tbl, p))
   from (select tbl from member_readable union all select tbl from server_only) t,
        unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger', 'maintain']) p),
  'anon: どのテーブルにも権限がない');

-- テストデータ
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a5a1', 'grants-m@example.com'),
  ('00000000-0000-0000-0000-00000000a5b1', 'grants-n@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('a5000000-0000-0000-0000-000000000001', '権限グループ', '00000000-0000-0000-0000-00000000a5a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('a5000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a5a1', 'owner');
insert into public.boards (id, group_id, topic, opens_at, closes_at) values
  ('a5100000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001', 'お題', now() - interval '1 day', now() + interval '6 days');
insert into public.photos (id, board_id, posted_by, storage_path, status) values
  ('a5200000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a5a1', 'grants/posted.jpg', 'posted');
insert into public.decorations (id, board_id, created_by, kind, content) values
  ('a5300000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a5a1', 'stamp', '{"stamp": "snow"}');
insert into public.devices (installation_id, user_id, apns_token) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000a5a1', repeat('a5', 32));

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated, anon;

create function pg_temp.visible_rows(p_tbl text) returns int language plpgsql as $$
declare v int;
begin
  execute format('select count(*)::int from %s', p_tbl) into v;
  return v;
end;
$$;
grant execute on function pg_temp.visible_rows(text) to authenticated, anon;

set local role authenticated;

-- M（所属者）は自分のグループの行を読める
select pg_temp.act_as('00000000-0000-0000-0000-00000000a5a1');
select is(pg_temp.visible_rows('public.groups'), 1, 'M: 所属グループを読める');
select is(pg_temp.visible_rows('public.group_members'), 1, 'M: 所属グループの参加者を読める');
select is(pg_temp.visible_rows('public.profiles'), 1, 'M: 自分のプロフィールを読める');
select is(pg_temp.visible_rows('public.boards'), 1, 'M: 所属グループのボードを読める');
select is(pg_temp.visible_rows('public.photos'), 1, 'M: 所属グループの写真を読める');
select is(pg_temp.visible_rows('public.decorations'), 1, 'M: 所属グループの装飾を読める');
select is(pg_temp.visible_rows('public.devices'), 1, 'M: 自分の端末を読める');
select ok(pg_temp.visible_rows('public.topic_prompts') > 0, 'M: 固定のお題を読める');
select throws_ok($$ select pg_temp.visible_rows('public.invitations') $$, '42501', null, 'M: 招待テーブルは直接読めない');
select throws_ok($$ select pg_temp.visible_rows('public.notification_events') $$, '42501', null, 'M: 通知イベントは直接読めない');
select throws_ok($$ select pg_temp.visible_rows('public.notification_deliveries') $$, '42501', null, 'M: 通知の配信記録は直接読めない');

-- N（非メンバー）は権限エラーにならず、所属グループの行は0件
select pg_temp.act_as('00000000-0000-0000-0000-00000000a5b1');
select is(pg_temp.visible_rows('public.groups'), 0, 'N: グループは0件');
select is(pg_temp.visible_rows('public.group_members'), 0, 'N: 参加者は0件');
select is(pg_temp.visible_rows('public.boards'), 0, 'N: ボードは0件');
select is(pg_temp.visible_rows('public.photos'), 0, 'N: 写真は0件');
select is(pg_temp.visible_rows('public.decorations'), 0, 'N: 装飾は0件');
select is(pg_temp.visible_rows('public.devices'), 0, 'N: 他人の端末は0件');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000a5a1'),
  0, 'N: グループを共有しない M のプロフィールは0件');
select is(pg_temp.visible_rows('public.profiles'), 1, 'N: 見えるプロフィールは自分だけ');
select ok(pg_temp.visible_rows('public.topic_prompts') > 0, 'N: 固定のお題はグループに関係なく読める');

-- 書き込みは所属者でもできない
select pg_temp.act_as('00000000-0000-0000-0000-00000000a5a1');
select throws_ok($$ update public.groups set name = '変更' $$, '42501', null, 'M: グループを直接変更できない');
select throws_ok($$ delete from public.photos $$, '42501', null, 'M: 写真を直接消せない');
select throws_ok($$ truncate public.decorations $$, '42501', null, 'M: 装飾をTRUNCATEできない');
select throws_ok($$ truncate public.notification_events $$, '42501', null, 'M: 通知イベントをTRUNCATEできない');
select throws_ok(
  $$ insert into public.notification_events (kind, group_id, board_id, topic)
     values ('topic_changed', 'a5000000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000001', 'お題') $$,
  '42501', null, 'M: 通知イベントを直接追加できない');

-- anon はどのテーブルも読めない
reset role;
set local role anon;
select throws_ok($$ select pg_temp.visible_rows('public.profiles') $$, '42501', null, 'anon: プロフィールを読めない');
select throws_ok($$ select pg_temp.visible_rows('public.groups') $$, '42501', null, 'anon: グループを読めない');
select throws_ok($$ select pg_temp.visible_rows('public.group_members') $$, '42501', null, 'anon: 参加者を読めない');
select throws_ok($$ select pg_temp.visible_rows('public.topic_prompts') $$, '42501', null, 'anon: お題を読めない');
select throws_ok($$ select pg_temp.visible_rows('public.boards') $$, '42501', null, 'anon: ボードを読めない');
select throws_ok($$ select pg_temp.visible_rows('public.photos') $$, '42501', null, 'anon: 写真を読めない');
select throws_ok($$ select pg_temp.visible_rows('public.decorations') $$, '42501', null, 'anon: 装飾を読めない');
select throws_ok($$ select pg_temp.visible_rows('public.devices') $$, '42501', null, 'anon: 端末を読めない');
select throws_ok($$ select pg_temp.visible_rows('public.notification_events') $$, '42501', null, 'anon: 通知イベントを読めない');
reset role;

select * from finish();
rollback;
