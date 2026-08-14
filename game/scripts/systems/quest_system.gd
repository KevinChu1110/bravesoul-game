extends Node
## 每日獎勵 + 長遠任務（離線）。進度寫入 GameState.flags。

const DAILY_KEY := "meta.daily_day"
const DAILY_CLAIMED := "meta.daily_claimed"
const DAILY_STREAK := "meta.daily_streak"

## 每日委託（養成循環）：track 對應 track_day
const COMMISSIONS: Array[Dictionary] = [
	{"id": "d_train", "name": "演武三巡", "desc": "演武場練功 3 次", "track": "train", "need": 3, "gold": 30, "dust": 1, "xp": 25},
	{"id": "d_skirmish", "name": "清道委託", "desc": "雜魚勝 3 場", "track": "skirmish", "need": 3, "gold": 35, "dust": 1, "xp": 30},
	{"id": "d_mats", "name": "材料回收", "desc": "賣出材料累計 5 件", "track": "sell", "need": 5, "gold": 25, "dust": 1, "xp": 20},
	{"id": "d_craft", "name": "爐邊功課", "desc": "鍛造升階或職系武器 1 次", "track": "craft", "need": 1, "gold": 40, "dust": 2, "xp": 35},
	{"id": "d_shop", "name": "市集一遊", "desc": "在材料行購買 1 次", "track": "shop", "need": 1, "gold": 20, "dust": 1, "xp": 15},
]

## 長遠任務表：id → 目標 flag／計數 key、需求、獎勵
const MISSIONS: Array[Dictionary] = [
	{"id": "m_first_boss", "name": "初試啼聲", "desc": "戰勝雷歐（或任一聖獸）", "kind": "flag", "key": "boss.leo_cleared", "need": 1, "gold": 50, "dust": 3},
	{"id": "m_letter", "name": "遲到的字", "desc": "在霧隱讀完麥穗的信", "kind": "flag", "key": "c2_wheat_letter", "need": 1, "gold": 40, "dust": 2},
	{"id": "m_sprout", "name": "木劍之約", "desc": "完成小芽支線", "kind": "flag", "key": "c1_sprout_done", "need": 1, "gold": 30, "dust": 2},
	{"id": "m_ding_debt", "name": "鐵匠的舊債", "desc": "取回舊主斷劍並交給釘釘", "kind": "flag", "key": "side.ding_debt_done", "need": 1, "gold": 40, "dust": 2},
	{"id": "m_fog_letter", "name": "霧中家書", "desc": "把霧隱的真信送到行商驛站", "kind": "flag", "key": "side.fog_letter_done", "need": 1, "gold": 40, "dust": 2},
	{"id": "m_ronin", "name": "岔路分刃", "desc": "勸降或戰勝黑焰浪人", "kind": "flag", "key": "side.ronin_done", "need": 1, "gold": 50, "dust": 3},
	{"id": "m_codex", "name": "矛盾之頁", "desc": "讀完絲絨典籍架", "kind": "flag", "key": "lore.codex_read", "need": 1, "gold": 25, "dust": 1},
	{"id": "m_side4", "name": "人情四境", "desc": "完成小芽／舊債／家書／浪人四條支線", "kind": "flags_all", "keys": ["c1_sprout_done", "side.ding_debt_done", "side.fog_letter_done", "side.ronin_done"], "need": 4, "gold": 150, "dust": 8},
	{"id": "m_three_kings", "name": "三域行者", "desc": "通關雷歐、白霧、阿波", "kind": "flags_all", "keys": ["boss.leo_cleared", "boss.white_fog_cleared", "boss.abo_cleared"], "need": 3, "gold": 120, "dust": 6},
	{"id": "m_optional", "name": "風與石", "desc": "戰勝疾影與石拳", "kind": "flags_all", "keys": ["boss.shadowwind_cleared", "boss.stonefist_cleared"], "need": 2, "gold": 100, "dust": 5},
	{"id": "m_clear", "name": "晨光見證", "desc": "通關終章", "kind": "flag", "key": "game_cleared", "need": 1, "gold": 200, "dust": 10},
	{"id": "m_rift3", "name": "裂縫試煉", "desc": "裂縫勝場達 3", "kind": "count", "key": "postgame.rift_wins", "need": 3, "gold": 80, "dust": 4},
	{"id": "m_ng1", "name": "二周目啟程", "desc": "進入黑焰迴響（NG+）", "kind": "ng", "need": 1, "gold": 150, "dust": 8},
	{"id": "m_titles5", "name": "稱號收藏家", "desc": "解鎖 5 個稱號", "kind": "titles", "need": 5, "gold": 60, "dust": 3},
	{"id": "m_guild", "name": "盟約之契", "desc": "公會貢獻達 100", "kind": "guild", "need": 100, "gold": 70, "dust": 4},
	{"id": "m_chests5", "name": "拾荒者", "desc": "開啟 5 個世界寶箱", "kind": "chests", "need": 5, "gold": 50, "dust": 3},
	{"id": "m_chests12", "name": "翠嶺寶藏家", "desc": "開啟 12 個世界寶箱", "kind": "chests", "need": 12, "gold": 100, "dust": 5},
	{"id": "m_visit15", "name": "遠足兔", "desc": "造訪 15 張不同地圖", "kind": "visits", "need": 15, "gold": 60, "dust": 3},
	{"id": "m_visit30", "name": "六域漫遊", "desc": "造訪 30 張不同地圖", "kind": "visits", "need": 30, "gold": 120, "dust": 6},
	{"id": "m_skirmish10", "name": "路邊清道夫", "desc": "雜魚勝場 10", "kind": "count", "key": "meta.skirmish_wins", "need": 10, "gold": 70, "dust": 3},
	{"id": "m_scar", "name": "疤地行者", "desc": "戰勝黑焰疤主", "kind": "flag", "key": "boss.scar_lord_cleared", "need": 1, "gold": 100, "dust": 5},
	{"id": "m_mirror", "name": "破鏡之人", "desc": "戰勝鏡廊殘影", "kind": "flag", "key": "boss.mirror_wraith_cleared", "need": 1, "gold": 90, "dust": 5},
	{"id": "m_wreck", "name": "沉船終結者", "desc": "戰勝沉船船長影", "kind": "flag", "key": "boss.wreck_captain_cleared", "need": 1, "gold": 100, "dust": 5},
	{"id": "m_three_secrets", "name": "三秘境", "desc": "三隻秘境小 Boss 全通", "kind": "flags_all", "keys": ["boss.scar_lord_cleared", "boss.mirror_wraith_cleared", "boss.wreck_captain_cleared"], "need": 3, "gold": 200, "dust": 10},
	{"id": "m_hunt3", "name": "星途獵手", "desc": "狩獵場有獎通關 3 次", "kind": "count", "key": "hunt.clears_total", "need": 3, "gold": 70, "dust": 3},
	{"id": "m_party3", "name": "旅人同行", "desc": "助戰裂縫有獎加成 3 次", "kind": "count", "key": "party.boosts_total", "need": 3, "gold": 80, "dust": 4},
	{"id": "m_coop_rift", "name": "裂縫同袍", "desc": "裂縫房共鬥勝 2 次", "kind": "count", "key": "room.coop_wins", "need": 2, "gold": 90, "dust": 4},
	{"id": "m_coop_hunt", "name": "共獵之約", "desc": "狩獵房共鬥勝 2 次", "kind": "count", "key": "room.hunt_coop_wins", "need": 2, "gold": 80, "dust": 3},
	{"id": "m_sync3", "name": "雙星合拍", "desc": "雙星連招成功 3 次", "kind": "count", "key": "room.sync_combos", "need": 3, "gold": 100, "dust": 5},
]


func _day_id() -> int:
	## 以本地日切換（unix / 86400）
	return int(Time.get_unix_time_from_system() / 86400.0)


func refresh_daily() -> void:
	var today := _day_id()
	var last := int(GameState.get_flag(DAILY_KEY, -1))
	if last != today:
		GameState.set_flag(DAILY_KEY, today)
		GameState.set_flag(DAILY_CLAIMED, false)
		## 斷簽：間隔 >1 日清 streak（可選溫和）
		if last >= 0 and today - last > 1:
			GameState.set_flag(DAILY_STREAK, 0)
		## 日計數歸零（委託進度）
		for t in ["train", "skirmish", "sell", "craft", "shop", "hunt"]:
			GameState.set_flag("day.%s" % t, 0)
		## 委託領獎旗
		for c in COMMISSIONS:
			GameState.set_flag("quest.dayclaim.%s" % str(c.get("id", "")), false)
		## 練功日計（與 main 共用）
		GameState.set_flag("meta.train_today", 0)


func track_day(track: String, n: int = 1) -> void:
	refresh_daily()
	if track == "":
		return
	var key := "day.%s" % track
	GameState.set_flag(key, int(GameState.get_flag(key, 0)) + maxi(0, n))


func day_count(track: String) -> int:
	refresh_daily()
	return int(GameState.get_flag("day.%s" % track, 0))


func commission_progress(c: Dictionary) -> int:
	return day_count(str(c.get("track", "")))


func commission_done(c: Dictionary) -> bool:
	return commission_progress(c) >= int(c.get("need", 1))


func commission_claimed(id: String) -> bool:
	return GameState.has_flag("quest.dayclaim.%s" % id)


func claim_commission(id: String) -> Dictionary:
	refresh_daily()
	for c in COMMISSIONS:
		if str(c.get("id", "")) != id:
			continue
		if commission_claimed(id):
			return {"ok": false, "msg": "此委託今日已領。"}
		if not commission_done(c):
			return {"ok": false, "msg": "尚未完成：%s" % str(c.get("desc", ""))}
		var gold_n := int(c.get("gold", 0))
		var dust_n := int(c.get("dust", 0))
		var xp_n := int(c.get("xp", 0))
		GameState.add_gold(gold_n)
		GameState.add_stardust(dust_n)
		var xr: Dictionary = GameState.add_xp(xp_n)
		GameState.set_flag("quest.dayclaim.%s" % id, true)
		## 順手給一點鍛造材
		if Engine.get_main_loop() is SceneTree:
			var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("InventorySystem")
			if inv and inv.has_method("add_item"):
				inv.call("add_item", "iron_scrap", 1)
				if randf() < 0.5:
					inv.call("add_item", "star_ore", 1)
		SaveManager.save_game()
		var lv_s := ""
		if int(xr.get("levels", 0)) > 0:
			lv_s = " · 升級！"
		return {
			"ok": true,
			"msg": "委託「%s」：金 %d · 星屑 %d · 經驗 %d%s · 鐵屑×1" % [
				c.get("name", id), gold_n, dust_n, int(xr.get("gained", xp_n)), lv_s
			],
		}
	return {"ok": false, "msg": "找不到委託。"}


func list_commissions_bbcode() -> String:
	refresh_daily()
	var lines: PackedStringArray = []
	lines.append("[b]今日委託[/b]（養成循環 · 每日重置）")
	for c in COMMISSIONS:
		var id := str(c.get("id", ""))
		var need := int(c.get("need", 1))
		var prog := mini(need, commission_progress(c))
		var mark := "✓" if commission_claimed(id) else ("●" if prog >= need else "·")
		lines.append("%s [b]%s[/b]  %d/%d\n   %s" % [mark, c.get("name", id), prog, need, c.get("desc", "")])
	return "\n".join(lines)


func claimable_commissions() -> int:
	refresh_daily()
	var n := 0
	for c in COMMISSIONS:
		var id := str(c.get("id", ""))
		if commission_done(c) and not commission_claimed(id):
			n += 1
	return n


func can_claim_daily() -> bool:
	refresh_daily()
	return not bool(GameState.get_flag(DAILY_CLAIMED, false))


func claim_daily() -> Dictionary:
	## 回傳 {ok, gold, dust, streak, msg}
	refresh_daily()
	if bool(GameState.get_flag(DAILY_CLAIMED, false)):
		return {"ok": false, "msg": "今日獎勵已領過。明天再來。"}
	var streak := int(GameState.get_flag(DAILY_STREAK, 0)) + 1
	GameState.set_flag(DAILY_STREAK, streak)
	GameState.set_flag(DAILY_CLAIMED, true)
	var gold_n := 20 + mini(30, streak * 2)
	var dust_n := 1 + (1 if streak % 3 == 0 else 0)
	if GameState.ng_plus > 0:
		gold_n += 10
		dust_n += 1
	GameState.add_gold(gold_n)
	GameState.add_stardust(dust_n)
	## 公會貢獻
	if Engine.get_main_loop() is SceneTree:
		var g: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
		if g and g.has_method("add_contrib"):
			g.call("add_contrib", 5)
	SaveManager.save_game()
	return {
		"ok": true,
		"gold": gold_n,
		"dust": dust_n,
		"streak": streak,
		"msg": "每日補給：金 %d · 星屑 %d · 連續簽到 %d 天" % [gold_n, dust_n, streak],
	}


func _mission_progress(m: Dictionary) -> int:
	var kind := str(m.get("kind", ""))
	match kind:
		"flag":
			return 1 if GameState.has_flag(str(m.get("key", ""))) else 0
		"flags_all":
			var n := 0
			for k in m.get("keys", []):
				if GameState.has_flag(str(k)):
					n += 1
			return n
		"count":
			return int(GameState.get_flag(str(m.get("key", "")), 0))
		"ng":
			return GameState.ng_plus
		"titles":
			return TitleCatalog.unlocked_count()
		"guild":
			if Engine.get_main_loop() is SceneTree:
				var g: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
				if g:
					return int(g.get("contrib"))
			return 0
		"chests":
			var WC = load("res://scripts/world/world_content.gd")
			return WC.chest_opened_count() if WC else 0
		"visits":
			var WC2 = load("res://scripts/world/world_content.gd")
			return WC2.visit_count() if WC2 else 0
		_:
			return 0


func mission_done(m: Dictionary) -> bool:
	return _mission_progress(m) >= int(m.get("need", 1))


func mission_claimed(id: String) -> bool:
	return GameState.has_flag("quest.claim.%s" % id)


func claim_mission(id: String) -> Dictionary:
	for m in MISSIONS:
		if str(m.get("id", "")) != id:
			continue
		if mission_claimed(id):
			return {"ok": false, "msg": "已領過此任務獎勵。"}
		if not mission_done(m):
			return {"ok": false, "msg": "條件尚未達成。"}
		var gold_n := int(m.get("gold", 0))
		var dust_n := int(m.get("dust", 0))
		GameState.add_gold(gold_n)
		GameState.add_stardust(dust_n)
		GameState.set_flag("quest.claim.%s" % id, true)
		if Engine.get_main_loop() is SceneTree:
			var g: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GuildSystem")
			if g and g.has_method("add_contrib"):
				g.call("add_contrib", 15)
		SaveManager.save_game()
		return {"ok": true, "msg": "任務「%s」完成：金 %d · 星屑 %d" % [m.get("name", id), gold_n, dust_n]}
	return {"ok": false, "msg": "找不到任務。"}


func list_missions_bbcode() -> String:
	var lines: PackedStringArray = []
	for m in MISSIONS:
		var id := str(m.get("id", ""))
		var need := int(m.get("need", 1))
		var prog := mini(need, _mission_progress(m))
		var mark := "✓" if mission_claimed(id) else ("●" if prog >= need else "·")
		lines.append("%s [b]%s[/b]  %d/%d\n   %s" % [mark, m.get("name", id), prog, need, m.get("desc", "")])
	return "\n".join(lines)


func claimable_count() -> int:
	var n := 0
	if can_claim_daily():
		n += 1
	n += claimable_commissions()
	for m in MISSIONS:
		var id := str(m.get("id", ""))
		if mission_done(m) and not mission_claimed(id):
			n += 1
	return n
