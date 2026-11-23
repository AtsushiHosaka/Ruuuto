-- RCNO-4 固定のお題に日本語と英語の本文を持たせる
-- 定量目標: 48件すべてに ja と en があり80文字以内。開催中・履歴・スナップショット・board_updated に
-- topic_texts が入り、手動のお題は空のオブジェクト。英語がないお題は ja だけ。
-- 週の切替の通知は英語の端末に英語の本文、英語がなければ日本語、手動のお題は入力のまま。
begin;
select plan(26);

-- 本文のデータ
select is((select count(*)::int from public.topic_prompt_texts where locale = 'en'), 48, '英語の本文は48件');
select is(
  (select count(*)::int from public.topic_prompts p
   join public.topic_prompt_texts t on t.prompt_id = p.id and t.locale = 'en'), 48,
  '48件のお題すべてに英語の本文がある');
select ok(
  (select bool_and(char_length(body) between 1 and 80) from public.topic_prompt_texts where locale = 'en'),
  '英語の本文はどれも1〜80文字');
select is(
  (select count(*)::int from public.topic_prompts p
   join public.topic_prompt_texts t on t.prompt_id = p.id and t.locale = 'ja' and t.body = p.body), 48,
  '日本語の本文は topic_prompts.body と同じ48件');
select is(
  (select t.body from public.topic_prompt_texts t join public.topic_prompts p on p.id = t.prompt_id
   where p.month = 11 and p.week = 3 and t.locale = 'en'),
  'Your favorite spot in your room', '11月第3週の英語の本文');
select is(
  (select t.body from public.topic_prompt_texts t join public.topic_prompts p on p.id = t.prompt_id
   where p.month = 7 and p.week = 3 and t.locale = 'en'),
  'Describe your country in just 3 emoji! (7/17 World Emoji Day)', '7月第3週の英語の本文');
select throws_ok(
  $$ insert into public.topic_prompt_texts (prompt_id, locale, body)
     select id, 'fr', 'Ta pièce préférée' from public.topic_prompts where month = 11 and week = 3 $$,
  '23514', null, 'ja・en 以外の言語は保存できない');

-- A: 日本語の端末 / B: 英語の端末（en-US）
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000004b1', 'tr-a@example.com'),
  ('00000000-0000-0000-0000-0000000004b2', 'tr-b@example.com');
update public.profiles set display_name = 'あゆむ' where id = '00000000-0000-0000-0000-0000000004b1';
insert into public.groups (id, name, created_by, create_request_id) values
  ('04b00000-0000-0000-0000-000000000001', '翻訳班', '00000000-0000-0000-0000-0000000004b1', gen_random_uuid());
insert into public.group_members (group_id, user_id) values
  ('04b00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000004b1'),
  ('04b00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000004b2');
insert into public.devices (installation_id, user_id, apns_token, environment, locale) values
  ('04b20000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000004b1', repeat('a', 64), 'production', 'ja'),
  ('04b20000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000004b2', repeat('b', 64), 'production', 'en-US');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.sent(p_event text) returns setof realtime.messages
language sql security definer as $$
  select * from realtime.messages m
  where m.event = p_event and m.extension = 'broadcast'
  order by m.inserted_at;
$$;
create function pg_temp.delivered(p_device uuid) returns text language sql as $$
  select string_agg(d.title || ' / ' || d.body, ' | ' order by d.created_at)
  from public.notification_deliveries d where d.device_id = p_device;
$$;

-- 11/16 始まりの週の切替で、11月第3週の固定のお題のボードができる
select private.ruuuto_rotate_week('2026-11-16 00:05+00');

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000004b2');
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000001')::jsonb -> 'topic_texts'),
  '{"ja": "自分の部屋の「お気に入りスペース」", "en": "Your favorite spot in your room"}'::jsonb,
  '開催中のボード: 固定のお題は topic_texts に ja と en が入る');
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000001')::jsonb ->> 'topic'),
  '自分の部屋の「お気に入りスペース」', '開催中のボード: topic はこれまでどおり日本語');
select is(
  (select public.ruuuto_board_history('04b00000-0000-0000-0000-000000000001', 2026, 11)::jsonb -> 0 -> 'topic_texts' ->> 'en'),
  'Your favorite spot in your room', '月別履歴の各要素にも topic_texts が入る');
select is(
  (select public.ruuuto_board_snapshot(b.id)::jsonb -> 'board' -> 'topic_texts' ->> 'en'
   from public.boards b where b.group_id = '04b00000-0000-0000-0000-000000000001'),
  'Your favorite spot in your room', 'スナップショットの board にも topic_texts が入る');
select is(
  (select count(*)::int from public.topic_prompt_texts), 96,
  'ログイン済みなら言語別の本文を直接読める');
reset role;

set local role anon;
select throws_ok($$ select * from public.topic_prompt_texts $$, '42501', null, 'anon は言語別の本文を読めない');
reset role;

-- 週の切替の通知: 英語の端末には英語の本文、日本語の端末には日本語
select public.ruuuto_admin_push_fanout();
select is(pg_temp.delivered('04b20000-0000-0000-0000-00000000000b'),
  'This week''s topic / Your favorite spot in your room', '公開の通知: en-US の端末には英語の本文を送る');
select is(pg_temp.delivered('04b20000-0000-0000-0000-00000000000a'),
  '今週のお題 / 自分の部屋の「お気に入りスペース」', '公開の通知: 日本語の端末には日本語の本文を送る');

-- board_updated: 固定のお題のまま期間が変わったら、topic_texts 付きで配信する
-- （締切をテスト実行時より後にずらし、この後の手動変更を受け付けるようにする）
update public.boards set closes_at = now() + interval '6 days'
 where group_id = '04b00000-0000-0000-0000-000000000001' and status = 'open';
select is(
  (select payload -> 'topic_texts' ->> 'en' from pg_temp.sent('board_updated') order by inserted_at desc limit 1),
  'Your favorite spot in your room', 'board_updated にも topic_texts が入る');

-- 手動でお題を変えると topic_texts は空のオブジェクト。通知は入力したまま送る
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000004b1');
select public.ruuuto_save_topic(b.id, '窓から見える景色')
  from public.boards b where b.group_id = '04b00000-0000-0000-0000-000000000001' and b.status = 'open';
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000001')::jsonb -> 'topic_texts'),
  '{}'::jsonb, '手動のお題: 開催中のボードの topic_texts は空のオブジェクト');
select is(
  (select public.ruuuto_board_history('04b00000-0000-0000-0000-000000000001', 2026, 11)::jsonb -> 0 -> 'topic_texts'),
  '{}'::jsonb, '手動のお題: 月別履歴の topic_texts も空のオブジェクト');
reset role;
select is(
  (select payload -> 'topic_texts' from pg_temp.sent('board_updated') order by inserted_at desc limit 1),
  '{}'::jsonb, '手動のお題: board_updated の topic_texts は空のオブジェクト');
update public.notification_events set created_at = now() - interval '3 minutes'
 where kind = 'topic_changed' and group_id = '04b00000-0000-0000-0000-000000000001';
select public.ruuuto_admin_push_fanout();
select is(
  (select title || ' / ' || body from public.notification_deliveries d
   join public.notification_events e on e.id = d.event_id
   where e.kind = 'topic_changed' and d.device_id = '04b20000-0000-0000-0000-00000000000b'),
  'Topic changed / あゆむ changed it to “窓から見える景色”', '手動のお題の通知は英語の端末にも入力したまま送る');

-- 英語の本文がない固定のお題は ja だけを返し、通知は日本語にする
insert into public.groups (id, name, created_by, create_request_id) values
  ('04b00000-0000-0000-0000-000000000002', '翻訳班2', '00000000-0000-0000-0000-0000000004b1', gen_random_uuid());
insert into public.group_members (group_id, user_id) values
  ('04b00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000004b1'),
  ('04b00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000004b2');
delete from public.topic_prompt_texts t using public.topic_prompts p
 where p.id = t.prompt_id and p.month = 11 and p.week = 3 and t.locale = 'en';
select private.ruuuto_rotate_week('2026-11-16 00:10+00');

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000004b2');
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000002')::jsonb -> 'topic_texts'),
  '{"ja": "自分の部屋の「お気に入りスペース」"}'::jsonb,
  '英語の本文がないお題: topic_texts は ja だけ（iOSは ja で表示する）');
reset role;

delete from public.notification_deliveries;
select public.ruuuto_admin_push_fanout();
select is(pg_temp.delivered('04b20000-0000-0000-0000-00000000000b'),
  'This week''s topic / 自分の部屋の「お気に入りスペース」', '英語の本文がなければ、英語の端末にも日本語の本文を送る');

-- 既定の文言（第5週）は固定のお題ではないので空のオブジェクト
insert into public.groups (id, name, created_by, create_request_id) values
  ('04b00000-0000-0000-0000-000000000003', '翻訳班3', '00000000-0000-0000-0000-0000000004b1', gen_random_uuid());
insert into public.group_members (group_id, user_id) values
  ('04b00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000004b1');
select private.ruuuto_rotate_week('2026-11-30 00:05+00');
set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000004b1');
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000003')::jsonb ->> 'topic'),
  '今週の一枚', '第5週は既定の文言');
select is(
  (select public.ruuuto_current_board('04b00000-0000-0000-0000-000000000003')::jsonb -> 'topic_texts'),
  '{}'::jsonb, '既定の文言の topic_texts は空のオブジェクト');
reset role;

-- 関数を直接は呼ばせない
select ok(not has_function_privilege('authenticated', 'private.ruuuto_topic_texts(uuid)', 'execute'),
  'authenticated は private.ruuuto_topic_texts を直接呼べない');
select ok(not has_table_privilege('authenticated', 'public.topic_prompt_texts', 'insert'),
  'authenticated は言語別の本文を書き換えられない');

select * from finish();
rollback;
