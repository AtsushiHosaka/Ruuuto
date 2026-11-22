-- RCNO-42 招待の一覧と取り消し
-- 定量目標: オーナーは全部、メンバーは自分の招待だけを一覧・取り消しでき、取り消した招待では参加できない（RC003）。
begin;
select plan(17);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000f4a1', 'owner-rv@example.com'),
  ('00000000-0000-0000-0000-00000000f4b1', 'member-rv@example.com'),
  ('00000000-0000-0000-0000-00000000f4c1', 'outsider-rv@example.com'),
  ('00000000-0000-0000-0000-00000000f4d1', 'joiner-rv@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('f4000000-0000-0000-0000-000000000001', '取り消し班', '00000000-0000-0000-0000-00000000f4a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('f4000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000f4a1', 'owner'),
  ('f4000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000f4b1', 'member');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create temp table inv (who text primary key, i jsonb);
grant select, insert on inv to authenticated;
set local role authenticated;

select pg_temp.act_as('00000000-0000-0000-0000-00000000f4a1');
insert into inv select 'owner_never', public.ruuuto_issue_invitation('f4000000-0000-0000-0000-000000000001', 'never')::jsonb;
select ok((select i ? 'id' from inv where who = 'owner_never'), '発行すると招待のIDも返す');

select pg_temp.act_as('00000000-0000-0000-0000-00000000f4b1');
insert into inv select 'member_1h', public.ruuuto_issue_invitation('f4000000-0000-0000-0000-000000000001', '1h')::jsonb;
insert into inv select 'member_7d', public.ruuuto_issue_invitation('f4000000-0000-0000-0000-000000000001')::jsonb;

-- 一覧
select is(json_array_length(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')), 2,
  'メンバーは自分の招待だけが見える');
select pg_temp.act_as('00000000-0000-0000-0000-00000000f4a1');
select is(json_array_length(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')), 3,
  'オーナーはグループの全部の招待が見える');
select is(
  (select e ->> 'expires_in' from json_array_elements(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')) e
    where e ->> 'id' = (select i ->> 'id' from inv where who = 'owner_never')),
  'never', '一覧に選んだ期限が出る');
select ok(
  (select bool_and(not (e::jsonb ? 'token')) from json_array_elements(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')) e),
  '一覧にトークンは出ない');
select pg_temp.act_as('00000000-0000-0000-0000-00000000f4c1');
select throws_ok($$ select public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001') $$,
  '42501', null, '非メンバーは一覧を見られない');

-- 取り消し: 権限
select throws_ok(format('select public.ruuuto_revoke_invitation(%L)', (select i ->> 'id' from inv where who = 'member_1h')),
  '42501', null, '非メンバーは取り消せない');
select pg_temp.act_as('00000000-0000-0000-0000-00000000f4b1');
select throws_ok(format('select public.ruuuto_revoke_invitation(%L)', (select i ->> 'id' from inv where who = 'owner_never')),
  '42501', null, 'メンバーは他の人の招待を取り消せない');
select throws_ok($$ select public.ruuuto_revoke_invitation(gen_random_uuid()) $$,
  '42501', null, '存在しない招待も 42501（あるかどうかを見せない）');

-- メンバーが自分の招待を取り消す
select ok(public.ruuuto_revoke_invitation((select (i ->> 'id')::uuid from inv where who = 'member_1h'))::jsonb ->> 'revoked_at' is not null,
  'メンバーは自分の招待を取り消せる');
select is(
  public.ruuuto_revoke_invitation((select (i ->> 'id')::uuid from inv where who = 'member_1h'))::jsonb ->> 'id',
  (select i ->> 'id' from inv where who = 'member_1h'), '取り消しの送り直しも成功する');
select is(json_array_length(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')), 1,
  '取り消した招待は一覧から消える');

-- オーナーがメンバーの招待と無期限の招待を取り消す
select pg_temp.act_as('00000000-0000-0000-0000-00000000f4a1');
select ok(public.ruuuto_revoke_invitation((select (i ->> 'id')::uuid from inv where who = 'member_7d'))::jsonb ->> 'revoked_at' is not null,
  'オーナーはメンバーの招待を取り消せる');
select ok(public.ruuuto_revoke_invitation((select (i ->> 'id')::uuid from inv where who = 'owner_never'))::jsonb ->> 'revoked_at' is not null,
  'オーナーは無期限の招待を取り消せる');
select is(json_array_length(public.ruuuto_list_invitations('f4000000-0000-0000-0000-000000000001')), 0,
  '全部取り消すと一覧は空');

-- 取り消した招待では参加できない
select pg_temp.act_as('00000000-0000-0000-0000-00000000f4d1');
select throws_ok(format('select public.ruuuto_accept_invitation(%L)', (select i ->> 'token' from inv where who = 'owner_never')),
  'RC003', null, '取り消した無期限の招待では参加できない（RC003）');
reset role;

set local role anon;
select throws_ok($$ select public.ruuuto_revoke_invitation(gen_random_uuid()) $$, '42501', null, 'anon は取り消せない');
reset role;

select * from finish();
rollback;
