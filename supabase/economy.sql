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
--   客戶端再也不能直接寫 saves，只能經 save_push 進來。
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
-- 3. 可交易物清單（伺服器自己的一份，別信客戶端報價）
-- ══════════════════════════════════════════════════════════
-- 市集砍掉之後，這張表的角色從「商品定價」變成「save_push 拿來限制
-- 可交易物成長速率的白名單」——沒列在這裡的道具，影子帳不管它。
-- 表名沒跟著改，原因寫在下面第 6～7 節。

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
set search_path = pg_catalog
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
-- 6～7. 市集 RPC 與共鬥領獎：2026-08-16 移除
-- ══════════════════════════════════════════════════════════
--
-- market_list_item / market_cancel_listing / market_buy / market_claim_credit /
-- room_report_result / room_claim_reward / room_members_guard 全部砍掉。
-- 遊戲端的市集、裂縫房、狩獵房、助戰也一起移除（理由見 docs/DECISIONS.md）。
--
-- market_catalog 這張表**留著**：它現在的角色不是市集商品表，而是
-- save_push 用來限制「可交易物成長速率」的清單。名字沒改是因為改名要一路動到
-- save_push 與 economy_test.sql，跟這次的移除混在一起出事會分不清是哪一邊。
--
-- 已部署的專案要退掉那些函式與表，跑 supabase/drop_market_rooms.sql。


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
-- 10. 權限收斂
-- ══════════════════════════════════════════════════════════
-- PostgreSQL 預設把新函式的 execute 給 PUBLIC，而 anon 是 PUBLIC 的成員——
-- 所以「只 grant 給 authenticated」並不會擋掉未登入者。每支函式內部都有
-- auth.uid() 檢查，這裡收的是曝險面：沒登入就連呼叫都呼叫不到。
-- 順序要緊：先 revoke PUBLIC，再 grant 回 authenticated。

do $$
declare
  fn text;
  player_fns text[] := array[
    'public.save_push(jsonb, int)',
    'public.leaderboard_submit(text, bigint)',
    'public.econ_state()'
  ];
  -- 觸發器用的函式不該出現在 REST 上，誰都不給
  internal_fns text[] := array[
    'public.messages_rate_guard()',
    'public.econ_set_item(jsonb, text, int)'
  ];
begin
  foreach fn in array player_fns loop
    execute format('revoke execute on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
  foreach fn in array internal_fns loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
  end loop;
end $$;

-- 點燈是刻意開放給未登入者的（官網也會顯示總數），但補上 search_path
create or replace function public.candle_increment()
returns bigint
language plpgsql
security definer
set search_path = public
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


-- ══════════════════════════════════════════════════════════
-- 11. 收尾
-- ══════════════════════════════════════════════════════════
-- 舊版客戶端（0.14.9 以前）會直接 upsert saves，本檔跑完後那些寫入會被 RLS
-- 擋下並回 42501。務必同版更新客戶端。
--
-- 重跑順序：schema.sql 會把被本檔移除的舊 policy 加回來，所以
--   一定是先 schema.sql、後 economy.sql。
--
-- 人工複查：
--   select * from public.econ_audit order by created_at desc limit 50;
--   select user_id, gold, strikes from public.player_econ order by strikes desc limit 20;
-- 停權（只在確認濫用後手動下）：
--   update public.player_econ set blocked = true where user_id = '...';
