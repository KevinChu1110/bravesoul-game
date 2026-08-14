extends Node
## 稱號牆：條件判定 + 自動解鎖寫入 GameState.flags（title.*）

## 每筆：flag / name / desc / cond（內部條件鍵）
const ENTRIES: Array[Dictionary] = [
	{
		"flag": "title.claw_parry",
		"name": "以劍抵爪",
		"desc": "對雷歐完美格擋至少一次。",
		"cond": "parry",
	},
	{
		"flag": "title.fog_seer",
		"name": "看破者",
		"desc": "看破白霧，走過霧隱。",
		"cond": "fog",
	},
	{
		"flag": "title.guard_breaker",
		"name": "破架之人",
		"desc": "單場對阿波破防兩次以上。",
		"cond": "abo_perfect",
	},
	{
		"flag": "title.gale_chaser",
		"name": "追風的",
		"desc": "等來疾影的停拍。",
		"cond": "falcon",
	},
	{
		"flag": "title.shore_last",
		"name": "岸上最後",
		"desc": "站到石拳承認力氣的方向。",
		"cond": "boar",
	},
	{
		"flag": "title.no_worship",
		"name": "我不慕強權",
		"desc": "魔王三拒皆滿。",
		"cond": "refuse_all",
	},
	{
		"flag": "title.cleared",
		"name": "晨光中的兔子",
		"desc": "通關終章。",
		"cond": "cleared",
	},
	{
		"flag": "title.rift_walker",
		"name": "裂縫行者",
		"desc": "裂縫勝場達到五次。",
		"cond": "rift5",
	},
	{
		"flag": "title.echo_walker",
		"name": "迴響行者",
		"desc": "黑焰迴響任意層再通關。",
		"cond": "echo",
	},
	{
		"flag": "title.wheat_keeper",
		"name": "稈在",
		"desc": "麥稈替你擋過一擊。",
		"cond": "wheat",
	},
	{
		"flag": "title.featured_fan",
		"name": "週焦點獵人",
		"desc": "四套裂縫皆至少鎮壓過一次。",
		"cond": "rift_all",
	},
	{
		"flag": "title.wood_mentor",
		"name": "木劍之約",
		"desc": "把練習的夢想交到小芽手裡。",
		"cond": "sprout",
	},
	{
		"flag": "title.scar_walker",
		"name": "疤地行者",
		"desc": "踏平黑焰疤地的主宰。",
		"cond": "scar",
	},
	{
		"flag": "title.mirror_break",
		"name": "破鏡之人",
		"desc": "在鏡廊戰勝自己的捷徑。",
		"cond": "mirror",
	},
	{
		"flag": "title.wreck_end",
		"name": "沉船終結者",
		"desc": "讓船長影再沉一次。",
		"cond": "wreck",
	},
	{
		"flag": "title.world_wanderer",
		"name": "翠嶺漫遊者",
		"desc": "造訪三十處不同的土地。",
		"cond": "visit30",
	},
	{
		"flag": "title.treasure_rabbit",
		"name": "拾荒兔",
		"desc": "打開十二個世界寶箱。",
		"cond": "chests12",
	},
	{
		"flag": "title.event_any",
		"name": "歲旅之人",
		"desc": "完成任一期活動的十日簿或專屬任務。",
		"cond": "event_any",
	},
]


func evaluate_all() -> Array[String]:
	## 回傳本輪新解鎖的稱號名
	var newly: Array[String] = []
	for e in ENTRIES:
		var flag: String = str(e.get("flag", ""))
		if flag == "":
			continue
		if GameState.has_flag(flag):
			continue
		if _cond_met(str(e.get("cond", ""))):
			GameState.set_flag(flag, true)
			newly.append(str(e.get("name", flag)))
	return newly


func _cond_met(cond: String) -> bool:
	match cond:
		"parry":
			return GameState.has_flag("c1_perfect_parry_once")
		"fog":
			return GameState.has_flag("boss.white_fog_cleared")
		"abo_perfect":
			return GameState.has_flag("c3_abo_perfect")
		"falcon":
			return GameState.has_flag("boss.shadowwind_cleared")
		"boar":
			return GameState.has_flag("boss.stonefist_cleared")
		"refuse_all":
			return GameState.has_flag("c6_refuse_all")
		"cleared":
			return GameState.has_flag("game_cleared") or GameState.has_flag("boss.demon_cleared")
		"rift5":
			return int(GameState.get_flag("postgame.rift_wins", 0)) >= 5 \
				or GameState.has_flag("title.rift_walker")
		"echo":
			return GameState.has_flag("title.echo_walker") \
				or GameState.ng_plus > 0 and GameState.has_flag("boss.demon_cleared")
		"wheat":
			return GameState.has_flag("c0_wheat_saved") or GameState.wheat_stalk_broken
		"rift_all":
			return GameState.has_flag("postgame.wrath_cleared") \
				and GameState.has_flag("postgame.tide_cleared") \
				and GameState.has_flag("postgame.statue_cleared") \
				and GameState.has_flag("postgame.chrono_cleared")
		"sprout":
			return GameState.has_flag("c1_sprout_done")
		"scar":
			return GameState.has_flag("boss.scar_lord_cleared")
		"mirror":
			return GameState.has_flag("boss.mirror_wraith_cleared")
		"wreck":
			return GameState.has_flag("boss.wreck_captain_cleared")
		"visit30":
			return int(GameState.get_flag("meta.maps_visited", 0)) >= 30
		"chests12":
			var WC = load("res://scripts/world/world_content.gd")
			return WC != null and WC.chest_opened_count() >= 12
		"event_any":
			return GameState.has_flag("title.event_any")
		_:
			## 活動稱號：title.event_* 由 EventRuntime 直接立 flag
			if cond.begins_with("event_"):
				return GameState.has_flag("title." + cond)
			return false


func event_title_entries() -> Array:
	var out: Array = []
	if Engine.get_main_loop() is SceneTree:
		var er: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EventRuntime")
		if er and er.has_method("all_events"):
			for e in er.call("all_events"):
				var flag := str(e.get("title_flag", ""))
				if flag == "":
					continue
				out.append({
					"flag": flag,
					"name": str(e.get("title_name", e.get("name", flag))),
					"desc": str(e.get("title_desc", "完成對應活動任務。")),
					"cond": "",
				})
	return out


func unlocked_count() -> int:
	var n := 0
	for e in ENTRIES:
		if is_unlocked(e):
			n += 1
	for e in event_title_entries():
		if GameState.has_flag(str(e.get("flag", ""))):
			n += 1
	return n


func total_count() -> int:
	return ENTRIES.size() + event_title_entries().size()


func is_unlocked(entry: Dictionary) -> bool:
	var flag: String = str(entry.get("flag", ""))
	if GameState.has_flag(flag):
		return true
	return _cond_met(str(entry.get("cond", "")))


## 牆面 BBCode 文字
func wall_bbcode() -> String:
	evaluate_all()
	var lines: PackedStringArray = []
	lines.append("[b]稱號牆[/b]  %d／%d" % [unlocked_count(), total_count()])
	lines.append("")
	for e in ENTRIES:
		var unlocked: bool = GameState.has_flag(str(e.get("flag", ""))) \
			or _cond_met(str(e.get("cond", "")))
		## 再寫一次確保
		if unlocked and not GameState.has_flag(str(e.get("flag", ""))):
			GameState.set_flag(str(e.get("flag", "")), true)
		var name_s: String = str(e.get("name", ""))
		var desc_s: String = str(e.get("desc", ""))
		if unlocked:
			lines.append("[color=#e8c86a]★ %s[/color]\n  %s" % [name_s, desc_s])
		else:
			lines.append("[color=#666]？ ？？？[/color]\n  [color=#555]（尚未解鎖）[/color]")
	lines.append("")
	lines.append("[b]歲旅活動稱號[/b]")
	for e in event_title_entries():
		var unlocked2: bool = GameState.has_flag(str(e.get("flag", "")))
		if unlocked2:
			lines.append("[color=#c96]★ %s[/color]\n  %s" % [str(e.get("name", "")), str(e.get("desc", ""))])
		else:
			lines.append("[color=#666]？ %s[/color]\n  [color=#555]（活動未完成）[/color]" % str(e.get("name", "")))
	## 外觀契機一覽（非稱號，附錄）
	lines.append("")
	lines.append("[b]外觀契機[/b]")
	var cosmetics: Array[Dictionary] = [
		{"flag": "cosmetic.gold_mane", "name": "金鬃"},
		{"flag": "cosmetic.mist_fur", "name": "霧影"},
		{"flag": "cosmetic.jade_fur", "name": "玉魄"},
		{"flag": "cosmetic.gale_fur", "name": "疾風"},
		{"flag": "cosmetic.ember_fur", "name": "炎心"},
		{"flag": "cosmetic.star_rabbit", "name": "星辰兔"},
		{"flag": "cosmetic.ash_edge", "name": "沾焰灰邊"},
	]
	for c in cosmetics:
		var on: bool = GameState.has_flag(str(c.get("flag", "")))
		if on:
			lines.append("[color=#9cf]◆ %s[/color]" % str(c.get("name", "")))
		else:
			lines.append("[color=#555]◇ ？？？[/color]")
	return "\n".join(lines)


func unlocked_names_line() -> String:
	evaluate_all()
	var names: PackedStringArray = []
	for e in ENTRIES:
		if GameState.has_flag(str(e.get("flag", ""))):
			names.append(str(e.get("name", "")))
	for e in event_title_entries():
		if GameState.has_flag(str(e.get("flag", ""))):
			names.append(str(e.get("name", "")))
	if names.is_empty():
		return "尚無稱號"
	return "、".join(names)
