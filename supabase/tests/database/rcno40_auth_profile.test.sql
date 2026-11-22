-- RCNO-40 Authの利用者IDとプロフィールの対応
begin;
select plan(11);

-- 新規利用: Authに利用者が入るとプロフィールができる
insert into auth.users (id, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-0000000040a1', 'hanako@example.com', '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000040b1', 'taro@example.com', '{"display_name": "  たろう  "}'::jsonb);

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040a1'),
  'hanako', '表示名の既定はメールの@より前');
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040b1'),
  'たろう', 'メタデータの display_name があれば前後の空白を除いて使う');

-- 本人として取得する
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "00000000-0000-0000-0000-0000000040a1", "role": "authenticated"}', true);

select is(
  public.ruuuto_my_profile()::jsonb,
  '{"id": "00000000-0000-0000-0000-0000000040a1", "display_name": "hanako"}'::jsonb,
  '本人のIDと表示名を返す');

select is(
  public.ruuuto_update_profile('  はなこ ')::jsonb ->> 'display_name',
  'はなこ', '表示名を変えられる（前後の空白は除く）');

select throws_ok(
  $$ select public.ruuuto_update_profile('   ') $$,
  'RC005', null, '空白だけの表示名は RC005');
select throws_ok(
  $$ select public.ruuuto_update_profile(repeat('あ', 41)) $$,
  'RC005', null, '41文字の表示名は RC005');

-- 再ログイン: 同じ利用者IDなら同じプロフィールを取得する
select set_config('request.jwt.claims',
  '{"sub": "00000000-0000-0000-0000-0000000040a1", "role": "authenticated"}', true);
select is(
  public.ruuuto_my_profile()::jsonb ->> 'display_name',
  'はなこ', '再ログイン後も同じプロフィール');

-- 別の利用者は自分のプロフィールだけを取得する
select set_config('request.jwt.claims',
  '{"sub": "00000000-0000-0000-0000-0000000040b1", "role": "authenticated"}', true);
select is(
  public.ruuuto_my_profile()::jsonb ->> 'id',
  '00000000-0000-0000-0000-0000000040b1', '他人のプロフィールは返さない');

-- 利用者IDのないセッションは拒否する
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok(
  $$ select public.ruuuto_my_profile() $$,
  '42501', null, '利用者IDがなければ 42501');

-- 未ログイン（anon）は関数を実行できない
reset role;
set local role anon;
select throws_ok(
  $$ select public.ruuuto_my_profile() $$,
  '42501', null, 'anon は ruuuto_my_profile を実行できない');
reset role;

-- Authの利用者を消すとプロフィールも消える
delete from auth.users where id = '00000000-0000-0000-0000-0000000040b1';
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000040b1'),
  0, 'Authの利用者を消すとプロフィールも消える');

select * from finish();
rollback;
