class_name CivGeoSlice
extends RefCounted

const CivUtil = preload("res://sim/civ_util.gd")

## Карта вертикального среза: 18×18, чанки 6×6. Местности — идентификаторы из Контент/Местности.

const SIZE := 18
const CHUNK := 6
const SURVEY_TURNS := 3

const FOUNDATIONS: Array[String] = ["latium_hills", "campanian_coast", "apulian_harbor"]

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


static func start_zone(foundation_id: String) -> Dictionary:
	return _best_start_zone(foundation_id)


static func initial_chunks(foundation_id: String) -> Array:
	var zone: Dictionary = start_zone(foundation_id)
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
	var zone: Dictionary = start_zone(foundation_id)
	return Vector2i(int(zone["x"]), int(zone["y"]))


static func _best_start_zone(foundation_id: String) -> Dictionary:
	var width := 6
	var height := 6
	if foundation_id == "apulian_harbor":
		width = 5
	var center := Vector2(float(SIZE) * 0.5, float(SIZE) * 0.5)
	var best_dist := 999999.0
	var best := {"x": 6, "y": 6, "w": width, "h": height}
	for y0 in range(0, SIZE - height + 1):
		for x0 in range(0, SIZE - width + 1):
			if not _zone_all_buildable(x0, y0, width, height, foundation_id):
				continue
			var zx := float(x0) + float(width) * 0.5
			var zy := float(y0) + float(height) * 0.5
			var dist := (zx - center.x) * (zx - center.x) + (zy - center.y) * (zy - center.y)
			if dist < best_dist:
				best_dist = dist
				best = {"x": x0, "y": y0, "w": width, "h": height}
	return best


static func _zone_all_buildable(x0: int, y0: int, width: int, height: int, foundation_id: String) -> bool:
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			if not allows_default_building(terrain_at(x, y, foundation_id)):
				return false
	return true


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
