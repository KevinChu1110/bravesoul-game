# 星途足跡 · 殘影與留言石（0.17.2）

> 目標：打開地圖就感覺「世界裡有別人」——貼齊 FB 網頁遊戲的社會證明，不必真 MMO。

## 殘影

- 探索開圖自動 `fetch_presence`；已登入會 `push_presence`
- 雲端空／離線：據點圖補 3～5 個半透明「假旅人」剪影
- 位置壓在站立帶（不飄屋頂）

據點圖：村、堡、演武場、霧隱、塔下、岔路、驛站等。

## 留言石

| 地圖 | place id |
|------|----------|
| 翠谷村 | `village_well` |
| 騎士堡／演武場 | `town_gate` |
| 霧隱 | `mist_gate` |
| 荒路留言板 | `road_inn` |
| 塔下 | `tower_camp` |

- **上線**：讀寫雲端 `messages`，並備份本地
- **離線**：仍可留〔本地〕足跡＋舊刻文；引導連線設定

## 入口

- 地圖上靠近留言石按 E
- 今日星途 →「留言石（足跡）」

## 通關蠟燭人數（常駐）

- `OnlineGate.fetch_candle_total` 讀 `candles.total`（可不登入）
- 快取：`candle_total` + `meta.candle_total_cache`
- 顯示：標題畫面、今日星途、HUD tip、塔下蠟燭壇

## 帳號登入

- 訪客 Anonymous、Email／密碼
- **OAuth**：Google／Discord／Facebook／X（本機 `127.0.0.1:8765/callback`）
- 設定步驟見 [ONLINE_SETUP.md](ONLINE_SETUP.md) §2.6
- Steam／LINE 尚未內建
