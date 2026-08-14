# 勇者之魂 · Agent 執行憲章（Godogen 適配）

本專案用 **Godot 4.7 + GDScript**（非 Godogen 預設的 C# 綠地專案）。  
Godogen 流程仍適用：**用「跑起來的畫面」證明進度，不要只信編譯通過。**

- 狀態寫在 `README.md`（已完成／未完成／資源表）。
- 產美術用 `$asset-gen`（`.agents/skills/asset-gen/`）。**付費 API 先問使用者。**
- 引擎注意事項見 `godot.md`。
- 遊戲本體在 `game/`。

## 交付方式

從**正在跑的遊戲**判斷進度，不是從 clean build：

1. `godot --path game --headless --import`（資源變更後）
2. `godot --path game --headless --quit-after 3`（無 SCRIPT ERROR）
3. 有證明需求時跑 `./tools/proof_run.sh` 產截圖／短片到 `screenshots/`

任務偏探索就常 checkpoint；任務偏規格就穩步做完，最後用畫面證明。

## 本專案硬規則

- 主線必須**單機可通關**；連線／雲端不可鎖劇情。
- 探索地圖定義在 `game/scripts/world/map_catalog.gd`；鏡頭／小地圖在 `explore_view.gd`。
- 付費生成資產前確認；輸出進 `game/assets/`，生成用參考圖不要塞進 runtime 路徑。
- 改 XML／DB schema 類比：改探索實體後務必測互動 id 是否在 `main.gd` 有 handler。
