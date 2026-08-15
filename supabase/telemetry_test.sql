-- 體驗回報的情境測試：由 tools/test_economy_sql.sh 在丟完即棄的本機資料庫上跑
-- 不要在正式資料庫執行（會寫測試事件、動參數）
--
-- 每一段對應一件「這份設計說它做得到」的事。全過才印 TELEMETRY_SQL_OK。
--
-- ⚠ 比對錯誤碼一律用 `is distinct from`，不要用 `<>`。
-- 原本寫的是 `if r->>'error' <> '...' then raise`，那是假的：
-- 擋不住的時候 ingest 會回成功，'error' 是 NULL，NULL <> '字串' 的結果是 NULL，
-- 而 plpgsql 的 if 把 NULL 當成 false —— 也就是說，**只有在守門有效的時候
-- 這條斷言才有可能觸發**，守門一被拿掉它反而安靜了。變異測試證實過：
-- 把全站閘門整段拿掉，這份測試 16 項照樣全過。

do $$
declare
  I1 uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  I2 uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  S1 uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  r        jsonb;
  n        int;
  txt      text;
begin
  ------------------------------------------------------------------
  -- 1. 正常一批：五種事件都收得下
  ------------------------------------------------------------------
  r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'session_start', 's', 0,
          'p', jsonb_build_object('chapter', 'c1', 'level', 7, 'ng', 0)),
        jsonb_build_object('n', 'chapter_enter', 's', 12,
          'p', jsonb_build_object('chapter', 'c2', 'level', 9)),
        jsonb_build_object('n', 'battle_end', 's', 300,
          'p', jsonb_build_object('mode', 'leo', 'boss', true, 'won', false,
                                  'dur', 45, 'level', 9, 'place', 'town')),
        jsonb_build_object('n', 'tutorial_step', 's', 5,
          'p', jsonb_build_object('step', 'battle_parry')),
        jsonb_build_object('n', 'session_tick', 's', 600,
          'p', jsonb_build_object('sec', 600))
      ));
  if (r->>'ok')::boolean is not true or (r->>'accepted')::int <> 5 then
    raise exception 'TELEMETRY_SQL_FAIL 1: 正常一批應收 5 筆，得到 %', r;
  end if;
  raise notice '  ok 1  五種事件正常收下';

  ------------------------------------------------------------------
  -- 2. 不認得的事件名靜靜丟掉，不讓舊版客戶端整批失敗
  ------------------------------------------------------------------
  r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'player_clicked_everything', 's', 1, 'p', '{}'::jsonb),
        jsonb_build_object('n', 'session_tick', 's', 900, 'p', jsonb_build_object('sec', 900))
      ));
  if (r->>'ok')::boolean is not true or (r->>'accepted')::int <> 1 or (r->>'dropped')::int <> 1 then
    raise exception 'TELEMETRY_SQL_FAIL 2: 應收 1 丟 1，得到 %', r;
  end if;
  select count(*) into n from public.telemetry_events
    where name = 'player_clicked_everything';
  if n <> 0 then
    raise exception 'TELEMETRY_SQL_FAIL 2: 白名單外的事件被寫進去了';
  end if;
  raise notice '  ok 2  白名單外的事件被丟掉，整批仍然成功';

  ------------------------------------------------------------------
  -- 3. 自由文字進不來：這是隱私承諾的實作，不是禮貌
  ------------------------------------------------------------------
  -- 洗掉的理由有兩個，要分開驗，不然只驗得到其中一個：
  --   (a) key 不在白名單上
  --   (b) 值不是 a-z0-9_ 的短 token
  -- 原本這一段的壞欄位剛好每個都同時踩到 (b)，所以整條 key 白名單被拿掉
  -- 也不會紅（變異測試證實過）。uid／player 這兩個是專門來測 (a) 的：
  -- 格式完全合法，純粹因為不在白名單上才該被丟掉。
  r := public.telemetry_ingest(I2, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'battle_end', 's', 10, 'p', jsonb_build_object(
          'mode', 'demon',
          'won', true,
          'uid', 'a1b2c3d4',                            -- 白名單外，但格式合法
          'player', 'kevin_chu',                        -- 白名單外，但格式合法
          'seed', 42,                                   -- 白名單外的數字
          'display_name', '小白',                       -- 白名單外的 key
          'email', 'someone@example.com',               -- 白名單外的 key
          'place', 'C:\Users\kevin\save.json',          -- 白名單內但格式不合
          'step', '玩家自己打的一句話'                  -- 白名單內但不是 token
        ))
      ));
  if (r->>'accepted')::int <> 1 then
    raise exception 'TELEMETRY_SQL_FAIL 3: 這批應該收下，得到 %', r;
  end if;
  select props::text into txt from public.telemetry_events
    where install_id = I2 order by id desc limit 1;
  if txt like '%display_name%' or txt like '%example.com%'
     or txt like '%kevin%' or txt like '%玩家自己%' then
    raise exception 'TELEMETRY_SQL_FAIL 3: 自由文字被存下來了：%', txt;
  end if;
  if txt like '%uid%' or txt like '%player%' or txt like '%seed%' then
    raise exception 'TELEMETRY_SQL_FAIL 3: 白名單外的欄位只因為格式合法就被存下來了：%', txt;
  end if;
  if txt not like '%demon%' then
    raise exception 'TELEMETRY_SQL_FAIL 3: 該留的 mode 被洗掉了：%', txt;
  end if;
  raise notice '  ok 3  白名單外的 key（含格式合法的）與非 token 字串全被洗掉，該留的留下';

  ------------------------------------------------------------------
  -- 4. session_sec 亂給不會壞，也不會存進離譜的數字
  ------------------------------------------------------------------
  r := public.telemetry_ingest(I2, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'session_tick', 's', 'not a number', 'p', '{}'::jsonb),
        jsonb_build_object('n', 'session_tick', 's', 9999999, 'p', '{}'::jsonb)
      ));
  if (r->>'accepted')::int <> 2 then
    raise exception 'TELEMETRY_SQL_FAIL 4: 應收 2 筆，得到 %', r;
  end if;
  select max(session_sec) into n from public.telemetry_events where install_id = I2;
  if n > 86400 then
    raise exception 'TELEMETRY_SQL_FAIL 4: session_sec 沒有封頂，實際 %', n;
  end if;
  raise notice '  ok 4  秒數亂給會被歸零／封頂，不會讓整批爆掉';

  ------------------------------------------------------------------
  -- 5. 版本字串也是客戶端給的，只留得出來的字元
  ------------------------------------------------------------------
  r := public.telemetry_ingest(I2, S1, '0.15.0<script>並附上一段很長很長的東西',
        jsonb_build_array(jsonb_build_object('n', 'session_start', 's', 0, 'p', '{}'::jsonb)));
  select app_version into txt from public.telemetry_events
    where install_id = I2 order by id desc limit 1;
  if txt !~ '^[a-z0-9._-]{0,16}$' then
    raise exception 'TELEMETRY_SQL_FAIL 5: 版本字串沒有洗乾淨：%', txt;
  end if;
  raise notice '  ok 5  版本字串只留 % 這樣的內容', txt;

  ------------------------------------------------------------------
  -- 6. 單次呼叫筆數上限
  ------------------------------------------------------------------
  select jsonb_agg(jsonb_build_object('n', 'session_tick', 's', 1, 'p', '{}'::jsonb))
    into r from generate_series(1, 60);
  r := public.telemetry_ingest(I2, S1, '0.14.9', r);
  if r->>'error' is distinct from 'batch too large' then
    raise exception 'TELEMETRY_SQL_FAIL 6: 60 筆一次應被擋下，得到 %', r;
  end if;
  raise notice '  ok 6  單次呼叫筆數超過上限被擋下';

  ------------------------------------------------------------------
  -- 7. 個人每小時上限：灌不進去
  ------------------------------------------------------------------
  update public.telemetry_config set events_per_hour = 12 where id = 1;
  delete from public.telemetry_quota where install_id = I1;
  for n in 1..4 loop
    r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(
          jsonb_build_object('n', 'session_tick', 's', 1, 'p', '{}'::jsonb),
          jsonb_build_object('n', 'session_tick', 's', 2, 'p', '{}'::jsonb),
          jsonb_build_object('n', 'session_tick', 's', 3, 'p', '{}'::jsonb),
          jsonb_build_object('n', 'session_tick', 's', 4, 'p', '{}'::jsonb),
          jsonb_build_object('n', 'session_tick', 's', 5, 'p', '{}'::jsonb)
        ));
  end loop;
  if r->>'error' is distinct from 'telemetry rate limit' then
    raise exception 'TELEMETRY_SQL_FAIL 7: 連灌 20 筆應撞上限（限 12），得到 %', r;
  end if;
  select events_in_window into n from public.telemetry_quota where install_id = I1;
  if n > 12 then
    raise exception 'TELEMETRY_SQL_FAIL 7: 窗內收了 % 筆，超過上限 12', n;
  end if;
  raise notice '  ok 7  個人每小時上限擋得住連灌（窗內 % 筆）', n;

  ------------------------------------------------------------------
  -- 8. 過了一小時，額度自己重來
  ------------------------------------------------------------------
  update public.telemetry_quota set window_start = now() - interval '2 hours'
    where install_id = I1;
  r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'session_tick', 's', 1, 'p', '{}'::jsonb)));
  if (r->>'ok')::boolean is not true then
    raise exception 'TELEMETRY_SQL_FAIL 8: 換窗之後應該又收得下，得到 %', r;
  end if;
  update public.telemetry_config set events_per_hour = 600 where id = 1;
  raise notice '  ok 8  換窗之後額度重來';

  ------------------------------------------------------------------
  -- 9. 全站閘門：換 install_id 也繞不過去
  ------------------------------------------------------------------
  update public.telemetry_config set global_events_per_hour = 1 where id = 1;
  update public.telemetry_gate set window_start = now(), events_in_window = 1 where id = 1;
  r := public.telemetry_ingest(gen_random_uuid(), S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'session_tick', 's', 1, 'p', '{}'::jsonb)));
  if r->>'error' is distinct from 'telemetry busy' then
    raise exception 'TELEMETRY_SQL_FAIL 9: 全站上限應擋下沒見過的 install，得到 %', r;
  end if;
  update public.telemetry_config set global_events_per_hour = 500000 where id = 1;
  update public.telemetry_gate set events_in_window = 0 where id = 1;
  raise notice '  ok 9  全站上限擋得住換 install_id 的分散灌入';

  ------------------------------------------------------------------
  -- 10. 人工停權
  ------------------------------------------------------------------
  update public.telemetry_quota set blocked = true where install_id = I1;
  r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(
        jsonb_build_object('n', 'session_tick', 's', 1, 'p', '{}'::jsonb)));
  if r->>'error' is distinct from 'telemetry blocked' then
    raise exception 'TELEMETRY_SQL_FAIL 10: 停權後不該收，得到 %', r;
  end if;
  update public.telemetry_quota set blocked = false where install_id = I1;
  raise notice '  ok 10  停權後整個 install 收不進來';

  ------------------------------------------------------------------
  -- 11. 亂七八糟的輸入不會讓函式炸掉
  ------------------------------------------------------------------
  r := public.telemetry_ingest(I1, S1, null, '"不是陣列"'::jsonb);
  if r->>'error' is distinct from 'bad batch' then
    raise exception 'TELEMETRY_SQL_FAIL 11: 非陣列應回 bad batch，得到 %', r;
  end if;
  r := public.telemetry_ingest(null, S1, '0.14.9', '[]'::jsonb);
  if r->>'error' is distinct from 'bad batch' then
    raise exception 'TELEMETRY_SQL_FAIL 11: 缺 install 應回 bad batch，得到 %', r;
  end if;
  r := public.telemetry_ingest(I1, S1, '0.14.9', '[]'::jsonb);
  if (r->>'ok')::boolean is not true then
    raise exception 'TELEMETRY_SQL_FAIL 11: 空陣列應該安靜地成功，得到 %', r;
  end if;
  r := public.telemetry_ingest(I1, S1, '0.14.9', jsonb_build_array(to_jsonb('不是物件'::text), to_jsonb(3)));
  if (r->>'ok')::boolean is not true or (r->>'accepted')::int <> 0 then
    raise exception 'TELEMETRY_SQL_FAIL 11: 陣列裡不是物件應被丟掉，得到 %', r;
  end if;
  raise notice '  ok 11  壞輸入一律回錯誤或丟掉，函式不會炸';

  ------------------------------------------------------------------
  -- 12. 事件不綁帳號：外鍵接不上去才是隱私承諾
  ------------------------------------------------------------------
  select count(*) into n
    from information_schema.constraint_column_usage cu
    join information_schema.table_constraints tc
      on tc.constraint_name = cu.constraint_name
    where tc.table_name = 'telemetry_events' and tc.constraint_type = 'FOREIGN KEY';
  if n <> 0 then
    raise exception 'TELEMETRY_SQL_FAIL 12: 事件表有 % 個外鍵，不該跟任何身分資料接起來', n;
  end if;
  raise notice '  ok 12  事件表沒有任何外鍵，接不到帳號';

  ------------------------------------------------------------------
  -- 13. 過期資料清得掉
  ------------------------------------------------------------------
  update public.telemetry_events set created_at = now() - interval '400 days'
    where install_id = I2;
  select public.telemetry_prune(365) into n;
  select count(*) into n from public.telemetry_events where install_id = I2;
  if n <> 0 then
    raise exception 'TELEMETRY_SQL_FAIL 13: 過期資料沒清掉，還剩 %', n;
  end if;
  raise notice '  ok 13  過期資料清得掉';

  ------------------------------------------------------------------
  -- 14. 視圖跑得動（真的拿來看數字的那幾張）
  ------------------------------------------------------------------
  perform count(*) from public.telemetry_chapter_funnel;
  perform count(*) from public.telemetry_boss_wall;
  perform count(*) from public.telemetry_death_spots;
  perform count(*) from public.telemetry_tutorial_funnel;
  perform count(*) from public.telemetry_session_len;
  select count(*) into n from public.telemetry_death_spots where place = 'town';
  if n <> 1 then
    raise exception 'TELEMETRY_SQL_FAIL 14: 死亡熱點沒有算到 town，得到 %', n;
  end if;
  raise notice '  ok 14  五張視圖都跑得動，死亡熱點算得出地點';
end $$;


-- ── 曝險面：沒登入的人只能送，不能讀 ──
do $$
declare
  blocked int := 0;
  r jsonb;
begin
  -- 匿名回報必須送得進去，否則等於只收到有帳號的那群人
  set local role anon;
  r := public.telemetry_ingest(
        'cccccccc-0000-0000-0000-000000000001'::uuid,
        'cccccccc-0000-0000-0000-000000000002'::uuid,
        '0.14.9',
        jsonb_build_array(jsonb_build_object('n', 'session_start', 's', 0, 'p', '{}'::jsonb)));
  reset role;
  if (r->>'ok')::boolean is not true then
    raise exception 'TELEMETRY_SQL_FAIL 15: 未登入者應該送得進去，得到 %', r;
  end if;
  raise notice '  ok 15  未登入者送得進去（匿名回報本來就該收）';

  set local role anon;
  begin
    perform count(*) from public.telemetry_events;
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 未登入者讀得到事件表';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role authenticated;
  begin
    perform count(*) from public.telemetry_events;
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 登入者讀得到事件表';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role authenticated;
  begin
    insert into public.telemetry_events (install_id, session_id, name)
      values (gen_random_uuid(), gen_random_uuid(), 'session_start');
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 登入者繞過 RPC 直接寫得進事件表';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  -- 視圖也不能開，開了等於事件表開了
  set local role authenticated;
  begin
    perform count(*) from public.telemetry_boss_wall;
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 登入者讀得到統計視圖';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  -- 清理與清洗是內部工具，不該被當 API 呼叫
  set local role authenticated;
  begin
    perform public.telemetry_prune(1);
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 登入者呼叫得到清理函式';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  set local role anon;
  begin
    perform public.telemetry_clean_props('{}'::jsonb);
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 未登入者呼叫得到欄位清洗函式';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  -- 參數表也不該讓玩家讀（讀得到就知道上限在哪）
  set local role anon;
  begin
    perform count(*) from public.telemetry_config;
    reset role;
    raise exception 'TELEMETRY_SQL_FAIL 16: 未登入者讀得到參數表';
  exception when insufficient_privilege then
    blocked := blocked + 1;
  when others then
    if sqlerrm like 'TELEMETRY_SQL_FAIL%' then raise; end if;
    blocked := blocked + 1;
  end;

  reset role;
  if blocked <> 7 then
    raise exception 'TELEMETRY_SQL_FAIL 16: 只擋下 % 條側門，應為 7', blocked;
  end if;
  raise notice '  ok 16  讀取／直寫／視圖／內部函式／參數表七條側門全部堵死';
  raise notice '';
  raise notice 'TELEMETRY_SQL_OK';
end $$;
