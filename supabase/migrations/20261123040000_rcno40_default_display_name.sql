-- RCNO-40 メールアドレスから表示名を作らない
--
-- 表示名は同じグループの参加者に見えるため、メールアドレスの@より前を既定にしない。
-- * 新規登録でメタデータに display_name がなければ「メンバー」と4桁の数字（例: メンバー4821）にする。
--   数字はランダムで、重なってもよい（表示名は一意でなくてよい）。
-- * メタデータの display_name があれば、これまでどおり前後の空白を除いて40文字までを使う。
-- * 既存のプロフィールで、表示名が以前の既定（メールの@より前、40文字まで）と同じものは、
--   新しい既定に置き換える。本人が同じ文字列を選んでいた場合も、メールアドレスの一部なので置き換える。
-- 表示名は ruuuto_update_profile でいつでも変えられる。

-- 新しい既定の表示名（メールアドレスは使わない）
create function private.ruuuto_generated_display_name()
returns text
language sql
volatile
set search_path = ''
as $$
  select 'メンバー' || lpad(floor(random() * 10000)::int::text, 4, '0');
$$;

-- 新規登録時の表示名（RCNO-40 の関数を置き換え）。
-- 呼び出し側（ruuuto_handle_new_user）を変えないよう引数は同じにし、p_email は使わない。
create or replace function private.ruuuto_default_display_name(p_email text, p_metadata jsonb)
returns text
language sql
volatile
set search_path = ''
as $$
  select coalesce(
    nullif(left(btrim(p_metadata ->> 'display_name'), 40), ''),
    private.ruuuto_generated_display_name()
  );
$$;

revoke execute on function private.ruuuto_generated_display_name() from public, anon, authenticated;
revoke execute on function private.ruuuto_default_display_name(text, jsonb) from public, anon, authenticated;

-- メールの@より前から作られた表示名を、新しい既定に置き換える。置き換えた件数を返す。
-- 判定は以前の既定と同じ式（前後の空白を除いた@より前、40文字まで）。
create function private.ruuuto_replace_email_display_names()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  update public.profiles p
     set display_name = private.ruuuto_generated_display_name()
    from auth.users u
   where u.id = p.id
     and p.display_name = nullif(left(btrim(split_part(coalesce(u.email, ''), '@', 1)), 40), '');
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function private.ruuuto_replace_email_display_names() from public, anon, authenticated;

-- 既存のプロフィールを置き換える
select private.ruuuto_replace_email_display_names();
