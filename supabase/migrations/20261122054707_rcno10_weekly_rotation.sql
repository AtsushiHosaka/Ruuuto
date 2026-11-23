-- RCNO-10 週の切替で次のお題を公開する
--
-- 2026-11-22 の決定: 週は「月曜 00:00 UTC」に切り替わる。
--   日本時間 月曜 9:00 / バンクーバー 日曜 16:00（夏時間は 17:00）
-- どちらの国でも同じ瞬間に、同じボードへ切り替わる。
--
-- 第5週（月曜が月の29〜31日に来る週）の固定のお題は、まだ決まっていない。
-- topic_prompts に week = 5 の行がなければ、既定の文言「今週の一枚」を使う。

-- 週の区切り: RCNO-42 の暫定（日本時間）をUTCに置き換える
create or replace function private.ruuuto_week_window(p_at timestamptz)
returns table (opens_at timestamptz, closes_at timestamptz)
language sql
stable
set search_path = ''
as $$
  select w.start_at, w.start_at + interval '7 days'
  from (
    select (date_trunc('week', p_at at time zone 'UTC') at time zone 'UTC') as start_at
  ) w;
$$;

-- 固定のお題: 週の開始日（UTC）の月と、その月の第何週かで引く
create or replace function private.ruuuto_weekly_prompt(p_opens_at timestamptz)
returns table (prompt_id uuid, topic text)
language sql
stable
set search_path = ''
as $$
  with week_start as (
    select (p_opens_at at time zone 'UTC')::date as d
  )
  select p.id, coalesce(p.body, '今週の一枚')
  from week_start
  left join public.topic_prompts p
    on p.month = extract(month from week_start.d)::smallint
   and p.week = least(5, ((extract(day from week_start.d)::int - 1) / 7) + 1)::smallint;
$$;

-- 月別履歴の月の区切りもUTCにそろえる（RCNO-43 の関数を置き換え）
create or replace function public.ruuuto_board_history(p_group_id uuid, p_year int, p_month int)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from timestamptz;
begin
  perform private.ruuuto_require_member(p_group_id);
  if p_year not between 2000 and 2100 or p_month not between 1 and 12 then
    raise exception '年月の指定が正しくありません' using errcode = '22023';
  end if;

  v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');

  return coalesce((
    select json_agg(json_build_object(
             'id', b.id,
             'topic', b.topic,
             'opens_at', private.ruuuto_ts(b.opens_at),
             'closes_at', private.ruuuto_ts(b.closes_at),
             'status', b.status,
             'photo_count', coalesce(s.photo_count, 0),
             'preview_paths', coalesce(s.preview_paths, '[]'::json))
           order by b.opens_at)
    from public.boards b
    left join lateral (
      select count(*)::int as photo_count,
             (select json_agg(x.storage_path order by x.created_at, x.id)
              from (select p2.storage_path, p2.created_at, p2.id
                    from public.photos p2
                    where p2.board_id = b.id and p2.status = 'posted'
                    order by p2.created_at, p2.id
                    limit 3) x) as preview_paths
      from public.photos p
      where p.board_id = b.id and p.status = 'posted'
    ) s on true
    where b.group_id = p_group_id
      and b.opens_at >= v_from
      and b.opens_at < v_from + interval '1 month'
  ), '[]'::json);
end;
$$;

-- 週の切替
--
-- p_at の時点で締切を過ぎた開催中のボードを締め切り、p_at を含む週のボードを作る。
-- グループごとに1トランザクション（このSQL関数の呼び出し全体）で行う。
-- * 何度実行しても同じ結果になる（開催中は常にグループに1件、同じ週のボードは1件）。
-- * 実行が何週か止まっていた場合は、間の週は作らずに p_at を含む週へ進める。
-- * 開催中のボードがないグループ（作成直後の失敗など）にも、今週のボードを作る。
-- * 新しく作ったボードごとに、通知用のイベント topic_published を記録する。
-- 戻り値: {"opens_at", "closed": 締め切った数, "created": 作った数}
create function private.ruuuto_rotate_week(p_at timestamptz default now())
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_prompt_id uuid;
  v_topic text;
  v_closed int;
  v_created int;
begin
  select w.opens_at, w.closes_at into v_opens_at, v_closes_at
  from private.ruuuto_week_window(p_at) w;
  select p.prompt_id, p.topic into v_prompt_id, v_topic
  from private.ruuuto_weekly_prompt(v_opens_at) p;

  -- 1. 締切を過ぎた開催中のボードを締め切る
  update public.boards b
     set status = 'closed', closed_at = b.closes_at
   where b.status = 'open' and b.closes_at <= p_at;
  get diagnostics v_closed = row_count;

  -- 2. 開催中のボードがないグループに、今週のボードを作る
  with created as (
    insert into public.boards (group_id, topic, topic_source, prompt_id, opens_at, closes_at)
    select g.id, v_topic, 'weekly', v_prompt_id, v_opens_at, v_closes_at
    from public.groups g
    where not exists (
      select 1 from public.boards b where b.group_id = g.id and b.status = 'open'
    )
    on conflict do nothing
    returning id, group_id, topic
  ), events as (
    insert into public.notification_events (kind, group_id, board_id, topic)
    select 'topic_published', c.group_id, c.id, c.topic from created c
    returning 1
  )
  select count(*) into v_created from created;

  return json_build_object(
    'opens_at', private.ruuuto_ts(v_opens_at),
    'closed', v_closed,
    'created', v_created);
end;
$$;

revoke execute on function private.ruuuto_rotate_week(timestamptz) from public, anon, authenticated;
