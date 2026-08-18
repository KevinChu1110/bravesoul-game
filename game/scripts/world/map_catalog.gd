extends RefCounted
class_name MapCatalog
## 大地圖定義：尺寸、出生點、實體列表。世界座標以 origin 為左上可行走區。
## 0.9：六域多層分區（40+ 張可走地圖）。

const TILE := 32
const ContentLoc := preload("res://scripts/systems/content_loc.gd")

## 回傳 {title, bg_color, origin, size, spawn, art, entities:[{id,pos,size,label,color,solid?}]}
##
## 地名與物件標籤在非繁中會被 ContentLoc 換掉（domain "map"），以原文當 key。
## 不用物件 id 當 key 是因為同一個 id 在不同地圖上是不同的字（back_town 有
## 「回外城廣場」也有「回城」），實測 39 個這種撞名，用 id 會翻錯。
static func build(id: String) -> Dictionary:
	var m := _build_raw(id)
	if ContentLoc.locale() == "zh_TW":
		return m
	m = m.duplicate(true)
	m["title"] = ContentLoc.text("map", str(m.get("title", "")))
	for e in m.get("entities", []):
		if typeof(e) == TYPE_DICTIONARY:
			e["label"] = ContentLoc.text("map", str(e.get("label", "")))
	return m


static func _build_raw(id: String) -> Dictionary:
	match id:
		"village":
			return _village()
		"village_outskirts":
			return _village_outskirts()
		"village_mill":
			return _village_mill()
		"village_cave":
			return _village_cave()
		"village_grave":
			return _village_grave()
		"road":
			return _road()
		"road_bridge":
			return _road_bridge()
		"road_inn":
			return _road_inn()
		"road_ruins":
			return _road_ruins()
		"town":
			return _town()
		"town_keep":
			return _town_keep()
		"town_market":
			return _town_market()
		"town_sewers":
			return _town_sewers()
		"barracks_yard":
			return _barracks_yard()
		"wild":
			return _wild()
		"wild_ravine":
			return _wild_ravine()
		"wild_leo_court":
			return _wild_leo_court()
		"crossroads":
			return _crossroads()
		"cross_north":
			return _cross_north()
		"cross_east":
			return _cross_east()
		"caravan_camp":
			return _caravan_camp()
		"starfall_plain":
			return _starfall_plain()
		"blackflame_scar":
			return _blackflame_scar()
		"hunting_grounds":
			return _hunting_grounds()
		"mist_village":
			return _mist()
		"mist_deep":
			return _mist_deep()
		"mist_cliff":
			return _mist_cliff()
		"mist_shrine":
			return _mist_shrine()
		"mist_mirror":
			return _mist_mirror()
		"dojo":
			return _dojo()
		"dojo_inner":
			return _dojo_inner()
		"dojo_bamboo":
			return _dojo_bamboo()
		"dojo_peak":
			return _dojo_peak()
		"forest":
			return _forest()
		"forest_deep":
			return _forest_deep()
		"forest_canopy":
			return _forest_canopy()
		"forest_ruins":
			return _forest_ruins()
		"forest_lake":
			return _forest_lake()
		"coast":
			return _coast()
		"coast_cliff":
			return _coast_cliff()
		"coast_harbor":
			return _coast_harbor()
		"coast_cave":
			return _coast_cave()
		"coast_wreck":
			return _coast_wreck()
		"tower_camp":
			return _tower_camp()
		"tower_foyer":
			return _tower_foyer()
		"tower_stairs":
			return _tower_stairs()
		"tower_memory":
			return _tower_memory()
		_:
			return _fallback(id)


static func _base(title: String, col: Color, w: float, h: float, spawn: Vector2, art: String) -> Dictionary:
	return {
		"title": title,
		"bg_color": col,
		"origin": Vector2(40, 80),
		"size": Vector2(w, h),
		"spawn": spawn,
		"art": art,
		"entities": [],
	}


static func _e(id: String, x: float, y: float, w: float, h: float, label: String, c: Color, solid := false) -> Dictionary:
	return {"id": id, "pos": Vector2(x, y), "size": Vector2(w, h), "label": label, "color": c, "solid": solid}


# ═══════════════════════════════════════════
#  翠谷
# ═══════════════════════════════════════════

static func _village() -> Dictionary:
	var m := _base("翠谷村 · 夜（本村）", Color(0.08, 0.04, 0.05), 2800, 1562, Vector2(880, 1173), "village")
	m["entities"] = [
		_e("hut_a", 448, 719, 80, 72, "焦黑茅屋", Color(0.35, 0.25, 0.2), true),
		_e("hut_b", 816, 657, 72, 64, "塌半的倉", Color(0.4, 0.28, 0.2), true),
		_e("hut_c", 1139, 1340, 70, 60, "半毀木屋", Color(0.38, 0.26, 0.22), true),
		_e("maisui", 1332, 1109, 48, 64, "麥穗", Color(0.85, 0.55, 0.45)),
		_e("well", 1470, 1027, 52, 52, "井沿", Color(0.4, 0.42, 0.45), true),
		_e("sword", 1290, 953, 48, 48, "鏽劍", Color(0.55, 0.5, 0.4)),
		_e("ash_pile", 1698, 1071, 44, 40, "灰堆", Color(0.3, 0.28, 0.28)),
		_e("fire", 1860, 976, 56, 56, "火光", Color(0.9, 0.35, 0.1), true),
		_e("cart", 1116, 840, 60, 52, "翻倒的車", Color(0.45, 0.35, 0.25), true),
		_e("fence_row", 556, 1083, 200, 28, "燒焦籬笆", Color(0.3, 0.25, 0.2), true),
		_e("field_west", 414, 1242, 120, 48, "西邊田埂", Color(0.35, 0.3, 0.2)),
		_e("sign_east", 2482, 840, 44, 52, "東路木牌", Color(0.4, 0.35, 0.25)),
		_e("exit_east", 2510, 874, 72, 80, "往東 · 荒路", Color(0.3, 0.25, 0.2)),
		_e("exit_outskirts", 298, 984, 72, 64, "村外田野", Color(0.35, 0.4, 0.3)),
		_e("to_cave", 2066, 493, 64, 56, "山邊洞窟", Color(0.3, 0.28, 0.32)),
		_e("to_grave", 2402, 1211, 64, 56, "村後墓園", Color(0.35, 0.32, 0.3)),
		_e("shrine_stub", 1626, 516, 48, 56, "村口小祠", Color(0.45, 0.4, 0.35), true),
		_e("orchard", 1972, 1352, 56, 48, "枯果園", Color(0.4, 0.35, 0.28)),
	]
	return m


static func _village_outskirts() -> Dictionary:
	var m := _base("翠谷 · 村外田野", Color(0.07, 0.08, 0.06), 2600, 1451, Vector2(690, 1067), "village")
	m["entities"] = [
		_e("back_village", 363, 924, 56, 56, "回村子", Color(0.4, 0.35, 0.3)),
		_e("scare_field", 653, 1127, 48, 56, "稻草人", Color(0.4, 0.35, 0.25)),
		_e("pond", 1040, 990, 80, 48, "乾涸池塘", Color(0.3, 0.35, 0.4), true),
		_e("woodpile", 870, 736, 56, 40, "木柴堆", Color(0.45, 0.35, 0.25)),
		_e("to_mill", 1425, 480, 64, 64, "風車田", Color(0.4, 0.42, 0.35)),
		_e("trail_east", 2292, 829, 72, 64, "接荒路", Color(0.35, 0.4, 0.3)),
		_e("windmill", 1726, 479, 60, 80, "風車殘架", Color(0.4, 0.38, 0.35), true),
		_e("stone_circle", 1676, 1222, 56, 48, "石圈", Color(0.42, 0.4, 0.38)),
	]
	return m


static func _village_mill() -> Dictionary:
	var m := _base("翠谷 · 風車田與碾坊", Color(0.09, 0.1, 0.07), 2400, 1350, Vector2(200, 595), "village_mill")
	m["entities"] = [
		_e("back_from_mill", 100, 584, 56, 56, "回田野", Color(0.4, 0.35, 0.3)),
		_e("big_mill", 600, 377, 96, 120, "巨風車", Color(0.45, 0.42, 0.38), true),
		_e("grain_silo", 900, 549, 56, 64, "糧倉", Color(0.5, 0.4, 0.3), true),
		_e("miller_hut", 1100, 670, 64, 56, "碾坊主屋", Color(0.42, 0.36, 0.28), true),
		_e("wheat_sea", 1400, 484, 80, 48, "麥浪坡", Color(0.55, 0.5, 0.3)),
		_e("mill_to_road", 2000, 608, 64, 56, "捷徑·荒路", Color(0.35, 0.4, 0.3)),
		_e("scare_b", 1600, 852, 40, 48, "第二稻草人", Color(0.4, 0.35, 0.25)),
	]
	return m


static func _village_cave() -> Dictionary:
	var m := _base("翠谷 · 山邊舊礦洞", Color(0.06, 0.06, 0.08), 2200, 1238, Vector2(180, 575), "village_cave")
	m["entities"] = [
		_e("back_from_cave", 100, 551, 56, 56, "回村子", Color(0.4, 0.35, 0.3)),
		_e("cave_mouth", 500, 431, 80, 72, "洞口", Color(0.25, 0.25, 0.3), true),
		_e("ore_cart", 800, 609, 56, 40, "礦車", Color(0.4, 0.35, 0.3)),
		_e("glow_moss", 1100, 486, 40, 40, "螢光苔", Color(0.3, 0.55, 0.4)),
		_e("deep_dark", 1500, 551, 64, 56, "更深的黑", Color(0.2, 0.2, 0.25)),
		_e("old_pick", 900, 794, 40, 36, "斷鎬", Color(0.45, 0.4, 0.35)),
		_e("echo_wall", 1700, 368, 48, 64, "回音壁", Color(0.35, 0.35, 0.4), true),
	]
	return m


static func _village_grave() -> Dictionary:
	var m := _base("翠谷 · 村後墓園", Color(0.07, 0.07, 0.09), 2200, 1238, Vector2(200, 575), "village_grave")
	var lamp_lab := "長明燈（亮）" if GameState.has_flag("side.lantern_done") else "長明燈"
	m["entities"] = [
		_e("back_from_grave", 100, 551, 56, 56, "回村子", Color(0.4, 0.35, 0.3)),
		_e("stone_gate", 400, 369, 64, 72, "墓園門", Color(0.4, 0.38, 0.4), true),
		_e("grave_a", 700, 549, 40, 48, "無名碑", Color(0.45, 0.42, 0.4), true),
		_e("grave_b", 900, 611, 40, 48, "舊碑", Color(0.42, 0.4, 0.38), true),
		_e("willow", 1100, 347, 56, 80, "垂柳", Color(0.3, 0.4, 0.32), true),
		_e("lantern_post", 1300, 489, 36, 56, lamp_lab, Color(0.55, 0.5, 0.35)),
		_e("fresh_earth", 1500, 671, 48, 40, "新土", Color(0.35, 0.3, 0.25)),
		_e("hill_edge", 1800, 426, 56, 48, "遠眺丘", Color(0.35, 0.38, 0.32)),
	]
	return m


# ═══════════════════════════════════════════
#  荒路
# ═══════════════════════════════════════════

static func _road() -> Dictionary:
	var m := _base("荒路 · 橫貫翠嶺東道", Color(0.12, 0.16, 0.22), 3600, 2009, Vector2(180, 811), "road")
	m["entities"] = [
		_e("look_back", 200, 521, 48, 48, "煙柱（村）", Color(0.4, 0.35, 0.35)),
		_e("milepost", 500, 747, 40, 56, "里程碑·一", Color(0.45, 0.42, 0.4), true),
		_e("to_road_inn", 800, 492, 64, 56, "路旁客棧", Color(0.5, 0.4, 0.3)),
		_e("bush_a", 1000, 971, 48, 40, "灌木", Color(0.3, 0.35, 0.28)),
		_e("wolf", 1300, 790, 64, 64, "灌木異響", Color(0.35, 0.3, 0.35)),
		_e("milepost_b", 1700, 711, 40, 56, "里程碑·二", Color(0.45, 0.42, 0.4), true),
		_e("to_road_bridge", 2100, 747, 64, 56, "大橋段", Color(0.4, 0.42, 0.45)),
		_e("to_road_ruins", 2400, 528, 64, 56, "古驛廢墟", Color(0.4, 0.38, 0.35)),
		_e("bush_b", 2600, 880, 48, 40, "黑刺叢", Color(0.28, 0.3, 0.28)),
		_e("road_stone", 2800, 840, 40, 36, "裂開的路石", Color(0.4, 0.38, 0.36)),
		_e("camp_ash", 1500, 515, 56, 40, "路人餘燼", Color(0.4, 0.3, 0.25)),
		_e("bridge", 3000, 777, 80, 48, "小橋", Color(0.4, 0.38, 0.35), true),
		_e("dawn_glow", 3300, 565, 56, 56, "東邊亮光·城", Color(0.55, 0.5, 0.4)),
		_e("exit_town_hint", 3400, 936, 72, 64, "通往騎士堡方向", Color(0.4, 0.4, 0.45)),
	]
	return m


static func _road_bridge() -> Dictionary:
	var m := _base("荒路 · 斷崖大橋", Color(0.1, 0.14, 0.2), 2600, 1462, Vector2(200, 621), "road_bridge")
	m["entities"] = [
		_e("back_road", 100, 618, 56, 56, "回主路", Color(0.4, 0.4, 0.45)),
		_e("bridge_arch", 800, 548, 120, 64, "石拱橋", Color(0.45, 0.43, 0.42), true),
		_e("ravine_view", 1000, 789, 64, 48, "深谷俯瞰", Color(0.3, 0.35, 0.4)),
		_e("toll_ruin", 1400, 457, 56, 56, "廢稅亭", Color(0.42, 0.38, 0.35), true),
		_e("broken_rail", 1600, 592, 80, 32, "斷欄杆", Color(0.4, 0.35, 0.3), true),
		_e("east_span", 2100, 574, 64, 56, "橋東·接主路", Color(0.4, 0.42, 0.45)),
		_e("nest_under", 1200, 1005, 48, 40, "橋下鳥巢" + ("（已顧）" if GameState.has_flag("side.nest_care_done") else ""), Color(0.35, 0.4, 0.3)),
	]
	return m


static func _road_inn() -> Dictionary:
	var m := _base("荒路 · 半塌客棧", Color(0.11, 0.1, 0.12), 2200, 1238, Vector2(200, 575), "road_inn")
	var hearth_lab := "壁爐（暖）" if GameState.has_flag("side.hearth_lit") else "熄滅壁爐"
	m["entities"] = [
		_e("back_road", 100, 551, 56, 56, "回主路", Color(0.4, 0.4, 0.45)),
		_e("inn_sign", 500, 341, 48, 56, "「歇腳」破牌", Color(0.5, 0.4, 0.3), true),
		_e("common_room", 700, 516, 80, 64, "大堂", Color(0.42, 0.35, 0.28), true),
		_e("hearth", 900, 611, 56, 48, hearth_lab, Color(0.35, 0.3, 0.28), true),
		_e("cellar_hatch", 1100, 733, 48, 40, "地窖口", Color(0.3, 0.28, 0.25)),
		_e("stable_ruin", 1400, 489, 64, 56, "馬廄廢墟", Color(0.4, 0.36, 0.3), true),
		_e("guest_bed", 1600, 671, 48, 40, "塌床", Color(0.45, 0.38, 0.32)),
		_e("road_note", 1800, 424, 40, 40, "留言板", Color(0.5, 0.45, 0.35)),
	]
	return m


static func _road_ruins() -> Dictionary:
	var m := _base("荒路 · 古驛站廢墟", Color(0.1, 0.12, 0.14), 2400, 1350, Vector2(200, 595), "road_ruins")
	m["entities"] = [
		_e("back_road", 100, 571, 56, 56, "回主路", Color(0.4, 0.4, 0.45)),
		_e("column_a", 500, 366, 40, 72, "斷柱", Color(0.45, 0.42, 0.4), true),
		_e("column_b", 700, 389, 40, 64, "斷柱", Color(0.42, 0.4, 0.38), true),
		_e("mosaic", 900, 582, 72, 48, "碎馬賽克", Color(0.5, 0.45, 0.4)),
		_e("courier_post", 1200, 485, 56, 56, "驛亭基座", Color(0.4, 0.38, 0.35), true),
		_e("sealed_chest", 1500, 666, 48, 40, "封箱", Color(0.45, 0.35, 0.25)),
		_e("star_mark", 1800, 361, 48, 48, "星曜刻紋", Color(0.5, 0.55, 0.7)),
		_e("to_starfall", 2000, 731, 64, 56, "往星落平原", Color(0.45, 0.5, 0.65)),
	]
	return m


# ═══════════════════════════════════════════
#  騎士堡
# ═══════════════════════════════════════════

static func _town() -> Dictionary:
	var m := _base("騎士堡壘 · 外城廣場", Color(0.1, 0.11, 0.14), 3200, 1785, Vector2(792, 1293), "town")
	var flag_label := "旗幟（兔爪）" if GameState.has_flag("c1_flag_paw") else "灰旗"
	m["entities"] = [
		_e("greybeard", 1024, 891, 48, 64, "灰鬚", Color(0.55, 0.55, 0.6)),
		_e("wall_notice", 1442, 840, 44, 52, "告示牆", Color(0.45, 0.4, 0.35), true),
		_e("message_stone", 736, 1009, 48, 52, "留言石", Color(0.5, 0.55, 0.7), true),
		_e("to_market", 888, 1488, 64, 56, "下城市集", Color(0.5, 0.4, 0.3)),
		_e("market", 1096, 1027, 64, 52, "攤位殘架", Color(0.5, 0.4, 0.3), true),
		_e("ding", 848, 1176, 48, 64, "釘釘·鐵匠", Color(0.7, 0.4, 0.25)),
		_e("forge_sign", 978, 1133, 44, 44, "鐵匠招牌", Color(0.55, 0.4, 0.25)),
		_e("fountain", 1832, 1170, 64, 52, "乾涸水池", Color(0.4, 0.45, 0.5), true),
		_e("flag", 1760, 828, 48, 56, flag_label, Color(0.85, 0.75, 0.35), true),
		_e("star", 2304, 1015, 48, 64, "星讀", Color(0.45, 0.5, 0.75)),
		_e("bench", 2176, 1150, 48, 36, "石凳", Color(0.45, 0.45, 0.48)),
		_e("sprout", 1616, 1577, 48, 64, "小芽", Color(0.55, 0.75, 0.45)),
		_e("silk", 2224, 855, 48, 64, "絲絨·書吏", Color(0.55, 0.5, 0.65)),
		_e("to_barracks_yard", 792, 1398, 64, 56, "演武場", Color(0.4, 0.38, 0.4)),
		_e("barracks", 676, 1291, 72, 64, "舊兵營", Color(0.4, 0.38, 0.4), true),
		_e("chapel", 1544, 803, 64, 72, "小禮拜堂", Color(0.45, 0.42, 0.48), true),
		_e("to_sewers", 1356, 1648, 56, 48, "下水道口", Color(0.3, 0.32, 0.3)),
		_e("gate_arch", 1116, 803, 56, 72, "內城門影", Color(0.4, 0.38, 0.42), true),
		_e("exit_keep", 1236, 820, 72, 72, "進入內城", Color(0.45, 0.4, 0.35)),
		_e("exit_wild", 2820, 463, 72, 72, "出城荒野", Color(0.35, 0.4, 0.3)),
		_e("exit_world", 668, 1202, 56, 56, "六域地圖", Color(0.4, 0.5, 0.55)),
		_e("menu_save", 1040, 1585, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("stable", 2296, 1335, 64, 56, "空馬廄", Color(0.42, 0.36, 0.3), true),
	]
	return m


static func _town_keep() -> Dictionary:
	var m := _base("騎士堡 · 內城與內殿道", Color(0.09, 0.09, 0.12), 2600, 1451, Vector2(690, 1154), "town")
	m["entities"] = [
		_e("back_town", 571, 1170, 56, 56, "回外城廣場", Color(0.4, 0.4, 0.45)),
		_e("hall", 936, 675, 80, 72, "騎士舊廳", Color(0.4, 0.38, 0.42), true),
		_e("armor", 1177, 677, 40, 56, "空盔甲架", Color(0.5, 0.5, 0.55)),
		_e("throne_hall", 1421, 662, 72, 64, "議政廳門", Color(0.45, 0.4, 0.35), true),
		_e("keep_well", 1264, 961, 48, 48, "內井", Color(0.4, 0.42, 0.48), true),
		_e("statue_knight", 679, 829, 48, 64, "無名騎士像", Color(0.5, 0.48, 0.5), true),
		_e("archive", 1741, 706, 56, 56, "檔案庫門", Color(0.42, 0.4, 0.45), true),
		_e("silk", 1810, 858, 48, 64, "絲絨·書吏", Color(0.55, 0.5, 0.65)),
		_e("codex_shelf", 1862, 787, 48, 48, "典籍架", Color(0.45, 0.4, 0.5), true),
		_e("exit_wild_inner", 1044, 1322, 72, 64, "側門·荒野", Color(0.35, 0.4, 0.3)),
		_e("to_leo_court", 2309, 387, 64, 56, "內殿前院道", Color(0.5, 0.4, 0.3)),
	]
	return m


static func _town_market() -> Dictionary:
	var m := _base("騎士堡 · 下城市集", Color(0.11, 0.1, 0.12), 2600, 1451, Vector2(200, 648), "town_market")
	m["entities"] = [
		_e("back_from_market", 100, 624, 56, 56, "回廣場", Color(0.4, 0.4, 0.45)),
		_e("stall_a", 400, 477, 56, 48, "布攤", Color(0.55, 0.4, 0.35), true),
		_e("stall_b", 600, 598, 56, 48, "藥草攤", Color(0.4, 0.55, 0.35), true),
		_e("stall_c", 800, 501, 56, 48, "空攤", Color(0.45, 0.4, 0.35), true),
		_e("scale_table", 1000, 717, 48, 40, "天秤台", Color(0.5, 0.48, 0.4)),
		_e("beggar", 1200, 840, 40, 48, "坐地老人", Color(0.4, 0.38, 0.35)),
		_e("alley_dark", 1500, 539, 48, 56, "窄巷", Color(0.3, 0.3, 0.32)),
		_e("spice_smell", 1800, 657, 48, 40, "香料殘跡", Color(0.55, 0.4, 0.3)),
		_e("to_sewers", 2100, 961, 56, 48, "市集下水口", Color(0.3, 0.32, 0.3)),
	]
	return m


static func _town_sewers() -> Dictionary:
	var m := _base("騎士堡 · 舊下水道", Color(0.06, 0.08, 0.07), 2400, 1350, Vector2(200, 580), "town_sewers")
	m["entities"] = [
		_e("back_from_sewers", 100, 572, 56, 56, "爬回地面", Color(0.4, 0.4, 0.45)),
		_e("pipe_a", 500, 394, 64, 48, "鐵管", Color(0.35, 0.38, 0.35), true),
		_e("slime_pool", 800, 661, 72, 40, "黏液池", Color(0.3, 0.4, 0.3), true),
		_e("rat_nest", 1100, 526, 48, 40, "鼠窩", Color(0.35, 0.3, 0.28)),
		_e("sealed_door", 1500, 467, 56, 64, "封死鐵門", Color(0.4, 0.4, 0.42), true),
		_e("echo_drip", 1800, 728, 40, 40, "滴水聲", Color(0.4, 0.45, 0.5)),
		_e("ladder_out", 2100, 559, 48, 56, "另一出口", Color(0.4, 0.42, 0.4)),
	]
	return m


static func _barracks_yard() -> Dictionary:
	var m := _base("騎士堡 · 演武場", Color(0.1, 0.1, 0.12), 2400, 1340, Vector2(200, 592), "barracks_yard")
	var blade_lab := "空武器架" if GameState.has_flag("item.broken_blade") or GameState.has_flag("side.ding_debt_done") else "武器架（斷劍）"
	m["entities"] = [
		_e("back_from_barracks", 100, 579, 56, 56, "回廣場", Color(0.4, 0.4, 0.45)),
		_e("training_ring", 700, 487, 100, 80, "圓形演武台", Color(0.45, 0.4, 0.35), true),
		_e("weapon_rack", 500, 665, 48, 56, blade_lab, Color(0.5, 0.45, 0.4), true),
		_e("target_dummy", 1000, 604, 40, 56, "木靶", Color(0.45, 0.35, 0.28)),
		_e("banner_stand", 1200, 362, 40, 64, "團旗架", Color(0.55, 0.4, 0.3), true),
		_e("officer_desk", 1500, 541, 56, 48, "隊長桌", Color(0.4, 0.35, 0.3), true),
		_e("sand_pit", 1800, 724, 80, 48, "沙坑", Color(0.5, 0.45, 0.35)),
		_e("knight_orphan", 1600, 727, 48, 64, "遺孤少年", Color(0.5, 0.48, 0.55)),
	]
	return m


static func _wild() -> Dictionary:
	var m := _base("城外荒野 · 焦土平原", Color(0.08, 0.12, 0.08), 3200, 1800, Vector2(180, 813), "wild")
	var ents: Array = [
		_e("back_town", 100, 765, 56, 56, "回城", Color(0.35, 0.4, 0.35)),
		_e("burnt_field", 400, 891, 64, 48, "焦麥田邊", Color(0.45, 0.38, 0.2)),
		_e("camp", 600, 699, 64, 52, "焦麥田", Color(0.45, 0.4, 0.2), true),
		_e("scarecrow", 800, 572, 40, 56, "燒焦稻草人", Color(0.4, 0.35, 0.25)),
		_e("wild_shrine", 500, 442, 44, 52, "路邊小祠", Color(0.45, 0.4, 0.35)),
		_e("supply_crate", 900, 953, 48, 40, "補給箱", Color(0.5, 0.4, 0.3)),
		_e("tower", 1300, 448, 56, 72, "廢棄哨塔", Color(0.4, 0.38, 0.35), true),
		_e("to_wild_ravine", 1600, 1150, 64, 56, "深裂谷", Color(0.3, 0.28, 0.25)),
		_e("rubble", 1800, 824, 52, 40, "石牆碎塊", Color(0.4, 0.38, 0.36)),
		_e("trail_mark", 2000, 631, 44, 40, "爪印土", Color(0.35, 0.4, 0.3)),
		_e("ravine", 1200, 1403, 100, 40, "乾裂溝", Color(0.3, 0.28, 0.25), true),
		_e("hill_view", 2400, 377, 56, 48, "遠眺丘", Color(0.35, 0.4, 0.3)),
	]
	if GameState.has_flag("boss.leo_cleared"):
		ents.append(_e("path_mist", 2300, 1088, 72, 64, "霧道（東南方）", Color(0.5, 0.55, 0.7)))
		ents.append(_e("path_crossroads", 2700, 831, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)))
		ents.append(_e("to_leo_court", 2800, 572, 64, 56, "內殿前院", Color(0.5, 0.4, 0.3)))
		ents.append(_e("leo_gate", 2900, 617, 72, 80, "內殿（已通）", Color(0.4, 0.35, 0.25), true))
	else:
		ents.append(_e("to_leo_court", 2600, 636, 64, 56, "內殿前院", Color(0.55, 0.4, 0.25)))
		ents.append(_e("leo_gate", 2750, 671, 80, 88, "內殿·雷歐", Color(0.65, 0.45, 0.2), true))
	m["entities"] = ents
	return m


static func _wild_ravine() -> Dictionary:
	var m := _base("荒野 · 深裂谷", Color(0.07, 0.09, 0.07), 2400, 1350, Vector2(200, 595), "wild_ravine")
	m["entities"] = [
		_e("back_wild", 100, 584, 56, 56, "回平原", Color(0.35, 0.4, 0.3)),
		_e("cliff_edge", 600, 420, 80, 40, "崖緣", Color(0.35, 0.32, 0.28), true),
		_e("rope_bridge", 1000, 543, 100, 40, "繩橋", Color(0.45, 0.38, 0.3), true),
		_e("bone_pile", 1300, 727, 48, 40, "獸骨", Color(0.5, 0.48, 0.45)),
		_e("echo_canyon", 1600, 484, 56, 48, "回音峽", Color(0.35, 0.4, 0.38)),
		_e("black_vein", 1900, 666, 56, 40, "黑焰脈紋", Color(0.3, 0.2, 0.35)),
	]
	return m


static func _wild_leo_court() -> Dictionary:
	var m := _base("荒野 · 內殿前院", Color(0.1, 0.09, 0.08), 2400, 1350, Vector2(200, 595), "wild_leo_court")
	m["entities"] = [
		_e("back_wild", 100, 584, 56, 56, "回焦土", Color(0.35, 0.4, 0.3)),
		_e("lion_statue", 600, 368, 64, 80, "石獅像", Color(0.55, 0.45, 0.3), true),
		_e("courtyard", 1000, 550, 100, 72, "石板院", Color(0.45, 0.4, 0.35), true),
		_e("banner_torn", 800, 424, 40, 56, "撕破旗", Color(0.5, 0.35, 0.25)),
		_e("leo_gate", 1800, 517, 80, 88, "內殿·雷歐", Color(0.65, 0.45, 0.2), true),
		_e("honor_plaque", 1400, 361, 48, 48, "榮譽碑", Color(0.5, 0.48, 0.4), true),
	]
	return m


# ═══════════════════════════════════════════
#  岔路與秘境
# ═══════════════════════════════════════════

static func _crossroads() -> Dictionary:
	var m := _base("六域岔路 · 翠嶺之心道", Color(0.1, 0.12, 0.1), 3000, 1674, Vector2(1400, 781), "road")
	var ents: Array = [
		_e("sign_board", 1400, 627, 64, 56, "六域路標", Color(0.45, 0.4, 0.3), true),
		_e("camp_fire", 1250, 856, 48, 48, "旅人營火", Color(0.9, 0.4, 0.15), true),
		_e("merchant", 1500, 889, 48, 64, "行商", Color(0.6, 0.5, 0.4)),
		_e("path_knight", 400, 784, 72, 64, "西·騎士堡", Color(0.5, 0.45, 0.4)),
		_e("path_mist_c", 1400, 1412, 72, 64, "南·霧隱", Color(0.5, 0.55, 0.7)),
		_e("path_dojo_c", 1400, 209, 72, 64, "北·道場", Color(0.4, 0.55, 0.35)),
		_e("path_forest_c", 2300, 418, 72, 64, "東北·森林", Color(0.35, 0.55, 0.4)),
		_e("path_coast_c", 2300, 1150, 72, 64, "東南·海岸", Color(0.4, 0.55, 0.65)),
		_e("path_tower_c", 2600, 784, 72, 64, "東·法師之塔", Color(0.45, 0.35, 0.55)),
		_e("to_cross_north", 900, 260, 64, 56, "北山道", Color(0.4, 0.5, 0.4)),
		_e("to_cross_east", 2400, 784, 64, 56, "東塔荒原道", Color(0.4, 0.35, 0.45)),
		_e("to_caravan", 700, 1045, 64, 56, "行商驛站", Color(0.55, 0.45, 0.35)),
		_e("to_starfall", 500, 417, 64, 56, "星落平原", Color(0.45, 0.5, 0.7)),
		_e("to_hunt", 600, 836, 64, 56, "星途獵場", Color(0.65, 0.35, 0.4)),
		_e("ruin_pillar", 900, 522, 40, 64, "古柱", Color(0.4, 0.38, 0.36), true),
		_e("save_cross", 1100, 731, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("world_map_stone", 1600, 679, 56, 48, "世界輿圖石", Color(0.4, 0.5, 0.55)),
	]
	## 雷歐後、未完結前：岔路擋道的黑焰浪人
	if GameState.has_flag("boss.leo_cleared") and not GameState.has_flag("side.ronin_done"):
		ents.append(_e("ronin", 1750, 941, 52, 68, "黑焰浪人", Color(0.35, 0.2, 0.35)))
	elif GameState.has_flag("side.ronin_spared"):
		ents.append(_e("ronin", 1750, 941, 48, 64, "浪人（收刃）", Color(0.4, 0.35, 0.4)))
	m["entities"] = ents
	return m


static func _cross_north() -> Dictionary:
	var m := _base("岔路 · 北山道", Color(0.09, 0.12, 0.1), 2400, 1350, Vector2(760, 1295), "cross_north")
	m["entities"] = [
		_e("back_cross", 732, 1266, 56, 56, "回岔路", Color(0.45, 0.5, 0.4)),
		_e("switchback", 728, 1004, 64, 48, "之字坡", Color(0.4, 0.42, 0.38)),
		_e("pine_row", 288, 969, 80, 56, "松林", Color(0.3, 0.45, 0.35), true),
		_e("wayshrine", 1744, 969, 48, 56, "山神小祠", Color(0.45, 0.42, 0.4), true),
		_e("path_dojo_c", 2164, 934, 72, 64, "通往道場", Color(0.4, 0.55, 0.35)),
		_e("cloud_view", 1164, 653, 56, 48, "雲海眺望", Color(0.5, 0.55, 0.6)),
	]
	return m


static func _cross_east() -> Dictionary:
	var m := _base("岔路 · 東塔荒原道", Color(0.1, 0.09, 0.14), 2600, 1462, Vector2(196, 1103), "cross_east")
	m["entities"] = [
		_e("back_cross", 142, 1077, 56, 56, "回岔路", Color(0.45, 0.5, 0.4)),
		_e("dead_trees", 394, 930, 72, 56, "枯樹陣", Color(0.35, 0.3, 0.35), true),
		_e("ash_wind", 922, 1180, 56, 40, "灰風帶", Color(0.4, 0.35, 0.4)),
		_e("to_blackflame_scar", 1308, 828, 64, 56, "黑焰疤地", Color(0.35, 0.2, 0.4)),
		_e("path_tower_c", 2292, 893, 72, 64, "塔下方向", Color(0.45, 0.35, 0.55)),
		_e("watch_rock", 1654, 690, 48, 48, "眺望岩", Color(0.4, 0.38, 0.42)),
	]
	return m


static func _caravan_camp() -> Dictionary:
	var m := _base("行商驛站 · 星途旅人落腳處", Color(0.1, 0.11, 0.12), 2400, 1340, Vector2(200, 592), "caravan_camp")
	var letter_lab := "行商頭領" if not GameState.has_flag("item.true_letter") else "行商（待交信）"
	m["entities"] = [
		_e("back_cross", 100, 579, 56, 56, "回岔路", Color(0.45, 0.5, 0.4)),
		_e("wagon_a", 500, 482, 72, 56, "篷車", Color(0.5, 0.4, 0.3), true),
		_e("wagon_b", 800, 604, 72, 56, "篷車", Color(0.48, 0.38, 0.28), true),
		_e("merchant", 1000, 545, 48, 64, letter_lab, Color(0.6, 0.5, 0.4)),
		_e("amber", 1100, 630, 48, 64, "琥珀·商人", Color(0.75, 0.55, 0.3)),
		_e("camp_fire", 1200, 663, 48, 48, "營火", Color(0.9, 0.4, 0.15), true),
		_e("goods_pile", 1500, 480, 56, 48, "貨堆", Color(0.45, 0.4, 0.35)),
		_e("map_table", 1700, 600, 48, 40, "地圖桌", Color(0.5, 0.45, 0.35)),
		_e("guard_dog", 600, 782, 40, 36, "守車犬", Color(0.4, 0.35, 0.3)),
	]
	return m


static func _starfall_plain() -> Dictionary:
	var m := _base("星落平原 · 十四星夜空", Color(0.05, 0.06, 0.12), 2800, 1563, Vector2(200, 692), "starfall_plain")
	m["entities"] = [
		_e("back_cross", 100, 670, 56, 56, "回岔路", Color(0.45, 0.5, 0.4)),
		_e("meteor_stone", 600, 511, 56, 48, "隕星石", Color(0.5, 0.55, 0.75), true),
		_e("constellation", 1000, 381, 64, 48, "星圖刻地", Color(0.45, 0.5, 0.7)),
		_e("star_reader_camp", 1400, 709, 56, 56, "星讀帳篷", Color(0.4, 0.4, 0.55), true),
		_e("night_bloom", 1800, 835, 40, 40, "夜開花", Color(0.5, 0.4, 0.6)),
		_e("wish_pool", 2100, 576, 64, 48, "許願淺池" + ("（已許）" if GameState.has_flag("side.star_wish_done") else ""), Color(0.35, 0.4, 0.55), true),
		_e("to_road_ruins", 2400, 904, 64, 56, "接古驛", Color(0.4, 0.38, 0.35)),
	]
	return m


static func _hunting_grounds() -> Dictionary:
	var m := _base("星途獵場 · 黑焰溢地", Color(0.09, 0.06, 0.08), 3000, 1674, Vector2(400, 762), "hunting_grounds")
	m["entities"] = [
		_e("hunt_board", 600, 595, 72, 64, "狩獵告示", Color(0.65, 0.4, 0.35), true),
		_e("hunt_start", 800, 653, 64, 56, "開始狩獵", Color(0.75, 0.35, 0.4)),
		_e("hunt_recycler", 1100, 571, 56, 64, "溢物回收", Color(0.55, 0.5, 0.4)),
		_e("camp_ash", 500, 829, 56, 40, "獵手餘燼", Color(0.4, 0.3, 0.25)),
		_e("bone_pile", 1400, 710, 48, 40, "獸骨堆", Color(0.5, 0.48, 0.45)),
		_e("scar_vein", 1700, 530, 56, 40, "溢脈", Color(0.35, 0.2, 0.35)),
		_e("save_hunt", 350, 1070, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("back_cross", 200, 713, 56, 56, "回岔路", Color(0.45, 0.5, 0.4)),
		_e("exit_world", 2500, 593, 56, 56, "世界輿圖", Color(0.4, 0.5, 0.55)),
		_e("path_knight", 2200, 1071, 64, 56, "往騎士堡", Color(0.5, 0.45, 0.4)),
	]
	return m


static func _blackflame_scar() -> Dictionary:
	var m := _base("黑焰疤地 · 被吞噬的土地", Color(0.08, 0.05, 0.1), 2600, 1451, Vector2(200, 648), "blackflame_scar")
	m["entities"] = [
		_e("back_cross", 100, 624, 56, 56, "退回荒原道", Color(0.4, 0.35, 0.45)),
		_e("char_soil", 500, 537, 80, 48, "焦裂地", Color(0.25, 0.15, 0.2), true),
		_e("flame_vent", 900, 479, 48, 56, "焰口", Color(0.5, 0.2, 0.45), true),
		_e("obsidian", 1200, 657, 48, 40, "黑曜碎", Color(0.2, 0.18, 0.25)),
		_e("lost_banner", 1500, 418, 40, 56, "半融旗", Color(0.4, 0.25, 0.3)),
		_e("whisper_stone", 1800, 598, 48, 48, "低語石", Color(0.35, 0.25, 0.4), true),
		_e("scar_boss", 2000, 510, 80, 88, "黑焰疤主", Color(0.65, 0.25, 0.45)),
		_e("path_tower_c", 2200, 662, 72, 64, "疤地盡頭·塔", Color(0.45, 0.35, 0.55)),
	]
	return m


# ═══════════════════════════════════════════
#  霧隱
# ═══════════════════════════════════════════

static func _mist() -> Dictionary:
	var m := _base("霧隱村 · 外圍", Color(0.1, 0.11, 0.16), 3000, 1674, Vector2(180, 750), "mist_village")
	var ents: Array = [
		_e("fog_hide", 280, 575, 48, 64, "霧隱", Color(0.5, 0.55, 0.7)),
		_e("lantern", 400, 401, 36, 40, "霧燈", Color(0.55, 0.55, 0.7)),
		_e("well_fog", 520, 505, 44, 44, "霧井", Color(0.4, 0.45, 0.55), true),
		_e("inn", 700, 766, 64, 56, "客棧（營火）", Color(0.55, 0.4, 0.3)),
		_e("laundry", 900, 426, 48, 40, "曬衣繩", Color(0.55, 0.5, 0.6)),
		_e("cat_shadow", 1000, 889, 40, 36, "影貓", Color(0.35, 0.35, 0.4)),
		_e("train", 1300, 570, 48, 48, "霧廊訓練", Color(0.4, 0.45, 0.55)),
		_e("shrine", 1500, 379, 48, 56, "霧祠", Color(0.45, 0.48, 0.6), true),
		_e("to_mist_shrine", 1600, 351, 56, 48, "霧祠深處", Color(0.45, 0.5, 0.65)),
		_e("alley_gate", 1800, 701, 64, 56, "深巷入口", Color(0.4, 0.42, 0.5)),
		_e("to_mist_cliff", 2000, 379, 64, 56, "霧崖", Color(0.45, 0.5, 0.6)),
		_e("to_mist_mirror", 2200, 830, 64, 56, "鏡廊", Color(0.5, 0.55, 0.7)),
		_e("fog_gate", 2500, 646, 80, 88, "幻廊·白霧", Color(0.65, 0.7, 0.85)),
		_e("save_c2", 140, 1343, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("back_knight", 100, 441, 56, 48, "回騎士堡", Color(0.4, 0.4, 0.45)),
		_e("exit_cross_m", 2750, 1283, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)),
	]
	if GameState.has_flag("boss.white_fog_cleared"):
		ents.append(_e("path_dojo", 2300, 1347, 72, 64, "山道·道場", Color(0.4, 0.55, 0.35)))
	m["entities"] = ents
	return m


static func _mist_deep() -> Dictionary:
	var m := _base("霧隱 · 深巷與影廊前", Color(0.08, 0.09, 0.14), 2200, 1228, Vector2(200, 534), "mist_village")
	m["entities"] = [
		_e("back_mist", 100, 523, 56, 56, "回霧隱村", Color(0.45, 0.5, 0.6)),
		_e("mirror", 500, 389, 48, 64, "霧鏡", Color(0.5, 0.55, 0.65), true),
		_e("mask_shop", 800, 584, 56, 56, "面具攤", Color(0.45, 0.4, 0.5), true),
		_e("echo_well", 1100, 459, 48, 48, "回聲井", Color(0.4, 0.45, 0.55), true),
		_e("to_mist_mirror", 1400, 607, 56, 48, "鏡廊入口", Color(0.5, 0.55, 0.7)),
		_e("fog_gate_deep", 1800, 516, 72, 80, "幻廊側門", Color(0.65, 0.7, 0.85)),
	]
	return m


static func _mist_cliff() -> Dictionary:
	var m := _base("霧隱 · 霧崖觀台", Color(0.09, 0.1, 0.15), 2200, 1238, Vector2(200, 538), "mist_cliff")
	m["entities"] = [
		_e("back_from_mist_sub", 100, 527, 56, 56, "回霧隱村", Color(0.45, 0.5, 0.6)),
		_e("cliff_rail", 600, 422, 100, 32, "崖欄", Color(0.4, 0.42, 0.5), true),
		_e("fog_sea", 900, 611, 80, 48, "霧海", Color(0.5, 0.55, 0.65)),
		_e("bell_tower", 1300, 369, 48, 72, "霧鐘樓", Color(0.45, 0.45, 0.55), true),
		_e("kite_string", 1600, 486, 40, 40, "斷線風箏", Color(0.55, 0.5, 0.45)),
		_e("overlook", 1800, 549, 56, 48, "遠眺六域", Color(0.45, 0.5, 0.6)),
	]
	return m


static func _mist_shrine() -> Dictionary:
	var m := _base("霧隱 · 霧祠內殿", Color(0.08, 0.09, 0.14), 2000, 1116, Vector2(200, 479), "mist_shrine")
	var incense_lab := "香爐（已燃）" if GameState.has_flag("side.fog_incense_done") else "香爐"
	m["entities"] = [
		_e("back_from_mist_sub", 100, 466, 56, 56, "出祠", Color(0.45, 0.5, 0.6)),
		_e("fox_statue", 600, 350, 56, 64, "白狐像", Color(0.7, 0.72, 0.8), true),
		_e("incense", 900, 522, 40, 40, incense_lab, Color(0.5, 0.45, 0.4)),
		_e("prayer_strip", 1100, 407, 48, 56, "願條", Color(0.55, 0.5, 0.6)),
		_e("secret_panel", 1500, 464, 48, 48, "暗板", Color(0.4, 0.4, 0.5)),
	]
	return m


static func _mist_mirror() -> Dictionary:
	var m := _base("霧隱 · 鏡廊迷宮", Color(0.07, 0.08, 0.13), 2400, 1350, Vector2(200, 595), "mist_mirror")
	m["entities"] = [
		_e("back_from_mist_sub", 100, 584, 56, 56, "出廊", Color(0.45, 0.5, 0.6)),
		_e("mirror_a", 500, 426, 48, 64, "鏡·一", Color(0.55, 0.6, 0.7), true),
		_e("mirror_b", 800, 610, 48, 64, "鏡·二", Color(0.5, 0.55, 0.65), true),
		_e("mirror_c", 1100, 426, 48, 64, "鏡·三", Color(0.55, 0.58, 0.7), true),
		_e("false_exit", 1400, 729, 56, 48, "假出口", Color(0.4, 0.42, 0.5)),
		_e("true_path", 1800, 484, 56, 48, "真影道", Color(0.5, 0.55, 0.75)),
		_e("mirror_boss", 1950, 517, 80, 88, "鏡廊殘影", Color(0.7, 0.75, 0.9)),
		_e("fog_gate_deep", 2100, 552, 72, 80, "幻廊核心", Color(0.65, 0.7, 0.85)),
	]
	return m


# ═══════════════════════════════════════════
#  道場
# ═══════════════════════════════════════════

static func _dojo() -> Dictionary:
	var m := _base("武鬥道場 · 山門院落", Color(0.12, 0.14, 0.1), 2800, 1563, Vector2(264, 1393), "dojo")
	var ents: Array = [
		_e("acha", 688, 641, 48, 64, "阿茶", Color(0.7, 0.55, 0.4)),
		_e("gate_bell", 1248, 172, 48, 64, "山門鐘", Color(0.55, 0.5, 0.35)),
		_e("training_dummy", 804, 837, 40, 56, "木人樁", Color(0.5, 0.4, 0.3)),
		_e("scroll_wall", 1416, 407, 48, 48, "拳譜牆", Color(0.45, 0.42, 0.35), true),
		_e("stone_garden", 964, 567, 56, 44, "石庭", Color(0.4, 0.45, 0.4)),
		_e("tea", 1752, 563, 48, 48, "茶席", Color(0.5, 0.4, 0.3)),
		_e("to_dojo_inner", 1744, 837, 64, 56, "內院", Color(0.4, 0.5, 0.35)),
		_e("to_dojo_bamboo", 1464, 1056, 64, 56, "竹林徑", Color(0.35, 0.5, 0.35)),
		_e("to_dojo_peak", 1856, 1243, 64, 56, "山巔道", Color(0.4, 0.48, 0.4)),
		_e("trial_hall", 2296, 1305, 80, 88, "試煉堂·阿波", Color(0.35, 0.5, 0.3)),
		_e("dorm", 848, 962, 64, 56, "僧寮", Color(0.4, 0.38, 0.32), true),
		_e("save_c3", 408, 1251, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("back_mist", 180, 1407, 56, 48, "回霧隱村", Color(0.45, 0.5, 0.6)),
		_e("exit_cross_d", 228, 1454, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)),
	]
	if GameState.has_flag("boss.abo_cleared"):
		ents.append(_e("path_forest", 452, 1391, 72, 64, "林道·遊俠", Color(0.35, 0.55, 0.4)))
		ents.append(_e("path_tower", 2468, 1391, 72, 64, "向塔之路", Color(0.4, 0.3, 0.5)))
	m["entities"] = ents
	return m


static func _dojo_inner() -> Dictionary:
	var m := _base("道場 · 內院與靜室", Color(0.11, 0.13, 0.1), 2200, 1238, Vector2(700, 996), "dojo_inner")
	m["entities"] = [
		_e("back_dojo", 672, 915, 56, 56, "回山門", Color(0.4, 0.5, 0.35)),
		_e("zen_pond", 792, 725, 80, 48, "靜心池", Color(0.35, 0.45, 0.5), true),
		_e("scripture", 1160, 668, 48, 56, "經閣", Color(0.45, 0.4, 0.35), true),
		_e("meditation", 1464, 800, 56, 48, "打坐席", Color(0.4, 0.42, 0.35)),
		_e("master_room", 1812, 841, 64, 56, "掌門靜室", Color(0.42, 0.38, 0.32), true),
	]
	return m


static func _dojo_bamboo() -> Dictionary:
	var m := _base("道場 · 竹林徑", Color(0.08, 0.14, 0.09), 2400, 1350, Vector2(472, 1052), "dojo_bamboo")
	m["entities"] = [
		_e("back_dojo", 444, 969, 56, 56, "回山門", Color(0.4, 0.5, 0.35)),
		_e("bamboo_wall", 672, 718, 80, 64, "竹牆", Color(0.3, 0.5, 0.35), true),
		_e("stream_stone", 1120, 823, 48, 40, "溪石", Color(0.4, 0.45, 0.4)),
		_e("hidden_spar", 1692, 842, 56, 48, "隱切磋場", Color(0.4, 0.48, 0.35)),
		_e("leaf_pile", 1936, 1043, 48, 36, "落葉堆", Color(0.4, 0.45, 0.3)),
		_e("to_dojo_peak", 1208, 240, 64, 56, "上山巔", Color(0.4, 0.48, 0.4)),
	]
	return m


static func _dojo_peak() -> Dictionary:
	var m := _base("道場 · 山巔試煉台", Color(0.12, 0.14, 0.16), 2200, 1228, Vector2(480, 989), "dojo_peak")
	m["entities"] = [
		_e("back_dojo", 452, 908, 56, 56, "下山", Color(0.4, 0.5, 0.35)),
		_e("peak_platform", 980, 769, 100, 72, "試煉台", Color(0.45, 0.42, 0.38), true),
		_e("wind_flag", 1054, 491, 40, 56, "風旗", Color(0.5, 0.45, 0.35)),
		_e("trial_hall", 1364, 852, 80, 88, "巔上·阿波影", Color(0.35, 0.5, 0.3)),
		_e("sunrise_view", 1948, 327, 56, 48, "日出眺", Color(0.6, 0.5, 0.4)),
	]
	return m


# ═══════════════════════════════════════════
#  森林
# ═══════════════════════════════════════════

static func _forest() -> Dictionary:
	var m := _base("遊俠森林 · 樹海邊緣", Color(0.06, 0.12, 0.08), 3200, 1786, Vector2(180, 807), "forest")
	var ents: Array = [
		_e("wind_ear", 320, 659, 48, 64, "風耳", Color(0.45, 0.7, 0.5)),
		_e("treehouse", 600, 442, 64, 64, "樹屋聚落", Color(0.4, 0.55, 0.35)),
		_e("kite_stuck", 480, 346, 40, 40, "卡住的風箏", Color(0.7, 0.5, 0.4)),
		_e("arrow_path", 1100, 731, 56, 48, "箭道", Color(0.35, 0.5, 0.4)),
		_e("watch_tower", 1400, 353, 48, 64, "觀風塔", Color(0.45, 0.5, 0.4)),
		_e("herb_slope", 900, 1076, 48, 48, "藥草坡", Color(0.4, 0.6, 0.35)),
		_e("stream", 1000, 600, 48, 36, "溪流", Color(0.35, 0.5, 0.55)),
		_e("owl_post", 1300, 527, 40, 48, "貓頭鷹樁", Color(0.4, 0.35, 0.3)),
		_e("deep_gate", 1800, 823, 64, 56, "深林入口", Color(0.3, 0.45, 0.3)),
		_e("to_forest_canopy", 1600, 376, 64, 56, "樹冠層", Color(0.35, 0.55, 0.4)),
		_e("to_forest_lake", 2000, 1142, 64, 56, "靜湖", Color(0.35, 0.5, 0.55)),
		_e("to_forest_ruins", 2300, 631, 64, 56, "古遊俠遺址", Color(0.4, 0.45, 0.35)),
		_e("falcon_nest", 2700, 704, 80, 88, "疾影巢", Color(0.4, 0.75, 0.55)),
		_e("save_c4", 140, 1458, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("back_dojo", 100, 438, 56, 48, "回道場", Color(0.4, 0.45, 0.35)),
		_e("exit_cross_f", 2900, 1399, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)),
	]
	if GameState.has_flag("boss.shadowwind_cleared"):
		ents.append(_e("path_coast", 2400, 1463, 72, 64, "海岸道", Color(0.4, 0.55, 0.65)))
	m["entities"] = ents
	return m


static func _forest_deep() -> Dictionary:
	var m := _base("深林 · 風道迷宮", Color(0.05, 0.1, 0.06), 2600, 1451, Vector2(200, 648), "forest")
	m["entities"] = [
		_e("back_forest", 100, 624, 56, 56, "回樹海邊緣", Color(0.35, 0.5, 0.4)),
		_e("wind_tunnel", 600, 537, 64, 48, "風道", Color(0.4, 0.6, 0.5)),
		_e("nest_mark", 1100, 417, 48, 48, "羽痕石", Color(0.45, 0.5, 0.4)),
		_e("hidden_cache", 1500, 778, 48, 40, "獵人藏匿處", Color(0.4, 0.35, 0.3)),
		_e("to_forest_canopy", 1800, 356, 56, 48, "爬上樹冠", Color(0.35, 0.55, 0.4)),
		_e("falcon_nest_deep", 2200, 605, 72, 80, "疾影巢（近）", Color(0.4, 0.75, 0.55)),
	]
	return m


static func _forest_canopy() -> Dictionary:
	var m := _base("森林 · 樹冠層", Color(0.08, 0.14, 0.1), 2400, 1350, Vector2(200, 595), "forest_canopy")
	m["entities"] = [
		_e("back_from_forest_sub", 100, 584, 56, 56, "下樹", Color(0.35, 0.5, 0.4)),
		_e("bridge_rope", 700, 482, 100, 40, "藤橋", Color(0.4, 0.45, 0.3), true),
		_e("nest_platform", 1100, 424, 64, 56, "巢台", Color(0.45, 0.5, 0.35), true),
		_e("wind_chime", 1400, 359, 40, 40, "風鈴", Color(0.5, 0.55, 0.45)),
		_e("eagle_view", 1800, 545, 56, 48, "鷹眼眺望", Color(0.4, 0.55, 0.5)),
		_e("to_forest_ruins", 2000, 729, 56, 48, "藤蔓下·遺址", Color(0.4, 0.45, 0.35)),
	]
	return m


static func _forest_ruins() -> Dictionary:
	var m := _base("森林 · 古遊俠遺址", Color(0.07, 0.1, 0.08), 2400, 1350, Vector2(200, 595), "forest_ruins")
	m["entities"] = [
		_e("back_from_forest_sub", 100, 584, 56, 56, "回樹海", Color(0.35, 0.5, 0.4)),
		_e("arch_ruin", 600, 426, 72, 64, "石拱廢墟", Color(0.45, 0.42, 0.38), true),
		_e("bow_relief", 1000, 485, 48, 56, "弓神浮雕", Color(0.4, 0.45, 0.4), true),
		_e("arrow_well", 1300, 668, 48, 48, "箭井", Color(0.35, 0.4, 0.38), true),
		_e("moss_script", 1600, 420, 56, 40, "苔文", Color(0.35, 0.5, 0.35)),
		_e("chest_root", 1900, 605, 48, 40, "根纏箱", Color(0.4, 0.35, 0.28)),
	]
	return m


static func _forest_lake() -> Dictionary:
	var m := _base("森林 · 靜湖", Color(0.06, 0.11, 0.12), 2400, 1340, Vector2(200, 592), "forest_lake")
	m["entities"] = [
		_e("back_from_forest_sub", 100, 579, 56, 56, "回樹海", Color(0.35, 0.5, 0.4)),
		_e("lake_shore", 800, 541, 120, 48, "湖岸", Color(0.35, 0.5, 0.55), true),
		_e("reed", 600, 661, 48, 40, "蘆葦", Color(0.4, 0.5, 0.35)),
		_e("dock_log", 1100, 599, 64, 36, "原木碼頭", Color(0.45, 0.4, 0.3)),
		_e("reflection", 1400, 480, 56, 48, "倒影奇", Color(0.4, 0.5, 0.55)),
		_e("heron", 1700, 419, 40, 48, "蒼鷺", Color(0.5, 0.55, 0.5)),
	]
	return m


# ═══════════════════════════════════════════
#  海岸
# ═══════════════════════════════════════════

static func _coast() -> Dictionary:
	var m := _base("維京海岸 · 碼頭與岸道", Color(0.12, 0.16, 0.2), 3200, 1786, Vector2(232, 1616), "coast")
	var ents: Array = [
		_e("tide_roar", 624, 1123, 48, 64, "潮吼", Color(0.65, 0.45, 0.35)),
		_e("dock", 1064, 582, 64, 52, "碼頭鎮", Color(0.4, 0.45, 0.5)),
		_e("to_coast_harbor", 1416, 953, 64, 56, "深港", Color(0.4, 0.48, 0.55)),
		_e("boat_wreck", 1480, 1108, 64, 44, "破船骸", Color(0.4, 0.35, 0.3)),
		_e("forge_c5", 720, 810, 48, 56, "岸邊鍛爐", Color(0.7, 0.4, 0.25)),
		_e("net_rack", 880, 719, 48, 40, "漁網架", Color(0.45, 0.4, 0.35)),
		_e("cliff_path", 1068, 782, 56, 48, "峭壁道", Color(0.45, 0.42, 0.4)),
		_e("runestone", 1360, 524, 48, 56, "符文石", Color(0.5, 0.48, 0.55), true),
		_e("to_coast_cave", 1672, 399, 64, 56, "潮汐洞", Color(0.35, 0.4, 0.45)),
		_e("to_coast_wreck", 1992, 310, 64, 56, "沉船灣", Color(0.4, 0.38, 0.35)),
		_e("cliff_gate", 2280, 238, 64, 56, "崖上祭壇道", Color(0.5, 0.4, 0.35)),
		_e("boar_cliff", 2560, 171, 80, 88, "石拳崖", Color(0.6, 0.4, 0.3)),
		_e("save_c5", 464, 1282, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("back_forest", 300, 1461, 56, 48, "回森林", Color(0.35, 0.5, 0.4)),
		_e("exit_cross_c", 132, 1623, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)),
	]
	if GameState.has_flag("boss.stonefist_cleared"):
		ents.append(_e("path_tower_c5", 2756, 248, 72, 64, "向塔之路", Color(0.45, 0.35, 0.55)))
	m["entities"] = ents
	return m


static func _coast_cliff() -> Dictionary:
	var m := _base("崖上 · 祭壇與浪聲", Color(0.1, 0.13, 0.16), 2200, 1228, Vector2(260, 1038), "coast")
	m["entities"] = [
		_e("back_coast", 166, 1056, 56, 56, "回碼頭", Color(0.4, 0.5, 0.55)),
		_e("altar", 514, 552, 64, 56, "浪祭壇", Color(0.5, 0.45, 0.4), true),
		_e("beacon", 702, 421, 40, 64, "烽火台", Color(0.55, 0.4, 0.3), true),
		_e("boar_cliff_near", 1544, 160, 72, 80, "石拳崖近路", Color(0.6, 0.4, 0.3)),
		_e("gull_nest", 1076, 326, 40, 36, "海鷗巢", Color(0.5, 0.48, 0.45)),
	]
	return m


static func _coast_harbor() -> Dictionary:
	var m := _base("海岸 · 深港碼頭", Color(0.1, 0.14, 0.18), 2600, 1451, Vector2(2276, 370), "coast_harbor")
	m["entities"] = [
		_e("back_from_coast_sub", 2248, 227, 56, 56, "回岸道", Color(0.4, 0.5, 0.55)),
		_e("longship", 458, 779, 100, 56, "長船", Color(0.4, 0.35, 0.3), true),
		_e("crane", 1628, 617, 48, 72, "吊桿", Color(0.45, 0.42, 0.4), true),
		_e("warehouse", 2084, 895, 72, 56, "貨倉", Color(0.4, 0.38, 0.35), true),
		_e("tide_gauge", 1528, 1077, 40, 48, "潮位尺", Color(0.4, 0.45, 0.5)),
		_e("captain_post", 1832, 467, 56, 48, "船長柱", Color(0.5, 0.4, 0.35)),
	]
	return m


static func _coast_cave() -> Dictionary:
	var m := _base("海岸 · 潮汐洞", Color(0.08, 0.1, 0.14), 2200, 1238, Vector2(590, 699), "coast_cave")
	m["entities"] = [
		_e("back_from_coast_sub", 540, 618, 56, 56, "出洞", Color(0.4, 0.5, 0.55)),
		_e("tide_pool", 708, 688, 72, 48, "潮池", Color(0.3, 0.4, 0.5), true),
		_e("crystal", 1890, 800, 40, 48, "海晶", Color(0.4, 0.55, 0.65)),
		_e("pirate_mark", 1380, 560, 48, 40, "海盜標記", Color(0.45, 0.35, 0.3)),
		_e("air_hole", 944, 510, 40, 40, "氣孔光", Color(0.5, 0.55, 0.6)),
		_e("deep_water", 1372, 1047, 64, 48, "深水", Color(0.25, 0.3, 0.4), true),
	]
	return m


static func _coast_wreck() -> Dictionary:
	var m := _base("海岸 · 沉船灣", Color(0.1, 0.12, 0.14), 2400, 1339, Vector2(520, 616), "coast_wreck")
	m["entities"] = [
		_e("back_from_coast_sub", 336, 506, 56, 56, "回岸道", Color(0.4, 0.5, 0.55)),
		_e("hull", 844, 651, 120, 72, "船體殘骸", Color(0.4, 0.35, 0.3), true),
		_e("mast", 1016, 442, 40, 80, "斷桅", Color(0.42, 0.38, 0.32), true),
		_e("chest_half", 1228, 736, 48, 40, "半埋箱", Color(0.5, 0.4, 0.25)),
		_e("skull_rock", 1420, 608, 48, 48, "頭骨岩", Color(0.45, 0.42, 0.4)),
		_e("wreck_boss", 720, 722, 80, 88, "沉船船長影", Color(0.45, 0.55, 0.7)),
		_e("to_coast_cave", 2064, 253, 56, 48, "洞口（內側）", Color(0.35, 0.4, 0.45)),
	]
	return m


# ═══════════════════════════════════════════
#  塔
# ═══════════════════════════════════════════

static func _tower_camp() -> Dictionary:
	var m := _base("法師之塔 · 塔下營地", Color(0.08, 0.07, 0.12), 2800, 1575, Vector2(300, 697), "tower")
	var ents: Array = [
		_e("duanye", 500, 625, 48, 64, "斷頁", Color(0.55, 0.45, 0.65)),
		_e("refugee_fire", 700, 804, 56, 48, "逃難營火", Color(0.9, 0.4, 0.15), true),
		_e("tent_a", 400, 909, 64, 48, "帳棚", Color(0.4, 0.35, 0.4), true),
		_e("tent_b", 900, 843, 64, 48, "帳棚", Color(0.38, 0.35, 0.42), true),
		_e("scroll_pile", 1100, 512, 48, 40, "散落卷軸", Color(0.5, 0.45, 0.4)),
		_e("message_stone", 1200, 675, 52, 56, "留言石", Color(0.5, 0.55, 0.75), true),
		_e("candle_altar", 1400, 624, 56, 60, "通關蠟燭", Color(0.95, 0.75, 0.35), true),
		_e("tower_gate", 1800, 596, 80, 96, "塔門", Color(0.35, 0.25, 0.4), true),
		_e("to_tower_foyer", 1900, 609, 64, 56, "進入塔門廳", Color(0.45, 0.35, 0.5)),
		_e("climb_tower", 2100, 625, 64, 64, "登上塔", Color(0.5, 0.35, 0.55)),
		_e("save_tower", 200, 1237, 48, 48, "存檔石", Color(0.4, 0.45, 0.5)),
		_e("exit_cross_t", 2500, 1111, 72, 64, "六域岔路", Color(0.45, 0.5, 0.4)),
		_e("path_back_wild", 150, 449, 56, 48, "回荒野", Color(0.35, 0.4, 0.3)),
	]
	## 勸降成功：塔下再見
	if GameState.has_flag("side.ronin_spared"):
		ents.append(_e("ronin", 1000, 678, 48, 64, "浪人（守營）", Color(0.4, 0.35, 0.42)))
	m["entities"] = ents
	return m


static func _tower_foyer() -> Dictionary:
	var m := _base("法師之塔 · 門廳", Color(0.07, 0.06, 0.11), 2400, 1340, Vector2(200, 592), "tower_foyer")
	m["entities"] = [
		_e("back_tower_camp", 100, 579, 56, 56, "回營地", Color(0.4, 0.35, 0.5)),
		_e("pillar_a", 500, 365, 40, 80, "黑石柱", Color(0.3, 0.25, 0.35), true),
		_e("pillar_b", 800, 365, 40, 80, "黑石柱", Color(0.3, 0.25, 0.35), true),
		_e("mural", 1100, 421, 80, 56, "封印壁畫", Color(0.4, 0.3, 0.45), true),
		_e("to_tower_stairs", 1600, 543, 64, 56, "螺旋階", Color(0.45, 0.35, 0.5)),
		_e("to_tower_memory", 1900, 726, 64, 56, "回憶層入口", Color(0.5, 0.4, 0.55)),
		_e("climb_tower", 2100, 581, 64, 64, "直接登頂路", Color(0.5, 0.35, 0.55)),
	]
	return m


static func _tower_stairs() -> Dictionary:
	var m := _base("法師之塔 · 螺旋階", Color(0.06, 0.05, 0.1), 2200, 1238, Vector2(200, 982), "tower_stairs")
	m["entities"] = [
		_e("back_tower_camp", 100, 975, 56, 56, "下塔", Color(0.4, 0.35, 0.5)),
		_e("step_mark", 600, 800, 48, 40, "腳印", Color(0.35, 0.3, 0.4)),
		_e("window_slit", 900, 623, 40, 48, "狹窗", Color(0.3, 0.35, 0.45)),
		_e("echo_step", 1200, 447, 48, 40, "回音階", Color(0.4, 0.35, 0.45)),
		_e("to_tower_memory", 1500, 313, 56, 48, "回憶層", Color(0.5, 0.4, 0.55)),
		_e("climb_tower", 1800, 223, 64, 64, "更高處", Color(0.5, 0.35, 0.55)),
	]
	return m


static func _tower_memory() -> Dictionary:
	var m := _base("法師之塔 · 回憶層", Color(0.08, 0.06, 0.12), 2400, 1350, Vector2(200, 595), "tower_memory")
	m["entities"] = [
		_e("back_tower_camp", 100, 584, 56, 56, "離開回憶", Color(0.4, 0.35, 0.5)),
		_e("memory_orb_a", 500, 484, 48, 48, "記憶球·村", Color(0.55, 0.45, 0.4)),
		_e("memory_orb_b", 900, 545, 48, 48, "記憶球·堡", Color(0.5, 0.45, 0.55)),
		_e("memory_orb_c", 1300, 484, 48, 48, "記憶球·聖獸", Color(0.5, 0.55, 0.45)),
		_e("throne_shadow", 1700, 549, 72, 64, "王座影", Color(0.35, 0.25, 0.4), true),
		_e("climb_tower", 2000, 585, 64, 64, "面對終焉", Color(0.55, 0.35, 0.5)),
	]
	return m


static func _fallback(id: String) -> Dictionary:
	return _base(id, Color(0.1, 0.1, 0.12), 2000, 1000, Vector2(200, 400), id)
