# 主線／支線台詞資料 Schema（DialogLines）

路徑：`res://data/dialogues/*.json`。
**檔名不影響 key**：所有檔案會合併成同一張表，撞名會 `push_error`。
分檔只是為了好找（`hub` 大廳面板、`side` 支線、`world` 廣域探索、
`battle` 戰後結算、`craft` 鍛造／招式／戰魂、`chapter` 章節與各地互動）。

遊戲端用 `DialogLines.lines("<key>")` 取台詞，丟給 `main.gd::_play_dialog()`。

## 檔案結構

```json
{
  "c2.lantern": [
    { "speaker": "旁白", "text": "霧燈只照三步。再遠的路，要靠自己的眼睛。" }
  ],
  "shop.bought": [
    { "speaker": "琥珀", "text": "成交。別死外頭——我還想再賺你一次。" },
    { "speaker": "系統", "text": "購入【{item}】×1（-{price}金）" }
  ]
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| key | string | `<區域>.<情境>`，例如 `c5.dock`、`forge.no_gold` |
| `speaker` | string | 顯示的說話者名 |
| `text` | string | 台詞本文，可帶 `{名稱}` 插槽 |

`speaker`／`text` 以外的欄位（例如 `portrait`）會原樣傳給對話框，
但**只有 `text` 會做插值**。

## 插值

`text` 裡的 `{名稱}` 由呼叫端的 `vars` 填：

```gdscript
_play_dialog(DialogLines.lines("shop.bought", {
    "item": InventorySystem.item_name(item_id),
    "price": price,
}), _go_material_shop)
```

值一律 `str()` 之後代入。取代 `"%d" % n` 這種寫法是刻意的：
用名字比用位置不容易接錯，而且資料檔自己看得懂缺什麼。
漏傳或多留插槽都會 `push_error`。

## 條件不在這裡

`NpcLines` 連「這個狀態下該講哪一段」都寫在 JSON 的 `rules` 裡；
這邊**沒有** `rules`，選哪個 key 仍然由 `main.gd` 的 `if` ／ `match` 決定。

這不是還沒做完，是刻意的：這些台詞的分支條件跟流程綁死
（剛打贏誰、身上有沒有信、第幾層），塞進 JSON 只會變成把程式碼寫成字串。
NPC 那邊條件單純（幾個 flag 加周目數）才適合資料化。

## 動到台詞之後

一定要跑 `tools/run_tests.sh`（`test_main_dialog`）。
黃金樣本 `scripts/systems/test_main_dialog_golden.json` 是遷移當下從舊版
`main.gd` 機械抽出來的，**改台詞就要一起更新黃金樣本**，
否則測試會擋下來——這是刻意的摩擦，避免有人順手改字沒人知道。

新增 key 時同理：`main.gd` 的呼叫順序要跟黃金樣本一致，
測試會比對順序，所以新增／刪除都得回頭補黃金樣本那一筆。
