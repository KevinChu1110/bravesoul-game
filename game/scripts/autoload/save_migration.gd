extends RefCounted
## 舊存檔升級。載入時把舊格式一版一版往上帶，帶到 GameState.VERSION 才交出去。
##
## 為什麼 from_dict() 的 `d.get(key, default)` 不夠：那只擋得住「欄位不見了」。
## 擋不住「欄位還在、值的意思變了」——那種情況 get() 會安安靜靜把舊語意的值
## 餵進新程式，數值錯了卻不會報任何錯，玩家只覺得「怎麼跟我上次存的不一樣」。
## 所以每動一次存檔結構，就在下面補一步，把舊值明確翻成新值。
##
## 三條規矩：
##   1. 一步只負責 N → N+1。想跳版的那天，你已經忘記中間那版長什麼樣了。
##   2. 步驟只讀寫傳進來的字典，不准碰 GameState 或任何 autoload。
##      這樣才測得起來，也才能拿去洗雲端拉下來、別台機器寫的存檔。
##   3. 只往上、不往下。遇到比現在還新的存檔就原樣退回並標記，
##      寧可讓玩家看到「這份紀錄來自更新的遊戲」，也不要把它降級寫壞。

## 目前的存檔版本。改動存檔結構時：這裡 +1、GameState.VERSION 同步 +1、
## 下面補一支 _vN_to_vN1()、然後去 test_save_slots.gd 加一個舊檔情境。
const CURRENT := 9

## 沒寫 version 的存檔一律當第 1 版。0.13 之前的檔就是這種。
const OLDEST := 1

## 1 → 2 的武器流派改名。舊的三條路線併進十武器流派時，兩個 id 換了名字。
const PATH_RENAME := {
	"soul": "magic",
	"iron": "hammer",
}

## 快捷欄格數。舊檔可能只存了實際用到的幾格。
const HOTBAR_SIZE := 8


static func version_of(d: Dictionary) -> int:
	var v := int(d.get("version", OLDEST))
	return maxi(OLDEST, v)


## 回傳 {ok, data, from, to, applied, reason}
##   ok      — data 能不能交給 GameState.from_dict()
##   applied — 實際跑過的步驟，空的代表本來就是最新版
##   reason  — ok=false 時給人看的原因（不是玩家面文字，面板要自己換句話說）
static func migrate(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _bad("存檔不是一份字典")
	## 深拷貝：升級不該就地改壞呼叫端手上那份。呼叫端常常還要拿原檔比對或重寫。
	var d: Dictionary = (raw as Dictionary).duplicate(true)
	var from := version_of(d)

	if from > CURRENT:
		## 玩家在另一台裝了新版、存檔同步回這台舊版。降級一定寫壞，不如攔在這裡。
		var res := _bad("存檔版本 %d 比這份遊戲認得的 %d 還新" % [from, CURRENT])
		res["data"] = d
		res["from"] = from
		res["future"] = true
		return res

	var applied := PackedStringArray()
	var v := from
	while v < CURRENT:
		var stepped: Dictionary = _step(v, d)
		if stepped.is_empty():
			## 版號跳號（例如有人把 CURRENT 加了 2 卻只補一支步驟）。
			## 這種時候硬吞下去比噴錯危險，因為錯的是資料不是流程。
			var res := _bad("缺少第 %d 版往上的升級步驟" % v)
			res["from"] = from
			res["applied"] = applied
			return res
		d = stepped
		applied.append("%d→%d" % [v, v + 1])
		v += 1

	d["version"] = CURRENT
	return {
		"ok": true,
		"data": d,
		"from": from,
		"to": CURRENT,
		"applied": applied,
		"future": false,
		"reason": "",
	}


static func _bad(reason: String) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"from": OLDEST,
		"to": CURRENT,
		"applied": PackedStringArray(),
		"future": false,
		"reason": reason,
	}


## 派工。回空字典＝這一版沒有對應步驟。
static func _step(from_v: int, d: Dictionary) -> Dictionary:
	match from_v:
		1:
			return _v1_to_v2(d)
		2:
			return _v2_to_v3(d)
		3:
			return _v3_to_v4(d)
		4:
			return _v4_to_v5(d)
		5:
			return _v5_to_v6(d)
		6:
			return _v6_to_v7(d)
		7:
			return _v7_to_v8(d)
		8:
			return _v8_to_v9(d)
	return {}


## 1 → 2：招式從單一欄位攤成字典、武器流派 id 改名、快捷欄長度固定。
##
## 這三件事原本寫死在 from_dict() 裡每次載入都跑一遍。搬過來的好處是：
## 存檔升上第 2 版之後就不必再跑，而且「什麼時候變的」有地方可查。
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	## 欄位拆分：舊檔只記得斬擊等級，新檔每招各有等級與熟練
	var sd: Variant = d.get("skill_data", {})
	if typeof(sd) != TYPE_DICTIONARY:
		sd = {}
	var slash := int(d.get("skill_slash_lv", 0))
	if (sd as Dictionary).is_empty() and slash > 0:
		(sd as Dictionary)["slash"] = {"lv": slash, "mastery": 0}
	d["skill_data"] = sd

	## 值改名：舊的三條路線併進十武器流派
	var p := str(d.get("path_style", ""))
	d["path_style"] = str(PATH_RENAME.get(p, p))

	## 快捷欄補滿。少一格不會報錯，只會讓玩家第 8 格點下去沒反應。
	var hb: Variant = d.get("hotbar", [])
	if typeof(hb) != TYPE_ARRAY:
		hb = []
	var arr: Array = hb
	while arr.size() < HOTBAR_SIZE:
		arr.append("")
	if arr.size() > HOTBAR_SIZE:
		arr.resize(HOTBAR_SIZE)
	d["hotbar"] = arr

	return d


## 2 → 3：新增遊玩時間；戰魂的 equipped 改成由 soul_slots 推導。
static func _v2_to_v3(d: Dictionary) -> Dictionary:
	## 欄位新增：舊檔沒這個數字，補 0。留空的話摘要會顯示成一段空白。
	if not d.has("play_time"):
		d["play_time"] = 0.0

	## 語意改變 —— 這一步是整套升級機制存在的理由。
	##
	## souls[].equipped 以前是各記各的一筆狀態，soul_slots 也記一份，兩邊各改各的。
	## 只要有一條路徑漏更新（例如魂被熔掉、槽數縮回去），就會出現
	## equipped=true 卻不在任何槽上的魂：加成算不到，背包也不列它，那顆魂等於消失。
	##
	## 第 3 版起 equipped 只是 soul_slots 的影子。舊檔的值不能沿用——欄位名沒變、
	## 型別沒變，光看 get() 完全看不出問題，所以一律照 soul_slots 重算。
	var slots: Variant = d.get("soul_slots", [])
	var on_slot := {}
	if typeof(slots) == TYPE_ARRAY:
		for sid in (slots as Array):
			if str(sid) != "":
				on_slot[str(sid)] = true

	var souls: Variant = d.get("souls", [])
	if typeof(souls) == TYPE_ARRAY:
		var out: Array = []
		for s in (souls as Array):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var soul: Dictionary = s
			soul["equipped"] = on_slot.has(str(soul.get("id", "")))
			out.append(soul)
		d["souls"] = out
	else:
		d["souls"] = []

	return d


## 3 → 4：倉庫與市集被移除，存在那兩處的東西要還給玩家。
##
## 這一步不是「補一個欄位」而是「把資料搬家」。倉庫欄位直接刪掉的話，
## 玩家存進去的材料與裝備會安安靜靜消失——存檔讀得出來、遊戲也不會報錯，
## 只是東西不見了。所以先倒回背包再刪。
##
## 市集掛單同理：本地掛單是把物品從背包扣走、寄放在 market.local_listings 裡的，
## 系統沒了就沒有地方能取回，得在這裡退還。
static func _v3_to_v4(d: Dictionary) -> Dictionary:
	var inv: Variant = d.get("inventory", {})
	if typeof(inv) != TYPE_DICTIONARY:
		inv = {}
	var bag: Dictionary = inv

	## 倉庫的堆疊物倒回背包
	var wh: Variant = d.get("warehouse", {})
	if typeof(wh) == TYPE_DICTIONARY:
		for item_id in (wh as Dictionary).keys():
			var n := int((wh as Dictionary)[item_id])
			if n > 0:
				bag[str(item_id)] = int(bag.get(str(item_id), 0)) + n
	d.erase("warehouse")

	## 倉庫的裝備實例倒回未裝備清單
	var eq_bag: Variant = d.get("equip_bag", [])
	if typeof(eq_bag) != TYPE_ARRAY:
		eq_bag = []
	var wh_eq: Variant = d.get("warehouse_equip", [])
	if typeof(wh_eq) == TYPE_ARRAY:
		for inst in (wh_eq as Array):
			if typeof(inst) == TYPE_DICTIONARY:
				(eq_bag as Array).append(inst)
	d.erase("warehouse_equip")
	d["equip_bag"] = eq_bag

	## 本地掛單退貨。掛單格式是 {item_id, qty, ...}；認不出來的就跳過，
	## 寧可少退一筆也不要把垃圾塞進背包。
	var flags: Variant = d.get("flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		var listings: Variant = (flags as Dictionary).get("market.local_listings", [])
		if typeof(listings) == TYPE_ARRAY:
			for row in (listings as Array):
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var iid := str((row as Dictionary).get("item_id", ""))
				var q := int((row as Dictionary).get("qty", 0))
				if iid != "" and q > 0:
					bag[iid] = int(bag.get(iid, 0)) + q
		(flags as Dictionary).erase("market.local_listings")
		(flags as Dictionary).erase("market.pending_credit")
		d["flags"] = flags

	d["inventory"] = bag
	return d


## 4 → 5：抽魂寫回原作葫蘆魂器。舊檔沒有魂器欄位，從綠葫蘆起步並給 1 次免費。
static func _v4_to_v5(d: Dictionary) -> Dictionary:
	if str(d.get("soul_vessel", "")) == "":
		d["soul_vessel"] = "綠葫蘆"
	if not d.has("soul_free_draws"):
		d["soul_free_draws"] = 1
	if not d.has("soul_free_day"):
		d["soul_free_day"] = ""
	return d


## 5 → 6：能量制＋飾品六槽（舊 accessory → ring）。
static func _v5_to_v6(d: Dictionary) -> Dictionary:
	if not d.has("energy"):
		d["energy"] = 15
	if not d.has("energy_ts"):
		d["energy_ts"] = 0.0
	var slots: Variant = d.get("equip_slots", {})
	if typeof(slots) != TYPE_DICTIONARY:
		slots = {}
	var sl: Dictionary = slots
	if sl.has("accessory"):
		var legacy := str(sl.get("accessory", ""))
		if legacy != "" and str(sl.get("ring", "")) == "":
			sl["ring"] = legacy
		sl.erase("accessory")
	for s in ["weapon", "armor", "ring", "necklace", "bracelet", "earring", "amulet", "belt"]:
		if not sl.has(s):
			sl[s] = ""
	d["equip_slots"] = sl
	## 背包／已裝備實例的 slot 欄位
	for key in ["equip_bag"]:
		var arr: Variant = d.get(key, [])
		if typeof(arr) == TYPE_ARRAY:
			var out: Array = []
			for inst in arr:
				if typeof(inst) == TYPE_DICTIONARY:
					var e: Dictionary = inst
					if str(e.get("slot", "")) == "accessory":
						e["slot"] = "ring"
					out.append(e)
				else:
					out.append(inst)
			d[key] = out
	var worn: Variant = d.get("equip_worn", {})
	if typeof(worn) == TYPE_DICTIONARY:
		var wo: Dictionary = {}
		for uid in (worn as Dictionary).keys():
			var inst2: Variant = (worn as Dictionary)[uid]
			if typeof(inst2) == TYPE_DICTIONARY:
				var e2: Dictionary = inst2
				if str(e2.get("slot", "")) == "accessory":
					e2["slot"] = "ring"
				wo[uid] = e2
			else:
				wo[uid] = inst2
		d["equip_worn"] = wo
	return d


## 6 → 7：真正多武器欄（最多 3；由 equip_slots.weapon 灌進第 1 欄）
static func _v6_to_v7(d: Dictionary) -> Dictionary:
	var loadout: Variant = d.get("weapon_loadout", null)
	if typeof(loadout) != TYPE_ARRAY:
		loadout = ["", "", ""]
	var lo: Array = loadout
	while lo.size() < 3:
		lo.append("")
	if lo.size() > 3:
		lo.resize(3)
	var slots: Variant = d.get("equip_slots", {})
	var wuid := ""
	if typeof(slots) == TYPE_DICTIONARY:
		wuid = str((slots as Dictionary).get("weapon", ""))
	## 若三欄皆空，把當前武器放進第 0 欄
	var any := false
	for i in 3:
		if str(lo[i]) != "":
			any = true
			break
	if not any and wuid != "":
		lo[0] = wuid
	elif wuid != "" and str(lo[0]) == "":
		lo[0] = wuid
	d["weapon_loadout"] = lo
	var active := int(d.get("weapon_loadout_active", 0))
	if active < 0 or active > 2:
		active = 0
	## 若 active 空而 0 有武，對齊 0
	if str(lo[active]) == "" and str(lo[0]) != "":
		active = 0
	d["weapon_loadout_active"] = active
	## 同步 equip_slots.weapon = active 欄
	if typeof(slots) != TYPE_DICTIONARY:
		slots = {
			"weapon": "", "armor": "",
			"ring": "", "necklace": "", "bracelet": "", "earring": "", "amulet": "", "belt": "",
		}
	(slots as Dictionary)["weapon"] = str(lo[active])
	d["equip_slots"] = slots
	return d


## 7 → 8：寶石背包＋演武挑戰狀
static func _v7_to_v8(d: Dictionary) -> Dictionary:
	if typeof(d.get("gem_bag", null)) != TYPE_ARRAY:
		d["gem_bag"] = []
	if not d.has("arena_tickets"):
		## 舊檔：依今日剩餘有獎場次灌挑戰狀（最多 5）
		var runs := 0
		var flags: Variant = d.get("flags", {})
		if typeof(flags) == TYPE_DICTIONARY:
			runs = int((flags as Dictionary).get("arena.runs_today", 0))
		var left := maxi(0, 3 - runs)
		d["arena_tickets"] = clampi(maxi(left, 1), 1, 5)
	if not d.has("arena_ticket_ts"):
		d["arena_ticket_ts"] = 0.0
	return d


## 8 → 9：寶石碎片＋熔爐第二產線
static func _v8_to_v9(d: Dictionary) -> Dictionary:
	if typeof(d.get("gem_shards", null)) != TYPE_DICTIONARY:
		d["gem_shards"] = {"red": 0, "yellow": 0, "blue": 0}
	else:
		var sh: Dictionary = d["gem_shards"]
		for c in ["red", "yellow", "blue"]:
			if not sh.has(c):
				sh[c] = 0
		d["gem_shards"] = sh
	if not d.has("gem_furnace"):
		d["gem_furnace"] = false
	if not d.has("gem_smelt_day"):
		d["gem_smelt_day"] = ""
	if not d.has("gem_smelt_used"):
		d["gem_smelt_used"] = 0
	return d
