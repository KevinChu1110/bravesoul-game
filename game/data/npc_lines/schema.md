# NPC 台詞資料 Schema（NpcLines）

路徑：`res://data/npc_lines/<npc_id>.json`，**檔名即 npc id**。

加新 NPC 或改台詞**不需要動程式**：丟一個 JSON 進來，再在
`scripts/systems/test_npc_lines.gd` 的 `NPCS` 加上 id 讓測試涵蓋到即可。
遊戲端用 `NpcLines.for_npc("<id>")` 取台詞。

## 檔案結構

```json
{
  "id": "greybeard",
  "speaker": "灰鬚",
  "rules": [
    { "when": { "ng_plus_min": 1, "flags": ["boss.leo_cleared"] },
      "lines": ["又一次。……", "迴響裡的獅子更躁。格擋別鬆。"] },
    { "when": { "flags": ["c1_forged"] },
      "lines": ["刃有了。……"] },
    { "when": {}, "lines": ["聖獅在內殿。……"] }
  ]
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `id` | string | 與檔名相同 |
| `speaker` | string | 顯示的說話者名。**一個 NPC 只有一個** |
| `rules` | object[] | 由上而下比對，**第一個成立的就用** |

## rules[].when

**空物件 `{}` = 永遠成立**，用來當最後的預設規則。

| 欄位 | 型別 | 說明 |
|------|------|------|
| `flags` | string[] | 這些 flag **全部**要成立（AND） |
| `ng_plus_min` | int | `GameState.ng_plus` 要 ≥ 這個值 |

目前只支援 AND，沒有 OR / NOT。真的需要時再擴充 `_matches()`，
**不要在 JSON 裡塞表達式字串** —— 那等於把程式碼搬進資料，失去資料化的意義。

## 順序很重要

規則是由上而下、第一個成立就採用，所以**條件愈嚴格的要放愈前面**。
例如 `{ng_plus_min: 1, flags: [A]}` 必須排在 `{flags: [A]}` 前面，
否則永遠輪不到它。

## 沒有台詞是合法的

`"lines": []` 表示這個狀態下 NPC 不出聲（例如麥穗在村裡走主線對話、
星讀還沒解鎖觀星）。這種 NPC 要加進 `test_npc_lines.gd` 的 `MAY_BE_SILENT`，
否則「全新開局下每個 NPC 都要講得出話」那條檢查會擋下來。

若所有規則都不成立，`for_npc()` 一樣回空陣列。

## 這批資料怎麼來的

原本硬編碼在 `scripts/systems/npc_lines.gd`，用 `tools/migrate_npc_lines.py`
機器轉換（含 round-trip 驗證），再以 344 種狀態 × 10 個 NPC 共 3440 組
新舊對拍確認行為完全一致後才切換。詳見該次 commit。
