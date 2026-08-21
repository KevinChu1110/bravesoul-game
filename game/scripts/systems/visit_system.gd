extends Node
## 好友挑戰／友誼鑰匙／寶箱（對齊原作：挑戰好友打法、勝選金或經驗、3 鑰開箱）。
## 不做即時 PVP：打的是對方留下的殘影。離線用傭兵團名冊。
## Autoload：VisitSystem

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const CHALLENGE_DAILY := 10
const KEYS_PER_CHEST := 3
const KEY_ITEM := "friendship_key"
const CHEST_GOLD_MIN := 40
const CHEST_GOLD_MAX := 120

## 離線／無 presence 時的本地殘影名冊
## 離線名冊＝傭兵團裡可挑戰的「好友殘影」（不是即時對戰）
const LOCAL_SHADOWS: Array[Dictionary] = [
	{"id": "shadow_ash", "name": "好友・灰道", "mode": "pvp_snap", "power": 12,
		"payload": {"name": "好友・灰道", "max_hp": 55, "atk": 9, "def": 3, "speed": 10.0, "power": 12}},
	{"id": "shadow_bandit", "name": "好友・荒路", "mode": "pvp_snap", "power": 18,
		"payload": {"name": "好友・荒路", "max_hp": 70, "atk": 11, "def": 4, "speed": 11.0, "power": 18}},
	{"id": "shadow_fog", "name": "好友・霧隱", "mode": "pvp_snap", "power": 22,
		"payload": {"name": "好友・霧隱", "max_hp": 80, "atk": 13, "def": 5, "speed": 12.0, "power": 22}},
	{"id": "shadow_coast", "name": "好友・潮岸", "mode": "pvp_snap", "power": 26,
		"payload": {"name": "好友・潮岸", "max_hp": 92, "atk": 15, "def": 6, "speed": 11.5, "power": 26}},
	{"id": "shadow_scar", "name": "好友・疤地", "mode": "pvp_snap", "power": 30,
		"payload": {"name": "好友・疤地", "max_hp": 105, "atk": 17, "def": 7, "speed": 12.5, "power": 30}},
]


static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


func _fk(suffix: String) -> String:
	return "visit.%s" % suffix


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func _refresh_daily() -> void:
	var today := today_key()
	if str(GameState.get_flag(_fk("day"), "")) != today:
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("challenges_today"), 0)
		## 清空當日已挑戰名單
		GameState.set_flag(_fk("challenged"), {})


func challenges_today() -> int:
	_refresh_daily()
	return int(GameState.get_flag(_fk("challenges_today"), 0))


func challenges_left() -> int:
	return maxi(0, CHALLENGE_DAILY - challenges_today())


func key_count() -> int:
	return InventorySystem.count(KEY_ITEM)


func _challenged_map() -> Dictionary:
	_refresh_daily()
	var v: Variant = GameState.get_flag(_fk("challenged"), {})
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return (v as Dictionary).duplicate(true)


func was_challenged_today(tid: String) -> bool:
	return bool(_challenged_map().get(tid, false))


func mark_challenged(tid: String) -> void:
	var m := _challenged_map()
	m[tid] = true
	GameState.set_flag(_fk("challenged"), m)
	GameState.set_flag(_fk("challenges_today"), challenges_today() + 1)


## 合併本地殘影＋（可選）線上 presence 名單
func ingest_remote(list: Array) -> void:
	GameState.set_flag("pvp.remote", list)


func list_targets() -> Array:
	_refresh_daily()
	var out: Array = []
	for s in LOCAL_SHADOWS:
		var row: Dictionary = s.duplicate(true)
		row["source"] = "local"
		row["done"] = was_challenged_today(str(row.get("id", "")))
		out.append(row)
	## 連線：其他玩家上傳的戰鬥殘影（非即時）
	var remote: Variant = GameState.get_flag("pvp.remote", [])
	if remote is Array:
		for row in remote:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var uid := str(row.get("user_id", row.get("id", "")))
			if uid == "":
				continue
			if OnlineGate and str(OnlineGate.user_id) != "" and uid == str(OnlineGate.user_id):
				continue
			var tid := "pvp_%s" % uid
			var payload: Dictionary = {}
			if typeof(row.get("payload", {})) == TYPE_DICTIONARY:
				payload = (row.get("payload", {}) as Dictionary).duplicate(true)
			var nm := str(row.get("display_name", payload.get("name", _t("好友殘影"))))
			out.append({
				"id": tid,
				"name": _t("好友・%s") % nm,
				"mode": "pvp_snap",
				"power": int(row.get("power", payload.get("power", 0))),
				"payload": payload,
				"source": "remote",
				"done": was_challenged_today(tid),
			})
	return out


func can_challenge(tid: String) -> Dictionary:
	_refresh_daily()
	if challenges_left() <= 0:
		return {"ok": false, "msg": _t("今日好友挑戰已滿（%d／%d）。") % [CHALLENGE_DAILY, CHALLENGE_DAILY]}
	if was_challenged_today(tid):
		return {"ok": false, "msg": _t("今天已經挑戰過這位好友了。")}
	return {"ok": true, "msg": ""}


func find_target(tid: String) -> Dictionary:
	for t in list_targets():
		if str(t.get("id", "")) == tid:
			return t
	return {}


func begin_challenge(tid: String) -> Dictionary:
	var gate: Dictionary = can_challenge(tid)
	if not bool(gate.get("ok", false)):
		return gate
	var t: Dictionary = find_target(tid)
	if t.is_empty():
		return {"ok": false, "msg": _t("找不到這位好友。")}
	GameState.set_flag(_fk("pending_id"), tid)
	GameState.set_flag(_fk("pending_name"), str(t.get("name", "")))
	if str(t.get("mode", "")) == "pvp_snap":
		var pl: Dictionary = {}
		if typeof(t.get("payload", {})) == TYPE_DICTIONARY:
			pl = (t.get("payload", {}) as Dictionary).duplicate(true)
		if str(pl.get("name", "")) == "":
			pl["name"] = str(t.get("name", _t("好友殘影")))
		GameState.set_flag("pvp.pending_def", pl)
	else:
		GameState.set_flag("pvp.pending_def", {})
	return {
		"ok": true,
		"mode": str(t.get("mode", "pvp_snap")),
		"name": str(t.get("name", "")),
		"power": int(t.get("power", 0)),
		"msg": _t("向【%s】發起好友挑戰（戰力 %d）。打的是留下的打法，不是即時對戰。") % [
			str(t.get("name", "")), int(t.get("power", 0))
		],
	}


func clear_pending() -> void:
	GameState.set_flag(_fk("pending_id"), "")
	GameState.set_flag(_fk("pending_name"), "")


func pending_id() -> String:
	return str(GameState.get_flag(_fk("pending_id"), ""))


func on_challenge_won(prefer_gold: bool) -> Dictionary:
	var tid := pending_id()
	var tname := str(GameState.get_flag(_fk("pending_name"), _t("好友")))
	if tid == "":
		return {"ok": false, "msg": _t("沒有進行中的好友挑戰。")}
	mark_challenged(tid)
	clear_pending()
	InventorySystem.add_item(KEY_ITEM, 1)
	var gold_n := 0
	var xp_n := 0
	if prefer_gold:
		gold_n = 25 + randi() % 20
		GameState.add_gold(gold_n)
	else:
		xp_n = 18 + randi() % 12
		GameState.add_xp(xp_n)
	SaveManager.save_game()
	var msg := _t("贏了【%s】的好友挑戰！友誼鑰匙 ×1。") % tname
	if prefer_gold:
		msg += _t(" 金幣 +%d。") % gold_n
	else:
		msg += _t(" 經驗 +%d。") % xp_n
	return {
		"ok": true,
		"gold": gold_n,
		"xp": xp_n,
		"key": 1,
		"keys_total": key_count(),
		"msg": msg,
	}


func on_challenge_lost() -> Dictionary:
	var tid := pending_id()
	if tid != "":
		## 失敗也算今日挑戰次數（原作挑戰次數有限）
		mark_challenged(tid)
	clear_pending()
	SaveManager.save_game()
	return {"ok": true, "msg": _t("好友挑戰敗北。今日次數仍會消耗。")}


func can_open_chest() -> bool:
	return key_count() >= KEYS_PER_CHEST


func open_chest() -> Dictionary:
	if not can_open_chest():
		return {
			"ok": false,
			"msg": _t("友誼鑰匙不足（需 %d，現有 %d）。") % [KEYS_PER_CHEST, key_count()],
		}
	InventorySystem.remove_item(KEY_ITEM, KEYS_PER_CHEST)
	var gold_n := CHEST_GOLD_MIN + randi() % (CHEST_GOLD_MAX - CHEST_GOLD_MIN + 1)
	GameState.add_gold(gold_n)
	var dust_n := 1 + randi() % 3
	GameState.add_stardust(dust_n)
	## 機率掉一枚低階飾品
	var loot_line := _t("金 +%d · 星屑 +%d") % [gold_n, dust_n]
	var rolled: Dictionary = {}
	if GameState.level >= EquipmentSystem.ACCESSORY_LEVEL_REQ and randf() < 0.45:
		var bases := ["star_pendant", "oak_charm", "blade_ring", "mist_earring", "tide_bracelet", "scar_amulet", "knight_belt"]
		var bid := str(bases[randi() % bases.size()])
		rolled = EquipmentSystem.roll_instance(bid)
		if not rolled.is_empty():
			GameState.equip_bag.append(rolled)
			loot_line += _t(" · 飾品【%s】") % str(rolled.get("name", bid))
	else:
		InventorySystem.add_item("iron_scrap", 1 + randi() % 2)
		loot_line += _t(" · 鐵屑")
	SaveManager.save_game()
	return {
		"ok": true,
		"gold": gold_n,
		"dust": dust_n,
		"equip": rolled,
		"msg": _t("打開友誼寶箱！%s") % loot_line,
	}


func status_bbcode() -> String:
	_refresh_daily()
	var lines: PackedStringArray = []
	lines.append(_t("[b]好友挑戰[/b]"))
	lines.append(_t("打的是對方留下的打法（殘影），不是即時對戰。不耗能量。"))
	lines.append(_t("登入後可打其他旅人的殘影。離線則打傭兵團名冊。"))
	lines.append(_t("勝可選金幣或經驗，並得友誼鑰匙。每日 %d 場；同一人一天一次。") % CHALLENGE_DAILY)
	lines.append(_t("今日挑戰：%d／%d（剩餘 %d）") % [challenges_today(), CHALLENGE_DAILY, challenges_left()])
	lines.append(_t("友誼鑰匙：%d（%d 把開 1 個友誼寶箱）") % [key_count(), KEYS_PER_CHEST])
	return "\n".join(lines)
