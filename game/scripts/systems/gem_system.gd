extends Node
## 寶石（原作手藝工坊）：紅／黃／藍 · 3 合 1 升階 · 最高 5 · 鑲嵌必定成功、不可取下只能替換。
## Autoload：GemSystem
## 與戰魂正交：魂＝十四星入槽；寶石＝色階％／命中迴避點。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const COLORS: PackedStringArray = ["red", "yellow", "blue"]
const COLOR_NAME := {"red": "紅寶石", "yellow": "黃寶石", "blue": "藍寶石"}
const UNLOCK_LEVEL := 10
const FURNACE_LEVEL := 20
const FURNACE_GOLD := 2500
const FURNACE_MEDALS := 50  ## 原作：未達金幣可用 50 勳章解鎖
const MAX_LEVEL := 5
const FUSE_NEED := 3
const SHARD_NEED := 3  ## 碎片熔煉 → 1 級寶石
const SOCKET_GOLD_BASE := 40
const SOCKET_GOLD_PER_LV := 25


static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)


func _ready() -> void:
	_ensure_bag()
	_ensure_shards()


func _ensure_bag() -> void:
	if GameState.gem_bag == null or typeof(GameState.gem_bag) != TYPE_ARRAY:
		GameState.gem_bag = []


func _ensure_shards() -> void:
	if GameState.gem_shards == null or typeof(GameState.gem_shards) != TYPE_DICTIONARY:
		GameState.gem_shards = {"red": 0, "yellow": 0, "blue": 0}
	for c in COLORS:
		if not GameState.gem_shards.has(c):
			GameState.gem_shards[c] = 0


func unlocked() -> bool:
	return GameState.level >= UNLOCK_LEVEL


func furnace_unlocked() -> bool:
	return bool(GameState.gem_furnace)


func medals() -> int:
	if Engine.get_main_loop() is SceneTree:
		var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
		if inv != null and inv.has_method("count"):
			return int(inv.call("count", "medal"))
	return int(GameState.inventory.get("medal", 0)) if GameState.inventory else 0


func furnace_can_unlock() -> bool:
	if not unlocked() or GameState.level < FURNACE_LEVEL or furnace_unlocked():
		return false
	return GameState.gold >= FURNACE_GOLD or medals() >= FURNACE_MEDALS


func furnace_can_unlock_gold() -> bool:
	return unlocked() and GameState.level >= FURNACE_LEVEL and not furnace_unlocked() \
		and GameState.gold >= FURNACE_GOLD


func furnace_can_unlock_medal() -> bool:
	return unlocked() and GameState.level >= FURNACE_LEVEL and not furnace_unlocked() \
		and medals() >= FURNACE_MEDALS


func unlock_furnace(pay: String = "auto") -> Dictionary:
	if furnace_unlocked():
		return {"ok": false, "msg": _t("熔爐早已點燃。")}
	if GameState.level < FURNACE_LEVEL:
		return {"ok": false, "msg": _t("熔爐需達到 Lv%d。") % FURNACE_LEVEL}
	var use_medal := false
	if pay == "medal":
		use_medal = true
	elif pay == "gold":
		use_medal = false
	else:
		## auto：金幣夠優先金幣；否則勳章
		use_medal = GameState.gold < FURNACE_GOLD
	if use_medal:
		if medals() < FURNACE_MEDALS:
			return {"ok": false, "msg": _t("勳章不足（需 %d）。") % FURNACE_MEDALS}
		var inv: Node = null
		if Engine.get_main_loop() is SceneTree:
			inv = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
		if inv != null and inv.has_method("remove_item"):
			if not bool(inv.call("remove_item", "medal", FURNACE_MEDALS)):
				return {"ok": false, "msg": _t("勳章不足（需 %d）。") % FURNACE_MEDALS}
		else:
			return {"ok": false, "msg": _t("勳章不足（需 %d）。") % FURNACE_MEDALS}
	else:
		if GameState.gold < FURNACE_GOLD:
			return {"ok": false, "msg": _t("金幣不足（需 %d）。或集滿 %d 枚勳章。") % [FURNACE_GOLD, FURNACE_MEDALS]}
		GameState.add_gold(-FURNACE_GOLD)
	GameState.gem_furnace = true
	SaveManager.save_game()
	var how := _t("勳章") if use_medal else _t("金幣")
	return {"ok": true, "msg": _t("熔爐點燃（%s）！第二條熔煉產線已開。") % how}


## 每日可熔煉次數：工坊 1 線；解鎖熔爐後 2 線（原作雙爐並行）
func smelt_lines_per_day() -> int:
	return 2 if furnace_unlocked() else 1


func _refresh_smelt_day() -> void:
	var d: Dictionary = Time.get_date_dict_from_system()
	var today := "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]
	if str(GameState.gem_smelt_day) != today:
		GameState.gem_smelt_day = today
		GameState.gem_smelt_used = 0


func smelt_left_today() -> int:
	_refresh_smelt_day()
	return maxi(0, smelt_lines_per_day() - int(GameState.gem_smelt_used))


func add_shards(color: String, qty: int = 1) -> void:
	_ensure_shards()
	if color not in COLORS or qty <= 0:
		return
	GameState.gem_shards[color] = int(GameState.gem_shards.get(color, 0)) + qty


func shard_count(color: String) -> int:
	_ensure_shards()
	return int(GameState.gem_shards.get(color, 0))


func can_smelt(color: String) -> bool:
	if not unlocked():
		return false
	if color not in COLORS:
		return false
	if smelt_left_today() <= 0:
		return false
	return shard_count(color) >= SHARD_NEED


func smelt(color: String) -> Dictionary:
	if not unlocked():
		return {"ok": false, "msg": _t("寶石工坊需達到 Lv%d。") % UNLOCK_LEVEL}
	if color not in COLORS:
		return {"ok": false, "msg": _t("未知寶石色。")}
	_refresh_smelt_day()
	if smelt_left_today() <= 0:
		var hint := _t("今日熔煉線已用完。")
		if not furnace_unlocked() and GameState.level >= FURNACE_LEVEL:
			hint += _t("（點燃熔爐可再加一條產線）")
		elif not furnace_unlocked():
			hint += _t("（Lv%d 可點燃熔爐，得第二條產線）") % FURNACE_LEVEL
		return {"ok": false, "msg": hint}
	if shard_count(color) < SHARD_NEED:
		return {"ok": false, "msg": _t("碎片不足（需 %d 個同色）。") % SHARD_NEED}
	GameState.gem_shards[color] = shard_count(color) - SHARD_NEED
	GameState.gem_smelt_used = int(GameState.gem_smelt_used) + 1
	add_gem(color, 1, 1)
	SaveManager.save_game()
	var line_note := _t("熔爐線") if furnace_unlocked() and int(GameState.gem_smelt_used) >= 2 else _t("工坊線")
	return {
		"ok": true,
		"msg": _t("熔煉成功（%s）：%s · 1 級 · 今日剩餘線 %d") % [
			line_note, color_label(color), smelt_left_today()
		],
		"color": color,
	}


func color_label(color: String) -> String:
	return _t(str(COLOR_NAME.get(color, color)))


func gem_label(g: Dictionary) -> String:
	if g.is_empty():
		return _t("（無）")
	return _t("%s · %d 級") % [color_label(str(g.get("color", ""))), int(g.get("level", 1))]


func add_gem(color: String, level: int = 1, qty: int = 1) -> void:
	_ensure_bag()
	if color not in COLORS:
		return
	level = clampi(level, 1, MAX_LEVEL)
	for _i in qty:
		GameState.gem_bag.append({
			"id": "gem_%d_%d" % [Time.get_unix_time_from_system(), randi() % 99999],
			"color": color,
			"level": level,
		})


func count_of(color: String, level: int) -> int:
	_ensure_bag()
	var n := 0
	for g in GameState.gem_bag:
		if str(g.get("color", "")) == color and int(g.get("level", 0)) == level:
			n += 1
	return n


func can_fuse(color: String, level: int) -> bool:
	if not unlocked():
		return false
	if color not in COLORS or level < 1 or level >= MAX_LEVEL:
		return false
	return count_of(color, level) >= FUSE_NEED


func fuse(color: String, level: int) -> Dictionary:
	if not can_fuse(color, level):
		return {"ok": false, "msg": _t("無法合成（需 3 顆同色同級，且未滿 5 級）。")}
	_ensure_bag()
	var removed := 0
	var next: Array = []
	for g in GameState.gem_bag:
		if removed < FUSE_NEED and str(g.get("color", "")) == color and int(g.get("level", 0)) == level:
			removed += 1
			continue
		next.append(g)
	GameState.gem_bag = next
	add_gem(color, level + 1, 1)
	SaveManager.save_game()
	return {
		"ok": true,
		"msg": _t("合成成功：%s · %d 級") % [color_label(color), level + 1],
		"color": color,
		"level": level + 1,
	}


func socket_cost(level: int) -> int:
	return SOCKET_GOLD_BASE + SOCKET_GOLD_PER_LV * maxi(0, level - 1)


## 鑲嵌到裝備 uid（武器或防具）。必定成功；已有則替換（舊寶石消失，原作不可取下）。
func socket(equip_uid: String, gem_id: String) -> Dictionary:
	if not unlocked():
		return {"ok": false, "msg": _t("寶石工坊需達到 Lv%d。") % UNLOCK_LEVEL}
	_ensure_bag()
	var inst: Dictionary = {}
	if GameState.equip_worn.has(equip_uid):
		inst = GameState.equip_worn[equip_uid]
	else:
		for e in GameState.equip_bag:
			if str(e.get("uid", "")) == equip_uid:
				inst = e
				break
	if inst.is_empty():
		return {"ok": false, "msg": _t("找不到裝備。")}
	var slot := str(inst.get("slot", ""))
	if slot != "weapon" and slot != "armor":
		return {"ok": false, "msg": _t("只能鑲在武器或防具上。")}
	var gem: Dictionary = {}
	var gem_idx := -1
	for i in GameState.gem_bag.size():
		if str(GameState.gem_bag[i].get("id", "")) == gem_id:
			gem = GameState.gem_bag[i]
			gem_idx = i
			break
	if gem.is_empty():
		return {"ok": false, "msg": _t("背包沒有這顆寶石。")}
	var lv := int(gem.get("level", 1))
	var cost := socket_cost(lv)
	if GameState.gold < cost:
		return {"ok": false, "msg": _t("金幣不足（需 %d）。") % cost}
	GameState.add_gold(-cost)
	GameState.gem_bag.remove_at(gem_idx)
	## 舊寶石替換消失（不可取下）
	inst["gem"] = {
		"color": str(gem.get("color", "")),
		"level": lv,
	}
	## 寫回 worn 或 bag
	if GameState.equip_worn.has(equip_uid):
		GameState.equip_worn[equip_uid] = inst
	else:
		for i in GameState.equip_bag.size():
			if str(GameState.equip_bag[i].get("uid", "")) == equip_uid:
				GameState.equip_bag[i] = inst
				break
	SaveManager.save_game()
	var stars := "★".repeat(clampi(lv, 1, 5))
	return {
		"ok": true,
		"msg": _t("鑲嵌成功 %s（%s）· 花費 %d 金") % [gem_label(inst["gem"]), stars, cost],
		"rating": lv,
	}


## 彙總已穿裝備上的寶石加成（給 GameState.effective_* 用）
func worn_bonuses() -> Dictionary:
	var out := {
		"atk_pct": 0.0, "def_pct": 0.0, "hp_pct": 0.0,
		"crit": 0.0, "hit": 0.0, "eva": 0.0,
	}
	var per := {
		"crit": 2.0, "hp_pct": 0.03, "atk_pct": 0.04,
		"def_pct": 0.04, "hit": 3.0, "eva": 3.0,
	}
	## 嘗試讀表
	if Engine.get_main_loop() is SceneTree:
		var dt: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DataTables")
		if dt != null:
			var root: Variant = dt.get("gems") if "gems" in dt else null
			# DataTables may not have gems yet — use constants
	for uid in GameState.equip_worn.keys():
		var inst: Dictionary = GameState.equip_worn[uid]
		var g: Variant = inst.get("gem", {})
		if typeof(g) != TYPE_DICTIONARY or (g as Dictionary).is_empty():
			continue
		var color := str(g.get("color", ""))
		var lv := clampi(int(g.get("level", 1)), 1, MAX_LEVEL)
		var slot := str(inst.get("slot", ""))
		var key := ""
		match color:
			"red":
				key = "crit" if slot == "weapon" else "hp_pct"
			"yellow":
				key = "atk_pct" if slot == "weapon" else "def_pct"
			"blue":
				key = "hit" if slot == "weapon" else "eva"
		if key == "":
			continue
		out[key] = float(out[key]) + float(per.get(key, 0.0)) * float(lv)
	return out


func grant_arena_settle_shards(tier: int) -> int:
	## 角鬥日結：依檔位給**碎片**（進熔煉產線）。原創補完數量。
	if tier <= 0:
		return 0
	var n := mini(8, 1 + tier * 2)  ## 新銳3／精銳5／菁英7／至尊8
	var colors := ["red", "yellow", "blue"]
	for i in n:
		add_shards(colors[i % 3], 1)
	return n


func status_bbcode() -> String:
	_ensure_bag()
	_ensure_shards()
	_refresh_smelt_day()
	var lines: PackedStringArray = []
	lines.append(_t("[b]手藝工坊 · 寶石[/b]"))
	if not unlocked():
		lines.append(_t("Lv%d 開放。紅＝暴擊／生命 · 黃＝攻擊／防禦 · 藍＝命中／迴避。") % UNLOCK_LEVEL)
		return "\n".join(lines)
	lines.append(_t("3 碎片→1 級寶石（熔煉）· 3 同級寶石→升階（最高 5）。鑲嵌必定成功，不可取下。"))
	## 熔爐產線
	if furnace_unlocked():
		lines.append(_t("熔爐：已點燃 · 每日熔煉線 %d／%d（雙線並行）") % [
			smelt_left_today(), smelt_lines_per_day()
		])
	else:
		lines.append(_t("熔爐：未點燃（Lv%d · %d 金 或 %d 勳章）· 今日熔煉線 %d／%d") % [
			FURNACE_LEVEL, FURNACE_GOLD, FURNACE_MEDALS, smelt_left_today(), smelt_lines_per_day()
		])
	## 碎片
	var shard_parts: PackedStringArray = []
	for c in COLORS:
		var sn := shard_count(c)
		if sn > 0:
			shard_parts.append("%s×%d" % [color_label(c), sn])
	if shard_parts.is_empty():
		lines.append(_t("碎片：—（角鬥日結／獵場有機會掉）"))
	else:
		lines.append(_t("碎片：%s") % "、".join(shard_parts))
	for c in COLORS:
		var parts: PackedStringArray = []
		for lv in range(1, MAX_LEVEL + 1):
			var n := count_of(c, lv)
			if n > 0:
				parts.append(_t("%d級×%d") % [lv, n])
		if parts.is_empty():
			lines.append("· %s：—" % color_label(c))
		else:
			lines.append("· %s：%s" % [color_label(c), "、".join(parts)])
	return "\n".join(lines)


func panel_actions_hint() -> String:
	return _t("熔煉：3 碎片→寶石。合成：3 同級升階。鑲嵌：選武器／防具。熔爐＝第二條每日產線。")
