# Godogen 整合說明

來源：[htdt/godogen](https://github.com/htdt/godogen)

## 裝了什麼

| 路徑 | 用途 |
|------|------|
| `AGENTS.md` | 本專案 agent 執行憲章（已改寫為 GDScript 現況） |
| `godot.md` | 引擎靜默失敗與閘門 |
| `.agents/skills/asset-gen/` | 付費產圖／影片／GLB 技能（需 API key） |
| `tools/proof_run.sh` | 證明管線：import → smoke → 截圖 |
| `game/scripts/dev/proof_capture.gd` | headless 截圖腳本 |
| `screenshots/` | 證明輸出（`.gdignore` 不進遊戲） |

## 與上游差異

上游 Godogen 預設 **C# 綠地專案 + 建置時產 .tscn**。  
本遊戲是 **既有 GDScript 敘事 RPG**，因此：

- 不重寫成 C#
- 不強制 SceneBuilder 管線
- 保留 `game/` 現有架構
- 採納其核心：**proof over claims**、asset-gen skill、引擎靜默失敗清單

## 日常指令

```bash
# 開發
cd game && godot .

# Godogen 閘門（headless）
./tools/proof_run.sh

# 視窗模式截真畫面（本機有顯示器時）
PROOF_WINDOWED=1 ./tools/proof_run.sh

# 輸出：screenshots/proof_01_title.png
#       screenshots/proof_02_explore_town.png
#       screenshots/proof_03_inventory.png
#       screenshots/proof_manifest.txt

# 付費產圖（需 export XAI_API_KEY 或 GOOGLE_API_KEY）
python3 .agents/skills/asset-gen/tools/asset_gen.py image \
  --prompt "pixel art village night, top-down, 16-bit" \
  -o game/assets/sprites/maps/village_bg_new.png
```

### proof 多階段流程

1. 載入 `main.tscn` → 截標題  
2. `Main.proof_jump_explore("town")` → 截探索（含 HUD／快捷欄）  
3. `Main.proof_open_inventory()` → 截物品欄  
4. headless 若 viewport 全黑 → 自動寫**色帶 fallback**（manifest 可辨）並仍產出 3 張 PNG  
5. 真像素請用 `PROOF_WINDOWED=1`

## 建議優化順序（對齊 Godogen）

1. `./tools/proof_run.sh` 必須綠  
2. 肉眼看 `screenshots/` 與本機 `godot .`  
3. 有 key 時用 asset-gen **重繪地圖底圖／NPC**（先確認花費）  
4. 缺陷驅動下一輪（卡選單、小地圖、戰鬥提示等）
