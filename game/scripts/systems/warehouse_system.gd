extends Node
## 倉庫：堆疊物 + 裝備實例分區存放。
## Autoload：WarehouseSystem

signal warehouse_changed


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if GameState.warehouse == null:
		GameState.warehouse = {}
	if GameState.warehouse_equip == null:
		GameState.warehouse_equip = []


func max_slots() -> int:
	return DataTables.warehouse_max() if Engine.get_main_loop() else 60


func used_stack_slots() -> int:
	_ensure()
	return GameState.warehouse.size()


func deposit_item(item_id: String, n: int = 1) -> Dictionary:
	_ensure()
	n = maxi(1, n)
	if not InventorySystem.has_item(item_id, n):
		return {"ok": false, "msg": "背包數量不足。"}
	if not GameState.warehouse.has(item_id) and used_stack_slots() >= max_slots():
		return {"ok": false, "msg": "倉庫已滿。"}
	InventorySystem.remove_item(item_id, n)
	GameState.warehouse[item_id] = int(GameState.warehouse.get(item_id, 0)) + n
	warehouse_changed.emit()
	SaveManager.save_game()
	GameLog.economy("存入倉庫 %s×%d" % [InventorySystem.item_name(item_id), n])
	return {"ok": true, "msg": "已存入 %s×%d" % [InventorySystem.item_name(item_id), n]}


func withdraw_item(item_id: String, n: int = 1) -> Dictionary:
	_ensure()
	n = maxi(1, n)
	var have := int(GameState.warehouse.get(item_id, 0))
	if have < n:
		return {"ok": false, "msg": "倉庫數量不足。"}
	GameState.warehouse[item_id] = have - n
	if GameState.warehouse[item_id] <= 0:
		GameState.warehouse.erase(item_id)
	InventorySystem.add_item(item_id, n)
	warehouse_changed.emit()
	SaveManager.save_game()
	GameLog.economy("取出倉庫 %s×%d" % [InventorySystem.item_name(item_id), n])
	return {"ok": true, "msg": "已取出 %s×%d" % [InventorySystem.item_name(item_id), n]}


func deposit_equip(uid: String) -> Dictionary:
	_ensure()
	EquipmentSystem._ensure_state()
	var inst := EquipmentSystem.find_bag(uid)
	if inst.is_empty():
		return {"ok": false, "msg": "背包裝備中找不到。"}
	if GameState.warehouse_equip.size() >= max_slots():
		return {"ok": false, "msg": "倉庫裝備欄已滿。"}
	EquipmentSystem._remove_from_bag(uid)
	GameState.warehouse_equip.append(inst)
	warehouse_changed.emit()
	SaveManager.save_game()
	GameLog.equip("裝備入庫 %s" % inst.get("name", uid))
	return {"ok": true, "msg": "裝備已入庫"}


func withdraw_equip(uid: String) -> Dictionary:
	_ensure()
	var found: Dictionary = {}
	var next: Array = []
	for e in GameState.warehouse_equip:
		if str(e.get("uid", "")) == uid:
			found = e
		else:
			next.append(e)
	if found.is_empty():
		return {"ok": false, "msg": "倉庫沒有此裝。"}
	GameState.warehouse_equip = next
	EquipmentSystem.add_to_bag(found)
	warehouse_changed.emit()
	SaveManager.save_game()
	GameLog.equip("裝備取出 %s" % found.get("name", uid))
	return {"ok": true, "msg": "裝備已取出"}


func status_bbcode() -> String:
	_ensure()
	var lines: PackedStringArray = []
	lines.append("[b]倉庫[/b]（%d／%d 堆疊格 · 裝備 %d）" % [
		used_stack_slots(), max_slots(), GameState.warehouse_equip.size()
	])
	if GameState.warehouse.is_empty() and GameState.warehouse_equip.is_empty():
		lines.append("（空空如也）")
		return "\n".join(lines)
	var n := 0
	for id in GameState.warehouse.keys():
		if n >= 12:
			lines.append("…")
			break
		lines.append("· %s ×%d" % [InventorySystem.item_name(str(id)), int(GameState.warehouse[id])])
		n += 1
	for e in GameState.warehouse_equip:
		if n >= 16:
			break
		lines.append("· [裝] %s" % EquipmentSystem.label(e))
		n += 1
	return "\n".join(lines)
