extends RefCounted
class_name WorldContent
## 廣域內容：寶箱、雜魚遭遇、秘境小 Boss、探索計數。
## 互動 id 對應；進度寫入 GameState.flags。

## ── 雜魚／小 Boss 數值定義（battle mode key）──
const ContentLoc := preload("res://scripts/systems/content_loc.gd")


## 敵人名在非繁中會被 ContentLoc 換掉。enemy_def() 是唯一入口，翻在這裡
## 戰鬥畫面、日誌、掉落訊息就全都吃得到。
static func enemy_def(mode: String) -> Dictionary:
	return ContentLoc.apply("enemy", _enemy_def_raw(mode), PackedStringArray(["name"]))


static func _enemy_def_raw(mode: String) -> Dictionary:
	match mode:
		## 雜魚
		"ash_rat":
			return {"id": "ash_rat", "name": "灰燼鼠", "max_hp": 55, "atk": 8, "def": 2, "speed": 12.0, "is_boss": false, "art": "ash_rat", "art_fallback": "wolf"}
		"road_bandit":
			return {"id": "road_bandit", "name": "荒路殘兵", "max_hp": 75, "atk": 10, "def": 4, "speed": 10.0, "is_boss": false, "art": "road_bandit", "art_fallback": "wolf"}
		"sewer_slime":
			return {"id": "sewer_slime", "name": "下水黏漿", "max_hp": 70, "atk": 9, "def": 5, "speed": 8.0, "is_boss": false, "art": "sewer_slime", "art_fallback": "wolf"}
		"fog_shade":
			return {"id": "fog_shade", "name": "霧影", "max_hp": 90, "atk": 11, "def": 4, "speed": 13.0, "is_boss": false, "art": "fog_shade", "art_fallback": "fog"}
		"bamboo_spirit":
			return {"id": "bamboo_spirit", "name": "竹影拳靈", "max_hp": 100, "atk": 12, "def": 6, "speed": 11.0, "is_boss": false, "art": "bamboo_spirit", "art_fallback": "abo"}
		"forest_sprite":
			return {"id": "forest_sprite", "name": "林間風妖", "max_hp": 95, "atk": 11, "def": 5, "speed": 14.0, "is_boss": false, "art": "forest_sprite", "art_fallback": "falcon"}
		"coast_raider":
			return {"id": "coast_raider", "name": "潮襲海盜", "max_hp": 110, "atk": 13, "def": 7, "speed": 10.0, "is_boss": false, "art": "coast_raider", "art_fallback": "boar"}
		"scar_wisp":
			return {"id": "scar_wisp", "name": "疤地焰靈", "max_hp": 120, "atk": 14, "def": 6, "speed": 12.0, "is_boss": false, "art": "scar_wisp", "art_fallback": "wrath"}
		## 支線：黑焰浪人（可戰可勸）
		"black_ronin":
			return {
				"id": "black_ronin", "name": "黑焰浪人", "max_hp": 160, "atk": 14, "def": 7, "speed": 12.5,
				"is_boss": false, "art": "black_ronin", "art_fallback": "road_bandit",
			}
		## 秘境小 Boss
		"scar_lord":
			return {
				"id": "scar_lord", "name": "黑焰疤主", "max_hp": 280, "atk": 15, "def": 9, "speed": 10.0,
				"is_boss": true, "art": "scar_lord", "art_fallback": "wrath",
				"windup": 0.28, "recover": 0.42, "king_slash_cd": 2.8, "hazard": "fire_ring", "hazard_cd": 4.0,
			}
		"mirror_wraith":
			return {
				"id": "mirror_wraith", "name": "鏡廊殘影", "max_hp": 260, "atk": 14, "def": 7, "speed": 13.0,
				"is_boss": true, "art": "mirror_wraith", "art_fallback": "fog",
				"windup": 0.22, "recover": 0.38, "king_slash_cd": 3.0, "hazard": "wind_cut", "hazard_cd": 4.5,
			}
		"wreck_captain":
			return {
				"id": "wreck_captain", "name": "沉船船長影", "max_hp": 300, "atk": 16, "def": 11, "speed": 8.5,
				"is_boss": true, "art": "wreck_captain", "art_fallback": "tide",
				"windup": 0.32, "recover": 0.48, "king_slash_cd": 3.2, "hazard": "rockfall", "hazard_cd": 5.0,
			}
		_:
			return {}


static func is_world_battle(mode: String) -> bool:
	return not enemy_def(mode).is_empty()


static func is_miniboss(mode: String) -> bool:
	var d := enemy_def(mode)
	return bool(d.get("is_boss", false))


static func art_key(mode: String) -> String:
	var d := enemy_def(mode)
	if d.is_empty():
		return mode
	var art := str(d.get("art", mode))
	## 若專用圖不存在，battle_view 再 fallback
	return art


static func art_fallback(mode: String) -> String:
	var d := enemy_def(mode)
	return str(d.get("art_fallback", d.get("art", "wolf")))


## entity id → 寶箱（經濟 0.15：單次略收，合計約 −12%；不重砍，主線探索仍要有摸箱爽感）
static func chests() -> Dictionary:
	return {
		"sealed_chest": {"flag": "loot.chest.road_ruins", "gold": 40, "dust": 2, "text": "封箱裂開：古驛的通行費，如今歸你。"},
		"chest_root": {"flag": "loot.chest.forest_ruins", "gold": 44, "dust": 3, "text": "根纏箱打開：遊俠留下的箭矢錢。"},
		"chest_half": {"flag": "loot.chest.coast_wreck", "gold": 48, "dust": 2, "text": "半埋箱：海水泡過的金幣仍作響。"},
		"supply_crate": {"flag": "loot.chest.wild_supply", "gold": 26, "dust": 1, "text": "補給箱：乾糧與幾枚城徽幣。"},
		"hidden_cache": {"flag": "loot.chest.forest_cache", "gold": 35, "dust": 2, "text": "獵人藏匿處：藥草與銅板。"},
		"cellar_hatch": {"flag": "loot.chest.road_inn", "gold": 30, "dust": 1, "text": "地窖底：客棧老闆藏的小費罐。"},
		"ore_cart": {"flag": "loot.chest.village_cave", "gold": 22, "dust": 2, "text": "礦車夾層：半袋未熔的星屑礦砂。"},
		"fresh_earth": {"flag": "loot.chest.village_grave", "gold": 18, "dust": 1, "text": "新土下露出小盒——村民的護身符錢。"},
		"goods_pile": {"flag": "loot.chest.caravan", "gold": 35, "dust": 2, "text": "行商允你摸一層貨——規矩內的謝禮。"},
		"scroll_pile": {"flag": "loot.chest.tower_scrolls", "gold": 30, "dust": 3, "text": "卷軸間夾著星屑袋。斷頁說過：拿吧。"},
		"obsidian": {"flag": "loot.chest.scar_obsidian", "gold": 52, "dust": 4, "text": "黑曜碎中封著濃縮星屑——燙手，但有用。"},
		"scale_table": {"flag": "loot.chest.market_scale", "gold": 24, "dust": 1, "text": "天秤台抽屜：商會遺落的零錢。"},
		"guest_bed": {"flag": "loot.chest.inn_bed", "gold": 14, "dust": 1, "text": "塌床底下：旅客來不及拿走的錢袋。"},
		"nest_mark": {"flag": "loot.chest.forest_feather", "gold": 30, "dust": 2, "text": "羽痕石縫：疾影屬下遺落的戰利。"},
		"pirate_mark": {"flag": "loot.chest.coast_pirate", "gold": 42, "dust": 2, "text": "海盜標記下埋著箱——他們不會回來了。"},
		"mosaic": {"flag": "loot.chest.star_mosaic", "gold": 36, "dust": 3, "text": "馬賽克中央撬起：古驛的星途通行符與金幣。"},
	}


## entity id → 可重複或單次雜魚
static func skirmishes() -> Dictionary:
	return {
		"deep_dark": {"mode": "ash_rat", "once_flag": "", "intro": "黑暗裡兩點紅光——灰燼鼠撲來。"},
		"bone_pile": {"mode": "ash_rat", "once_flag": "", "intro": "獸骨堆動了。不是風。"},
		"bush_b": {"mode": "road_bandit", "once_flag": "skirmish.road_bush", "intro": "黑刺叢後竄出殘兵！"},
		"rat_nest": {"mode": "sewer_slime", "once_flag": "", "intro": "黏液從管口湧出。"},
		"slime_pool": {"mode": "sewer_slime", "once_flag": "skirmish.sewer_pool", "intro": "池面鼓起人形……不，是黏漿。"},
		"cat_shadow": {"mode": "fog_shade", "once_flag": "skirmish.mist_cat", "intro": "影貓化作霧影撲向你。"},
		"false_exit": {"mode": "fog_shade", "once_flag": "", "intro": "假出口合攏——霧影從鏡裡踏出。"},
		"hidden_spar": {"mode": "bamboo_spirit", "once_flag": "skirmish.bamboo", "intro": "竹影拳靈求一戰。"},
		"kite_stuck": {"mode": "forest_sprite", "once_flag": "skirmish.kite", "intro": "風箏線上纏著風妖。"},
		"owl_post": {"mode": "forest_sprite", "once_flag": "skirmish.owl", "intro": "貓頭鷹樁後，風妖尖叫。"},
		"boat_wreck": {"mode": "coast_raider", "once_flag": "skirmish.boat", "intro": "破船骸裡爬出海盜影。"},
		"deep_water": {"mode": "coast_raider", "once_flag": "", "intro": "深水翻湧——潮襲者上岸。"},
		"flame_vent": {"mode": "scar_wisp", "once_flag": "", "intro": "焰口噴出疤地焰靈！"},
		"black_vein": {"mode": "scar_wisp", "once_flag": "skirmish.black_vein", "intro": "黑焰脈紋凝成靈體。"},
		"echo_canyon": {"mode": "ash_rat", "once_flag": "skirmish.ravine", "intro": "回音峽傳出獸吼——灰燼鼠群。"},
		"alley_dark": {"mode": "road_bandit", "once_flag": "skirmish.market_alley", "intro": "窄巷裡有刀光。"},
	}


## entity id → 秘境小 Boss
static func minibosses() -> Dictionary:
	return {
		"scar_boss": {
			"mode": "scar_lord",
			"flag": "boss.scar_lord_cleared",
			"need_flag": "boss.abo_cleared",
			"deny": "疤主的氣壓太重。至少先通過道場試煉。",
			"cleared_dialog": "world.scar_cleared",
			"intro": [
				{"speaker": "旁白", "text": "疤地中央，黑焰聚成人形——沒有臉，只有胃口。"},
				{"speaker": "旁白", "text": "焦土一跳一跳，像還在流血的傷口。"},
				{"speaker": "黑焰疤主", "portrait": "scar_lord", "text": "……弱者……也配踏入我的傷口？"},
				{"speaker": "黑焰疤主", "portrait": "scar_lord", "text": "野心……香味……過來。讓我把它從你身上撕開。"},
			],
			"win": [
				{"speaker": "疤主", "portrait": "scar_lord", "text": "傷口……合上了嗎……"},
				{"speaker": "疤主", "portrait": "scar_lord", "text": "……你沒有餵我。奇怪。……"},
				{"speaker": "系統", "text": "戰勝【黑焰疤主】。金 90 · 星屑 5。稱號「疤地行者」進度。"},
			],
			"lose": "黑焰把你掀回岔路。疤地仍在跳動脈搏。",
			"gold": 90, "dust": 5, "hp": 12,
			"lose_map": "crossroads", "lose_screen": "C1_WILD",
			"win_map": "blackflame_scar", "win_screen": "C1_WILD",
		},
		"mirror_boss": {
			"mode": "mirror_wraith",
			"flag": "boss.mirror_wraith_cleared",
			"need_flag": "c2_entered",
			"deny": "鏡廊拒絕外人。先被霧隱接納。",
			"cleared_dialog": "world.mirror_cleared",
			"intro": [
				{"speaker": "旁白", "text": "所有鏡子同時亮起——裡頭的你，比你更像獵人。"},
				{"speaker": "旁白", "text": "倒影先動了一步。你還沒拔劍。"},
				{"speaker": "鏡廊殘影", "portrait": "mirror_wraith", "text": "我才是敢走捷徑的那一個。"},
				{"speaker": "鏡廊殘影", "portrait": "mirror_wraith", "text": "你把懦弱叫作慈悲。來——讓我替你變強。"},
			],
			"win": [
				{"speaker": "殘影", "portrait": "mirror_wraith", "text": "……原來真影比較沉。"},
				{"speaker": "殘影", "portrait": "mirror_wraith", "text": "捷徑……碎了。你自己走吧。"},
				{"speaker": "系統", "text": "戰勝【鏡廊殘影】。金 80 · 星屑 5。"},
			],
			"lose": "你被自己的倒影推回霧隱村。",
			"gold": 80, "dust": 5, "hp": 10,
			"lose_map": "mist_village", "lose_screen": "C2_MIST",
			"win_map": "mist_mirror", "win_screen": "C2_MIST",
		},
		"wreck_boss": {
			"mode": "wreck_captain",
			"flag": "boss.wreck_captain_cleared",
			"need_flag": "c5_entered",
			"deny": "船長影只認海上來的人。先踏上維京海岸。",
			"cleared_dialog": "world.wreck_cleared",
			"intro": [
				{"speaker": "旁白", "text": "沉船龍骨站起——船長帽下沒有臉，只有浪聲。"},
				{"speaker": "旁白", "text": "潮水退半尺，像在給你登船的時間。很短。"},
				{"speaker": "沉船船長影", "portrait": "wreck_captain", "text": "這船是我的墳。訪客，留下通行證——或骨頭。"},
				{"speaker": "沉船船長影", "portrait": "wreck_captain", "text": "海不認弱者的名字。報上你的，或沉下去。"},
			],
			"win": [
				{"speaker": "船長影", "portrait": "wreck_captain", "text": "……潮水……準時……"},
				{"speaker": "船長影", "portrait": "wreck_captain", "text": "……船……可以再睡一次。……去吧，岸上的。"},
				{"speaker": "系統", "text": "戰勝【沉船船長影】。金 95 · 星屑 5。"},
			],
			"lose": "浪把你送回碼頭。船骸仍張著口。",
			"gold": 95, "dust": 5, "hp": 12,
			"lose_map": "coast", "lose_screen": "C5_COAST",
			"win_map": "coast_wreck", "win_screen": "C5_COAST",
		},
	}


## autoload 不可以在這裡用識別字直接寫（例如 `GameState.has_flag(...)`）。
##
## 這支是 class_name 的靜態工具，會被 `godot --headless -s res://...` 那類
## 測試腳本當成相依項在**自動載入還沒建立之前**編譯。那時候 GameState 這個
## 識別字不存在，整支就 Compile Error，而錯誤只會冒出一句
## 「Failed to compile depended scripts」—— 真正壞掉的地方在別的檔案裡，
## 呼叫端拿到的是一個沒有任何方法的 GDScript，症狀是
## 「Nonexistent function 'enemy_def'」，跟根因看起來毫無關係。
##
## 所以一律從 SceneTree.root 取，執行期才解析。
static func _gs() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree and (t as SceneTree).root != null:
		return (t as SceneTree).root.get_node_or_null("GameState")
	return null


static func _has_flag(key: String) -> bool:
	var gs := _gs()
	return gs != null and bool(gs.call("has_flag", key))


static func chest_opened_count() -> int:
	var n := 0
	for _k in chests().keys():
		var c: Dictionary = chests()[_k]
		if _has_flag(str(c.get("flag", ""))):
			n += 1
	return n


static func miniboss_cleared_count() -> int:
	var n := 0
	for _k in minibosses().keys():
		var m: Dictionary = minibosses()[_k]
		if _has_flag(str(m.get("flag", ""))):
			n += 1
	return n


static func visit_count() -> int:
	var gs := _gs()
	return int(gs.call("get_flag", "meta.maps_visited", 0)) if gs != null else 0


static func mark_visit(map_id: String) -> void:
	var gs := _gs()
	if gs == null:
		return
	var key := "visit.%s" % map_id
	if bool(gs.call("has_flag", key)):
		return
	gs.call("set_flag", key, true)
	gs.call("set_flag", "meta.maps_visited", visit_count() + 1)
