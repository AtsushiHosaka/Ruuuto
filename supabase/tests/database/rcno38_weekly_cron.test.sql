-- RCNO-38 週次切替ジョブの実行と失敗時の再実行
-- 定量目標: スケジューラーからの実行成功・実行途中の失敗・同じ回の再実行の3ケース。
-- 再実行後もグループごとの開催中のお題は1件で、実行結果が記録される。
begin;
select plan(14);

-- スケジュールの登録
select is(
  (select schedule from cron.job where jobname = 'ruuuto-weekly-rotation'),
  '*/5 * * * *', 'Cronに5分ごとのジョブが登録されている');
select is(
  (select command from cron.job where jobname = 'ruuuto-weekly-rotation'),
  'select private.ruuuto_run_weekly_rotation(now(), ''cron'')', 'ジョブは週の切替を呼ぶ');
select ok(
  (select active from cron.job where jobname = 'ruuuto-weekly-rotation'), 'ジョブは有効');

-- データ: 2グループ、11/16 の週のボード
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000038a1', 'cron@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('38100000-0000-0000-0000-000000000001', '班1', '00000000-0000-0000-0000-0000000038a1', gen_random_uuid()),
  ('38100000-0000-0000-0000-000000000002', '班2', '00000000-0000-0000-0000-0000000038a1', gen_random_uuid());
insert into public.boards (group_id, topic, opens_at, closes_at) values
  ('38100000-0000-0000-0000-000000000001', '先週', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z'),
  ('38100000-0000-0000-0000-000000000002', '先週', '2026-11-16T00:00:00Z', '2026-11-23T00:00:00Z');

create function pg_temp.open_counts() returns int[] language sql as $$
  select array_agg(c order by g.id) from (
    select g.id, (select count(*)::int from public.boards b where b.group_id = g.id and b.status = 'open') c
    from public.groups g where g.id::text like '38100000-%') g;
$$;

-- 1. 実行途中の失敗: 新しいボードの作成で失敗させる
create function pg_temp.fail_board_insert() returns trigger language plpgsql as $$
begin
  raise exception '試験用の失敗' using errcode = 'XX001';
end;
$$;
create trigger rcno38_fail before insert on public.boards
  for each row execute function pg_temp.fail_board_insert();

select is(
  private.ruuuto_run_weekly_rotation('2026-11-23T00:00:00Z', 'cron')::jsonb - 'error_message',
  '{"status": "failed", "run_week": "2026-11-23T00:00:00Z", "error_code": "XX001"}'::jsonb,
  '失敗: 失敗したことと対象の週を返す');
select is(
  (select array_agg(status order by opens_at) from public.boards where group_id::text like '38100000-%'),
  array['open', 'open'], '失敗: 途中まで締め切った状態は残らない（古いボードは開催中のまま）');
select is(
  (select status || ' ' || error_code || ' ' || trigger from private.weekly_rotation_runs order by id desc limit 1),
  'failed XX001 cron', '失敗: 実行結果が記録される');

drop trigger rcno38_fail on public.boards;

-- 2. 同じ回の再実行（手動）
select is(
  private.ruuuto_run_weekly_rotation('2026-11-23T00:03:00Z', 'manual')::jsonb,
  '{"status": "succeeded", "run_week": "2026-11-23T00:00:00Z", "closed": 2, "created": 2}'::jsonb,
  '再実行: 同じ週（同じ識別子）で成功し、2件を締め切って2件を作る');
select is(pg_temp.open_counts(), array[1, 1], '再実行: 各グループの開催中は1件');
select is(
  (select count(*)::int from private.weekly_rotation_runs where run_week = '2026-11-23T00:00:00Z'),
  2, '再実行: 同じ週の記録が失敗と成功の2件になる');

-- 3. スケジューラーからの通常の回（何も起きない回は記録しない）
select is(
  private.ruuuto_run_weekly_rotation('2026-11-23T00:05:00Z', 'cron')::jsonb,
  '{"status": "succeeded", "run_week": "2026-11-23T00:00:00Z", "closed": 0, "created": 0}'::jsonb,
  '通常の回: 何も変わらない');
select is(pg_temp.open_counts(), array[1, 1], '通常の回: 各グループの開催中は1件のまま');
select is(
  (select count(*)::int from private.weekly_rotation_runs where run_week = '2026-11-23T00:00:00Z'),
  2, '通常の回: 何も起きなかった回は記録を増やさない');

-- 4. 翌週の切替（スケジューラーからの成功）
select is(
  private.ruuuto_run_weekly_rotation('2026-11-30T00:00:00Z', 'cron')::jsonb ->> 'created',
  '2', '翌週: 切替時刻の回で2件を作る');
select is(
  (select status || ' ' || closed_count || ' ' || created_count from private.weekly_rotation_runs order by id desc limit 1),
  'succeeded 2 2', '翌週: 成功の結果が記録される');

select * from finish();
rollback;
