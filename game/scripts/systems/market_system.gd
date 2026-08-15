extends Node
## 星途市集：非同步掛單。離線＝本地＋NPC 陰影；上線＝Supabase listings。
## Autoload：MarketSystem

const FEE_RATE := 0.08
const MAX_OWN_LISTINGS := 8
const LOCAL_KEY := "market.local_listings"
const CREDIT_KEY := "market.pending_credit"

## 可上架
const TRADEABLE: Array[String] = [
	"hunt_hide", "hunt_bone", "hunt_core",
	"wolf_fang", "mist_shard", "sea_shell", "scar_ember", "dust_crumb",
	"hp_s", "bread", "antidote",
]

## 離線 NPC 陰影庫（每日刷新價）
const NPC_STOCK: Array[Dictionary] = [
	{"item_id": "hunt_hide", "qty": 3, "price_mult": 1.2},
	{"item_id": "hunt_bone", "qty": 2, "price_mult": 1.15},
	{"item_id": "hp_s", "qty": 5, "price_mult": 1.4},
	{"item_id": "bread", "qty": 4, "price_mult": 1.3},
	{"item_id": "dust_crumb", "qty": 2, "price_mult": 1.5},
]

var _cache: Array = []  ## 最近拉到的上線掛單
var _busy: bool = false
## 伺服器認定的可交易餘額。連線交易看的是這一份，不是本地存檔的數字。
var _ledger: Dictionary = {}


func is_tradeable(item_id: String) -> bool:
	if item_id in TRADEABLE:
		return true
	var def: Dictionary = InventorySystem.catalog(item_id)
	return bool(def.get("tradeable", false))


func fee_of(price: int) -> int:
	return maxi(1, int(round(float(price) * FEE_RATE)))


func seller_receive(price: int) -> int:
	return maxi(0, price - fee_of(price))


func base_price(item_id: String) -> int:
	var def: Dictionary = InventorySystem.catalog(item_id)
	var s := int(def.get("sell", 0))
	if s > 0:
		return s
	match item_id:
		"hp_s":
			return 18
		"bread":
			return 12
		"antidote":
			return 20
		"dust_crumb":
			return 25
		_:
			return 10


func is_unlocked() -> bool:
	return GameState.has_flag("c1_entered_city") or GameState.chapter != "c0" \
		or GameState.has_flag("c0_first_battle")


func online_mode() -> bool:
	return OnlineGate.is_signed_in()


func pending_credit() -> int:
	return int(GameState.get_flag(CREDIT_KEY, 0))


func add_pending_credit(n: int) -> void:
	if n <= 0:
		return
	GameState.set_flag(CREDIT_KEY, pending_credit() + n)
	SaveManager.save_game()


func claim_pending_credit() -> Dictionary:
	var n := pending_credit()
	if n <= 0:
		return {"ok": false, "msg": "沒有待領金幣。"}
	GameState.set_flag(CREDIT_KEY, 0)
	GameState.add_gold(n)
	SaveManager.save_game()
	## 上線時一併清伺服器 credit
	if online_mode():
		OnlineGate.market_claim_credit()
	return {"ok": true, "msg": "領取市集貨款 金 +%d" % n, "gold": n}


func local_listings() -> Array:
	var raw: Variant = GameState.get_flag(LOCAL_KEY, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw.duplicate(true)


func _save_local(list: Array) -> void:
	GameState.set_flag(LOCAL_KEY, list)
	SaveManager.save_game()


func _npc_day_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d.year) * 400 + int(d.month) * 32 + int(d.day)


func npc_listings() -> Array:
	var seed_n := _npc_day_seed()
	var out: Array = []
	var i := 0
	for row in NPC_STOCK:
		i += 1
		var iid := str(row.get("item_id", ""))
		var base := base_price(iid)
		var mult := float(row.get("price_mult", 1.2))
		## 日抖動 ±10%
		var jitter := 1.0 + float((seed_n * 17 + i * 31) % 21 - 10) / 100.0
		var unit := maxi(1, int(round(float(base) * mult * jitter)))
		var qty := int(row.get("qty", 1))
		out.append({
			"id": "npc_%d_%s" % [seed_n, iid],
			"seller_id": "npc",
			"seller_name": "行商陰影",
			"item_id": iid,
			"qty": qty,
			"price": unit * qty,
			"status": "active",
			"source": "npc",
		})
	return out


func list_item(item_id: String, qty: int, total_price: int) -> Dictionary:
	if not is_unlocked():
		return {"ok": false, "msg": "市集尚未開張。"}
	if not is_tradeable(item_id):
		return {"ok": false, "msg": "此物不可上架。"}
	qty = maxi(1, qty)
	total_price = maxi(1, total_price)
	if not InventorySystem.has_item(item_id, qty):
		return {"ok": false, "msg": "數量不足。"}
	var own := _count_own_active()
	if own >= MAX_OWN_LISTINGS:
		return {"ok": false, "msg": "掛單上限 %d。" % MAX_OWN_LISTINGS}

	## 先扣物
	if not InventorySystem.remove_item(item_id, qty):
		return {"ok": false, "msg": "扣物失敗。"}

	if online_mode():
		OnlineGate.market_create_listing(item_id, qty, total_price, func(res: Dictionary):
			if not bool(res.get("ok", false)):
				## 回滾
				InventorySystem.add_item(item_id, qty)
				SaveManager.save_game()
		)
		SaveManager.save_game()
		return {"ok": true, "msg": "已送出上架（連線）。手續費約 %d%%。" % int(FEE_RATE * 100)}

	## 離線本地掛單
	var list := local_listings()
	var lid := "local_%d_%s" % [Time.get_unix_time_from_system(), item_id]
	list.append({
		"id": lid,
		"seller_id": "local",
		"seller_name": GameState.player_name,
		"item_id": item_id,
		"qty": qty,
		"price": total_price,
		"status": "active",
		"source": "local",
	})
	_save_local(list)
	return {"ok": true, "msg": "已本地掛單（上線後可同步）。手續費 %d%% 於售出時扣。" % int(FEE_RATE * 100)}


func _count_own_active() -> int:
	var n := 0
	for row in local_listings():
		if str(row.get("status", "")) == "active":
			n += 1
	for row in _cache:
		if str(row.get("seller_id", "")) == OnlineGate.user_id and str(row.get("status", "")) == "active":
			n += 1
	return n


func cancel_listing(listing_id: String) -> Dictionary:
	## 本地
	var list := local_listings()
	for i in range(list.size()):
		var row: Dictionary = list[i]
		if str(row.get("id", "")) != listing_id:
			continue
		if str(row.get("status", "")) != "active":
			return {"ok": false, "msg": "此單已結束。"}
		row["status"] = "cancelled"
		list[i] = row
		_save_local(list)
		InventorySystem.add_item(str(row.get("item_id", "")), int(row.get("qty", 1)))
		SaveManager.save_game()
		return {"ok": true, "msg": "已下架，物歸囊中。"}
	if online_mode():
		OnlineGate.market_cancel_listing(listing_id, func(res: Dictionary):
			if bool(res.get("ok", false)):
				var iid := str(res.get("item_id", ""))
				var q := int(res.get("qty", 0))
				if iid != "" and q > 0:
					InventorySystem.add_item(iid, q)
					SaveManager.save_game()
		)
		return {"ok": true, "msg": "已送出下架請求。"}
	return {"ok": false, "msg": "找不到掛單。"}


func buy_listing(listing: Dictionary) -> Dictionary:
	var lid := str(listing.get("id", ""))
	var iid := str(listing.get("item_id", ""))
	var qty := int(listing.get("qty", 1))
	var price := int(listing.get("price", 0))
	var source := str(listing.get("source", "online"))
	if iid == "" or qty <= 0 or price <= 0:
		return {"ok": false, "msg": "掛單無效。"}
	if GameState.gold < price:
		return {"ok": false, "msg": "金幣不足（需 %d）。" % price}

	## 自己的單不能買
	if source == "local" and str(listing.get("seller_id", "")) == "local":
		return {"ok": false, "msg": "不能買自己的掛單。"}
	if online_mode() and str(listing.get("seller_id", "")) == OnlineGate.user_id:
		return {"ok": false, "msg": "不能買自己的掛單。"}

	if source == "npc":
		GameState.add_gold(-price)
		InventorySystem.add_item(iid, qty)
		SaveManager.save_game()
		return {"ok": true, "msg": "向行商陰影購入 %s×%d（-%d 金）" % [InventorySystem.item_name(iid), qty, price]}

	if source == "local":
		## 買別人的本地單：單機模擬，給自己物、扣金、標記 sold + 若是自己賣的加 credit
		var list := local_listings()
		var found := false
		for i in range(list.size()):
			var row: Dictionary = list[i]
			if str(row.get("id", "")) != lid:
				continue
			if str(row.get("status", "")) != "active":
				return {"ok": false, "msg": "已售出或下架。"}
			row["status"] = "sold"
			list[i] = row
			found = true
			break
		if not found:
			return {"ok": false, "msg": "找不到掛單。"}
		_save_local(list)
		GameState.add_gold(-price)
		InventorySystem.add_item(iid, qty)
		## 本地賣家＝自己時：貨款入待領（手續費後）
		add_pending_credit(seller_receive(price))
		SaveManager.save_game()
		return {"ok": true, "msg": "購入 %s×%d（-%d 金）" % [InventorySystem.item_name(iid), qty, price]}

	## 上線
	if not online_mode():
		return {"ok": false, "msg": "需上線才能買連線掛單。"}
	GameState.add_gold(-price)
	SaveManager.save_game()
	OnlineGate.market_buy(lid, func(res: Dictionary):
		if not bool(res.get("ok", false)):
			GameState.add_gold(price)  ## 退款
			SaveManager.save_game()
			return
		InventorySystem.add_item(str(res.get("item_id", iid)), int(res.get("qty", qty)))
		SaveManager.save_game()
	)
	return {"ok": true, "msg": "已送出購買（連線結算中）…"}


func refresh_online(cb: Callable = Callable()) -> void:
	if not online_mode():
		_cache = []
		_ledger = {}
		if cb.is_valid():
			cb.call({"ok": true, "list": browse_all()})
		return
	_busy = true
	OnlineGate.market_fetch_listings(func(res: Dictionary):
		_busy = false
		if bool(res.get("ok", false)):
			_cache = res.get("list", [])
		OnlineGate.fetch_ledger(func(lg: Dictionary):
			if bool(lg.get("ok", false)):
				_ledger = lg
			if cb.is_valid():
				cb.call({"ok": true, "list": browse_all()})
		)
	)


## 伺服器認的可用金幣；-1 代表還沒問到
func ledger_gold() -> int:
	if not online_mode() or _ledger.is_empty():
		return -1
	return int(_ledger.get("gold", 0))


func ledger_seeded() -> bool:
	return bool(_ledger.get("seeded", false))


func ledger_qty(item_id: String) -> int:
	var items: Variant = _ledger.get("items", {})
	if items is Dictionary:
		return int(items.get(item_id, 0))
	return 0


func browse_all() -> Array:
	var out: Array = []
	## 自己的本地 active
	for row in local_listings():
		if str(row.get("status", "")) == "active":
			var d: Dictionary = row.duplicate(true)
			d["source"] = "local"
			out.append(d)
	## NPC
	for row in npc_listings():
		out.append(row)
	## 連線
	for row in _cache:
		if str(row.get("status", "active")) != "active" and str(row.get("status", "")) != "":
			## 後端只拉 active 時可略
			if str(row.get("status", "")) != "active":
				continue
		var d2: Dictionary = row.duplicate(true) if row is Dictionary else {}
		if d2.is_empty():
			continue
		d2["source"] = "online"
		## 欄位對齊
		if not d2.has("id") and d2.has("id"):
			pass
		out.append(d2)
	return out


func status_bbcode() -> String:
	var lines: PackedStringArray = []
	lines.append("[b]星途市集[/b]")
	lines.append("非同步掛單。手續費 %d%%（售出時從貨款扣）。" % int(FEE_RATE * 100))
	lines.append("模式：%s" % ("連線市集" if online_mode() else "離線陰影（NPC＋本地掛單）"))
	if online_mode():
		if not ledger_seeded():
			lines.append("[color=#c9a]連線交易的額度尚未建立：先推一次雲存檔，市集才認得你的家當。[/color]")
		elif ledger_gold() >= 0:
			lines.append("連線可用：%d 金（與別人交易只認這一筆）" % ledger_gold())
	lines.append("待領貨款：%d 金" % pending_credit())
	lines.append("可交易：狩獵材料、部分消耗品。")
	lines.append("")
	if not is_unlocked():
		lines.append("（進入騎士堡後開張）")
	return "\n".join(lines)


func listing_label(row: Dictionary) -> String:
	var iid := str(row.get("item_id", ""))
	var qty := int(row.get("qty", 1))
	var price := int(row.get("price", 0))
	var seller := str(row.get("seller_name", row.get("seller_id", "?")))
	var src := str(row.get("source", ""))
	var tag := ""
	if src == "npc":
		tag = "〔影〕"
	elif src == "local":
		tag = "〔本〕"
	elif src == "online":
		tag = "〔線〕"
	return "%s%s×%d · %d金 · %s" % [tag, InventorySystem.item_name(iid), qty, price, seller]
