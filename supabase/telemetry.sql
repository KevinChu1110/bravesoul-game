-- 翠嶺·兔勇者 — 第 7 步：體驗回報（遙測）
-- 前置：先跑過 supabase/schema.sql，再跑 supabase/economy.sql
-- 在 Supabase SQL Editor 整段執行；可重複執行（idempotent）
--
-- 設計要點
--   這份資料的用途只有一個：知道玩家卡在哪，然後去改那一段。
--   所以它刻意收得很少（五種事件），而且刻意不認得人。
--
--   身分只有客戶端自己產的 install_id（一顆亂數 uuid），沒有 auth.users 外鍵，
--   跟帳號、信箱、存檔都接不起來。這不是疏漏，是要求：接得起來就變成個資。
--
--   回報是匿名的，所以 telemetry_ingest 必須開給 anon——沒登入的玩家佔多數，
--   要他們先辦帳號才肯收資料，收到的就只剩最黏的那群人，數字沒有意義。
--   代價是誰都能打這支 RPC，所以擋量的責任全在這裡：
--     每個 install 每小時有上限、每次呼叫筆數有上限，
--     另外還有一道全站每小時上限——install_id 是客戶端給的，換一顆就繞過個人上限，
--     真正擋得住灌爆的是全站那道。
--
--   欄位在伺服器再洗一次。客戶端已經只送 a-z0-9_ 的短字串，
--   但客戶端是玩家的，改得動；能不能把自由文字寫進資料庫要由這裡決定。


-- ══════════════════════════════════════════════════════════
-- 1. 參數
-- ══════════════════════════════════════════════════════════

create table if not exists public.telemetry_config (
  id                   int primary key default 1 check (id = 1),
  events_per_call      int not null default 50,      -- 單次 RPC 最多幾筆
  events_per_hour      int not null default 600,     -- 單一 install 每小時上限
  calls_per_hour       int not null default 120,     -- 單一 install 每小時呼叫次數
  global_events_per_hour bigint not null default 500000,  -- 全站每小時上限（擋灌爆）
  retain_days          int not null default 120,     -- 保留天數，過期由 telemetry_prune 清
  allowed_names        text[] not null default array[
                         'session_start', 'session_tick', 'chapter_enter',
                         'battle_end', 'tutorial_step'
                       ]
);

insert into public.telemetry_config (id) values (1) on conflict (id) do nothing;

alter table public.telemetry_config enable row level security;
-- 沒有任何 policy：玩家連參數都不必知道


-- ══════════════════════════════════════════════════════════
-- 2. 事件表
-- ══════════════════════════════════════════════════════════

create table if not exists public.telemetry_events (
  id          bigserial primary key,
  install_id  uuid not null,          -- 本機亂數，刻意不連 auth.users
  session_id  uuid not null,
  name        text not null,
  props       jsonb not null default '{}'::jsonb,
  session_sec int  not null default 0,  -- 這筆發生在本次遊玩的第幾秒
  app_version text not null default '',
  created_at  timestamptz not null default now()
);

-- 查詢一律是「某事件在某段時間的分布」，索引照這個形狀開
create index if not exists telemetry_events_name_created
  on public.telemetry_events (name, created_at desc);
create index if not exists telemetry_events_install_created
  on public.telemetry_events (install_id, created_at desc);
create index if not exists telemetry_events_session
  on public.telemetry_events (session_id);

alter table public.telemetry_events enable row level security;
-- 沒有任何 policy：玩家不能讀、不能寫，只有 telemetry_ingest 進得去


-- ══════════════════════════════════════════════════════════
-- 3. 限流帳
-- ══════════════════════════════════════════════════════════

create table if not exists public.telemetry_quota (
  install_id   uuid primary key,
  window_start timestamptz not null default now(),
  events_in_window int not null default 0,
  calls_in_window  int not null default 0,
  over_limit_hits  int not null default 0,   -- 撞上限幾次（人工複查用）
  blocked      boolean not null default false, -- 只由人工設定
  total_events bigint not null default 0,
  last_seen    timestamptz not null default now()
);

alter table public.telemetry_quota enable row level security;

-- 全站閘門：install_id 換一顆就能繞過個人上限，這道才是真的防線
create table if not exists public.telemetry_gate (
  id           int primary key default 1 check (id = 1),
  window_start timestamptz not null default now(),
  events_in_window bigint not null default 0
);

insert into public.telemetry_gate (id) values (1) on conflict (id) do nothing;

alter table public.telemetry_gate enable row level security;


-- ══════════════════════════════════════════════════════════
-- 4. 欄位清洗
-- ══════════════════════════════════════════════════════════

-- 只留白名單欄位；字串限定 a-z0-9_ 的短 token。
-- 玩家名字、留言、檔案路徑這類自由文字在型別上就寫不進來，
-- 不必依賴「客戶端記得別傳」。
create or replace function public.telemetry_clean_props(p jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) as t(k, v)
  where k in ('chapter', 'level', 'ng', 'sec', 'mode', 'boss', 'won', 'dur', 'place', 'step')
    and (
      jsonb_typeof(v) in ('number', 'boolean')
      or (jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^[a-z0-9_]{1,32}$')
    );
$$;


-- ══════════════════════════════════════════════════════════
-- 5. 寫入口：唯一能把事件放進資料庫的路
-- ══════════════════════════════════════════════════════════

create or replace function public.telemetry_ingest(
  p_install uuid,
  p_session uuid,
  p_version text,
  p_events  jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg   public.telemetry_config%rowtype;
  q     public.telemetry_quota%rowtype;
  gate  public.telemetry_gate%rowtype;
  n     int;
  ver   text;
  taken int;
begin
  select * into cfg from public.telemetry_config where id = 1;
  if not found then
    return jsonb_build_object('error', 'telemetry off');
  end if;

  if p_install is null or p_session is null then
    return jsonb_build_object('error', 'bad batch');
  end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    return jsonb_build_object('error', 'bad batch');
  end if;

  n := jsonb_array_length(p_events);
  if n = 0 then
    return jsonb_build_object('ok', true, 'accepted', 0);
  end if;
  if n > cfg.events_per_call then
    return jsonb_build_object('error', 'batch too large');
  end if;

  -- 版本字串也是客戶端給的，只留得出來的字元
  ver := left(regexp_replace(lower(coalesce(p_version, '')), '[^a-z0-9._-]', '', 'g'), 16);

  -- ── 個人額度 ──
  insert into public.telemetry_quota (install_id) values (p_install)
    on conflict (install_id) do nothing;
  select * into q from public.telemetry_quota where install_id = p_install for update;

  if q.blocked then
    return jsonb_build_object('error', 'telemetry blocked');
  end if;

  if q.window_start < now() - interval '1 hour' then
    q.window_start := now();
    q.events_in_window := 0;
    q.calls_in_window := 0;
  end if;

  if q.calls_in_window + 1 > cfg.calls_per_hour
     or q.events_in_window + n > cfg.events_per_hour then
    update public.telemetry_quota
      set window_start = q.window_start,
          events_in_window = q.events_in_window,
          calls_in_window = q.calls_in_window + 1,
          over_limit_hits = over_limit_hits + 1,
          last_seen = now()
      where install_id = p_install;
    return jsonb_build_object('error', 'telemetry rate limit');
  end if;

  -- ── 全站閘門 ──
  select * into gate from public.telemetry_gate where id = 1 for update;
  if gate.window_start < now() - interval '1 hour' then
    gate.window_start := now();
    gate.events_in_window := 0;
  end if;
  if gate.events_in_window + n > cfg.global_events_per_hour then
    update public.telemetry_gate
      set window_start = gate.window_start, events_in_window = gate.events_in_window
      where id = 1;
    update public.telemetry_quota
      set calls_in_window = q.calls_in_window + 1, last_seen = now()
      where install_id = p_install;
    return jsonb_build_object('error', 'telemetry busy');
  end if;

  -- ── 寫入（名稱不在白名單的整筆丟掉，不報錯：舊版客戶端不該因此壞掉）──
  insert into public.telemetry_events
    (install_id, session_id, name, props, session_sec, app_version)
  select
    p_install,
    p_session,
    e->>'n',
    public.telemetry_clean_props(e->'p'),
    case when (e->>'s') ~ '^[0-9]{1,7}$'
         then least((e->>'s')::int, 86400) else 0 end,
    ver
  from jsonb_array_elements(p_events) as e
  where jsonb_typeof(e) = 'object'
    and e->>'n' = any(cfg.allowed_names);
  get diagnostics taken = row_count;

  update public.telemetry_quota
    set window_start = q.window_start,
        events_in_window = q.events_in_window + taken,
        calls_in_window = q.calls_in_window + 1,
        total_events = total_events + taken,
        last_seen = now()
    where install_id = p_install;

  update public.telemetry_gate
    set window_start = gate.window_start,
        events_in_window = gate.events_in_window + taken
    where id = 1;

  return jsonb_build_object('ok', true, 'accepted', taken, 'dropped', n - taken);
end;
$$;


-- ══════════════════════════════════════════════════════════
-- 6. 清理：資料留著只為了改遊戲，過期就沒有留的理由
-- ══════════════════════════════════════════════════════════

create or replace function public.telemetry_prune(p_days int default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  d int;
  removed bigint;
begin
  select coalesce(p_days, retain_days) into d from public.telemetry_config where id = 1;
  delete from public.telemetry_events where created_at < now() - make_interval(days => coalesce(d, 120));
  get diagnostics removed = row_count;
  delete from public.telemetry_quota where last_seen < now() - interval '30 days' and not blocked;
  return removed;
end;
$$;


-- ══════════════════════════════════════════════════════════
-- 7. 看數字用的視圖
-- ══════════════════════════════════════════════════════════
-- 這幾張就是收這些事件的理由。每一張對應一個會動手改的決定。
-- 都不開放給 anon／authenticated，只有 Dashboard（service_role）讀得到。

-- 章節漏斗：哪一章之後人就不見了
drop view if exists public.telemetry_chapter_funnel cascade;
create view public.telemetry_chapter_funnel as
  select
    props->>'chapter' as chapter,
    count(distinct install_id) as reached,
    round(avg((props->>'level')::numeric), 1) as avg_level
  from public.telemetry_events
  where name = 'chapter_enter' and props ? 'chapter'
  group by 1
  order by reached desc;

-- Boss 牆：勸退率＝挑戰過但一次都沒贏的人佔多少
drop view if exists public.telemetry_boss_wall cascade;
create view public.telemetry_boss_wall as
  select
    props->>'mode' as boss,
    count(*) as attempts,
    count(*) filter (where (props->>'won')::boolean) as wins,
    count(distinct install_id) as challengers,
    count(distinct install_id) filter (where (props->>'won')::boolean) as clearers,
    round(
      1 - count(distinct install_id) filter (where (props->>'won')::boolean)::numeric
        / nullif(count(distinct install_id), 0), 3
    ) as give_up_rate,
    round(avg((props->>'dur')::numeric) filter (where (props->>'won')::boolean), 1) as avg_win_sec
  from public.telemetry_events
  where name = 'battle_end' and (props->>'boss')::boolean is true
  group by 1
  order by give_up_rate desc nulls last;

-- 死亡熱點：在哪張圖、被誰打倒最多次
drop view if exists public.telemetry_death_spots cascade;
create view public.telemetry_death_spots as
  select
    coalesce(props->>'place', '(unknown)') as place,
    props->>'mode' as mode,
    count(*) as deaths,
    count(distinct install_id) as installs,
    round(avg((props->>'level')::numeric), 1) as avg_level
  from public.telemetry_events
  where name = 'battle_end' and (props->>'won')::boolean is false
  group by 1, 2
  order by deaths desc;

-- 教學漏斗：哪一步之後就沒有下一步了
drop view if exists public.telemetry_tutorial_funnel cascade;
create view public.telemetry_tutorial_funnel as
  select
    props->>'step' as step,
    count(distinct install_id) as installs,
    min(created_at) as first_seen
  from public.telemetry_events
  where name = 'tutorial_step' and props ? 'step'
  group by 1
  order by installs desc;

-- 遊玩時長：一次坐下來玩多久（取每個 session 的最大秒數）
drop view if exists public.telemetry_session_len cascade;
create view public.telemetry_session_len as
  with s as (
    select session_id, install_id, max(session_sec) as len
    from public.telemetry_events
    group by 1, 2
  )
  select
    case
      when len < 300 then 'a_under_5m'
      when len < 900 then 'b_5_15m'
      when len < 1800 then 'c_15_30m'
      when len < 3600 then 'd_30_60m'
      else 'e_over_60m'
    end as bucket,
    count(*) as sessions,
    count(distinct install_id) as installs
  from s
  group by 1
  order by 1;


-- ══════════════════════════════════════════════════════════
-- 8. 權限收斂
-- ══════════════════════════════════════════════════════════
-- PostgreSQL 預設把新函式的 execute 給 PUBLIC，而 anon 是 PUBLIC 的成員，
-- 所以「只 grant 給 authenticated」擋不掉未登入者。順序要緊：
-- 先 revoke public/anon/authenticated，再把該給的明確給回去。
--
-- Supabase 另外會對 public schema 的新表自動授權給 anon／authenticated，
-- 所以表也要一張一張收回來，不能只靠 RLS。

revoke all on public.telemetry_events   from public, anon, authenticated;
revoke all on public.telemetry_quota    from public, anon, authenticated;
revoke all on public.telemetry_gate     from public, anon, authenticated;
revoke all on public.telemetry_config   from public, anon, authenticated;
revoke all on sequence public.telemetry_events_id_seq from public, anon, authenticated;

revoke all on public.telemetry_chapter_funnel  from public, anon, authenticated;
revoke all on public.telemetry_boss_wall       from public, anon, authenticated;
revoke all on public.telemetry_death_spots     from public, anon, authenticated;
revoke all on public.telemetry_tutorial_funnel from public, anon, authenticated;
revoke all on public.telemetry_session_len     from public, anon, authenticated;

-- 清洗與清理是內部工具，不該出現在 REST 上
revoke execute on function public.telemetry_clean_props(jsonb) from public, anon, authenticated;
revoke execute on function public.telemetry_prune(int) from public, anon, authenticated;

-- 寫入口刻意開給未登入者（匿名回報），但先收乾淨再明確給回去
revoke execute on function public.telemetry_ingest(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.telemetry_ingest(uuid, uuid, text, jsonb) to anon, authenticated;


-- ══════════════════════════════════════════════════════════
-- 9. 收尾
-- ══════════════════════════════════════════════════════════
-- 定期清理：正式專案已排程為 `telemetry-prune-daily`
--   （Integrations → Cron，0 18 * * * GMT ＝台北 02:00）
--   select public.telemetry_prune();
-- 新專案要自己排：那頁得先按 Install integration 裝 pg_cron，
-- 沒裝的話建 job 只會回 relation "cron.job" does not exist。
--
-- 看數字：
--   select * from public.telemetry_chapter_funnel;
--   select * from public.telemetry_boss_wall;
--   select * from public.telemetry_death_spots limit 30;
--   select * from public.telemetry_tutorial_funnel;
--   select * from public.telemetry_session_len;
--
-- 被灌爆時（先看是不是同一顆 install）：
--   select install_id, total_events, over_limit_hits from public.telemetry_quota
--     order by total_events desc limit 20;
--   update public.telemetry_quota set blocked = true where install_id = '...';
-- 若是換 install_id 的分散灌入，調小全站上限：
--   update public.telemetry_config set global_events_per_hour = 50000 where id = 1;
