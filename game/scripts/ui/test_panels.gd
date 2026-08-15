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
## 注意 expect_buttons 為什麼必要：市集的 open() 先同步畫一次，接著 refresh_online()
## 的回呼又會重畫一次。只驗「標題 + 按鈕數」的話，就算把同步那次拿掉，非同步重畫
## 也會把測試補成綠燈 —— 實測過，那種破壞抓不到。驗到具體按鈕才擋得住。
const PANELS: Array = [
	{
		"entry": "_go_market_panel",
		"title": "星途市集",
		"min_buttons": 3,
		"expect_buttons": ["我要上架", "返回"],
	},
	## 未連線時的裂縫房：走 online_ready()==false 那條分支
	{
		"entry": "_go_room_panel",
		"title": "裂縫房",
		"min_buttons": 3,
		"expect_buttons": ["連線設定", "星途助戰", "返回"],
	},
	## 帶輸入框的加入代碼窗（自己畫，不走 ui_panel）
	{
		"entry": "_go_room_join_code_panel",
		"title": "用代碼加入房間",
		"min_buttons": 2,
		"expect_buttons": ["加入", "返回"],
	},
]

## main.gd 必須提供給 scripts/ui/panels/* 的公開契約
const HOST_API: Array = [
	"ui_panel", "ui_toast", "ui_goto",
	"ui_host", "ui_clear_host", "ui_reset_fade",
	"ui_room_spectate", "ui_room_host_start",
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
				return _finish()
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
	return false


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
