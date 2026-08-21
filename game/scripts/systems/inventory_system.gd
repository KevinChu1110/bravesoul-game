extends Node
## 楓式背包／快捷欄。道具定義 + 使用效果。存檔掛在 GameState.inventory / hotbar。

signal inventory_changed
signal hotbar_changed
signal item_used(item_id: String, result: Dictionary)

## 戰鬥中 HP 的權威不在 GameState，而在 BattleSim 的戰鬥單位上。
##
## 開戰時 battle_view 把玩家當下的 HP 快照進戰鬥單位，之後整場的加減都只動那一份；
## GameState.hp 要到戰鬥結束才被寫回去。所以戰鬥中喝藥如果只加 GameState.hp：
##   1. 戰鬥單位一滴都沒回，藥等於沒效
##   2. GameState.hp 通常還停在滿血，mini() 夾完 healed 是 0，訊息顯示「HP +0」
##   3. 藥還是被扣掉了
## 三件事湊起來就是「藥被吃掉但什麼都沒發生」——不報錯，玩家只能懷疑自己看錯。
##
## battle_view 開戰時把自己掛上來，結束時拿掉。沒掛的時候照舊寫 GameState。
var hp_authority: Callable = Callable()


func _apply_heal(h: int) -> int:
	if h <= 0:
		return 0
	if hp_authority.is_valid():
		return int(hp_authority.call(h))
	var max_h: int = GameState.effective_max_hp()
	var before: int = GameState.hp
	GameState.hp = mini(max_h, GameState.hp + h)
	return GameState.hp - before

const HOTBAR_SIZE := 8
const BAG_SLOTS := 24  ## 顯示格數（4×6）

## id → {name, desc, kind, stack, heal?, dust?, gold?, key?, color}
const ContentLoc := preload("res://scripts/systems/content_loc.gd")
const ITEM_TEXT_FIELDS: PackedStringArray = ["name", "desc"]

const CATALOG: Dictionary = {
	"hp_s": {
		"name": "小紅水",
		"desc": "恢復 25 生命。",
		"kind": "consumable",
		"stack": 99,
		"heal": 25,
		"color": Color(0.9, 0.25, 0.25),
		"glyph": "🧪",
	},
	"hp_m": {
		"name": "中紅水",
		"desc": "恢復 55 生命。",
		"kind": "consumable",
		"stack": 99,
		"heal": 55,
		"color": Color(0.85, 0.15, 0.2),
		"glyph": "🍷",
	},
	"bread": {
		"name": "乾糧",
		"desc": "恢復 15 生命。路上充飢。",
		"kind": "consumable",
		"stack": 99,
		"heal": 15,
		"color": Color(0.75, 0.55, 0.3),
		"glyph": "🍖",
	},
	"dust_crumb": {
		"name": "星屑碎",
		"desc": "使用後獲得 1 星屑。",
		"kind": "consumable",
		"stack": 99,
		"dust": 1,
		"color": Color(0.55, 0.65, 0.95),
		"glyph": "✦",
	},
	"antidote": {
		"name": "清焰露",
		"desc": "恢復 10 生命，並略提振精神。",
		"kind": "consumable",
		"stack": 30,
		"heal": 10,
		"color": Color(0.4, 0.75, 0.55),
		"glyph": "💧",
	},
	"key_rusty": {
		"name": "鏽劍（紀念）",
		"desc": "村口撿起的那把。已鍛成正器後仍留念。",
		"kind": "key",
		"stack": 1,
		"color": Color(0.55, 0.5, 0.4),
		"glyph": "🗡️",
	},
	"map_scrap": {
		"name": "六域殘圖",
		"desc": "行商撕給你的一角。可看不可吃。",
		"kind": "key",
		"stack": 1,
		"color": Color(0.7, 0.65, 0.45),
		"glyph": "📜",
	},
	"medal": {
		"name": "勳章",
		"desc": "傭兵／演武功績。手藝工坊可用 50 枚點燃熔爐（原作替代金幣）。",
		"kind": "key",
		"stack": 99,
		"color": Color(0.85, 0.7, 0.3),
		"glyph": "🏅",
	},
	"relic_token": {
		"name": "秘境印記",
		"desc": "通關秘境留下的印。收藏用。",
		"kind": "key",
		"stack": 9,
		"color": Color(0.65, 0.4, 0.75),
		"glyph": "☸",
	},
	"wolf_fang": {
		"name": "狼牙",
		"desc": "雜魚掉落。可賣 8 金。",
		"kind": "material",
		"stack": 99,
		"sell": 8,
		"color": Color(0.7, 0.7, 0.75),
		"glyph": "🦴",
	},
	"mist_shard": {
		"name": "霧晶",
		"desc": "霧影掉落。可賣 12 金。",
		"kind": "material",
		"stack": 99,
		"sell": 12,
		"color": Color(0.6, 0.7, 0.9),
		"glyph": "🔮",
	},
	"sea_shell": {
		"name": "潮貝",
		"desc": "海岸掉落。可賣 10 金。",
		"kind": "material",
		"stack": 99,
		"sell": 10,
		"color": Color(0.5, 0.7, 0.75),
		"glyph": "🐚",
	},
	"scar_ember": {
		"name": "疤焰燼",
		"desc": "疤地掉落。可賣 15 金。",
		"kind": "material",
		"stack": 99,
		"sell": 15,
		"color": Color(0.55, 0.25, 0.5),
		"glyph": "🔥",
	},
	"hunt_hide": {
		"name": "溢皮",
		"desc": "狩獵場材料。可在溢物回收換金。",
		"kind": "material",
		"stack": 99,
		"sell": 10,
		"tradeable": true,
		"color": Color(0.55, 0.4, 0.3),
		"glyph": "📜",
	},
	"hunt_bone": {
		"name": "焰骨",
		"desc": "狩獵場中階材料。",
		"kind": "material",
		"stack": 99,
		"sell": 22,
		"tradeable": true,
		"color": Color(0.7, 0.55, 0.4),
		"glyph": "🦴",
	},
	"hunt_core": {
		"name": "溢核",
		"desc": "狩獵場稀有核。溢物回收價最好。",
		"kind": "material",
		"stack": 99,
		"sell": 60,
		"tradeable": true,
		"color": Color(0.85, 0.35, 0.55),
		"glyph": "💎",
	},
	## 0.12.1 鍛造材料循環
	"iron_scrap": {
		"name": "鐵屑",
		"desc": "鍛造基礎材。鐵匠與商店都收。",
		"kind": "material",
		"stack": 99,
		"sell": 6,
		"buy": 14,
		"color": Color(0.55, 0.55, 0.58),
		"glyph": "鐵",
	},
	"star_ore": {
		"name": "星砂礦",
		"desc": "抽魂／獵場武器材料。",
		"kind": "material",
		"stack": 99,
		"sell": 10,
		"buy": 22,
		"color": Color(0.55, 0.6, 0.95),
		"glyph": "砂",
	},
	"oak_resin": {
		"name": "橡脂",
		"desc": "穩固與飾品材料。",
		"kind": "material",
		"stack": 99,
		"sell": 8,
		"buy": 18,
		"color": Color(0.55, 0.45, 0.25),
		"glyph": "脂",
	},
	"knight_shard": {
		"name": "騎士碎鐵",
		"desc": "騎士域鍛造碎片。可做軍刀線。",
		"kind": "material",
		"stack": 99,
		"sell": 12,
		"buy": 28,
		"color": Color(0.65, 0.6, 0.5),
		"glyph": "碎",
	},
	"friendship_key": {
		"name": "友誼鑰匙",
		"desc": "好友挑戰勝利所得。三把開一個友誼寶箱。",
		"kind": "key",
		"stack": 99,
		"sell": 0,
		"color": Color(0.85, 0.7, 0.35),
		"glyph": "鑰",
	},
}


func _ready() -> void:
	ensure_hotbar()


func ensure_hotbar() -> void:
	if GameState.hotbar == null:
		GameState.hotbar = []
	while GameState.hotbar.size() < HOTBAR_SIZE:
		GameState.hotbar.append("")
	if GameState.hotbar.size() > HOTBAR_SIZE:
		GameState.hotbar.resize(HOTBAR_SIZE)
	if GameState.inventory == null:
		GameState.inventory = {}


## 道具名與說明在非繁中會被 ContentLoc 換掉。CATALOG 是 id → 資料，
## 但每筆裡面沒有 id 欄位，所以補一個再交給 apply()。
func catalog(id: String) -> Dictionary:
	var d: Dictionary = CATALOG.get(id, {})
	if d.is_empty() or ContentLoc.locale() == "zh_TW":
		return d
	var with_id := d.duplicate(true)
	with_id["id"] = id
	var out: Dictionary = ContentLoc.apply("item", with_id, ITEM_TEXT_FIELDS)
	out.erase("id")
	return out


func item_name(id: String) -> String:
	var d := catalog(id)
	return str(d.get("name", id))


func count(id: String) -> int:
	ensure_hotbar()
	return int(GameState.inventory.get(id, 0))


func has_item(id: String, n: int = 1) -> bool:
	return count(id) >= n


func add_item(id: String, n: int = 1) -> bool:
	if n <= 0 or not CATALOG.has(id):
		return false
	ensure_hotbar()
	var stack_max := int(catalog(id).get("stack", 99))
	var cur := count(id)
	var nxt := mini(stack_max, cur + n)
	GameState.inventory[id] = nxt
	## 自動放進第一個空快捷欄
	_auto_hotbar(id)
	inventory_changed.emit()
	hotbar_changed.emit()
	return nxt > cur


func remove_item(id: String, n: int = 1) -> bool:
	if not has_item(id, n):
		return false
	var cur := count(id) - n
	if cur <= 0:
		GameState.inventory.erase(id)
		## 清快捷欄空引用
		for i in GameState.hotbar.size():
			if str(GameState.hotbar[i]) == id and count(id) <= 0:
				GameState.hotbar[i] = ""
	else:
		GameState.inventory[id] = cur
	inventory_changed.emit()
	hotbar_changed.emit()
	return true


func _auto_hotbar(id: String) -> void:
	ensure_hotbar()
	for s in GameState.hotbar:
		if str(s) == id:
			return
	for i in GameState.hotbar.size():
		if str(GameState.hotbar[i]) == "":
			GameState.hotbar[i] = id
			return


func set_hotbar(slot: int, id: String) -> void:
	ensure_hotbar()
	if slot < 0 or slot >= HOTBAR_SIZE:
		return
	if id != "" and count(id) <= 0:
		return
	GameState.hotbar[slot] = id
	hotbar_changed.emit()


func clear_hotbar(slot: int) -> void:
	set_hotbar(slot, "")


func bag_list() -> Array:
	## [{id, count, def}] 有數量的
	ensure_hotbar()
	var out: Array = []
	for id in GameState.inventory.keys():
		var c := int(GameState.inventory[id])
		if c > 0 and CATALOG.has(id):
			out.append({"id": id, "count": c, "def": CATALOG[id]})
	out.sort_custom(func(a, b): return str(a.get("id")) < str(b.get("id")))
	return out


func use_item(id: String) -> Dictionary:
	## {ok, msg, heal, dust, sold}
	if id == "" or not has_item(id):
		return {"ok": false, "msg": "沒有這個道具。"}
	var def: Dictionary = catalog(id)
	var kind := str(def.get("kind", ""))
	match kind:
		"consumable":
			if not remove_item(id, 1):
				return {"ok": false, "msg": "使用失敗。"}
			var msg_parts: PackedStringArray = []
			var healed := 0
			if def.has("heal"):
				healed = _apply_heal(int(def.get("heal", 0)))
				msg_parts.append("HP +%d" % healed)
			if def.has("dust"):
				var d: int = int(def.get("dust", 0))
				GameState.add_stardust(d)
				msg_parts.append("星屑 +%d" % d)
			var res := {
				"ok": true,
				"msg": "使用【%s】%s" % [str(def.get("name", id)), " · ".join(msg_parts)],
				"heal": healed,
				"id": id,
			}
			item_used.emit(id, res)
			return res
		"material":
			## 賣出 1 個
			var sell: int = int(def.get("sell", 1))
			if not remove_item(id, 1):
				return {"ok": false, "msg": "賣出失敗。"}
			GameState.add_gold(sell)
			if Engine.get_main_loop() is SceneTree:
				var qs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("QuestSystem")
				if qs and qs.has_method("track_day"):
					qs.call("track_day", "sell", 1)
			var res2 := {
				"ok": true,
				"msg": "賣出【%s】· 金 +%d" % [str(def.get("name", id)), sell],
				"sold": sell,
				"id": id,
			}
			item_used.emit(id, res2)
			return res2
		"key":
			return {"ok": false, "msg": "【%s】是重要物品，不能消耗。" % str(def.get("name", id))}
		_:
			return {"ok": false, "msg": "無法使用。"}


func use_hotbar_slot(slot: int) -> Dictionary:
	ensure_hotbar()
	if slot < 0 or slot >= HOTBAR_SIZE:
		return {"ok": false, "msg": ""}
	var id := str(GameState.hotbar[slot])
	if id == "":
		## 靜默失敗會讓新玩家以為快捷欄根本沒作用——第一次嘗試就得到零回饋，
		## 這個功能對他而言等於不存在
		return {"ok": false, "msg": "第 %d 格是空的。開 I 背包指派道具。" % (slot + 1)}
	return use_item(id)


func grant_starter() -> void:
	## 新遊戲／教學後
	if GameState.has_flag("inv.starter_given"):
		return
	add_item("hp_s", 3)
	add_item("bread", 2)
	GameState.set_flag("inv.starter_given", true)


func roll_skirmish_loot(mode: String) -> Array:
	## 回傳 [{id, n, msg}]
	var drops: Array = []
	var r := randf()
	if r < 0.45:
		drops.append({"id": "hp_s", "n": 1})
	elif r < 0.65:
		drops.append({"id": "bread", "n": 1})
	## 鍛造材料常駐掉落（循環）
	if randf() < 0.42:
		drops.append({"id": "iron_scrap", "n": 1})
	if randf() < 0.22:
		drops.append({"id": "star_ore", "n": 1})
	if randf() < 0.18:
		drops.append({"id": "oak_resin", "n": 1})
	match mode:
		"ash_rat", "road_bandit":
			if randf() < 0.5:
				drops.append({"id": "wolf_fang", "n": 1})
			if randf() < 0.35:
				drops.append({"id": "knight_shard", "n": 1})
		"fog_shade", "bamboo_spirit":
			if randf() < 0.45:
				drops.append({"id": "mist_shard", "n": 1})
			if randf() < 0.3:
				drops.append({"id": "star_ore", "n": 1})
		"coast_raider", "sewer_slime":
			if randf() < 0.45:
				drops.append({"id": "sea_shell", "n": 1})
			if randf() < 0.28:
				drops.append({"id": "iron_scrap", "n": 2})
		"scar_wisp", "forest_sprite":
			if randf() < 0.4:
				drops.append({"id": "scar_ember" if mode == "scar_wisp" else "dust_crumb", "n": 1})
			if randf() < 0.25:
				drops.append({"id": "oak_resin", "n": 1})
		"black_ronin":
			if randf() < 0.7:
				drops.append({"id": "knight_shard", "n": 2})
			if randf() < 0.5:
				drops.append({"id": "iron_scrap", "n": 2})
		_:
			if randf() < 0.3:
				drops.append({"id": "dust_crumb", "n": 1})
	return drops


func sell_all_materials() -> Dictionary:
	## 一鍵賣出可賣材料。回傳 {ok, gold, count, msg}
	ensure_hotbar()
	var gold_n := 0
	var cnt := 0
	var ids: Array = GameState.inventory.keys().duplicate()
	for id in ids:
		var def: Dictionary = catalog(str(id))
		if str(def.get("kind", "")) != "material":
			continue
		var sell: int = int(def.get("sell", 0))
		if sell <= 0:
			continue
		var n := count(str(id))
		if n <= 0:
			continue
		if remove_item(str(id), n):
			gold_n += sell * n
			cnt += n
	if cnt <= 0:
		return {"ok": false, "gold": 0, "count": 0, "msg": "沒有可賣的材料。"}
	GameState.add_gold(gold_n)
	if Engine.get_main_loop() is SceneTree:
		var qs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("QuestSystem")
		if qs and qs.has_method("track_day"):
			qs.call("track_day", "sell", cnt)
	return {
		"ok": true,
		"gold": gold_n,
		"count": cnt,
		"msg": "賣出材料 %d 件 · 金 +%d" % [cnt, gold_n],
	}


func apply_drops(drops: Array) -> String:
	var parts: PackedStringArray = []
	for d in drops:
		var id := str(d.get("id", ""))
		var n := int(d.get("n", 1))
		if add_item(id, n):
			parts.append("%s×%d" % [item_name(id), n])
	if parts.is_empty():
		return ""
	return "獲得 " + "、".join(parts)
