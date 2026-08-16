extends Node
## 分章新手引導：首次進場景／首次戰鬥彈關鍵提示，可跳過。

const STEPS: Dictionary = {
	"boot": [
		"歡迎來到翠嶺。走慢一點也沒關係，這裡的故事等得起人。",
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
		"一次舉手只有一次機會：亂按會揮空，那一擊就擋不掉了。差一點按早不算數，還能補。",
	],
	"battle_fog": [
		"白霧有分身。用 Tab 或 1/2/3 鎖定目標。",
		"只有本體發白的那一瞬打得中。砍到幻影會被反咬。",
	],
	"forge": [
		"釘釘養【器】：花金幣升階。失敗不掉階，但連敗他會發脾氣。",
	],
	"soul": [
		"星讀用【星屑】觀星，凝出戰魂。你走過的路會影響凝出什麼。",
	],
	"ng": [
		"二周目（黑焰迴響）：敵人更硬，出手的空檔更窄，但養成和外觀都帶著走。",
		"畫面上會標著迴響到第幾層。有些台詞和佈告也會跟著換。",
	],
}


func seen(key: String) -> bool:
	return GameState.has_flag("tut.v2.%s" % key)


func mark(key: String) -> void:
	GameState.set_flag("tut.v2.%s" % key, true)
	## 從這裡回報而不是從呼叫端，教學步驟才不會漏掉哪一支
	var tel: Node = _telemetry_node()
	if tel:
		tel.call("note_tutorial", key)


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


## autoload 之間用絕對路徑 get_node 在某些啟動時機會噴錯，一律從 SceneTree.root 走
func _telemetry_node() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		return (t as SceneTree).root.get_node_or_null("Telemetry")
	return null
