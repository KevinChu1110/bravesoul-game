extends RefCounted
## 旅途紀錄面板：列出四格，讓玩家挑一格接著走、或在空格上重新開始。
##
## 宿主介面見 main.gd 的「面板宿主介面」段落。這塊比其他面板多兩條線：
## 載入完要有人把畫面帶回章節、按返回要知道回哪裡（從標題進來跟從中樞進來不一樣）。
## 面板不該知道 main.gd 怎麼跑流程，所以那兩件事由宿主建構完掛 Callable 上來。
##
## 刻意不用 class_name（見 AGENTS.md「寫測試的規矩」）。

const ContentLoc := preload("res://scripts/systems/content_loc.gd")

var _host: Node

## 宿主掛上：紀錄已經進 GameState 了，請把畫面接回章節。新開的旅途也走這支。
var on_loaded: Callable = Callable()
## 宿主掛上：按返回時去哪。沒掛就回中樞。
var on_close: Callable = Callable()

## 刪除要按兩次。記住第一次按的是哪一格，0 代表現在沒有待確認的。
var _pending_delete: int = 0



## 玩家看得到的中文字面值一律包這支（以原文當 key，譯文在
## data/i18n/content/<locale>/ui.json）。務必包在格式化之前 ——
## `_t("A %d") % [n]` 查得到表，`_t("A %d" % [n])` 查不到。
static func _t(s: String) -> String:
	return ContentLoc.text("ui", s)

func _init(host: Node) -> void:
	_host = host


func open() -> void:
	_pending_delete = 0
	_render()


func _render() -> void:
	var summaries: Array = SaveManager.slot_summaries()
	var body := _t("選一格接著走。每一格是各自獨立的一段旅途，不會互相蓋掉。\n\n")
	var buttons: Array = []

	for s in summaries:
		body += _slot_line(s)
		_add_slot_buttons(buttons, s)

	buttons.append({"text": _t("返回"), "cb": _close})
	_host.ui_panel(_t("旅途紀錄"), body, buttons)


func _slot_line(s: Dictionary) -> String:
	var n := int(s.get("slot", 0))
	var mark := "▶ " if n == SaveManager.current_slot and bool(s.get("used", false)) else "　 "
	if not bool(s.get("used", false)):
		return _t("%s[b]第 %d 格[/b] [color=#8a8070]空著[/color]\n\n") % [mark, n]

	var line := _t("%s[b]第 %d 格[/b] %s · Lv%d · %s") % [
		mark, n, str(s.get("name", "")), int(s.get("level", 1)), str(s.get("place", "")),
	]
	if int(s.get("ng_plus", 0)) > 0:
		line += _t(" · 黑焰迴響 ×%d") % int(s.get("ng_plus", 0))
	line += _t("\n　  [color=#b8a88a]走了 %s · 存於 %s[/color]") % [
		str(s.get("play_time_text", "")), str(s.get("saved_at_text", "")),
	]
	if bool(s.get("future", false)):
		line += _t("\n　  [color=#e77]這份紀錄來自更新的遊戲，先更新再讀。[/color]")
	elif bool(s.get("outdated", false)):
		line += _t("\n　  [color=#c96]來自舊版本，讀進去時會自動接上。[/color]")
	return line + "\n\n"


func _add_slot_buttons(buttons: Array, s: Dictionary) -> void:
	var n := int(s.get("slot", 0))
	if not bool(s.get("used", false)):
		buttons.append({"text": _t("第 %d 格 · 新的旅途") % n, "cb": start_new.bind(n)})
		return
	if bool(s.get("future", false)):
		## 讀下去只會把它降級寫壞，所以連按鈕都不給
		buttons.append({"text": _t("第 %d 格 · 讀不了") % n, "cb": _explain_future.bind(n)})
	else:
		buttons.append({"text": _t("第 %d 格 · 接著走") % n, "cb": load_slot.bind(n)})
	var label := (_t("第 %d 格 · 再按一次就真的刪掉") % n) if _pending_delete == n else (_t("第 %d 格 · 刪掉") % n)
	buttons.append({"text": label, "cb": delete_slot.bind(n)})


func load_slot(slot: int) -> void:
	if SaveManager.load_game(slot) != OK:
		_host.ui_toast(_t("第 %d 格讀不起來。") % slot)
		_render()
		return
	_host.ui_toast(_t("回到第 %d 格的旅途。") % slot)
	if on_loaded.is_valid():
		on_loaded.call()


func start_new(slot: int) -> void:
	GameState.reset_new_game()
	if SaveManager.save_game(slot) != OK:
		_host.ui_toast(_t("第 %d 格寫不進去。") % slot)
		_render()
		return
	_host.ui_toast(_t("第 %d 格，新的旅途。") % slot)
	if on_loaded.is_valid():
		on_loaded.call()


## 第一次按只是舉手，第二次才真的動手。刪掉的紀錄回不來，值得多問一次。
func delete_slot(slot: int) -> void:
	if _pending_delete != slot:
		_pending_delete = slot
		_render()
		return
	_pending_delete = 0
	if SaveManager.delete_slot(slot) != OK:
		_host.ui_toast(_t("第 %d 格刪不掉。") % slot)
	else:
		_host.ui_toast(_t("第 %d 格已經清空。") % slot)
	_render()


func _explain_future(slot: int) -> void:
	_host.ui_toast(_t("第 %d 格是更新的遊戲存的，這個版本讀了會弄壞它。") % slot)


func _close() -> void:
	if on_close.is_valid():
		on_close.call()
		return
	_host.ui_goto("hub")
