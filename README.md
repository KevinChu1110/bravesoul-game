# 翠嶺·兔勇者（暫定）

> 工作名：`bravesoul-game`  
> 類型：像素 2D · 敘事為主 · 即時自動戰鬥 · 可連線  
> 時程目標：3 個月可通關短篇 · 6 個月可公開完整作品  
> 與舊作關係：延續《勇者之魂》Discord bot（`../bravesoul`）的**世界觀與美術精神**，架構全新建（A）

## 一句話

在**翠嶺大陸**上，一隻不慕強權的兔子，走過六域、對話眾生、以即時戰鬥通過聖獸試煉，並在可選的連線世界裡與他人交會——但**主線永遠單人可完整體驗**。

## 已定案

| 項目 | 決定 |
|------|------|
| 產品重心 | 故事 / 世界 / NPC ＞ 系統堆疊 |
| 連線 | **可連線但故事為主**（見 `docs/ONLINE.md`） |
| 世界觀 | **延續翠嶺／兔勇者／五聖獸／黑焰／法師之塔** |
| 戰鬥 | **即時動畫手感**（雜魚即時自動；BOSS 策略互動） |
| 舊 bot | 只讀參考，不 import、不共用 runtime |
| 重做策略 | 全新建（A）：戰鬥驅動＋場景敘事管線全新；舊數值當靈感 |

## 文件地圖

**從 [docs/GDD.md](docs/GDD.md) 進入。**

| 文件 | 內容 |
|------|------|
| [docs/GDD.md](docs/GDD.md) | **設計總索引** |
| [docs/VISION.md](docs/VISION.md) | 願景、體驗承諾、不做清單 |
| [docs/SCOPE.md](docs/SCOPE.md) | 3 個月 / 6 個月 / 砍掉 |
| [docs/WORLD.md](docs/WORLD.md) | 世界觀、六域、勢力、黑焰規則 |
| [docs/STORY_BIBLE.md](docs/STORY_BIBLE.md) | 主線節拍、章節、結局 |
| [docs/NPC.md](docs/NPC.md) | NPC 表、階段台詞、支線掛點 |
| [docs/SYSTEMS.md](docs/SYSTEMS.md) | 系統總覽 |
| [docs/PROGRESSION.md](docs/PROGRESSION.md) | **器／魂／招三重養成** |
| [docs/COMBAT.md](docs/COMBAT.md) | **即時戰鬥規格** |
| [docs/BALANCE.md](docs/BALANCE.md) | 數值起點 |
| [docs/SCRIPT_C0.md](docs/SCRIPT_C0.md) | 序章對白稿 |
| [docs/SCRIPT_C1.md](docs/SCRIPT_C1.md) | 騎士域＋雷歐劇本 |
| [docs/SCRIPT_C6.md](docs/SCRIPT_C6.md) | 塔＋魔王＋終章 |
| [docs/UI.md](docs/UI.md) | 介面與用詞 |
| [docs/ONLINE.md](docs/ONLINE.md) | 連線分層 |
| [docs/MULTIPLAYER_LOOPS.md](docs/MULTIPLAYER_LOOPS.md) | 狩獵場／市集／組隊 Boss |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 半年節奏 |
| [docs/TECH.md](docs/TECH.md) | 技術選型 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 決策紀錄 |
| [docs/DESIGN_CRITIQUE.md](docs/DESIGN_CRITIQUE.md) | 外部建議評析 R1 |
| [docs/DESIGN_CRITIQUE_R2.md](docs/DESIGN_CRITIQUE_R2.md) | 外部建議評析 R2 |
| [docs/SHARE.md](docs/SHARE.md) | 高光／成就／發行 |
| [docs/SCRIPT_C2.md](docs/SCRIPT_C2.md) | 忍者村＋延遲的信 |
| [docs/BOSS_KITS.md](docs/BOSS_KITS.md) | 翠嶺四王機制 |
| [docs/MECHANIC_LIBRARY.md](docs/MECHANIC_LIBRARY.md) | Artale 機制庫（未來 Boss／活動） |
| [docs/CHAPTER_C4_C5.md](docs/CHAPTER_C4_C5.md) | C4 疾影／C5 石拳 |
| [docs/POSTGAME_AND_EVENTS.md](docs/POSTGAME_AND_EVENTS.md) | 通關後／週裂縫 |
| [docs/ART_2D.md](docs/ART_2D.md) | 2D 表現方向 |

舊作參考（唯讀）：`../bravesoul/`（見 `design/references/`）。

## 目前狀態

- [x] 專案開箱、願景與範圍定案  
- [x] **核心設計文件寫齊**  
- [x] **Godot 4.7 可玩主線**（`game/`）— **C0～C6 可通關**  
- [x] 探索密度／支線／BGM／半身像／稱號／裂縫／NG+  
- [x] **0.8.x**：現代 UI · 戰鬥提示 · 每日／任務 · 離線公會 · 大地圖 · **小地圖** · 一周目／二周目  
- [x] **0.9.0 廣域世界**：約 **45** 張可走分區 · 秘境（星落／行商／黑焰疤）· **31** 張 Gemini 子域底圖  
- [x] **0.9.1 世界內容包**：16 寶箱 · 雜魚遭遇 · 3 秘境 Boss · 新任務／稱號 · Boss 立繪 · 地標 banner · 行商半身像  
- [x] **0.9.2**：雜魚專用立繪 ×8 · 秘境專屬魂器 ×3 · **楓之谷風小 UI**（左上狀態板／木框選單／對話底欄）  
- [x] **0.9.3**：快捷欄 1–8 · 物品欄格子 · 聊天泡泡 · 道具掉落／商店  
- [x] **0.9.4～0.9.5**：歲旅活動全年 12 月 · 日曆循環 · 三件事 · 收攤換幣 · 歲旅石 · 活動稱號  
- [x] **0.9.6**：多人設計 `docs/ONLINE.md` · `OnlineGate` · Supabase schema · 純單機開關  
- [x] **0.9.7**：星途殘影 · 留言石 · 通關蠟燭  
- [x] **0.9.8**：星途獵場（3 波／日 cap 5／練習）· 溢皮／焰骨／溢核 · 溢物回收 · `MULTIPLAYER_LOOPS.md`  
- [x] **0.9.9**：獵場專用地圖／banner · 星途助戰（離線組隊）· rooms SQL 骨架  
- [x] **0.10.0**：真市集（掛單／買／貨款）· 真裂縫房（建房／加入／房主戰／共鬥獎）  
- [x] **0.10.1**：狩獵多人房 · 單人獵可帶助戰 · 房代碼顯示強化  
- [x] **0.10.2**：Realtime 同屏觀戰（房主轉播 HP／招式 · 成員觀戰 · WS＋輪詢）  
- [x] **0.10.3**：成員同屏操作 · 雙星連招 · room_inputs 輸入分攤  
- [x] **0.10.4**：網路容錯格擋 · 連招窗加速拉輸入 · 代碼加入 UI · 雙星合拍任務  
- [x] **0.11.0～0.11.1**：帳號／裝備浮動／倉庫／Log／爆擊 · 連線健康檢查 · 雙星手感 · 官網 Pages  
- [x] **0.11.2 內容密度**：鐵匠舊債 · 霧中家書 · 浪人分岔 · 絲絨典籍 · 支線任務／稱號 · 氛圍台詞加厚  
- [x] **0.11.0**：帳號密碼 · 官網 · 資料表 · 裝備浮動 · 倉庫 · 冒險日誌 · 傷害浮動／爆擊  
- [x] **0.11.1**：連線健康檢查 UI · 中文錯誤 · 後端金鑰表單 · 雙星連招倒數／音效回饋  
- [x] **Godogen 工作流**（`AGENTS.md` · `godot.md` · `.agents/skills/asset-gen` · `tools/proof_run.sh`）  
- [x] itch 出貨腳本與文案（`tools/export_itch.sh` · `release/ITCH_PAGE.md`）  
- [ ] 連線公會／雲存檔實測（需真實 Supabase）  
- [ ] 分區內支線密度／秘境戰鬥再加厚

### 執行遊戲

```bash
cd game && godot .
# Godogen 證明閘門
./tools/proof_run.sh
```

### 官網（GitHub Pages）

靜態站在 [`web/`](web/)。推上 GitHub 後：

1. **Settings → Pages → Source: GitHub Actions**
2. 推送 `main`（或手動跑 Actions：**Deploy GitHub Pages**）
3. 網址約：`https://你的帳號.github.io/bravesoul-game/`

詳見 [`web/README.md`](web/README.md)。Workflow：`.github/workflows/github-pages.yml`。

### 資源表（執行期 · `game/assets/`）

| Name | Description | Size | Path | Cost |
|------|-------------|------|------|------|
| 主域底圖 ×9 | 村／城／路／野／霧／道／林／海／塔 | 1280×720 | `sprites/maps/*_bg.png` | ~63¢ |
| 子域底圖 ×31 | 風車田、市集、下水道、樹冠、鏡廊、塔階… | 1280×720 | `sprites/maps/*_bg.png` | ~217¢ |
| 星途獵場底圖＋banner | 溢地獵場 | 1280×720／960×220 | `sprites/maps/hunting_grounds_*` | Imagine |
| 秘境 Boss ×3 | 疤主／鏡影／船長 | 220×240 | `sprites/bosses/` | ~21¢ |
| 地標 banner ×7 | 村路野／行商／星落／疤地／岔路 | 960×220 | `sprites/maps/*_banner.png` | ~49¢ |
| 半身像 ×4 | 行商＋三 Boss | 384×480 | `sprites/portraits/` | ~28¢ |
| portraits | 既有 NPC 半身像 | 384×480 | `sprites/portraits/` | — |
| BGM | 地區循環曲 | wav | `audio/bgm/` | — |
| tiles | 地磚 atlas | 32px | `sprites/tiles/` | — |

底圖：`tools/gen_world_maps.py` · 內容美術：`tools/gen_world_content_art.py`  
舊底圖備份：`sprites/maps/_backup_20260813/`

## 原則（貼在牆上）

1. **主線離線也能通關**；連線只加厚，不鎖劇情。  
2. **每個系統要服務某個 NPC 或某段故事**，否則進 backlog 或砍。  
3. **戰鬥時間模型前 4 週鎖版**，之後只調數值不改節奏。  
4. **完整 ≠ 功能最多**；完整 = 故事閉環 + 世界自洽 + 手感穩定。
