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

-- ── event progress ──
create table if not exists public.event_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id text not null,
  runs_total int not null default 0,
  token int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

alter table public.event_progress enable row level security;

drop policy if exists "event_progress_select_own" on public.event_progress;
create policy "event_progress_select_own"
  on public.event_progress for select
  using (auth.uid() = user_id);

drop policy if exists "event_progress_upsert_own" on public.event_progress;
create policy "event_progress_upsert_own"
  on public.event_progress for insert
  with check (auth.uid() = user_id);

drop policy if exists "event_progress_update_own" on public.event_progress;
create policy "event_progress_update_own"
  on public.event_progress for update
  using (auth.uid() = user_id);

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

-- ── market_listings（星途市集）──
create table if not exists public.market_listings (
  id bigserial primary key,
  seller_id uuid not null references auth.users(id) on delete cascade,
  seller_name text not null default '星途旅人',
  item_id text not null,
  qty int not null check (qty > 0 and qty <= 99),
  price int not null check (price > 0 and price <= 999999),
  status text not null default 'active' check (status in ('active', 'sold', 'cancelled')),
  buyer_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  sold_at timestamptz
);

create index if not exists market_listings_active
  on public.market_listings (status, created_at desc);

alter table public.market_listings enable row level security;

drop policy if exists "market_select_active_or_own" on public.market_listings;
create policy "market_select_active_or_own"
  on public.market_listings for select
  using (status = 'active' or seller_id = auth.uid() or buyer_id = auth.uid());

drop policy if exists "market_insert_own" on public.market_listings;
create policy "market_insert_own"
  on public.market_listings for insert
  with check (auth.uid() = seller_id);

drop policy if exists "market_update_own_seller" on public.market_listings;
create policy "market_update_own_seller"
  on public.market_listings for update
  using (auth.uid() = seller_id or auth.uid() = buyer_id);

-- 賣家待領貨款
create table if not exists public.market_credit (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pending_gold bigint not null default 0
);

alter table public.market_credit enable row level security;

drop policy if exists "market_credit_select_own" on public.market_credit;
create policy "market_credit_select_own"
  on public.market_credit for select
  using (auth.uid() = user_id);

-- 購買 RPC：標記 sold、賣家入帳（手續費 8%）
create or replace function public.market_buy(p_listing_id bigint)
returns jsonb
language plpgsql
security definer
as $$
declare
  r public.market_listings%rowtype;
  fee int;
  credit int;
begin
  if auth.uid() is null then
    return jsonb_build_object('error', 'not signed in');
  end if;
  select * into r from public.market_listings
    where id = p_listing_id and status = 'active' for update;
  if not found then
    return jsonb_build_object('error', 'listing gone');
  end if;
  if r.seller_id = auth.uid() then
    return jsonb_build_object('error', 'cannot buy own');
  end if;
  fee := greatest(1, round(r.price * 0.08)::int);
  credit := greatest(0, r.price - fee);
  update public.market_listings
    set status = 'sold', buyer_id = auth.uid(), sold_at = now()
    where id = p_listing_id;
  insert into public.market_credit (user_id, pending_gold)
    values (r.seller_id, credit)
    on conflict (user_id) do update
      set pending_gold = public.market_credit.pending_gold + excluded.pending_gold;
  return jsonb_build_object(
    'item_id', r.item_id,
    'qty', r.qty,
    'price', r.price,
    'seller_credit', credit
  );
end;
$$;

grant execute on function public.market_buy(bigint) to authenticated, anon;

-- 領取待領貨款
create or replace function public.market_claim_credit()
returns jsonb
language plpgsql
security definer
as $$
declare
  g bigint;
begin
  if auth.uid() is null then
    return jsonb_build_object('gold', 0);
  end if;
  select pending_gold into g from public.market_credit where user_id = auth.uid() for update;
  if g is null or g <= 0 then
    return jsonb_build_object('gold', 0);
  end if;
  update public.market_credit set pending_gold = 0 where user_id = auth.uid();
  return jsonb_build_object('gold', g);
end;
$$;

grant execute on function public.market_claim_credit() to authenticated, anon;

-- ── rooms（L2 組隊裂縫房）──
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  mode text not null default 'wrath',
  status text not null default 'open',  -- open | fighting | closed
  max_players int not null default 4,
  code text not null default '',
  result text not null default '',  -- '' | win | lose
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '星途旅人',
  is_ready boolean not null default false,
  reward_claimed boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

do $$ begin
  alter table public.rooms add column if not exists code text not null default '';
  alter table public.rooms add column if not exists result text not null default '';
  alter table public.room_members add column if not exists reward_claimed boolean not null default false;
exception when others then null;
end $$;

create unique index if not exists rooms_code_open
  on public.rooms (code) where status = 'open' and code <> '';

create index if not exists rooms_status_updated
  on public.rooms (status, updated_at desc);

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;

drop policy if exists "rooms_select_open" on public.rooms;
drop policy if exists "rooms_select_members_or_open" on public.rooms;
create policy "rooms_select_members_or_open"
  on public.rooms for select
  using (
    status = 'open'
    or host_id = auth.uid()
    or exists (
      select 1 from public.room_members m
      where m.room_id = rooms.id and m.user_id = auth.uid()
    )
  );

drop policy if exists "rooms_insert_host" on public.rooms;
create policy "rooms_insert_host"
  on public.rooms for insert
  with check (auth.uid() = host_id);

drop policy if exists "rooms_update_host" on public.rooms;
create policy "rooms_update_host"
  on public.rooms for update
  using (auth.uid() = host_id);

drop policy if exists "room_members_select" on public.room_members;
create policy "room_members_select"
  on public.room_members for select
  using (true);

drop policy if exists "room_members_insert_self" on public.room_members;
create policy "room_members_insert_self"
  on public.room_members for insert
  with check (auth.uid() = user_id);

drop policy if exists "room_members_update_self" on public.room_members;
create policy "room_members_update_self"
  on public.room_members for update
  using (auth.uid() = user_id);

drop policy if exists "room_members_delete_self" on public.room_members;
create policy "room_members_delete_self"
  on public.room_members for delete
  using (auth.uid() = user_id);

-- ── room_events（Realtime 同屏轉播）──
create table if not exists public.room_events (
  id bigserial primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  seq int not null default 0,
  kind text not null,  -- battle_start | snap | action | end | chat
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists room_events_room_seq
  on public.room_events (room_id, id);

alter table public.room_events enable row level security;

drop policy if exists "room_events_select_member" on public.room_events;
create policy "room_events_select_member"
  on public.room_events for select
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_events.room_id and m.user_id = auth.uid()
    )
    or exists (
      select 1 from public.rooms r
      where r.id = room_events.room_id and r.host_id = auth.uid()
    )
  );

drop policy if exists "room_events_insert_member" on public.room_events;
create policy "room_events_insert_member"
  on public.room_events for insert
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = room_events.room_id and r.host_id = auth.uid()
    )
  );

-- 舊事件可清：保留最近 500 條／房（可選維運）
-- Realtime：Dashboard → Database → Replication 啟用 room_events；
-- 或用 REST 輪詢（客戶端已支援 fallback）。

-- ── room_inputs（成員操作／同屏輸入分攤）──
create table if not exists public.room_inputs (
  id bigserial primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '旅人',
  kind text not null,  -- parry | skill | assist | sync
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists room_inputs_room_id
  on public.room_inputs (room_id, id);

alter table public.room_inputs enable row level security;

drop policy if exists "room_inputs_select_member" on public.room_inputs;
create policy "room_inputs_select_member"
  on public.room_inputs for select
  using (
    exists (
      select 1 from public.room_members m
      where m.room_id = room_inputs.room_id and m.user_id = auth.uid()
    )
    or exists (
      select 1 from public.rooms r
      where r.id = room_inputs.room_id and r.host_id = auth.uid()
    )
  );

drop policy if exists "room_inputs_insert_member" on public.room_inputs;
create policy "room_inputs_insert_member"
  on public.room_inputs for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.room_members m
      where m.room_id = room_inputs.room_id and m.user_id = auth.uid()
    )
  );

-- ── 訪客登入：Supabase Dashboard → Authentication → Providers → Anonymous 開啟
