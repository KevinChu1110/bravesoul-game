extends SceneTree
## 體驗回報測試：godot --headless -s res://scripts/autoload/test_telemetry.gd
##
## 這支測試不連網路。它守的是四件「壞掉了也不會有人發現」的事：
##
##   1. 預設關閉 —— 沒同意就一筆都不該收。這是承諾，不是設定值。
##   2. 自由文字進不來 —— 玩家名字、路徑、句子在型別上就該被擋掉，
##      不能靠呼叫端自律。
##   3. 事件名跟伺服器同一份 —— 客戶端多送一種伺服器不認得的，
##      玩家的頻寬就白花了，而且沒人會發現。
##   4. 壞掉不影響遊戲 —— 沒設定後端、連線關掉、連續送失敗，
##      都只能安靜地什麼都不做。
##
## 第 1、2 點原本是假的，變異測試抓出來的：
##   * 「預設關閉」原本只驗「把 consent 設成 false 之後不收」，
##     所以有人把宣告改成 `var consent := true` 照樣全綠。現在改成從一顆
##     全新的實例上驗（_check_default_is_off）。
##   * 「不收個資」原本只驗幾個寫死的壞欄位進不來，
##     所以偷偷在白名單加一個 nickname 照樣全綠。現在把整組欄位釘死
##     並跟伺服器對表（_check_prop_allowlist）。

## 可以送出的欄位，就這些。這張表是「不收個資」的實作，不是說明文件：
## 多一個欄位就多一條認得出人的路，所以要加欄位得先過來改這裡，
## 順手回答一次「這個欄位單獨看、或跟別的欄位湊起來，認不認得出某個人」。
const EXPECT_PROPS: Array[String] = [
	"boss", "chapter", "dur", "level", "mode", "ng", "place", "sec", "step", "won",
]

var _ok := true
var _saved_config: String = ""
var _had_config := false


func _fail(msg: String) -> void:
	push_error(msg)
	print("  FAIL ", msg)
	_ok = false


func _initialize() -> void:
	var tel := root.get_node_or_null("Telemetry")
	var gate := root.get_node_or_null("OnlineGate")
	if tel == null:
		_fail("Telemetry autoload missing")
		_finish()
		return
	if gate == null:
		_fail("OnlineGate autoload missing")
		_finish()
		return

	_backup_config(tel)

	## 假裝後端設定好了，但整場測試都不會真的送：
	## -s 模式下 _ready 還沒跑，HTTPRequest 是 null，flush 一定原地返回。
	var was_offline: bool = gate.offline_only
	var was_url: String = gate.supabase_url
	var was_key: String = gate.supabase_anon_key
	gate.offline_only = false
	gate.supabase_url = "https://telemetry.test.invalid"
	gate.supabase_anon_key = "test-key"

	_check_default_is_off(tel)
	_check_default_off(tel)
	_check_offline_safe(tel, gate)
	_check_prop_allowlist(tel)
	_check_prop_cleaning(tel)
	_check_event_names(tel)
	_check_queue_cap(tel)
	_check_battle(tel)
	_check_withdraw(tel)
	_check_give_up(tel)
	_check_player_text(tel)

	gate.offline_only = was_offline
	gate.supabase_url = was_url
	gate.supabase_anon_key = was_key
	_restore_config(tel)
	_finish()


## ── 各項 ──

## 「預設關閉」是承諾，要從沒有人碰過的狀態驗起。
##
## 下面那條 _check_default_off 自己先把 consent 設成 false，
## 所以它證得了「關掉之後不收」，證不了「一開始是關的」——
## 有人把宣告改成 true、或把設定檔的預設值改成 true，它都不會紅。
func _check_default_is_off(tel: Node) -> void:
	var script: GDScript = tel.get_script()
	var path := str(script.get_script_constant_map().get("CONFIG_PATH", ""))
	if path == "":
		_fail("找不到設定檔路徑，驗不了預設值")
		return

	## 一、剛 new 出來（_ready 都還沒跑）就該是關的
	var fresh: Node = script.new()
	var default_consent := bool(fresh.consent)
	fresh.free()
	if default_consent:
		_fail("consent 的預設值是開啟 —— 沒有人同意就會開始收")
		return

	## 二、設定檔沒寫同意與否（舊版留下的、手改壞的）也要當成沒同意
	_write_config(path, '{"install_id": "11111111-1111-1111-1111-111111111111"}')
	var quiet: Node = script.new()
	quiet.load_config()
	var quiet_consent := bool(quiet.consent)
	quiet.free()
	if quiet_consent:
		_fail("設定檔沒寫同意與否，卻被當成已經同意")
		return

	## 三、反過來也要成立。少了這條，上面兩條可能只是因為
	##     load_config 根本沒在讀檔，那就變成兩條假的檢查。
	_write_config(path, '{"consent": true, "install_id": "11111111-1111-1111-1111-111111111111"}')
	var yes: Node = script.new()
	yes.load_config()
	var yes_consent := bool(yes.consent)
	yes.free()
	if not yes_consent:
		_fail("設定檔寫了同意卻沒讀進來 —— 上面兩條檢查等於沒測到東西")
		return
	print("  ok 預設關閉：全新實例、沒寫同意與否的設定檔，都是關的")


## 白名單是一張封閉的表：整組欄位要跟登記在案的一模一樣，
## 而且要跟伺服器認得的一模一樣。
##
## 為什麼不是「檢查幾個壞欄位進不來」就好：那種寫法只擋得住想像得到的壞欄位。
## 真正的風險是有人為了查一個問題，順手在白名單加一個看起來人畜無害的欄位
## （nickname、uid、seed……），加完沒有任何測試會紅。
func _check_prop_allowlist(tel: Node) -> void:
	var consts: Dictionary = tel.get_script().get_script_constant_map()
	var got: Array[String] = []
	for k in (consts.get("PROP_INT", {}) as Dictionary).keys():
		got.append(str(k))
	for k2 in (consts.get("PROP_STR", {}) as Dictionary).keys():
		got.append(str(k2))
	for k3 in (consts.get("PROP_BOOL", []) as Array):
		got.append(str(k3))
	got.sort()
	var want := EXPECT_PROPS.duplicate()
	want.sort()
	if got != want:
		_fail("可送出的欄位變了：實際 %s／登記在案 %s\n"
			% [str(got), str(want)]
			+ "    要加欄位，先確認它單獨或跟別的欄位湊起來認不出人，再來改 EXPECT_PROPS")
		return

	## 伺服器那邊的白名單要一模一樣。
	## 客戶端多送＝白花玩家的頻寬；伺服器多收＝有人把收集範圍偷偷放寬了。
	var sql := _read_sql("telemetry.sql")
	if sql == "":
		_fail("讀不到 supabase/telemetry.sql")
		return
	var at := sql.find("where k in (")
	if at < 0:
		_fail("telemetry.sql 裡找不到欄位白名單（where k in ...）")
		return
	var chunk := sql.substr(at, sql.find(")", at) - at)
	var server: Array[String] = []
	var re := RegEx.create_from_string("'([a-z_]+)'")
	for m in re.search_all(chunk):
		server.append(m.get_string(1))
	server.sort()
	if server != want:
		_fail("伺服器收的欄位跟客戶端不一致：伺服器 %s／客戶端 %s" % [str(server), str(want)])
		return
	print("  ok 可送出的欄位是一張封閉的表（%d 個），兩邊一致" % want.size())


## 沒有人按下同意之前，佇列必須是空的
func _check_default_off(tel: Node) -> void:
	tel.consent = false
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0
	tel.track("session_start", {"chapter": "c1"})
	tel.track("battle_end", {"mode": "leo", "won": false})
	tel.note_tutorial("boot")
	tel.battle_finished("leo", false)
	if not tel._queue.is_empty():
		_fail("沒有同意就收了 %d 筆" % tel._queue.size())
		return
	if tel.is_active():
		_fail("沒有同意卻回報自己是開著的")
		return
	print("  ok 預設關閉：沒同意時一筆都不收")


## 玩家把連線關掉＝不想跟伺服器講話，就算同意過也不該送
func _check_offline_safe(tel: Node, gate: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0

	gate.offline_only = true
	tel.track("session_tick", {"sec": 10})
	if not tel._queue.is_empty():
		gate.offline_only = false
		_fail("純單機下仍然收了 %d 筆" % tel._queue.size())
		return
	gate.offline_only = false

	## 後端沒設定也一樣
	var url: String = gate.supabase_url
	gate.supabase_url = ""
	tel.track("session_tick", {"sec": 10})
	var n: int = tel._queue.size()
	gate.supabase_url = url
	if n != 0:
		_fail("未設定後端時仍然收了 %d 筆" % n)
		return

	## flush 在任何情況下都不能爆
	tel.flush()
	tel._on_tick()
	print("  ok 連線關掉／未設定後端時不收也不送，且呼叫得動")


## 白名單外的欄位、非 token 的字串一律進不來
func _check_prop_cleaning(tel: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0
	tel.track("battle_end", {
		"mode": "demon",
		"won": true,
		"level": 9999,              ## 超出上限要被夾
		"dur": -5,                  ## 負值要被夾
		"place": "C:/Users/kevin",  ## 白名單內但不是 token
		"step": "玩家自己打的一句話",
		"display_name": "小白",     ## 白名單外
		"email": "a@b.c",           ## 白名單外
	})
	if tel._queue.size() != 1:
		_fail("同意後應收 1 筆，實際 %d" % tel._queue.size())
		return
	var p: Dictionary = tel._queue[0].get("p", {})
	for bad in ["display_name", "email", "place", "step"]:
		if p.has(bad):
			_fail("欄位『%s』不該留下，實際值 %s" % [bad, str(p[bad])])
			return
	if str(p.get("mode", "")) != "demon" or bool(p.get("won", false)) != true:
		_fail("該留的欄位被洗掉了：%s" % str(p))
		return
	if int(p.get("level", -1)) != 999 or int(p.get("dur", -1)) != 0:
		_fail("數值沒有夾在範圍內：%s" % str(p))
		return
	## 整包序列化之後不該出現任何中文或可識別字串
	var raw := JSON.stringify(tel._queue)
	for leak in ["小白", "kevin", "a@b.c", "玩家自己"]:
		if leak in raw:
			_fail("送出內容含有『%s』：%s" % [leak, raw])
			return
	print("  ok 自由文字與白名單外欄位全被洗掉，數值夾在範圍內")


## 客戶端跟 supabase/telemetry.sql 必須認得同一組事件名
func _check_event_names(tel: Node) -> void:
	var consts: Dictionary = tel.get_script().get_script_constant_map()
	var names: Array = consts.get("EVENTS", [])
	if names.is_empty():
		_fail("客戶端沒有事件名白名單")
		return

	var sql := _read_sql("telemetry.sql")
	if sql == "":
		_fail("讀不到 supabase/telemetry.sql")
		return
	## allowed_names 的預設值那一段
	var start := sql.find("array[", sql.find("allowed_names"))
	var stop := sql.find("]", start)
	if start < 0 or stop < 0:
		_fail("telemetry.sql 裡找不到 allowed_names 預設值")
		return
	var chunk := sql.substr(start, stop - start)
	for n in names:
		if not ("'%s'" % str(n)) in chunk:
			_fail("客戶端會送『%s』，但伺服器白名單沒有它" % str(n))
			return
	## 反過來也要對：伺服器認得的事件，客戶端沒在送就是設計走鐘了
	var re := RegEx.create_from_string("'([a-z_]+)'")
	for m in re.search_all(chunk):
		var sn := m.get_string(1)
		if not names.has(sn):
			_fail("伺服器認得『%s』，但客戶端從來不送" % sn)
			return
	print("  ok 事件名白名單兩邊一致（%d 種）" % names.size())


## 佇列不能無限長：送不出去的時候記憶體必須有上界
func _check_queue_cap(tel: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0
	var consts: Dictionary = tel.get_script().get_script_constant_map()
	var cap: int = int(consts.get("QUEUE_MAX", 200))
	for i in cap * 2:
		tel.track("session_tick", {"sec": i})
	if tel._queue.size() > cap:
		_fail("灌 %d 筆之後佇列長到 %d，超過上限 %d" % [cap * 2, tel._queue.size(), cap])
		return
	## 單場總量閘門
	var limit: int = int(consts.get("SESSION_EVENT_MAX", 400))
	tel._sent_this_session = limit
	var before: int = tel._queue.size()
	tel.track("session_tick", {"sec": 1})
	if tel._queue.size() != before:
		_fail("單場總量已達 %d，還收得進去" % limit)
		return
	print("  ok 佇列上限 %d 與單場總量閘門 %d 都生效" % [cap, limit])


## Boss 判定與觀戰排除
func _check_battle(tel: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0

	tel.battle_started("leo")
	tel.battle_finished("leo", false)
	if tel._queue.size() != 1 or not bool(tel._queue[0]["p"].get("boss", false)):
		_fail("雷歐應該被認成 Boss：%s" % str(tel._queue))
		return

	tel._queue.clear()
	tel.battle_finished("ash_rat", true)
	if tel._queue.size() != 1 or bool(tel._queue[0]["p"].get("boss", true)):
		_fail("灰燼鼠不該被認成 Boss：%s" % str(tel._queue))
		return

	tel._queue.clear()
	tel.battle_finished("spectate:leo", true)
	if not tel._queue.is_empty():
		_fail("觀戰不該被算成自己的戰績：%s" % str(tel._queue))
		return
	print("  ok Boss 判定正確，觀戰不列入戰績")


## 關掉的時候連還沒送的都要倒掉——「我不要了」不是「從下一筆開始」
func _check_withdraw(tel: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0
	tel.track("session_tick", {"sec": 1})
	tel.track("session_tick", {"sec": 2})
	if tel._queue.size() != 2:
		_fail("撤回前應有 2 筆，實際 %d" % tel._queue.size())
		return
	tel.set_consent(false)
	if not tel._queue.is_empty():
		_fail("撤回同意後還留著 %d 筆沒送的" % tel._queue.size())
		return
	tel.track("session_tick", {"sec": 3})
	if not tel._queue.is_empty():
		_fail("撤回同意後還在收")
		return
	print("  ok 撤回同意後立刻停收，且把沒送的倒掉")


## 伺服器出事的時候要閉嘴，不是抱著佇列等
func _check_give_up(tel: Node) -> void:
	tel.consent = true
	tel._muted = false
	tel._queue.clear()
	tel._sent_this_session = 0
	var consts: Dictionary = tel.get_script().get_script_constant_map()
	var limit: int = int(consts.get("FAIL_GIVE_UP", 5))
	tel.track("session_tick", {"sec": 1})
	for i in limit:
		tel._after_fail()
	if not tel._queue.is_empty():
		_fail("連續失敗 %d 次後佇列沒清空" % limit)
		return
	if tel.is_active():
		_fail("連續失敗 %d 次後還在收" % limit)
		return
	tel.track("session_tick", {"sec": 2})
	if not tel._queue.is_empty():
		_fail("閉嘴之後還收得進去")
		return
	print("  ok 連續失敗 %d 次後整場閉嘴並倒掉佇列" % limit)


## 同意畫面是玩家會讀的東西，不能出現我們自己的用語
func _check_player_text(tel: Node) -> void:
	var text: String = tel.consent_prompt_bbcode() + "\n" + tel.status_line()
	if text.strip_edges() == "":
		_fail("同意說明是空的")
		return
	## 事件名、識別碼、實作字眼都不該讓玩家讀到
	var leaks: Array[String] = [
		"session_start", "battle_end", "install_id", "uuid", "RPC", "HTTP",
		"jsonb", "supabase", "遙測", "事件", "欄位", "白名單", "佇列", "上傳",
	]
	for w in leaks:
		if w in text:
			_fail("同意說明出現實作用語『%s』" % w)
			return
	## 講不講得出「送什麼、不送什麼、關掉會怎樣」
	for must in ["不會送出", "隨時可以關"]:
		if not must in text:
			_fail("同意說明沒有交代『%s』" % must)
			return
	print("  ok 同意說明講清楚了，也沒有實作用語外洩")


## ── 收尾 ──

func _read_sql(fname: String) -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("../supabase/").path_join(fname)
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _write_config(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _backup_config(tel: Node) -> void:
	var path: String = str(tel.get_script().get_script_constant_map().get("CONFIG_PATH", ""))
	if path == "" or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_saved_config = f.get_as_text()
	_had_config = true


## 測試會動到 user://telemetry.json，跑完要還給開發者原本的選擇。
## 本來就沒有這個檔的機器要還原成沒有，不然跑一次測試就等於幫人做了決定。
func _restore_config(tel: Node) -> void:
	var path: String = str(tel.get_script().get_script_constant_map().get("CONFIG_PATH", ""))
	if path == "":
		return
	if not _had_config:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	_write_config(path, _saved_config)


func _finish() -> void:
	if _ok:
		print("TELEMETRY_OK")
		quit(0)
	else:
		print("TELEMETRY_FAIL")
		quit(1)
