-- 退掉市集／裂縫房／狩獵房／歲旅活動的伺服器端物件（2026-08-16）
--
-- 遊戲端那五個系統已經移除（理由見 docs/DECISIONS.md），schema.sql 與
-- economy.sql 也不再建立這些東西。這支是給**已經部署過舊版**的專案用的：
-- 重跑 schema/economy 不會刪掉既有的表，得明確 drop。
--
-- 跑之前先確認沒有資料要留：
--   select count(*) from public.market_listings;   -- 掛單
--   select count(*) from public.market_credit;     -- 待領貨款
--   select count(*) from public.rooms;             -- 房間
--   select count(*) from public.event_progress;    -- 活動進度
-- 2026-08-16 在正式專案上跑的時候，這四張都是 0 列。
--
-- ⚠ market_catalog **不在這份清單裡**。名字有 market 但它現在是
--    save_push 用來限制可交易物成長速率的白名單，刪掉存檔就推不上去了。
--
-- 順序：先函式後表。函式裡有對表的 reference，反過來 drop 會留下壞掉的函式。

begin;

-- ── 市集 RPC ──
drop function if exists public.market_list_item(text, int, int);
drop function if exists public.market_cancel_listing(bigint);
drop function if exists public.market_buy(bigint);
drop function if exists public.market_claim_credit();

-- ── 共鬥 RPC 與觸發器 ──
drop trigger if exists room_members_guard_trg on public.room_members;
drop function if exists public.room_claim_reward(uuid);
drop function if exists public.room_report_result(uuid, text);
drop function if exists public.room_members_guard();

-- ── 表（cascade 一併帶走 policy、index、外鍵）──
drop table if exists public.market_credit   cascade;
drop table if exists public.market_listings cascade;
drop table if exists public.room_inputs     cascade;
drop table if exists public.room_events     cascade;
drop table if exists public.room_members    cascade;
drop table if exists public.rooms           cascade;
drop table if exists public.event_progress  cascade;

commit;

-- 驗證：下面兩查都該回 0 列
--   select tablename from pg_tables where schemaname = 'public'
--     and tablename in ('market_listings','market_credit','rooms','room_members',
--                       'room_events','room_inputs','event_progress');
--   select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and (proname like 'market\_%' or proname like 'room\_%')
--       and proname <> 'market_catalog';
