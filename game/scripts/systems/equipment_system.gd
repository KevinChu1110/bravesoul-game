extends Node
## 裝備實例：素質浮動 roll 一次鎖定。
## Autoload：EquipmentSystem

signal equipment_changed

const SLOTS: Array[String] = ["weapon", "armor", "accessory"]


func _ready() -> void:
	_ensure_state()


func _ensure_state() -> void:
	if GameState.equip_bag == null:
		GameState.equip_bag = []
	if GameState.equip_slots == null:
		GameState.equip_slots = {"weapon": "", "armor": "", "accessory": ""}
	for s in SLOTS:
		if not GameState.equip_slots.has(s):
			GameState.equip_slots[s] = ""


func _uid() -> String:
	return "eq_%d_%d" % [Time.get_unix_time_from_system(), randi() % 99999]


func base_def(base_id: String) -> Dictionary:
	var bases: Dictionary = DataTables.equip_bases()
	return bases.get(base_id, {}) as Dictionary


func roll_instance(base_id: String, quality: String = "", rng: RandomNumberGenerator = null) -> Dictionary:
	_ensure_state()
	var def: Dictionary = base_def(base_id)
	if def.is_empty():
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if quality == "" or not DataTables.equip_qualities().has(quality):
		quality = _roll_quality(rng)
	var qdef: Dictionary = DataTables.equip_qualities().get(quality, {})
	var bonus := float(qdef.get("roll_bonus", 0.0))
	var base_stats: Dictionary = def.get("base", {})
	var ranges: Dictionary = DataTables.float_ranges()
	var rolled: Dictionary = {}
	for k in ["atk", "def", "hp", "crit", "crit_dmg"]:
		var base_v := float(base_stats.get(k, 0))
		if absf(base_v) < 0.001:
			rolled[k] = 0.0
			continue
		var fr: Dictionary = ranges.get(k, {"min_ratio": 0.9, "max_ratio": 1.1})
		var lo := float(fr.get("min_ratio", 0.9)) * (1.0 + bonus * 0.5)
		var hi := float(fr.get("max_ratio", 1.1)) * (1.0 + bonus)
		var ratio := rng.randf_range(lo, hi)
		if k in ["crit", "crit_dmg"]:
			rolled[k] = snappedf(base_v * ratio, 0.1)
		else:
			rolled[k] = float(maxi(0, int(round(base_v * ratio))))
	var inst := {
		"uid": _uid(),
		"base_id": base_id,
		"name": str(def.get("name", base_id)),
		"slot": str(def.get("slot", "weapon")),
		"tier": int(def.get("tier", 1)),
		"line": str(def.get("line", "")),
		"quality": quality,
		"quality_label": str(qdef.get("label", quality)),
		"rolled": rolled,
		"bound": false,
	}
	return inst


func _roll_quality(rng: RandomNumberGenerator) -> String:
	var qs: Dictionary = DataTables.equip_qualities()
	var total := 0
	for k in qs.keys():
		total += int((qs[k] as Dictionary).get("weight", 1))
	if total <= 0:
		return "common"
	var r := rng.randi_range(1, total)
	var acc := 0
	for k in qs.keys():
		acc += int((qs[k] as Dictionary).get("weight", 1))
		if r <= acc:
			return str(k)
	return "common"


func add_to_bag(inst: Dictionary) -> bool:
	_ensure_state()
	if inst.is_empty() or str(inst.get("uid", "")) == "":
		return false
	GameState.equip_bag.append(inst)
	equipment_changed.emit()
	if Engine.get_main_loop() is SceneTree:
		var gl: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameLog")
		if gl and gl.has_method("info"):
			gl.call("info", "equip", "獲得裝備【%s】（%s）" % [inst.get("name", ""), inst.get("quality_label", "")], {"uid": inst.get("uid")})
	return true


func find_bag(uid: String) -> Dictionary:
	_ensure_state()
	for e in GameState.equip_bag:
		if str(e.get("uid", "")) == uid:
			return e
	return {}


func find_any(uid: String) -> Dictionary:
	var b := find_bag(uid)
	if not b.is_empty():
		return b
	for s in SLOTS:
		var u := str(GameState.equip_slots.get(s, ""))
		if u == uid:
			return _equipped_lookup(uid)
	return {}


func _equipped_lookup(uid: String) -> Dictionary:
	## 裝備中的也存在 bag 或 slots 旁的 cache；簡化：bag 含未裝，裝上的移出 bag 存 slots 旁
	if GameState.equip_worn.has(uid):
		return GameState.equip_worn[uid]
	return {}


func equip(uid: String) -> Dictionary:
	_ensure_state()
	var inst := find_bag(uid)
	if inst.is_empty():
		return {"ok": false, "msg": "背包沒有此裝。"}
	var slot := str(inst.get("slot", "weapon"))
	if slot not in SLOTS:
		return {"ok": false, "msg": "未知部位。"}
	## 卸下舊的
	var old_uid := str(GameState.equip_slots.get(slot, ""))
	if old_uid != "":
		unequip(slot)
	## 從 bag 移除並 worn
	_remove_from_bag(uid)
	GameState.equip_worn[uid] = inst
	GameState.equip_slots[slot] = uid
	_sync_legacy_weapon()
	equipment_changed.emit()
	SaveManager.save_game()
	return {"ok": true, "msg": "裝備【%s】" % inst.get("name", "")}


func unequip(slot: String) -> Dictionary:
	_ensure_state()
	var uid := str(GameState.equip_slots.get(slot, ""))
	if uid == "":
		return {"ok": false, "msg": "該部位無裝備。"}
	var inst: Dictionary = GameState.equip_worn.get(uid, {})
	GameState.equip_slots[slot] = ""
	GameState.equip_worn.erase(uid)
	if not inst.is_empty():
		GameState.equip_bag.append(inst)
	_sync_legacy_weapon()
	equipment_changed.emit()
	SaveManager.save_game()
	return {"ok": true, "msg": "已卸下"}


func _remove_from_bag(uid: String) -> void:
	var next: Array = []
	for e in GameState.equip_bag:
		if str(e.get("uid", "")) != uid:
			next.append(e)
	GameState.equip_bag = next


func _sync_legacy_weapon() -> void:
	## 兼容舊 weapon_name / weapon_atk
	var wuid := str(GameState.equip_slots.get("weapon", ""))
	if wuid == "" or not GameState.equip_worn.has(wuid):
		return
	var w: Dictionary = GameState.equip_worn[wuid]
	var r: Dictionary = w.get("rolled", {})
	GameState.weapon_name = str(w.get("name", GameState.weapon_name))
	GameState.weapon_atk = int(r.get("atk", 0))
	GameState.weapon_tier = maxi(GameState.weapon_tier, int(w.get("tier", 1)))


func bonus_totals() -> Dictionary:
	_ensure_state()
	var t := {"atk": 0, "def": 0, "hp": 0, "crit": 0.0, "crit_dmg": 0.0}
	for s in SLOTS:
		var uid := str(GameState.equip_slots.get(s, ""))
		if uid == "" or not GameState.equip_worn.has(uid):
			continue
		var r: Dictionary = (GameState.equip_worn[uid] as Dictionary).get("rolled", {})
		t["atk"] = int(t["atk"]) + int(r.get("atk", 0))
		t["def"] = int(t["def"]) + int(r.get("def", 0))
		t["hp"] = int(t["hp"]) + int(r.get("hp", 0))
		t["crit"] = float(t["crit"]) + float(r.get("crit", 0))
		t["crit_dmg"] = float(t["crit_dmg"]) + float(r.get("crit_dmg", 0))
	return t


func label(inst: Dictionary) -> String:
	if inst.is_empty():
		return "（空）"
	var r: Dictionary = inst.get("rolled", {})
	return "%s〔%s〕攻%d 防%d 暴%.0f%%" % [
		inst.get("name", "?"),
		inst.get("quality_label", ""),
		int(r.get("atk", 0)),
		int(r.get("def", 0)),
		float(r.get("crit", 0)),
	]


func status_bbcode() -> String:
	_ensure_state()
	var lines: PackedStringArray = []
	lines.append("[b]裝備[/b]（素質於獲得時浮動鎖定）")
	var b := bonus_totals()
	lines.append("總加成：攻+%d 防+%d 血+%d 暴擊+%.1f 暴傷+%.1f" % [
		int(b.atk), int(b.def), int(b.hp), float(b.crit), float(b.crit_dmg)
	])
	for s in SLOTS:
		var uid := str(GameState.equip_slots.get(s, ""))
		var name_s := s
		match s:
			"weapon":
				name_s = "武器"
			"armor":
				name_s = "防具"
			"accessory":
				name_s = "飾品"
		if uid != "" and GameState.equip_worn.has(uid):
			lines.append("· %s：%s" % [name_s, label(GameState.equip_worn[uid])])
		else:
			lines.append("· %s：—" % name_s)
	lines.append("")
	lines.append("背包裝備 %d 件" % GameState.equip_bag.size())
	return "\n".join(lines)


func migrate_line(line: String) -> String:
	## 舊 soul/iron 裝備線對齊十流派 id（與 path_style migration 一致）
	match line:
		"soul":
			return "magic"
		"iron":
			return "hammer"
		_:
			return line


func line_display(line: String) -> String:
	var L := migrate_line(line)
	match L:
		"sword":
			return "劍"
		"bow":
			return "弓"
		"magic":
			return "法"
		"fist":
			return "拳"
		"axe":
			return "斧"
		"hammer":
			return "鎚"
		"spear":
			return "槍"
		"gun":
			return "火槍"
		"dart":
			return "鏢"
		"crystal":
			return "水晶"
		"soul":
			return "星途"
		"iron":
			return "鐵骨"
		_:
			return "通用"


func can_craft(recipe: Dictionary) -> Dictionary:
	## {ok, msg}
	var base_id := str(recipe.get("base_id", ""))
	var def := base_def(base_id)
	if def.is_empty():
		return {"ok": false, "msg": "未知配方。"}
	var need_tier := int(recipe.get("need_tier", 1))
	if GameState.weapon_tier < need_tier and not GameState.has_flag("c1_forged"):
		return {"ok": false, "msg": "先完成釘釘初鍛。"}
	if GameState.weapon_tier < need_tier:
		return {"ok": false, "msg": "器階不足（需 T%d+）" % need_tier}
	var gold_n := int(recipe.get("gold", 0))
	if GameState.gold < gold_n:
		return {"ok": false, "msg": "金幣不足（需 %d）" % gold_n}
	var mats: Dictionary = recipe.get("mats", {})
	for mid in mats.keys():
		var need := int(mats[mid])
		if not InventorySystem.has_item(str(mid), need):
			return {"ok": false, "msg": "缺材料：%s ×%d" % [InventorySystem.item_name(str(mid)), need]}
	return {"ok": true, "msg": "可鍛"}


func craft(recipe: Dictionary) -> Dictionary:
	var chk := can_craft(recipe)
	if not bool(chk.get("ok", false)):
		return chk
	var gold_n := int(recipe.get("gold", 0))
	var mats: Dictionary = recipe.get("mats", {})
	for mid in mats.keys():
		if not InventorySystem.remove_item(str(mid), int(mats[mid])):
			return {"ok": false, "msg": "扣材料失敗。"}
	GameState.add_gold(-gold_n)
	var base_id := str(recipe.get("base_id", ""))
	## 流派對應線品質略升（soul/iron 舊線會 migrate 後再比）
	var q := ""
	var line := migrate_line(str(base_def(base_id).get("line", "")))
	var path_line := migrate_line(str(GameState.path_style))
	if line != "" and line == path_line and randf() < 0.35:
		q = "uncommon"
	var inst := roll_instance(base_id, q)
	if inst.is_empty():
		return {"ok": false, "msg": "鍛造失敗（定義錯誤）。"}
	add_to_bag(inst)
	## 自動裝備武器（若是武器槽）
	var auto := ""
	if str(inst.get("slot", "")) == "weapon":
		var er := equip(str(inst.get("uid", "")))
		if bool(er.get("ok", false)):
			auto = " · 已裝備"
	if Engine.get_main_loop() is SceneTree:
		var qs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("QuestSystem")
		if qs and qs.has_method("track_day"):
			qs.call("track_day", "craft", 1)
	SaveManager.save_game()
	if AudioManager and AudioManager.has_method("play_craft_success"):
		AudioManager.play_craft_success()
	return {
		"ok": true,
		"inst": inst,
		"msg": "鍛成【%s】%s" % [label(inst), auto],
	}


func recipe_line(recipe: Dictionary) -> String:
	var base_id := str(recipe.get("base_id", ""))
	var def := base_def(base_id)
	var nm := str(def.get("name", base_id))
	var line := line_display(str(def.get("line", "")))
	var gold_n := int(recipe.get("gold", 0))
	var mats: Dictionary = recipe.get("mats", {})
	var parts: PackedStringArray = []
	for mid in mats.keys():
		parts.append("%s×%d" % [InventorySystem.item_name(str(mid)), int(mats[mid])])
	var ok := bool(can_craft(recipe).get("ok", false))
	var mark := "✓" if ok else "·"
	## 中高階配方是主 sink：金幣欄加「需」字，方便玩家對帳
	var gold_s := "需 %d 金" % gold_n if gold_n >= 150 else "%d 金" % gold_n
	var have := GameState.gold
	var afford := "夠" if have >= gold_n else "差 %d" % (gold_n - have)
	return "%s [%s] %s  %s（%s）· %s  %s" % [mark, line, nm, gold_s, afford, "、".join(parts), str(recipe.get("hint", ""))]


## 掉落：依機率 roll 裝備進背包
func try_drop_loot(force_id: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base_id := force_id
	if base_id == "":
		var keys: Array = DataTables.equip_bases().keys()
		if keys.is_empty():
			return {"ok": false}
		base_id = str(keys[rng.randi() % keys.size()])
	var inst := roll_instance(base_id, "", rng)
	if inst.is_empty():
		return {"ok": false}
	add_to_bag(inst)
	return {"ok": true, "inst": inst, "msg": "獲得 %s" % label(inst)}
