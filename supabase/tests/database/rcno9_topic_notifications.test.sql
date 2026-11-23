-- RCNO-9 お題変更をプッシュで知らせる
-- 定量目標: 週の切替は所属メンバーの端末ごとに1件、手動の変更は本人を除く、
-- 短時間の3回の変更は最後の1回だけを2分後に送る、再実行しても増えない、
-- 無効・解除した端末と抜けたメンバーには送らない、ja / en / それ以外の文面、
-- グループごとの通知設定（既定オン・オフで止まる・オンで戻る・ほかのグループは届く）。
begin;
select plan(39);

-- A ja / B en-US / C fr / D 言語なし / E 無効な端末 / F 解除した端末 / G 抜けた人 / H 2グループに所属
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000009a1', 'n9-a@example.com'),
  ('00000000-0000-0000-0000-0000000009b1', 'n9-b@example.com'),
  ('00000000-0000-0000-0000-0000000009c1', 'n9-c@example.com'),
  ('00000000-0000-0000-0000-0000000009d1', 'n9-d@example.com'),
  ('00000000-0000-0000-0000-0000000009e1', 'n9-e@example.com'),
  ('00000000-0000-0000-0000-0000000009f1', 'n9-f@example.com'),
  ('00000000-0000-0000-0000-000000000901', 'n9-g@example.com'),
  ('00000000-0000-0000-0000-000000000911', 'n9-h@example.com'),
  ('00000000-0000-0000-0000-000000000921', 'n9-x@example.com');
update public.profiles set display_name = 'あゆむ' where id = '00000000-0000-0000-0000-0000000009a1';
update public.profiles set display_name = 'Bob' where id = '00000000-0000-0000-0000-0000000009b1';

insert into public.groups (id, name, created_by, create_request_id) values
  ('09000000-0000-0000-0000-000000000001', '班1', '00000000-0000-0000-0000-0000000009a1', gen_random_uuid()),
  ('09000000-0000-0000-0000-000000000002', '班2', '00000000-0000-0000-0000-0000000009a1', gen_random_uuid());
insert into public.group_members (group_id, user_id, joined_at)
select '09000000-0000-0000-0000-000000000001', u, now() - interval '1 day'
from unnest(array[
  '00000000-0000-0000-0000-0000000009a1', '00000000-0000-0000-0000-0000000009b1',
  '00000000-0000-0000-0000-0000000009c1', '00000000-0000-0000-0000-0000000009d1',
  '00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009f1',
  '00000000-0000-0000-0000-000000000911']::uuid[]) u;
insert into public.group_members (group_id, user_id) values
  ('09000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000009a1'),
  ('09000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000911');

insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('09100000-0000-0000-0000-000000000001', '09000000-0000-0000-0000-000000000001', '窓の外', now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('09100000-0000-0000-0000-000000000002', '09000000-0000-0000-0000-000000000002', '窓の外', now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('09100000-0000-0000-0000-000000000003', '09000000-0000-0000-0000-000000000001', '先週', now() - interval '8 days', now() - interval '1 day', 'closed', now() - interval '1 day');

insert into public.devices (installation_id, user_id, apns_token, environment, locale, invalidated_at) values
  ('09200000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000009a1', repeat('a', 64), 'production', 'ja', null),
  ('09200000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000009b1', repeat('b', 64), 'production', 'en-US', null),
  ('09200000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-0000000009c1', repeat('c', 64), 'production', 'fr', null),
  ('09200000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-0000000009d1', repeat('d', 64), 'sandbox', null, null),
  ('09200000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-0000000009e1', repeat('e', 64), 'production', 'ja', now()),
  ('09200000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000009f1', null, 'production', 'ja', null),
  ('09200000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000901', repeat('1', 64), 'production', 'ja', null),
  ('09200000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000911', repeat('2', 64), 'production', 'ja_JP', null);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
-- イベントの送り先（端末IDの末尾）
create function pg_temp.recipients(p_event uuid) returns text[] language sql as $$
  select coalesce(array_agg(right(device_id::text, 2) order by device_id), '{}')
  from public.notification_deliveries where event_id = p_event;
$$;
create function pg_temp.text_for(p_event uuid, p_device text) returns text language sql as $$
  select title || ' / ' || body from public.notification_deliveries
  where event_id = p_event and right(device_id::text, 2) = p_device;
$$;
create function pg_temp.fanout() returns jsonb language sql as $$
  select public.ruuuto_admin_push_fanout()::jsonb;
$$;

-- ===== 週の切替 =====
insert into public.notification_events (id, kind, group_id, board_id, topic) values
  ('09400000-0000-0000-0000-000000000001', 'topic_published', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '窓の外');

set local role service_role;
select is(pg_temp.fanout(), '{"events": 1, "deliveries": 5, "skipped": 0}'::jsonb, '週の切替: 5台に配信行を作る');
reset role;
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000001'), array['0a', '0b', '0c', '0d', '11'],
  '週の切替: 有効な端末を持つメンバー全員。無効・解除した端末と抜けた人は含まない');
select is(
  (select count(*)::int from public.notification_deliveries where event_id = '09400000-0000-0000-0000-000000000001'
   group by device_id order by 1 desc limit 1), 1, '週の切替: 端末ごとに1件');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000001', '0a'), '今週のお題 / 窓の外', '文面: ja');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000001', '0b'), 'This week''s topic / 窓の外', '文面: en-US は英語（固定のお題は日本語のまま）');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000001', '0c'), '今週のお題 / 窓の外', '文面: fr は日本語');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000001', '0d'), '今週のお題 / 窓の外', '文面: 言語なしは日本語');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000001', '11'), '今週のお題 / 窓の外', '文面: ja_JP は日本語');
select isnt((select processed_at from public.notification_events where id = '09400000-0000-0000-0000-000000000001'),
  null, '週の切替: イベントは処理済みになる');

-- 再実行しても増えない
set local role service_role;
select is(pg_temp.fanout(), '{"events": 0, "deliveries": 0, "skipped": 0}'::jsonb, '再実行: 何も増えない');
reset role;
update public.notification_events set processed_at = null where id = '09400000-0000-0000-0000-000000000001';
set local role service_role;
select is(pg_temp.fanout() ->> 'deliveries', '0', '再実行: 処理済みの印が消えても配信行は重複しない');
reset role;
select is((select count(*)::int from public.notification_deliveries), 5, '再実行: 配信行は5件のまま');

-- ===== 手動の変更 =====
insert into public.notification_events (id, kind, group_id, board_id, topic, actor_id, created_at) values
  ('09400000-0000-0000-0000-000000000002', 'topic_changed', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '雨の日', '00000000-0000-0000-0000-0000000009a1', now() - interval '3 minutes');
set local role service_role;
select is(pg_temp.fanout() ->> 'deliveries', '4', '手動: 2分たった変更を送る');
reset role;
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000002'), array['0b', '0c', '0d', '11'],
  '手動: 変えた本人（A）には送らない');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000002', '0c'),
  'お題が変わりました / あゆむさんが「雨の日」に変えました', '文面: 手動の変更（ja）');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000002', '0b'),
  'Topic changed / あゆむ changed it to “雨の日”', '文面: 手動の変更（en）');

-- 2分たっていない変更はまだ送らない
insert into public.notification_events (id, kind, group_id, board_id, topic, actor_id, created_at) values
  ('09400000-0000-0000-0000-000000000003', 'topic_changed', '09000000-0000-0000-0000-000000000002',
   '09100000-0000-0000-0000-000000000002', '夕焼け', '00000000-0000-0000-0000-0000000009a1', now() - interval '119 seconds');
set local role service_role;
select is(pg_temp.fanout(), '{"events": 0, "deliveries": 0, "skipped": 0}'::jsonb, '手動: 2分たつまでは送らない');
reset role;
select is((select processed_at from public.notification_events where id = '09400000-0000-0000-0000-000000000003'),
  null, '手動: 2分たつまでは未処理のまま');
update public.notification_events set created_at = now() - interval '2 minutes'
 where id = '09400000-0000-0000-0000-000000000003';
set local role service_role;
select is(pg_temp.fanout() ->> 'deliveries', '1', '手動: ちょうど2分で送る');
reset role;
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000003'), array['11'], '手動: 別のグループの人には送らない');

-- 短時間に3回変えたら最後の1回だけ
insert into public.notification_events (id, kind, group_id, board_id, topic, actor_id, created_at) values
  ('09400000-0000-0000-0000-000000000011', 'topic_changed', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '1回目', '00000000-0000-0000-0000-0000000009a1', now() - interval '150 seconds'),
  ('09400000-0000-0000-0000-000000000012', 'topic_changed', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '2回目', '00000000-0000-0000-0000-0000000009b1', now() - interval '140 seconds'),
  ('09400000-0000-0000-0000-000000000013', 'topic_changed', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '3回目', '00000000-0000-0000-0000-0000000009b1', now() - interval '30 seconds');
set local role service_role;
select is(pg_temp.fanout(), '{"events": 0, "deliveries": 0, "skipped": 2}'::jsonb,
  '連続の変更: 前の2回は送らずに処理し、最後の1回は2分待つ');
reset role;
select is(
  (select array_agg(skipped_reason order by id) from public.notification_events
    where id in ('09400000-0000-0000-0000-000000000011', '09400000-0000-0000-0000-000000000012')),
  array['superseded', 'superseded'], '連続の変更: 前の2回は superseded');
update public.notification_events set created_at = now() - interval '121 seconds'
 where id = '09400000-0000-0000-0000-000000000013';
set local role service_role;
select is(pg_temp.fanout() ->> 'deliveries', '4', '連続の変更: 2分たったら最後の1回を送る');
reset role;
select is(
  (select count(*)::int from public.notification_deliveries
    where event_id in ('09400000-0000-0000-0000-000000000011', '09400000-0000-0000-0000-000000000012')),
  0, '連続の変更: 前の2回は配信行がない');
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000013'), array['0a', '0c', '0d', '11'],
  '連続の変更: 最後に変えた B 以外に送る（最初に変えた A には届く）');
select is(pg_temp.text_for('09400000-0000-0000-0000-000000000013', '0a'),
  'お題が変わりました / Bobさんが「3回目」に変えました', '連続の変更: 最新のお題を送る');

-- 古いイベント・締め切られたボードは送らない
insert into public.notification_events (id, kind, group_id, board_id, topic, actor_id, created_at) values
  ('09400000-0000-0000-0000-000000000021', 'topic_published', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000001', '古い', null, now() - interval '7 hours'),
  ('09400000-0000-0000-0000-000000000022', 'topic_changed', '09000000-0000-0000-0000-000000000001',
   '09100000-0000-0000-0000-000000000003', '締切後', '00000000-0000-0000-0000-0000000009a1', now() - interval '5 minutes');
set local role service_role;
select is(pg_temp.fanout(), '{"events": 0, "deliveries": 0, "skipped": 2}'::jsonb, '古いイベントと締切後のボードは送らない');
reset role;
select is(
  (select array_agg(skipped_reason order by id) from public.notification_events
    where id in ('09400000-0000-0000-0000-000000000021', '09400000-0000-0000-0000-000000000022')),
  array['stale', 'board_closed'], '送らなかった理由が残る');

-- ===== グループごとの通知設定 =====
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-000000000911');
select is(
  public.ruuuto_list_groups()::jsonb,
  jsonb_build_array(
    jsonb_build_object('id', '09000000-0000-0000-0000-000000000001', 'name', '班1', 'notifications_enabled', true),
    jsonb_build_object('id', '09000000-0000-0000-0000-000000000002', 'name', '班2', 'notifications_enabled', true)),
  '通知設定: 既定はオンで、所属一覧に表示される');
select is(
  public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', false)::jsonb,
  '{"group_id": "09000000-0000-0000-0000-000000000001", "notifications_enabled": false}'::jsonb,
  '通知設定: 班1をオフにできる');
select is(
  public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', false)::jsonb ->> 'notifications_enabled',
  'false', '通知設定: 同じ設定を繰り返しても同じ結果');
select is(
  (select array_agg(x ->> 'notifications_enabled' order by x ->> 'name') from json_array_elements(public.ruuuto_list_groups()) x),
  array['false', 'true'], '通知設定: 所属一覧に班1オフ・班2オンが表示される');
select throws_ok($$ select public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', null) $$,
  '22023', null, '通知設定: null は指定できない');
select pg_temp.act_as('00000000-0000-0000-0000-000000000921');
select throws_ok($$ select public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', false) $$,
  '42501', null, '通知設定: 所属していないグループは変えられない');
set local role anon;
select throws_ok($$ select public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', false) $$,
  '42501', null, '通知設定: anon は変えられない');

reset role;
insert into public.notification_events (id, kind, group_id, board_id, topic) values
  ('09400000-0000-0000-0000-000000000031', 'topic_published', '09000000-0000-0000-0000-000000000001', '09100000-0000-0000-0000-000000000001', '班1の週'),
  ('09400000-0000-0000-0000-000000000032', 'topic_published', '09000000-0000-0000-0000-000000000002', '09100000-0000-0000-0000-000000000002', '班2の週');
set local role service_role;
select pg_temp.fanout();
reset role;
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000031'), array['0a', '0b', '0c', '0d'],
  '通知設定: オフにした班1のイベントは H に届かない');
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000032'), array['0a', '11'],
  '通知設定: オンのままの班2のイベントは H に届く');

-- オンに戻すとまた届く
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-000000000911');
select public.ruuuto_set_group_notifications('09000000-0000-0000-0000-000000000001', true);
reset role;
insert into public.notification_events (id, kind, group_id, board_id, topic) values
  ('09400000-0000-0000-0000-000000000033', 'topic_published', '09000000-0000-0000-0000-000000000001', '09100000-0000-0000-0000-000000000001', '班1の次');
set local role service_role;
select pg_temp.fanout();
reset role;
select is(pg_temp.recipients('09400000-0000-0000-0000-000000000033'), array['0a', '0b', '0c', '0d', '11'],
  '通知設定: オンに戻すと H にまた届く');

-- 配信行を作った後にオフにしたら、送る直前に止まる
update public.notification_deliveries set status = 'sent' where status = 'pending' and event_id <> '09400000-0000-0000-0000-000000000033';
update public.group_members set notifications_enabled = false
 where group_id = '09000000-0000-0000-0000-000000000001' and user_id = '00000000-0000-0000-0000-000000000911';
set local role service_role;
select is(
  (select array_agg(right(x ->> 'apns_token', 1) order by x ->> 'apns_token')
     from jsonb_array_elements(public.ruuuto_admin_push_claim(100)::jsonb) x),
  array['a', 'b', 'c', 'd'], '通知設定: 配信行を作った後にオフにした人へは送らない');

select * from finish();
rollback;
