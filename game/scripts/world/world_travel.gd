extends RefCounted
class_name WorldTravel
## 全域路標：entity id → 目標地圖與章節畫面鍵（main 再轉 Screen）。
## need_flag 有值時需已立旗；deny 為未解鎖提示。


## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
const ContentLoc := preload("res://scripts/systems/content_loc.gd")

static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

static func links() -> Dictionary:
	return {
		## ── 翠谷 ──
		"exit_outskirts": {"map": "village_outskirts", "screen": "C0_VILLAGE"},
		"back_village": {"map": "village", "screen": "C0_VILLAGE"},
		"to_mill": {"map": "village_mill", "screen": "C0_VILLAGE"},
		"to_cave": {"map": "village_cave", "screen": "C0_VILLAGE"},
		"to_grave": {"map": "village_grave", "screen": "C0_VILLAGE"},
		"back_from_mill": {"map": "village_outskirts", "screen": "C0_VILLAGE"},
		"back_from_cave": {"map": "village", "screen": "C0_VILLAGE"},
		"back_from_grave": {"map": "village", "screen": "C0_VILLAGE"},
		"trail_east": {
			"map": "road", "screen": "C0_ROAD",
			"need_flag": "item.rusty_sword",
			"deny": _t("空手走不遠。先回村撿劍。"),
		},
		"mill_to_road": {
			"map": "road", "screen": "C0_ROAD",
			"need_flag": "item.rusty_sword",
			"deny": _t("沒有武器不建議上荒路。"),
		},

		## ── 荒路 ──
		"to_road_bridge": {"map": "road_bridge", "screen": "C0_ROAD"},
		"to_road_inn": {"map": "road_inn", "screen": "C0_ROAD"},
		"to_road_ruins": {"map": "road_ruins", "screen": "C0_ROAD"},
		"back_road": {"map": "road", "screen": "C0_ROAD"},
		"east_span": {"map": "road", "screen": "C0_ROAD"},
		"ladder_out": {"map": "town", "screen": "C1_TOWN"},
		"exit_town_hint": {"map": "town", "screen": "C1_TOWN", "need_flag": "c0_first_battle", "deny": ""},
		"dawn_glow": {"map": "town", "screen": "C1_TOWN", "need_flag": "c0_first_battle", "deny": ""},

		## ── 騎士堡 ──
		"exit_keep": {"map": "town_keep", "screen": "C1_TOWN"},
		"back_town": {"map": "town", "screen": "C1_TOWN"},
		"to_market": {"map": "town_market", "screen": "C1_TOWN"},
		"to_sewers": {"map": "town_sewers", "screen": "C1_TOWN"},
		"to_barracks_yard": {"map": "barracks_yard", "screen": "C1_TOWN"},
		"back_from_market": {"map": "town", "screen": "C1_TOWN"},
		"back_from_sewers": {"map": "town", "screen": "C1_TOWN"},
		"back_from_barracks": {"map": "town", "screen": "C1_TOWN"},
		## 原作村內四店：門楣走進室內
		"tutor_hall": {"map": "town_tutor", "screen": "C1_TOWN"},
		"forge_sign": {"map": "town_forge", "screen": "C1_TOWN"},
		"gem_shop": {"map": "town_gem", "screen": "C1_TOWN"},
		"soul_hall": {"map": "town_soul", "screen": "C1_TOWN"},
		"back_from_shop": {"map": "town", "screen": "C1_TOWN"},
		"exit_wild": {"map": "wild", "screen": "C1_WILD"},
		"exit_wild_inner": {"map": "wild", "screen": "C1_WILD"},
		"to_wild_ravine": {"map": "wild_ravine", "screen": "C1_WILD"},
		## 內殿前院要先鍛造。正門 exit_wild 一直有這道門檻（「鏽劍捲刃了，先去找釘釘」），
		## 這條側路沒有 —— 玩家可以拿著鏽劍直接走到雷歐面前，而戰敗收尾接的是
		## _go_c1_wild，它又被同一個旗標擋下 return，畫面就停在打完的戰鬥上。
		"to_leo_court": {"map": "wild_leo_court", "screen": "C1_WILD", "need_flag": "c1_forged", "deny": _t("鏽劍捲刃了。先去找釘釘。")},
		"back_wild": {"map": "wild", "screen": "C1_WILD"},

		## ── 岔路（0.12：鍛造後即可練功／自由探索，不必先打雷歐）──
		"path_crossroads": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。先找釘釘把劍養好。"),
		},
		"exit_cross_m": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。先找釘釘把劍養好。"),
		},
		"exit_cross_d": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。"),
		},
		"exit_cross_f": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。"),
		},
		"exit_cross_c": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。"),
		},
		"exit_cross_t": {
			"map": "crossroads", "screen": "C1_WILD",
			"need_flag": "c1_forged",
			"deny": _t("岔路仍封著。"),
		},
		"to_cross_north": {"map": "cross_north", "screen": "C1_WILD"},
		"to_cross_east": {"map": "cross_east", "screen": "C1_WILD"},
		"to_caravan": {"map": "caravan_camp", "screen": "C1_WILD"},
		"to_starfall": {"map": "starfall_plain", "screen": "C1_WILD"},
		"to_hunt": {
			"map": "hunting_grounds", "screen": "C1_WILD",
			"need_flag": "c1_entered_city",
			"deny": _t("獵場在堡外溢地。先進騎士堡再說。"),
		},
		"to_blackflame_scar": {
			"map": "blackflame_scar", "screen": "C1_WILD",
			"need_flag": "boss.abo_cleared",
			"deny": _t("黑焰疤地太危險。至少先通過道場試煉。"),
		},
		"back_cross": {"map": "crossroads", "screen": "C1_WILD"},

		## ── 霧隱 ──
		"alley_gate": {"map": "mist_deep", "screen": "C2_MIST"},
		"back_mist": {"map": "mist_village", "screen": "C2_MIST"},
		"to_mist_cliff": {"map": "mist_cliff", "screen": "C2_MIST"},
		"to_mist_shrine": {"map": "mist_shrine", "screen": "C2_MIST"},
		"to_mist_mirror": {"map": "mist_mirror", "screen": "C2_MIST"},
		"back_from_mist_sub": {"map": "mist_village", "screen": "C2_MIST"},
		"path_mist": {"map": "mist_village", "screen": "C2_MIST"},
		"path_mist_c": {"map": "mist_village", "screen": "C2_MIST"},

		## ── 道場 ──
		"path_dojo": {"map": "dojo", "screen": "C3_DOJO"},
		"path_dojo_c": {"map": "dojo", "screen": "C3_DOJO"},
		"to_dojo_inner": {"map": "dojo_inner", "screen": "C3_DOJO"},
		"to_dojo_bamboo": {"map": "dojo_bamboo", "screen": "C3_DOJO"},
		"to_dojo_peak": {"map": "dojo_peak", "screen": "C3_DOJO"},
		"back_dojo": {"map": "dojo", "screen": "C3_DOJO"},

		## ── 森林 ──
		"path_forest": {"map": "forest", "screen": "C4_FOREST"},
		"path_forest_c": {"map": "forest", "screen": "C4_FOREST"},
		"deep_gate": {"map": "forest_deep", "screen": "C4_FOREST"},
		"back_forest": {"map": "forest", "screen": "C4_FOREST"},
		"to_forest_canopy": {"map": "forest_canopy", "screen": "C4_FOREST"},
		"to_forest_ruins": {"map": "forest_ruins", "screen": "C4_FOREST"},
		"to_forest_lake": {"map": "forest_lake", "screen": "C4_FOREST"},
		"back_from_forest_sub": {"map": "forest", "screen": "C4_FOREST"},

		## ── 海岸 ──
		"path_coast": {"map": "coast", "screen": "C5_COAST"},
		"path_coast_c": {"map": "coast", "screen": "C5_COAST"},
		"cliff_gate": {"map": "coast_cliff", "screen": "C5_COAST"},
		"back_coast": {"map": "coast", "screen": "C5_COAST"},
		"to_coast_harbor": {"map": "coast_harbor", "screen": "C5_COAST"},
		"to_coast_cave": {"map": "coast_cave", "screen": "C5_COAST"},
		"to_coast_wreck": {"map": "coast_wreck", "screen": "C5_COAST"},
		"back_from_coast_sub": {"map": "coast", "screen": "C5_COAST"},

		## ── 塔 ──
		"path_tower_c": {"map": "tower_camp", "screen": "C6_TOWER"},
		"path_tower": {"map": "tower_camp", "screen": "C6_TOWER"},
		"path_tower_c5": {"map": "tower_camp", "screen": "C6_TOWER"},
		"to_tower_foyer": {"map": "tower_foyer", "screen": "C6_TOWER"},
		"to_tower_stairs": {"map": "tower_stairs", "screen": "C6_TOWER"},
		"to_tower_memory": {"map": "tower_memory", "screen": "C6_TOWER"},
		"back_tower_camp": {"map": "tower_camp", "screen": "C6_TOWER"},
		"path_back_wild": {"map": "wild", "screen": "C1_WILD"},

		## ── 騎士域互連 ──
		"path_knight": {"map": "town", "screen": "C1_TOWN"},
		"back_knight": {"map": "town", "screen": "C1_TOWN"},
	}


static func list_map_ids() -> PackedStringArray:
	## 文件／除錯用：所有合法 map id
	return PackedStringArray([
		"village", "village_outskirts", "village_mill", "village_cave", "village_grave",
		"road", "road_bridge", "road_inn", "road_ruins",
		"town", "town_keep", "town_market", "town_sewers", "barracks_yard",
		"town_forge", "town_soul", "town_gem", "town_tutor",
		"wild", "wild_ravine", "wild_leo_court",
		"crossroads", "cross_north", "cross_east", "caravan_camp", "starfall_plain", "blackflame_scar", "hunting_grounds",
		"mist_village", "mist_deep", "mist_cliff", "mist_shrine", "mist_mirror",
		"dojo", "dojo_inner", "dojo_bamboo", "dojo_peak",
		"forest", "forest_deep", "forest_canopy", "forest_ruins", "forest_lake",
		"coast", "coast_cliff", "coast_harbor", "coast_cave", "coast_wreck",
		"tower_camp", "tower_foyer", "tower_stairs", "tower_memory",
	])
