-- RCNO-40 メールアドレスから表示名を作らない
begin;
select plan(11);

-- 新規登録: メタデータがなければ「メンバー」と4桁の数字
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000040c1', 'sakura.private@example.com', '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000040c2', 'kenji@example.com', null),
  ('00000000-0000-0000-0000-0000000040c3', 'yuki@example.com', '{"display_name": "  ゆき  "}'::jsonb),
  ('00000000-0000-0000-0000-0000000040c4', 'mika@example.com', '{"display_name": "   "}'::jsonb);

select matches(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c1'),
  '^メンバー[0-9]{4}$', 'メタデータが空なら「メンバー」と4桁の数字');
select ok(
  (select position('sakura' in display_name) = 0 from public.profiles where id = '00000000-0000-0000-0000-0000000040c1'),
  '既定の表示名にメールの@より前を含めない');
select matches(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c2'),
  '^メンバー[0-9]{4}$', 'メタデータがなくても「メンバー」と4桁の数字');
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c3'),
  'ゆき', 'メタデータの display_name があれば、前後の空白を除いて使う');
select matches(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c4'),
  '^メンバー[0-9]{4}$', 'メタデータの display_name が空白だけなら既定の表示名');

-- 既存のプロフィールの置き換え（マイグレーションが呼ぶ関数を、以前の既定のままの行に当てる）
update public.profiles set display_name = 'sakura.private' where id = '00000000-0000-0000-0000-0000000040c1';
update public.profiles set display_name = 'けんじ' where id = '00000000-0000-0000-0000-0000000040c2';
select is(private.ruuuto_replace_email_display_names(), 1, '置き換えるのは以前の既定のままの1件だけ');
select matches(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c1'),
  '^メンバー[0-9]{4}$', 'メールの@より前のままの表示名は、新しい既定に置き換わる');
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c2'),
  'けんじ', '本人が変えた表示名はそのまま');
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000040c3'),
  'ゆき', 'メタデータから作った表示名もそのまま');

-- 表示名の変更はこれまでどおり
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "00000000-0000-0000-0000-0000000040c1", "role": "authenticated"}', true);
select is(
  public.ruuuto_update_profile(' さくら ')::jsonb ->> 'display_name',
  'さくら', 'ruuuto_update_profile で表示名を変えられる');
reset role;

select ok(not has_function_privilege('authenticated', 'private.ruuuto_generated_display_name()', 'execute')
          and not has_function_privilege('authenticated', 'private.ruuuto_replace_email_display_names()', 'execute'),
  'authenticated は既定の表示名を作る関数と置き換える関数を直接呼べない');

select * from finish();
rollback;
