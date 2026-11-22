-- RCNO-40 Supabase Authと参加者情報
--
-- 本人確認はメールアドレスとパスワード（2026年11月21日の決定）。
-- Authで利用者が作られたら、同じIDのプロフィールを自動で作る。
-- iOSは ruuuto_my_profile で表示名を取得し、ruuuto_update_profile で変更する。

-- 外部に公開しない補助関数を置くスキーマ。PostgRESTの公開対象には含めない。
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- ログイン中の利用者ID。未ログインなら 42501 で拒否する。
create function private.ruuuto_require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  return v_user_id;
end;
$$;

-- 新規登録時の表示名。iOSの登録画面はメールとパスワードだけなので、
-- メタデータに display_name があればそれを、なければメールの@より前を使う。
create function private.ruuuto_default_display_name(p_email text, p_metadata jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    nullif(left(btrim(p_metadata ->> 'display_name'), 40), ''),
    nullif(left(btrim(split_part(coalesce(p_email, ''), '@', 1)), 40), ''),
    '参加者'
  );
$$;

-- auth.users に行が入ったらプロフィールを作る
create function private.ruuuto_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, private.ruuuto_default_display_name(new.email, new.raw_user_meta_data))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger ruuuto_on_auth_user_created
  after insert on auth.users
  for each row execute function private.ruuuto_handle_new_user();

-- このマイグレーションより前に登録済みの利用者にもプロフィールを作る
insert into public.profiles (id, display_name)
select u.id, private.ruuuto_default_display_name(u.email, u.raw_user_meta_data)
from auth.users u
on conflict (id) do nothing;

-- 自分のプロフィールを返す: {"id": uuid, "display_name": text}
create function public.ruuuto_my_profile()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_result json;
begin
  select json_build_object('id', p.id, 'display_name', p.display_name)
    into v_result
  from public.profiles p
  where p.id = v_user_id;

  if v_result is null then
    -- Authにはいるがプロフィールがない（削除直後など）。iOSはサインアウトして扱う。
    raise exception 'プロフィールが見つかりません' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 自分の表示名を変える。前後の空白を除いて1〜40文字。不正なら RC005。
create function public.ruuuto_update_profile(p_display_name text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_name text := btrim(coalesce(p_display_name, ''));
  v_result json;
begin
  if char_length(v_name) not between 1 and 40 then
    raise exception '表示名は1〜40文字で入力してください' using errcode = 'RC005';
  end if;

  update public.profiles p
     set display_name = v_name
   where p.id = v_user_id
  returning json_build_object('id', p.id, 'display_name', p.display_name)
    into v_result;

  if v_result is null then
    raise exception 'プロフィールが見つかりません' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 実行できるのはログイン済みの利用者だけ
revoke execute on function private.ruuuto_require_user() from public, anon;
revoke execute on function private.ruuuto_default_display_name(text, jsonb) from public, anon, authenticated;
revoke execute on function private.ruuuto_handle_new_user() from public, anon, authenticated;
revoke execute on function public.ruuuto_my_profile() from public, anon;
revoke execute on function public.ruuuto_update_profile(text) from public, anon;
grant execute on function private.ruuuto_require_user() to authenticated;
grant execute on function public.ruuuto_my_profile() to authenticated;
grant execute on function public.ruuuto_update_profile(text) to authenticated;
