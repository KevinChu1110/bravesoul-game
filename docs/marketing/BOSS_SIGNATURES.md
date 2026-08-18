# Boss 名場面靜幀

六王高潮圖，供 **戰鬥勝利演出**、**Short**、**官網 gallery** 共用。

## 檔案

| Boss | 遊戲 | 官網 |
|------|------|------|
| 雷歐 | `game/assets/sprites/bosses/signature/leo.png` | `web/media/bosses/signature/leo.png` |
| 白霧 | `…/fog.png` | 同左 web |
| 阿波 | `…/abo.png` | 同左 web |
| 疾影 | `…/falcon.png` | 同左 web |
| 石拳 | `…/boar.png` | 同左 web |
| 魔王 | `…/demon.png` | 同左 web |

## 程式

```gdscript
SpriteDB.boss_signature("leo")  # 無則退回 attack → idle
```

戰鬥 `_on_end(won)` 勝利時會切 Boss 立繪為名場面。

## Short 用法

每週 Boss 向短影音可用對應 signature 當封面／定格尾幀；錨圖產 Grok 15s 時也可上傳此圖。

## 備註

阿波初版以 idle 當 ref 被安全過濾擋下，改為純文字 chibi 熊貓重產；若風格偏離立繪，可之後再微調。
