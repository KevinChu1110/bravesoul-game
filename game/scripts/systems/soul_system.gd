extends Node
## 戰魂：探索星屑 → 觀星凝魂 → 入魂槽。非 gacha。

const STARS: Array[Dictionary] = [
	{"id": "破軍", "stat": "atk", "label": "攻", "base": 2},
	{"id": "七殺", "stat": "atk", "label": "銳", "base": 1},  ## 另加微量速度感用 atk
	{"id": "貪狼", "stat": "hp", "label": "血", "base": 6},
	{"id": "天梁", "stat": "def", "label": "防", "base": 2},
	{"id": "紫微", "stat": "all", "label": "衡", "base": 1},
]

const QUALITIES: Array[Dictionary] = [
	{"id": "凡", "mult": 1.0, "weight": 50},
	{"id": "吉", "mult": 1.5, "weight": 30},
	{"id": "大吉", "mult": 2.2, "weight": 15},
	{"id": "稀世", "mult": 3.0, "weight": 5},
]

const RITUAL_COST := 3  ## 每次觀星耗星屑
const FUSE_COUNT := 3

## 秘境專屬戰魂（唯一）：key = boss battle mode
const SECRET_RELICS: Dictionary = {
	"scar_lord": {
		"unique_flag": "soul.relic.scar_lord",
		"star": "疤焰",
		"quality": "秘境",
		"display": "疤焰心核",
		"atk": 9,
		"def": 2,
		"hp": 8,
		"lore": "黑焰疤主的傷口凝成的心核。刃上會殘一絲不肯散的熱。",
	},
	"mirror_wraith": {
		"unique_flag": "soul.relic.mirror_wraith",
		"star": "鏡影",
		"quality": "秘境",
		"display": "真影裂片",
		"atk": 5,
		"def": 6,
		"hp": 12,
		"lore": "鏡廊殘影碎裂時留下的真影。防的是「猶豫」。",
	},
	"wreck_captain": {
		"unique_flag": "soul.relic.wreck_captain",
		"star": "潮骨",
		"quality": "秘境",
		"display": "船長潮骨",
		"atk": 7,
		"def": 5,
		"hp": 20,
		"lore": "沉船船長影的龍骨碎片。像潮汐一樣穩、一樣重。",
	},
}


## 器階到魂槽的門檻。設計是 T1／T6／T11 各開一槽（PROGRESSION 2.2）。
##
## 這張表要跟鍛造的階數上限對得起來。曾經對不上：這裡寫 T11 開第三槽，
## 而鍛造在 T8 就擋下來 —— 第三個魂槽是一個玩家再怎麼玩都拿不到的獎勵。
## 不會報錯，玩家只會把武器練到頂、發現第三格還是灰的，以為自己漏了什麼。
## `test_progression.gd` 現在守著「每一個門檻都要鍛造得到」。
const SLOT_TIERS: Array[int] = [1, 6, 11]


func slot_count() -> int:
	var t: int = GameState.weapon_tier
	var n := 0
	for need in SLOT_TIERS:
		if t >= need:
			n += 1
	return n


func ensure_slots() -> void:
	var n: int = slot_count()
	while GameState.soul_slots.size() < n:
		GameState.soul_slots.append("")
	if GameState.soul_slots.size() > n:
		## 多出來的卸下回背包
		for i in range(n, GameState.soul_slots.size()):
			var sid: String = str(GameState.soul_slots[i])
			if sid != "":
				_set_soul_equipped(sid, false)
		GameState.soul_slots.resize(n)


func find_soul(sid: String) -> Dictionary:
	for s in GameState.souls:
		if str(s.get("id", "")) == sid:
			return s
	return {}


func soul_display(s: Dictionary) -> String:
	if s.is_empty():
		return "（空）"
	if bool(s.get("relic", false)):
		var dn := str(s.get("display", s.get("star", "秘境魂")))
		var lv: int = int(s.get("level", 0))
		var lv_s := "" if lv <= 0 else "·%d" % lv
		return "秘·%s%s" % [dn, lv_s]
	var q: String = str(s.get("quality", "凡"))
	var star: String = str(s.get("star", "？"))
	var lv2: int = int(s.get("level", 0))
	var lv_s2 := "" if lv2 <= 0 else "·%d" % lv2
	return "%s·%s%s" % [q, star, lv_s2]


func soul_bonus_line(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var b: Dictionary = calc_soul_bonus(s)
	var parts: PackedStringArray = []
	if int(b.get("atk", 0)) != 0:
		parts.append("攻+%d" % int(b.get("atk", 0)))
	if int(b.get("def", 0)) != 0:
		parts.append("防+%d" % int(b.get("def", 0)))
	if int(b.get("hp", 0)) != 0:
		parts.append("血+%d" % int(b.get("hp", 0)))
	return " ".join(parts)


func calc_soul_bonus(s: Dictionary) -> Dictionary:
	## 秘境專屬：固定三圍（可再吃 level 微幅）
	if bool(s.get("relic", false)):
		var lv: int = int(s.get("level", 0))
		var scale := 1.0 + 0.12 * float(lv)
		return {
			"atk": maxi(1, int(round(float(s.get("atk_bonus", 0)) * scale))),
			"def": maxi(0, int(round(float(s.get("def_bonus", 0)) * scale))),
			"hp": maxi(0, int(round(float(s.get("hp_bonus", 0)) * scale))),
		}
	var star_id: String = str(s.get("star", "破軍"))
	var q_id: String = str(s.get("quality", "凡"))
	var lv2: int = int(s.get("level", 0))
	var star_def: Dictionary = {}
	for st in STARS:
		if str(st.get("id", "")) == star_id:
			star_def = st
			break
	if star_def.is_empty():
		star_def = STARS[0]
	var mult := 1.0
	for q in QUALITIES:
		if str(q.get("id", "")) == q_id:
			mult = float(q.get("mult", 1.0))
			break
	if q_id == "秘境":
		mult = 3.2
	var base: float = float(star_def.get("base", 1)) * mult * (1.0 + 0.15 * float(lv2))
	var val: int = maxi(1, int(round(base)))
	var stat: String = str(star_def.get("stat", "atk"))
	var out := {"atk": 0, "def": 0, "hp": 0}
	match stat:
		"atk":
			out["atk"] = val
			if star_id == "七殺":
				out["atk"] = val + 1
		"def":
			out["def"] = val
		"hp":
			out["hp"] = val
		"all":
			out["atk"] = val
			out["def"] = val
			out["hp"] = val * 3
	return out


func grant_secret_relic(boss_mode: String) -> Dictionary:
	## 回傳 {ok, soul?, msg, dust?}
	if not SECRET_RELICS.has(boss_mode):
		return {"ok": false, "msg": "沒有對應秘境魂器。"}
	var def: Dictionary = SECRET_RELICS[boss_mode]
	var flag := str(def.get("unique_flag", ""))
	if flag != "" and GameState.has_flag(flag):
		## 已有：補償星屑
		GameState.add_stardust(3)
		return {"ok": true, "duplicate": true, "dust": 3, "msg": "你已持有此秘境魂器。改獲星屑 3。"}
	var soul := {
		"id": "relic_%s_%d" % [boss_mode, Time.get_ticks_msec()],
		"star": str(def.get("star", "秘")),
		"quality": str(def.get("quality", "秘境")),
		"display": str(def.get("display", "秘境魂")),
		"level": 0,
		"equipped": false,
		"relic": true,
		"relic_key": boss_mode,
		"atk_bonus": int(def.get("atk", 0)),
		"def_bonus": int(def.get("def", 0)),
		"hp_bonus": int(def.get("hp", 0)),
		"lore": str(def.get("lore", "")),
	}
	GameState.souls.append(soul)
	if flag != "":
		GameState.set_flag(flag, true)
	## 至少開一槽
	if GameState.weapon_tier < 1:
		GameState.weapon_tier = 1
	ensure_slots()
	return {
		"ok": true,
		"duplicate": false,
		"soul": soul,
		"msg": "獲得秘境魂器【%s】！%s" % [str(def.get("display", "")), str(def.get("lore", ""))],
	}


func total_equipped_bonus() -> Dictionary:
	ensure_slots()
	var total := {"atk": 0, "def": 0, "hp": 0}
	for sid in GameState.soul_slots:
		if str(sid) == "":
			continue
		var s: Dictionary = find_soul(str(sid))
		if s.is_empty():
			continue
		var b: Dictionary = calc_soul_bonus(s)
		total["atk"] = int(total["atk"]) + int(b.get("atk", 0))
		total["def"] = int(total["def"]) + int(b.get("def", 0))
		total["hp"] = int(total["hp"]) + int(b.get("hp", 0))
	return total


## 足跡權重：主線進度偏科
func _star_weights() -> Dictionary:
	var w: Dictionary = {}
	for st in STARS:
		w[str(st.get("id", ""))] = 20.0
	if GameState.has_flag("boss.leo_cleared"):
		w["破軍"] = float(w.get("破軍", 20)) + 25.0
		w["七殺"] = float(w.get("七殺", 20)) + 10.0
	if GameState.has_flag("boss.white_fog_cleared"):
		w["紫微"] = float(w.get("紫微", 20)) + 15.0
	if GameState.has_flag("boss.abo_cleared"):
		w["天梁"] = float(w.get("天梁", 20)) + 20.0
	if GameState.has_flag("c0_care") or GameState.has_wheat_stalk or GameState.wheat_stalk_broken:
		w["天梁"] = float(w.get("天梁", 20)) + 12.0
		w["貪狼"] = float(w.get("貪狼", 20)) + 8.0
	if GameState.has_flag("boss.shadowwind_cleared"):
		w["七殺"] = float(w.get("七殺", 20)) + 12.0
	if GameState.has_flag("boss.stonefist_cleared"):
		w["貪狼"] = float(w.get("貪狼", 20)) + 12.0
	## 進度抬高品質（在 roll 品質時另算）
	return w


func _quality_weights() -> Array:
	var out: Array = []
	var progress := 0
	if GameState.has_flag("boss.leo_cleared"):
		progress += 1
	if GameState.has_flag("boss.white_fog_cleared"):
		progress += 1
	if GameState.has_flag("boss.abo_cleared"):
		progress += 1
	if GameState.has_flag("game_cleared"):
		progress += 2
	for q in QUALITIES:
		var wt: float = float(q.get("weight", 10))
		if str(q.get("id", "")) == "大吉":
			wt += float(progress) * 3.0
		if str(q.get("id", "")) == "稀世":
			wt += float(progress) * 1.5
		out.append({"id": q.get("id"), "mult": q.get("mult"), "weight": wt})
	return out


func _pick_weighted(items: Array, key: String = "weight") -> Dictionary:
	var total := 0.0
	for it in items:
		total += float(it.get(key, 0))
	if total <= 0.0:
		return items[0] if not items.is_empty() else {}
	var r := randf() * total
	var acc := 0.0
	for it in items:
		acc += float(it.get(key, 0))
		if r <= acc:
			return it
	return items[items.size() - 1]


func can_ritual() -> bool:
	return GameState.stardust >= RITUAL_COST


func ritual() -> Dictionary:
	## 觀星：耗星屑，回傳新生戰魂 dict；失敗回空
	if not can_ritual():
		return {}
	GameState.stardust -= RITUAL_COST
	var sw: Dictionary = _star_weights()
	var star_items: Array = []
	for k in sw.keys():
		star_items.append({"id": k, "weight": sw[k]})
	var star_pick: Dictionary = _pick_weighted(star_items)
	var q_pick: Dictionary = _pick_weighted(_quality_weights())
	var soul := {
		"id": "soul_%d_%d" % [Time.get_ticks_msec(), randi() % 10000],
		"star": str(star_pick.get("id", "破軍")),
		"quality": str(q_pick.get("id", "凡")),
		"level": 0,
		"equipped": false,
	}
	GameState.souls.append(soul)
	return soul


func unequip_all_of(sid: String) -> void:
	ensure_slots()
	for i in GameState.soul_slots.size():
		if str(GameState.soul_slots[i]) == sid:
			GameState.soul_slots[i] = ""
	_set_soul_equipped(sid, false)


func _set_soul_equipped(sid: String, eq: bool) -> void:
	for i in GameState.souls.size():
		var s: Dictionary = GameState.souls[i]
		if str(s.get("id", "")) == sid:
			s["equipped"] = eq
			GameState.souls[i] = s
			return


func equip_soul(sid: String, slot: int) -> String:
	## 回傳錯誤訊息；空字串＝成功
	ensure_slots()
	if slot < 0 or slot >= GameState.soul_slots.size():
		return "沒有這個魂槽。"
	var s: Dictionary = find_soul(sid)
	if s.is_empty():
		return "找不到這顆戰魂。"
	if bool(s.get("equipped", false)):
		unequip_all_of(sid)
	## 槽上原魂卸下
	var old: String = str(GameState.soul_slots[slot])
	if old != "":
		_set_soul_equipped(old, false)
	GameState.soul_slots[slot] = sid
	_set_soul_equipped(sid, true)
	return ""


func unequip_slot(slot: int) -> void:
	ensure_slots()
	if slot < 0 or slot >= GameState.soul_slots.size():
		return
	var sid: String = str(GameState.soul_slots[slot])
	if sid != "":
		_set_soul_equipped(sid, false)
	GameState.soul_slots[slot] = ""


func bag_souls() -> Array:
	## 未裝備
	var out: Array = []
	for s in GameState.souls:
		if not bool(s.get("equipped", false)):
			out.append(s)
	return out


func can_fuse(star: String, quality: String, level: int) -> bool:
	var n := 0
	for s in bag_souls():
		if str(s.get("star", "")) == star \
				and str(s.get("quality", "")) == quality \
				and int(s.get("level", 0)) == level \
				and level < 3:
			n += 1
	return n >= FUSE_COUNT


func fuse(star: String, quality: String, level: int) -> Dictionary:
	if not can_fuse(star, quality, level):
		return {}
	var removed := 0
	var keep: Array = []
	for s in GameState.souls:
		if removed < FUSE_COUNT \
				and not bool(s.get("equipped", false)) \
				and str(s.get("star", "")) == star \
				and str(s.get("quality", "")) == quality \
				and int(s.get("level", 0)) == level:
			removed += 1
			continue
		keep.append(s)
	GameState.souls = keep
	var soul := {
		"id": "soul_%d_%d" % [Time.get_ticks_msec(), randi() % 10000],
		"star": star,
		"quality": quality,
		"level": level + 1,
		"equipped": false,
	}
	GameState.souls.append(soul)
	return soul


func grant_starter_soul() -> Dictionary:
	## C1 教學：凡·破軍
	var soul := {
		"id": "soul_starter_pojun",
		"star": "破軍",
		"quality": "凡",
		"level": 0,
		"equipped": false,
	}
	## 避免重複
	if find_soul(soul["id"]).is_empty():
		GameState.souls.append(soul)
	ensure_slots()
	if slot_count() >= 1 and str(GameState.soul_slots[0] if GameState.soul_slots.size() > 0 else "") == "":
		equip_soul(str(soul["id"]), 0)
	return soul


func panel_status_bbcode() -> String:
	ensure_slots()
	var bonus: Dictionary = total_equipped_bonus()
	var lines: PackedStringArray = []
	lines.append("[b]星途 · 戰魂[/b]")
	lines.append("星屑：%d（觀星一次耗 %d）" % [GameState.stardust, RITUAL_COST])
	lines.append("武器：%s  T%d · 魂槽 %d" % [GameState.weapon_name, GameState.weapon_tier, slot_count()])
	lines.append("入魂加成：攻+%d  防+%d  血+%d" % [
		int(bonus.get("atk", 0)), int(bonus.get("def", 0)), int(bonus.get("hp", 0))
	])
	lines.append("")
	lines.append("[b]已入魂[/b]")
	if slot_count() <= 0:
		lines.append("（器階不足，尚無魂槽。先找釘釘養器。）")
	else:
		for i in GameState.soul_slots.size():
			var sid: String = str(GameState.soul_slots[i])
			if sid == "":
				lines.append("  槽%d：空" % (i + 1))
			else:
				var s: Dictionary = find_soul(sid)
				lines.append("  槽%d：%s（%s）" % [i + 1, soul_display(s), soul_bonus_line(s)])
	lines.append("")
	lines.append("[b]背包戰魂[/b]")
	var bag: Array = bag_souls()
	if bag.is_empty():
		lines.append("  （空）")
	else:
		for s in bag:
			lines.append("  · %s  %s" % [soul_display(s), soul_bonus_line(s)])
	return "\n".join(lines)
