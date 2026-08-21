extends SceneTree
## 面板迴歸測試：godot --headless -s res://scripts/ui/test_panels.gd
##
## 為什麼要有這支：把面板從 main.gd 一塊一塊搬出去時，smoke（開機沒 script error）
## 只證明「載得起來」，證明不了「面板打開後長得對」。這支實際載入主場景、
## 呼叫入口、然後去 host 底下檢查真的產生了選單節點與按鈕。
##
## 新搬一塊面板就往 PANELS 加一筆。

## entry: main.gd 上的入口方法名
## title: 面板標題（Label 需完全相符）
## min_buttons: 至少要有幾顆按鈕
## expect_buttons: 這些字串每個都要出現在某顆按鈕的文字裡
##
## 注意 expect_buttons 為什麼必要：面板常常先同步畫一次、之後再重畫一次。
## 只驗「標題 + 按鈕數」的話，就算把同步那次拿掉，後來的重畫也會把測試補成綠燈
## —— 實測過，那種破壞抓不到。驗到具體按鈕才擋得住。
const PANELS: Array = [
	## 裝備面板：武器欄三格 + 防具／飾品 + 背包
	{
		"entry": "_go_equip_panel",
		"title": "裝備",
		"min_buttons": 2,
		"expect_buttons": ["返回", "裝填"],
	},
	{
		"entry": "_go_save_slots_panel",
		"title": "旅途紀錄",
		"min_buttons": 1,
		"expect_buttons": ["返回"],
	},
]

## main.gd 必須提供給 scripts/ui/panels/* 的公開契約
const HOST_API: Array = [
	"ui_panel", "ui_toast", "ui_goto",
	"ui_host", "ui_clear_host", "ui_reset_fade", "ui_refresh_hud",
]

var _ok := true
var _step := 0
var _wait := 0
var _main: Node = null
var _idx := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _process(_d: float) -> bool:
	_wait += 1
	match _step:
		0:
			## 等主場景就緒
			if _wait < 20:
				return false
			_main = current_scene
			if _main == null:
				_fail("main scene 沒載起來")
				return _finish()
			## 宿主契約
			for m in HOST_API:
				if not _main.has_method(m):
					_fail("main.gd 缺少宿主介面 %s()" % m)
				else:
					print("  ok host api ", m)
			## 市集要解鎖才會出現完整面板
			var gs := root.get_node_or_null("GameState")
			if gs == null:
				_fail("GameState autoload missing")
				return _finish()
			gs.reset_new_game()
			gs.set_flag("c1_entered_city", true)
			_step = 1
			_wait = 0
		1:
			if _idx >= PANELS.size():
				_check_goto_targets()
				_main.call("ui_panel", OVERFLOW_TITLE, "測試用面板。", _overflow_buttons())
				_step = 3
				_wait = 0
				return false
			var p: Dictionary = PANELS[_idx]
			var entry := str(p["entry"])
			if not _main.has_method(entry):
				_fail("main.gd 缺少入口 %s()" % entry)
				_idx += 1
				return false
			_main.call(entry)
			_step = 2
			_wait = 0
		2:
			## _panel 用 call_deferred 收尾，多等幾幀再檢查
			if _wait < 8:
				return false
			_check_panel(PANELS[_idx])
			_idx += 1
			_step = 1
			_wait = 0
		3:
			if _wait < 8:
				return false
			if not _check_overflow_layout():
				return _finish()
			## 捲到底，下一步驗最後一顆按鈕真的到得了
			if _overflow_scroll == null:
				_fail("按鈕爆量：按鈕列沒有放進 ScrollContainer，捲不動")
				return _finish()
			_overflow_scroll.scroll_vertical = 100000
			_step = 4
			_wait = 0
		4:
			if _wait < 4:
				return false
			_check_overflow_reachable()
			return _finish()
	return false


## 按鈕爆量時，最後一顆按鈕還是要在畫面裡。
##
## 為什麼特地測這個：按鈕列原本直接掛在卡片上，沒有捲動。按鈕一多，卡片就長過
## 螢幕，而 CenterContainer 是置中的 —— 上下同時被切掉，「返回」被推出畫面外。
## Esc 只會疊出暫停選單，玩家唯一的出路是回標題，那一趟的進度就沒了。
## 這是「面板長得對」測不到的一類壞法：標題在、按鈕也都建出來了，
## 只是玩家點不到。所以這裡驗的是**幾何**，不是節點數量。
const OVERFLOW_TITLE := "按鈕爆量測試"
const OVERFLOW_N := 24


func _overflow_buttons() -> Array:
	var out: Array = []
	for i in OVERFLOW_N:
		out.append({"text": "選項 %d" % (i + 1), "cb": Callable()})
	out.append({"text": "返回", "cb": Callable()})
	return out


var _overflow_scroll: ScrollContainer = null
var _overflow_last: Button = null


func _check_overflow_layout() -> bool:
	var host: Node = _main.get("host")
	if host == null:
		_fail("找不到 ScreenHost")
		return false
	var nodes: Array = []
	_collect_nodes(host, nodes)
	var btns: Array = []
	_overflow_scroll = null
	for n in nodes:
		if n is Button:
			btns.append(n)
		elif n is ScrollContainer:
			_overflow_scroll = n
	if btns.size() < OVERFLOW_N + 1:
		_fail("按鈕爆量：只建出 %d 顆，應有 %d 顆" % [btns.size(), OVERFLOW_N + 1])
		return false
	_overflow_last = btns[btns.size() - 1]

	## 用主場景那顆 viewport 的實際大小。headless 下 root.size 不等於畫面大小
	## （量到 64），拿它當螢幕高會把這條檢查變成亂報。
	var vp: Vector2 = (_main as Node).get_viewport_rect().size
	if vp.y < 100.0:
		_fail("量到的畫面高只有 %.0f，這條檢查沒有意義" % vp.y)
		return false

	## 卡片不可以高過螢幕 —— 高過就代表按鈕列沒有被限高，
	## 置中之後上下都會被切掉，玩家連捲都沒得捲。
	var card_h := 0.0
	for n in nodes:
		if n is PanelContainer:
			card_h = maxf(card_h, (n as PanelContainer).size.y)
	if card_h > vp.y:
		_fail("按鈕爆量：卡片高 %.0f 超過螢幕 %.0f，按鈕會被切掉" % [card_h, vp.y])
		return false
	print("  ok 按鈕爆量 %d 顆：卡片高 %.0f ≤ 螢幕 %.0f" % [btns.size(), card_h, vp.y])
	return true


func _check_overflow_reachable() -> void:
	if _overflow_last == null or not is_instance_valid(_overflow_last):
		_fail("按鈕爆量：捲動後找不到最後一顆按鈕")
		return
	var vp: Vector2 = (_main as Node).get_viewport_rect().size
	var r := _overflow_last.get_global_rect()
	if r.position.y < 0.0 or r.end.y > vp.y:
		_fail("按鈕爆量：捲到底之後，最後一顆「%s」仍在 y=%.0f~%.0f，出畫面 0~%.0f" % [
			_overflow_last.text, r.position.y, r.end.y, vp.y
		])
		return
	print("  ok 捲到底之後最後一顆「%s」在畫面內（y=%.0f~%.0f）" % [
		_overflow_last.text, r.position.y, r.end.y
	])


func _collect_nodes(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_collect_nodes(c, out)


func _check_panel(p: Dictionary) -> void:
	var want_title := str(p["title"])
	## 用 main.gd 的 host 屬性，不要用 %ScreenHost —— unique name 在場景外解析不到。
	## 也刻意不靠節點名字找面板：_panel() 裡設的 "MenuLayer" 實際不會生效，
	## 節點是自動命名的（@Control@N）。直接搜整棵子樹的 Label／Button 反而穩。
	var host: Node = _main.get("host")
	if host == null:
		_fail("找不到 ScreenHost")
		return
	if host.get_child_count() == 0:
		_fail("%s：呼叫入口後 host 底下沒有任何節點" % want_title)
		return
	var labels: Array = []
	var buttons: Array = []
	_collect(host, labels, buttons)
	if not labels.has(want_title):
		_fail("%s：面板標題不符，實際有 %s" % [want_title, str(labels)])
		return
	if buttons.size() < int(p["min_buttons"]):
		_fail("%s：按鈕只有 %d 顆，至少要 %d" % [want_title, buttons.size(), int(p["min_buttons"])])
		return
	for want in p.get("expect_buttons", []):
		var hit := false
		for b in buttons:
			if str(b).find(str(want)) >= 0:
				hit = true
				break
		if not hit:
			_fail("%s：找不到按鈕「%s」，實際有 %s" % [want_title, str(want), str(buttons)])
			return
	print("  ok panel %s（按鈕 %d 顆）" % [want_title, buttons.size()])


## ui_goto 宣告認得的每個去處都要真的接得到；同時確認未知去處會回 false
## （避免哪天 match 被改成 catch-all，測試就變成空的了）。
func _check_goto_targets() -> void:
	var targets = _main.get("UI_GOTO_TARGETS")
	if targets == null or (targets as Array).is_empty():
		_fail("main.gd 沒有 UI_GOTO_TARGETS")
		return
	for t in targets:
		if not bool(_main.call("ui_goto", str(t))):
			_fail("ui_goto('%s') 接不到" % str(t))
			return
	if bool(_main.call("ui_goto", "__不存在的去處__")):
		_fail("ui_goto 對未知去處回了 true，等於沒在檢查")
		return
	print("  ok ui_goto 去處 %d 個全部接得到" % (targets as Array).size())


func _collect(n: Node, labels: Array, buttons: Array) -> void:
	if n is Label:
		labels.append((n as Label).text)
	elif n is Button:
		buttons.append((n as Button).text)
	for c in n.get_children():
		_collect(c, labels, buttons)


func _finish() -> bool:
	if _ok:
		print("PANELS_OK")
		quit(0)
	else:
		print("PANELS_FAIL")
		quit(1)
	return true
