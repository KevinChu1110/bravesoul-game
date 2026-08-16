extends Node
## 分章新手引導：首次進場景／首次戰鬥彈關鍵提示，可跳過。
## 前 30 分鐘加厚：器／魂／招與「流派≠三重養成」拆成短步，勿堆牆文。
## 文案走 Loc key（tut.v2.*）；此表只列 key 順序。

const STEP_KEYS: Dictionary = {
	"boot": ["tut.v2.boot1", "tut.v2.boot2", "tut.v2.boot3"],
	"explore": ["tut.v2.explore1", "tut.v2.explore2"],
	"fort": ["tut.v2.fort1", "tut.v2.fort2", "tut.v2.fort3"],
	"battle_auto": ["tut.v2.battle_auto1", "tut.v2.battle_auto2"],
	"battle_parry": ["tut.v2.battle_parry1", "tut.v2.battle_parry2", "tut.v2.battle_parry3"],
	"battle_fog": ["tut.v2.battle_fog1", "tut.v2.battle_fog2"],
	"forge": ["tut.v2.forge1", "tut.v2.forge2"],
	"paths": ["tut.v2.paths1", "tut.v2.paths2"],
	"soul": ["tut.v2.soul1", "tut.v2.soul2"],
	"flag_hint": ["tut.v2.flag_hint1"],
	"ng": ["tut.v2.ng1", "tut.v2.ng2"],
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
	var keys: Array = STEP_KEYS.get(key, [])
	var out: Array = []
	var speaker := "引導"
	if Engine.get_main_loop() is SceneTree:
		var loc: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Loc")
		if loc and loc.has_method("t"):
			speaker = str(loc.call("t", "tut.guide_speaker"))
			for k in keys:
				out.append({"speaker": speaker, "text": str(loc.call("t", str(k)))})
			return out
	## Loc 尚未就緒時回 key，方便找漏翻
	for k in keys:
		out.append({"speaker": speaker, "text": str(k)})
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
