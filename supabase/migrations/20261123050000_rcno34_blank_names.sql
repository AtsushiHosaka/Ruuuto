-- RCNO-34 空白だけの名前やお題を受け付けない
--
-- btrim は半角スペースしか除かないため、タブ・改行・全角スペースだけの名前やお題が通っていた
-- （CodeRabbit の指摘、#14）。
-- * 前後の空白は、半角スペース・タブ・改行・全角スペースなど（[[:space:]] と U+3000）をまとめて除く。
--   除いた結果が空なら、これまでと同じエラーコードで拒否する。
--     グループ名 RC006 / 表示名 RC005 / お題 RC001 / 装飾の文字・スタンプ RC014
--   都市名だけは、これまでスペースだけを「未設定」として受け付けていたので、空白だけなら null にする。
-- * テーブルにも、空白以外の文字を1文字以上含む制約を足す。
--   既存の行に空白だけの値があれば、先に既定の値へ直してから制約を有効にする。

-- 前後の空白（[[:space:]] と全角スペース）を除く
create function private.ruuuto_trim(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(p_text, '^[[:space:]　]+|[[:space:]　]+$', '', 'g');
$$;

revoke execute on function private.ruuuto_trim(text) from public, anon, authenticated;

-- グループ名（RC006）。RCNO-42 の関数を置き換え。
create or replace function public.ruuuto_create_group(p_name text, p_request_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_name text := private.ruuuto_trim(coalesce(p_name, ''));
  v_group_id uuid;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_prompt_id uuid;
  v_topic text;
begin
  if p_request_id is null then
    raise exception '作成要求のIDが必要です' using errcode = '22004';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'グループ名は1〜40文字で入力してください' using errcode = 'RC006';
  end if;

  insert into public.groups (name, created_by, create_request_id)
  values (v_name, v_user_id, p_request_id)
  on conflict (created_by, create_request_id) do nothing
  returning id into v_group_id;

  if v_group_id is null then
    -- 送り直し。前回のグループを返す
    select g.id into v_group_id
    from public.groups g
    where g.created_by = v_user_id and g.create_request_id = p_request_id;
    return private.ruuuto_group_json(v_group_id);
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_user_id, 'owner');

  select w.opens_at, w.closes_at into v_opens_at, v_closes_at
  from private.ruuuto_week_window(now()) w;
  select p.prompt_id, p.topic into v_prompt_id, v_topic
  from private.ruuuto_weekly_prompt(v_opens_at) p;

  insert into public.boards (group_id, topic, topic_source, prompt_id, opens_at, closes_at)
  values (v_group_id, v_topic, 'weekly', v_prompt_id, v_opens_at, v_closes_at);

  return private.ruuuto_group_json(v_group_id);
end;
$$;

-- 表示名（RC005）。RCNO-40 の関数を置き換え。
create or replace function public.ruuuto_update_profile(p_display_name text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_name text := private.ruuuto_trim(coalesce(p_display_name, ''));
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

-- お題（RC001）。RCNO-41 の関数を置き換え。
create or replace function public.ruuuto_save_topic(p_board_id uuid, p_topic text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_board public.boards%rowtype;
  v_topic text := private.ruuuto_trim(coalesce(p_topic, ''));
begin
  v_user_id := private.ruuuto_require_board_member(p_board_id);

  if char_length(v_topic) not between 1 and 80 then
    raise exception 'お題は1〜80文字で入力してください' using errcode = 'RC001';
  end if;

  -- 同時に変更されても順に処理する
  select * into v_board from public.boards b where b.id = p_board_id for update;

  if v_board.status <> 'open' or v_board.closes_at <= now() then
    raise exception '締切を過ぎたため、お題を変更できません' using errcode = 'RC002';
  end if;

  if v_board.topic is distinct from v_topic then
    update public.boards b
       set topic = v_topic, topic_source = 'custom', prompt_id = null
     where b.id = p_board_id
    returning * into v_board;

    insert into public.notification_events (kind, group_id, board_id, topic, actor_id)
    values ('topic_changed', v_board.group_id, v_board.id, v_topic, v_user_id);
  end if;

  return json_build_object(
    'id', v_board.id,
    'group_id', v_board.group_id,
    'topic', v_board.topic,
    'opens_at', private.ruuuto_ts(v_board.opens_at),
    'closes_at', private.ruuuto_ts(v_board.closes_at),
    'status', v_board.status);
end;
$$;

-- 都市名（61文字以上は RC008）。空白だけなら、これまでのスペースだけと同じく未設定（null）にする。
-- RCNO-35 の関数を置き換え。
create or replace function public.ruuuto_begin_photo(
  p_photo_id uuid,
  p_board_id uuid,
  p_city text default null,
  p_width int default null,
  p_height int default null
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_board public.boards%rowtype;
  v_photo public.photos%rowtype;
  v_city text := nullif(private.ruuuto_trim(coalesce(p_city, '')), '');
begin
  v_user_id := private.ruuuto_require_board_member(p_board_id);

  if p_photo_id is null
     or (v_city is not null and char_length(v_city) > 60)
     or (p_width is not null and p_width <= 0)
     or (p_height is not null and p_height <= 0) then
    raise exception '写真の情報が正しくありません' using errcode = 'RC008';
  end if;

  -- 送り直し: 同じIDの行があれば、それを返す
  select * into v_photo from public.photos p where p.id = p_photo_id;
  if found then
    if v_photo.posted_by <> v_user_id or v_photo.board_id <> p_board_id then
      raise exception '同じIDの別の写真があります' using errcode = 'RC009';
    end if;
    if v_photo.status = 'withdrawn' then
      raise exception 'この写真は取り下げ済みです' using errcode = 'RC010';
    end if;
    return private.ruuuto_photo_json(v_photo);
  end if;

  select * into v_board from public.boards b where b.id = p_board_id;
  if v_board.status <> 'open' or v_board.closes_at <= now() then
    raise exception '締切を過ぎたため投稿できません' using errcode = 'RC002';
  end if;

  insert into public.photos (id, board_id, posted_by, storage_path, status, city, width, height)
  values (p_photo_id, p_board_id, v_user_id,
          v_board.group_id || '/' || v_board.id || '/' || p_photo_id,
          'pending', v_city, p_width, p_height)
  returning * into v_photo;

  return private.ruuuto_photo_json(v_photo);
end;
$$;

-- 装飾の文字・スタンプ（RC014）。RCNO-27 の関数を置き換え。
create or replace function private.ruuuto_require_decoration_content(p_kind text, p_content jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ok boolean;
begin
  v_ok := p_kind is not null and p_content is not null
          and jsonb_typeof(p_content) = 'object'
          and pg_column_size(p_content) <= 65536;

  if v_ok then
    v_ok := case p_kind
      when 'text' then
        jsonb_typeof(p_content -> 'text') = 'string'
        and private.ruuuto_trim(p_content ->> 'text') <> ''
        and char_length(p_content ->> 'text') <= 200
      when 'stamp' then
        jsonb_typeof(p_content -> 'stamp_id') = 'string'
        and private.ruuuto_trim(p_content ->> 'stamp_id') <> ''
      when 'pen' then
        jsonb_typeof(p_content -> 'strokes') = 'array'
      else false
    end;
  end if;

  if not coalesce(v_ok, false) then
    raise exception '装飾の内容が正しくありません' using errcode = 'RC014';
  end if;
end;
$$;

-- 都市別の写真一覧の都市名も同じ規則でそろえる。RCNO-43 の関数を置き換え。
create or replace function public.ruuuto_city_photos(p_board_id uuid, p_city text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.ruuuto_require_board_member(p_board_id);

  return coalesce((
    select json_agg(json_build_object(
             'id', p.id,
             'storage_path', p.storage_path,
             'city', p.city,
             'posted_by', p.posted_by,
             'display_name', pr.display_name,
             'posted_at', private.ruuuto_ts(coalesce(p.posted_at, p.created_at)),
             'width', p.width,
             'height', p.height)
           order by coalesce(p.posted_at, p.created_at), p.id)
    from public.photos p
    join public.profiles pr on pr.id = p.posted_by
    where p.board_id = p_board_id
      and p.status = 'posted'
      and p.city = private.ruuuto_trim(p_city)
  ), '[]'::json);
end;
$$;

-- 登録時のメタデータの表示名。空白だけなら既定の表示名にする。RCNO-40 の関数を置き換え。
create or replace function private.ruuuto_default_display_name(p_email text, p_metadata jsonb)
returns text
language sql
volatile
set search_path = ''
as $$
  select coalesce(
    nullif(left(private.ruuuto_trim(p_metadata ->> 'display_name'), 40), ''),
    private.ruuuto_generated_display_name()
  );
$$;

-- テーブルの制約。既存の空白だけの値を直してから有効にする。
update public.profiles set display_name = private.ruuuto_generated_display_name()
 where display_name !~ '[^[:space:]　]';
update public.groups set name = 'グループ' where name !~ '[^[:space:]　]';
update public.boards set topic = '今週の一枚' where topic !~ '[^[:space:]　]';
update public.photos set city = null where city !~ '[^[:space:]　]';

alter table public.profiles
  add constraint profiles_display_name_not_blank check (display_name ~ '[^[:space:]　]') not valid;
alter table public.groups
  add constraint groups_name_not_blank check (name ~ '[^[:space:]　]') not valid;
alter table public.topic_prompts
  add constraint topic_prompts_body_not_blank check (body ~ '[^[:space:]　]') not valid;
alter table public.topic_prompt_texts
  add constraint topic_prompt_texts_body_not_blank check (body ~ '[^[:space:]　]') not valid;
alter table public.boards
  add constraint boards_topic_not_blank check (topic ~ '[^[:space:]　]') not valid;
alter table public.photos
  add constraint photos_city_not_blank check (city is null or city ~ '[^[:space:]　]') not valid;

alter table public.profiles validate constraint profiles_display_name_not_blank;
alter table public.groups validate constraint groups_name_not_blank;
alter table public.topic_prompts validate constraint topic_prompts_body_not_blank;
alter table public.topic_prompt_texts validate constraint topic_prompt_texts_body_not_blank;
alter table public.boards validate constraint boards_topic_not_blank;
alter table public.photos validate constraint photos_city_not_blank;
