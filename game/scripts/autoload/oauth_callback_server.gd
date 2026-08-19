extends RefCounted
## 本機 OAuth callback：瀏覽器把 #access_token 轉成 query 給 Godot 讀。
## 用法：listen → OS.shell_open(authorize) → poll → take_result

signal completed(ok: bool, payload: Dictionary)

const PORT := 8765
const HOST := "127.0.0.1"

var _server: TCPServer = null
var _peers: Array = []  ## {peer: StreamPeerTCP, buf: String}
var _done: bool = false
var _result: Dictionary = {}
var _listening: bool = false


func redirect_uri() -> String:
	return "http://%s:%d/callback" % [HOST, PORT]


func is_listening() -> bool:
	return _listening and _server != null and _server.is_listening()


func listen() -> Error:
	stop()
	_done = false
	_result = {}
	_peers.clear()
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	_listening = err == OK
	return err


func stop() -> void:
	for p in _peers:
		var peer: StreamPeerTCP = p.get("peer")
		if peer:
			peer.disconnect_from_host()
	_peers.clear()
	if _server:
		_server.stop()
	_server = null
	_listening = false


func take_result() -> Dictionary:
	return _result.duplicate()


func is_done() -> bool:
	return _done


## 每幀呼叫（從 OnlineGate._process）
func poll() -> void:
	if _server == null or not _server.is_listening() or _done:
		return
	if _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_peers.append({"peer": peer, "buf": ""})
	var i := 0
	while i < _peers.size():
		var entry: Dictionary = _peers[i]
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED:
			_peers.remove_at(i)
			continue
		var avail := peer.get_available_bytes()
		if avail > 0:
			entry["buf"] = str(entry["buf"]) + peer.get_utf8_string(avail)
			_peers[i] = entry
			var buf: String = entry["buf"]
			if buf.find("\r\n\r\n") >= 0 or buf.find("\n\n") >= 0:
				_handle_http(peer, buf)
				_peers.remove_at(i)
				continue
		i += 1


func _handle_http(peer: StreamPeerTCP, raw: String) -> void:
	var first := raw.split("\n")[0].strip_edges()
	var path := "/"
	var parts := first.split(" ")
	if parts.size() >= 2:
		path = parts[1]
	## /callback → 回傳把 hash 轉 query 的頁
	if path.begins_with("/callback"):
		_send(peer, 200, "text/html; charset=utf-8", _callback_html())
		return
	## /ok?access_token=...&refresh_token=...
	if path.begins_with("/ok"):
		var q := {}
		var qi := path.find("?")
		if qi >= 0:
			q = _parse_query(path.substr(qi + 1))
		var at := str(q.get("access_token", ""))
		var rt := str(q.get("refresh_token", ""))
		if at != "":
			_done = true
			_result = {"ok": true, "access_token": at, "refresh_token": rt}
			_send(peer, 200, "text/html; charset=utf-8", _success_html())
			completed.emit(true, _result)
		else:
			_done = true
			_result = {"ok": false, "msg": "missing token"}
			_send(peer, 400, "text/html; charset=utf-8", _fail_html("missing token"))
			completed.emit(false, _result)
		return
	## /fail
	if path.begins_with("/fail"):
		_done = true
		_result = {"ok": false, "msg": "oauth denied"}
		_send(peer, 200, "text/html; charset=utf-8", _fail_html("denied"))
		completed.emit(false, _result)
		return
	_send(peer, 404, "text/plain", "not found")


func _parse_query(qs: String) -> Dictionary:
	var out := {}
	for pair in qs.split("&"):
		if pair == "":
			continue
		var kv := pair.split("=", true, 1)
		var k := kv[0].uri_decode() if kv.size() > 0 else ""
		var v := kv[1].uri_decode() if kv.size() > 1 else ""
		out[k] = v
	return out


func _send(peer: StreamPeerTCP, code: int, ctype: String, body: String) -> void:
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d OK\r\n" % code
	if code == 400:
		head = "HTTP/1.1 400 Bad Request\r\n"
	elif code == 404:
		head = "HTTP/1.1 404 Not Found\r\n"
	head += "Content-Type: %s\r\n" % ctype
	head += "Content-Length: %d\r\n" % bytes.size()
	head += "Connection: close\r\n\r\n"
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(bytes)


func _callback_html() -> String:
	return """<!DOCTYPE html><html><head><meta charset="utf-8"><title>勇者之魂 · 登入</title></head>
<body style="font-family:sans-serif;background:#1a1520;color:#eee;padding:2rem">
<h1>正在完成登入…</h1>
<p id="m">請稍候，不要關這個視窗。</p>
<script>
(function(){
  var h = new URLSearchParams(location.hash.slice(1));
  var q = new URLSearchParams(location.search);
  var err = h.get('error_description') || h.get('error') || q.get('error_description') || q.get('error');
  if (err) {
    location.replace('/fail?msg=' + encodeURIComponent(err));
    return;
  }
  var at = h.get('access_token') || q.get('access_token');
  var rt = h.get('refresh_token') || q.get('refresh_token') || '';
  if (at) {
    location.replace('/ok?access_token=' + encodeURIComponent(at) + '&refresh_token=' + encodeURIComponent(rt));
  } else {
    document.getElementById('m').textContent = '沒有收到 token。請回到遊戲重試，並確認 Supabase Redirect URL 含 http://127.0.0.1:8765/callback';
  }
})();
</script>
</body></html>
"""


func _success_html() -> String:
	return """<!DOCTYPE html><html><head><meta charset="utf-8"><title>登入成功</title></head>
<body style="font-family:sans-serif;background:#1a1520;color:#cfc;padding:2rem">
<h1>登入成功</h1>
<p>可以關閉此分頁，回到「勇者之魂」。</p>
<script>setTimeout(function(){ window.close(); }, 800);</script>
</body></html>
"""


func _fail_html(msg: String) -> String:
	return """<!DOCTYPE html><html><head><meta charset="utf-8"><title>登入失敗</title></head>
<body style="font-family:sans-serif;background:#1a1520;color:#fcc;padding:2rem">
<h1>登入失敗</h1>
<p>%s</p>
<p>請關閉此分頁，回到遊戲重試。</p>
</body></html>
""" % msg.replace("<", "&lt;").replace(">", "&gt;")
