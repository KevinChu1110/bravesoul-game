extends RefCounted
## 倉庫面板（存取材料與裝備）。
##
## 從 main.gd 抽出的第四塊，也是最單純的一塊：純 ui_panel()，沒有非同步、
## 沒有自繪、沒有流程控制。
##
## 宿主介面見 main.gd 的「面板宿主介面」段落。導覽一律走 ui_goto()。
##
## 刻意不用 class_name（見 AGENTS.md「寫測試的規矩」）。

## 可存進倉庫的材料。順序即面板上的顯示順序。
const DEPOSITABLE: Array[String] = [
	"hunt_hide", "hunt_bone", "hunt_core", "hp_s", "bread", "wolf_fang", "dust_crumb",
]

## 面板一頁最多列幾顆按鈕，避免選單被塞爆
const MAX_DEPOSIT := 6
const MAX_WITHDRAW := 6
const MAX_EQUIP_IN := 10
const MAX_EQUIP_OUT := 12

var _host: Node


func _init(host: Node) -> void:
	_host = host


func _goto(target: String) -> Callable:
	return Callable(_host, "ui_goto").bind(target)


func open() -> void:
	var body: String = WarehouseSystem.status_bbcode()
	var buttons: Array = []

	## 可存：背包有的材料
	var shown := 0
	for id in DEPOSITABLE:
		if InventorySystem.count(id) > 0 and shown < MAX_DEPOSIT:
			buttons.append({"text": "存 %s" % InventorySystem.item_name(id), "cb": deposit.bind(id)})
			shown += 1

	## 可取：倉庫裡的材料
	var wi := 0
	for id2 in GameState.warehouse.keys():
		if wi >= MAX_WITHDRAW:
			break
		buttons.append({"text": "取 %s" % InventorySystem.item_name(str(id2)), "cb": withdraw.bind(str(id2))})
		wi += 1

	## 裝備進出庫
	for e in GameState.equip_bag:
		if shown >= MAX_EQUIP_IN:
			break
		buttons.append({"text": "裝入庫 " + str(e.get("name", "")), "cb": deposit_equip.bind(str(e.get("uid", "")))})
		shown += 1
	for e2 in GameState.warehouse_equip:
		if wi >= MAX_EQUIP_OUT:
			break
		buttons.append({"text": "裝取出 " + str(e2.get("name", "")), "cb": withdraw_equip.bind(str(e2.get("uid", "")))})
		wi += 1

	buttons.append({"text": "裝備", "cb": _goto("equip")})
	buttons.append({"text": "返回", "cb": _goto("hub")})
	_host.ui_panel("倉庫", body, buttons)


func deposit(id: String) -> void:
	_host.ui_toast(str(WarehouseSystem.deposit_item(id, 1).get("msg", "")))
	open()


func withdraw(id: String) -> void:
	_host.ui_toast(str(WarehouseSystem.withdraw_item(id, 1).get("msg", "")))
	open()


func deposit_equip(uid: String) -> void:
	_host.ui_toast(str(WarehouseSystem.deposit_equip(uid).get("msg", "")))
	open()


func withdraw_equip(uid: String) -> void:
	_host.ui_toast(str(WarehouseSystem.withdraw_equip(uid).get("msg", "")))
	open()
