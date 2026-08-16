# 連線後端接線（Supabase）

## 1. 建專案

1. 到 [Supabase](https://supabase.com) 建專案  
2. SQL Editor 執行 repo 內 `supabase/schema.sql`  
3. SQL Editor 再執行 `supabase/economy.sql`（經濟守門，**順序不能顛倒**）  
4. 複製 **Project URL** 與 **anon public** key  

> 兩個檔都可以重複執行。但 `schema.sql` 會把 `economy.sql` 移除的舊寫入權限加回來，
> 所以每次重跑 `schema.sql` 之後都要接著再跑一次 `economy.sql`。

## 2. 本機設定（勿 commit key）

```bash
# 複製範例
cp game/data/online/config.example.json \
   "$HOME/Library/Application Support/Godot/app_userdata/勇者之魂/online_settings.json"
   （舊版若叫「翠嶺·兔勇者」資料夾，請手動搬移或重新設定）
```

或遊戲內：**標題 → 連線設定** 貼上 URL／anon key，關閉「純單機」。

`user://online_settings.json` 欄位：

```json
{
  "offline_only": false,
  "display_name": "星途旅人",
  "supabase_url": "https://xxxx.supabase.co",
  "supabase_anon_key": "eyJ..."
}
```

## 2.5 Email 帳號

Dashboard → Authentication → Providers → **Email** 開啟。  
遊戲內：連線／帳號 → Email 註冊／登入（密碼 ≥6）。

## 3. 驗證

1. 關純單機 → 訪客上線（應顯示 user id 前八碼）  
1b. Email 註冊 → 登入 → 推送雲存檔  
2. 推送雲存檔 → 拉回雲存檔  
3. 上傳殘影 → 狀態列有 last error 為空  
4. 留言石：塔下或城門留一句 → 換帳號看得到  
5. 通關蠟燭：通關後點祭壇 → 總數 +1

市集與房間的驗證步驟已刪除 —— 那幾套在 2026-08-16 隨系統一起砍掉
（見 [DECISIONS.md](DECISIONS.md)）。SQL 裡的表還在，只是沒有客戶端會用。

## 4. 安全

- 只用 **anon** key + RLS（schema 已寫）  
- **service_role** 永不進客戶端  
- itch 包體不內建 key；玩家可選填或你用私有渠道發

### 4.1 經濟守門（`economy.sql`）

單機模擬的遊戲，伺服器驗不出「這 300 金是不是真的打贏怪拿的」。所以不假裝驗得出來，
改成分兩本帳：

| 帳 | 內容 | 誰能寫 |
|----|------|--------|
| `saves.payload` | 玩家自己的存檔 | 玩家（經 `save_push`） |
| `player_econ` | **可拿去跟別人交易**的金幣與物品 | 只有伺服器 |

影子帳往下精確跟隨存檔（花掉就是花掉），往上只能按真實時間長：金幣每秒 60、
物品全品項合計每小時 120 個，額度會結轉但有封頂。

結論：改客戶端最多把自己的存檔改壞，沒辦法對別人的經濟灌水。

參數在 `public.econ_config` 單列表，直接改欄位即可調鬆緊。

**驗證**：`bash tools/test_economy_sql.sh` 會在本機起一個丟完即棄的 PostgreSQL，
跑完 schema + economy，再演 21 種作弊情境。改過 SQL 一定要跑這支。

**巡查**：

```sql
select * from public.econ_audit order by created_at desc limit 50;
select user_id, gold, strikes from public.player_econ order by strikes desc limit 20;
```

`strikes` 是「存檔報的數字被影子帳削掉」的次數。正常玩家偶爾會有（長時間離線後
第一次上線），持續累積才值得看。確認濫用後手動停權：

```sql
update public.player_econ set blocked = true where user_id = '...';
```

### 4.2 升級注意

`economy.sql` 跑完之後，**0.14.9 以前的客戶端會連不上雲存檔**——它們直接寫表，
現在會被擋成 42501。伺服器與客戶端要同版更新。  
