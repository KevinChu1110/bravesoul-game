# 2D 風格與表現層設計

> 決策：遊戲改 **2D**（像素偏敘事 RPG）。  
> **規則層不動**（BattleSim 事件）；換的是場景、角色、危險區表現。

---

## 1. 目標畫面

| 模式 | 表現 |
|------|------|
| 探索 | 俯視或 3/4 俯視 2D 地圖；角色 32×32 或 48×48 |
| 戰鬥 | 側視站位或同探索鏡頭 + 危險區貼地 |
| UI | 無 Emoji；左右血條保留；提示用文字+圖示幾何形 |

**對標感覺**：復古像素 + 溫暖敘事（非黑暗魂壓）。

---

## 2. 分層架構

```
BattleSim / GameState     ← 邏輯權威（已有）
        ↓ events
BattleView2D / Explore2D  ← 新：sprite、Tween、Area2D
        ↓
Assets                    ← 兔、Boss、tile、FX
```

現有 `ExploreView`（Control 色塊）→ 逐步換成 `TileMap + CharacterBody2D`。  
現有 `battle_view` 色塊 → 換成站位 Node2D + AnimatedSprite2D。

---

## 3. 資產優先級

| 優先 | 資產 | 狀態 |
|------|------|------|
| P0 | 兔勇者 4 向走 + 站立；基本武器 | **已接**：idle + walk×4（bob）+ battle；左右 scale 翻轉 |
| P0 | 雷歐、白霧、阿波、魔王 各 1 站立 + 1～2 攻擊 pose | **已接**：`bosses/poses/<id>/{idle,telegraph,attack,recover}`；戰鬥事件切幀 |
| P0 | 火圈／風切／落岩／時鐘 地面 FX（可先幾何後換畫） | **已接**：幾何 FX PNG + Battle HazardFX |
| P1 | 六域 tile 各 1 套 | **階段**：各域 bg／banner／battle 底圖已掛；tile 格子待做 |
| P1 | NPC 半身或全身各 1 | **已接**：程序像素 chibi（灰鬚／釘釘／風耳等） |
| P2 | 技能特效、破防碎石、看破閃白 | 看破／格擋 modulate + parry_flash |

### 實作入口（2026-08）

| 路徑 | 說明 |
|------|------|
| `game/assets/sprites/` | 烘焙後 PNG + `MANIFEST.md` |
| `game/assets/sprites/tiles/` | 16/32px 地面 tile（石／草／土／木／沙／霧／暗） |
| `game/assets/audio/sfx/` | 程序 WAV 簡包（格擋／火圈／看破等） |
| `tools/import_sprites.py` | 自 legacy bot 資產重烘焙 |
| `tools/gen_sfx_and_tiles.py` | 重生成音效 + tile |
| `game/scripts/art/sprite_db.gd` | 路徑／entity／tile 對照 |
| `game/scripts/autoload/audio_manager.gd` | SFX 池化播放 |
| `explore_view.gd` | 底圖 + tile 平鋪 + Y 排序 + 橫幅視差 |
| `battle_view.gd` + `battle.tscn` | Boss 肖像、戰鬥底圖、HazardFX + 音效事件 |

可從舊 `bravesoul/bot/assets` 像素圖 **降採樣／裁切** 當 placeholder（已用）。

### 2D 深化進度

| 項目 | 狀態 |
|------|------|
| 底圖 + 角色／Boss 貼圖 | 已接 |
| 地面 tile 疊層（依地圖種類） | **真 TileMapLayer** + atlas 4 變體 |
| 腳底 Y 排序 | 已接 |
| 遠景橫幅視差 | 已接 |
| 底部 vignette | 已接 |
| 真 TileMap／碰撞 tile | **已接**：邊界牆 + 建築佔位；軸分離滑牆 |
| Boss 攻擊幀 | **已接** |
| 玩家攻擊幀 | **已接** idle/telegraph/attack/recover/skill |

---

## 4. 機制 → 2D 表現對照

| 機制 | 現 UI | 2D 目標 |
|------|-------|---------|
| 格擋窗 | 中央「格擋」字 | Boss 抬爪 pose + 閃白框 |
| 火圈 | 黃字「閃」 | 腳下橙紅環擴散 |
| 看破 | 本體發白 | 輪廓高光 + 殘影半透明 |
| 破防條 | 中央 % | Boss 頭上黃條 |
| 控時 | 時鐘字 | 鐘面 UI 或場上時鐘 prop |
| 安全區 | 文字 | 地面亮格 |
| 對撞（石拳） | J 窗 | 雙方衝鋒軌跡相交 |

---

## 5. 探索 2D 規格

- 地圖單位：16px tile  
- 碰撞：靜態體 + 互動 Area2D（E）  
- 相機：跟兔，死區小  
- 進出：門觸發換 scene 或同 scene 遮罩  

**遷移順序建議：**  
騎士廣場 → 翠谷村 → 霧隱 → 道場 → 戰鬥場景 → 森林／海岸。

---

## 6. 音效（簡）— 已接

| 事件 | 檔 | 觸發 |
|------|-----|------|
| 格擋成功 | `parry.wav` | perfect_parry |
| 受擊 | `hit.wav` | hit |
| 橫斬 | `slash.wav` | skill_cast/hit |
| 火圈灼 | `fire.wav` | hazard_resolve 失敗 fire_ring |
| 風切 | `wind.wav` | wind_cut 失敗 |
| 落岩 | `rock.wav` | rockfall 失敗 |
| 看破 | `reveal.wav` | fog_reveal |
| 破防 | `break.wav` | abo_guard_break |
| 停拍 | `stop.wav` | falcon_stop |
| 對撞 | `clash.wav` | boar 剝甲／王者斬 |
| 時鐘／預告 | `clock` / `warn` | hazard |
| 勝／敗 | `victory` / `defeat` | battle_end |
| 腳步／互動 | `step` / `interact` | 探索 |

### BGM（已接 · 程序循環曲）

| id | 時機 |
|----|------|
| title | 標題畫面 |
| village / town / wild / road | 對應探索圖 |
| mist / dojo / forest / coast | C2–C5 域 |
| battle / boss | 狼戰／聖獸與魔王 |
| tower / ending | 塔下營地／終章 |

淡入淡出：`AudioManager.play_bgm`（雙播放器交叉）。檔案：`assets/audio/bgm/`。

---

## 7. 不做（現階段）

- 3D  
- 高畫質立繪全量  
- 全程骨骼動畫（可先幀動畫）  

---

## 8. 與設計文件關係

- 機制：MECHANIC_LIBRARY / BOSS_KITS  
- 章節：CHAPTER_C4_C5、POSTGAME  
- 本檔只管**怎麼看起來像 2D 遊戲**  
