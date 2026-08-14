extends Node
## 組隊挑戰 · 離線助戰骨架（L2 前身）。
## 真多人房未接時：召喚「星途旅人」AI 助戰進裂縫。
## Autoload：PartySystem

const MAX_SLOTS := 2
const DAILY_PARTY_CAP := 3  ## 每日助戰有獎加成次數

## 助戰名冊（離線假旅人）
const ROSTER: Array[Dictionary] = [
	{"id": "ash_blade", "name": "灰刃旅人", "role": "atk", "line": "刀口朝黑焰。", "atk": 3, "def": 0, "gold_bonus": 25},
	{"id": "ward_oak", "name": "橡盾行者", "role": "def", "line": "我擋前面。", "atk": 0, "def": 4, "gold_bonus": 20},
	{"id": "star_sage", "name": "星屑術士", "role": "sup", "line": "星屑借你一瞬。", "atk": 2, "def": 1, "gold_bonus": 30},
	{"id": "mist_scout", "name": "霧影斥候", "role": "spd", "line": "節奏我會跟。", "atk": 1, "def": 1, "gold_bonus": 22},
	{"id": "scar_hunter", "name": "疤地獵手", "role": "atk", "line": "溢皮，我認識味。", "atk": 4, "def": 0, "gold_bonus": 28},
]


func _fk(s: String) -> String:
	return "party.%s" % s


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func _refresh_daily() -> void:
	var today := today_key()
	if str(GameState.get_flag(_fk("day"), "")) != today:
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("boosts_today"), 0)


func boosts_today() -> int:
	_refresh_daily()
	return int(GameState.get_flag(_fk("boosts_today"), 0))


func daily_boost_left() -> int:
	return maxi(0, DAILY_PARTY_CAP - boosts_today())


func is_unlocked() -> bool:
	return GameState.has_flag("game_cleared") or GameState.has_flag("postgame.rift_unlocked")


func selected_ids() -> Array:
	var raw: Variant = GameState.get_flag(_fk("selected"), [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for x in raw:
		out.append(str(x))
	return out


func set_selected(ids: Array) -> void:
	var clean: Array = []
	for x in ids:
		var sid := str(x)
		if _find_companion(sid).is_empty():
			continue
		if sid in clean:
			continue
		clean.append(sid)
		if clean.size() >= MAX_SLOTS:
			break
	GameState.set_flag(_fk("selected"), clean)
	SaveManager.save_game()


func toggle_companion(cid: String) -> Dictionary:
	if not is_unlocked():
		return {"ok": false, "msg": "通關後才能召集星途助戰。"}
	var cur: Array = selected_ids()
	if cid in cur:
		cur.erase(cid)
		set_selected(cur)
		return {"ok": true, "msg": "已卸下 %s。" % companion_name(cid)}
	if cur.size() >= MAX_SLOTS:
		return {"ok": false, "msg": "助戰最多 %d 人。" % MAX_SLOTS}
	if _find_companion(cid).is_empty():
		return {"ok": false, "msg": "未知旅人。"}
	cur.append(cid)
	set_selected(cur)
	return {"ok": true, "msg": "已召集 %s。" % companion_name(cid)}


func clear_selected() -> void:
	set_selected([])


func companion_name(cid: String) -> String:
	var c := _find_companion(cid)
	return str(c.get("name", cid))


func _find_companion(cid: String) -> Dictionary:
	for c in ROSTER:
		if str(c.get("id", "")) == cid:
			return c
	return {}


func selected_companions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cid in selected_ids():
		var c := _find_companion(str(cid))
		if not c.is_empty():
			out.append(c)
	return out


func has_party() -> bool:
	return not selected_ids().is_empty()


## 戰鬥前：是否套用助戰（裂縫等）
func is_party_battle_active() -> bool:
	return bool(GameState.get_flag(_fk("battle_active"), false)) and has_party()


func begin_party_battle() -> void:
	if has_party():
		GameState.set_flag(_fk("battle_active"), true)
	else:
		GameState.set_flag(_fk("battle_active"), false)


func end_party_battle() -> void:
	GameState.set_flag(_fk("battle_active"), false)


## battle_view 用：加到玩家 stats
func battle_player_stats_patch() -> Dictionary:
	if not is_party_battle_active():
		return {}
	var atk_b := 0
	var def_b := 0
	for c in selected_companions():
		atk_b += int(c.get("atk", 0))
		def_b += int(c.get("def", 0))
	var patch: Dictionary = {}
	if atk_b > 0:
		patch["atk"] = atk_b  ## 呼叫端會累加
	if def_b > 0:
		patch["def"] = def_b
	return patch


func apply_stats_to_dict(stats: Dictionary) -> Dictionary:
	var p := battle_player_stats_patch()
	if p.is_empty():
		return stats
	if p.has("atk"):
		stats["atk"] = int(stats.get("atk", 0)) + int(p["atk"])
	if p.has("def"):
		stats["def"] = int(stats.get("def", 0)) + int(p["def"])
	return stats


## 勝利結算：有獎助戰加成（每日 cap）
func grant_win_bonus() -> Dictionary:
	if not is_party_battle_active():
		return {"ok": false, "msg": "", "gold": 0}
	var names: PackedStringArray = []
	var gold_b := 0
	for c in selected_companions():
		names.append(str(c.get("name", "")))
		gold_b += int(c.get("gold_bonus", 15))
	_refresh_daily()
	var practice_cut := false
	if daily_boost_left() <= 0:
		gold_b = int(gold_b * 0.3)
		practice_cut = true
	else:
		GameState.set_flag(_fk("boosts_today"), boosts_today() + 1)
		GameState.set_flag(_fk("boosts_total"), int(GameState.get_flag(_fk("boosts_total"), 0)) + 1)
	if gold_b > 0:
		GameState.add_gold(gold_b)
	## 小機率狩獵材料（助戰獵手風味）
	var loot := ""
	if randf() < 0.4 and Engine.get_main_loop() is SceneTree:
		var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
		if inv and inv.has_method("add_item"):
			var item := "hunt_hide" if randf() < 0.7 else "hunt_bone"
			if inv.call("add_item", item, 1):
				loot = " · %s×1" % inv.call("item_name", item)
	var msg := "助戰（%s）：金 +%d%s" % ["、".join(names), gold_b, loot]
	if practice_cut:
		msg += "（今日助戰有獎已盡·縮減）"
	end_party_battle()
	SaveManager.save_game()
	return {"ok": true, "msg": msg, "gold": gold_b}


func status_bbcode() -> String:
	_refresh_daily()
	var lines: PackedStringArray = []
	lines.append("[b]星途助戰[/b]（組隊挑戰 · 離線原型）")
	lines.append("真多人房尚未開啟。現可召集 0～%d 名旅人影子，進裂縫時提供攻防與通關金。" % MAX_SLOTS)
	lines.append("主線仍單人；助戰不鎖進度。")
	lines.append("")
	if not is_unlocked():
		lines.append("（通關後解鎖）")
		return "\n".join(lines)
	lines.append("今日助戰有獎加成：剩餘 %d／%d" % [daily_boost_left(), DAILY_PARTY_CAP])
	var sel := selected_ids()
	if sel.is_empty():
		lines.append("目前：單人出戰")
	else:
		var parts: PackedStringArray = []
		for cid in sel:
			var c := _find_companion(str(cid))
			parts.append("%s（攻+%d 防+%d）" % [c.get("name", cid), int(c.get("atk", 0)), int(c.get("def", 0))])
		lines.append("目前助戰：%s" % "、".join(parts))
	lines.append("")
	lines.append("日後：2～4 人真房 · 房主權威 · 伺服器發獎（見 MULTIPLAYER_LOOPS）")
	return "\n".join(lines)


func roster_for_ui() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sel := selected_ids()
	for c in ROSTER:
		var d: Dictionary = c.duplicate()
		d["picked"] = str(c.get("id", "")) in sel
		out.append(d)
	return out


## 敘事：開戰前台詞
func intro_lines() -> Array:
	var lines: Array = []
	for c in selected_companions():
		lines.append({
			"speaker": str(c.get("name", "旅人")),
			"text": str(c.get("line", "……")),
		})
	if lines.is_empty():
		lines.append({"speaker": "系統", "text": "單人踏入裂縫。"})
	else:
		lines.append({"speaker": "系統", "text": "助戰影子與你同進。（非真實玩家連線）"})
	return lines
