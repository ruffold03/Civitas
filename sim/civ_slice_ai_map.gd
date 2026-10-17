class_name CivSliceAiMap
extends RefCounted

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceRoads = preload("res://sim/civ_slice_roads.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivUtil = preload("res://sim/civ_util.gd")

const FOOTPRINT_SHAPES := {
	1: [[[0, 0]]],
	2: [[[0, 0], [1, 0]], [[0, 0], [0, 1]]],
	3: [[[0, 0], [1, 0], [2, 0]], [[0, 0], [0, 1], [0, 2]], [[0, 0], [1, 0], [0, 1]]],
	4: [[[0, 0], [1, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [2, 0], [3, 0]]],
}


static func find_build_cells(state: Dictionary, type_id: String) -> Array:
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	var area := int(definition["area"])
	var shapes: Array = FOOTPRINT_SHAPES.get(area, [])
	if shapes.is_empty():
		return []
	var foundation := str(state.get("foundation", ""))
	var anchors := _anchor_cells(state, foundation)
	for anchor in anchors:
		for shape in shapes:
			var cells: Array = []
			for offset in shape:
				cells.append([int(anchor[0]) + int(offset[0]), int(anchor[1]) + int(offset[1])])
			if _valid_build_cells(state, type_id, cells, foundation):
				return cells
	return []


static func find_prepare_cell(state: Dictionary) -> Array:
	var foundation := str(state.get("foundation", ""))
	for anchor in _anchor_cells(state, foundation):
		var x := int(anchor[0])
		var y := int(anchor[1])
		if CivSliceMap.is_start_zone_cell(x, y, foundation):
			continue
		if not _cell_ready_to_prepare(state, x, y, foundation):
			continue
		return [x, y]
	return []


static func find_road_cell(state: Dictionary) -> Array:
	var foundation := str(state.get("foundation", ""))
	for anchor in _anchor_cells(state, foundation):
		var x := int(anchor[0])
		var y := int(anchor[1])
		var place := CivSliceRoads.can_place_road(state, x, y, foundation)
		if place["ok"]:
			return [x, y]
	return []


static func pick_survey_chunk(state: Dictionary) -> Vector2i:
	var hall := _town_hall_cell(state)
	var best_dist := 9999
	var pick := Vector2i(-1, -1)
	for record in state.get("chunks", []):
		if bool(record.get("surveyed", false)):
			continue
		if int(record.get("survey_timer", 0)) > 0:
			continue
		var cx := int(record["x"])
		var cy := int(record["y"])
		var dist: int = absi(cx * CivGeoSlice.CHUNK - hall.x) + absi(cy * CivGeoSlice.CHUNK - hall.y)
		if dist < best_dist:
			best_dist = dist
			pick = Vector2i(cx, cy)
	if pick.x < 0:
		return Vector2i(-1, -1)
	return pick


static func _valid_build_cells(state: Dictionary, type_id: String, cells: Array, foundation: String) -> bool:
	if not CivGeoSlice.connected(cells):
		return false
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	if cells.size() != int(definition["area"]):
		return false
	var req := str(definition.get("requires_tech", ""))
	if req != "" and not CivSliceTech.is_researched(state, req):
		return false
	for cell in cells:
		var x := int(cell[0])
		var y := int(cell[1])
		if not CivGeoSlice.in_bounds(x, y):
			return false
		var terrain := CivGeoSlice.terrain_at(x, y, foundation)
		if not CivGeoSlice.allows_default_building(terrain):
			return false
		var chunk: Array = CivGeoSlice.chunk_of(x, y)
		if not CivSliceMap.chunk_is_surveyed(state, int(chunk[0]), int(chunk[1])):
			return false
		if not CivSliceMap.is_prepared_for_build(state, x, y, foundation):
			return false
		if CivSliceMap.is_cell_blocked(state, x, y):
			return false
	if bool(definition.get("requires_road", false)):
		if CivSliceRoads.needs_outside_road_check(cells, foundation):
			if not CivSliceRoads.building_linked_to_town(state, cells, foundation):
				return false
	return true


static func _cell_ready_to_prepare(state: Dictionary, x: int, y: int, foundation: String) -> bool:
	if not CivGeoSlice.in_bounds(x, y):
		return false
	var terrain := CivGeoSlice.terrain_at(x, y, foundation)
	if not CivGeoSlice.allows_default_building(terrain):
		return false
	if CivGeoSlice.preparation_turns(terrain) < 0:
		return false
	var chunk: Array = CivGeoSlice.chunk_of(x, y)
	if not CivSliceMap.chunk_is_surveyed(state, int(chunk[0]), int(chunk[1])):
		return false
	if CivSliceMap.is_cell_blocked(state, x, y):
		return false
	var prep: Dictionary = CivSliceMap.prep_record(state, x, y)
	if bool(prep.get("prepared", false)):
		return false
	if int(prep.get("timer", 0)) > 0:
		return false
	return true


static func _anchor_cells(state: Dictionary, foundation: String) -> Array:
	var hall := _town_hall_cell(state)
	var anchors: Array = []
	for y in CivGeoSlice.SIZE:
		for x in CivGeoSlice.SIZE:
			if not CivGeoSlice.allows_default_building(CivGeoSlice.terrain_at(x, y, foundation)):
				continue
			var dist: int = absi(x - hall.x) + absi(y - hall.y)
			anchors.append({"x": x, "y": y, "dist": dist})
	anchors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["dist"]) < int(b["dist"]))
	var sorted: Array = []
	for item in anchors:
		sorted.append([int(item["x"]), int(item["y"])])
	return sorted


static func _town_hall_cell(state: Dictionary) -> Vector2i:
	for building in state.get("buildings", []):
		if str(building.get("type", "")) != "town_hall":
			continue
		var cells: Array = building["cells"]
		if cells.is_empty():
			continue
		return Vector2i(int(cells[0][0]), int(cells[0][1]))
	var origin := CivGeoSlice.start_zone_origin(str(state.get("foundation", "latium_hills")))
	return origin + Vector2i(2, 2)
