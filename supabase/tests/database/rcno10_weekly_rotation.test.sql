-- RCNO-10 週の切替で次のお題を公開する
-- 定量目標: 切替の直前・直後・同じ切替の再実行の3ケースで、開催中のお題が常に1件。
-- 日本とカナダの2タイムゾーンで同じボードに切り替わる。
begin;
select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000010a1', 'rotate-a@example.com'),
  ('00000000-0000-0000-0000-0000000010b1', 'rotate-b@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('10100000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000010a1', gen_random_uuid()),
  ('10100000-0000-0000-0000-000000000002', '別の班', '00000000-0000-0000-0000-0000000010b1', gen_random_uuid()),
  ('10100000-0000-0000-0000-000000000003', 'ボードなしの班', '00000000-0000-0000-0000-0000000010b1', gen_random_uuid());

insert into public.topic_prompts (month, week, body) values
  (11, 3, '窓の外'),
  (11, 4, 'あったかいもの'),
  (12, 1, '冬のはじまり');

-- 11/16 の週のボード（グループ1・2）。グループ3はボードがない
insert into public.boards (id, group_id, topic, opens_at, closes_at) values
  ('10200000-0000-0000-0000-000000000001', '10100000-0000-0000-0000-000000000001', '窓の外', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z'),
  ('10200000-0000-0000-0000-000000000002', '10100000-0000-0000-0000-000000000002', '窓の外', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z');

create function pg_temp.open_topics() returns text[] language sql as $$
  select array_agg(g.name || ':' || b.topic order by g.name)
  from public.boards b join public.groups g on g.id = b.group_id
  where b.status = 'open';
$$;
create function pg_temp.open_count(p_group uuid) returns int language sql as $$
  select count(*)::int from public.boards where group_id = p_group and status = 'open';
$$;

-- 切替の直前（日曜 23:59:59 UTC）: グループ1・2はそのまま。ボードのないグループ3には今週分を作る
select is(
  private.ruuuto_rotate_week('2026-11-22T23:59:59Z')::jsonb,
  '{"opens_at": "2026-11-16T00:00:00Z", "closed": 0, "created": 1}'::jsonb,
  '直前: 締め切るボードはなく、ボードのないグループに今週分を1件作る');
select is(pg_temp.open_count('10100000-0000-0000-0000-000000000001'), 1, '直前: グループ1の開催中は1件');
select is(
  (select topic from public.boards where group_id = '10100000-0000-0000-0000-000000000001' and status = 'open'),
  '窓の外', '直前: グループ1はまだ先週（11/16）のお題');

-- 切替の直後（月曜 00:00:01 UTC）
select is(
  private.ruuuto_rotate_week('2026-11-23T00:00:01Z')::jsonb,
  '{"opens_at": "2026-11-23T00:00:00Z", "closed": 3, "created": 3}'::jsonb,
  '直後: 3グループの古いボードを締め切り、新しいボードを3件作る');
select is(
  pg_temp.open_topics(),
  array['えーえす班:あったかいもの', 'ボードなしの班:あったかいもの', '別の班:あったかいもの'],
  '直後: 全グループが11月第4週のお題に切り替わる');
select is(pg_temp.open_count('10100000-0000-0000-0000-000000000001'), 1, '直後: グループ1の開催中は1件');
select is(
  (select status || ' ' || closed_at::text from public.boards where id = '10200000-0000-0000-0000-000000000001'),
  'closed 2026-11-23 00:00:00+00', '直後: 古いボードは締切時刻で締め切られる');
select is(
  (select opens_at::text || ' / ' || closes_at::text from public.boards
   where group_id = '10100000-0000-0000-0000-000000000001' and status = 'open'),
  '2026-11-23 00:00:00+00 / 2026-11-30 00:00:00+00', '直後: 新しいボードは月曜 00:00 UTC から7日間');
select is(
  (select count(*)::int from public.notification_events where kind = 'topic_published'),
  4, '新しく作ったボードごとに通知イベント（直前の1件と直後の3件）');

-- 同じ切替の再実行
select is(
  private.ruuuto_rotate_week('2026-11-23T00:05:00Z')::jsonb,
  '{"opens_at": "2026-11-23T00:00:00Z", "closed": 0, "created": 0}'::jsonb,
  '再実行: 何も変わらない');
select is(pg_temp.open_count('10100000-0000-0000-0000-000000000001'), 1, '再実行: グループ1の開催中は1件');
select is(
  (select count(*)::int from public.boards where group_id = '10100000-0000-0000-0000-000000000001'),
  2, '再実行: グループ1のボードは2件のまま（二重に作らない）');
select is(
  (select count(*)::int from public.notification_events where kind = 'topic_published'),
  4, '再実行: 通知イベントも増えない');

-- 2つのタイムゾーン: 日本の月曜 9:00 と、バンクーバーの日曜 16:00 は同じ週
select is(
  (select opens_at from private.ruuuto_week_window('2026-11-23T09:00:00+09:00')),
  (select opens_at from private.ruuuto_week_window('2026-11-22T16:00:00-08:00')),
  '日本の月曜 9:00 とバンクーバーの日曜 16:00 は同じ週');
select isnt(
  (select opens_at from private.ruuuto_week_window('2026-11-23T08:59:59+09:00')),
  (select opens_at from private.ruuuto_week_window('2026-11-23T09:00:00+09:00')),
  '日本の月曜 8:59 まではまだ前の週');

-- 実行が止まっていた場合: 2週あとに動いても、間の週は作らず今の週へ進む
select is(
  private.ruuuto_rotate_week('2026-12-08T03:00:00Z')::jsonb ->> 'opens_at',
  '2026-12-07T00:00:00Z', '止まっていた場合は今の週（12/7）へ進む');
select is(
  (select count(*)::int from public.boards where group_id = '10100000-0000-0000-0000-000000000001'),
  3, '間の週（11/30）のボードは作らない');

-- 第5週・お題がない週は既定の文言。12月第1週は固定のお題
select is((select topic from private.ruuuto_weekly_prompt('2026-11-30T00:00:00Z')), '今週の一枚', '11月の第5週（11/30）は既定の文言');
select is((select topic from private.ruuuto_weekly_prompt('2026-12-07T00:00:00Z')), '冬のはじまり', '12/7 は12月最初の月曜なので12月第1週のお題');

select * from finish();
rollback;
