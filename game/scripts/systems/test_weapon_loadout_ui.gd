extends SceneTree
## 無頭：武器欄裝填／卸下／作用中切換（裝備系統 API）


func _initialize() -> void:
	print("== 測試武器欄 UI API ==")
	var gs = root.get_node_or_null("GameState")
	var eq = root.get_node_or_null("EquipmentSystem")
	if gs == null or eq == null:
		push_error("autoload missing")
		quit(1)
		return
	gs.reset_new_game()
	eq._ensure_state()
	gs.level = 16  ## 三欄全開

	var w1: Dictionary = eq.roll_instance("meager_blade") if eq.has_method("roll_instance") else {}
	## 若 base 不存在，造假實例
	if w1.is_empty() or str(w1.get("slot", "")) != "weapon":
		w1 = {
			"uid": "tw1", "base_id": "test", "name": "測劍", "slot": "weapon",
			"tier": 1, "line": "sword", "quality": "common", "quality_label": "凡",
			"rolled": {"atk": 8, "def": 0, "hp": 0, "crit": 0, "crit_dmg": 0},
		}
	else:
		w1["uid"] = "tw1"
		w1["line"] = "sword"
		w1["name"] = "測劍"
	var w2 := w1.duplicate(true)
	w2["uid"] = "tw2"
	w2["line"] = "axe"
	w2["name"] = "測斧"
	w2["rolled"] = {"atk": 12, "def": 0, "hp": 0, "crit": 0, "crit_dmg": 0}

	gs.equip_bag = [w1, w2]
	gs.equip_worn = {}
	gs.weapon_loadout = ["", "", ""]
	gs.weapon_loadout_active = 0
	gs.equip_slots["weapon"] = ""

	var r1: Dictionary = eq.equip_weapon_to_loadout("tw1", 0)
	assert(bool(r1.get("ok", false)), "裝欄0應成功 %s" % r1)
	assert(str(gs.weapon_loadout[0]) == "tw1", "欄0應為 tw1")
	assert(str(gs.equip_slots.get("weapon", "")) == "tw1", "mirror weapon")
	assert(str(gs.path_style) == "sword", "path 應跟 line")

	var r2: Dictionary = eq.equip_weapon_to_loadout("tw2", 1)
	assert(bool(r2.get("ok", false)), "裝欄1應成功")
	assert(str(gs.weapon_loadout[1]) == "tw2", "欄1 斧")

	var sw: Dictionary = eq.switch_weapon_loadout(1)
	assert(bool(sw.get("ok", false)), "切作用中應成功")
	assert(int(gs.weapon_loadout_active) == 1, "active=1")
	assert(str(gs.path_style) == "axe", "path=axe")
	assert(str(gs.equip_slots.get("weapon", "")) == "tw2", "mirror=斧")

	var snap: Array = eq.loadout_snapshot_for_battle()
	assert(snap.size() == 3, "snapshot 3")
	assert(bool(snap[1].get("active", false)), "snap active 1")

	var ue: Dictionary = eq.unequip_loadout_slot(1)
	assert(bool(ue.get("ok", false)), "卸欄1")
	assert(str(gs.weapon_loadout[1]) == "", "欄1空")
	## 卸作用中後應跳回仍有武的欄0
	assert(str(gs.weapon_loadout[0]) == "tw1", "欄0仍在")
	assert(int(gs.weapon_loadout_active) == 0, "active 回到 0")

	## Lv 鎖
	gs.level = 5
	var blocked: Dictionary = eq.equip_weapon_to_loadout("tw2", 2)
	assert(not bool(blocked.get("ok", true)), "Lv5 不可裝第3欄")

	print("WEAPON_LOADOUT_UI_OK")
	quit(0)
