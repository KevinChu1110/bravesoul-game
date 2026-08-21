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
3. `./tools/run_tests.sh`（9 個無頭測試，CI 跑的是同一支）
4. 有證明需求時跑 `./tools/proof_run.sh` 產截圖／短片到 `screenshots/`（已含 1–3）

CI：`.github/workflows/game-ci.yml` 每次 push／PR 自動跑 1–3；export 三平台只在
手動觸發或發 release 時跑。

## 寫測試的規矩

- 測試檔放 `scripts/**/test_*.gd`，`extends SceneTree`，結尾 `print("XXX_OK")` + `quit(0)`
  或 `print("XXX_FAIL")` + `quit(1)`。runner 靠這個哨兵判定。
- **一定用 `_initialize()`，不要用 `_init()`。** `_init()` 早於 autoload 註冊，
  凡是碰到 autoload 的腳本會 Compile Error；此時 Godot 會**退回去跑主場景**而不是收工，
  行程永遠不結束（runner 有 timeout 擋，但那是 FAIL）。
- 同理，`class_name` 的工具類（如 `SpriteDB`）**不可在編譯期直接寫 `GameState.xxx`**，
  要用 `Engine.get_main_loop()` 執行期查找。範例見 `sprite_db.gd::_gs()`、`battle_sim.gd`。

任務偏探索就常 checkpoint；任務偏規格就穩步做完，最後用畫面證明。

## 本專案硬規則

- 主線必須**單機可通關**；連線／雲端不可鎖劇情。
- 探索地圖定義在 `game/scripts/world/map_catalog.gd`；鏡頭／小地圖在 `explore_view.gd`。
- 付費生成資產前確認；輸出進 `game/assets/`，生成用參考圖不要塞進 runtime 路徑。
- 改 XML／DB schema 類比：改探索實體後務必測互動 id 是否在 `main.gd` 有 handler。
- **產品北辰**：[docs/PRODUCT_BRIDGE.md](docs/PRODUCT_BRIDGE.md)（原作對齊）；AI 契約：[CLAUDE.md](CLAUDE.md)。
- **降 AI 感**：禁空泛勵志套話；用語對齊選單別名（今日村莊／演武場／抽魂／聚魂殿）。
- **經濟／能量**：開戰走 `EnergySystem`；勿另造體力第二套。
- **BGM**：只用 `AudioManager.play_bgm_for_map` / `play_bgm_for_battle`；地區對照表在 `map_to_bgm`。真曲用 `tools/import_bgm.py`／占位烤 `tools/bake_placeholder_bgm.py`。
- **地圖場景**：可選 `scenes/maps/<id>.tscn`（`MapSceneRegistry`）；scaffold：`tools/scaffold_map_scene.py`。

## 改完自檢（影片心法精簡）

| 問 | 若否 → |
|----|--------|
| 玩家看得見的字有沒有「AI 腔」？ | 改短、改口吻 |
| 有沒有偏離原作名詞／機制？ | 對 PRODUCT_BRIDGE |
| 存檔版號要不要升？ | `GameState.VERSION` + `save_migration` |
| 無頭測試哨兵有沒有綠？ | `./tools/run_tests.sh` 或單支 `test_*.gd` |
