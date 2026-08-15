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
const CURRENT := 3

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
