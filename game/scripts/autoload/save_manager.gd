extends Node
## 本地單槽自動存檔。玩家面用「繼續」即可。
## export／import 僅開發／備份工具，不掛標題 UI。

const SAVE_PATH := "user://bravesoul_save.json"
const BACKUP_PATH := "user://bravesoul_backup.json"


func save_game() -> Error:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(GameState.to_dict(), "\t"))
	return OK


func load_game() -> Error:
	if not FileAccess.file_exists(SAVE_PATH):
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	GameState.from_dict(data)
	return OK


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func export_to_path(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(GameState.to_dict(), "\t"))
	return OK


func import_from_path(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	GameState.from_dict(data)
	return save_game()


## 玩家向備份：寫到 user:// 並回傳實際路徑字串
func export_backup() -> String:
	var err := export_to_path(BACKUP_PATH)
	if err != OK:
		return ""
	return ProjectSettings.globalize_path(BACKUP_PATH)


func import_backup() -> Error:
	return import_from_path(BACKUP_PATH)
