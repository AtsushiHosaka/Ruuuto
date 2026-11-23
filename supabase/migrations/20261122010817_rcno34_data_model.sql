-- RCNO-34 データモデルと初期マイグレーション
--
-- グループの所属、招待、週別ボード、写真、装飾、端末登録を定義する。
-- アクセス制御はRCNO-5で追加する。それまでは全テーブルでRLSを有効にし、
-- ポリシーを置かないことで、Publishable keyからの読み書きをすべて拒否する。

create extension if not exists pgcrypto with schema extensions;

-- 共通: updated_at を更新する
create function public.ruuuto_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 参加者のプロフィール。auth.users と1対1で対応する（作成処理はRCNO-40）。
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    check (char_length(btrim(display_name)) between 1 and 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- グループ。create_request_id は作成の再送で二重に作らないための識別子。
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null
    check (char_length(btrim(name)) between 1 and 40),
  created_by uuid not null references public.profiles (id) on delete restrict,
  create_request_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (created_by, create_request_id)
);

-- 所属。複数グループに所属できる。
create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_id_idx on public.group_members (user_id);

-- 招待リンク。トークンそのものは保存せず、SHA-256のハッシュだけを持つ。
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  token_hash bytea not null unique check (octet_length(token_hash) = 32),
  created_by uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create index invitations_group_id_idx on public.invitations (group_id);

-- 固定のお題（Slackの月別・週別のお題案）。初期データはRCNO-4。
create table public.topic_prompts (
  id uuid primary key default gen_random_uuid(),
  month smallint not null check (month between 1 and 12),
  week smallint not null check (week between 1 and 5),
  body text not null check (char_length(btrim(body)) between 1 and 80),
  unique (month, week)
);

-- 週別ボード。status = 'open' のボードはグループごとに1件だけ。
-- closes_at はサーバーで締切を判定する根拠（RCNO-27）。
create table public.boards (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  topic text not null check (char_length(btrim(topic)) between 1 and 80),
  topic_source text not null default 'weekly'
    check (topic_source in ('weekly', 'custom')),
  prompt_id uuid references public.topic_prompts (id) on delete set null,
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closes_at > opens_at),
  check ((status = 'closed') = (closed_at is not null)),
  -- 同じ期間のボードを二重に作らない（週次切替の再実行に備える）
  unique (group_id, opens_at)
);

create unique index boards_one_open_per_group_idx
  on public.boards (group_id) where status = 'open';

-- 月別の履歴は開始日時で引く
create index boards_group_history_idx on public.boards (group_id, opens_at desc);

-- 写真。id はiOSが投稿前に決め、再送しても同じ行になるようにする（RCNO-35）。
-- x, y, rotation, scale, z_index はボード上の配置。revision は同時編集の判定に使う（RCNO-19）。
create table public.photos (
  id uuid primary key,
  board_id uuid not null references public.boards (id) on delete cascade,
  posted_by uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'posted', 'withdrawn')),
  width integer check (width > 0),
  height integer check (height > 0),
  city text check (city is null or char_length(btrim(city)) between 1 and 60),
  x double precision not null default 0,
  y double precision not null default 0,
  rotation double precision not null default 0,
  scale double precision not null default 1 check (scale > 0),
  z_index integer not null default 0,
  revision bigint not null default 1,
  updated_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  posted_at timestamptz,
  withdrawn_at timestamptz
);

create index photos_board_id_idx on public.photos (board_id);
create index photos_posted_by_idx on public.photos (posted_by);
-- 都市別マップ用（都市未設定は地図に出さない）
create index photos_board_city_idx on public.photos (board_id, city)
  where status = 'posted' and city is not null;

-- 装飾（文字・スタンプ・ペン）。種類ごとの中身は content に入れる。
create table public.decorations (
  id uuid primary key,
  board_id uuid not null references public.boards (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('text', 'stamp', 'pen')),
  content jsonb not null default '{}'::jsonb
    check (jsonb_typeof(content) = 'object' and pg_column_size(content) <= 65536),
  x double precision not null default 0,
  y double precision not null default 0,
  rotation double precision not null default 0,
  scale double precision not null default 1 check (scale > 0),
  z_index integer not null default 0,
  revision bigint not null default 1,
  updated_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index decorations_board_id_idx on public.decorations (board_id);

-- 端末登録。installation_id はアプリのインストールごとの識別子。
-- apns_token が null の行は通知の受信を止めた端末。
create table public.devices (
  installation_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  apns_token text check (apns_token is null or apns_token ~ '^[0-9a-f]{64,200}$'),
  invalidated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index devices_user_id_idx on public.devices (user_id);
create unique index devices_active_token_idx on public.devices (apns_token)
  where apns_token is not null and invalidated_at is null;

-- updated_at の自動更新
create trigger profiles_touch before update on public.profiles
  for each row execute function public.ruuuto_touch_updated_at();
create trigger groups_touch before update on public.groups
  for each row execute function public.ruuuto_touch_updated_at();
create trigger boards_touch before update on public.boards
  for each row execute function public.ruuuto_touch_updated_at();
create trigger photos_touch before update on public.photos
  for each row execute function public.ruuuto_touch_updated_at();
create trigger decorations_touch before update on public.decorations
  for each row execute function public.ruuuto_touch_updated_at();
create trigger devices_touch before update on public.devices
  for each row execute function public.ruuuto_touch_updated_at();

-- RLSを有効にする。ポリシーはRCNO-5で追加するまで置かない（全拒否）。
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.invitations enable row level security;
alter table public.topic_prompts enable row level security;
alter table public.boards enable row level security;
alter table public.photos enable row level security;
alter table public.decorations enable row level security;
alter table public.devices enable row level security;

-- 未ログインの利用者には何も公開しない。対象はここで作った9テーブルに限り、
-- public にある他のテーブルの権限は変えない。
revoke all on
  public.profiles,
  public.groups,
  public.group_members,
  public.invitations,
  public.topic_prompts,
  public.boards,
  public.photos,
  public.decorations,
  public.devices
from anon;
revoke execute on function public.ruuuto_touch_updated_at() from public, anon, authenticated;
