-- RCNO-41 手動のお題変更をSupabaseで保存する
--
-- 2026-11-22 の判断（11/25 リリース）
-- * 所属しているメンバー全員が、開催中のボードのお題を変更できる。
-- * ボードは差し替えず、同じボードのお題を書き換える（写真・配置・装飾はそのまま残る）。
-- * 提案と投票の仕組みはリリース後に作る。
--
-- iOS #9 の TopicEditorAPI が呼ぶ形:
--   ruuuto_save_topic(p_board_id, p_topic)
--   お題が不正 RC001 / 締切後・終了済み RC002 / 権限なし 42501

-- 通知の送り先（RCNO-9・37）に渡すイベント。保存と同じトランザクションで記録し、
-- 配信処理は後からこの表を読む（アウトボックス方式）。
create table public.notification_events (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('topic_changed', 'topic_published')),
  group_id uuid not null references public.groups (id) on delete cascade,
  board_id uuid not null references public.boards (id) on delete cascade,
  topic text not null,
  actor_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index notification_events_unprocessed_idx
  on public.notification_events (created_at) where processed_at is null;

alter table public.notification_events enable row level security;
-- アプリからは読ませない（ポリシーなし）

create function public.ruuuto_save_topic(p_board_id uuid, p_topic text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_board public.boards%rowtype;
  v_topic text := btrim(coalesce(p_topic, ''));
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

revoke execute on function public.ruuuto_save_topic(uuid, text) from public, anon;
grant execute on function public.ruuuto_save_topic(uuid, text) to authenticated;
