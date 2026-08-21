-- 翠嶺·兔勇者 Online L0.5～L1
-- 在 Supabase SQL Editor 整段執行
-- RLS：玩家只能讀公開展示、寫自己的列

-- ── profiles ──
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '星途旅人',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
  on public.profiles for select
  using (true);

drop policy if exists "profiles_upsert_own" on public.profiles;
create policy "profiles_upsert_own"
  on public.profiles for insert
  with check (auth.uid() = user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = user_id);

-- ── cloud saves ──
create table if not exists public.saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  schema_version int not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.saves enable row level security;

drop policy if exists "saves_select_own" on public.saves;
create policy "saves_select_own"
  on public.saves for select
  using (auth.uid() = user_id);

drop policy if exists "saves_insert_own" on public.saves;
create policy "saves_insert_own"
  on public.saves for insert
  with check (auth.uid() = user_id);

drop policy if exists "saves_update_own" on public.saves;
create policy "saves_update_own"
  on public.saves for update
  using (auth.uid() = user_id);

-- ── presence (旅人殘影) ──
create table if not exists public.presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '星途旅人',
  map_id text not null default 'town',
  chapter text not null default 'c0',
  cosmetic text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists presence_map_updated
  on public.presence (map_id, updated_at desc);

alter table public.presence enable row level security;

drop policy if exists "presence_select_all" on public.presence;
create policy "presence_select_all"
  on public.presence for select
  using (true);

drop policy if exists "presence_upsert_own" on public.presence;
create policy "presence_upsert_own"
  on public.presence for insert
  with check (auth.uid() = user_id);

drop policy if exists "presence_update_own" on public.presence;
create policy "presence_update_own"
  on public.presence for update
  using (auth.uid() = user_id);

-- ── messages (留言石) ──
create table if not exists public.messages (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  place text not null,
  body text not null check (char_length(body) > 0 and char_length(body) <= 80),
  created_at timestamptz not null default now()
);

create index if not exists messages_place_created
  on public.messages (place, created_at desc);

alter table public.messages enable row level security;

drop policy if exists "messages_select_all" on public.messages;
create policy "messages_select_all"
  on public.messages for select
  using (true);

drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own"
  on public.messages for insert
  with check (auth.uid() = user_id);

-- ── candles (通關燈) ──
create table if not exists public.candles (
  id int primary key default 1 check (id = 1),
  total bigint not null default 0
);

insert into public.candles (id, total) values (1, 0)
  on conflict (id) do nothing;

alter table public.candles enable row level security;

drop policy if exists "candles_select" on public.candles;
create policy "candles_select"
  on public.candles for select
  using (true);

-- 僅透過 RPC 增加（避免客戶端亂寫）
create or replace function public.candle_increment()
returns bigint
language plpgsql
security definer
as $$
declare
  new_total bigint;
begin
  update public.candles set total = total + 1 where id = 1
  returning total into new_total;
  return new_total;
end;
$$;

grant execute on function public.candle_increment() to anon, authenticated;

-- ── leaderboard ──
create table if not exists public.leaderboard (
  board text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '星途旅人',
  score bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (board, user_id)
);

create index if not exists leaderboard_board_score
  on public.leaderboard (board, score desc);

alter table public.leaderboard enable row level security;

drop policy if exists "leaderboard_select_all" on public.leaderboard;
create policy "leaderboard_select_all"
  on public.leaderboard for select
  using (true);

drop policy if exists "leaderboard_upsert_own" on public.leaderboard;
create policy "leaderboard_upsert_own"
  on public.leaderboard for insert
  with check (auth.uid() = user_id);

drop policy if exists "leaderboard_update_own" on public.leaderboard;
create policy "leaderboard_update_own"
  on public.leaderboard for update
  using (auth.uid() = user_id);

-- ── 非即時 PVP 殘影（好友挑戰打的是這份，不是即時操作）──
create table if not exists public.pvp_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '星途旅人',
  power int not null default 0,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id)
);

alter table public.pvp_snapshots enable row level security;

drop policy if exists "pvp_snapshots_select_all" on public.pvp_snapshots;
create policy "pvp_snapshots_select_all"
  on public.pvp_snapshots for select
  using (true);

drop policy if exists "pvp_snapshots_upsert_own" on public.pvp_snapshots;
create policy "pvp_snapshots_upsert_own"
  on public.pvp_snapshots for insert
  with check (auth.uid() = user_id);

drop policy if exists "pvp_snapshots_update_own" on public.pvp_snapshots;
create policy "pvp_snapshots_update_own"
  on public.pvp_snapshots for update
  using (auth.uid() = user_id);

grant select on table public.pvp_snapshots to anon, authenticated;
grant insert, update on table public.pvp_snapshots to authenticated;

-- ── 市集／房間：2026-08-16 移除 ──
--
-- market_listings / market_credit / rooms / room_members / room_events /
-- room_inputs 與對應的 RPC 全部砍掉，遊戲端的市集、裂縫房、狩獵房、助戰
-- 也一起移除了（理由見 docs/DECISIONS.md）。
--
-- 已部署的專案要退掉它們，跑 supabase/drop_market_rooms.sql。
-- 這份 schema 本身不含 drop —— 它是「從零建起來」用的，
-- 加 drop 進來會讓每次重跑都去動不相干的東西。

-- ── 訪客登入：Supabase Dashboard → Authentication → Providers → Anonymous 開啟
