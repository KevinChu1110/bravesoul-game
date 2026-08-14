extends Node
## 分章新手引導：首次進場景／首次戰鬥彈關鍵提示，可跳過。

const STEPS: Dictionary = {
	"boot": [
		"歡迎來到翠嶺。這是一則「故事優先」的旅途。",
		"操作：WASD 移動 · E 互動 · J 格擋 · Esc 開功能選單。",
		"Esc 裡有：每日獎勵、長遠任務、公會盟約、戰魂與技能。",
	],
	"explore": [
		"靠近人物或物件會出現黃色提示，按 E 互動。",
		"底部提示條會顯示當前目標。卡住時開 Esc → 旅程進度。",
	],
	"battle_auto": [
		"雜魚戰會自動進行。受傷累積【怒氣】，滿了自動放招。",
		"可按「逃離」脫離非必要戰鬥（Boss 戰通常不建議）。",
	],
	"battle_parry": [
		"Boss 中央會出現倒數。數字變【綠】時按 J（或滑鼠左鍵）格擋。",
		"完美格擋會反擊；失敗會受傷。火圈／風切等預告後也按 J。",
	],
	"battle_fog": [
		"白霧有分身。用 Tab 或 1/2/3 鎖定目標。",
		"只有本體發白的「看破窗」才能有效輸出。打幻影會反噬。",
	],
	"forge": [
		"釘釘養【器】：花金幣升階。失敗不掉階，但連敗他會發脾氣。",
	],
	"soul": [
		"星讀用【星屑】觀星凝戰魂。足迹影響星型——不是轉蛋。",
	],
	"ng": [
		"二周目（黑焰迴響）：敵更強、機制窗略短，但保留養成與外觀。",
		"HUD 會顯示迴響層數。部分台詞與盟約佈告會變化。",
	],
}


func seen(key: String) -> bool:
	return GameState.has_flag("tut.v2.%s" % key)


func mark(key: String) -> void:
	GameState.set_flag("tut.v2.%s" % key, true)


func lines_for(key: String) -> Array:
	if seen(key):
		return []
	var arr: Array = STEPS.get(key, [])
	var out: Array = []
	for t in arr:
		out.append({"speaker": "引導", "text": str(t)})
	return out


## 產生可交給 _play_dialog 的台詞；呼叫端負責 mark + after
func take(key: String) -> Array:
	var lines := lines_for(key)
	if not lines.is_empty():
		mark(key)
	return lines
