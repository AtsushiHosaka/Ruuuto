-- RCNO-42 グループ作成と招待参加
-- 定量目標: 2ユーザーで作成、招待参加、参加の再送、無効な招待を各1回。再送で所属が重複しない。
begin;
select plan(24);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000042a1', 'owner@example.com'),
  ('00000000-0000-0000-0000-0000000042b1', 'friend@example.com'),
  ('00000000-0000-0000-0000-0000000042c1', 'outsider@example.com');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- 週の区切り（暫定: 日本時間の月曜0時から7日間）
select is(
  (select opens_at from private.ruuuto_week_window('2026-11-22T12:00:00+09:00')),
  '2026-11-16T00:00:00+09:00'::timestamptz, '日曜の昼は、その週の月曜0時（日本時間）に始まる週');
select is(
  (select closes_at from private.ruuuto_week_window('2026-11-23T00:00:00+09:00')),
  '2026-11-30T00:00:00+09:00'::timestamptz, '月曜0時ちょうどは新しい週。締切は7日後');
select is(
  (select opens_at from private.ruuuto_week_window('2026-11-22T14:59:59Z')),
  '2026-11-16T00:00:00+09:00'::timestamptz, 'バンクーバーの日曜夕方（UTC 14:59）も同じ週');

-- お題の初期データがなければ既定の文言
select is((select topic from private.ruuuto_weekly_prompt('2026-11-16T00:00:00+09:00')), '今週の一枚', 'お題の初期データがなければ既定の文言');
insert into public.topic_prompts (month, week, body) values (11, 3, '窓の外');
select is((select topic from private.ruuuto_weekly_prompt('2026-11-16T00:00:00+09:00')), '窓の外', '11月16日は11月の第3週のお題');

set local role authenticated;

-- 作成（オーナー）
select pg_temp.act_as('00000000-0000-0000-0000-0000000042a1');
select is(public.ruuuto_list_groups()::jsonb, '[]'::jsonb, '最初は所属グループがない');

create temp table created as
  select public.ruuuto_create_group('  えーえす班 ', '42000000-0000-0000-0000-000000000001')::jsonb as g;
select is((select g ->> 'name' from created), 'えーえす班', '作成したグループ名（前後の空白を除く）を返す');

select is(
  public.ruuuto_create_group('えーえす班', '42000000-0000-0000-0000-000000000001')::jsonb,
  (select g from created), '同じ作成要求IDの再送は、前回のグループを返す');

reset role;
select is((select count(*)::int from public.groups where created_by = '00000000-0000-0000-0000-0000000042a1'), 1, '再送してもグループは1件');
select is(
  (select role from public.group_members where group_id = (select (g ->> 'id')::uuid from created)),
  'owner', '作成者は owner として所属する');
select is(
  (select count(*)::int from public.boards where group_id = (select (g ->> 'id')::uuid from created) and status = 'open'),
  1, '作成と同時に開催中のボードが1件できる');
select ok(
  (select opens_at <= now() and closes_at > now() from public.boards where group_id = (select (g ->> 'id')::uuid from created)),
  '最初のボードは今週の期間');
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000042a1');

select throws_ok(
  $$ select public.ruuuto_create_group('   ', gen_random_uuid()) $$,
  'RC006', null, '空白だけのグループ名は RC006');
select throws_ok(
  $$ select public.ruuuto_create_group(repeat('あ', 41), gen_random_uuid()) $$,
  'RC006', null, '41文字のグループ名は RC006');

-- 招待を発行する
create temp table issued as
  select public.ruuuto_issue_invitation((select (g ->> 'id')::uuid from created))::jsonb as i;
select ok((select (i ->> 'token') ~ '^[A-Za-z0-9_-]{43}$' from issued), 'トークンはURLで使える43文字');

-- 所属していない人は招待を発行できない
select pg_temp.act_as('00000000-0000-0000-0000-0000000042c1');
select throws_ok(
  format('select public.ruuuto_issue_invitation(%L)', (select g ->> 'id' from created)),
  '42501', null, '非メンバーは招待を発行できない');

-- 友達が招待で参加する
select pg_temp.act_as('00000000-0000-0000-0000-0000000042b1');
select is(
  public.ruuuto_accept_invitation((select i ->> 'token' from issued))::jsonb,
  jsonb_build_object('group_id', (select g ->> 'id' from created), 'joined', true),
  '招待で参加すると group_id と joined = true を返す');
select is(
  public.ruuuto_accept_invitation((select i ->> 'token' from issued))::jsonb ->> 'joined',
  'false', '参加の再送は成功し joined = false');
select is(
  (select json_agg(x ->> 'name')::jsonb from json_array_elements(public.ruuuto_list_groups()) x),
  '["えーえす班"]'::jsonb, '参加したグループが一覧に出る');

reset role;
select is(
  (select count(*)::int from public.group_members where user_id = '00000000-0000-0000-0000-0000000042b1'),
  1, '参加を再送しても所属は1件');
-- 期限切れと取り消し済みの招待を用意する
insert into public.invitations (group_id, token_hash, created_by, expires_at, created_at)
values ((select (g ->> 'id')::uuid from created), extensions.digest('expired-token', 'sha256'),
        '00000000-0000-0000-0000-0000000042a1', now() - interval '1 day', now() - interval '8 days');
insert into public.invitations (group_id, token_hash, created_by, expires_at, revoked_at)
values ((select (g ->> 'id')::uuid from created), extensions.digest('revoked-token', 'sha256'),
        '00000000-0000-0000-0000-0000000042a1', now() + interval '7 days', now());
set local role authenticated;

select pg_temp.act_as('00000000-0000-0000-0000-0000000042c1');
select throws_ok($$ select public.ruuuto_accept_invitation('no-such-token') $$, 'RC003', null, '存在しない招待は RC003');
select throws_ok($$ select public.ruuuto_accept_invitation('revoked-token') $$, 'RC003', null, '取り消した招待は RC003');
select throws_ok($$ select public.ruuuto_accept_invitation('expired-token') $$, 'RC004', null, '期限切れの招待は RC004');

-- 未ログインは呼べない
reset role;
set local role anon;
select throws_ok($$ select public.ruuuto_list_groups() $$, '42501', null, 'anon は所属一覧を呼べない');
reset role;

select * from finish();
rollback;
