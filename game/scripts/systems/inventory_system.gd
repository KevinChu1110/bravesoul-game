extends Node
## 楓式背包／快捷欄。道具定義 + 使用效果。存檔掛在 GameState.inventory / hotbar。

signal inventory_changed
signal hotbar_changed
signal item_used(item_id: String, result: Dictionary)

const HOTBAR_SIZE := 8
const BAG_SLOTS := 24  ## 顯示格數（4×6）

## id → {name, desc, kind, stack, heal?, dust?, gold?, key?, color}
const CATALOG: Dictionary = {
	"hp_s": {
		"name": "小紅水",
		"desc": "恢復 25 生命。",
		"kind": "consumable",
		"stack": 99,
		"heal": 25,
		"color": Color(0.9, 0.25, 0.25),
		"glyph": "紅",
	},
	"hp_m": {
		"name": "中紅水",
		"desc": "恢復 55 生命。",
		"kind": "consumable",
		"stack": 99,
		"heal": 55,
		"color": Color(0.85, 0.15, 0.2),
		"glyph": "赤",
	},
	"bread": {
		"name": "乾糧",
		"desc": "恢復 15 生命。路上充飢。",
		"kind": "consumable",
		"stack": 99,
		"heal": 15,
		"color": Color(0.75, 0.55, 0.3),
		"glyph": "糧",
	},
	"dust_crumb": {
		"name": "星屑碎",
		"desc": "使用後獲得 1 星屑。",
		"kind": "consumable",
		"stack": 99,
		"dust": 1,
		"color": Color(0.55, 0.65, 0.95),
		"glyph": "星",
	},
	"antidote": {
		"name": "清焰露",
		"desc": "恢復 10 生命，並略提振精神。",
		"kind": "consumable",
		"stack": 30,
		"heal": 10,
		"color": Color(0.4, 0.75, 0.55),
		"glyph": "露",
	},
	"key_rusty": {
		"name": "鏽劍（紀念）",
		"desc": "村口撿起的那把。已鍛成正器後仍留念。",
		"kind": "key",
		"stack": 1,
		"color": Color(0.55, 0.5, 0.4),
		"glyph": "劍",
	},
	"map_scrap": {
		"name": "六域殘圖",
		"desc": "行商撕給你的一角。可看不可吃。",
		"kind": "key",
		"stack": 1,
		"color": Color(0.7, 0.65, 0.45),
		"glyph": "圖",
	},
	"relic_token": {
		"name": "秘境印記",
		"desc": "通關秘境留下的印。收藏用。",
		"kind": "key",
		"stack": 9,
		"color": Color(0.65, 0.4, 0.75),
		"glyph": "印",
	},
	"wolf_fang": {
		"name": "狼牙",
		"desc": "雜魚掉落。可賣 8 金。",
		"kind": "material",
		"stack": 99,
		"sell": 8,
		"color": Color(0.7, 0.7, 0.75),
		"glyph": "牙",
	},
	"mist_shard": {
		"name": "霧晶",
		"desc": "霧影掉落。可賣 12 金。",
		"kind": "material",
		"stack": 99,
		"sell": 12,
		"color": Color(0.6, 0.7, 0.9),
		"glyph": "霧",
	},
	"sea_shell": {
		"name": "潮貝",
		"desc": "海岸掉落。可賣 10 金。",
		"kind": "material",
		"stack": 99,
		"sell": 10,
		"color": Color(0.5, 0.7, 0.75),
		"glyph": "貝",
	},
	"scar_ember": {
		"name": "疤焰燼",
		"desc": "疤地掉落。可賣 15 金。",
		"kind": "material",
		"stack": 99,
		"sell": 15,
		"color": Color(0.55, 0.25, 0.5),
		"glyph": "燼",
	},
	"hunt_hide": {
		"name": "溢皮",
		"desc": "狩獵場材料。可賣；未來市集可交易。",
		"kind": "material",
		"stack": 99,
		"sell": 10,
		"tradeable": true,
		"color": Color(0.55, 0.4, 0.3),
		"glyph": "皮",
	},
	"hunt_bone": {
		"name": "焰骨",
		"desc": "狩獵場中階材料。",
		"kind": "material",
		"stack": 99,
		"sell": 22,
		"tradeable": true,
		"color": Color(0.7, 0.55, 0.4),
		"glyph": "骨",
	},
	"hunt_core": {
		"name": "溢核",
		"desc": "狩獵場稀有核。日後市集硬貨。",
		"kind": "material",
		"stack": 99,
		"sell": 60,
		"tradeable": true,
		"color": Color(0.85, 0.35, 0.55),
		"glyph": "核",
	},
}


func _ready() -> void:
	ensure_hotbar()


func ensure_hotbar() -> void:
	if GameState.hotbar == null:
		GameState.hotbar = []
	while GameState.hotbar.size() < HOTBAR_SIZE:
		GameState.hotbar.append("")
	if GameState.hotbar.size() > HOTBAR_SIZE:
		GameState.hotbar.resize(HOTBAR_SIZE)
	if GameState.inventory == null:
		GameState.inventory = {}


func catalog(id: String) -> Dictionary:
	return CATALOG.get(id, {})


func item_name(id: String) -> String:
	var d := catalog(id)
	return str(d.get("name", id))


func count(id: String) -> int:
	ensure_hotbar()
	return int(GameState.inventory.get(id, 0))


func has_item(id: String, n: int = 1) -> bool:
	return count(id) >= n


func add_item(id: String, n: int = 1) -> bool:
	if n <= 0 or not CATALOG.has(id):
		return false
	ensure_hotbar()
	var stack_max := int(catalog(id).get("stack", 99))
	var cur := count(id)
	var nxt := mini(stack_max, cur + n)
	GameState.inventory[id] = nxt
	## 自動放進第一個空快捷欄
	_auto_hotbar(id)
	inventory_changed.emit()
	hotbar_changed.emit()
	return nxt > cur


func remove_item(id: String, n: int = 1) -> bool:
	if not has_item(id, n):
		return false
	var cur := count(id) - n
	if cur <= 0:
		GameState.inventory.erase(id)
		## 清快捷欄空引用
		for i in GameState.hotbar.size():
			if str(GameState.hotbar[i]) == id and count(id) <= 0:
				GameState.hotbar[i] = ""
	else:
		GameState.inventory[id] = cur
	inventory_changed.emit()
	hotbar_changed.emit()
	return true


func _auto_hotbar(id: String) -> void:
	ensure_hotbar()
	for s in GameState.hotbar:
		if str(s) == id:
			return
	for i in GameState.hotbar.size():
		if str(GameState.hotbar[i]) == "":
			GameState.hotbar[i] = id
			return


func set_hotbar(slot: int, id: String) -> void:
	ensure_hotbar()
	if slot < 0 or slot >= HOTBAR_SIZE:
		return
	if id != "" and count(id) <= 0:
		return
	GameState.hotbar[slot] = id
	hotbar_changed.emit()


func clear_hotbar(slot: int) -> void:
	set_hotbar(slot, "")


func bag_list() -> Array:
	## [{id, count, def}] 有數量的
	ensure_hotbar()
	var out: Array = []
	for id in GameState.inventory.keys():
		var c := int(GameState.inventory[id])
		if c > 0 and CATALOG.has(id):
			out.append({"id": id, "count": c, "def": CATALOG[id]})
	out.sort_custom(func(a, b): return str(a.get("id")) < str(b.get("id")))
	return out


func use_item(id: String) -> Dictionary:
	## {ok, msg, heal, dust, sold}
	if id == "" or not has_item(id):
		return {"ok": false, "msg": "沒有這個道具。"}
	var def: Dictionary = catalog(id)
	var kind := str(def.get("kind", ""))
	match kind:
		"consumable":
			if not remove_item(id, 1):
				return {"ok": false, "msg": "使用失敗。"}
			var msg_parts: PackedStringArray = []
			var healed := 0
			if def.has("heal"):
				var h: int = int(def.get("heal", 0))
				var max_h: int = GameState.effective_max_hp()
				var before: int = GameState.hp
				GameState.hp = mini(max_h, GameState.hp + h)
				healed = GameState.hp - before
				msg_parts.append("HP +%d" % healed)
			if def.has("dust"):
				var d: int = int(def.get("dust", 0))
				GameState.add_stardust(d)
				msg_parts.append("星屑 +%d" % d)
			var res := {
				"ok": true,
				"msg": "使用【%s】%s" % [str(def.get("name", id)), " · ".join(msg_parts)],
				"heal": healed,
				"id": id,
			}
			item_used.emit(id, res)
			return res
		"material":
			## 賣出 1 個
			var sell: int = int(def.get("sell", 1))
			if not remove_item(id, 1):
				return {"ok": false, "msg": "賣出失敗。"}
			GameState.add_gold(sell)
			var res2 := {
				"ok": true,
				"msg": "賣出【%s】· 金 +%d" % [str(def.get("name", id)), sell],
				"sold": sell,
				"id": id,
			}
			item_used.emit(id, res2)
			return res2
		"key":
			return {"ok": false, "msg": "【%s】是重要物品，不能消耗。" % str(def.get("name", id))}
		_:
			return {"ok": false, "msg": "無法使用。"}


func use_hotbar_slot(slot: int) -> Dictionary:
	ensure_hotbar()
	if slot < 0 or slot >= HOTBAR_SIZE:
		return {"ok": false, "msg": ""}
	var id := str(GameState.hotbar[slot])
	if id == "":
		return {"ok": false, "msg": ""}
	return use_item(id)


func grant_starter() -> void:
	## 新遊戲／教學後
	if GameState.has_flag("inv.starter_given"):
		return
	add_item("hp_s", 3)
	add_item("bread", 2)
	GameState.set_flag("inv.starter_given", true)


func roll_skirmish_loot(mode: String) -> Array:
	## 回傳 [{id, n, msg}]
	var drops: Array = []
	var r := randf()
	if r < 0.45:
		drops.append({"id": "hp_s", "n": 1})
	elif r < 0.65:
		drops.append({"id": "bread", "n": 1})
	match mode:
		"ash_rat", "road_bandit":
			if randf() < 0.5:
				drops.append({"id": "wolf_fang", "n": 1})
		"fog_shade", "bamboo_spirit":
			if randf() < 0.45:
				drops.append({"id": "mist_shard", "n": 1})
		"coast_raider", "sewer_slime":
			if randf() < 0.45:
				drops.append({"id": "sea_shell", "n": 1})
		"scar_wisp", "forest_sprite":
			if randf() < 0.4:
				drops.append({"id": "scar_ember" if mode == "scar_wisp" else "dust_crumb", "n": 1})
		_:
			if randf() < 0.3:
				drops.append({"id": "dust_crumb", "n": 1})
	return drops


func apply_drops(drops: Array) -> String:
	var parts: PackedStringArray = []
	for d in drops:
		var id := str(d.get("id", ""))
		var n := int(d.get("n", 1))
		if add_item(id, n):
			parts.append("%s×%d" % [item_name(id), n])
	if parts.is_empty():
		return ""
	return "獲得 " + "、".join(parts)
