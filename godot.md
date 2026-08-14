# Godot 引擎指南 · 翠嶺·兔勇者

Stack: **Godot 4.7** · **GDScript** · `game/project.godot`  
（上游 Godogen 指南以 C# 為例；此檔才是本 repo 的準則。）

## 專案形狀

```
game/
  project.godot
  scenes/          # main / battle / dialogue
  scripts/         # autoload · world · battle · systems · ui
  assets/          # 執行期載入的唯一美術路徑
  data/i18n/
tools/             # export · gen_bgm · proof_run · asset-gen 輔助
screenshots/       # 證明截圖（可 .gdignore）
```

Build 閘門：

```bash
godot --path game --headless --import
godot --path game --headless --quit-after 5   # 不可有 SCRIPT ERROR
./tools/proof_run.sh                          # 可選：截圖證明
```

## 靜默失敗（GDScript 常見）

- **Owner 鏈**：動態 `add_child` 的 Control 若要進 PackedScene 才需 owner；本專案探索 UI 多為 runtime 建樹，重點是 **mouse_filter / z 序 / 父節點**。
- **大 TileMap**：地圖 >2000px 時仍用 atlas 變體填格即可；避免每格 new 節點。
- **相機**：世界內容放在 `ScrollWorld`，HUD（標題／小地圖／提示）掛在 ExploreView 根上，**不要**跟著 scroll。
- **小地圖點位**：entity 重建後要 `_rebuild_minimap()`；相機每幀 `_update_minimap_markers()`。
- **`.gdignore`**：只給 `screenshots/`；**絕不可**放在 `assets/`。
- **Headless 退出 RID leak**：可忽略。

## 證明（Proof video / stills）

```bash
./tools/proof_run.sh
# → screenshots/proof_*.png 與可選 video
```

Prefer 看得到的缺陷（空白地圖、小地圖不更新、卡選單）驅動下一輪，而不是「腳本能 parse」。

## 資產

見 `.agents/skills/asset-gen/SKILL.md`。  
本遊戲以 **2D pixel + 插畫半身像** 為主；3D/GLB 非必須。
