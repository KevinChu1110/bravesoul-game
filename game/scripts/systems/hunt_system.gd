extends Node
## 狩獵場：單人波次、每日有獎 cap。後期可接多人房。
## Autoload：HuntSystem

const DAILY_CAP := 5
const PRACTICE_GOLD_MULT := 0.35

## 三波敵人（WorldContent mode）
const WAVES: Array[Dictionary] = [
	{"mode": "ash_rat", "label": "第一波 · 灰燼鼠潮"},
	{"mode": "road_bandit", "label": "第二波 · 溢地殘兵"},
	{"mode": "scar_wisp", "label": "第三波 · 焰靈"},
]


func _ready() -> void:
	pass


func _fk(suffix: String) -> String:
	return "hunt.%s" % suffix


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func _refresh_daily() -> void:
	var today := today_key()
	if str(GameState.get_flag(_fk("day"), "")) != today:
		GameState.set_flag(_fk("day"), today)
		GameState.set_flag(_fk("runs_today"), 0)


func runs_today() -> int:
	_refresh_daily()
	return int(GameState.get_flag(_fk("runs_today"), 0))


func daily_left() -> int:
	return maxi(0, DAILY_CAP - runs_today())


func is_unlocked() -> bool:
	return GameState.has_flag("c1_entered_city") or GameState.chapter != "c0" \
		or GameState.has_flag("c0_first_battle")


func is_run_active() -> bool:
	return bool(GameState.get_flag(_fk("active"), false))


func current_wave() -> int:
	return int(GameState.get_flag(_fk("wave"), 0))


func is_practice() -> bool:
	return bool(GameState.get_flag(_fk("practice"), false))


func status_bbcode() -> String:
	_refresh_daily()
	var lines: PackedStringArray = []
	lines.append("[b]星途獵場[/b]")
	lines.append("黑焰溢地的邊陲。主線不經此處——只為鍛鍊與材料。")
	lines.append("")
	if not is_unlocked():
		lines.append("（進入騎士堡後解鎖）")
		return "\n".join(lines)
	lines.append("今日有獎場次：%d／%d（剩餘 %d）" % [runs_today(), DAILY_CAP, daily_left()])
	lines.append("每場：3 波雜魚。通關發材料與金。")
	if is_run_active():
		lines.append("[color=#c96]進行中：第 %d／%d 波[/color]" % [current_wave() + 1, WAVES.size()])
	lines.append("")
	lines.append("掉落：溢皮、焰骨、溢核（可賣；未來市集可交易）")
	return "\n".join(lines)


## 開始一場（有獎或練習）
func start_run(force_practice: bool = false) -> Dictionary:
	if not is_unlocked():
		return {"ok": false, "msg": "尚未解鎖狩獵場。"}
	if is_run_active():
		return {"ok": false, "msg": "已有進行中的狩獵。請先打完或放棄。"}
	_refresh_daily()
	var practice := force_practice or daily_left() <= 0
	GameState.set_flag(_fk("active"), true)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), practice)
	GameState.set_flag(_fk("waves_cleared"), 0)
	SaveManager.save_game()
	var msg := "狩獵開始（練習·獎勵減少）。" if practice else "狩獵開始（有獎）。"
	return {
		"ok": true,
		"practice": practice,
		"mode": str(WAVES[0].get("mode", "ash_rat")),
		"label": str(WAVES[0].get("label", "第一波")),
		"msg": msg,
	}


func abandon_run() -> void:
	GameState.set_flag(_fk("active"), false)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), false)
	SaveManager.save_game()


func wave_label(index: int = -1) -> String:
	var i := current_wave() if index < 0 else index
	if i < 0 or i >= WAVES.size():
		return ""
	return str(WAVES[i].get("label", "波次"))


func wave_mode(index: int = -1) -> String:
	var i := current_wave() if index < 0 else index
	if i < 0 or i >= WAVES.size():
		return "ash_rat"
	return str(WAVES[i].get("mode", "ash_rat"))


## 勝利一波：回傳 {ok, finished, next_mode?, next_label?, loot_msg, msg}
func on_wave_won() -> Dictionary:
	if not is_run_active():
		return {"ok": false, "msg": "沒有進行中的狩獵。"}
	var w := current_wave()
	var cleared := int(GameState.get_flag(_fk("waves_cleared"), 0)) + 1
	GameState.set_flag(_fk("waves_cleared"), cleared)
	## 波次小掉落
	var mid_loot := _roll_wave_loot(false)
	if w + 1 >= WAVES.size():
		## 通關整場
		var fin := _finish_run(true)
		fin["wave_loot"] = mid_loot
		return fin
	GameState.set_flag(_fk("wave"), w + 1)
	SaveManager.save_game()
	var nw := w + 1
	return {
		"ok": true,
		"finished": false,
		"next_mode": wave_mode(nw),
		"next_label": wave_label(nw),
		"loot_msg": mid_loot,
		"msg": "擊破！%s" % wave_label(nw),
	}


func on_wave_lost() -> Dictionary:
	if not is_run_active():
		return {"ok": false, "msg": ""}
	var cleared := int(GameState.get_flag(_fk("waves_cleared"), 0))
	var pity := ""
	if cleared > 0 and not is_practice():
		pity = _grant_items({"hunt_hide": 1})
	abandon_run()
	var msg := "狩獵中斷。"
	if pity != "":
		msg += " 保底：%s" % pity
	return {"ok": true, "msg": msg, "loot_msg": pity}


func _finish_run(full_clear: bool) -> Dictionary:
	var practice := is_practice()
	if full_clear and not practice:
		_refresh_daily()
		GameState.set_flag(_fk("runs_today"), runs_today() + 1)
		GameState.set_flag(_fk("clears_total"), int(GameState.get_flag(_fk("clears_total"), 0)) + 1)
	var gold_n := 40 + int(GameState.get_flag(_fk("waves_cleared"), 0)) * 12
	if practice:
		gold_n = int(gold_n * PRACTICE_GOLD_MULT)
	GameState.add_gold(gold_n)
	var loot_msg := _roll_wave_loot(true)
	if not practice and full_clear:
		## 通關加碼
		var extra := _grant_items({"hunt_bone": 1})
		if randf() < 0.35:
			extra += _grant_items({"hunt_core": 1})
		if randf() < 0.4:
			InventorySystem.add_item("hp_s", 1)
			extra += " 小紅水×1"
		loot_msg = (loot_msg + " " + extra).strip_edges()
	elif practice and full_clear:
		loot_msg = _grant_items({"hunt_hide": 1})
	GameState.set_flag(_fk("active"), false)
	GameState.set_flag(_fk("wave"), 0)
	GameState.set_flag(_fk("practice"), false)
	## 每日探索
	if Engine.get_main_loop() is SceneTree:
		var er: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EventRuntime")
		if er and er.has_method("mark_explore_daily"):
			er.call("mark_explore_daily")
	SaveManager.save_game()
	return {
		"ok": true,
		"finished": true,
		"gold": gold_n,
		"loot_msg": loot_msg,
		"msg": "狩獵完成！金 +%d。%s" % [gold_n, loot_msg],
		"practice": practice,
	}


func _roll_wave_loot(finale: bool) -> String:
	var bag: Dictionary = {}
	if randf() < (0.7 if finale else 0.45):
		bag["hunt_hide"] = 1 + (1 if finale and randf() < 0.3 else 0)
	if finale and randf() < 0.55:
		bag["hunt_bone"] = 1
	if finale and randf() < 0.2:
		bag["hunt_core"] = 1
	if is_practice():
		## 練習大砍
		if bag.has("hunt_core"):
			bag.erase("hunt_core")
		if bag.has("hunt_bone") and randf() < 0.5:
			bag.erase("hunt_bone")
	return _grant_items(bag)


func _grant_items(bag: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in bag.keys():
		var n := int(bag[id])
		if n <= 0:
			continue
		if InventorySystem.add_item(str(id), n):
			parts.append("%s×%d" % [InventorySystem.item_name(str(id)), n])
	if parts.is_empty():
		return ""
	return "獲得 " + "、".join(parts)


## NPC 回收價（假市集）
func recycle_price(item_id: String) -> int:
	match item_id:
		"hunt_hide":
			return 10
		"hunt_bone":
			return 22
		"hunt_core":
			return 60
		_:
			var def: Dictionary = InventorySystem.catalog(item_id)
			return int(def.get("sell", 0))


func recycle_one(item_id: String) -> Dictionary:
	var price := recycle_price(item_id)
	if price <= 0:
		return {"ok": false, "msg": "此物不收。"}
	if not InventorySystem.has_item(item_id, 1):
		return {"ok": false, "msg": "沒有此物。"}
	InventorySystem.remove_item(item_id, 1)
	GameState.add_gold(price)
	SaveManager.save_game()
	return {"ok": true, "msg": "回收【%s】· 金 +%d" % [InventorySystem.item_name(item_id), price]}
