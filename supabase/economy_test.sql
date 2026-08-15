-- 經濟守門的情境測試：由 tools/test_economy_sql.sh 在丟完即棄的本機資料庫上跑
-- 不要在正式資料庫執行（會建測試帳號、寫測試資料）
--
-- 每一段都對應一種「玩家把客戶端改掉之後會試的事」。
-- 全部通過才印 ECON_SQL_OK。

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
  -- 6. 上架：影子帳沒有的東西掛不上去
  ------------------------------------------------------------------
  r := public.market_list_item('hunt_core', 10, 5000);
  if r->>'error' <> 'not enough items' then
    raise exception 'ECON_SQL_FAIL 6: 影子帳只有 % 個卻能掛 10 個，回應 %', n, r;
  end if;
  raise notice '  ok 6  沒有的貨掛不上去';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 7. 補足庫存後可以上架，且訂價有上限
  ------------------------------------------------------------------
  update public.player_econ
    set items = jsonb_build_object('hunt_core', 20), last_push = now() - interval '2 hours'
    where user_id = A;

  -- 基準價 60 × 10 個 × 20 倍 = 12000 上限
  r := public.market_list_item('hunt_core', 10, 999999);
  if r->>'error' <> 'price out of range' then
    raise exception 'ECON_SQL_FAIL 7: 天價掛單沒被擋，回應 %', r;
  end if;

  r := public.market_list_item('hunt_core', 10, 5000);
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 7: 正常掛單失敗，回應 %', r;
  end if;
  lid := (r->>'id')::bigint;
  select coalesce((items->>'hunt_core')::int, 0) into n
    from public.player_econ where user_id = A;
  if n <> 10 then
    raise exception 'ECON_SQL_FAIL 7: 上架後影子帳應剩 10，實際 %', n;
  end if;
  raise notice '  ok 7  天價擋下、正常掛單扣帳正確';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 8. 不可交易的品項掛不上去
  ------------------------------------------------------------------
  r := public.market_list_item('key_rusty', 1, 10);
  if r->>'error' <> 'item not tradeable' then
    raise exception 'ECON_SQL_FAIL 8: 非交易品竟可上架，回應 %', r;
  end if;
  raise notice '  ok 8  非交易品擋下';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 9. 沒錢買不了（買方付的是影子帳，不是存檔裡自己寫的數字）
  ------------------------------------------------------------------
  perform set_config('test.uid', B::text, true);
  r := public.save_push(jsonb_build_object(
        'gold', 100, 'inventory', '{}'::jsonb
      ), 1);
  r := public.market_buy(lid);
  if r->>'error' <> 'not enough gold' then
    raise exception 'ECON_SQL_FAIL 9: 沒錢卻買得動，回應 %', r;
  end if;
  raise notice '  ok 9  影子帳沒錢就買不動';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 10. 有錢就買得成，錢貨兩訖、賣家入待領款
  ------------------------------------------------------------------
  update public.player_econ set gold = 8000 where user_id = B;
  r := public.market_buy(lid);
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 10: 正常購買失敗，回應 %', r;
  end if;
  select gold, coalesce((items->>'hunt_core')::int, 0) into g, n
    from public.player_econ where user_id = B;
  if g <> 3000 then
    raise exception 'ECON_SQL_FAIL 10: 買方應剩 3000，實際 %', g;
  end if;
  if n <> 10 then
    raise exception 'ECON_SQL_FAIL 10: 買方應收到 10 個，實際 %', n;
  end if;
  -- 手續費 8%：5000 → 賣家 4600
  if (select pending_gold from public.market_credit where user_id = A) <> 4600 then
    raise exception 'ECON_SQL_FAIL 10: 賣家待領款不對';
  end if;
  raise notice '  ok 10  錢貨兩訖，手續費 8%% 正確';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 11. 同一筆掛單不能買第二次
  ------------------------------------------------------------------
  r := public.market_buy(lid);
  if r->>'error' <> 'listing gone' then
    raise exception 'ECON_SQL_FAIL 11: 掛單被買兩次，回應 %', r;
  end if;
  raise notice '  ok 11  掛單不能重複購買';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 12. 不能買自己的單
  ------------------------------------------------------------------
  perform set_config('test.uid', A::text, true);
  r := public.market_list_item('hunt_core', 5, 1000);
  lid2 := (r->>'id')::bigint;
  r := public.market_buy(lid2);
  if r->>'error' <> 'cannot buy own' then
    raise exception 'ECON_SQL_FAIL 12: 買到自己的單，回應 %', r;
  end if;
  raise notice '  ok 12  自己的單買不了';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 13. 下架退貨一次，下架兩次不會退兩次
  ------------------------------------------------------------------
  select coalesce((items->>'hunt_core')::int, 0) into n
    from public.player_econ where user_id = A;
  r := public.market_cancel_listing(lid2);
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 13: 下架失敗，回應 %', r;
  end if;
  if (select coalesce((items->>'hunt_core')::int, 0)
        from public.player_econ where user_id = A) <> n + 5 then
    raise exception 'ECON_SQL_FAIL 13: 下架沒退回 5 個';
  end if;
  r := public.market_cancel_listing(lid2);
  if r->>'error' <> 'listing gone' then
    raise exception 'ECON_SQL_FAIL 13: 下架兩次退兩次貨，回應 %', r;
  end if;
  raise notice '  ok 13  下架只退一次';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 14. 領貨款：進影子帳，且領完歸零
  ------------------------------------------------------------------
  select gold into g from public.player_econ where user_id = A;
  r := public.market_claim_credit();
  if (r->>'gold')::bigint <> 4600 then
    raise exception 'ECON_SQL_FAIL 14: 領款金額不對，回應 %', r;
  end if;
  if (select gold from public.player_econ where user_id = A) <> g + 4600 then
    raise exception 'ECON_SQL_FAIL 14: 貨款沒進影子帳';
  end if;
  r := public.market_claim_credit();
  if (r->>'gold')::bigint <> 0 then
    raise exception 'ECON_SQL_FAIL 14: 貨款可以領第二次';
  end if;
  raise notice '  ok 14  貨款進影子帳且只能領一次';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 15. 掛單數量上限
  ------------------------------------------------------------------
  update public.player_econ set items = jsonb_build_object('hunt_hide', 99) where user_id = A;
  for n in 1..8 loop
    r := public.market_list_item('hunt_hide', 1, 100);
  end loop;
  r := public.market_list_item('hunt_hide', 1, 100);
  if r->>'error' <> 'too many listings' then
    raise exception 'ECON_SQL_FAIL 15: 掛單上限沒生效，回應 %', r;
  end if;
  raise notice '  ok 15  同時掛單上限 8 生效';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 16. 共鬥領獎：房主結算後不能再領，成員只能領一次
  ------------------------------------------------------------------
  insert into public.rooms (host_id, mode, status) values (A, 'wrath', 'open')
    returning id into rid;
  insert into public.room_members (room_id, user_id, display_name) values
    (rid, A, '甲旅人'), (rid, B, '乙旅人');

  r := public.room_report_result(rid, 'win');
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 16: 房主回報失敗，回應 %', r;
  end if;
  r := public.room_claim_reward(rid);
  if r->>'error' <> 'already claimed' then
    raise exception 'ECON_SQL_FAIL 16: 房主結算後還能再領，回應 %', r;
  end if;
  r := public.room_report_result(rid, 'win');
  if r->>'error' <> 'already settled' then
    raise exception 'ECON_SQL_FAIL 16: 同一場可以結算兩次，回應 %', r;
  end if;

  perform set_config('test.uid', B::text, true);
  r := public.room_claim_reward(rid);
  if (r->>'ok')::boolean is not true then
    raise exception 'ECON_SQL_FAIL 16: 成員第一次領獎失敗，回應 %', r;
  end if;
  r := public.room_claim_reward(rid);
  if r->>'error' <> 'already claimed' then
    raise exception 'ECON_SQL_FAIL 16: 成員可以重複領獎，回應 %', r;
  end if;
  raise notice '  ok 16  共鬥獎一人一次';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 17. 直接改領獎旗標會被擋
  ------------------------------------------------------------------
  begin
    update public.room_members set reward_claimed = false
      where room_id = rid and user_id = B;
    raise exception 'ECON_SQL_FAIL 17: 領獎旗標可以直接被改回去';
  exception when others then
    if sqlerrm like 'ECON_SQL_FAIL%' then
      raise;
    end if;
  end;
  raise notice '  ok 17  領獎旗標改不動';
  passed := passed + 1;

  ------------------------------------------------------------------
  -- 18. 排行榜：只進不退，且分數有上限
  ------------------------------------------------------------------
  r := public.leaderboard_submit('rift_weekly', 500);
  r := public.leaderboard_submit('rift_weekly', 100);
  if (select score from public.leaderboard where board = 'rift_weekly' and user_id = B) <> 500 then
    raise exception 'ECON_SQL_FAIL 18: 較低分覆蓋了高分';
  end if;
  r := public.leaderboard_submit('rift_weekly', 999999999999);
  if r->>'error' <> 'score out of range' then
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

  set local role authenticated;
  begin
    insert into public.market_listings (seller_id, item_id, qty, price)
      values (A, 'hunt_core', 99, 999999);
    reset role;
    raise exception 'ECON_SQL_FAIL 20: 掛單還能被直接寫入';
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
  raise notice '  ok 20  存檔／掛單／排行榜／影子帳 4 條側門全部堵死';
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
    perform public.market_list_item('hunt_core', 1, 100);
    reset role;
    raise exception 'ECON_SQL_FAIL 21: 未登入者可以呼叫上架';
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
