extends Node
## 本地存檔：四格紀錄 ＋ 舊檔升級。
##
## 為什麼要分格：只有一份檔的時候，玩家想試另一條武器流派就得覆蓋掉現在的進度，
## 想回頭也回不去。分格之後每格是各自獨立的一段旅途，互不覆蓋。
##
## 為什麼載入一定經過 SaveMigration：舊檔有些欄位名字沒變、意思變了（見
## save_migration.gd 的 souls[].equipped）。不升級就直接餵給 GameState，
## 壞掉的是數值而不是流程，不會噴任何錯，玩家只會覺得自己莫名其妙變弱。
##
## export／import 仍然只是開發／備份工具，不掛在玩家面。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

const SaveMigration = preload("res://scripts/autoload/save_migration.gd")

const SLOT_COUNT := 4

## 0.14 之前只有這一份單檔。開機時搬進第 1 格，搬完就改名——
## 不改名的話，玩家哪天刪掉第 1 格，下次開遊戲它又會被救回來。
const LEGACY_NAME := "bravesoul_save.json"
const LEGACY_DONE_NAME := "bravesoul_save.pre_slots.json"
const BACKUP_NAME := "bravesoul_backup.json"
const SLOT_SUBDIR := "saves"

## 存檔根目錄。正常就是 user://；測試會改指到別的資料夾，
## 免得跑一次無頭測試就把玩家真正的紀錄洗掉。
var root_dir: String = "user://"

## 沒指定格數時寫哪一格。main.gd 那一堆無參數的 save_game() 都落在這裡。
var current_slot: int = 1

## 章節 id → 玩家看得懂的地名。摘要上只寫「c3」沒人知道那是哪。
const CHAPTER_NAMES := {
	"title": "尚未啟程",
	"c0": "翠谷村",
	"c1": "騎士堡",
	"c2": "霧隱村",
	"c3": "武鬥道場",
	"c4": "遊俠森林",
	"c5": "維京海岸",
	"c6": "塔下營地",
	"cleared": "晨光之後",
}



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _ready() -> void:
	_adopt_legacy_save()
	## 開機指向最近存過的那一格，標題的「繼續」才會接到玩家上次玩的進度
	var newest := newest_slot()
	if newest > 0:
		current_slot = newest


func _process(delta: float) -> void:
	## 停在標題翻設定不算旅途時間，否則摘要那個數字會慢慢膨脹成沒有意義的數。
	if GameState.chapter == "" or GameState.chapter == "title":
		return
	GameState.play_time += delta


# ─── 路徑 ───

func slot_dir() -> String:
	return root_dir.path_join(SLOT_SUBDIR)


func slot_path(slot: int) -> String:
	return slot_dir().path_join("slot_%d.json" % slot)


func legacy_path() -> String:
	return root_dir.path_join(LEGACY_NAME)


func backup_path() -> String:
	return root_dir.path_join(BACKUP_NAME)


func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


# ─── 存 ／ 讀 ───

## slot 省略＝寫目前這一格
func save_game(slot: int = -1) -> Error:
	## 人還在標題畫面時，GameState 裡是一份誰都不是的預設值——還沒有人按下「繼續」。
	## 這時候寫檔就是拿「小白 Lv1」去蓋掉開機時指向的那一格，玩家的進度當場消失。
	## 標題上的稱號牆一按就會走到這裡（它評估完稱號就存檔），所以擋在最底層而不是逐支去堵。
	## 稱號本身是從別的 flag 推出來的，晚一次寫也推得回來，不會少東西。
	if GameState.chapter == "" or GameState.chapter == "title":
		return OK
	var s := _resolve_write_slot(slot)
	if not is_valid_slot(s):
		return ERR_INVALID_PARAMETER
	var payload: Dictionary = GameState.to_dict()
	## 存檔時間寫進同一份檔：摘要才能只讀檔就列出來，不必先載進 GameState
	payload["saved_at"] = int(Time.get_unix_time_from_system())
	var err := _write(s, payload)
	if err == OK:
		current_slot = s
	return err


## slot 省略＝目前這一格；那一格是空的（例如剛被刪掉）就退到最近存過的一格，
## 標題的「繼續」才不會因為刪了一格就整個消失。
func load_game(slot: int = -1) -> Error:
	var s := slot
	if not is_valid_slot(s):
		s = current_slot if has_save_in(current_slot) else newest_slot()
	if not is_valid_slot(s):
		return ERR_FILE_NOT_FOUND
	var raw := _read(s)
	if raw.is_empty():
		return ERR_FILE_NOT_FOUND if not FileAccess.file_exists(slot_path(s)) else ERR_INVALID_DATA

	var res: Dictionary = SaveMigration.migrate(raw)
	if not bool(res.get("ok", false)):
		push_error(_t("第 %d 格讀不起來：%s") % [s, str(res.get("reason", ""))])
		return ERR_INVALID_DATA

	GameState.from_dict(res.get("data", {}))
	current_slot = s

	## 升級過就立刻寫回。不寫回的話每次載入都要重跑一遍，而且下次還是舊格式——
	## 等到哪天某個步驟被刪掉（因為以為沒人在用了），那份檔就真的救不回來了。
	var applied: PackedStringArray = res.get("applied", PackedStringArray())
	if not applied.is_empty():
		var upgraded: Dictionary = (res.get("data", {}) as Dictionary).duplicate(true)
		## 保留原本的存檔時間：升級不是玩家存的檔，不該讓摘要顯示成「剛剛」
		upgraded["saved_at"] = int(raw.get("saved_at", 0))
		_write(s, upgraded)
	return OK


## 有沒有任何一格有紀錄。標題的「繼續」用這支。
func has_save() -> bool:
	return newest_slot() > 0


func has_save_in(slot: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


## 最近存過、而且真的讀得起來的那一格；沒有回 0。
## 讀不出來的那一格不能算數：標題會照著這支決定要不要給「繼續」，
## 算進去的話玩家會看到一顆按了只會彈回標題的按鈕，還以為是遊戲當了。
func newest_slot() -> int:
	var best := 0
	var best_t := -1
	for s in range(1, SLOT_COUNT + 1):
		if not has_save_in(s):
			continue
		var raw := _read(s)
		if raw.is_empty():
			continue
		var t := int(raw.get("saved_at", 0))
		if t > best_t:
			best_t = t
			best = s
	return best


## 四格裡有沒有任何一格被占著（含讀不出來的壞檔）。
## 跟 has_save() 分開：壞檔不能拿來「繼續」，但要讓玩家進得了紀錄面板把它清掉。
func has_any_slot() -> bool:
	for s in range(1, SLOT_COUNT + 1):
		if has_save_in(s):
			return true
	return false


## 第一個空著的格子；四格都滿了回 0。
## 開新旅途前先問這支，不然「新遊戲」會直接蓋掉玩家上次玩的那一格。
func first_empty_slot() -> int:
	for s in range(1, SLOT_COUNT + 1):
		if not has_save_in(s):
			return s
	return 0


func delete_slot(slot: int) -> Error:
	if not has_save_in(slot):
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.remove_absolute(slot_path(slot))
	if err != OK:
		push_error(_t("第 %d 格刪不掉：%s") % [slot, error_string(err)])
		return err
	## 刪掉的是目前這一格的話，指標不能繼續留在那裡：
	## 下一次無參數的 save_game() 會照著它把剛刪掉的紀錄原封不動寫回去，
	## 玩家會發現自己刪不掉那一格。改指到還活著的最新一格。
	if slot == current_slot:
		current_slot = maxi(1, newest_slot())
	return OK


# ─── 摘要（給存檔面板列表用）───

func slot_summaries() -> Array:
	var out: Array = []
	for s in range(1, SLOT_COUNT + 1):
		out.append(slot_summary(s))
	return out


## 只讀檔、不動 GameState。欄位都是可以直接印給玩家看的。
func slot_summary(slot: int) -> Dictionary:
	var base := {
		"slot": slot,
		"used": false,
		"name": "",
		"chapter": "",
		"place": "",
		"level": 0,
		"gold": 0,
		"path": "",
		"ng_plus": 0,
		"play_time": 0.0,
		"play_time_text": "",
		"saved_at": 0,
		"saved_at_text": "",
		"version": 0,
		"outdated": false,
		"future": false,
	}
	if not has_save_in(slot):
		return base
	var raw := _read(slot)
	if raw.is_empty():
		## 檔在、內容壞了。這種也要列出來，玩家至少知道那一格被占住了。
		base["used"] = true
		base["name"] = _t("（這格的內容讀不出來）")
		return base

	var v := int(SaveMigration.version_of(raw))
	base["used"] = true
	base["name"] = str(raw.get("player_name", _t("無名")))
	base["chapter"] = str(raw.get("chapter", "title"))
	## CHAPTER_NAMES 是 const（裡面不能呼叫函式），所以譯文查在讀的時候
	base["place"] = _t(str(CHAPTER_NAMES.get(base["chapter"], base["chapter"])))
	base["level"] = int(raw.get("level", 1))
	base["gold"] = int(raw.get("gold", 0))
	base["path"] = str(raw.get("path_style", ""))
	base["ng_plus"] = int(raw.get("ng_plus", 0))
	base["play_time"] = float(raw.get("play_time", 0.0))
	base["play_time_text"] = format_play_time(base["play_time"])
	base["saved_at"] = int(raw.get("saved_at", 0))
	base["saved_at_text"] = format_saved_at(base["saved_at"])
	base["version"] = v
	base["outdated"] = v < SaveMigration.CURRENT
	base["future"] = v > SaveMigration.CURRENT
	return base


static func format_play_time(sec: float) -> String:
	var t := int(maxf(0.0, sec))
	var h := t / 3600
	var m := (t % 3600) / 60
	if h > 0:
		return _t("%d 小時 %d 分") % [h, m]
	if m > 0:
		return _t("%d 分") % m
	return _t("未滿 1 分")


## 一律講相對時間，避免時區換算出錯讓玩家看到一個差了 8 小時的日期。
## 超過一週才退回日期，那時候「幾天前」已經沒有參考價值了。
static func format_saved_at(unix_t: int) -> String:
	if unix_t <= 0:
		return _t("時間不明")
	var diff := int(Time.get_unix_time_from_system()) - unix_t
	if diff < 0:
		return _t("時間不明")
	if diff < 90:
		return _t("剛剛")
	if diff < 3600:
		return _t("%d 分鐘前") % (diff / 60)
	if diff < 86400:
		return _t("%d 小時前") % (diff / 3600)
	if diff < 604800:
		return _t("%d 天前") % (diff / 86400)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var dt := Time.get_datetime_dict_from_unix_time(unix_t + bias * 60)
	return "%d/%d/%d" % [int(dt.get("year", 0)), int(dt.get("month", 0)), int(dt.get("day", 0))]


# ─── 備份／匯出（開發與救援用，不掛玩家面）───

func export_to_path(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var payload: Dictionary = GameState.to_dict()
	payload["saved_at"] = int(Time.get_unix_time_from_system())
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return OK


## 匯入的檔可能是很久以前備份的，一樣要走升級再進 GameState
func import_from_path(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var res: Dictionary = SaveMigration.migrate(parsed)
	if not bool(res.get("ok", false)):
		push_error(_t("匯入失敗：%s") % str(res.get("reason", "")))
		return ERR_INVALID_DATA
	GameState.from_dict(res.get("data", {}))
	return save_game()


## 玩家向備份：寫到 user:// 並回傳實際路徑字串
func export_backup() -> String:
	if export_to_path(backup_path()) != OK:
		return ""
	return ProjectSettings.globalize_path(backup_path())


func import_backup() -> Error:
	return import_from_path(backup_path())


# ─── 內部 ───

func _resolve_write_slot(slot: int) -> int:
	return slot if is_valid_slot(slot) else current_slot


func _ensure_dir() -> bool:
	var d := slot_dir()
	if DirAccess.dir_exists_absolute(d):
		return true
	var err := DirAccess.make_dir_recursive_absolute(d)
	if err != OK:
		push_error(_t("建不出存檔資料夾 %s：%s") % [d, error_string(err)])
		return false
	return true


## 先寫暫存檔再改名。直接覆蓋的話，寫到一半當掉就同時失去舊的和新的——
## 存檔是玩家唯一不能重來的東西，值得多這一步。
func _write(slot: int, payload: Dictionary) -> Error:
	if not _ensure_dir():
		return ERR_CANT_CREATE
	var final_path := slot_path(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error(_t("第 %d 格寫不進去：%s") % [slot, error_string(err)])
		return err
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir := DirAccess.open(slot_dir())
	if dir == null:
		return DirAccess.get_open_error()
	## 不先刪舊檔：rename 本身就會原子地蓋過去（Windows 上 Godot 內部也是這樣處理）。
	## 自己先刪只是在「舊的沒了、新的還沒就位」之間開一個原本不存在的空窗。
	var rerr := dir.rename(tmp_path.get_file(), final_path.get_file())
	if rerr != OK:
		push_error(_t("第 %d 格收尾失敗：%s") % [slot, error_string(rerr)])
	return rerr


## 讀出原始字典（不升級、不進 GameState）。讀不到或格式壞掉都回空字典。
func _read(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## 把 0.14 之前的單檔搬進第 1 格。只在第 1 格是空的時候搬，
## 不然玩家新開的旅途會被一份很舊的紀錄蓋掉。
func _adopt_legacy_save() -> bool:
	var old := legacy_path()
	if not FileAccess.file_exists(old):
		return false
	if has_save_in(1):
		return false
	var f := FileAccess.open(old, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if _write(1, parsed) != OK:
		return false
	## 改名而不是刪掉：萬一搬壞了，檔案還在原地救得回來
	var dir := DirAccess.open(root_dir)
	if dir != null:
		dir.rename(LEGACY_NAME, LEGACY_DONE_NAME)
	return true
