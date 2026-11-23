-- RCNO-34 空白だけの名前やお題を受け付けない
-- タブ・改行・全角スペースだけの入力を、これまでと同じエラーコードで拒否する。
begin;
select plan(31);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000034f1', 'blank-a@example.com');
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000034f2', 'blank-b@example.com', jsonb_build_object('display_name', E'\t\n'));

-- 登録時のメタデータが空白だけなら既定の表示名
select matches(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000034f2'),
  '^メンバー[0-9]{4}$', 'メタデータの表示名がタブと改行だけなら既定の表示名');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000034f1');

-- グループ名（RC006）
select throws_ok($$ select public.ruuuto_create_group(E'\t\t', gen_random_uuid()) $$, 'RC006', null, 'タブだけのグループ名は RC006');
select throws_ok($$ select public.ruuuto_create_group(E'\n\r\n', gen_random_uuid()) $$, 'RC006', null, '改行だけのグループ名は RC006');
select throws_ok($$ select public.ruuuto_create_group('　　', gen_random_uuid()) $$, 'RC006', null, '全角スペースだけのグループ名は RC006');
select is(
  public.ruuuto_create_group(E'\t週末写真部\n', '34f00000-0000-0000-0000-000000000001')::jsonb ->> 'name',
  '週末写真部', '前後のタブ・改行は除いて保存する');
select is(
  public.ruuuto_create_group('Photo Club', gen_random_uuid())::jsonb ->> 'name',
  'Photo Club', '英語のグループ名（間のスペースはそのまま）');

-- 表示名（RC005）
select throws_ok($$ select public.ruuuto_update_profile(E'\t') $$, 'RC005', null, 'タブだけの表示名は RC005');
select throws_ok($$ select public.ruuuto_update_profile(E'\n\n') $$, 'RC005', null, '改行だけの表示名は RC005');
select throws_ok($$ select public.ruuuto_update_profile(E' 　\t') $$, 'RC005', null, '空白の組み合わせだけの表示名は RC005');
select is(public.ruuuto_update_profile(E'　あゆむ\n')::jsonb ->> 'display_name', 'あゆむ', '前後の全角スペースと改行は除く');
select is(public.ruuuto_update_profile('Ayumu K')::jsonb ->> 'display_name', 'Ayumu K', '英語の表示名');

-- お題（RC001）
create temp table g as
  select b.id as board_id from public.boards b
  join public.groups gr on gr.id = b.group_id
  where gr.create_request_id = '34f00000-0000-0000-0000-000000000001' and b.status = 'open';
reset role;
grant select on g to authenticated;
-- 締切をテスト実行時より後にずらしておく
update public.boards set closes_at = now() + interval '6 days' where id = (select board_id from g);
set local role authenticated;
select throws_ok($$ select public.ruuuto_save_topic((select board_id from g), E'\t') $$, 'RC001', null, 'タブだけのお題は RC001');
select throws_ok($$ select public.ruuuto_save_topic((select board_id from g), E'\n') $$, 'RC001', null, '改行だけのお題は RC001');
select is(public.ruuuto_save_topic((select board_id from g), E'\t窓の外\n')::jsonb ->> 'topic', '窓の外', 'お題の前後の空白は除く');
select is(public.ruuuto_save_topic((select board_id from g), 'Window view')::jsonb ->> 'topic', 'Window view', '英語のお題');

-- 装飾の文字・スタンプ（RC014）
select throws_ok(
  $$ select public.ruuuto_add_decoration(gen_random_uuid(), (select board_id from g), 'text', jsonb_build_object('text', E'\t\n'), 0, 0) $$,
  'RC014', null, 'タブと改行だけの文字の装飾は RC014');
select throws_ok(
  $$ select public.ruuuto_add_decoration(gen_random_uuid(), (select board_id from g), 'stamp', jsonb_build_object('stamp_id', E'\n'), 0, 0) $$,
  'RC014', null, '改行だけのスタンプIDは RC014');
select lives_ok(
  $$ select public.ruuuto_add_decoration(gen_random_uuid(), (select board_id from g), 'text', '{"text": "さむっ！"}', 0, 0) $$,
  '普通の文字の装飾は追加できる');

-- 都市名: 空白だけなら未設定（null）
select is(
  public.ruuuto_begin_photo('34f20000-0000-0000-0000-000000000001', (select board_id from g), E'\t\n')::jsonb -> 'city',
  'null'::jsonb, 'タブと改行だけの都市名は未設定になる');
select is(
  public.ruuuto_begin_photo('34f20000-0000-0000-0000-000000000002', (select board_id from g), E'\tVancouver\n')::jsonb ->> 'city',
  'Vancouver', '都市名の前後の空白は除く');
select throws_ok(
  $$ select public.ruuuto_begin_photo(gen_random_uuid(), (select board_id from g), repeat('あ', 61)) $$,
  'RC008', null, '61文字の都市名はこれまでどおり RC008');
reset role;

-- テーブルの制約（RPCを通さない書き込みも拒否する）
select throws_ok(
  $$ update public.groups set name = E'\t\n' where create_request_id = '34f00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'groups: タブと改行だけの名前は保存できない');
select throws_ok(
  $$ update public.profiles set display_name = '　' where id = '00000000-0000-0000-0000-0000000034f1' $$,
  '23514', null, 'profiles: 全角スペースだけの表示名は保存できない');
select throws_ok(
  $$ update public.boards set topic = E'\n' where id = (select board_id from g) $$,
  '23514', null, 'boards: 改行だけのお題は保存できない');
select throws_ok(
  $$ update public.photos set city = E'\t' where id = '34f20000-0000-0000-0000-000000000002' $$,
  '23514', null, 'photos: タブだけの都市名は保存できない');
select throws_ok(
  $$ update public.topic_prompts set body = E'\t' where month = 11 and week = 3 $$,
  '23514', null, 'topic_prompts: タブだけのお題は保存できない');
select throws_ok(
  $$ update public.topic_prompt_texts set body = E'\n' where locale = 'en' $$,
  '23514', null, 'topic_prompt_texts: 改行だけの本文は保存できない');
select lives_ok(
  $$ update public.groups set name = '週末 写真部' where create_request_id = '34f00000-0000-0000-0000-000000000001' $$,
  'groups: 間にスペースのある名前は保存できる');

-- 制約は有効（not valid のまま残っていない）
select is(
  (select count(*)::int from pg_constraint
   where conname in ('profiles_display_name_not_blank', 'groups_name_not_blank', 'topic_prompts_body_not_blank',
                     'topic_prompt_texts_body_not_blank', 'boards_topic_not_blank', 'photos_city_not_blank')
     and convalidated),
  6, '6つの制約がすべて検証済み');

-- 既存の固定のお題48件と英語の本文は制約を満たす
select is((select count(*)::int from public.topic_prompts where body ~ '[^[:space:]　]'), 48, '固定のお題48件は制約を満たす');
select ok(not has_function_privilege('authenticated', 'private.ruuuto_trim(text)', 'execute'),
  'authenticated は private.ruuuto_trim を直接呼べない');

select * from finish();
rollback;
