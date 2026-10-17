class_name CivSliceRoads
extends RefCounted

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivUtil = preload("res://sim/civ_util.gd")

const BUILD_TIME := 1
const COST := {"wood": 2}


static func building_requires_road(type_id: String) -> bool:
	return bool(CivSliceCatalog.building(type_id).get("requires_road", false))


static func needs_outside_road_check(cells: Array, foundation_id: String) -> bool:
	for cell in cells:
		if not CivSliceMap.is_start_zone_cell(int(cell[0]), int(cell[1]), foundation_id):
			return true
	return false


static func can_place_road(state: Dictionary, x: int, y: int, foundation_id: String) -> Dictionary:
	if not CivGeoSlice.in_bounds(x, y):
		return {"ok": false, "error": "Клетка вне карты."}
	var terrain := CivGeoSlice.terrain_at(x, y, foundation_id)
	if not CivGeoSlice.allows_default_building(terrain):
		return {"ok": false, "error": "Здесь нельзя строить дорогу."}
	var chunk: Array = CivGeoSlice.chunk_of(x, y)
	if not CivSliceMap.chunk_is_surveyed(state, int(chunk[0]), int(chunk[1])):
		return {"ok": false, "error": "Сначала изучи чанк."}
	if not CivSliceMap.is_prepared_for_build(state, x, y, foundation_id):
		return {"ok": false, "error": "Сначала подготовь клетку."}
	if CivSliceMap.is_cell_blocked(state, x, y):
		return {"ok": false, "error": "Клетка занята."}
	if not _touches_network(state, x, y):
		return {"ok": false, "error": "Дорога должна примыкать к ратуше или другой дороге."}
	return {"ok": true, "error": ""}


static func building_linked_to_town(state: Dictionary, cells: Array, foundation_id: String) -> bool:
	if not needs_outside_road_check(cells, foundation_id):
		return true
	var network := _network_cells(state)
	for cell in cells:
		var linked := false
		var x := int(cell[0])
		var y := int(cell[1])
		for next in [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]:
			if network.has(CivUtil.cell_key(next)):
				linked = true
				break
		if not linked:
			return false
	return true


static func _touches_network(state: Dictionary, x: int, y: int) -> bool:
	var network := _network_cells(state)
	for next in [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]:
		if network.has(CivUtil.cell_key(next)):
			return true
	return false


static func _network_cells(state: Dictionary) -> Dictionary:
	var network := {}
	for cell in _town_hall_cells(state):
		network[CivUtil.cell_key(cell)] = true
	var roads: Array = state.get("roads", [])
	var frontier: Array = []
	for cell in _town_hall_cells(state):
		frontier.append(cell)
	while not frontier.is_empty():
		var current: Array = frontier.pop_back()
		var x := int(current[0])
		var y := int(current[1])
		for next in [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]:
			var key := CivUtil.cell_key(next)
			if network.has(key):
				continue
			if not _is_working_road_at(roads, next):
				continue
			network[key] = true
			frontier.append(next)
	return network


static func _town_hall_cells(state: Dictionary) -> Array:
	var cells: Array = []
	for building in state.get("buildings", []):
		if str(building["type"]) != "town_hall":
			continue
		for cell in building["cells"]:
			cells.append(cell)
	return cells


static func _is_working_road_at(roads: Array, cell: Array) -> bool:
	var key := CivUtil.cell_key(cell)
	for road in roads:
		if str(road.get("status", "")) != "working":
			continue
		for road_cell in road["cells"]:
			if CivUtil.cell_key(road_cell) == key:
				return true
	return false
