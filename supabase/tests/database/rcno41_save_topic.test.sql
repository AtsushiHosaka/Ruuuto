-- RCNO-41 手動のお題変更
-- 定量目標: 成功・非メンバーの拒否・終了済みボードの拒否の3ケース。成功後の開催中のお題が1件。
begin;
select plan(15);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000041a1', 'member1@example.com'),
  ('00000000-0000-0000-0000-0000000041b1', 'member2@example.com'),
  ('00000000-0000-0000-0000-0000000041c1', 'outsider41@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('41000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000041a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('41000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000041a1', 'owner'),
  ('41000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000041b1', 'member');

-- RCNO-4 の48件を外し、このテストのお題だけにする
delete from public.topic_prompts;
insert into public.topic_prompts (id, month, week, body) values
  ('41300000-0000-0000-0000-000000000001', 11, 3, '窓の外');
insert into public.boards (id, group_id, topic, topic_source, prompt_id, opens_at, closes_at, status, closed_at) values
  ('41100000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000001', '紅葉', 'weekly', null,
   now() - interval '14 days', now() - interval '7 days', 'closed', now() - interval '7 days'),
  ('41100000-0000-0000-0000-000000000002', '41000000-0000-0000-0000-000000000001', '窓の外', 'weekly', '41300000-0000-0000-0000-000000000001',
   now() - interval '1 day', now() + interval '6 days', 'open', null);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

-- 成功: owner でない参加者も変更できる
select pg_temp.act_as('00000000-0000-0000-0000-0000000041b1');
select is(
  public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', '  朝ごはん ')::jsonb ->> 'topic',
  '朝ごはん', 'メンバーがお題を変更でき、前後の空白を除いた値を返す');
select is(
  public.ruuuto_current_board('41000000-0000-0000-0000-000000000001')::jsonb ->> 'topic',
  '朝ごはん', '変更後、開催中のボードのお題が変わる');

reset role;
select is(
  (select count(*)::int from public.boards where group_id = '41000000-0000-0000-0000-000000000001' and status = 'open'),
  1, '変更後も開催中のボードは1件（差し替えない）');
select is(
  (select topic_source || ':' || coalesce(prompt_id::text, 'null') from public.boards where id = '41100000-0000-0000-0000-000000000002'),
  'custom:null', '手動変更したボードは custom になり、固定のお題との紐付けを外す');
select is(
  (select count(*)::int from public.notification_events
   where board_id = '41100000-0000-0000-0000-000000000002' and kind = 'topic_changed'
     and topic = '朝ごはん' and actor_id = '00000000-0000-0000-0000-0000000041b1'),
  1, '通知用のイベントが1件記録される');
set local role authenticated;

-- 同じお題での再送は、変更もイベントも増やさない
select pg_temp.act_as('00000000-0000-0000-0000-0000000041a1');
select is(
  public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', '朝ごはん')::jsonb ->> 'topic',
  '朝ごはん', '同じお題の再送は成功する');
reset role;
select is(
  (select count(*)::int from public.notification_events where board_id = '41100000-0000-0000-0000-000000000002'),
  1, '同じお題の再送では通知イベントが増えない');
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000041a1');

-- 不正なお題
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', '   ') $$,
  'RC001', null, '空白だけのお題は RC001');
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', repeat('あ', 81)) $$,
  'RC001', null, '81文字のお題は RC001');

-- 終了済みのボード
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000001', '後から変更') $$,
  'RC002', null, '終了済みのボードは RC002');

-- 非メンバー
select pg_temp.act_as('00000000-0000-0000-0000-0000000041c1');
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', '乗っ取り') $$,
  '42501', null, '非メンバーは 42501');
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000099', '存在しない') $$,
  '42501', null, '存在しないボードも 42501');

-- 締切時刻を過ぎたが、まだ週次切替で閉じていないボード
reset role;
update public.boards set closes_at = now() - interval '1 second', opens_at = now() - interval '7 days'
 where id = '41100000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000041a1');
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', '締切後') $$,
  'RC002', null, '締切時刻を過ぎたボードは、status が open でも RC002');

-- アプリから通知イベントは見えない
select is((select count(*)::int from public.notification_events), 0, '通知イベントはアプリから読めない');

reset role;
set local role anon;
select throws_ok($$ select public.ruuuto_save_topic('41100000-0000-0000-0000-000000000002', 'x') $$,
  '42501', null, 'anon は呼べない');
reset role;

select * from finish();
rollback;
