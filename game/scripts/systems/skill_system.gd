extends Node
## 技能（招）：習得 · 熟練 · 升級。旅途養招，與器／魂正交。
## 戰鬥以怒氣滿自動放出「當前優先技能」；UI 看列表與下級預覽。
## 十武器流派各有簽名招；選流派時 grant_for_weapon_class 發招。

const MAX_LV := 3

## 熟練門檻：升到該級所需累計熟練（自上一級起算）
const MASTERY_NEED := {
	2: 30,
	3: 80,
}

## 武器流派 id → 簽名技能 id（選流派時強制習得）
const CLASS_SIGNATURE := {
	"sword": "blade_dance",
	"bow": "wind_arrow",
	"magic": "star_pierce",
	"fist": "pressure_fist",
	"axe": "heavy_cleave",
	"hammer": "iron_guard",
	"spear": "line_thrust",
	"gun": "powder_shot",
	"dart": "mist_needle",
	"crystal": "prism_ward",
	## 舊 id 相容（存檔 migration 前）
	"soul": "star_pierce",
	"iron": "iron_guard",
}

## 目錄：通用橫斬 + 劍系 + 十流派簽名 + 星／骨相容招
const ContentLoc := preload("res://scripts/systems/content_loc.gd")
## 目錄裡要翻的欄位（其餘是數值與 id，不能動）
const SKILL_TEXT_FIELDS: PackedStringArray = ["name", "desc", "lv2", "lv3", "unlock_hint"]

const CATALOG: Array[Dictionary] = [
	{
		"id": "slash",
		"name": "橫斬",
		"line": "sword",
		"kind": "attack",
		"base_mult": 1.8,
		"priority": 10,
		"desc": "橫掃一記。怒氣滿時自動使出。旅途的第一招。",
		"lv2": "倍率↑，出手更俐落。",
		"lv3": "附帶鋒勢：倍率再升，破防灌得更快。",
		"unlock_hint": "初戰或灰鬚指點",
	},
	{
		"id": "counter_strike",
		"name": "反戈一擊",
		"line": "sword",
		"kind": "attack",
		"base_mult": 2.4,
		"priority": 20,
		"desc": "吃一記後反咬。倍率高，節奏更兇。",
		"lv2": "反擊更重。",
		"lv3": "反戈尾勁延長，傷害再抬。",
		"unlock_hint": "雷歐後 · 或等級 7",
	},
	{
		"id": "emergency_heal",
		"name": "緊急恢復",
		"line": "sword",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.30,
		"priority": 5,  ## 僅在低血時搶優先
		"desc": "吐一口氣，回血。危急時自動優先。",
		"lv2": "恢復量略增。",
		"lv3": "恢復再增，危機能撐住。",
		"unlock_hint": "C1 鍛刀後找灰鬚體悟",
	},
	{
		"id": "thunder_fury",
		"name": "怒雷狂擊",
		"line": "sword",
		"kind": "attack",
		"base_mult": 2.6,
		"priority": 40,
		"desc": "滿怒優先的大招。獅子認可後的體悟。",
		"lv2": "雷勢更強。",
		"lv3": "怒雷尾音延長，傷害封頂前一檔。",
		"unlock_hint": "擊敗雷歐後體悟 · 或劍道 Lv10",
	},
	{
		"id": "star_pierce",
		"name": "星芒穿刺",
		"line": "magic",
		"kind": "attack",
		"base_mult": 2.2,
		"priority": 28,
		"desc": "法／星途簽名：偏暴擊節奏的一刺。",
		"lv2": "星芒更銳。",
		"lv3": "穿刺附帶短暫識破（倍率再升）。",
		"unlock_hint": "選法流派 · 或等級 6",
	},
	{
		"id": "iron_guard",
		"name": "鐵骨吐息",
		"line": "hammer",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.22,
		"priority": 8,
		"desc": "鎚／鐵骨簽名：較早觸發的穩血吐息。",
		"lv2": "回血略增。",
		"lv3": "危急門檻更寬，回血再增。",
		"unlock_hint": "選鎚流派 · 或等級 5",
	},
	{
		"id": "blade_dance",
		"name": "連鋒三斬",
		"line": "sword",
		"kind": "attack",
		"base_mult": 2.1,
		"priority": 32,
		"desc": "劍道簽名：中速連斬，熟練成長快。",
		"lv2": "連鋒更密。",
		"lv3": "三斬尾勁延長。",
		"unlock_hint": "選劍流派 · 或等級 8",
	},
	{
		"id": "wind_arrow",
		"name": "疾風穿矢",
		"line": "bow",
		"kind": "attack",
		"base_mult": 2.15,
		"priority": 30,
		"desc": "弓道簽名：遠距一箭，吃暴擊節奏。",
		"lv2": "穿矢更銳。",
		"lv3": "尾勁延長，倍率再抬。",
		"unlock_hint": "選弓流派 · 或等級 6",
	},
	{
		"id": "pressure_fist",
		"name": "破勢拳",
		"line": "fist",
		"kind": "attack",
		"base_mult": 2.05,
		"priority": 31,
		"desc": "拳道簽名：貼身連打，破對手架勢。",
		"lv2": "拳勢更密。",
		"lv3": "破勢尾勁，傷害再抬。",
		"unlock_hint": "選拳流派 · 或等級 6",
	},
	{
		"id": "heavy_cleave",
		"name": "重斧斷",
		"line": "axe",
		"kind": "attack",
		"base_mult": 2.45,
		"priority": 33,
		"desc": "斧道簽名：一擊有重量，慢但痛。",
		"lv2": "斧勢更沉。",
		"lv3": "斷勢封頂前一檔。",
		"unlock_hint": "選斧流派 · 或等級 6",
	},
	{
		"id": "line_thrust",
		"name": "一線突刺",
		"line": "spear",
		"kind": "attack",
		"base_mult": 2.25,
		"priority": 31,
		"desc": "槍道簽名：卡住距離的迎擊一刺。",
		"lv2": "槍線更長。",
		"lv3": "突刺附短暫壓制。",
		"unlock_hint": "選槍流派 · 或等級 6",
	},
	{
		"id": "powder_shot",
		"name": "火銃點射",
		"line": "gun",
		"kind": "attack",
		"base_mult": 2.55,
		"priority": 35,
		"desc": "火槍簽名：遠距爆發，打中很痛。",
		"lv2": "裝藥更穩。",
		"lv3": "點射尾音延長。",
		"unlock_hint": "選火槍流派 · 或等級 6",
	},
	{
		"id": "mist_needle",
		"name": "霧影鏢",
		"line": "dart",
		"kind": "attack",
		"base_mult": 2.1,
		"priority": 34,
		"desc": "鏢道簽名：高速真假同色的一手。",
		"lv2": "鏢影更密。",
		"lv3": "識破破綻，倍率再升。",
		"unlock_hint": "選鏢流派 · 或等級 6",
	},
	{
		"id": "prism_ward",
		"name": "晶盾吐息",
		"line": "crystal",
		"kind": "heal",
		"base_mult": 0.0,
		"heal_pct": 0.26,
		"priority": 9,
		"desc": "水晶簽名：把護盾織成吐息，穩血活得久。",
		"lv2": "回血略增。",
		"lv3": "危急門檻更寬。",
		"unlock_hint": "選水晶流派 · 或等級 5",
	},
]


func _ready() -> void:
	ensure_skill_map()


func ensure_skill_map() -> void:
	## 與舊存檔 skill_slash_lv 對齊（只寫入，不經 get_lv 迴圈）
	if not GameState.skill_data.has("slash") and GameState.skill_slash_lv > 0:
		GameState.skill_data["slash"] = {
			"lv": clampi(GameState.skill_slash_lv, 0, MAX_LV),
			"mastery": 0,
		}
	_sync_legacy_slash()


## 招式名與說明在非繁中會被 ContentLoc 換掉。翻在這裡而不是各個顯示點，
## 是因為 def_of() 是整個目錄唯一的讀取入口 —— 下游怎麼用都吃得到。
func def_of(id: String) -> Dictionary:
	for d in CATALOG:
		if str(d.get("id", "")) == id:
			return ContentLoc.apply("skill", d, SKILL_TEXT_FIELDS)
	return {}


func skill_entry(id: String) -> Dictionary:
	var e: Variant = GameState.skill_data.get(id, null)
	if e is Dictionary:
		return e
	return {"lv": 0, "mastery": 0}


func get_lv(id: String) -> int:
	return clampi(int(skill_entry(id).get("lv", 0)), 0, MAX_LV)


func get_mastery(id: String) -> int:
	return maxi(0, int(skill_entry(id).get("mastery", 0)))


func is_learned(id: String) -> bool:
	return get_lv(id) >= 1


func _set_entry(id: String, lv: int, mastery: int) -> void:
	GameState.skill_data[id] = {
		"lv": clampi(lv, 0, MAX_LV),
		"mastery": maxi(0, mastery),
	}
	if id == "slash":
		_sync_legacy_slash()


func _set_lv(id: String, lv: int) -> void:
	var e: Dictionary = skill_entry(id)
	_set_entry(id, lv, int(e.get("mastery", 0)))


func _sync_legacy_slash() -> void:
	var e: Variant = GameState.skill_data.get("slash", null)
	if e is Dictionary:
		GameState.skill_slash_lv = clampi(int(e.get("lv", 0)), 0, MAX_LV)
	else:
		## 無 skill_data 時保留舊欄
		pass


func display_name(id: String) -> String:
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return id
	var lv: int = get_lv(id)
	if lv <= 0:
		return str(d.get("name", id))
	return "%s · Lv%d" % [str(d.get("name", id)), lv]


func mult_for(id: String) -> float:
	var d: Dictionary = def_of(id)
	if d.is_empty() or str(d.get("kind", "")) == "heal":
		return 1.0
	var base: float = float(d.get("base_mult", 1.8))
	var lv: int = maxi(1, get_lv(id))
	return base * (1.0 + 0.12 * float(lv - 1))


func heal_pct_for(id: String) -> float:
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return 0.0
	var base: float = float(d.get("heal_pct", 0.30))
	var lv: int = maxi(1, get_lv(id))
	## 每級 +3% 最大血
	return base + 0.03 * float(lv - 1)


func mastery_need_for_next(id: String) -> int:
	var lv: int = get_lv(id)
	if lv <= 0 or lv >= MAX_LV:
		return 0
	return int(MASTERY_NEED.get(lv + 1, 999))


func mastery_progress_line(id: String) -> String:
	var lv: int = get_lv(id)
	if lv <= 0:
		return "未習得"
	if lv >= MAX_LV:
		return "滿級"
	var need: int = mastery_need_for_next(id)
	var cur: int = get_mastery(id)
	return "熟練 %d／%d" % [mini(cur, need), need]


func can_level_up(id: String) -> bool:
	if not is_learned(id):
		return false
	var lv: int = get_lv(id)
	if lv >= MAX_LV:
		return false
	return get_mastery(id) >= mastery_need_for_next(id)


func try_level_up(id: String) -> bool:
	if not can_level_up(id):
		return false
	var e: Dictionary = skill_entry(id)
	var need: int = mastery_need_for_next(id)
	var left: int = maxi(0, int(e.get("mastery", 0)) - need)
	_set_entry(id, get_lv(id) + 1, left)
	return true


## 戰鬥有效命中：+1～3 熟練；滿了不自動升，等 UI／導師體悟（可選自動）
func add_mastery(id: String, amount: int = 2) -> Dictionary:
	## 回傳 {leveled: bool, lv: int, mastery: int, name: String}
	if not is_learned(id):
		return {}
	if get_lv(id) >= MAX_LV:
		return {"leveled": false, "lv": get_lv(id), "mastery": get_mastery(id), "name": display_name(id)}
	var e: Dictionary = skill_entry(id)
	var m: int = int(e.get("mastery", 0)) + maxi(0, amount)
	_set_entry(id, get_lv(id), m)
	var leveled := false
	## 自動升一級（旅途養招，不卡 UI）
	while can_level_up(id):
		try_level_up(id)
		leveled = true
	return {
		"leveled": leveled,
		"lv": get_lv(id),
		"mastery": get_mastery(id),
		"name": display_name(id),
	}


func learn(id: String, min_lv: int = 1) -> bool:
	## 習得；若已學則只抬到 min_lv
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return false
	var cur: int = get_lv(id)
	if cur >= min_lv:
		return false
	_set_lv(id, maxi(cur, min_lv))
	return true


func _path_id() -> String:
	## 與 GameState 舊 soul/iron → magic/hammer 對齊
	var p := str(GameState.path_style)
	match p:
		"soul":
			return "magic"
		"iron":
			return "hammer"
		_:
			return p


func _path_is(class_id: String) -> bool:
	return _path_id() == class_id


func signature_for_class(class_id: String) -> String:
	var cid := class_id
	match cid:
		"soul":
			cid = "magic"
		"iron":
			cid = "hammer"
	return str(CLASS_SIGNATURE.get(cid, ""))


func is_unlocked(id: String) -> bool:
	## 可否習得（條件）— 等級／流派可解鎖，不全綁主線
	match id:
		"slash":
			return true
		"counter_strike":
			return GameState.has_flag("boss.leo_cleared") or GameState.level >= 7
		"emergency_heal":
			return GameState.has_flag("c1_forged") or GameState.has_flag("c1_entered_city") or GameState.level >= 3
		"thunder_fury":
			return GameState.has_flag("boss.leo_cleared") \
				or (_path_is("sword") and GameState.level >= 10) \
				or GameState.level >= 14
		"star_pierce":
			return _path_is("magic") or GameState.level >= 6 or GameState.has_flag("c1_soul_intro")
		"iron_guard":
			return _path_is("hammer") or GameState.level >= 5
		"blade_dance":
			return _path_is("sword") or GameState.level >= 8
		"wind_arrow":
			return _path_is("bow") or GameState.level >= 6
		"pressure_fist":
			return _path_is("fist") or GameState.level >= 6
		"heavy_cleave":
			return _path_is("axe") or GameState.level >= 6
		"line_thrust":
			return _path_is("spear") or GameState.level >= 6
		"powder_shot":
			return _path_is("gun") or GameState.level >= 6
		"mist_needle":
			return _path_is("dart") or GameState.level >= 6
		"prism_ward":
			return _path_is("crystal") or GameState.level >= 5
		_:
			return false


func try_unlock(id: String) -> bool:
	if is_learned(id):
		return false
	if not is_unlocked(id):
		return false
	return learn(id, 1)


## 戰鬥用：挑當前該放的技能（不硬編碼只認劍系）
func pick_battle_skill(hp_ratio: float = 1.0) -> Dictionary:
	ensure_skill_map()
	## 危急恢復：已學 heal 技中 priority 最高者；鐵骨／晶盾門檻略寬
	var best_heal: Dictionary = {}
	var best_heal_p := -1
	for d in CATALOG:
		if str(d.get("kind", "")) != "heal":
			continue
		var sid: String = str(d.get("id", ""))
		if not is_learned(sid):
			continue
		var threshold := 0.40
		if sid == "iron_guard":
			threshold = 0.48 if get_lv("iron_guard") >= 3 else 0.44
		elif sid == "prism_ward":
			threshold = 0.46 if get_lv("prism_ward") >= 3 else 0.42
		if hp_ratio > threshold:
			continue
		var prio: int = int(d.get("priority", 0))
		if prio > best_heal_p:
			best_heal_p = prio
			best_heal = d
	if not best_heal.is_empty():
		var hid: String = str(best_heal.get("id", ""))
		return {
			"id": hid,
			"name": str(best_heal.get("name", hid)),
			"kind": "heal",
			"mult": 0.0,
			"heal_pct": heal_pct_for(hid),
		}
	## 攻擊技：先看流派，再看 priority。
	##
	## 原本只看 priority，而打贏雷歐一定會體悟「怒雷狂擊」（priority 40，全表最高、
	## 劍系）。於是第一章之後，不管玩家選的是弓、鎚、法還是鏢，實戰永遠只會放出
	## 怒雷 ＋ 一個治療 —— 另外 9 招一輩子放不出來。連帶熟練度只在 skill_hit 累積，
	## 那些招的熟練度也永遠凍結：演武場還能練，練了不會被用到。
	##
	## 改成自己流派的招優先。跨流派的招仍然學得到、仍然是保底
	## （沒有本流派攻擊技時照樣會挑到），只是不再蓋掉玩家自己選的那條路。
	var my_line := GameState.path_style
	var best: Dictionary = {}
	var best_p := -1
	var best_own := false
	for d in CATALOG:
		var sid: String = str(d.get("id", ""))
		if str(d.get("kind", "")) != "attack":
			continue
		if not is_learned(sid):
			continue
		var prio: int = int(d.get("priority", 0))
		var is_own: bool = my_line != "" and str(d.get("line", "")) == my_line
		## 本流派一律排在跨流派前面；同一邊之內才比 priority
		if is_own != best_own:
			if is_own:
				best_own = true
				best_p = prio
				best = d
			continue
		if prio > best_p:
			best_p = prio
			best = d
	if best.is_empty():
		## 狼戰教學：尚未學也給橫斬
		return {
			"id": "slash",
			"name": "橫斬",
			"kind": "attack",
			"mult": 1.8,
			"heal_pct": 0.0,
		}
	var sid2: String = str(best.get("id", "slash"))
	return {
		"id": sid2,
		"name": str(best.get("name", "橫斬")),
		"kind": "attack",
		"mult": mult_for(sid2),
		"heal_pct": 0.0,
	}


func battle_player_stats_patch() -> Dictionary:
	var kit: Dictionary = pick_battle_skill(1.0)
	return {
		"can_skill": is_learned("slash") or kit.get("id", "") != "",
		"slash_lv": maxi(1, get_lv("slash")),
		"skill_id": str(kit.get("id", "slash")),
		"skill_name": str(kit.get("name", "橫斬")),
		"skill_mult": float(kit.get("mult", 1.8)),
		"skill_kind": str(kit.get("kind", "attack")),
		"heal_pct": float(kit.get("heal_pct", 0.0)),
	}


## 導師指點：耗金給熟練（灰鬚）
const TUTOR_COST := 40
const TUTOR_MASTERY := 15

func can_tutor(id: String) -> bool:
	return is_learned(id) and get_lv(id) < MAX_LV and GameState.gold >= TUTOR_COST


func tutor_train(id: String) -> Dictionary:
	if not can_tutor(id):
		return {}
	GameState.add_gold(-TUTOR_COST)
	return add_mastery(id, TUTOR_MASTERY)


func panel_status_bbcode() -> String:
	ensure_skill_map()
	var lines: PackedStringArray = []
	lines.append("[b]旅途 · 招式[/b]")
	lines.append("鐵匠養器 · 星途養魂 · [color=#c9e]旅途養招[/color]")
	lines.append("熟練靠戰鬥命中累積；滿了會自動升階。灰鬚可指點加速。")
	var pid := _path_id()
	if pid != "":
		var sig := signature_for_class(pid)
		if sig != "":
			if is_learned(sig):
				lines.append("當前流派簽名：%s" % display_name(sig))
			else:
				lines.append("當前流派簽名：%s（未習得）" % str(def_of(sig).get("name", sig)))
	lines.append("")
	for d in CATALOG:
		var sid: String = str(d.get("id", ""))
		var name: String = str(d.get("name", sid))
		var lv: int = get_lv(sid)
		if lv <= 0:
			if is_unlocked(sid):
				lines.append("[color=#aaa]· %s — 可體悟（尚未習得）[/color]" % name)
				lines.append("    %s" % str(d.get("desc", "")))
			else:
				lines.append("[color=#666]· ？？？ — %s[/color]" % str(d.get("unlock_hint", "未解鎖")))
			continue
		var kind: String = str(d.get("kind", "attack"))
		var stat_line := ""
		if kind == "heal":
			stat_line = "回復約 %d%% 最大生命" % int(round(heal_pct_for(sid) * 100.0))
		else:
			stat_line = "倍率 ×%.2f" % mult_for(sid)
		lines.append("[b]· %s · Lv%d[/b]  %s" % [name, lv, mastery_progress_line(sid)])
		lines.append("    %s · %s" % [stat_line, str(d.get("desc", ""))])
		if lv < MAX_LV:
			var next_key := "lv%d" % (lv + 1)
			var preview: String = str(d.get(next_key, "下級：倍率或效果↑"))
			lines.append("    [color=#8cf]下級預覽：%s[/color]" % preview)
		else:
			lines.append("    [color=#fc8]滿級[/color]")
	## 當前戰鬥會放什麼
	var kit: Dictionary = pick_battle_skill(0.35)
	var kit_full: Dictionary = pick_battle_skill(1.0)
	lines.append("")
	lines.append("[b]戰鬥優先[/b]")
	lines.append("  平常：%s" % str(kit_full.get("name", "—")))
	var any_heal := false
	for d2 in CATALOG:
		if str(d2.get("kind", "")) == "heal" and is_learned(str(d2.get("id", ""))):
			any_heal = true
			break
	if any_heal:
		lines.append("  危急（低血）：%s" % str(kit.get("name", "—")))
	return "\n".join(lines)


func grant_c0_slash() -> void:
	learn("slash", 1)


func grant_c1_greybeard() -> void:
	## 進城：橫斬更穩（至少 Lv1，略給熟練）
	learn("slash", 1)
	if get_lv("slash") == 1:
		add_mastery("slash", 8)


func grant_leo_insight() -> void:
	## 雷歐後：怒雷 + 反戈可悟
	try_unlock("thunder_fury")
	try_unlock("counter_strike")


func grant_heal_insight() -> void:
	try_unlock("emergency_heal")


## 選武器流派時：通用橫斬 + 該系簽名招
## 回傳本次新習得的 skill id 列表（已學則略過，不弄壞舊存檔）
func grant_for_weapon_class(class_id: String) -> Array:
	var cid := class_id
	match cid:
		"soul":
			cid = "magic"
		"iron":
			cid = "hammer"
	var granted: Array = []
	if learn("slash", 1):
		granted.append("slash")
	elif is_learned("slash"):
		pass
	var sig := signature_for_class(cid)
	if sig != "":
		if learn(sig, 1):
			granted.append(sig)
		## 已學也算「有這招」；確保 unlock 條件之後不會擋
	return granted
