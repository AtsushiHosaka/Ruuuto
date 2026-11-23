-- RCNO-5 グループ外からの操作を拒否する
--
-- 方針
-- * 読み取りはRLSで、所属しているグループのデータだけを返す。
-- * 書き込みはテーブルへの直接操作を許可しない。作成・移動・削除は、
--   所属・締切・同時編集を確かめる security definer のRPCだけで行う
--   （RCNO-42、41、19、27、35 などで追加する）。
-- * StorageとRealtimeの権限は RCNO-35、RCNO-36 で設定する。

-- 所属の確認（RLSから呼ぶ。security definer にして group_members のRLSを再帰させない）
create function private.ruuuto_is_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id
      and m.user_id = (select auth.uid())
  );
$$;

create function private.ruuuto_is_board_member(p_board_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.boards b
    join public.group_members m on m.group_id = b.group_id
    where b.id = p_board_id
      and m.user_id = (select auth.uid())
  );
$$;

-- 同じグループに所属している相手か（表示名を見せる範囲）
create function private.ruuuto_shares_group(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members mine
    join public.group_members theirs on theirs.group_id = mine.group_id
    where mine.user_id = (select auth.uid())
      and theirs.user_id = p_user_id
  );
$$;

revoke execute on function private.ruuuto_is_member(uuid) from public, anon;
revoke execute on function private.ruuuto_is_board_member(uuid) from public, anon;
revoke execute on function private.ruuuto_shares_group(uuid) from public, anon;
grant execute on function private.ruuuto_is_member(uuid) to authenticated;
grant execute on function private.ruuuto_is_board_member(uuid) to authenticated;
grant execute on function private.ruuuto_shares_group(uuid) to authenticated;

-- テーブルへの直接の書き込みは、ログイン済みでも許可しない。
-- 対象はRCNO-34で作ったテーブルに限り、public にある他のテーブルや既定の権限は変えない。
-- 後のマイグレーションで追加するテーブルは、それぞれのマイグレーションで権限を明示する。
revoke insert, update, delete, truncate, references, trigger on
  public.profiles,
  public.groups,
  public.group_members,
  public.invitations,
  public.topic_prompts,
  public.boards,
  public.photos,
  public.decorations,
  public.devices
from authenticated;

-- プロフィール: 自分と、同じグループの参加者
create policy "profiles: 自分と同じグループの参加者を読める"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.ruuuto_shares_group(id));

-- グループ: 所属しているもの
create policy "groups: 所属グループを読める"
  on public.groups for select to authenticated
  using (private.ruuuto_is_member(id));

-- 所属: 自分が所属しているグループの参加者一覧
create policy "group_members: 所属グループの参加者を読める"
  on public.group_members for select to authenticated
  using (private.ruuuto_is_member(group_id));

-- 招待: 直接は読ませない（発行と参加はRPCで行う）。ポリシーなし。

-- 固定のお題: ログイン済みなら読める（グループに依存しない共通データ）
create policy "topic_prompts: ログイン済みなら読める"
  on public.topic_prompts for select to authenticated
  using (true);

-- ボード: 所属グループのもの（開催中も終了済みも）
create policy "boards: 所属グループのボードを読める"
  on public.boards for select to authenticated
  using (private.ruuuto_is_member(group_id));

-- 写真: 所属グループのボードの投稿済み写真。投稿途中（pending）は投稿者だけ。
-- 取り下げた写真は誰にも返さない。
create policy "photos: 所属グループの写真を読める"
  on public.photos for select to authenticated
  using (
    private.ruuuto_is_board_member(board_id)
    and (
      status = 'posted'
      or (status = 'pending' and posted_by = (select auth.uid()))
    )
  );

-- 装飾: 所属グループのボードのもの
create policy "decorations: 所属グループの装飾を読める"
  on public.decorations for select to authenticated
  using (private.ruuuto_is_board_member(board_id));

-- 端末登録: 自分の端末だけ
create policy "devices: 自分の端末を読める"
  on public.devices for select to authenticated
  using (user_id = (select auth.uid()));
