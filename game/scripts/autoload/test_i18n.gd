extends SceneTree
## 翻譯表的把關測試：godot --headless -s res://scripts/autoload/test_i18n.gd
##
## 守三件事：
##   1. 每張語言表的 key 都要跟繁中一模一樣。少一個 key 不會報錯 ——
##      Loc.t() 查不到就**回傳 key 本身**，玩家會直接看到 "panel.world_map"。
##   2. 程式裡 Loc.t("...") 用到的 key 都要在表裡。同上，漏了不會當掉，
##      只會在畫面上冒出一個看起來像亂碼的英文字。
##   3. 劇情檔（dialogues／npc_lines）每個語言都要補齊。介面翻完但劇情沒翻，
##      玩家切過去會看到半英半中 —— 比整份沒翻更像 bug。
##
## 這支不管「翻得好不好」（那要人看），只管「有沒有漏」。

## 繁中是原文，其餘都要對齊它
const LOCALES := ["zh_CN", "en", "ja", "ko", "es"]
const STORY_DIRS := ["res://data/dialogues", "res://data/npc_lines"]

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _initialize() -> void:
	var zh := _load("res://data/i18n/zh_TW.json")
	if zh.is_empty():
		_fail("讀不到繁中翻譯表")
		return _finish()

	## 1) 每個語言的 key 都要跟繁中對齊
	for code in LOCALES:
		var tbl := _load("res://data/i18n/%s.json" % code)
		if tbl.is_empty():
			_fail("讀不到 %s 的翻譯表" % code)
			continue
		var missing: PackedStringArray = []
		var extra: PackedStringArray = []
		for k in zh.keys():
			if str(tbl.get(k, "")) == "":
				missing.append(str(k))
		for k in tbl.keys():
			if not zh.has(k):
				extra.append(str(k))
		if missing.size() > 0 or extra.size() > 0:
			_fail("%s 對不齊 —— 缺：%s；多出來：%s" % [
				code, ", ".join(missing), ", ".join(extra)])
	if not _ok:
		return _finish()
	print("  ok %d 個語言各 %d 個 key，全部對齊" % [LOCALES.size() + 1, zh.size()])

	## 2) 劇情檔要補齊
	_check_story()
	if not _ok:
		return _finish()

	## 3) 程式用到的 key 都要在表裡
	var used: Dictionary = {}
	_scan_dir("res://scripts", used)
	if used.is_empty():
		_fail("從程式裡一個 Loc.t() 都沒抓到 —— 這條檢查等於沒在檢查")
		return _finish()
	var missing: PackedStringArray = []
	for k in used.keys():
		if not zh.has(k):
			missing.append(str(k))
	if missing.size() > 0:
		_fail("程式用了表裡沒有的 key，玩家會直接看到 key 本身：%s" % ", ".join(missing))
		return _finish()
	print("  ok 程式用到的 %d 個 key 都在表裡" % used.size())
	_finish()


## 劇情檔：每個語言的子目錄都要有跟原文一樣多的檔，而且每個檔的 key 要對齊。
## 只比檔名不比內容的話，一個空殼 json 也算過關。
func _check_story() -> void:
	for d in STORY_DIRS:
		var base := DirAccess.open(d)
		if base == null:
			_fail("讀不到劇情目錄 %s" % d)
			continue
		var names: PackedStringArray = []
		for f in base.get_files():
			if f.ends_with(".json"):
				names.append(f)
		if names.is_empty():
			_fail("%s 裡一個劇情檔都沒有" % d)
			continue
		for code in LOCALES:
			for f in names:
				var src := _load("%s/%s" % [d, f])
				var tr := _load("%s/%s/%s" % [d, code, f])
				if tr.is_empty():
					_fail("%s/%s/%s 缺檔或是空的" % [d, code, f])
					continue
				var miss: PackedStringArray = []
				for k in src.keys():
					if not tr.has(k):
						miss.append(str(k))
				if miss.size() > 0:
					_fail("%s/%s/%s 漏了：%s" % [d, code, f, ", ".join(miss)])
	if _ok:
		print("  ok 劇情檔 %d 個語言都補齊了" % LOCALES.size())


func _scan_dir(path: String, used: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var re := RegEx.create_from_string('Loc\\.t\\(\\s*"([a-z0-9_.]+)"')
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		## 測試與量測腳本不算
		if f.begins_with("test_"):
			continue
		var fh := FileAccess.open(path + "/" + f, FileAccess.READ)
		if fh == null:
			continue
		## 逐行掃並跳過註解 —— loc.gd 的檔頭就寫著用法範例 Loc.t("key")，
		## 整檔一次掃會把那個範例當成真的 key，於是測試自己造出一個假失敗。
		for line in fh.get_as_text().split("\n"):
			var st := line.strip_edges()
			if st.begins_with("#"):
				continue
			for m in re.search_all(line):
				used[m.get_string(1)] = true
	for d in dir.get_directories():
		if d == "dev":
			continue
		_scan_dir(path + "/" + d, used)


func _finish() -> void:
	if _ok:
		print("I18N_OK")
		quit(0)
	else:
		print("I18N_FAIL")
		quit(1)
