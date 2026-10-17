class_name CivGeoSlice
extends RefCounted

const CivUtil = preload("res://sim/civ_util.gd")

## Карта вертикального среза: 18×18, чанки 6×6. Местности — идентификаторы из Контент/Местности.

const SIZE := 18
const CHUNK := 6
const SURVEY_TURNS := 3

const FOUNDATIONS: Array[String] = ["latium_hills", "campanian_coast", "apulian_harbor"]

const START_ZONE := {
	"latium_hills": {"x": 0, "y": 0, "w": 6, "h": 6},
	"campanian_coast": {"x": 0, "y": 12, "w": 6, "h": 6},
	"apulian_harbor": {"x": 12, "y": 12, "w": 5, "h": 6},
}


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE


static func terrain_at(x: int, y: int, foundation_id: String) -> String:
	if not in_bounds(x, y):
		return ""
	match foundation_id:
		"campanian_coast":
			return _terrain_campania(x, y)
		"apulian_harbor":
			return _terrain_apulia(x, y)
		_:
			return _terrain_latium(x, y)


static func allows_default_building(terrain: String) -> bool:
	return terrain == "plain" or terrain == "hill" or terrain == "coast"


static func preparation_turns(terrain: String) -> int:
	match terrain:
		"hill":
			return 3
		"plain", "coast":
			return 2
		_:
			return -1


static func chunk_of(x: int, y: int) -> Array:
	return [int(x / CHUNK), int(y / CHUNK)]


static func all_chunks() -> Array:
	var chunks: Array = []
	var count := int(SIZE / CHUNK)
	for cy in count:
		for cx in count:
			chunks.append([cx, cy])
	return chunks


static func initial_chunks(foundation_id: String) -> Array:
	var zone: Dictionary = START_ZONE.get(foundation_id, START_ZONE["latium_hills"])
	var developed_chunk := chunk_of(int(zone["x"]), int(zone["y"]))
	var records: Array = []
	for chunk in all_chunks():
		var is_start := int(chunk[0]) == int(developed_chunk[0]) and int(chunk[1]) == int(developed_chunk[1])
		records.append({
			"x": chunk[0],
			"y": chunk[1],
			"developed": is_start,
			"surveyed": is_start,
			"survey_timer": 0,
		})
	return records


static func start_zone_origin(foundation_id: String) -> Vector2i:
	var zone: Dictionary = START_ZONE.get(foundation_id, START_ZONE["latium_hills"])
	return Vector2i(int(zone["x"]), int(zone["y"]))


static func foot_of_mountain(x: int, y: int, foundation_id: String) -> bool:
	if not allows_default_building(terrain_at(x, y, foundation_id)):
		return false
	for offset in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var nx: int = x + int(offset[0])
		var ny: int = y + int(offset[1])
		if in_bounds(nx, ny) and terrain_at(nx, ny, foundation_id) == "mountain":
			return true
	return false


static func connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var present := {}
	for cell in cells:
		present[CivUtil.cell_key(cell)] = true
	var stack: Array = [cells[0]]
	var seen := {}
	while not stack.is_empty():
		var current: Array = stack.pop_back()
		var key := CivUtil.cell_key(current)
		if seen.has(key):
			continue
		seen[key] = true
		var x := int(current[0])
		var y := int(current[1])
		for next in [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]:
			if present.has(CivUtil.cell_key(next)):
				stack.append(next)
	return seen.size() == cells.size()


static func _terrain_latium(x: int, y: int) -> String:
	if y <= 1:
		return "mountain"
	if _is_tiber(x, y):
		return "river"
	if y >= 16 and x >= 9:
		return "sea"
	if y == 15 and x >= 9:
		return "coast"
	if y == 16 and x >= 9 and x <= 16:
		return "coast"
	if y == 2 and x <= 11:
		return "hill"
	if y >= 3 and y <= 7 and x <= 5 and (x + y) % 2 == 0:
		return "hill"
	return "plain"


static func _terrain_campania(x: int, y: int) -> String:
	if y >= 16:
		return "sea"
	if y == 15:
		return "coast"
	if y == 14 and x <= 10:
		return "coast"
	if x >= 14 and y <= 4:
		return "hill"
	return "plain"


static func _terrain_apulia(x: int, y: int) -> String:
	if _in_tarent_harbor(x, y):
		return "sea"
	if _harbor_coast(x, y):
		return "coast"
	if y <= 2 and x >= 10:
		return "mountain"
	if y <= 4 and x >= 8 and (x + y) % 2 == 1:
		return "hill"
	return "plain"


static func _is_tiber(x: int, y: int) -> bool:
	if y < 4 or y > 16:
		return false
	if x == 7:
		return true
	if y >= 10 and y <= 12 and (x == 6 or x == 8):
		return true
	return false


static func _in_tarent_harbor(x: int, y: int) -> bool:
	var dx := x - 13
	var dy := y - 14
	return dx * dx + dy * dy <= 6


static func _harbor_coast(x: int, y: int) -> bool:
	if _in_tarent_harbor(x, y):
		return false
	for offset in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		if _in_tarent_harbor(x + offset[0], y + offset[1]):
			return true
	return false
