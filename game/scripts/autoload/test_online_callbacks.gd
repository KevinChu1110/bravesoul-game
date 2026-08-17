extends SceneTree
## 連線回呼簽名的把關測試：
##   godot --headless -s res://scripts/autoload/test_online_callbacks.gd
##
## 守一件事：**`_cb_*` 的參數順序要跟 `bind()` 實際傳進來的一致。**
##
## 送出時寫的是 `_cb_xxx.bind(cb)`。Godot 的 `Callable.bind()` 是把綁定的參數接在
## **呼叫端參數的後面**，而 HTTP 回來時呼叫的是 `cb.call(ok, body)` ——
## 所以真正的簽名是 `(ok, body, cb)`。
##
## 十支回呼原本全部宣告成 `(cb, ok, body)`，第一個參數就型別不符。
## Godot 只噴一行 "Invalid type in function" 就把整個回呼丟掉：
## 遊戲不會當、測試不會紅（離線路徑根本走不到 _cb_*），
## 但連線面板每一顆按鈕都毫無反應 —— 不是「連不上會失敗」，
## 是連失敗都通知不到玩家，狀態列永遠停在「尚未檢測」。
##
## 這支直接對真實簽名下斷言，不靠跑網路。

const SRC := "res://scripts/autoload/online_gate.gd"

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		_fail("讀不到 %s" % SRC)
		return _finish()
	var src := f.get_as_text()

	## 1) 每一支 _cb_* 的宣告：cb 不可以在第一個
	var re := RegEx.create_from_string("func (_cb_[a-z_]+)\\(([^)]*)\\)")
	var checked := 0
	var bad: PackedStringArray = []
	for m in re.search_all(src):
		var name := m.get_string(1)
		var args := m.get_string(2)
		if args.find("cb: Callable") < 0:
			continue        ## 沒收 cb 的回呼不在守備範圍
		checked += 1
		var parts := args.split(",")
		var first := parts[0].strip_edges()
		if first.begins_with("cb"):
			bad.append(name)
	if checked == 0:
		_fail("一支收 cb 的 _cb_* 都沒找到 —— 這條檢查等於沒在檢查")
		return _finish()
	if bad.size() > 0:
		_fail("這些回呼把 cb 宣告在第一個，bind() 會把它接在最後 → 回呼永遠不執行：%s" % ", ".join(bad))
		return _finish()
	print("  ok %d 支 _cb_* 的 cb 都不在第一個參數" % checked)

	## 2) 送出端確實是用 bind(cb) 綁的（不然上面那條的前提就不成立）
	var bind_n := src.count(".bind(cb)")
	if bind_n < checked:
		_fail("只有 %d 處 .bind(cb)，但有 %d 支收 cb 的回呼 —— 兩邊對不上" % [bind_n, checked])
		return _finish()
	print("  ok 送出端 %d 處 .bind(cb) 跟回呼數量相符" % bind_n)

	## 3) 實際呼叫一次：離線時 health_check 會走 _fail 直接回呼，
	##    這裡確認回呼真的拿得到結果（不是被 Godot 丟掉）
	var gate := root.get_node_or_null("OnlineGate")
	if gate == null:
		_fail("OnlineGate autoload missing")
		return _finish()
	var got: Array = []
	gate.offline_only = true
	gate.health_check(func(res: Dictionary) -> void:
		got.append(res)
	)
	if got.is_empty():
		_fail("純單機下 health_check 沒有回呼 —— 玩家點了會完全沒反應")
		return _finish()
	print("  ok health_check 的回呼確實被呼叫到")
	_finish()


func _finish() -> void:
	if _ok:
		print("ONLINE_CB_OK")
		quit(0)
	else:
		print("ONLINE_CB_FAIL")
		quit(1)
