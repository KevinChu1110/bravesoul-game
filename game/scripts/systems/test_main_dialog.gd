extends SceneTree
## main.gd 台詞資料化的把關測試：godot --headless -s res://scripts/systems/test_main_dialog.gd
##
## 遷移是用「新舊對拍」驗的，這裡把那份對拍固定下來。要理解為什麼是這樣驗，
## 先看 test_npc_lines.gd 開頭那段教訓：round-trip 只證明「文字一條沒掉」，
## 證明不了「掛對位置」—— 兩個分支的 key 對調，文字集合照樣完全一致。
##
## 所以黃金樣本（test_main_dialog_golden.json）是 tools/migrate_main_dialog.py
## 從**遷移前**的 main.gd 機械抽出來的：第 N 個 _play_dialog 呼叫點該吐什麼字。
## 這支測試檢查四件事：
##   1. 遷移後 main.gd 裡 DialogLines.lines() 的出現**順序**與黃金樣本一致
##      → 抓「key 對調」「少搬一處」「多搬一處」
##   2. 每個 key 配上樣本插值後，逐字逐句等於遷移前的輸出
##      → 抓「文字被改動」
##   3. 呼叫端傳的插槽名，跟資料檔文字裡真的用到的插槽一模一樣
##      → 抓「插槽名打錯」「少傳一個」「多傳一個」
##   4. 資料檔裡沒有沒人用的 key
##
## 第 3 條是後來補的，補之前第 1、2 條漏了一整類錯。變異測試證實過：
## 把呼叫端的 {"power": ...} 打成 {"powr": ...}，前三條檢查全綠，
## 但玩家會在畫面上看到「{power}」四個字原封不動印出來 —— 因為第 2 條
## 是拿黃金樣本自己的 vars 去插值的，從頭到尾沒看過 main.gd 實際傳了什麼。
##
## 還守不到的一種錯（誠實記著，不要以為這裡全包了）：同一個呼叫點的兩個值
## 對調，但 key 沒動 —— 例如 {"item": price, "price": 品名}。
## key 一樣、插槽一樣，靜態上看不出來，要靠 test_panels 那類跑起來的測試接。

const GOLDEN_PATH := "res://scripts/systems/test_main_dialog_golden.json"
const MAIN_PATH := "res://scripts/main.gd"
const DIALOG_DIR := "res://data/dialogues"

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var golden := _read_golden()
	if golden.is_empty():
		_fail("讀不到黃金樣本 %s" % GOLDEN_PATH)
		_finish()
		return

	_check_call_order(golden)
	_check_texts(golden)
	_check_call_vars()
	_check_no_orphans(golden)
	_finish()


func _read_golden() -> Array:
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_ARRAY else []


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


## main.gd 裡的呼叫順序要跟黃金樣本一模一樣
func _check_call_order(golden: Array) -> void:
	var f := FileAccess.open(MAIN_PATH, FileAccess.READ)
	if f == null:
		_fail("讀不到 %s" % MAIN_PATH)
		return
	var re := RegEx.create_from_string('DialogLines\\.lines\\("([^"]+)"')
	var found := PackedStringArray()
	for m in re.search_all(f.get_as_text()):
		found.append(m.get_string(1))
	if found.size() != golden.size():
		_fail("main.gd 有 %d 處 DialogLines.lines()，黃金樣本有 %d 筆" % [found.size(), golden.size()])
		return
	for i in golden.size():
		var want := str(golden[i].get("key", ""))
		if found[i] != want:
			_fail("第 %d 處呼叫的 key 是 %s，黃金樣本是 %s（遷移前 main.gd 第 %d 行）"
				% [i + 1, found[i], want, int(golden[i].get("src_line", 0))])
			return
	print("  ok 呼叫順序 %d 處與黃金樣本相符" % found.size())


## 每個 key 填上樣本值之後，要逐字等於遷移前的輸出
func _check_texts(golden: Array) -> void:
	for g in golden:
		var key := str(g.get("key", ""))
		var vars_in: Dictionary = g.get("vars", {})
		var expect: Array = g.get("expect", [])
		var got: Array = DialogLines.lines(key, vars_in)
		if got.size() != expect.size():
			_fail("%s 有 %d 句，黃金樣本 %d 句" % [key, got.size(), expect.size()])
			return
		for i in expect.size():
			var e: Dictionary = expect[i]
			var a: Dictionary = got[i]
			if a.size() != e.size():
				_fail("%s 第 %d 句欄位數不同：實際 %s／期望 %s" % [key, i + 1, str(a.keys()), str(e.keys())])
				return
			for k in e.keys():
				if not a.has(k):
					_fail("%s 第 %d 句少了欄位 %s" % [key, i + 1, str(k)])
					return
				if str(a[k]) != str(e[k]):
					_fail("%s 第 %d 句的 %s 不同\n    實際=%s\n    期望=%s"
						% [key, i + 1, str(k), str(a[k]), str(e[k])])
					return
	print("  ok %d 段台詞逐字與遷移前相同" % golden.size())


## 呼叫端傳進去的插槽名，要跟資料檔文字裡真的用到的插槽一模一樣。
##
## 兩邊的來源刻意不同：一邊是硬解析 main.gd 的原始碼，一邊是直接讀 JSON 檔，
## 都不經過 DialogLines。這樣「_fill 把沒填的插槽吞掉」這種事也躲不掉。
func _check_call_vars() -> void:
	var need := _slots_in_data()
	if need.is_empty():
		_fail("讀不到 %s 底下的台詞資料" % DIALOG_DIR)
		return
	var src := _read_text(MAIN_PATH)
	if src == "":
		_fail("讀不到 %s" % MAIN_PATH)
		return

	var re := RegEx.create_from_string('DialogLines\\.lines\\("([^"]+)"')
	var checked := 0
	for m in re.search_all(src):
		var key := m.get_string(1)
		var got: Array = _vars_at_call(src, m.get_end())
		if got.size() == 1 and str(got[0]) == "?":
			## 呼叫端沒有直接寫出字典（例如先組好再傳）。允許的話這條檢查
			## 隨時可以被繞過，所以寧可擋下來要求改回字面值。
			_fail("%s 的插值不是直接寫成字典，這樣驗不到插槽名" % key)
			return
		if not need.has(key):
			_fail("main.gd 叫了 %s，資料檔裡卻沒有這個 key" % key)
			return
		var want: Array = need[key]
		var have := got.duplicate()
		have.sort()
		if have != want:
			_fail("%s 的插槽對不上：呼叫端傳 %s，文字裡要的是 %s"
				% [key, str(have), str(want)])
			return
		checked += 1
	print("  ok %d 處呼叫的插槽名與文字裡的插槽完全吻合" % checked)


## 每個 key 的文字裡用到哪些 {插槽}。直接讀 JSON，不經過 DialogLines。
func _slots_in_data() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("\\{([a-z_][a-z0-9_]*)\\}")
	var d := DirAccess.open(DIALOG_DIR)
	if d == null:
		return out
	for fname in d.get_files():
		var name := fname
		if name.ends_with(".remap"):
			name = name.substr(0, name.length() - 6)
		if not name.ends_with(".json"):
			continue
		var data = JSON.parse_string(_read_text("%s/%s" % [DIALOG_DIR, name]))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for k in (data as Dictionary).keys():
			var slots: Array = []
			for line in (data as Dictionary)[k]:
				for mm in re.search_all(str((line as Dictionary).get("text", ""))):
					if not slots.has(mm.get_string(1)):
						slots.append(mm.get_string(1))
			slots.sort()
			out[str(k)] = slots
	return out


## 從 `DialogLines.lines("key"` 後面把那個字典的 key 撈出來。
## 回 ["?"] 代表呼叫端沒有直接寫字典，驗不了。
func _vars_at_call(src: String, from: int) -> Array:
	var i := from
	while i < src.length() and src[i] in [" ", "\t", "\n"]:
		i += 1
	if i >= src.length():
		return []
	if src[i] == ")":
		return []
	if src[i] != ",":
		return ["?"]
	i += 1
	while i < src.length() and src[i] in [" ", "\t", "\n"]:
		i += 1
	if i >= src.length() or src[i] != "{":
		return ["?"]

	var keys: Array = []
	var depth := 0
	var in_str := false
	while i < src.length():
		var c := src[i]
		if in_str:
			if c == "\\":
				i += 2
				continue
			if c == '"':
				in_str = false
		elif c == '"':
			in_str = true
			## 只認最外層那一圈的 "名稱": ，巢狀字典裡的不算
			if depth == 1:
				var e := src.find('"', i + 1)
				if e < 0:
					return ["?"]
				var name := src.substr(i + 1, e - i - 1)
				var j := e + 1
				while j < src.length() and src[j] in [" ", "\t"]:
					j += 1
				if j < src.length() and src[j] == ":":
					keys.append(name)
		elif c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				break
		i += 1
	return keys


## 資料檔裡不該有沒人叫的 key —— 有的話多半是改 main.gd 時忘了刪
func _check_no_orphans(golden: Array) -> void:
	var used := {}
	for g in golden:
		used[str(g.get("key", ""))] = true
	var orphans: Array[String] = []
	for k in DialogLines.all_keys():
		if not used.has(k):
			orphans.append(k)
	if not orphans.is_empty():
		_fail("data/dialogues 有 %d 個沒人用的 key：%s" % [orphans.size(), str(orphans)])
		return
	print("  ok 資料檔 %d 個 key 全部有人用" % DialogLines.all_keys().size())


func _finish() -> void:
	if _ok:
		print("MAIN_DIALOG_OK")
		quit(0)
	else:
		print("MAIN_DIALOG_FAIL")
		quit(1)
