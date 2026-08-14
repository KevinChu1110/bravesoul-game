# 連線後端接線（Supabase）

## 1. 建專案

1. 到 [Supabase](https://supabase.com) 建專案  
2. SQL Editor 執行 repo 內 `supabase/schema.sql`  
3. 複製 **Project URL** 與 **anon public** key  

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
4. **市集**：上架溢皮 → 另一帳（或第二裝置）刷新購買 → 賣家「領取貨款」  
5. **裂縫房**：通關後建房 → 第二人加入 → 房主開戰 → 回報勝利 → 成員領共鬥獎  
6. **狩獵房**：獵場 → 狩獵房 → 建房 → 隊友加入 → 房主共獵 3 波 → 成員領共獵獎  
7. **同屏觀戰／操作**：房主開戰後，成員點「同屏操作」  
   - 看到血量同步；**J** 格擋／連招、**K** 戰意、**L** 助攻  
   - 綠窗時雙方 J → **雙星連招**  
   - 請再跑一次 `schema.sql`（含 `room_events` + **`room_inputs`**）  
   - Publications：`room_events` 進 `supabase_realtime`（可選）

## 4. 安全

- 只用 **anon** key + RLS（schema 已寫）  
- **service_role** 永不進客戶端  
- itch 包體不內建 key；玩家可選填或你用私有渠道發  
