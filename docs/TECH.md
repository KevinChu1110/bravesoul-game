# TECH · 技術方向

## 引擎

| 選擇 | **Godot 4.x**（維持） |
|------|----------------|
| 原因 | 2D 像素、動畫、場景、對話、BOSS 演出；桌面／Steam／Web export 皆可 |
| 語言 | GDScript 為主（迭代快） |
| 現況 | **已安裝** Godot 4.7.1；垂直切片可玩 |
| 美術方向 | **2D 像素／場景**（逐步替換色塊 Control 探索） |
| 機制 | `BattleSim` 為權威；新 Boss 掛機制庫 ID（見 MECHANIC_LIBRARY） |

### 發行順序 vs 引擎（2026-08）

| 外部建議 | 我們的決定 |
|----------|------------|
| itch／Web 優先於 Steam | ✅ **發行策略**採納 |
| 為 5 秒進頁改 Phaser | ❌ **不改引擎**；完整作用 **itch 下載包** 即可降創作者門檻 |
| Godot Web | 可另做 **C0+雷歐 demo** 網頁切片；不阻塞主專案 |

備選僅在「確定只要超輕量網頁、放棄複雜場景敘事」時重估 Phaser——目前否。

## 高層架構

```
game/                          # Godot 專案根（待建立）
  scenes/
    world/                     # 城鎮、野外、地圖
    battle/                    # 戰鬥場景
    ui/                        # HUD、選單、對話
  scripts/
    story/                     # flag、任務、章節
    battle/
      battle_sim.gd            # tick 模擬（權威數值）
      unit.gd                  # 狀態機
      formulas.gd              # 傷害／命中／暴擊
    net/                       # 可選連線
    save/
  data/                        # JSON / Resource：NPC、關卡、敵人
  assets/
```

### 戰鬥（必守）

- **Sim 與 View 分離**：`BattleSim` 只發事件；`BattleView` 只播動畫。  
- **禁止**「整場算完再播 log」當主路徑（那是舊 Discord 模型）。  
- 單機時客戶端 sim 即可；連線獎勵關卡再上伺服器校驗。

### 敘事

- 對話資料：Resource 或 JSON（id、speaker、text、choices、set_flag、next）  
- 全域 `GameState.flags`  
- 任務：聽 flag 變化更新  

### 存檔

```json
{
  "version": 1,
  "chapter": "C1",
  "flags": {},
  "party": {},
  "inventory": [],
  "world": { "node": "knight_town" }
}
```

雲同步：整包或 patch；衝突手動選。

## 連線（見 ONLINE.md）

- 初期：REST（存檔、殘影上報、排行）  
- 共鬥：後期房間服務  
- 候選後端：Supabase（你已有工具鏈）／自架 FastAPI  

## 與舊 bravesoul 的關係

| 舊路徑 | 新用法 |
|--------|--------|
| `engine/*.py` | **不引用**；公式可人工移植到 `formulas.gd` |
| `data/story.py` | 文案靈感，重寫進 `data/` |
| `bot/assets/` | 可複製到 `assets/from-legacy/` 當 placeholder |
| `bot/main.py` | 不使用 |

## 品質

- 戰鬥：固定 seed 的 sim 單元測試（Godot GUT 或 headless）  
- 主線：章節 smoke（flag 走到終章）  
- 每月 export 一份可分發 build  

## 專案路徑

```bash
cd /Users/kevin.chu/develop/sideprojects/bravesoul-game/game
godot .                    # 執行
godot --editor .           # 編輯器
godot --headless -s res://scripts/battle/test_formulas.gd
```

垂直切片流程見 `game/README.md`。

## 命名

| 用途 | 名 |
|------|-----|
| Repo／資料夾 | `bravesoul-game` |
| 工作標題 | 翠嶺·兔勇者 |
| 對外正式名 | 6 個月內再定（避開原作商標硬撞） |
