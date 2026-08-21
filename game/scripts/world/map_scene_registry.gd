extends RefCounted
class_name MapSceneRegistry
## 可選：某 map_id 有對應 .tscn 時，ExploreView 會掛上編輯器可預覽的裝飾層。
## 玩法實體（碰撞／E 互動）仍以 map_catalog.gd 為準，直到整張圖遷移完。

const SCENE_DIR := "res://scenes/maps"

## 明確登錄（也可靠慣例 SCENE_DIR/<id>.tscn）
const SCENES := {
	"village": "res://scenes/maps/village.tscn",
	"town": "res://scenes/maps/town.tscn",
	"mist_village": "res://scenes/maps/mist_village.tscn",
}


static func scene_path(map_id: String) -> String:
	if SCENES.has(map_id):
		return str(SCENES[map_id])
	var conventional := "%s/%s.tscn" % [SCENE_DIR, map_id]
	if ResourceLoader.exists(conventional):
		return conventional
	return ""


static func has_scene(map_id: String) -> bool:
	var p := scene_path(map_id)
	return p != "" and ResourceLoader.exists(p)


static func list_registered() -> PackedStringArray:
	var out: PackedStringArray = []
	for k in SCENES.keys():
		out.append(str(k))
	return out
