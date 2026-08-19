# 演武競技場 v1

> PVE 波次天梯。獵場刷材料、裂縫練 Boss、競技場追分數。

## 規則

| 項 | 規格 |
|----|------|
| 解鎖 | 進入騎士堡（同獵場） |
| 每日有獎 | **3** 場；用完可練習 |
| 結構 | **5** 波：灰燼鼠 → 殘兵 → 霧影 → 海盜 → 焰靈 |
| 分數 | 每波 1000 + 殘血（≤200）；記個人最佳 |
| 獎勵 | 輕金；**不掉**獵場材料 |
| 排行 | 本地 PB；登入後可 `leaderboard_submit("arena_best")` |

## 入口

Esc 暫停 →「演武競技場」

## 實作

| 模組 | 檔案 |
|------|------|
| 邏輯 | `game/scripts/systems/arena_system.gd` |
| UI／戰鬥收尾 | `main.gd` `_go_arena_panel` / `_on_arena_battle_finished` |
| 每日導流 | `QuestSystem` 委託 `d_arena` |
| 稱號 | `title.arena_challenger` |

## 不做（v1）

即時／非同步 PVP、組隊房、新敵人種。
