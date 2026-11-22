-- RCNO-37 プッシュの配信処理と無効な端末登録の処理
-- 定量目標: 端末登録（登録・更新・アカウント切替・解除・不正な入力・未ログイン）、
-- 配信行の一意性、受け取りと結果の記録、無効な端末の除外、再送の間隔、管理用RPCの権限。
-- トークンは試験用の明らかな偽物（同じ文字の繰り返し）を使う。
begin;
select plan(53);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000037a1', 'push-a@example.com'),
  ('00000000-0000-0000-0000-0000000037b1', 'push-b@example.com'),
  ('00000000-0000-0000-0000-0000000037c1', 'push-c@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('37000000-0000-0000-0000-000000000001', '通知の班', '00000000-0000-0000-0000-0000000037a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('37000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000037a1', 'owner'),
  ('37000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000037b1', 'member');
insert into public.boards (id, group_id, topic, opens_at, closes_at) values
  ('37100000-0000-0000-0000-000000000001', '37000000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- ===== 端末登録 =====
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000037a1');

select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000001', repeat('a', 64))::jsonb,
  '{"installation_id": "37200000-0000-0000-0000-000000000001", "enabled": true,
    "environment": "production", "locale": null}'::jsonb,
  '登録: iOS と同じ2つの引数で登録でき、環境は production になる');
select is(
  (select user_id::text || ' ' || apns_token from public.devices where installation_id = '37200000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-0000000037a1 ' || repeat('a', 64), '登録: 自分の端末として保存される');

select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000001', upper(repeat('ab', 32)), 'sandbox', 'en-US')::jsonb,
  '{"installation_id": "37200000-0000-0000-0000-000000000001", "enabled": true,
    "environment": "sandbox", "locale": "en-US"}'::jsonb,
  '更新: トークン・環境・言語を変えられる');
select is(
  (select apns_token from public.devices where installation_id = '37200000-0000-0000-0000-000000000001'),
  repeat('ab', 32), '更新: トークンは小文字で保存される');
select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000001', repeat('ab', 32))::jsonb ->> 'environment',
  'sandbox', '更新: 環境と言語を省くと前回の値が残る');

-- 同じトークンがほかのインストールに残っていたら外す（再インストール）
select lives_ok(
  $$ select public.ruuuto_sync_device('37200000-0000-0000-0000-000000000002', repeat('ab', 32), 'sandbox', 'ja') $$,
  '再インストール: 同じトークンを新しいインストールで登録できる');
select is(
  (select apns_token from public.devices where installation_id = '37200000-0000-0000-0000-000000000001'),
  null, '再インストール: 古いインストールからはトークンが外れる');

-- アカウント切替: 同じ端末で B がログインし直す
select pg_temp.act_as('00000000-0000-0000-0000-0000000037b1');
select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000002', repeat('ab', 32))::jsonb ->> 'enabled',
  'true', 'アカウント切替: 別の利用者が同じインストールを登録できる');
select is(
  (select count(*)::int from public.devices where installation_id = '37200000-0000-0000-0000-000000000002'
     and user_id = '00000000-0000-0000-0000-0000000037b1'),
  1, 'アカウント切替: 端末は呼んだ利用者に移る（B から見える）');
select pg_temp.act_as('00000000-0000-0000-0000-0000000037a1');
select is(
  (select count(*)::int from public.devices where installation_id = '37200000-0000-0000-0000-000000000002'),
  0, 'アカウント切替: 前の利用者 A からは見えなくなる');

-- 解除
select pg_temp.act_as('00000000-0000-0000-0000-0000000037b1');
select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000002', null)::jsonb ->> 'enabled',
  'false', '解除: トークン null で通知を止める');
select is(
  (select apns_token from public.devices where installation_id = '37200000-0000-0000-0000-000000000002'),
  null, '解除: トークンが消える');
select lives_ok(
  $$ select public.ruuuto_sync_device('37200000-0000-0000-0000-000000000002', repeat('ab', 32)) $$, '解除後に登録し直せる');
select is(
  public.ruuuto_sync_device('37200000-0000-0000-0000-000000000002', repeat('ab', 32), null, null, false)::jsonb ->> 'enabled',
  'false', '解除: p_enabled = false でも止まる');

-- 不正な入力（RC015）
select throws_ok($$ select public.ruuuto_sync_device(null, repeat('a', 64)) $$, 'RC015', null, 'インストールIDがない');
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), 'xyz') $$, 'RC015', null, '16進でないトークン');
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), repeat('a', 63)) $$, 'RC015', null, '短すぎるトークン');
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), '') $$, 'RC015', null, '空のトークン');
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), repeat('a', 64), 'development') $$, 'RC015', null, '不明な環境');
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), repeat('a', 64), null, 'ja; drop') $$, 'RC015', null, '不正な言語');

-- 未ログイン
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), repeat('c', 64)) $$, '42501', null, 'ログインしていないと登録できない');
set local role anon;
select throws_ok($$ select public.ruuuto_sync_device(gen_random_uuid(), repeat('c', 64)) $$, '42501', null, 'anon は登録できない');

-- アプリからは配信行・管理用RPCに触れない
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000037a1');
select throws_ok($$ select count(*) from public.notification_deliveries $$, '42501', null, 'アプリから配信行は読めない');
select throws_ok($$ select public.ruuuto_admin_push_fanout() $$, '42501', null, 'アプリから fanout は呼べない');
select throws_ok($$ select public.ruuuto_admin_push_claim(10) $$, '42501', null, 'アプリから claim は呼べない');
select throws_ok($$ select public.ruuuto_admin_push_record('[]') $$, '42501', null, 'アプリから record は呼べない');
select throws_ok($$ select private.ruuuto_request_push_dispatch() $$, '42501', null, 'アプリから配信の起動はできない');

-- ===== 配信行 =====
reset role;
-- 送り先: A の端末（production）、B の端末（sandbox）、グループ外の C の端末
delete from public.devices;
insert into public.devices (installation_id, user_id, apns_token, environment, locale) values
  ('37300000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000037a1', repeat('1', 64), 'production', 'ja'),
  ('37300000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000037b1', repeat('2', 64), 'sandbox', 'en'),
  ('37300000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-0000000037c1', repeat('3', 64), 'production', null);
insert into public.notification_events (id, kind, group_id, board_id, topic) values
  ('37400000-0000-0000-0000-000000000001', 'topic_published', '37000000-0000-0000-0000-000000000001',
   '37100000-0000-0000-0000-000000000001', '窓の外');
insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
  ('37400000-0000-0000-0000-000000000001', '37300000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000037a1', '今週のお題', '窓の外'),
  ('37400000-0000-0000-0000-000000000001', '37300000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000037b1', 'This week''s topic', '窓の外');

select throws_ok(
  $$ insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
     ('37400000-0000-0000-0000-000000000001', '37300000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000037a1', 'x', 'x') $$,
  '23505', null, '同じイベントを同じ端末へ送る行は1つだけ');

set local role service_role;
select lives_ok($$ select public.ruuuto_admin_push_fanout() $$, 'fanout を呼べる（中身は RCNO-9）');
select is((select count(*)::int from public.notification_deliveries), 2, 'fanout は既にある配信行を重複させない');

create temp table claim1 as select public.ruuuto_admin_push_claim(10)::jsonb as c;
select is(jsonb_array_length((select c from claim1)), 2, '受け取り: 送る時刻の2件を受け取る');
select is(
  (select (c -> 0) - 'id' from claim1),
  jsonb_build_object('event_id', '37400000-0000-0000-0000-000000000001', 'kind', 'topic_published',
    'group_id', '37000000-0000-0000-0000-000000000001', 'board_id', '37100000-0000-0000-0000-000000000001',
    'title', '今週のお題', 'body', '窓の外', 'apns_token', repeat('1', 64),
    'environment', 'production', 'attempts', 1),
  '受け取り: 送るのに必要な値（トークン・環境・文面・遷移先）がそろう');
select is((select c -> 1 ->> 'environment' from claim1), 'sandbox', '受け取り: 端末ごとの環境が返る');
select is(
  (select array_agg(distinct status) from public.notification_deliveries), array['sending'],
  '受け取り: 受け取った行は送信中になる');
select is(public.ruuuto_admin_push_claim(10)::jsonb, '[]'::jsonb, '受け取り: 送信中の行は二重に受け取らない');

-- 結果の記録: A は成功、B は一時的なエラー
select is(
  public.ruuuto_admin_push_record(jsonb_build_array(
    jsonb_build_object('id', (select c -> 0 ->> 'id' from claim1), 'outcome', 'sent', 'status_code', 200, 'apns_id', 'test-apns-id'),
    jsonb_build_object('id', (select c -> 1 ->> 'id' from claim1), 'outcome', 'retry', 'status_code', 429, 'reason', 'TooManyRequests')
  ))::jsonb,
  '{"sent": 1, "retry": 1, "invalid": 0, "failed": 0}'::jsonb, '記録: 成功1件・再送1件');
select is(
  (select status || ' ' || apns_id || ' ' || (sent_at is not null)::text from public.notification_deliveries
    where device_id = '37300000-0000-0000-0000-00000000000a'),
  'sent test-apns-id true', '記録: 成功は sent');
select is(
  (select status || ' ' || attempts || ' ' || (next_attempt_at - now())::text || ' ' || last_reason
     from public.notification_deliveries where device_id = '37300000-0000-0000-0000-00000000000b'),
  'pending 1 00:01:00 TooManyRequests', '再送: 1回目の失敗は1分後に送り直す');
select is(public.ruuuto_admin_push_claim(10)::jsonb, '[]'::jsonb, '再送: 時刻が来るまでは受け取らない');
select is(
  public.ruuuto_admin_push_record(jsonb_build_array(
    jsonb_build_object('id', (select c -> 0 ->> 'id' from claim1), 'outcome', 'failed')))::jsonb ->> 'failed',
  '0', '記録: 送信中でない行の結果は上書きしない');

reset role;
update public.notification_deliveries set next_attempt_at = now() - interval '1 second'
 where device_id = '37300000-0000-0000-0000-00000000000b';
set local role service_role;
create temp table claim2 as select public.ruuuto_admin_push_claim(10)::jsonb as c;
select is((select c -> 0 ->> 'attempts' from claim2), '2', '再送: 時刻が来たら2回目として受け取る');
select public.ruuuto_admin_push_record(jsonb_build_array(
  jsonb_build_object('id', (select c -> 0 ->> 'id' from claim2), 'outcome', 'retry', 'status_code', 503)));
select is(
  (select (next_attempt_at - now())::text from public.notification_deliveries where device_id = '37300000-0000-0000-0000-00000000000b'),
  '00:05:00', '再送: 2回目の失敗は5分後');

-- 5回目の失敗で failed
reset role;
update public.notification_deliveries set next_attempt_at = now() - interval '1 second', attempts = 4
 where device_id = '37300000-0000-0000-0000-00000000000b';
set local role service_role;
create temp table claim3 as select public.ruuuto_admin_push_claim(10)::jsonb as c;
select is(
  public.ruuuto_admin_push_record(jsonb_build_array(
    jsonb_build_object('id', (select c -> 0 ->> 'id' from claim3), 'outcome', 'retry', 'status_code', 500)))::jsonb ->> 'failed',
  '1', '再送: 5回失敗したら failed にする');
select is(
  (select status from public.notification_deliveries where device_id = '37300000-0000-0000-0000-00000000000b'),
  'failed', '再送: failed の行はもう受け取らない');

-- 無効な端末: 410 で無効にし、次のイベントでは送らない
reset role;
insert into public.notification_events (id, kind, group_id, board_id, topic) values
  ('37400000-0000-0000-0000-000000000002', 'topic_changed', '37000000-0000-0000-0000-000000000001',
   '37100000-0000-0000-0000-000000000001', '雨の日'),
  ('37400000-0000-0000-0000-000000000003', 'topic_changed', '37000000-0000-0000-0000-000000000001',
   '37100000-0000-0000-0000-000000000001', '夕焼け');
insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
  ('37400000-0000-0000-0000-000000000002', '37300000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000037a1', 't', 'b');
set local role service_role;
create temp table claim4 as select public.ruuuto_admin_push_claim(10)::jsonb as c;
select is(
  public.ruuuto_admin_push_record(jsonb_build_array(
    jsonb_build_object('id', (select c -> 0 ->> 'id' from claim4), 'outcome', 'invalid', 'status_code', 410, 'reason', 'Unregistered')))::jsonb ->> 'invalid',
  '1', '無効: 410 は invalid として記録する');
select isnt(
  (select invalidated_at from public.devices where installation_id = '37300000-0000-0000-0000-00000000000a'),
  null, '無効: 端末登録に無効の印が付く');

reset role;
insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
  ('37400000-0000-0000-0000-000000000003', '37300000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000037a1', 't', 'b');
set local role service_role;
select is(public.ruuuto_admin_push_claim(10)::jsonb, '[]'::jsonb, '無効: 次のイベントでは無効な端末へ送らない');
select is(
  (select status || ' ' || last_reason from public.notification_deliveries
    where event_id = '37400000-0000-0000-0000-000000000003'),
  'skipped DeviceUnavailable', '無効: その行は skipped になる');

-- 送る前に端末が別の人へ移った・グループを抜けた・古すぎる行は送らない
reset role;
update public.devices set user_id = '00000000-0000-0000-0000-0000000037a1'
 where installation_id = '37300000-0000-0000-0000-00000000000b';
insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
  ('37400000-0000-0000-0000-000000000003', '37300000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000037b1', 't', 'b'),
  ('37400000-0000-0000-0000-000000000003', '37300000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-0000000037c1', 't', 'b');
set local role service_role;
select is(public.ruuuto_admin_push_claim(10)::jsonb, '[]'::jsonb, '別の人へ移った端末・グループ外の人の端末へは送らない');

reset role;
insert into public.devices (installation_id, user_id, apns_token) values
  ('37300000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-0000000037b1', repeat('4', 64));
insert into public.notification_events (id, kind, group_id, board_id, topic, created_at) values
  ('37400000-0000-0000-0000-000000000004', 'topic_published', '37000000-0000-0000-0000-000000000001',
   '37100000-0000-0000-0000-000000000001', '古い', now() - interval '7 hours');
insert into public.notification_deliveries (event_id, device_id, user_id, title, body) values
  ('37400000-0000-0000-0000-000000000004', '37300000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-0000000037b1', 't', 'b');
set local role service_role;
select is(public.ruuuto_admin_push_claim(10)::jsonb, '[]'::jsonb, '6時間を過ぎたイベントは送らない');
select is(
  (select last_reason from public.notification_deliveries where event_id = '37400000-0000-0000-0000-000000000004'),
  'Expired', '古いイベントの行は Expired で skipped');

-- 送信中のまま止まった行は10分後に受け取り直す
reset role;
insert into public.notification_deliveries (event_id, device_id, user_id, title, body, status, attempts, updated_at) values
  ('37400000-0000-0000-0000-000000000002', '37300000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-0000000037b1',
   't', 'b', 'sending', 1, now() - interval '11 minutes');
set local role service_role;
select is(
  public.ruuuto_admin_push_claim(10)::jsonb -> 0 ->> 'attempts', '2', '止まった送信中の行を受け取り直す');

-- Cron
reset role;
select is(
  (select schedule || ' ' || command from cron.job where jobname = 'ruuuto-push-dispatch'),
  '* * * * * select private.ruuuto_request_push_dispatch()', 'Cronに1分ごとの配信ジョブが登録されている');

select * from finish();
rollback;
