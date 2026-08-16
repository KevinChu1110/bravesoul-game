extends RefCounted
class_name SideMilestones
## 支線里程碑：獎勵表 + 統一發獎樣板。
##
## 原本 flags／gold／stardust／xp／items／TitleCatalog／存檔 在各 _side_* 抄多遍；
## 漏 TitleCatalog 或 SaveManager 不會編譯失敗，卻會掉稱號提示或離線掉獎勵。
## apply() 收成一次宣告；reward(id) 是具名規格表。
##
## bubble 字串回傳給呼叫端（main._player_bubble），避免循環依賴。

static func _root() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


static func _gs() -> Node:
	var r := _root()
	return r.get_node_or_null("GameState") if r else null


static func _sys(name: String) -> Node:
	var r := _root()
	return r.get_node_or_null(name) if r else null


## 具名獎勵規格。數字與旗標與原先 main 支線一致，勿在此改經濟。
static func reward(id: String) -> Dictionary:
	match id:
		"codex":
			return {"flags": ["lore.codex_read"], "gold": 10, "stardust": 1}
		"broken_blade":
			return {"flags": ["item.broken_blade"], "bubble": "撿到斷劍了"}
		"ronin_persuade":
			return {
				"flags": ["side.ronin_spared", "side.ronin_done"],
				"gold": 40, "stardust": 3, "bubble": "他收刃了",
			}
		"fog_letter_deliver":
			return {
				"flags": ["side.fog_letter_done"], "clear_flags": ["item.true_letter"],
				"gold": 45, "stardust": 3, "bubble": "真信送達",
			}
		"ding_debt_done":
			return {
				"flags": ["side.ding_debt_done", "meta.forge_debt_bonus"],
				"clear_flags": ["item.broken_blade"],
				"gold": 50, "stardust": 3,
			}
		"ding_debt_asked":
			return {"flags": ["side.ding_debt_asked"]}
		"lantern":
			return {
				"flags": ["side.lantern_done"],
				"gold": 20, "stardust": 1, "xp": 15,
				"items": {"iron_scrap": 1},
				"bubble": "燈亮了",
			}
		"nest_care":
			return {
				"flags": ["side.nest_care_done"],
				"gold": 15, "stardust": 1, "xp": 12,
				"items": {"oak_resin": 1},
				"bubble": "巢穩了",
			}
		"star_wish":
			return {
				"flags": ["side.star_wish_done"],
				"gold": 25, "stardust": 2, "xp": 20,
				"items": {"star_ore": 1},
				"bubble": "許了一願",
			}
		"fog_incense":
			return {
				"flags": ["side.fog_incense_done"],
				"gold": 25, "stardust": 2, "xp": 18,
				"items": {"knight_shard": 1},
				"bubble": "香燃了",
			}
		"hearth":
			return {
				"flags": ["side.hearth_lit"],
				"gold": 18, "stardust": 1, "xp": 14,
				"items": {"bread": 1},
				"bubble": "爐火燃起",
			}
		"fog_letter_asked":
			return {
				"flags": ["side.fog_letter_asked", "item.true_letter"],
				"bubble": "收下真信",
			}
		_:
			return {}


## 套用獎勵規格：設旗／清旗／金／星屑／經驗／道具／稱號／存檔。
## 回傳 bubble 文案（空字串表示不需冒泡）。
static func apply(r: Dictionary) -> String:
	var gs := _gs()
	if gs == null:
		return ""
	for f in r.get("flags", []):
		gs.set_flag(str(f), true)
	for f in r.get("clear_flags", []):
		gs.set_flag(str(f), false)
	var gold := int(r.get("gold", 0))
	if gold != 0:
		gs.add_gold(gold)
	var dust := int(r.get("stardust", 0))
	if dust != 0:
		gs.add_stardust(dust)
	var xp_n := int(r.get("xp", 0))
	if xp_n > 0:
		gs.add_xp(xp_n)
	var items: Dictionary = r.get("items", {})
	var inv := _sys("InventorySystem")
	if inv and inv.has_method("add_item"):
		for iid in items.keys():
			inv.call("add_item", str(iid), int(items[iid]))
	var titles := _sys("TitleCatalog")
	if titles and titles.has_method("evaluate_all"):
		titles.call("evaluate_all")
	var sm := _sys("SaveManager")
	if sm and sm.has_method("save_game"):
		sm.call("save_game")
	return str(r.get("bubble", ""))
