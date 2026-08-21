# GDD · 遊戲設計總文件（索引）

> **勇者之魂** / Brave Soul（repo：`bravesoul-game`）  
> 本檔是設計入口。細節以各專章為準；衝突時以**較新、較專的檔**為準，並回寫 DECISIONS。

---

## 一句话产品

在**翠嶺大陸**上，一隻不慕強權的兔子，以**場景敘事 × 即時自動戰鬥 × 三重養成**走過六域、喚醒聖獸、對抗魔王；連線可選加厚，**主線永不鎖網**。

## 體驗支柱（優先序）

1. 世界與故事（NPC、旗幟、章節）  
2. 即時戰鬥演出（當場互毆，不是結算回放）  
3. 三重養成有各自意義（裝備 / 戰魂 / 技能）  
4. 輕連線（殘影、雲存檔、可選共鬥）

## 文件地圖

| 檔案 | 內容 | 狀態 |
|------|------|------|
| [VISION.md](VISION.md) | 願景、基調、不做 | ✅ |
| [SCOPE.md](SCOPE.md) | 3m / 6m 範圍 | ✅ 需對齊三重養成 |
| [WORLD.md](WORLD.md) | 世界觀 | ✅ |
| [STORY_BIBLE.md](STORY_BIBLE.md) | 主線節拍 | ✅ |
| [NPC.md](NPC.md) | NPC 表 | ✅ |
| [SYSTEMS.md](SYSTEMS.md) | 系統總覽 | ✅ 已改三重養成 |
| [COMBAT.md](COMBAT.md) | **即時戰鬥完整規格** | ✅ 新建 |
| [PROGRESSION.md](PROGRESSION.md) | **裝備／戰魂／技能升級** | ✅ 新建 |
| [BALANCE.md](BALANCE.md) | 數值起點 | ✅ 新建 |
| [SCRIPT_C0.md](SCRIPT_C0.md) | 序章對白稿 | ✅ 新建 |
| [SCRIPT_C1.md](SCRIPT_C1.md) | 騎士域＋雷歐戰 | ✅ |
| [SCRIPT_C6.md](SCRIPT_C6.md) | 塔＋反轉＋魔王＋終章 | ✅ |
| [ONLINE.md](ONLINE.md) | 連線分層 | ✅ |
| [HUNTING_GROUNDS.md](HUNTING_GROUNDS.md) | 星途獵場 | ✅ |
| [SYSTEMS_CORE.md](SYSTEMS_CORE.md) | 帳號／官網／裝備／Log／爆擊 | ✅ |
| [ROADMAP.md](ROADMAP.md) | 半年節奏 | ✅ |
| [TECH.md](TECH.md) | 技術 | ✅ |
| [DECISIONS.md](DECISIONS.md) | 決策 | ✅ |
| [UI.md](UI.md) | 介面與資訊架構 | ✅ |
| [DESIGN_CRITIQUE.md](DESIGN_CRITIQUE.md) | 外部 viral 建議評析 R1 | ✅ |
| [DESIGN_CRITIQUE_R2.md](DESIGN_CRITIQUE_R2.md) | 外部 6 問答覆評析 R2 | ✅ |
| [SHARE.md](SHARE.md) | 高光、成就、發行話術 | ✅ |
| [BOSS_KITS.md](BOSS_KITS.md) | 翠嶺四王機制定案 | ✅ |
| [MECHANIC_LIBRARY.md](MECHANIC_LIBRARY.md) | Artale 機制全盤＋未來 Boss 工具箱 | ✅ |
| [CHAPTER_C4_C5.md](CHAPTER_C4_C5.md) | **C4 疾影／C5 石拳 章節設計** | ✅ |
| [POSTGAME_AND_EVENTS.md](POSTGAME_AND_EVENTS.md) | **通關後＋週裂縫** | ✅ |
| [ART_2D.md](ART_2D.md) | **2D 表現與遷移** | ✅ |
| [SCRIPT_C2.md](SCRIPT_C2.md) | 忍者村＋N8 信＋白霧 | ✅ |
| [SCRIPT_C3.md](SCRIPT_C3.md) | 道場＋為何而戰 | ✅ |
| [SCRIPT_C4.md](SCRIPT_C4.md) | 疾影森林傭兵語氣 | ✅ |
| [SCRIPT_C5.md](SCRIPT_C5.md) | 石拳海岸傭兵語氣 | ✅ |

## 核心循環（定稿）

```
城鎮（NPC／鍛造／聚魂／學技）
    → 節點地圖出發
    → 野外：即時自動戰鬥（掉素材、經驗）
    → 據點／支線（對話、旗幟）
    → 區域 BOSS（策略＋劇情）
    → 回城：世界狀態變化、養成、下一章
```

## 三重養成（一句話分工）

| 軸 | 玩家感覺 | 主要給什麼 |
|----|----------|------------|
| **裝備升階** | 把「這把劍」養強 | 基礎攻防血、職系克制底盤 |
| **戰魂入魂** | 給裝備「星曜靈魂」 | 偏科屬性、build 個性、抽卡興奮 |
| **技能升級** | 招式越用越會 | 戰鬥表現、倍率／特效／怒氣效率 |

詳見 [PROGRESSION.md](PROGRESSION.md)。三者**都要**，但成長曲線錯開，避免三套同一件事。

## 敘事主題

> 黑焰以野心為食。能走到最後的，不是最強的，是**不低頭的心**。  
> 主反轉：魔王曾是第一位至弱者——**錯用了「變強」去守護**。（見 STORY_BIBLE）

## 可被記住的一句（傳播）

> 一隻拿鏽劍的兔子，格擋了獅子王的必殺；在塔頂發現，魔王也曾是至弱者。

詳見 [SHARE.md](SHARE.md)。
