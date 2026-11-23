-- RCNO-38 週次切替ジョブの実行と失敗時の再実行
--
-- * Supabase Cron（pg_cron）で 5分ごとに週の切替（RCNO-10）を呼ぶ。
--   切替時刻の月曜 00:00 UTC にも動き、失敗しても次の5分で自動的にやり直す。
--   切替処理は何度実行しても結果が変わらないので、通常の回では何も起きない。
-- * 何かを締め切った・作った回と、失敗した回を private.weekly_rotation_runs に記録する。
--   何も起きなかった回の記録は Cron 自身の cron.job_run_details に残る。
-- * 失敗した回は切替処理全体を取り消す（途中まで締め切った状態を残さない）。
-- * 手動で再実行するときは、SQLエディタで次を実行する（run_week が同じ識別子になる）:
--     select private.ruuuto_run_weekly_rotation(now(), 'manual');

create extension if not exists pg_cron with schema pg_catalog;

create table private.weekly_rotation_runs (
  id bigint generated always as identity primary key,
  run_week timestamptz not null,          -- 対象の週の開始（月曜 00:00 UTC）。再実行の識別子
  trigger text not null check (trigger in ('cron', 'manual')),
  status text not null check (status in ('succeeded', 'failed')),
  closed_count int,
  created_count int,
  error_code text,
  error_message text,
  started_at timestamptz not null,
  finished_at timestamptz not null default clock_timestamp()
);

create index weekly_rotation_runs_week_idx on private.weekly_rotation_runs (run_week, started_at desc);

revoke all on private.weekly_rotation_runs from public, anon, authenticated;

create function private.ruuuto_run_weekly_rotation(
  p_at timestamptz default now(),
  p_trigger text default 'cron'
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_started_at timestamptz := clock_timestamp();
  v_week timestamptz;
  v_result json;
  v_state text;
  v_message text;
begin
  select w.opens_at into v_week from private.ruuuto_week_window(p_at) w;

  begin
    v_result := private.ruuuto_rotate_week(p_at);
  exception when others then
    -- この begin ブロックの変更（締め切り・作成）はすべて取り消される
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    insert into private.weekly_rotation_runs
      (run_week, trigger, status, error_code, error_message, started_at)
    values (v_week, p_trigger, 'failed', v_state, v_message, v_started_at);
    return json_build_object(
      'status', 'failed', 'run_week', private.ruuuto_ts(v_week),
      'error_code', v_state, 'error_message', v_message);
  end;

  if (v_result ->> 'closed')::int > 0 or (v_result ->> 'created')::int > 0 or p_trigger = 'manual' then
    insert into private.weekly_rotation_runs
      (run_week, trigger, status, closed_count, created_count, started_at)
    values (v_week, p_trigger, 'succeeded',
            (v_result ->> 'closed')::int, (v_result ->> 'created')::int, v_started_at);
  end if;

  return json_build_object(
    'status', 'succeeded', 'run_week', private.ruuuto_ts(v_week),
    'closed', (v_result ->> 'closed')::int, 'created', (v_result ->> 'created')::int);
end;
$$;

revoke execute on function private.ruuuto_run_weekly_rotation(timestamptz, text) from public, anon, authenticated;

-- 5分ごとに実行（同じ名前のジョブがあれば置き換える）
select cron.schedule(
  'ruuuto-weekly-rotation',
  '*/5 * * * *',
  $$select private.ruuuto_run_weekly_rotation(now(), 'cron')$$
);
