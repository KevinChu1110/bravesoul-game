-- 經濟守門的情境測試：由 tools/test_economy_sql.sh 在丟完即棄的本機資料庫上跑
-- 不要在正式資料庫執行（會建測試帳號、寫測試資料）
--
-- 每一段都對應一種「玩家把客戶端改掉之後會試的事」。
-- 全部通過才印 ECON_SQL_OK。
--
-- ⚠ 比對錯誤碼一律用 `is distinct from`，不要用 `<>`。
-- 這裡本來全部寫成 `if r->>'error' <> '...' then raise`，那是假斷言：
-- 守門被拿掉的時候 RPC 會回成功，'error' 是 NULL，NULL <> '字串' 的結果是 NULL，
-- 而 plpgsql 的 if 把 NULL 當 false —— 於是「這件事應該被擋下來」這類斷言，
-- 剛好在沒擋下來的時候閉嘴。這是整份測試最容易全綠卻什麼都沒守的地方。

-- Supabase 預設會把 public 的表權限開給 anon/authenticated，
-- 這裡照做，測到的才是 RLS 那一層而不是 grant 那一層。
grant usage on schema public to authenticated, anon;
grant all on all tables in schema public to authenticated, anon;
grant all on all sequences in schema public to authenticated, anon;

do $$
declare
  A uuid := '11111111-1111-1111-1111-111111111111';
  B uuid := '22222222-2222-2222-2222-222222222222';
  r        jsonb;
  g        bigint;
  n        int;
  lid      bigint;
  lid2     bigint;
  rid      uuid;
  passed   int := 0;
begin
  -- ── 準備 ──
  insert into auth.users (id) values (A), (B) on conflict do nothing;
  insert into public.profiles (user_id, display_name) values
    (A, '甲旅人'), (B, '乙旅人') on conflict do nothing;

  ------------------------------------------------------------------
  -- 1. 首次建帳：存檔說有一千萬，影子帳只採信 gold_seed_max
  ------------------------------------------------------------------
  perform set_config('test.uid', A::text, true);
  r := public.save_push(jsonb_build_object(
        'gold', 10000000,
        'inventory', jsonb_build_object('hunt_core', 99, 'hunt_hide', 40)
      ), 1);
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 1: 首次推送應該成功，得到 %', r;
  end if;
  select gold into g from public.player_econ where user_id = A;
  if g <> 200000 then
    raise exception 'ECON_SQL_FAIL 1: 首次建帳應封頂在 200000，實際 %', g;
  end if;
  -- 存檔本身要原封不動存下來（玩家自己的資料不動它）
  if (select (payload->>'gold')::bigint from public.saves where user_id = A) <> 10000000 then
    raise exception 'ECON_SQL_FAIL 1: saves.payload 不該被改寫';
  end if;
  raise notice '  ok 1  首次建帳封頂，存檔原文保留';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 2. 連續猛推存檔不會多拿額度（額度只跟真實時間走）
  ------------------------------------------------------------------
  for n in 1..5 loop
    r := public.save_push(jsonb_build_object(
          'gold', 999999999,
          'inventory', jsonb_build_object('hunt_core', 99)
        ), 1);
  end loop;
  select gold into g from public.player_econ where user_id = A;
  if g > 200000 + 5000 then
    raise exception 'ECON_SQL_FAIL 2: 猛推 5 次就長到 %，額度被重複發放', g;
  end if;
  raise notice '  ok 2  連推 5 次沒有多拿額度（餘額 %）', g;
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 3. 過了一小時，額度才按速率長出來
  ------------------------------------------------------------------
  update public.player_econ set last_push = now() - interval '1 hour' where user_id = A;
  r := public.save_push(jsonb_build_object(
        'gold', 999999999,
        'inventory', jsonb_build_object('hunt_core', 99)
      ), 1);
  select gold into g from public.player_econ where user_id = A;
  -- 一小時額度 = 60/秒 × 3600 = 216000
  if g < 400000 or g > 420000 then
    raise exception 'ECON_SQL_FAIL 3: 一小時後應約 416000，實際 %', g;
  end if;
  raise notice '  ok 3  一小時長出 216000 額度（餘額 %）', g;
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 4. 往下精確跟隨：花掉就是花掉，不能只在存檔裡花
  ------------------------------------------------------------------
  r := public.save_push(jsonb_build_object(
        'gold', 500,
        'inventory', jsonb_build_object('hunt_core', 99)
      ), 1);
  select gold into g from public.player_econ where user_id = A;
  if g <> 500 then
    raise exception 'ECON_SQL_FAIL 4: 存檔降到 500，影子帳應同步降，實際 %', g;
  end if;
  raise notice '  ok 4  存檔變少時影子帳精確跟隨';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 5. 物品也長不快：額度用完後，短時間內補不回來
  ------------------------------------------------------------------
  update public.player_econ set item_credit = 0, last_push = now() where user_id = A;
  r := public.save_push(jsonb_build_object(
        'gold', 500, 'inventory', jsonb_build_object('hunt_core', 0)
      ), 1);
  r := public.save_push(jsonb_build_object(
        'gold', 500, 'inventory', jsonb_build_object('hunt_core', 99)
      ), 1);
  select coalesce((items->>'hunt_core')::int, 0) into n
    from public.player_econ where user_id = A;
  if n > 3 then
    raise exception 'ECON_SQL_FAIL 5: 物品瞬間補回 %，成長額度沒擋住', n;
  end if;
  raise notice '  ok 5  額度用完後物品補不回來（目前 %）', n;
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 5b. 掛機再久，能一次補的量也有上限（額度結轉封頂）
  ------------------------------------------------------------------
  update public.player_econ
    set item_credit = 0, items = '{}'::jsonb, last_push = now() - interval '30 days'
    where user_id = A;
  r := public.save_push(jsonb_build_object(
        'gold', 500,
        'inventory', jsonb_build_object('hunt_core', 99, 'hunt_hide', 99, 'hunt_bone', 99,
                                        'wolf_fang', 99, 'mist_shard', 99, 'sea_shell', 99)
      ), 1);
  select coalesce((items->>'hunt_core')::int, 0)
       + coalesce((items->>'hunt_hide')::int, 0)
       + coalesce((items->>'hunt_bone')::int, 0)
       + coalesce((items->>'wolf_fang')::int, 0)
       + coalesce((items->>'mist_shard')::int, 0)
       + coalesce((items->>'sea_shell')::int, 0) into n
    from public.player_econ where user_id = A;
  if n > 400 then
    raise exception 'ECON_SQL_FAIL 5b: 掛機 30 天一次補了 % 個，額度結轉沒封頂', n;
  end if;
  raise notice '  ok 5b 掛機 30 天也只補得回 % 個（上限 400）', n;
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 6～17（市集上架／買賣／下架／領款／共鬥領獎）：2026-08-16 隨系統一起刪掉
  --
  -- 那 12 段測的是 market_* 與 room_* RPC，函式已經不存在了。
  -- 編號沒有往前補：舊 commit 裡的「第 9 段」指的是哪件事，不該因為後來
  -- 刪了幾段就改變意思。
  ------------------------------------------------------------------

  ------------------------------------------------------------------
  -- 18. 排行榜：只進不退，且分數有上限
  ------------------------------------------------------------------
  r := public.leaderboard_submit('rift_weekly', 500);
  r := public.leaderboard_submit('rift_weekly', 100);
  if (select score from public.leaderboard where board = 'rift_weekly' and user_id = B) <> 500 then
    raise exception 'ECON_SQL_FAIL 18: 較低分覆蓋了高分';
  end if;
  r := public.leaderboard_submit('rift_weekly', 999999999999);
  if r->>'error' is distinct from 'score out of range' then
    raise exception 'ECON_SQL_FAIL 18: 天價分數沒被擋，回應 %', r;
  end if;
  raise notice '  ok 18  排行榜只進不退且有上限';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 19. 留言限流
  ------------------------------------------------------------------
  begin
    for n in 1..7 loop
      insert into public.messages (user_id, place, body) values (B, 'town', '足跡 ' || n);
    end loop;
    raise exception 'ECON_SQL_FAIL 19: 一分鐘塞 7 則沒被擋';
  exception when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then
      raise;
    end if;
  end;
  raise notice '  ok 19  留言限流生效';
  passed := passed + 1;

  raise notice '';
  raise notice '函式層 % 項全過', passed;
end $$;

-- ── RLS 層：確認客戶端真的沒有側門可以走 ──
do $$
declare
  A uuid := '11111111-1111-1111-1111-111111111111';
  blocked int := 0;
begin
  perform set_config('test.uid', A::text, true);
  set local role authenticated;

  begin
    insert into public.saves (user_id, payload) values (A, '{"gold": 999999999}'::jsonb);
    reset role;
    raise exception 'ECON_SQL_FAIL 20: 存檔還能被直接寫入';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  -- 市集砍掉後，market_catalog 變成 save_push 用來限制成長速率的白名單。
  -- 玩家能改它就能自己開一種「基準價很高、上限很大」的道具，等於繞過整套守門。
  -- （原本這格測的是掛單表擋不擋得住；那張表已經 drop 了，
  --  留著會變成「表不存在所以擋下來」的假綠燈。）
  set local role authenticated;
  begin
    insert into public.market_catalog (item_id, base_price, max_stack)
      values ('cheat_item', 1, 9999);
    reset role;
    raise exception 'ECON_SQL_FAIL 20: 可交易物清單還能被玩家寫入';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role authenticated;
  begin
    insert into public.leaderboard (board, user_id, score) values ('rift_weekly', A, 99999999);
    reset role;
    raise exception 'ECON_SQL_FAIL 20: 排行榜還能被直接寫入';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role authenticated;
  begin
    update public.player_econ set gold = 999999999 where user_id = A;
    if found then
      reset role;
      raise exception 'ECON_SQL_FAIL 20: 影子帳可以被玩家自己改';
    end if;
    blocked := blocked + 1;
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  reset role;
  if blocked <> 4 then
    raise exception 'ECON_SQL_FAIL 20: 只擋下 % 條側門，應為 4', blocked;
  end if;
  raise notice '  ok 20  存檔／可交易物清單／排行榜／影子帳 4 條側門全部堵死';
end $$;

-- ── 曝險面：沒登入的 anon 連呼叫都不該呼叫得到 ──
do $$
declare
  blocked int := 0;
begin
  set local role anon;
  begin
    perform public.save_push('{"gold": 1}'::jsonb, 1);
    reset role;
    raise exception 'ECON_SQL_FAIL 21: 未登入者可以呼叫存檔推送';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role anon;
  begin
    perform public.leaderboard_submit('rift_weekly', 100);
    reset role;
    raise exception 'ECON_SQL_FAIL 21: 未登入者可以呼叫上榜';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  -- 觸發器用的函式不該被任何人當 API 呼叫
  set local role authenticated;
  begin
    perform public.messages_rate_guard();
    reset role;
    raise exception 'ECON_SQL_FAIL 21: 觸發器函式被當成 API 呼叫得到';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  reset role;
  if blocked <> 3 then
    raise exception 'ECON_SQL_FAIL 21: 只擋下 % 條，應為 3', blocked;
  end if;
  raise notice '  ok 21  未登入者與觸發器函式的呼叫權限已收乾淨';
  raise notice '';
  raise notice 'ECON_SQL_OK';
end $$;
