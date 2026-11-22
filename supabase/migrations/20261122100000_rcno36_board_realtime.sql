-- RCNO-36 ボード単位のリアルタイム配信
--
-- ボードごとに2つの非公開チャネルを使う。iOSは購読時に config: { private: true } を渡す。
--
--   board:<board_id>       保存済みの変更。送るのはデータベースのトリガーだけ。
--                          所属メンバーは受信できる。アプリからは送信できない
--                          （偽の「保存済み」イベントを防ぐため、送信のポリシーを置かない）。
--   board:<board_id>:live  一時的な情報（カーソルの Broadcast と Presence）。
--                          所属メンバーが送信・受信できる。保存はしない。
--
-- どちらも、ボードのグループに所属していなければ参加できない（未ログインも不可）。
-- 締切後のボードも閲覧できるので、受信とカーソル・Presence の送信は締切後も許可する
-- （書き込みはRPC側で締め切るため、一時的な情報を許しても保存内容は変わらない）。
-- 形式が違うトピック（UUIDでない、余計な接尾辞がある等）はエラーにせず拒否する。
--
-- board:<board_id> のイベント（名前と項目は表示言語に依存しない英語の識別子）
--   photo_saved        写真が投稿済みになった、または投稿済みの写真の配置等が変わった。
--                      payload は ruuuto_begin_photo などと同じ写真の形
--                      {id, board_id, posted_by, bucket, storage_path, status, city, width, height,
--                       x, y, rotation, scale, z_index, revision, posted_at}
--   photo_withdrawn    投稿済みの写真が取り下げられた。{id, board_id}
--   decoration_saved   装飾が追加・変更された。
--                      {id, board_id, created_by, kind, content, x, y, rotation, scale, z_index,
--                       revision, updated_by, created_at, updated_at}
--   decoration_deleted 装飾が消された。{id, board_id}
--   board_updated      お題・状態・期間が変わった。ruuuto_current_board と同じ形
--                      {id, group_id, topic, opens_at, closes_at, status}
--                      status が closed になったら、iOSは ruuuto_current_board で次のボードを開き直す。
-- 投稿途中（pending）の写真は配信しない（投稿者以外に見せないため）。
-- 投稿途中から取り下げた写真も、他の人は見ていないので配信しない。
-- 中身が変わらない更新（updated_at だけが変わる等）は配信しない。
--
-- board:<board_id>:live の推奨形式（サーバーでは中身を検査しない）
--   Broadcast event "cursor"  {user_id, x, y, sent_at}
--   Presence key = user_id、state {user_id, display_name, editing_photo_id}（編集していなければ null）
--
-- 再接続したとき: チャネルを購読し直してから ruuuto_board_snapshot(p_board_id) で保存済みの状態を
-- 取り直す。切断中に届かなかった保存済みイベントは、取り直した内容で置き換える。

-- トピックからボードIDを取り出す。形式が違えば null（エラーにしない）。
-- p_live = true なら "board:<id>:live"、false なら "board:<id>" だけを受け付ける。
create function private.ruuuto_board_topic_id(p_topic text, p_live boolean)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_topic ~ ('^board:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                    || case when p_live then ':live' else '' end || '$')
      then substr(p_topic, 7, 36)::uuid
  end;
$$;

revoke execute on function private.ruuuto_board_topic_id(text, boolean) from public, anon;
grant execute on function private.ruuuto_board_topic_id(text, boolean) to authenticated;

-- 受信: どちらのチャネルも所属メンバーだけ
create policy "realtime: 所属ボードのチャネルを受信できる"
  on realtime.messages for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and private.ruuuto_is_board_member(coalesce(
      private.ruuuto_board_topic_id((select realtime.topic()), false),
      private.ruuuto_board_topic_id((select realtime.topic()), true)))
  );

-- 送信: :live のチャネルだけ。保存済みのチャネル（board:<id>）には送信のポリシーを置かない。
create policy "realtime: 所属ボードの live チャネルに送信できる"
  on realtime.messages for insert to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and private.ruuuto_is_board_member(
      private.ruuuto_board_topic_id((select realtime.topic()), true))
  );

-- 装飾1件を返す形
create function private.ruuuto_decoration_json(p_decoration public.decorations)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_decoration.id,
    'board_id', p_decoration.board_id,
    'created_by', p_decoration.created_by,
    'kind', p_decoration.kind,
    'content', p_decoration.content,
    'x', p_decoration.x,
    'y', p_decoration.y,
    'rotation', p_decoration.rotation,
    'scale', p_decoration.scale,
    'z_index', p_decoration.z_index,
    'revision', p_decoration.revision,
    'updated_by', p_decoration.updated_by,
    'created_at', private.ruuuto_ts(p_decoration.created_at),
    'updated_at', private.ruuuto_ts(p_decoration.updated_at));
$$;

-- ボード1件を返す形（ruuuto_current_board と同じ）
create function private.ruuuto_board_json(p_board public.boards)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_board.id,
    'group_id', p_board.group_id,
    'topic', p_board.topic,
    'opens_at', private.ruuuto_ts(p_board.opens_at),
    'closes_at', private.ruuuto_ts(p_board.closes_at),
    'status', p_board.status);
$$;

-- 写真の保存済みの変更を配信する
create function private.ruuuto_broadcast_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_topic text := 'board:' || new.board_id;
  v_new jsonb := private.ruuuto_photo_json(new)::jsonb;
begin
  if new.status = 'posted' then
    if tg_op = 'INSERT' or v_new is distinct from private.ruuuto_photo_json(old)::jsonb then
      perform realtime.send(v_new, 'photo_saved', v_topic, true);
    end if;
  elsif new.status = 'withdrawn' and tg_op = 'UPDATE' and old.status = 'posted' then
    perform realtime.send(
      jsonb_build_object('id', new.id, 'board_id', new.board_id), 'photo_withdrawn', v_topic, true);
  end if;
  return null;
end;
$$;

create trigger photos_broadcast
  after insert or update on public.photos
  for each row execute function private.ruuuto_broadcast_photo();

-- 装飾の保存済みの変更を配信する（updated_at だけの変化は送らない）
create function private.ruuuto_broadcast_decoration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb;
begin
  if tg_op = 'DELETE' then
    perform realtime.send(
      jsonb_build_object('id', old.id, 'board_id', old.board_id),
      'decoration_deleted', 'board:' || old.board_id, true);
    return null;
  end if;

  v_new := private.ruuuto_decoration_json(new);
  if tg_op = 'INSERT'
     or (v_new - 'updated_at') is distinct from (private.ruuuto_decoration_json(old) - 'updated_at') then
    perform realtime.send(v_new, 'decoration_saved', 'board:' || new.board_id, true);
  end if;
  return null;
end;
$$;

create trigger decorations_broadcast
  after insert or update or delete on public.decorations
  for each row execute function private.ruuuto_broadcast_decoration();

-- ボードのお題・状態・期間の変更を配信する
create function private.ruuuto_broadcast_board()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb := private.ruuuto_board_json(new);
begin
  if v_new is distinct from private.ruuuto_board_json(old) then
    perform realtime.send(v_new, 'board_updated', 'board:' || new.id, true);
  end if;
  return null;
end;
$$;

create trigger boards_broadcast
  after update on public.boards
  for each row execute function private.ruuuto_broadcast_board();

-- 再接続・初回表示用: ボードの保存済みの状態をまとめて返す
--   ruuuto_board_snapshot(p_board_id) -> {board, photos, decorations}
--   photos は投稿済みだけ（重なり順 z_index の昇順）、decorations も z_index の昇順。
--   所属していなければ 42501（ボードがないときも同じ）。
create function public.ruuuto_board_snapshot(p_board_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_board public.boards%rowtype;
begin
  perform private.ruuuto_require_board_member(p_board_id);
  select * into v_board from public.boards b where b.id = p_board_id;

  return json_build_object(
    'board', private.ruuuto_board_json(v_board),
    'photos', coalesce((
      select json_agg(private.ruuuto_photo_json(p) order by p.z_index, p.posted_at, p.id)
      from public.photos p
      where p.board_id = p_board_id and p.status = 'posted'), '[]'::json),
    'decorations', coalesce((
      select json_agg(private.ruuuto_decoration_json(d) order by d.z_index, d.created_at, d.id)
      from public.decorations d
      where d.board_id = p_board_id), '[]'::json));
end;
$$;

revoke execute on function private.ruuuto_decoration_json(public.decorations) from public, anon, authenticated;
revoke execute on function private.ruuuto_board_json(public.boards) from public, anon, authenticated;
revoke execute on function private.ruuuto_broadcast_photo() from public, anon, authenticated;
revoke execute on function private.ruuuto_broadcast_decoration() from public, anon, authenticated;
revoke execute on function private.ruuuto_broadcast_board() from public, anon, authenticated;
revoke execute on function public.ruuuto_board_snapshot(uuid) from public, anon;
grant execute on function public.ruuuto_board_snapshot(uuid) to authenticated;
