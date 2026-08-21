extends Node
## 裝備實例：素質浮動 roll 一次鎖定。
## Autoload：EquipmentSystem

signal equipment_changed

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

## 武器／防具＋原作飾品六槽（戒指／項鍊／手環／耳環／護符／腰帶）
const SLOTS: Array[String] = [
	"weapon", "armor",
	"ring", "necklace", "bracelet", "earring", "amulet", "belt",
]
const ACCESSORY_SLOTS: Array[String] = [
	"ring", "necklace", "bracelet", "earring", "amulet", "belt",
]
const ACCESSORY_LEVEL_REQ := 15
## 舊單一 accessory 槽 → 戒指
const LEGACY_ACCESSORY_TO := "ring"

## 真正多武器欄（原作升級解鎖；第 1 欄開局、第 2 欄 Lv10、第 3 欄 Lv16）
const WEAPON_LOADOUT_SIZE := 3
const WEAPON_LOADOUT_LEVEL_REQ := [1, 10, 16]



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _ready() -> void:
	_ensure_state()


func _ensure_state() -> void:
	if GameState.equip_bag == null:
		GameState.equip_bag = []
	if GameState.equip_slots == null:
		GameState.equip_slots = {}
	## 舊檔只有 accessory：搬到戒指
	if GameState.equip_slots.has("accessory"):
		var legacy := str(GameState.equip_slots.get("accessory", ""))
		if legacy != "" and str(GameState.equip_slots.get(LEGACY_ACCESSORY_TO, "")) == "":
			GameState.equip_slots[LEGACY_ACCESSORY_TO] = legacy
		GameState.equip_slots.erase("accessory")
	for s in SLOTS:
		if not GameState.equip_slots.has(s):
			GameState.equip_slots[s] = ""
	_ensure_weapon_loadout()


func _ensure_weapon_loadout() -> void:
	if GameState.weapon_loadout == null or typeof(GameState.weapon_loadout) != TYPE_ARRAY:
		GameState.weapon_loadout = ["", "", ""]
	while GameState.weapon_loadout.size() < WEAPON_LOADOUT_SIZE:
		GameState.weapon_loadout.append("")
	if GameState.weapon_loadout.size() > WEAPON_LOADOUT_SIZE:
		GameState.weapon_loadout.resize(WEAPON_LOADOUT_SIZE)
	GameState.weapon_loadout_active = clampi(int(GameState.weapon_loadout_active), 0, WEAPON_LOADOUT_SIZE - 1)
	## 若欄全空但 equip_slots.weapon 有值，灌進第 0 欄
	var any := false
	for i in WEAPON_LOADOUT_SIZE:
		if str(GameState.weapon_loadout[i]) != "":
			any = true
			break
	var wuid := str(GameState.equip_slots.get("weapon", ""))
	if not any and wuid != "":
		GameState.weapon_loadout[0] = wuid
		GameState.weapon_loadout_active = 0


func loadout_slot_unlocked(index: int) -> bool:
	if index < 0 or index >= WEAPON_LOADOUT_SIZE:
		return false
	var need := int(WEAPON_LOADOUT_LEVEL_REQ[index])
	return GameState.level >= need


func loadout_unlock_level(index: int) -> int:
	if index < 0 or index >= WEAPON_LOADOUT_SIZE:
		return 999
	return int(WEAPON_LOADOUT_LEVEL_REQ[index])


func active_loadout_index() -> int:
	_ensure_state()
	return clampi(int(GameState.weapon_loadout_active), 0, WEAPON_LOADOUT_SIZE - 1)


func loadout_uid(index: int) -> String:
	_ensure_state()
	if index < 0 or index >= GameState.weapon_loadout.size():
		return ""
	return str(GameState.weapon_loadout[index])


func weapon_inst(uid: String) -> Dictionary:
	if uid == "" or not GameState.equip_worn.has(uid):
		return {}
	return GameState.equip_worn[uid] as Dictionary


func active_weapon_inst() -> Dictionary:
	return weapon_inst(loadout_uid(active_loadout_index()))


func active_weapon_line() -> String:
	var inst := active_weapon_inst()
	var line := str(inst.get("line", ""))
	if line != "":
		return line
	return str(GameState.path_style)


## 把武器裝進指定欄（須已解鎖）。會從背包取出；原欄武器回背包。
func equip_weapon_to_loadout(uid: String, index: int = -1) -> Dictionary:
	_ensure_state()
	var inst := find_bag(uid)
	## 也可能已在另一欄／worn
	if inst.is_empty() and GameState.equip_worn.has(uid):
		inst = GameState.equip_worn[uid]
	if inst.is_empty():
		return {"ok": false, "msg": _t("背包沒有此裝。")}
	if normalize_slot(str(inst.get("slot", "weapon"))) != "weapon":
		return {"ok": false, "msg": _t("只能把武器放進武器欄。")}
	var idx := index
	if idx < 0:
		idx = active_loadout_index()
	if not loadout_slot_unlocked(idx):
		return {"ok": false, "msg": _t("武器欄 %d 需達到 Lv%d。") % [idx + 1, loadout_unlock_level(idx)]}
	## 若已在其他欄，先清掉那個 index
	for i in WEAPON_LOADOUT_SIZE:
		if str(GameState.weapon_loadout[i]) == uid:
			GameState.weapon_loadout[i] = ""
	## 原欄有武 → 回背包（若仍 worn）
	var old_uid := str(GameState.weapon_loadout[idx])
	if old_uid != "" and old_uid != uid:
		_unequip_weapon_uid(old_uid)
	## 從 bag 移到 worn
	if find_bag(uid).is_empty() == false:
		_remove_from_bag(uid)
	GameState.equip_worn[uid] = inst
	GameState.weapon_loadout[idx] = uid
	GameState.weapon_loadout_active = idx
	_sync_active_weapon_mirror()
	equipment_changed.emit()
	SaveManager.save_game()
	return {"ok": true, "msg": _t("武器欄 %d：【%s】") % [idx + 1, inst.get("name", "")]}


## 戰鬥外切換作用中武器欄（同步 path_style／面板攻擊）
func switch_weapon_loadout(index: int) -> Dictionary:
	_ensure_state()
	if not loadout_slot_unlocked(index):
		return {"ok": false, "msg": _t("武器欄 %d 需達到 Lv%d。") % [index + 1, loadout_unlock_level(index)]}
	var uid := loadout_uid(index)
	if uid == "":
		return {"ok": false, "msg": _t("武器欄 %d 是空的。") % [index + 1]}
	GameState.weapon_loadout_active = index
	_sync_active_weapon_mirror()
	equipment_changed.emit()
	SaveManager.save_game()
	var inst := weapon_inst(uid)
	return {"ok": true, "msg": _t("切換武器欄 %d：【%s】") % [index + 1, inst.get("name", "")], "line": str(inst.get("line", "")), "uid": uid}


func _unequip_weapon_uid(uid: String) -> void:
	if uid == "" or not GameState.equip_worn.has(uid):
		return
	## 若仍被其他欄引用則不卸
	for i in WEAPON_LOADOUT_SIZE:
		if str(GameState.weapon_loadout[i]) == uid:
			return
	var inst: Dictionary = GameState.equip_worn[uid]
	GameState.equip_worn.erase(uid)
	if not inst.is_empty():
		GameState.equip_bag.append(inst)


func _sync_active_weapon_mirror() -> void:
	_ensure_weapon_loadout()
	var idx := active_loadout_index()
	var uid := loadout_uid(idx)
	GameState.equip_slots["weapon"] = uid
	_sync_legacy_weapon()
	## 作用中武器決定流派（技能綁定）
	var inst := weapon_inst(uid)
	var line := str(inst.get("line", ""))
	if line != "":
		GameState.path_style = line


func loadout_snapshot_for_battle() -> Array:
	## [{index, uid, name, line, weapon_atk, unlocked, empty}]
	_ensure_state()
	var out: Array = []
	for i in WEAPON_LOADOUT_SIZE:
		var unlocked := loadout_slot_unlocked(i)
		var uid := loadout_uid(i) if unlocked else ""
		var inst := weapon_inst(uid)
		var atk := 0
		if not inst.is_empty():
			atk = int((inst.get("rolled", {}) as Dictionary).get("atk", 0))
		out.append({
			"index": i,
			"uid": uid,
			"name": str(inst.get("name", "")),
			"line": str(inst.get("line", "")),
			"weapon_atk": atk,
			"unlocked": unlocked,
			"empty": uid == "",
			"active": i == active_loadout_index(),
		})
	return out


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
		"slot": normalize_slot(str(def.get("slot", "weapon"))),
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
			gl.call("info", "equip", _t("獲得裝備【%s】（%s）") % [inst.get("name", ""), inst.get("quality_label", "")], {"uid": inst.get("uid")})
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


func normalize_slot(slot: String) -> String:
	if slot == "accessory":
		return LEGACY_ACCESSORY_TO
	return slot


func is_accessory_slot(slot: String) -> bool:
	return normalize_slot(slot) in ACCESSORY_SLOTS


func accessories_unlocked() -> bool:
	return GameState.level >= ACCESSORY_LEVEL_REQ


func equip(uid: String) -> Dictionary:
	_ensure_state()
	var inst := find_bag(uid)
	if inst.is_empty():
		return {"ok": false, "msg": _t("背包沒有此裝。")}
	var slot := normalize_slot(str(inst.get("slot", "weapon")))
	inst["slot"] = slot
	if slot not in SLOTS:
		return {"ok": false, "msg": _t("未知部位。")}
	if slot == "weapon":
		## 武器走多欄：裝進作用中欄（空則第一個已解鎖空欄）
		var idx := active_loadout_index()
		if loadout_uid(idx) != "":
			## 找第一個已解鎖空欄，否則覆寫作用中欄
			var found := -1
			for i in WEAPON_LOADOUT_SIZE:
				if loadout_slot_unlocked(i) and loadout_uid(i) == "":
					found = i
					break
			if found >= 0:
				idx = found
		return equip_weapon_to_loadout(uid, idx)
	if is_accessory_slot(slot) and not accessories_unlocked():
		return {"ok": false, "msg": _t("飾品六槽需達到 Lv%d（現 Lv%d）。") % [ACCESSORY_LEVEL_REQ, GameState.level]}
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
	return {"ok": true, "msg": _t("裝備【%s】") % inst.get("name", "")}


func unequip(slot: String) -> Dictionary:
	_ensure_state()
	slot = normalize_slot(slot)
	if slot == "weapon":
		return unequip_loadout_slot(active_loadout_index())
	var uid2 := str(GameState.equip_slots.get(slot, ""))
	if uid2 == "":
		return {"ok": false, "msg": _t("該部位無裝備。")}
	var inst2: Dictionary = GameState.equip_worn.get(uid2, {})
	GameState.equip_slots[slot] = ""
	GameState.equip_worn.erase(uid2)
	if not inst2.is_empty():
		GameState.equip_bag.append(inst2)
	_sync_legacy_weapon()
	equipment_changed.emit()
	SaveManager.save_game()
	return {"ok": true, "msg": _t("已卸下")}


## 卸下指定武器欄（不必是作用中欄）
func unequip_loadout_slot(index: int) -> Dictionary:
	_ensure_state()
	if index < 0 or index >= WEAPON_LOADOUT_SIZE:
		return {"ok": false, "msg": _t("無效的武器欄。")}
	if not loadout_slot_unlocked(index):
		return {"ok": false, "msg": _t("武器欄 %d 需達到 Lv%d。") % [index + 1, loadout_unlock_level(index)]}
	var uid := loadout_uid(index)
	if uid == "":
		return {"ok": false, "msg": _t("該武器欄是空的。")}
	GameState.weapon_loadout[index] = ""
	var still := false
	for i in WEAPON_LOADOUT_SIZE:
		if str(GameState.weapon_loadout[i]) == uid:
			still = true
			break
	var inst: Dictionary = GameState.equip_worn.get(uid, {})
	if not still:
		GameState.equip_worn.erase(uid)
		if not inst.is_empty():
			GameState.equip_bag.append(inst)
	## 若卸的是作用中欄，改指到第一個仍有武的欄
	if active_loadout_index() == index:
		var nxt := -1
		for i in WEAPON_LOADOUT_SIZE:
			if loadout_uid(i) != "":
				nxt = i
				break
		if nxt >= 0:
			GameState.weapon_loadout_active = nxt
		## else 維持 index，mirror 會清成空手
	_sync_active_weapon_mirror()
	## 全空時清 legacy 顯示
	if str(GameState.equip_slots.get("weapon", "")) == "":
		GameState.weapon_name = "空手"
		GameState.weapon_atk = 0
	equipment_changed.emit()
	SaveManager.save_game()
	return {"ok": true, "msg": _t("已卸下武器欄 %d") % [index + 1]}


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
		return _t("（空）")
	var r: Dictionary = inst.get("rolled", {})
	return _t("%s〔%s〕攻%d 防%d 暴%.0f%%") % [
		inst.get("name", "?"),
		inst.get("quality_label", ""),
		int(r.get("atk", 0)),
		int(r.get("def", 0)),
		float(r.get("crit", 0)),
	]


func status_bbcode() -> String:
	_ensure_state()
	var lines: PackedStringArray = []
	lines.append(_t("[b]裝備[/b]（素質於獲得時浮動鎖定）"))
	var b := bonus_totals()
	lines.append(_t("總加成：攻+%d 防+%d 血+%d 暴擊+%.1f 暴傷+%.1f") % [
		int(b.atk), int(b.def), int(b.hp), float(b.crit), float(b.crit_dmg)
	])
	lines.append(_t("[b]武器欄[/b]（耗盡自動切 · 2欄Lv10 · 3欄Lv16）"))
	for i in WEAPON_LOADOUT_SIZE:
		if not loadout_slot_unlocked(i):
			lines.append(_t("· 欄 %d：未解鎖（Lv%d）") % [i + 1, loadout_unlock_level(i)])
			continue
		var wuid := loadout_uid(i)
		var mark := _t("〔使用中〕") if i == active_loadout_index() and wuid != "" else ""
		if wuid != "" and GameState.equip_worn.has(wuid):
			lines.append("· %s%d%s：%s" % [_t("欄 "), i + 1, mark, label(GameState.equip_worn[wuid])])
		else:
			lines.append(_t("· 欄 %d%s：—") % [i + 1, mark])
	if not accessories_unlocked():
		lines.append(_t("飾品六槽：Lv%d 開放（戒指／項鍊／手環／耳環／護符／腰帶）") % ACCESSORY_LEVEL_REQ)
	for s in SLOTS:
		if s == "weapon":
			continue  ## 已用武器欄列出
		if is_accessory_slot(s) and not accessories_unlocked():
			continue
		var uid := str(GameState.equip_slots.get(s, ""))
		var name_s := slot_label(s)
		if uid != "" and GameState.equip_worn.has(uid):
			lines.append("· %s：%s" % [name_s, label(GameState.equip_worn[uid])])
		else:
			lines.append("· %s：—" % name_s)
	lines.append("")
	lines.append(_t("背包裝備 %d 件") % GameState.equip_bag.size())
	return "\n".join(lines)


func slot_label(slot: String) -> String:
	match normalize_slot(slot):
		"weapon":
			return _t("武器")
		"armor":
			return _t("防具")
		"ring":
			return _t("戒指")
		"necklace":
			return _t("項鍊")
		"bracelet":
			return _t("手環")
		"earring":
			return _t("耳環")
		"amulet":
			return _t("護符")
		"belt":
			return _t("腰帶")
		_:
			return slot


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
			return _t("劍")
		"bow":
			return _t("弓")
		"magic":
			return _t("法")
		"fist":
			return _t("拳")
		"axe":
			return _t("斧")
		"hammer":
			return _t("鎚")
		"spear":
			return _t("槍")
		"gun":
			return _t("火槍")
		"dart":
			return _t("鏢")
		"dagger":
			return _t("匕首")
		"claw":
			return _t("爪")
		"crystal":
			return _t("水晶")
		"common":
			return _t("通用")
		"soul":
			return _t("星途")
		"iron":
			return _t("鐵骨")
		_:
			return _t("通用")


func can_craft(recipe: Dictionary) -> Dictionary:
	## {ok, msg}
	var base_id := str(recipe.get("base_id", ""))
	var def := base_def(base_id)
	if def.is_empty():
		return {"ok": false, "msg": _t("未知配方。")}
	var need_tier := int(recipe.get("need_tier", 1))
	if GameState.weapon_tier < need_tier and not GameState.has_flag("c1_forged"):
		return {"ok": false, "msg": _t("先完成釘釘初鍛。")}
	if GameState.weapon_tier < need_tier:
		return {"ok": false, "msg": _t("器階不足（需 T%d+）") % need_tier}
	var gold_n := int(recipe.get("gold", 0))
	if GameState.gold < gold_n:
		return {"ok": false, "msg": _t("金幣不足（需 %d）") % gold_n}
	var mats: Dictionary = recipe.get("mats", {})
	for mid in mats.keys():
		var need := int(mats[mid])
		if not InventorySystem.has_item(str(mid), need):
			return {"ok": false, "msg": _t("缺材料：%s ×%d") % [InventorySystem.item_name(str(mid)), need]}
	return {"ok": true, "msg": _t("可鍛")}


func craft(recipe: Dictionary) -> Dictionary:
	var chk := can_craft(recipe)
	if not bool(chk.get("ok", false)):
		return chk
	var gold_n := int(recipe.get("gold", 0))
	var mats: Dictionary = recipe.get("mats", {})
	for mid in mats.keys():
		if not InventorySystem.remove_item(str(mid), int(mats[mid])):
			return {"ok": false, "msg": _t("扣材料失敗。")}
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
		return {"ok": false, "msg": _t("鍛造失敗（定義錯誤）。")}
	add_to_bag(inst)
	## 自動裝備武器（若是武器槽）
	var auto := ""
	if str(inst.get("slot", "")) == "weapon":
		var er := equip(str(inst.get("uid", "")))
		if bool(er.get("ok", false)):
			auto = _t(" · 已裝備")
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
		"msg": _t("鍛成【%s】%s") % [label(inst), auto],
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
	var gold_s := _t("需 %d 金") % gold_n if gold_n >= 150 else _t("%d 金") % gold_n
	var have := GameState.gold
	var afford := _t("夠") if have >= gold_n else _t("差 %d") % (gold_n - have)
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
	return {"ok": true, "inst": inst, "msg": _t("獲得 %s") % label(inst)}
