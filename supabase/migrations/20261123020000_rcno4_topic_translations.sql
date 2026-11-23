-- RCNO-4 固定のお題に日本語と英語の本文を持たせる
--
-- 同じお題ID（topic_prompts.id）に、言語ごとの本文を持てるようにする。
-- * public.topic_prompt_texts (prompt_id, locale) に本文を保存する。locale は ja / en。
-- * 日本語は topic_prompts.body から写す。topic_prompts.body は日本語の原文として残し、
--   週の切替（ruuuto_weekly_prompt）とボードの topic はこれまでどおり日本語を使う。
-- * 英語の48件は、Slackの「固定のお題案」の英語版としてあゆむが確認した文言。
--   文言を直すときは、新しいマイグレーションで同じ (prompt_id, locale) の行を更新する。
--
-- iOSへの返し方（既存のキーは変えず、topic_texts を足す）
--   ruuuto_current_board、ruuuto_board_history の各要素、ruuuto_board_snapshot の board、
--   Realtime の board_updated に topic_texts = {"ja": "...", "en": "..."} を足す。
--   * 固定のお題（boards.prompt_id がある）: 本文がある言語のキーだけを入れる。
--   * 手動のお題・既定の文言「今週の一枚」（prompt_id が null）: 空のオブジェクト {}。
--     null にせず常にオブジェクトを返すので、iOSはキーの有無だけを見ればよい。
--   * 表示のルール: 端末の言語のキーがあればそれ、なければ ja、それもなければ topic。
--
-- プッシュ通知（RCNO-9）
--   週の切替の通知（topic_published）は、英語の端末には固定のお題の英語の本文を送る。
--   英語の本文がなければ日本語のまま。手動のお題（topic_changed）は入力されたまま送る。

create table public.topic_prompt_texts (
  prompt_id uuid not null references public.topic_prompts (id) on delete cascade,
  locale text not null check (locale in ('ja', 'en')),
  body text not null check (char_length(btrim(body)) between 1 and 80),
  primary key (prompt_id, locale)
);

alter table public.topic_prompt_texts enable row level security;

create policy "topic_prompt_texts: ログイン済みなら読める"
  on public.topic_prompt_texts for select to authenticated
  using (true);

revoke all on public.topic_prompt_texts from anon, authenticated;
grant select on public.topic_prompt_texts to authenticated;

-- 日本語は既存の本文から写す
insert into public.topic_prompt_texts (prompt_id, locale, body)
select p.id, 'ja', p.body from public.topic_prompts p
on conflict (prompt_id, locale) do update set body = excluded.body;

-- 英語の本文（month, week で topic_prompts に対応づける）
insert into public.topic_prompt_texts (prompt_id, locale, body)
select p.id, 'en', v.body
from (values
  (1, 1, 'New Year greetings & holiday scenes (Happy New Year!)'),
  (1, 2, 'New Year foods & lucky charms from your country'),
  (1, 3, 'Something you want to try this year (drawings or words OK)'),
  (1, 4, 'A "little lucky thing" you found in January'),
  (2, 1, 'Pink & red things around you'),
  (2, 2, 'Valentine''s Day & classic sweets in your country'),
  (2, 3, 'What you''re into right now (music, shows, hobbies…)'),
  (2, 4, 'A "thank you" message for someone'),
  (3, 1, 'Find something green around you'),
  (3, 2, 'Signs of the changing season in your town (flowers, clothes, weather)'),
  (3, 3, 'A happy song that lifts your mood (3/20 International Day of Happiness)'),
  (3, 4, 'Something you got ready for a new season or a fresh start'),
  (4, 1, '"True or false?" local quiz (4/1 April Fools'' Day)'),
  (4, 2, 'Something that made you laugh, or a funny sign'),
  (4, 3, 'A book that changed you, or a favorite story (4/23 World Book Day)'),
  (4, 4, 'Flowers on your spring (or fall) walk'),
  (5, 1, 'Your morning routine or favorite morning drink'),
  (5, 2, 'A thank-you story for someone dear or your family (Mother''s Day)'),
  (5, 3, 'A heartwarming custom or manner from your country'),
  (5, 4, 'Something kind someone did for you recently'),
  (6, 1, 'Today''s sky (blue sky, sunset, rain clouds…)'),
  (6, 2, 'How you spend rainy days or changing weather'),
  (6, 3, 'No words needed: a song you love right now (6/21 World Music Day)'),
  (6, 4, 'Halfway through the year: your best shot so far (solstice)'),
  (7, 1, 'City lights, starry skies, or candles at night'),
  (7, 2, 'Go-to summer drinks & cold treats (warm drinks down south)'),
  (7, 3, 'Describe your country in just 3 emoji! (7/17 World Emoji Day)'),
  (7, 4, 'Your late-night companion (games, videos, music…)'),
  (8, 1, 'Water scenes (sea, rivers, fountains, puddles)'),
  (8, 2, 'A hidden gem in your town'),
  (8, 3, 'Your best shot this summer (or winter) (8/19 World Photo Day)'),
  (8, 4, 'A place you dream of visiting someday'),
  (9, 1, 'Classic street food or snacks in your town'),
  (9, 2, 'Find the moon, or anything round (Harvest Moon)'),
  (9, 3, 'Local food you''d love visitors to try'),
  (9, 4, 'A hobby for long fall (or spring) nights (9/27 World Tourism Day)'),
  (10, 1, 'Find orange & black around you'),
  (10, 2, 'A strange tale or urban legend from your country'),
  (10, 3, 'Pumpkin sweets & fall treats'),
  (10, 4, 'Halloween costumes, makeup & drawings! (10/31 Halloween)'),
  (11, 1, 'Your favorite warm drink for a cozy break'),
  (11, 2, 'Art, illustration, or design that moved you lately'),
  (11, 3, 'Your favorite spot in your room'),
  (11, 4, 'People or things you''re thankful for this year (Thanksgiving)'),
  (12, 1, 'City lights & sparkly things'),
  (12, 2, 'How you spend the holiday season in your country'),
  (12, 3, 'A gift you loved, or a treat for yourself (12/25 Christmas)'),
  (12, 4, 'Your best moment of the year (year in review)')
) as v (month, week, body)
join public.topic_prompts p on p.month = v.month and p.week = v.week
on conflict (prompt_id, locale) do update set body = excluded.body;

-- ボードのお題の言語別の本文。固定のお題でなければ空のオブジェクト。
create function private.ruuuto_topic_texts(p_prompt_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select jsonb_object_agg(t.locale, t.body)
     from public.topic_prompt_texts t
     where t.prompt_id = p_prompt_id),
    '{}'::jsonb);
$$;

revoke execute on function private.ruuuto_topic_texts(uuid) from public, anon, authenticated;

-- 端末の locale から言語部分を取り出す（en-US、en_US なら en）
create function private.ruuuto_locale_lang(p_locale text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(split_part(replace(coalesce(p_locale, ''), '_', '-'), '-', 1));
$$;

revoke execute on function private.ruuuto_locale_lang(text) from public, anon, authenticated;

-- ボード1件を返す形に topic_texts を足す（RCNO-36 の関数を置き換え）。
-- ruuuto_board_snapshot の board と Realtime の board_updated はこの形を使う。
create or replace function private.ruuuto_board_json(p_board public.boards)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_board.id,
    'group_id', p_board.group_id,
    'topic', p_board.topic,
    'topic_texts', private.ruuuto_topic_texts(p_board.prompt_id),
    'opens_at', private.ruuuto_ts(p_board.opens_at),
    'closes_at', private.ruuuto_ts(p_board.closes_at),
    'status', p_board.status);
$$;

-- 開催中のボードに topic_texts を足す（RCNO-43 の関数を置き換え。ほかのキーと例外は同じ）
create or replace function public.ruuuto_current_board(p_group_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result json;
begin
  perform private.ruuuto_require_member(p_group_id);

  select private.ruuuto_board_json(b)::json
    into v_result
  from public.boards b
  where b.group_id = p_group_id and b.status = 'open';

  if v_result is null then
    raise exception '開催中のボードがありません' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 月別のボード一覧の各要素に topic_texts を足す（RCNO-10 の関数を置き換え。ほかは同じ）
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
             'topic_texts', private.ruuuto_topic_texts(b.prompt_id),
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

-- 通知イベントから配信行を作る（RCNO-9 の関数を置き換え）。
-- 変更点: 週の切替の通知（topic_published）で、ボードがいまも同じ固定のお題なら、
-- 英語の端末には英語の本文を使う。英語の本文がなければイベントのお題（日本語）のまま。
create or replace function public.ruuuto_admin_push_fanout()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_skipped int := 0;
  v_count int;
  v_events int;
  v_deliveries int;
begin
  -- 1. 古すぎるイベント
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'stale'
   where e.processed_at is null and e.created_at < now() - interval '6 hours';
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 2. 同じボードに、より新しい手動変更がある
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'superseded'
   where e.processed_at is null and e.kind = 'topic_changed'
     and exists (
       select 1 from public.notification_events n
       where n.board_id = e.board_id and n.kind = 'topic_changed' and n.id <> e.id
         and (n.created_at > e.created_at or (n.created_at = e.created_at and n.id > e.id)));
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 3. 締め切られたボードの手動変更
  update public.notification_events e
     set processed_at = now(), skipped_reason = 'board_closed'
    from public.boards b
   where e.processed_at is null and e.kind = 'topic_changed'
     and b.id = e.board_id and (b.status <> 'open' or b.closes_at <= now());
  get diagnostics v_count = row_count;
  v_skipped := v_skipped + v_count;

  -- 4. 送る時刻になったイベントの配信行を作る
  with ready as (
    select e.id, e.kind, e.group_id, e.topic, e.actor_id,
           -- 公開の通知で、ボードがいまもイベントと同じ固定のお題のときだけ英語の本文を探す
           case when e.kind = 'topic_published' and b.topic = e.topic then b.prompt_id end as prompt_id
    from public.notification_events e
    left join public.boards b on b.id = e.board_id
    where e.processed_at is null
      and (e.kind = 'topic_published' or e.created_at <= now() - interval '2 minutes')
    order by e.created_at, e.id
    limit 200
    for update of e skip locked
  ), inserted as (
    insert into public.notification_deliveries (event_id, device_id, user_id, title, body)
    select r.id, dv.installation_id, dv.user_id, t.title, t.body
    from ready r
    join public.group_members m on m.group_id = r.group_id and m.notifications_enabled
    join public.devices dv on dv.user_id = m.user_id
                          and dv.apns_token is not null and dv.invalidated_at is null
    left join public.profiles actor on actor.id = r.actor_id
    left join public.topic_prompt_texts en on en.prompt_id = r.prompt_id and en.locale = 'en'
    cross join lateral private.ruuuto_push_text(
      r.kind, dv.locale,
      case when private.ruuuto_locale_lang(dv.locale) = 'en' then coalesce(en.body, r.topic) else r.topic end,
      actor.display_name) t
    where r.kind = 'topic_published' or m.user_id is distinct from r.actor_id
    on conflict (event_id, device_id) do nothing
    returning 1
  ), done as (
    update public.notification_events e
       set processed_at = now()
      from ready r
     where e.id = r.id
    returning 1
  )
  select (select count(*) from done), (select count(*) from inserted)
    into v_events, v_deliveries;

  return json_build_object('events', v_events, 'deliveries', v_deliveries, 'skipped', v_skipped);
end;
$$;
