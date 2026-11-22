-- RCNO-42 招待の有効期限を選べる
-- 定量目標: 7つの期限がそれぞれの長さになり、未指定は7日、無期限は期限切れにならず、不正な値は RC011。
begin;
select plan(14);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000e4a1', 'owner-exp@example.com'),
  ('00000000-0000-0000-0000-00000000e4b1', 'joiner-exp@example.com'),
  ('00000000-0000-0000-0000-00000000e4c1', 'outsider-exp@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('e4000000-0000-0000-0000-000000000001', '期限班', '00000000-0000-0000-0000-00000000e4a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('e4000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000e4a1', 'owner');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- 発行から期限までの秒数
create function pg_temp.lifetime(p_expires_in text) returns int language sql as $$
  select extract(epoch from (
    (public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', p_expires_in)::jsonb ->> 'expires_at')::timestamptz
    - date_trunc('second', now())))::int;
$$;

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000e4a1');

select is(pg_temp.lifetime('30m'), 1800, '30分');
select is(pg_temp.lifetime('1h'), 3600, '1時間');
select is(pg_temp.lifetime('6h'), 21600, '6時間');
select is(pg_temp.lifetime('12h'), 43200, '12時間');
select is(pg_temp.lifetime('1d'), 86400, '1日');
select is(pg_temp.lifetime('7d'), 604800, '7日');
select is(
  extract(epoch from ((public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001')::jsonb ->> 'expires_at')::timestamptz
    - date_trunc('second', now())))::int,
  604800, '期限を送らなければ7日（今のiOSの呼び出し）');

create temp table never_inv as
  select public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', 'never')::jsonb as i;
grant select on never_inv to authenticated;
select is((select i -> 'expires_at' from never_inv), 'null'::jsonb, '無期限は expires_at が null');
select is((select i ->> 'expires_in' from never_inv), 'never', '選んだ期限を返す');

select throws_ok(
  $$ select public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', '3d') $$,
  'RC011', null, '選べない期限は RC011');
select pg_temp.act_as('00000000-0000-0000-0000-00000000e4c1');
select throws_ok(
  $$ select public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', 'never') $$,
  '42501', null, '非メンバーは期限を選んでも発行できない');

-- 無期限の招待は、ずっと先でも参加できる（作成日時を1年前にずらして確かめる）
reset role;
update public.invitations set created_at = now() - interval '365 days'
 where token_hash = extensions.digest((select i ->> 'token' from never_inv), 'sha256');
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000e4b1');
select is(
  public.ruuuto_accept_invitation((select i ->> 'token' from never_inv))::jsonb ->> 'joined',
  'true', '1年前の無期限の招待でも参加できる');

-- 30分の招待は、期限を過ぎると RC004
reset role;
create temp table short_inv (token text);
grant select, insert on short_inv to authenticated;
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000e4a1');
insert into short_inv select public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', '30m')::jsonb ->> 'token';
reset role;
update public.invitations set created_at = now() - interval '31 minutes', expires_at = now() - interval '1 minute'
 where token_hash = extensions.digest((select token from short_inv), 'sha256');
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000e4c1');
select throws_ok(
  format('select public.ruuuto_accept_invitation(%L)', (select token from short_inv)),
  'RC004', null, '30分を過ぎた招待は RC004');
reset role;

set local role anon;
select throws_ok(
  $$ select public.ruuuto_issue_invitation('e4000000-0000-0000-0000-000000000001', '1h') $$,
  '42501', null, 'anon は発行できない');
reset role;

select * from finish();
rollback;
