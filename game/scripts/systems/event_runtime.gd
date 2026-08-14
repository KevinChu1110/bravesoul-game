extends Node
## 活動執行期：全年表、日曆／循環月、每日次數、活動幣、任務、商店、收攤換幣、每日三件事。
## Autoload：EventRuntime

const EVENTS_DIR := "res://data/events/"

var _events: Array = []
var _loaded: bool = false


func _ready() -> void:
	reload()


func reload() -> void:
	_events.clear()
	_loaded = false
	var dir := DirAccess.open(EVENTS_DIR)
	if dir == null:
		push_warning("EventRuntime: cannot open %s" % EVENTS_DIR)
		_loaded = true
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var path := EVENTS_DIR.path_join(fn)
			var raw := FileAccess.get_file_as_string(path)
			if raw != "":
				var data = JSON.parse_string(raw)
				if data is Dictionary and str(data.get("id", "")) != "":
					_events.append(data)
		fn = dir.get_next()
	dir.list_dir_end()
	## 依 start 排序
	_events.sort_custom(func(a, b): return _parse_day(str(a.get("start", ""))) < _parse_day(str(b.get("start", ""))))
	_loaded = true


func all_events() -> Array:
	if not _loaded:
		reload()
	return _events


func find_event(event_id: String) -> Dictionary:
	for e in all_events():
		if str(e.get("id", "")) == event_id:
			return e
	return {}


func _parse_day(s: String) -> int:
	var parts := s.split("-")
	if parts.size() < 3:
		return 0
	return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2])


func today_ymd() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


func today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func current_month() -> int:
	return int(Time.get_date_dict_from_system().month)


func is_active(ev: Dictionary) -> bool:
	if ev.is_empty():
		return false
	if bool(ev.get("force_active", false)):
		return true
	## 循環月：每年同月自動開（優先於絕對日期）
	if ev.has("recurring_month"):
		return int(ev.get("recurring_month", 0)) == current_month()
	var t := today_ymd()
	var a := _parse_day(str(ev.get("start", "1970-01-01")))
	var b := _parse_day(str(ev.get("end", "2099-12-31")))
	return t >= a and t <= b


func is_ended(ev: Dictionary) -> bool:
	if ev.is_empty() or is_active(ev):
		return false
	if bool(ev.get("force_active", false)):
		return false
	if ev.has("recurring_month"):
		## 循環月：非當月＝本輪已結束（可收攤）
		return int(ev.get("recurring_month", 0)) != current_month()
	var t := today_ymd()
	var b := _parse_day(str(ev.get("end", "2099-12-31")))
	return t > b


func active_events() -> Array:
	var out: Array = []
	for e in all_events():
		if is_active(e):
			out.append(e)
	return out


func primary_event() -> Dictionary:
	var act: Array = active_events()
	if act.is_empty():
		return {}
	## 多個同時開時取 recurring 月最接近的
	return act[0]


func has_active() -> bool:
	return not primary_event().is_empty()


func _fk(event_id: String, suffix: String) -> String:
	return "event.%s.%s" % [event_id, suffix]


func _refresh_daily(event_id: String) -> void:
	var today := today_key()
	var last := str(GameState.get_flag(_fk(event_id, "daily"), ""))
	if last != today:
		GameState.set_flag(_fk(event_id, "daily"), today)
		GameState.set_flag(_fk(event_id, "runs_today"), 0)


func tokens(event_id: String) -> int:
	return int(GameState.get_flag(_fk(event_id, "token"), 0))


func add_tokens(event_id: String, n: int) -> void:
	GameState.set_flag(_fk(event_id, "token"), maxi(0, tokens(event_id) + n))


func runs_today(event_id: String) -> int:
	_refresh_daily(event_id)
	return int(GameState.get_flag(_fk(event_id, "runs_today"), 0))


func runs_total(event_id: String) -> int:
	return int(GameState.get_flag(_fk(event_id, "runs_total"), 0))


func daily_cap(ev: Dictionary) -> int:
	return int(ev.get("daily_reward_cap", 3))


func daily_left(ev: Dictionary) -> int:
	var id := str(ev.get("id", ""))
	return maxi(0, daily_cap(ev) - runs_today(id))


func can_rewarded_run(ev: Dictionary) -> bool:
	return is_active(ev) and daily_left(ev) > 0


func complete_rewarded_run(event_id: String) -> Dictionary:
	var ev := find_event(event_id)
	if ev.is_empty() or not is_active(ev):
		return {"ok": false, "msg": "活動未開放。"}
	_refresh_daily(event_id)
	if daily_left(ev) <= 0:
		return {"ok": false, "msg": "今日有獎次數已用完。仍可自由探索。", "practice": true}
	var rt := runs_today(event_id) + 1
	var total := runs_total(event_id) + 1
	GameState.set_flag(_fk(event_id, "runs_today"), rt)
	GameState.set_flag(_fk(event_id, "runs_total"), total)
	var tok := int(ev.get("run_token", 2))
	var gold_n := int(ev.get("run_gold", 15))
	add_tokens(event_id, tok)
	GameState.add_gold(gold_n)
	## 每日三件事：活動挑戰
	GameState.set_flag("daily.task.event", true)
	_mark_daily_board()
	_try_grant_event_title(ev)
	var cname := str(ev.get("currency_name", "活動幣"))
	SaveManager.save_game()
	return {
		"ok": true,
		"token": tok,
		"gold": gold_n,
		"runs_today": rt,
		"runs_total": total,
		"msg": "挑戰完成：%s +%d · 金 +%d（今日 %d／%d）" % [cname, tok, gold_n, rt, daily_cap(ev)],
	}


func mission_progress(ev: Dictionary, m: Dictionary) -> int:
	var eid := str(ev.get("id", ""))
	if m.has("need_runs"):
		return runs_total(eid)
	if m.has("need_flag"):
		return 1 if GameState.has_flag(str(m.get("need_flag"))) else 0
	return 0


func mission_need(m: Dictionary) -> int:
	if m.has("need_runs"):
		return int(m.get("need_runs", 1))
	if m.has("need_flag"):
		return 1
	return 1


func mission_done(ev: Dictionary, m: Dictionary) -> bool:
	return mission_progress(ev, m) >= mission_need(m)


func mission_claimed(event_id: String, mission_id: String) -> bool:
	return GameState.has_flag(_fk(event_id, "claim.%s" % mission_id))


func claim_mission(event_id: String, mission_id: String) -> Dictionary:
	var ev := find_event(event_id)
	if ev.is_empty():
		return {"ok": false, "msg": "找不到活動。"}
	for m in ev.get("missions", []):
		if str(m.get("id", "")) != mission_id:
			continue
		if mission_claimed(event_id, mission_id):
			return {"ok": false, "msg": "已領過。"}
		if not mission_done(ev, m):
			return {"ok": false, "msg": "條件未達成。"}
		var tok := int(m.get("token", 0))
		var gold_n := int(m.get("gold", 0))
		var dust_n := int(m.get("dust", 0))
		if tok > 0:
			add_tokens(event_id, tok)
		if gold_n > 0:
			GameState.add_gold(gold_n)
		if dust_n > 0:
			GameState.add_stardust(dust_n)
		GameState.set_flag(_fk(event_id, "claim.%s" % mission_id), true)
		_try_grant_event_title(ev)
		SaveManager.save_game()
		return {
			"ok": true,
			"msg": "領取「%s」：%s +%d · 金 %d · 星屑 %d" % [
				str(m.get("name", mission_id)),
				str(ev.get("currency_name", "幣")),
				tok, gold_n, dust_n,
			],
		}
	return {"ok": false, "msg": "找不到任務。"}


func claim_all_missions(event_id: String) -> Dictionary:
	var ev := find_event(event_id)
	if ev.is_empty():
		return {"ok": false, "msg": "無活動。"}
	var n := 0
	var msgs: PackedStringArray = []
	for m in ev.get("missions", []):
		var mid := str(m.get("id", ""))
		if mission_done(ev, m) and not mission_claimed(event_id, mid):
			var r := claim_mission(event_id, mid)
			if bool(r.get("ok", false)):
				n += 1
				msgs.append(str(r.get("msg", "")))
	if n == 0:
		return {"ok": false, "msg": "沒有可領的任務。"}
	return {"ok": true, "msg": "已領 %d 項。\n%s" % [n, "\n".join(msgs)]}


func shop_buy(event_id: String, shop_index: int) -> Dictionary:
	var ev := find_event(event_id)
	if ev.is_empty() or not is_active(ev):
		return {"ok": false, "msg": "活動未開放（已收攤不可換貨）。"}
	var shop: Array = ev.get("shop", [])
	if shop_index < 0 or shop_index >= shop.size():
		return {"ok": false, "msg": "無效商品。"}
	var item: Dictionary = shop[shop_index]
	var cost := int(item.get("cost", 0))
	var iid := str(item.get("id", ""))
	var cnt := int(item.get("count", 1))
	if tokens(event_id) < cost:
		return {"ok": false, "msg": "%s 不足。" % str(ev.get("currency_name", "活動幣"))}
	if not InventorySystem.CATALOG.has(iid):
		return {"ok": false, "msg": "道具表無此物。"}
	add_tokens(event_id, -cost)
	InventorySystem.add_item(iid, cnt)
	SaveManager.save_game()
	var name_s := str(item.get("name", InventorySystem.item_name(iid)))
	return {
		"ok": true,
		"msg": "兌換【%s】×%d（-%d %s）" % [name_s, cnt, cost, str(ev.get("currency_name", "幣"))],
	}


## 收攤：剩幣 → 金
func convert_leftover_tokens(event_id: String) -> Dictionary:
	var ev := find_event(event_id)
	if ev.is_empty():
		return {"ok": false, "msg": "找不到活動。"}
	if is_active(ev):
		return {"ok": false, "msg": "活動進行中，不能收攤。月底再來。"}
	if GameState.has_flag(_fk(event_id, "converted")):
		return {"ok": false, "msg": "已收攤換過幣。"}
	var tok := tokens(event_id)
	if tok <= 0:
		GameState.set_flag(_fk(event_id, "converted"), true)
		return {"ok": false, "msg": "沒有剩餘活動幣。"}
	var rate := int(ev.get("token_to_gold", 2))
	var gold_n := tok * rate
	add_tokens(event_id, -tok)
	GameState.add_gold(gold_n)
	GameState.set_flag(_fk(event_id, "converted"), true)
	SaveManager.save_game()
	return {
		"ok": true,
		"msg": "收攤：%d %s → 金 %d（1 幣＝%d 金）" % [tok, str(ev.get("currency_name", "幣")), gold_n, rate],
	}


func can_enter_map(ev: Dictionary) -> bool:
	var need := str(ev.get("entry_need_flag", ""))
	if need == "":
		return true
	return GameState.has_flag(need)


func challenge_enemy(ev: Dictionary) -> String:
	return str(ev.get("challenge_enemy", "scar_wisp"))


func _try_grant_event_title(ev: Dictionary) -> void:
	var flag := str(ev.get("title_flag", ""))
	if flag == "" or GameState.has_flag(flag):
		return
	## 十日簿 or 任一專屬 boss 任務已領
	var eid := str(ev.get("id", ""))
	var ok := mission_claimed(eid, "ten_runs")
	for m in ev.get("missions", []):
		var mid := str(m.get("id", ""))
		if mid in ["scar_boss", "mirror_boss", "wreck_boss"] and mission_claimed(eid, mid):
			ok = true
	if not ok and runs_total(eid) >= 10:
		ok = true
	if ok:
		GameState.set_flag(flag, true)
		GameState.set_flag("title.event_any", true)


func _mark_daily_board() -> void:
	var today := today_key()
	if str(GameState.get_flag("daily.board.day", "")) != today:
		GameState.set_flag("daily.board.day", today)
		GameState.set_flag("daily.task.login", false)
		GameState.set_flag("daily.task.event", false)
		GameState.set_flag("daily.task.explore", false)
	GameState.set_flag("daily.task.login", true)


## 每日三件事（登入／活動挑戰／探索造訪）
func daily_board_bbcode() -> String:
	_mark_daily_board()
	var login_ok := GameState.has_flag("daily.task.login") or QuestSystem.can_claim_daily() == false
	## 登入：已領每日 or 今日開過面板
	if not GameState.has_flag("daily.task.login"):
		GameState.set_flag("daily.task.login", true)
	login_ok = true
	var event_ok := GameState.has_flag("daily.task.event")
	var explore_ok := GameState.has_flag("daily.task.explore")
	var lines: PackedStringArray = []
	lines.append("[b]今日三件事[/b]（翠嶺小習慣）")
	lines.append("%s 登入／每日補給" % ("✓" if login_ok else "·"))
	if has_active():
		var ev := primary_event()
		lines.append("%s 活動挑戰（%s 剩 %d）" % [
			"✓" if event_ok else "·",
			str(ev.get("name", "")),
			daily_left(ev),
		])
	else:
		lines.append("· 活動挑戰（本月無活動）")
	lines.append("%s 探索一處（開箱或造訪新圖）" % ("✓" if explore_ok else "·"))
	var done := 0
	if login_ok:
		done += 1
	if event_ok:
		done += 1
	if explore_ok:
		done += 1
	lines.append("")
	lines.append("進度 %d／3" % done)
	if done >= 3 and not GameState.has_flag("daily.board.bonus.%s" % today_key()):
		lines.append("[color=#7a5]三件事完成可領小獎勵（下方按鈕）[/color]")
	return "\n".join(lines)


func claim_daily_board_bonus() -> Dictionary:
	_mark_daily_board()
	var today := today_key()
	if GameState.has_flag("daily.board.bonus.%s" % today):
		return {"ok": false, "msg": "今日三件事獎勵已領。"}
	var n := 0
	if GameState.has_flag("daily.task.login"):
		n += 1
	if GameState.has_flag("daily.task.event"):
		n += 1
	if GameState.has_flag("daily.task.explore"):
		n += 1
	if n < 3:
		return {"ok": false, "msg": "尚未完成三件事（%d／3）。" % n}
	GameState.set_flag("daily.board.bonus.%s" % today, true)
	GameState.add_gold(25)
	GameState.add_stardust(1)
	InventorySystem.add_item("bread", 1)
	SaveManager.save_game()
	return {"ok": true, "msg": "三件事完成：金 25 · 星屑 1 · 乾糧×1"}


func mark_explore_daily() -> void:
	_mark_daily_board()
	GameState.set_flag("daily.task.explore", true)


func panel_bbcode(ev: Dictionary = {}) -> String:
	if ev.is_empty():
		ev = primary_event()
	if ev.is_empty():
		return "目前沒有進行中的活動。\n裂縫與秘境仍可照常探索。\n\n" + calendar_preview_bbcode()
	var eid := str(ev.get("id", ""))
	_refresh_daily(eid)
	var cname := str(ev.get("currency_name", "活動幣"))
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]" % str(ev.get("name", eid)))
	var tag := str(ev.get("tagline", ""))
	if tag != "":
		lines.append(tag)
	lines.append("")
	if ev.has("recurring_month"):
		lines.append("循環：每年 %d 月 · 本輪 %s～%s" % [
			int(ev.get("recurring_month", 0)),
			str(ev.get("start", "?")),
			str(ev.get("end", "?")),
		])
	else:
		lines.append("窗期：%s ～ %s" % [str(ev.get("start", "?")), str(ev.get("end", "?"))])
	lines.append("%s：%d" % [cname, tokens(eid)])
	lines.append("今日有獎：%d／%d（剩餘 %d）" % [runs_today(eid), daily_cap(ev), daily_left(ev)])
	lines.append("累計挑戰：%d" % runs_total(eid))
	lines.append("")
	lines.append(daily_board_bbcode())
	lines.append("")
	lines.append("[b]活動任務[/b]")
	for m in ev.get("missions", []):
		var mid := str(m.get("id", ""))
		var prog := mission_progress(ev, m)
		var need := mission_need(m)
		var st := "✓" if mission_claimed(eid, mid) else ("可領" if mission_done(ev, m) else "%d/%d" % [prog, need])
		lines.append("· %s — %s [%s]" % [str(m.get("name", mid)), str(m.get("desc", "")), st])
	lines.append("")
	lines.append("[b]兌換[/b]（用%s）" % cname)
	var i := 0
	for item in ev.get("shop", []):
		lines.append("· [%d] %s — %d %s" % [
			i,
			str(item.get("name", item.get("id", "?"))),
			int(item.get("cost", 0)),
			cname,
		])
		i += 1
	return "\n".join(lines)


func calendar_preview_bbcode() -> String:
	var lines: PackedStringArray = ["[b]歲旅一覽（循環月）[/b]"]
	var mon := current_month()
	for e in all_events():
		var rm := int(e.get("recurring_month", 0))
		var mark := "▶" if rm == mon else "·"
		lines.append("%s %02d月 %s" % [mark, rm, str(e.get("name", ""))])
	return "\n".join(lines)


func title_button_label() -> String:
	var ev := primary_event()
	if ev.is_empty():
		## 有可收攤的舊活動？
		for e in all_events():
			if is_ended(e) and tokens(str(e.get("id", ""))) > 0 and not GameState.has_flag(_fk(str(e.get("id")), "converted")):
				return "活動收攤 ★"
		return "歲旅一覽"
	var left := daily_left(ev)
	var star := " ★" if left > 0 else ""
	return "活動·%s%s" % [str(ev.get("name", "本期")), star]


func ended_with_tokens() -> Array:
	var out: Array = []
	for e in all_events():
		var eid := str(e.get("id", ""))
		if is_ended(e) and tokens(eid) > 0 and not GameState.has_flag(_fk(eid, "converted")):
			out.append(e)
	return out
