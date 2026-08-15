extends RefCounted
## 星途市集面板。
##
## 從 main.gd 抽出來的第一塊。這裡只負責「組出 title／body／buttons」，
## 真正的畫面渲染仍走宿主的 ui_panel()，資料進出走 MarketSystem。
##
## 宿主（main.gd）需提供的介面：
##   ui_panel(title: String, body: String, buttons: Array) -> void
##   ui_toast(msg: String) -> void
##   ui_hub_back() -> void
##   ui_open_hunt_recycle() -> void
##
## 刻意不用 class_name：避免把「編譯期就會拉到 autoload」的腳本註冊進全域類別快取
## （見 AGENTS.md「寫測試的規矩」）。main.gd 用 preload 取用即可。

var _host: Node


func _init(host: Node) -> void:
	_host = host


func open() -> void:
	if not MarketSystem.is_unlocked():
		_host.ui_panel("星途市集", "市集尚未開張。先進騎士堡。", [
			{"text": "返回", "cb": Callable(_host, "ui_hub_back")},
		])
		return
	var body: String = MarketSystem.status_bbcode()
	body += "\n\n（瀏覽中…）"
	var buttons: Array = [
		{"text": "刷新掛單", "cb": refresh},
		{"text": "我要上架", "cb": open_sell},
	]
	if MarketSystem.pending_credit() > 0:
		buttons.append({"text": "領取貨款（%d）" % MarketSystem.pending_credit(), "cb": claim})
	buttons.append({"text": "溢物回收（即時）", "cb": Callable(_host, "ui_open_hunt_recycle")})
	buttons.append({"text": "返回", "cb": Callable(_host, "ui_hub_back")})
	_host.ui_panel("星途市集", body, buttons)
	MarketSystem.refresh_online(func(res: Dictionary):
		_show_browse(res.get("list", MarketSystem.browse_all()))
	)


func refresh() -> void:
	_host.ui_toast("刷新中…")
	MarketSystem.refresh_online(func(res: Dictionary):
		_show_browse(res.get("list", []))
	)


func _show_browse(list: Array) -> void:
	var body: String = MarketSystem.status_bbcode() + "\n\n[b]掛單[/b]\n"
	var buttons: Array = []
	var n := 0
	for row in list:
		if n >= 12:
			body += "…（僅顯示前 12）\n"
			break
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row
		body += "· " + MarketSystem.listing_label(d) + "\n"
		var src := str(d.get("source", "online"))
		var seller := str(d.get("seller_id", ""))
		var is_own: bool = src == "local" or (OnlineGate.is_signed_in() and seller == OnlineGate.user_id)
		if is_own:
			buttons.append({
				"text": "下架 %s" % InventorySystem.item_name(str(d.get("item_id", ""))),
				"cb": cancel.bind(str(d.get("id", ""))),
			})
		else:
			buttons.append({
				"text": "買 %s" % MarketSystem.listing_label(d).substr(0, 28),
				"cb": buy.bind(d),
			})
		n += 1
	if n == 0:
		body += "（目前沒有掛單）\n"
	buttons.append({"text": "我要上架", "cb": open_sell})
	if MarketSystem.pending_credit() > 0:
		buttons.append({"text": "領取貨款（%d）" % MarketSystem.pending_credit(), "cb": claim})
	buttons.append({"text": "刷新", "cb": refresh})
	buttons.append({"text": "返回", "cb": Callable(_host, "ui_hub_back")})
	_host.ui_panel("星途市集", body, buttons)


func open_sell() -> void:
	var body := "[b]上架[/b]\n選擇可交易物。總價自訂（預設為底價×數量×1.5）。\n手續費售出時扣 %d%%。\n\n" % int(MarketSystem.FEE_RATE * 100)
	var buttons: Array = []
	for iid in MarketSystem.TRADEABLE:
		var c: int = InventorySystem.count(iid)
		if c <= 0:
			continue
		var unit: int = MarketSystem.base_price(iid)
		var qty := mini(c, 3)
		var price := maxi(unit * qty, int(unit * qty * 1.5))
		body += "· %s ×%d（底 %d／個）\n" % [InventorySystem.item_name(iid), c, unit]
		buttons.append({
			"text": "上架 %s×%d · 總價%d" % [InventorySystem.item_name(iid), qty, price],
			"cb": list_item.bind(iid, qty, price),
		})
		if c >= 1 and qty != 1:
			buttons.append({
				"text": "上架 %s×1 · 總價%d" % [InventorySystem.item_name(iid), maxi(unit, int(unit * 1.5))],
				"cb": list_item.bind(iid, 1, maxi(unit, int(unit * 1.5))),
			})
	if buttons.is_empty():
		body += "（沒有可上架物品）\n"
	buttons.append({"text": "返回市集", "cb": open})
	_host.ui_panel("市集 · 上架", body, buttons)


func list_item(item_id: String, qty: int, price: int) -> void:
	var r: Dictionary = MarketSystem.list_item(item_id, qty, price)
	_host.ui_toast(str(r.get("msg", "")))
	open()


func buy(listing: Dictionary) -> void:
	var r: Dictionary = MarketSystem.buy_listing(listing)
	_host.ui_toast(str(r.get("msg", "")))
	refresh()


func cancel(listing_id: String) -> void:
	var r: Dictionary = MarketSystem.cancel_listing(listing_id)
	_host.ui_toast(str(r.get("msg", "")))
	refresh()


func claim() -> void:
	var r: Dictionary = MarketSystem.claim_pending_credit()
	_host.ui_toast(str(r.get("msg", "")))
	open()
