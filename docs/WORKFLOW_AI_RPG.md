# AI × Godot RPG 工作流（Brave Soul 適配）

對照影片：[新手的第一個 AI x RPG 實作指南](https://www.youtube.com/watch?v=jHNoc3Vhex0)（臭臭虎）  
本專案已在 Godot 4.7 上路，下列是**可直接套用**的 checklist，不是從頭教學。

## 1. 契約（CLAUDE.md / AGENTS.md）

- [x] 專案根有 `CLAUDE.md` + `AGENTS.md`
- [ ] 大改前先問範圍（存檔／付費圖／公開文案）
- [ ] 交付以「跑起來＋測試哨兵」為準

## 2. 美術（對齊 itch 選材＋風格鎖）

| 做 | 不做 |
|----|------|
| 同一批 chibi／色票；`$asset-gen` 帶參考圖 | 無提示混寫實／暗黑／Q 版 |
| 產出進 `game/assets/` | 把生成暫存／參考圖塞進 runtime |
| 新 props 優先可在編輯器擺 | 只為了快全部 `ColorRect` |

**地圖：** 新區域優先 Godot 場景／TileMap 可預覽；`map_catalog.gd` 負責資料與出口 id，`main.gd` 必須有對應 handler。

## 3. Git

- 玩法一小段一 commit；`[ADD]/[FIX]`/`[IMP]` 標籤見 Kevin 慣例
- 大圖／音訊用 LFS 或保持目錄乾淨；勿把 API key 寫進 repo

## 4. 系統塊（影片 15:29 對照本專案）

| 影片項 | 本專案位置 |
|--------|------------|
| NPC／對話 | `npc_lines.gd`、`dialogues/`、`main.gd` |
| 存檔 | `SaveManager` + `save_migration`（現 VERSION 6） |
| 場景切換 | `ExploreView` + `map_catalog` + `_open_explore` |
| 音樂 | `AudioManager` + `assets/audio/bgm/` |

## 5. 音樂（Suno／自產皆可）

- 地區曲放 `bgm/<id>.wav`，id 對 `map_to_bgm`
- 循環點：`bgm/loops.json`（`tools/import_bgm.py`）
- 戰鬥用 `battle`／`boss`；結束回探索會再 `play_bgm_for_map`
- **聽感檢查：** 同圖進出選單不應重頭播；戰後音量要拉回（見 `play_bgm` 同曲還原）

## 6. AI 擅長／不擅長（影片回顧）

| 擅長 | 不擅長 → 人要盯 |
|------|------------------|
| 重複樣板、測試、遷移腳本 | 手感調參、風格最終裁決 |
| 依考據補機制 | 默默發明第二套經濟 |
| 重整文件 | 長篇空話文案 |

## 7. 地圖場景（編輯器可預覽）

```bash
# 新圖骨架
python3 tools/scaffold_map_scene.py coast
# Godot 開啟 game/scenes/maps/coast.tscn 擺 Decor／Markers
```

- 登錄：`map_scene_registry.gd` 或慣例 `scenes/maps/<map_id>.tscn`
- 執行期：`ExploreView` 自動掛上；**互動／碰撞仍以 `map_catalog.gd` 為準**
- 已附：`village`／`town`／`mist_village`

## 8. 本輪已套用

- 強化 `CLAUDE.md`／`AGENTS.md` 契約
- BGM：同曲戰後壓低音量會自動拉回；`bake_placeholder_bgm.py` 真曲槽位
- 地圖：可預覽 `.tscn`＋scaffold
- 過期教學字對齊現行別名
