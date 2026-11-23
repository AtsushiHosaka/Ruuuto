-- RCNO-4 固定のお題48件
-- 定量目標: 12か月 × 第1〜4週がそろい、週の切替で正しい週のお題が選ばれる。第5週は既定の文言。
begin;
select plan(9);

select is((select count(*)::int from public.topic_prompts), 48, 'お題は48件');
select is(
  (select count(*)::int from (select month from public.topic_prompts group by month having count(*) = 4) m),
  12, '12か月それぞれに4週分ある');
select is((select count(*)::int from public.topic_prompts where week = 5), 0, '第5週の行はまだない');
select is((select max(char_length(body)) <= 80 from public.topic_prompts), true, 'どのお題もボードのお題の上限（80文字）に収まる');

-- 週の開始日（月曜 UTC）から選ばれるお題
select is((select topic from private.ruuuto_weekly_prompt('2026-11-16 00:00+00')),
  '自分の部屋の「お気に入りスペース」', '11/16 始まりは11月の第3週');
select is((select topic from private.ruuuto_weekly_prompt('2027-01-04 00:00+00')),
  '新年の挨拶・お正月の風景（Happy New Year!）', '1/4 始まりは1月の第1週');
select is((select topic from private.ruuuto_weekly_prompt('2026-11-30 00:00+00')),
  '今週の一枚', '11/30 始まり（第5週）は既定の文言');
select ok((select prompt_id is not null from private.ruuuto_weekly_prompt('2026-12-21 00:00+00')),
  '固定のお題を使ったボードは prompt_id でお題を覚える');

-- 週の切替で作られるボードにもお題が入る
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000004a1', 'topic4@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('04000000-0000-0000-0000-000000000001', 'お題班', '00000000-0000-0000-0000-0000000004a1', gen_random_uuid());
select private.ruuuto_rotate_week('2026-12-14 00:05+00');
select is(
  (select topic from public.boards where group_id = '04000000-0000-0000-0000-000000000001' and status = 'open'),
  'あなたの国の「ホリデーシーズンの過ごし方」', '12/14 の切替で12月の第2週のお題のボードができる');

select * from finish();
rollback;
