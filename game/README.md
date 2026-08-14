# 翠嶺·兔勇者 · Godot 專案

Godot **4.7.x** · 垂直切片（可走探索 + 即時戰鬥 + 雷歐格擋）

## 開啟

```bash
cd /Users/kevin.chu/develop/sideprojects/bravesoul-game/game
godot .
```

## 切片流程

1. **新的旅途** → **可走**村夜（WASD）  
2. E 麥穗 → E **拔劍三振** → E 往東（麥稈）  
3. 荒路 E 灌木 → **狼戰**（衝刺／跳字／麥稈擋死）  
4. 進城 → **可走廣場**（灰鬚／釘釘／星讀／小芽／旗／出城）  
5. E 釘釘 **認劍** → 升階（摔錘）  
6. 荒野 E 內殿 → **雷歐**（體型對照、王者斬、**微末一格**）  
7. **C2** 霧隱村（信）→ 白霧看破戰  
8. **C3** 道場 → 阿波**架勢破防**戰（攻擊灌條）  
9. **C4**（可選）遊俠森林 → **疾影**（停拍輸出 · 風切 J）  
10. **C5**（可選）維京海岸 → **石拳**（對撞剝甲 · 落岩 J）  
11. **C6** 塔（反轉 → 三拒 → 終章）  
12. **通關後** 黑焰裂縫四套 + 週焦點／每日 3 次有獎  
13. **黑焰迴響 NG+**：敵強化、機制窗略短、可選沾焰  
14. **稱號牆**：11 稱號 + 外觀契機一覽（標題／終章／裂縫／存檔石）  

C3 後可直上 C6（最短通關），或先走 C4／C5 補完五柱。通關後塔下／終章可進裂縫。

## 操作

| 鍵 | 作用 |
|----|------|
| WASD／方向鍵 | 探索移動 |
| E / Space | 對話／靠近互動 |
| J / K / 滑鼠左鍵 | 格擋／火圈／時鐘／重拳等互動窗 |
| Tab 或 1/2/3 | 白霧戰切換目標（2=本體） |
| Esc | 暫停（繼續／存檔／稱號／回標題） |
| F3 | 切換除錯狀態列 |
| 戰鬥中大按鈕 | 魔王誘惑時點「我拒絕」 |

## 目錄

```
scripts/autoload/   GameState, SaveManager
scripts/battle/     BattleSim + battle_view（演出）
scripts/world/      ExploreView（可走地圖）
scripts/main.gd     流程路由
scenes/             main, battle, dialogue
```

## 測試

```bash
godot --headless -s res://scripts/battle/test_formulas.gd
```

## 進度備註

- [x] 2D／TileMap／碰撞／攻擊幀／音效 BGM  
- [x] C0–C6 主線 + C4/C5 可選 + 裂縫 + NG+ + 稱號牆  
- [x] Esc 暫停 · 精簡 HUD（F3 除錯）  
- [x] 戰魂入魂 UI（星讀觀星台）  
- [x] 技能／招式 UI（熟練·劍系多級）  
- [x] itch 出貨骨架（export 預設 + 文案 + `tools/export_itch.sh`）

## itch 打包

```bash
# 需已安裝 Godot 4.7.1 export templates
cd /Users/kevin.chu/develop/sideprojects/bravesoul-game
./tools/export_itch.sh
# 產物：dist/uploads/*.zip
# 商店文案：release/ITCH_PAGE.md
```
