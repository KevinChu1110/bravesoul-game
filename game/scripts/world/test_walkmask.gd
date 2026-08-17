extends SceneTree
## 可走區遮罩的把關測試：godot --headless -s res://scripts/world/test_walkmask.gd
##
## 守的是「遮罩靜靜失效」這種爛法：JSON 打錯、多邊形少一點、art key 拼錯，
## 都不會噴錯 —— WalkMask.has() 回 false，explore_view 就默默退回舊的百分比方塊，
## 畫面看起來一樣，只是兔子照樣走上城牆。測試全綠、問題還在。
##
## 座標對不對（NPC 站不站得到）由 tools/check_walkmask.py 顧，那支能讀 map_catalog。
## 這支只顧「機制有沒有真的在運作」。

const WalkMask := preload("res://scripts/world/walk_mask.gd")

var _ok := true


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	WalkMask.reload()
	var arts := WalkMask.arts()
	if arts.is_empty():
		_fail("walkmask.json 一個 art 都沒載到 —— 檔案不見了、JSON 壞了，或 key 全被底線開頭吃掉")
		return _finish()
	print("  ok 載到 %d 個 art：%s" % [arts.size(), ", ".join(arts)])

	## 每個啟用的 art 都要真的有作用：全部可走 = 等於沒設
	for art in arts:
		if not WalkMask.has(art):
			_fail("%s 在表裡卻沒有可走多邊形" % art)
			continue
		var inside := 0
		var total := 0
		for gy in 24:
			for gx in 40:
				var uv := Vector2((gx + 0.5) / 40.0, (gy + 0.5) / 24.0)
				total += 1
				if WalkMask.walkable(art, uv):
					inside += 1
		var frac := float(inside) / float(total)
		if frac >= 0.98:
			_fail("%s 幾乎整張都可走（%.0f%%）—— 多邊形大概畫錯了，等於沒擋" % [art, frac * 100.0])
		elif frac <= 0.03:
			_fail("%s 幾乎整張都不可走（%.0f%%）—— 玩家會卡死" % [art, frac * 100.0])
	if _ok:
		print("  ok 每個 art 的可走比例都在合理範圍")

	## 沒列進表的 art 一定要回 false，否則呼叫端不會退回舊行為
	if WalkMask.has("__not_a_real_art__"):
		_fail("沒列進表的 art 竟然回報有遮罩 —— 那會把整張圖擋成不可走")

	## 底線開頭的 key 是說明與停用的範例，不可以被吃進來
	for art in arts:
		if art.begins_with("_"):
			_fail("底線開頭的 key %s 被載進來了 —— 那是說明文字或停用的範例" % art)

	_finish()


func _finish() -> void:
	if _ok:
		print("WALKMASK_OK")
		quit(0)
	else:
		print("WALKMASK_FAIL")
		quit(1)
