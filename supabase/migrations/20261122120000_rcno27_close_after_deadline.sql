-- RCNO-27 【履歴】締切後の投稿と編集を閉じる
--
-- 締切の決まり（すべての書き込みで同じ）
--   保存する時点のサーバー時刻で判定し、「status = 'open' かつ closes_at > now()」のときだけ書き込める。
--   端末の時計や、操作を始めた時点の状態は見ない。締切をまたいだ操作（締切前につかんで締切後に保存、
--   締切前に投稿を始めて締切後に確定する等）も、保存した時点で締切後なら RC002 で断る。
--   判定は private.ruuuto_require_open_board(board_id) にまとめる（RCNO-19 で用意したもの。
--   ここでは文言を「動かせません」から書き込み全般に合う形へ直す）。
--   既存の ruuuto_begin_photo / ruuuto_finish_photo / ruuuto_save_topic と Storage のアップロード権限は
--   同じ条件を各関数の中で直接書いている。条件が同じことはテスト（rcno27_close_after_deadline）で確かめ、
--   関数は作り直さない。
--
-- 操作ごとの扱い（○ 可 / × RC002）
--   | 操作                                         | 締切前 | 締切後 |
--   | ruuuto_begin_photo（投稿を始める）           | ○      | ×（同じIDの送り直しは既存の行を返す） |
--   | Storage へのアップロード・上書き             | ○      | ×（権限で拒否、42501 相当） |
--   | ruuuto_finish_photo（投稿を確定する）        | ○      | ×（確定済みの送り直しは既存の行を返す） |
--   | ruuuto_grab_photo / ruuuto_move_photo        | ○      | × |
--   | ruuuto_release_photo                         | ○      | ○ |
--   | ruuuto_withdraw_photo（本人の取り下げ）      | ○      | ○ |
--   | Storage から本人の取り下げた画像を消す       | ○      | ○ |
--   | ruuuto_add_decoration（装飾を追加）          | ○      | ×（同じIDの送り直しは既存の行を返す） |
--   | ruuuto_edit_decoration（装飾の中身を変更）   | ○      | × |
--   | ruuuto_grab_decoration / ruuuto_move_decoration | ○   | × |
--   | ruuuto_release_decoration                    | ○      | ○ |
--   | ruuuto_delete_decoration（装飾を消す）       | ○      | × |
--   | ruuuto_save_topic（お題の変更）              | ○      | × |
--   | 閲覧（snapshot・history・都市別・画像の取得）| ○      | ○ |
--   装飾は投稿者だけの非公開の内容ではないので、写真の取り下げと違い、締切後は消せない。
--
-- 装飾の RPC（いずれも所属メンバーだけ。所属していない・対象がないときは 42501）
--   ruuuto_add_decoration(p_decoration_id, p_board_id, p_kind, p_content, p_x, p_y,
--                         p_rotation default 0, p_scale default 1)
--     p_decoration_id はiOSが追加前に決めるUUID。同じ人が同じボードに送り直したら既存の行を返す。
--     ほかの人・ほかのボードで使われているIDなら RC009。
--     重なり順は、そのボードの装飾の最大 z_index + 1（一番上に置く）。
--   ruuuto_edit_decoration(p_decoration_id, p_content)
--     中身（文字の内容や色など）を変える。先に ruuuto_grab_decoration でつかんでいる人だけ。
--     つかんでいなければ RC013、ほかの人がつかんでいれば RC012（RCNO-19 と同じ）。
--     revision を1増やし、つかみの期限を延ばす。中身が同じなら保存せず今の状態を返す。
--     ペンは描いたら変えない決まりなので RC014。種類（kind）は変えられない。
--   ruuuto_delete_decoration(p_decoration_id)
--     追加した本人だけが消せる（ほかの人は 42501。写真の取り下げと同じく本人だけ）。
--     ほかの人がつかんでいる間は RC012。消すとき自分がつかんでいる必要はない。
--     すでに消えているIDは、エラーにせず {id, deleted: false} を返す（送り直しても安全）。
--     消したら {id, deleted: true}。board:<id> に decoration_deleted {id, board_id} が届く。
--   add / edit の戻り値は decoration_saved と同じ形に locked_by, lock_expires_at を足したもの。
--   保存すると board:<id> に decoration_saved が届く（RCNO-36 のトリガー）。
--
-- 装飾の content の形（推奨。サーバーは下の「最低限」だけを検査する）
--   text  {"text": "こんにちは", "color": "#FF3366"}
--         最低限: text が空白だけでない文字列で200文字以内
--   stamp {"stamp_id": "star"}
--         最低限: stamp_id が空でない文字列
--   pen   {"strokes": [{"points": [[x, y], [x, y], ...], "color": "#000000", "width": 4}]}
--         最低限: strokes が配列
--   いずれも JSON オブジェクトで 64KB 以内（データモデルの制約と同じ）。
--   x, y と points の座標の単位（ボード上の点か、0〜1 の割合か）は、iOS とデザイン担当でまだ決めていない。
--
-- エラー（コードは表示言語に依存しない。表示する文言はiOS側で決める）
--   RC002 締切後（ボードが open でない、または closes_at を過ぎた）
--   RC009 同じIDの別の装飾がある（ほかの人・ほかのボード）
--   RC012 ほかの人がつかんでいる。DETAIL は JSON {"locked_by", "lock_expires_at"}
--   RC013 つかんでいない（edit の前に grab が必要。期限切れも同じ）
--   RC014 装飾の内容が正しくない（種類・content・数値。ペンの中身の変更もこれ）
--   42501 未ログイン・所属していない・対象がない・本人以外の削除

-- 締切前のボードか（RC002）。RCNO-19 の関数の文言を、書き込み全般に合う形へ直す。
create or replace function private.ruuuto_require_open_board(p_board_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.boards b
    where b.id = p_board_id and b.status = 'open' and b.closes_at > now()
  ) then
    raise exception '締切を過ぎたため変更できません' using errcode = 'RC002';
  end if;
end;
$$;

-- 装飾の種類と content を確かめる（RC014）
create function private.ruuuto_require_decoration_content(p_kind text, p_content jsonb)
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
        and btrim(p_content ->> 'text') <> ''
        and char_length(p_content ->> 'text') <= 200
      when 'stamp' then
        jsonb_typeof(p_content -> 'stamp_id') = 'string'
        and btrim(p_content ->> 'stamp_id') <> ''
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

-- 装飾を追加する
create function public.ruuuto_add_decoration(
  p_decoration_id uuid,
  p_board_id uuid,
  p_kind text,
  p_content jsonb,
  p_x double precision,
  p_y double precision,
  p_rotation double precision default 0,
  p_scale double precision default 1
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_decoration public.decorations%rowtype;
begin
  v_user_id := private.ruuuto_require_board_member(p_board_id);

  if p_decoration_id is null
     or p_x is null or p_y is null or p_rotation is null or p_scale is null
     or p_x in ('NaN', 'Infinity', '-Infinity')
     or p_y in ('NaN', 'Infinity', '-Infinity')
     or p_rotation in ('NaN', 'Infinity', '-Infinity')
     or p_scale in ('NaN', 'Infinity', '-Infinity')
     or p_scale <= 0 then
    raise exception '装飾の内容が正しくありません' using errcode = 'RC014';
  end if;
  perform private.ruuuto_require_decoration_content(p_kind, p_content);

  -- 送り直し: 同じ人が同じボードに追加した行があれば、それを返す
  select * into v_decoration from public.decorations d where d.id = p_decoration_id;
  if found then
    if v_decoration.created_by <> v_user_id or v_decoration.board_id <> p_board_id then
      raise exception '同じIDの別の装飾があります' using errcode = 'RC009';
    end if;
    return (private.ruuuto_decoration_json(v_decoration)
            || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
  end if;

  perform private.ruuuto_require_open_board(p_board_id);

  -- 重なり順を決める間、同じボードの装飾の z_index の更新を順番に並べる（grab_decoration と同じキー）
  perform pg_advisory_xact_lock(hashtextextended('ruuuto_dz:' || p_board_id, 0));

  insert into public.decorations
    (id, board_id, created_by, kind, content, x, y, rotation, scale, z_index, updated_by)
  values
    (p_decoration_id, p_board_id, v_user_id, p_kind, p_content, p_x, p_y, p_rotation, p_scale,
     coalesce((select max(d.z_index) from public.decorations d where d.board_id = p_board_id), 0) + 1,
     v_user_id)
  on conflict (id) do nothing
  returning * into v_decoration;

  -- 同じIDで同時に追加された（同じ人の送り直しが重なった等）: 先に入った行で判定し直す
  if v_decoration.id is null then
    select * into v_decoration from public.decorations d where d.id = p_decoration_id;
    if v_decoration.created_by <> v_user_id or v_decoration.board_id <> p_board_id then
      raise exception '同じIDの別の装飾があります' using errcode = 'RC009';
    end if;
  end if;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- 装飾の中身を変える（つかんでいる人だけ。ペンは不可）
create function public.ruuuto_edit_decoration(p_decoration_id uuid, p_content jsonb)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_decoration public.decorations%rowtype := private.ruuuto_lock_decoration_row(p_decoration_id, false);
begin
  if v_decoration.kind = 'pen' then
    raise exception 'ペンの装飾は変更できません' using errcode = 'RC014';
  end if;
  perform private.ruuuto_require_open_board(v_decoration.board_id);
  perform private.ruuuto_require_decoration_content(v_decoration.kind, p_content);

  if v_decoration.locked_by is null or v_decoration.lock_expires_at <= now() then
    raise exception 'この装飾をつかんでいません' using errcode = 'RC013';
  end if;
  if v_decoration.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_decoration.locked_by, v_decoration.lock_expires_at);
  end if;

  update public.decorations d
     set content = p_content,
         revision = d.revision + case when d.content = p_content then 0 else 1 end,
         updated_by = case when d.content = p_content then d.updated_by else v_user_id end,
         lock_expires_at = now() + private.ruuuto_lock_lease()
   where d.id = v_decoration.id
  returning * into v_decoration;

  return (private.ruuuto_decoration_json(v_decoration)
          || private.ruuuto_lock_json(v_decoration.locked_by, v_decoration.lock_expires_at))::json;
end;
$$;

-- 装飾を消す（追加した本人だけ。締切前のみ）
create function public.ruuuto_delete_decoration(p_decoration_id uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
  v_decoration public.decorations%rowtype;
begin
  select * into v_decoration from public.decorations d where d.id = p_decoration_id for update;
  if not found then
    return json_build_object('id', p_decoration_id, 'deleted', false);
  end if;

  perform private.ruuuto_require_board_member(v_decoration.board_id);
  if v_decoration.created_by <> v_user_id then
    raise exception 'この装飾を消す権限がありません' using errcode = '42501';
  end if;
  perform private.ruuuto_require_open_board(v_decoration.board_id);

  if v_decoration.locked_by is not null and v_decoration.lock_expires_at > now()
     and v_decoration.locked_by <> v_user_id then
    perform private.ruuuto_raise_locked(v_decoration.locked_by, v_decoration.lock_expires_at);
  end if;

  delete from public.decorations d where d.id = v_decoration.id;
  return json_build_object('id', v_decoration.id, 'deleted', true);
end;
$$;

revoke execute on function private.ruuuto_require_open_board(uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_decoration_content(text, jsonb) from public, anon, authenticated;

revoke execute on function public.ruuuto_add_decoration(uuid, uuid, text, jsonb, double precision, double precision, double precision, double precision) from public, anon;
revoke execute on function public.ruuuto_edit_decoration(uuid, jsonb) from public, anon;
revoke execute on function public.ruuuto_delete_decoration(uuid) from public, anon;
grant execute on function public.ruuuto_add_decoration(uuid, uuid, text, jsonb, double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.ruuuto_edit_decoration(uuid, jsonb) to authenticated;
grant execute on function public.ruuuto_delete_decoration(uuid) to authenticated;
