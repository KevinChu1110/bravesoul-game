extends SceneTree
## 連線閘門把關測試：godot --headless -s res://scripts/autoload/test_online_gate.gd
##
## 這支測試不連網路。它守的是三件在改「經濟搬上伺服器」時最容易破的事：
##
##   1. 純單機仍然安全 —— 沒設定後端時，每一支經濟 API 都要能安全呼叫且回失敗，
##      不能噴錯、不能卡住。單機是主要玩法，連線壞掉不該波及它。
##   2. 伺服器錯誤不外洩 —— RPC 回的是 not enough gold 這種英文技術碼，
##      玩家面必須全部翻成中文。這裡窮舉伺服器會吐的每一種錯。
##   3. RPC 參數解析正確 —— 掛單 id 從字串轉成 bigint，轉錯就整個市集打不動。

## 伺服器（supabase/economy.sql）會回的每一種 error 字串。
## 新增伺服器錯誤碼時要一起加進來，否則玩家會看到英文。
const SERVER_ERRORS: Array[String] = [
	"not signed in",
	"bad payload",
	"payload too large",
	"item not tradeable",
	"bad qty",
	"price out of range",
	"market blocked",
	"too many listings",
	"daily listing limit",
	"not enough items",
	"not enough gold",
	"listing gone",
	"cannot buy own",
	"room gone",
	"no win yet",
	"not a member",
	"already claimed",
	"not host",
	"already settled",
	"bad result",
	"bad board",
	"score out of range",
	"reward_claimed is server-managed",
	"message rate limit",
]

## 翻完之後不該還留著的字。ASCII 技術詞漏到玩家面就是 bug。
const LEAK_WORDS: Array[String] = [
	"gold", "item", "listing", "room", "board", "payload",
	"claimed", "host", "member", "qty", "score", "rate limit",
]

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var gate := root.get_node_or_null("OnlineGate")
	if gate == null:
		_fail("OnlineGate autoload missing")
		_finish()
		return

	_check_offline_safe(gate)
	_check_error_translation(gate)
	_check_listing_id(gate)
	_check_rpc_row(gate)
	_finish()


## 純單機下每支經濟 API 都要回失敗而不是爆掉
func _check_offline_safe(gate: Node) -> void:
	var was_offline: bool = gate.offline_only
	gate.offline_only = true

	var results: Array = []
	var collect := func(res: Dictionary) -> void:
		results.append(res)

	gate.push_cloud_save(collect)
	gate.market_create_listing("hunt_hide", 1, 10, collect)
	gate.market_cancel_listing("1", collect)
	gate.market_buy("1", collect)
	gate.room_claim_reward("00000000-0000-0000-0000-000000000000", collect)
	gate.room_report_result("00000000-0000-0000-0000-000000000000", "win", collect)
	gate.leaderboard_submit("rift_weekly", 100, collect)

	if results.size() != 7:
		gate.offline_only = was_offline
		_fail("純單機下 7 支寫入 API 只回了 %d 個結果（有 API 沒有回呼）" % results.size())
		return
	for r in results:
		if bool(r.get("ok", false)):
			gate.offline_only = was_offline
			_fail("純單機下寫入不該回成功：%s" % str(r))
			return

	## 讀取型的餘額查詢照其他 fetch_* 的慣例回空值，不算失敗；
	## 但餘額一定要是 0，不能把上一次連線留下的數字帶進單機。
	## lambda 捕捉區域變數是傳值，得用容器接回來
	var ledger: Array = []
	gate.fetch_ledger(func(res: Dictionary) -> void:
		ledger.append(res)
	)
	gate.offline_only = was_offline

	if ledger.is_empty() or int(ledger[0].get("gold", -1)) != 0:
		_fail("純單機下餘額查詢應回 0，實際 %s" % str(ledger))
		return
	print("  ok 純單機下 7 支寫入 API 安全回失敗，餘額查詢回 0")


## 伺服器錯誤碼一律翻成中文，且不留英文技術詞
func _check_error_translation(gate: Node) -> void:
	for code in SERVER_ERRORS:
		var out: String = gate.humanize_error(code)
		if out == "" or out == code:
			_fail("伺服器錯誤『%s』沒有翻譯" % code)
			return
		var low := out.to_lower()
		for w in LEAK_WORDS:
			if w in low:
				_fail("『%s』翻成『%s』，還留著技術字『%s』" % [code, out, w])
				return
	print("  ok %d 種伺服器錯誤都翻成中文且無技術字外洩" % SERVER_ERRORS.size())


## 掛單 id 在客戶端是字串，送進 RPC 必須是整數
func _check_listing_id(gate: Node) -> void:
	var cases := {
		"42": 42,
		"0": 0,
		"1234567890": 1234567890,
	}
	for raw in cases:
		var got: Variant = gate._as_listing_id(str(raw))
		if typeof(got) != TYPE_INT or int(got) != int(cases[raw]):
			_fail("掛單 id『%s』轉成 %s，期望整數 %d" % [str(raw), str(got), int(cases[raw])])
			return
	## 非數字要原樣留著讓伺服器去拒絕，不能靜靜變成 0
	var bad: Variant = gate._as_listing_id("npc_123_hunt_hide")
	if typeof(bad) != TYPE_STRING:
		_fail("非數字掛單 id 不該被轉成 %s" % str(bad))
		return
	print("  ok 掛單 id 轉型正確（數字轉整數、非數字原樣留下）")


## PostgREST 有時把 RPC 結果包成陣列，兩種都要吃得下
func _check_rpc_row(gate: Node) -> void:
	var direct: Dictionary = gate._rpc_row({"ok": true, "gold": 5})
	if int(direct.get("gold", 0)) != 5:
		_fail("_rpc_row 讀不到物件形式的結果")
		return
	var wrapped: Dictionary = gate._rpc_row([{"ok": true, "gold": 7}])
	if int(wrapped.get("gold", 0)) != 7:
		_fail("_rpc_row 讀不到陣列包一層的結果")
		return
	if not gate._rpc_row("").is_empty() or not gate._rpc_row([]).is_empty():
		_fail("_rpc_row 對空回應該給空字典")
		return
	print("  ok RPC 結果解析涵蓋物件／陣列／空回應")


func _finish() -> void:
	if _ok:
		print("ONLINE_GATE_OK")
		quit(0)
	else:
		print("ONLINE_GATE_FAIL")
		quit(1)
