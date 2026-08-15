-- 翠嶺·兔勇者 — 第 4 步：經濟寫入搬上伺服器
-- 前置：先跑過 supabase/schema.sql
-- 在 Supabase SQL Editor 整段執行；可重複執行（idempotent）
--
-- 設計要點
--   遊戲本體是單機模擬，伺服器沒辦法驗證「這 300 金到底有沒有真的打贏怪」。
--   所以這裡不假裝做得到，改成兩本帳：
--     saves.payload   ── 玩家自己的存檔，照舊，隨他寫（壞掉只壞他自己的）
--     player_econ     ── 伺服器保守影子帳，只記「可拿去跟別人交易」的金幣與物品
--   影子帳往下精確跟隨存檔（花掉就是花掉），往上只能按真實時間的速率長。
--   市集買賣、共鬥領獎一律動影子帳，客戶端再也不能直接寫 saves / market_listings。
--   結果：改客戶端最多能弄壞自己的存檔，沒辦法對別人的經濟灌水。
--
--   額度一律是「速率 × 距上次推送的真實秒數」，沒有任何「每次推送就發一份」的固定額，
--   所以連續猛推存檔不會多拿額度；物品額度用小數結轉，高頻推送也不會被整數截斷吃掉。

-- ══════════════════════════════════════════════════════════
-- 1. 參數
-- ══════════════════════════════════════════════════════════

create table if not exists public.econ_config (
  id int primary key default 1 check (id = 1),
  gold_rate_per_sec    int not null default 60,        -- 影子帳金幣每秒可長多少（實測手打約 10/秒）
  gold_push_max        int not null default 500000,    -- 單次推送成長硬上限
  gold_seed_max        bigint not null default 200000, -- 首次建帳時採信的上限
  item_rate_per_hour   int not null default 120,       -- 全部可交易物合計每小時可長多少
  item_credit_max      int not null default 400,       -- 物品額度最多結轉到多少
  item_seed_max        int not null default 99,
  listing_max_active   int not null default 8,
  listing_max_per_day  int not null default 30,
  listing_price_mult   int not null default 20,        -- 售價上限＝基準價 × 數量 × 此值
  message_per_min      int not null default 6,
  payload_max_bytes    int not null default 1048576
);

insert into public.econ_config (id) values (1) on conflict (id) do nothing;

alter table public.econ_config enable row level security;

drop policy if exists "econ_config_select" on public.econ_config;
create policy "econ_config_select"
  on public.econ_config for select
  using (true);


-- ══════════════════════════════════════════════════════════
-- 2. 影子帳 / 稽核
-- ══════════════════════════════════════════════════════════

create table if not exists public.player_econ (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  gold        bigint  not null default 0,
  items       jsonb   not null default '{}'::jsonb,   -- {item_id: qty}
  item_credit numeric not null default 0,             -- 尚未用掉的物品成長額度（小數結轉）
  last_push   timestamptz not null default now(),
  strikes     int not null default 0,                 -- 影子帳被削掉的次數（人工複查用）
  blocked     boolean not null default false,         -- 僅人工設定，擋掉市集
  created_at  timestamptz not null default now()
);

alter table public.player_econ add column if not exists item_credit numeric not null default 0;

alter table public.player_econ enable row level security;

drop policy if exists "player_econ_select_own" on public.player_econ;
create policy "player_econ_select_own"
  on public.player_econ for select
  using (auth.uid() = user_id);
-- 沒有 insert / update policy：只能透過下面的 RPC 動

create table if not exists public.econ_audit (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  kind        text not null,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists econ_audit_user_created
  on public.econ_audit (user_id, created_at desc);

alter table public.econ_audit enable row level security;
-- 玩家看不到稽核；只有 service_role（Dashboard）讀得到


-- ══════════════════════════════════════════════════════════
-- 3. 可交易物基準價（伺服器自己的一份，別信客戶端報價）
-- ══════════════════════════════════════════════════════════

create table if not exists public.market_catalog (
  item_id     text primary key,
  base_price  int not null check (base_price > 0),
  max_stack   int not null default 99 check (max_stack > 0)
);

insert into public.market_catalog (item_id, base_price, max_stack) values
  ('hunt_hide',   10, 99),
  ('hunt_bone',   22, 99),
  ('hunt_core',   60, 99),
  ('wolf_fang',    8, 99),
  ('mist_shard',  12, 99),
  ('sea_shell',   10, 99),
  ('scar_ember',  15, 99),
  ('dust_crumb',  25, 99),
  ('hp_s',        18, 99),
  ('bread',       12, 99),
  ('antidote',    20, 30)
on conflict (item_id) do update
  set base_price = excluded.base_price,
      max_stack  = excluded.max_stack;

alter table public.market_catalog enable row level security;

drop policy if exists "market_catalog_select" on public.market_catalog;
create policy "market_catalog_select"
  on public.market_catalog for select
  using (true);


-- ══════════════════════════════════════════════════════════
-- 4. 影子帳工具函式
-- ══════════════════════════════════════════════════════════

-- 取（必要時建）影子帳並上鎖。呼叫端必須已在交易中。
create or replace function public.econ_row(p_user uuid)
returns public.player_econ
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.player_econ%rowtype;
begin
  select * into e from public.player_econ where user_id = p_user for update;
  if not found then
    insert into public.player_econ (user_id) values (p_user)
      on conflict (user_id) do nothing;
    select * into e from public.player_econ where user_id = p_user for update;
  end if;
  return e;
end;
$$;

revoke execute on function public.econ_row(uuid) from public, anon, authenticated;


-- 把數量寫回 items（0 就整個 key 移掉，避免 jsonb 長肥）
create or replace function public.econ_set_item(p_items jsonb, p_item text, p_n int)
returns jsonb
language sql
immutable
as $$
  select case
    when p_n > 0 then p_items || jsonb_build_object(p_item, p_n)
    else p_items - p_item
  end;
$$;


-- 玩家自己查影子帳（面板顯示用）
create or replace function public.econ_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.player_econ%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object('error', 'not signed in');
  end if;
  select * into e from public.player_econ where user_id = auth.uid();
  if not found then
    return jsonb_build_object('gold', 0, 'items', '{}'::jsonb, 'seeded', false);
  end if;
  return jsonb_build_object(
    'ok', true,
    'gold', e.gold,
    'items', e.items,
    'blocked', e.blocked,
    'seeded', true
  );
end;
$$;

grant execute on function public.econ_state() to authenticated;


-- ══════════════════════════════════════════════════════════
-- 5. 存檔推送：唯一的寫入口
-- ══════════════════════════════════════════════════════════

create or replace function public.save_push(p_payload jsonb, p_schema_version int default 1)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg        public.econ_config%rowtype;
  e          public.player_econ%rowtype;
  uid        uuid := auth.uid();
  seeding    boolean;
  elapsed    numeric := 0;
  allowance  bigint;
  pay_gold   bigint;
  new_gold   bigint;
  gold_clip  bigint := 0;
  credit     numeric;
  budget     int;
  cat        record;
  pay_n      int;
  shadow_n   int;
  take_n     int;
  next_n     int;
  new_items  jsonb := '{}'::jsonb;
  item_clip  int := 0;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    return jsonb_build_object('error', 'bad payload');
  end if;

  select * into cfg from public.econ_config where id = 1;
  if pg_column_size(p_payload) > cfg.payload_max_bytes then
    return jsonb_build_object('error', 'payload too large');
  end if;

  seeding := not exists (select 1 from public.player_econ where user_id = uid);
  e := public.econ_row(uid);
  elapsed := greatest(0, extract(epoch from (now() - e.last_push)));

  -- ── 金幣：往下精確跟隨，往上受「速率 × 真實秒數」限制 ──
  pay_gold := greatest(0, coalesce((p_payload->>'gold')::bigint, 0));

  if seeding then
    new_gold := least(pay_gold, cfg.gold_seed_max);
  else
    allowance := least(
      (cfg.gold_rate_per_sec::numeric * elapsed)::bigint,
      cfg.gold_push_max::bigint
    );
    new_gold := least(pay_gold, e.gold + allowance);
  end if;
  gold_clip := greatest(0, pay_gold - new_gold);

  -- ── 可交易物：全部品項共用一份成長額度，小數結轉 ──
  if seeding then
    credit := 0;
    budget := 0;
  else
    credit := least(
      cfg.item_credit_max::numeric,
      e.item_credit + cfg.item_rate_per_hour::numeric * elapsed / 3600.0
    );
    budget := floor(credit)::int;
  end if;

  for cat in select * from public.market_catalog order by item_id loop
    pay_n := least(greatest(0, coalesce((p_payload->'inventory'->>cat.item_id)::int, 0)), cat.max_stack);
    shadow_n := coalesce((e.items->>cat.item_id)::int, 0);

    if seeding then
      next_n := least(pay_n, cfg.item_seed_max);
    elsif pay_n <= shadow_n then
      next_n := pay_n;                       -- 用掉／賣掉：照實跟隨
    else
      take_n := least(pay_n - shadow_n, budget);
      budget := budget - take_n;
      next_n := shadow_n + take_n;
    end if;

    if pay_n > next_n then
      item_clip := item_clip + (pay_n - next_n);
    end if;
    new_items := public.econ_set_item(new_items, cat.item_id, next_n);
  end loop;

  if not seeding then
    credit := credit - (floor(credit)::int - budget);   -- 只扣真的用掉的整數份
  end if;

  -- ── 落帳 ──
  update public.player_econ
    set gold = new_gold,
        items = new_items,
        item_credit = credit,
        last_push = now(),
        strikes = strikes + (case when gold_clip > 1000 or item_clip > 0 then 1 else 0 end)
    where user_id = uid;

  insert into public.saves (user_id, payload, schema_version, updated_at)
    values (uid, p_payload, coalesce(p_schema_version, 1), now())
    on conflict (user_id) do update
      set payload = excluded.payload,
          schema_version = excluded.schema_version,
          updated_at = excluded.updated_at;

  if gold_clip > 1000 or item_clip > 0 then
    insert into public.econ_audit (user_id, kind, detail)
      values (uid, 'save_clip', jsonb_build_object(
        'payload_gold', pay_gold,
        'ledger_gold', new_gold,
        'gold_clipped', gold_clip,
        'items_clipped', item_clip,
        'elapsed_sec', elapsed,
        'seeding', seeding
      ));
  end if;

  return jsonb_build_object(
    'ok', true,
    'ledger_gold', new_gold,
    'seeded', seeding
  );
end;
$$;

grant execute on function public.save_push(jsonb, int) to authenticated;

-- 存檔只能經 save_push 寫入
drop policy if exists "saves_insert_own" on public.saves;
drop policy if exists "saves_update_own" on public.saves;


-- ══════════════════════════════════════════════════════════
-- 6. 市集：上架 / 下架 / 購買 / 領款
-- ══════════════════════════════════════════════════════════

create or replace function public.market_list_item(
  p_item_id text,
  p_qty int,
  p_price int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg       public.econ_config%rowtype;
  e         public.player_econ%rowtype;
  cat       public.market_catalog%rowtype;
  uid       uuid := auth.uid();
  have_n    int;
  active_n  int;
  today_n   int;
  max_price bigint;
  new_row   public.market_listings%rowtype;
  nm        text;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;

  select * into cfg from public.econ_config where id = 1;
  select * into cat from public.market_catalog where item_id = p_item_id;
  if not found then
    return jsonb_build_object('error', 'item not tradeable');
  end if;

  p_qty := coalesce(p_qty, 0);
  p_price := coalesce(p_price, 0);
  if p_qty <= 0 or p_qty > cat.max_stack then
    return jsonb_build_object('error', 'bad qty');
  end if;
  max_price := least(999999::bigint, cat.base_price::bigint * p_qty * cfg.listing_price_mult);
  if p_price <= 0 or p_price > max_price then
    return jsonb_build_object('error', 'price out of range', 'max_price', max_price);
  end if;

  e := public.econ_row(uid);
  if e.blocked then
    return jsonb_build_object('error', 'market blocked');
  end if;

  select count(*) into active_n from public.market_listings
    where seller_id = uid and status = 'active';
  if active_n >= cfg.listing_max_active then
    return jsonb_build_object('error', 'too many listings');
  end if;

  select count(*) into today_n from public.market_listings
    where seller_id = uid and created_at > now() - interval '1 day';
  if today_n >= cfg.listing_max_per_day then
    return jsonb_build_object('error', 'daily listing limit');
  end if;

  have_n := coalesce((e.items->>p_item_id)::int, 0);
  if have_n < p_qty then
    return jsonb_build_object('error', 'not enough items', 'ledger_qty', have_n);
  end if;

  update public.player_econ
    set items = public.econ_set_item(items, p_item_id, have_n - p_qty)
    where user_id = uid;

  select display_name into nm from public.profiles where user_id = uid;

  insert into public.market_listings
      (seller_id, seller_name, item_id, qty, price, status)
    values (uid, coalesce(nm, '星途旅人'), p_item_id, p_qty, p_price, 'active')
    returning * into new_row;

  return jsonb_build_object(
    'ok', true,
    'id', new_row.id,
    'item_id', new_row.item_id,
    'qty', new_row.qty,
    'price', new_row.price
  );
end;
$$;

grant execute on function public.market_list_item(text, int, int) to authenticated;


create or replace function public.market_cancel_listing(p_listing_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r   public.market_listings%rowtype;
  cat public.market_catalog%rowtype;
  e   public.player_econ%rowtype;
  cur int;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;

  select * into r from public.market_listings
    where id = p_listing_id and seller_id = uid and status = 'active'
    for update;
  if not found then
    return jsonb_build_object('error', 'listing gone');
  end if;

  update public.market_listings set status = 'cancelled' where id = r.id;

  -- 退回影子帳（不超過該物堆疊上限）
  e := public.econ_row(uid);
  select * into cat from public.market_catalog where item_id = r.item_id;
  cur := coalesce((e.items->>r.item_id)::int, 0);
  update public.player_econ
    set items = public.econ_set_item(
          items, r.item_id,
          least(coalesce(cat.max_stack, 99), cur + r.qty)
        )
    where user_id = uid;

  return jsonb_build_object('ok', true, 'item_id', r.item_id, 'qty', r.qty);
end;
$$;

grant execute on function public.market_cancel_listing(bigint) to authenticated;


-- 購買：買方付的是影子帳的金幣，賣方入待領款
create or replace function public.market_buy(p_listing_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid    uuid := auth.uid();
  r      public.market_listings%rowtype;
  cat    public.market_catalog%rowtype;
  buyer  public.player_econ%rowtype;
  fee    int;
  credit int;
  cur    int;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;

  buyer := public.econ_row(uid);
  if buyer.blocked then
    return jsonb_build_object('error', 'market blocked');
  end if;

  select * into r from public.market_listings
    where id = p_listing_id and status = 'active' for update;
  if not found then
    return jsonb_build_object('error', 'listing gone');
  end if;
  if r.seller_id = uid then
    return jsonb_build_object('error', 'cannot buy own');
  end if;
  if buyer.gold < r.price then
    return jsonb_build_object('error', 'not enough gold', 'ledger_gold', buyer.gold);
  end if;

  fee := greatest(1, round(r.price * 0.08)::int);
  credit := greatest(0, r.price - fee);

  update public.market_listings
    set status = 'sold', buyer_id = uid, sold_at = now()
    where id = r.id;

  select * into cat from public.market_catalog where item_id = r.item_id;
  cur := coalesce((buyer.items->>r.item_id)::int, 0);

  update public.player_econ
    set gold = gold - r.price,
        items = public.econ_set_item(
          items, r.item_id,
          least(coalesce(cat.max_stack, 99), cur + r.qty)
        )
    where user_id = uid;

  insert into public.market_credit (user_id, pending_gold)
    values (r.seller_id, credit)
    on conflict (user_id) do update
      set pending_gold = public.market_credit.pending_gold + excluded.pending_gold;

  return jsonb_build_object(
    'ok', true,
    'item_id', r.item_id,
    'qty', r.qty,
    'price', r.price,
    'seller_credit', credit
  );
end;
$$;

grant execute on function public.market_buy(bigint) to authenticated;
revoke execute on function public.market_buy(bigint) from anon;


-- 領款：同步進影子帳，客戶端才能真的拿去買東西
create or replace function public.market_claim_credit()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  g   bigint;
begin
  if uid is null then
    return jsonb_build_object('gold', 0);
  end if;
  perform public.econ_row(uid);
  select pending_gold into g from public.market_credit
    where user_id = uid for update;
  if g is null or g <= 0 then
    return jsonb_build_object('ok', true, 'gold', 0);
  end if;
  update public.market_credit set pending_gold = 0 where user_id = uid;
  update public.player_econ set gold = gold + g where user_id = uid;
  return jsonb_build_object('ok', true, 'gold', g);
end;
$$;

grant execute on function public.market_claim_credit() to authenticated;
revoke execute on function public.market_claim_credit() from anon;

-- 掛單只能經 RPC 寫入
drop policy if exists "market_insert_own" on public.market_listings;
drop policy if exists "market_update_own_seller" on public.market_listings;


-- ══════════════════════════════════════════════════════════
-- 7. 共鬥領獎：一次就是一次
-- ══════════════════════════════════════════════════════════

create or replace function public.room_members_guard()
returns trigger
language plpgsql
as $$
begin
  if new.reward_claimed is distinct from old.reward_claimed
     and coalesce(current_setting('app.econ_bypass', true), '') <> '1' then
    raise exception 'reward_claimed is server-managed';
  end if;
  return new;
end;
$$;

drop trigger if exists room_members_guard_trg on public.room_members;
create trigger room_members_guard_trg
  before update on public.room_members
  for each row execute function public.room_members_guard();


create or replace function public.room_claim_reward(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rm  public.room_members%rowtype;
  rr  public.rooms%rowtype;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;

  select * into rr from public.rooms where id = p_room_id;
  if not found then
    return jsonb_build_object('error', 'room gone');
  end if;
  if rr.result <> 'win' then
    return jsonb_build_object('error', 'no win yet');
  end if;

  select * into rm from public.room_members
    where room_id = p_room_id and user_id = uid for update;
  if not found then
    return jsonb_build_object('error', 'not a member');
  end if;
  if rm.reward_claimed then
    return jsonb_build_object('error', 'already claimed');
  end if;

  perform set_config('app.econ_bypass', '1', true);
  update public.room_members set reward_claimed = true
    where room_id = p_room_id and user_id = uid;
  perform set_config('app.econ_bypass', '0', true);

  return jsonb_build_object('ok', true, 'mode', rr.mode);
end;
$$;

grant execute on function public.room_claim_reward(uuid) to authenticated;


-- 房主回報結果：順手把自己標成已領，走同一道閘門
create or replace function public.room_report_result(p_room_id uuid, p_result text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rr  public.rooms%rowtype;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;
  if p_result not in ('win', 'lose') then
    return jsonb_build_object('error', 'bad result');
  end if;

  select * into rr from public.rooms
    where id = p_room_id and host_id = uid for update;
  if not found then
    return jsonb_build_object('error', 'not host');
  end if;
  if rr.result = 'win' then
    return jsonb_build_object('error', 'already settled');
  end if;

  update public.rooms
    set result = p_result,
        status = case when p_result = 'win' then 'closed' else 'open' end,
        updated_at = now()
    where id = p_room_id;

  perform set_config('app.econ_bypass', '1', true);
  update public.room_members set reward_claimed = true
    where room_id = p_room_id and user_id = uid;
  perform set_config('app.econ_bypass', '0', true);

  return jsonb_build_object('ok', true, 'result', p_result);
end;
$$;

grant execute on function public.room_report_result(uuid, text) to authenticated;


-- ══════════════════════════════════════════════════════════
-- 8. 排行榜：分數只能經 RPC 進來
-- ══════════════════════════════════════════════════════════

create or replace function public.leaderboard_submit(p_board text, p_score bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  nm  text;
  cur bigint;
begin
  if uid is null then
    return jsonb_build_object('error', 'not signed in');
  end if;
  if p_board is null or char_length(p_board) = 0 or char_length(p_board) > 32 then
    return jsonb_build_object('error', 'bad board');
  end if;
  if p_score is null or p_score < 0 or p_score > 100000000 then
    return jsonb_build_object('error', 'score out of range');
  end if;

  select score into cur from public.leaderboard
    where board = p_board and user_id = uid;
  if cur is not null and cur >= p_score then
    return jsonb_build_object('ok', true, 'score', cur, 'kept', true);
  end if;

  select display_name into nm from public.profiles where user_id = uid;

  insert into public.leaderboard (board, user_id, display_name, score, updated_at)
    values (p_board, uid, coalesce(nm, '星途旅人'), p_score, now())
    on conflict (board, user_id) do update
      set score = excluded.score,
          display_name = excluded.display_name,
          updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'score', p_score);
end;
$$;

grant execute on function public.leaderboard_submit(text, bigint) to authenticated;

drop policy if exists "leaderboard_upsert_own" on public.leaderboard;
drop policy if exists "leaderboard_update_own" on public.leaderboard;


-- ══════════════════════════════════════════════════════════
-- 9. 留言石：擋洗版
-- ══════════════════════════════════════════════════════════

create or replace function public.messages_rate_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  lim int;
  n   int;
begin
  select message_per_min into lim from public.econ_config where id = 1;
  select count(*) into n from public.messages
    where user_id = new.user_id and created_at > now() - interval '1 minute';
  if n >= coalesce(lim, 6) then
    raise exception 'message rate limit';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_rate_guard_trg on public.messages;
create trigger messages_rate_guard_trg
  before insert on public.messages
  for each row execute function public.messages_rate_guard();


-- ══════════════════════════════════════════════════════════
-- 10. 收尾
-- ══════════════════════════════════════════════════════════
-- 舊版客戶端（0.14.9 以前）會直接 upsert saves／market_listings，本檔跑完後
-- 那些寫入會被 RLS 擋下並回 42501。務必同版更新客戶端。
--
-- 重跑順序：schema.sql 會把被本檔移除的舊 policy 加回來，所以
--   一定是先 schema.sql、後 economy.sql。
--
-- 人工複查：
--   select * from public.econ_audit order by created_at desc limit 50;
--   select user_id, gold, strikes from public.player_econ order by strikes desc limit 20;
-- 停權（只在確認濫用後手動下）：
--   update public.player_econ set blocked = true where user_id = '...';
