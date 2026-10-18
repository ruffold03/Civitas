class_name CivSliceScenario
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivUtil = preload("res://sim/civ_util.gd")

const SCENARIOS := {
	"rome": {
		"name": "Рим",
		"foundation": "latium_hills",
		"pop": 40,
		"loyalty": 50,
		"stocks": {
			"food": 22,
			"wood": 22,
			"stone": 10,
			"clay": 8,
			"metal": 4,
			"wine": 0,
			"money": 0,
		},
	},
	"neapolis": {
		"name": "Неаполь",
		"foundation": "campanian_coast",
		"pop": 35,
		"loyalty": 52,
		"stocks": {
			"food": 24,
			"wood": 18,
			"stone": 6,
			"clay": 10,
			"metal": 2,
			"wine": 6,
			"money": 0,
		},
	},
	"tarentum": {
		"name": "Тарент",
		"foundation": "apulian_harbor",
		"pop": 32,
		"loyalty": 48,
		"stocks": {
			"food": 18,
			"wood": 24,
			"stone": 4,
			"clay": 6,
			"metal": 2,
			"wine": 10,
			"money": 0,
		},
	},
}


static func has_scenario(scenario_id: String) -> bool:
	return SCENARIOS.has(scenario_id)


static func opening_snapshot(scenario_id: String) -> Dictionary:
	assert(has_scenario(scenario_id))
	var scenario: Dictionary = SCENARIOS[scenario_id]
	var foundation := str(scenario["foundation"])
	var origin := CivGeoSlice.start_zone_origin(foundation)
	var buildings: Array = []
	var next_id := 1
	for cell in _domus_layout(scenario_id):
		buildings.append(_placed(next_id, "domus", [_offset_cell(cell, origin)]))
		next_id += 1
	buildings.append(_placed(next_id, "well", [_offset_cell([1, 1], origin)]))
	next_id += 1
	buildings.append(_placed(next_id, "town_hall", [_offset_cell([2, 2], origin)]))
	next_id += 1
	for extra in _starter_industry_layout():
		var cells: Array = []
		for cell in extra["cells"]:
			cells.append(_offset_cell(cell, origin))
		buildings.append(_placed(next_id, str(extra["type"]), cells))
		next_id += 1
	var map_seed := CivSliceMap.scenario_map_seed(scenario_id)
	var map_cells: Dictionary = CivSliceMap.generate_map_cells(foundation, map_seed)
	CivSliceMap.clear_cells_under_buildings(map_cells, buildings)
	CivSliceMap.reveal_start_zone(map_cells, foundation)
	return {
		"turn": 1,
		"era": CivSliceCatalog.ERA,
		"country": CivSliceCatalog.COUNTRY_ID,
		"scenario": scenario_id,
		"foundation": foundation,
		"mode": "play",
		"victory_id": "population_slice",
		"pop": int(scenario["pop"]),
		"pop_capacity": _pop_capacity(buildings),
		"loyalty": int(scenario["loyalty"]),
		"loyalty_sources": [],
		"stocks": CivUtil.deep_copy(scenario["stocks"]),
		"storage": CivUtil.deep_copy(CivSliceCatalog.BASE_STORAGE),
		"science": 0,
		"prestige": 0,
		"buildings": buildings,
		"roads": [],
		"map_seed": map_seed,
		"map_cells": map_cells,
		"cell_terrain": {},
		"cell_prep": {},
		"chunks": CivGeoSlice.initial_chunks(foundation),
		"effects": [],
		"current_event": "",
		"resolved_events": [],
		"notifications": [],
		"next_id": next_id,
		"technologies": [],
		"research": "",
		"tech_progress": {},
	}


static func scenario_ids() -> Array:
	return SCENARIOS.keys()


static func _pop_capacity(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		total += int(CivSliceCatalog.building(building["type"])["pop_capacity"])
	return total


static func _placed(id_number: int, type_id: String, cells: Array) -> Dictionary:
	return {
		"id": id_number,
		"type": type_id,
		"cells": cells,
		"status": "working",
		"timer": 0,
		"born_turn": 0,
	}


static func _starter_industry_layout() -> Array:
	return [
		{"type": "farm", "cells": [[0, 3], [1, 3]]},
		{"type": "sawmill", "cells": [[3, 3], [4, 3]]},
	]


static func _domus_layout(scenario_id: String) -> Array:
	if scenario_id == "rome":
		return [[0, 0], [1, 0], [3, 0], [4, 0], [0, 1], [4, 1]]
	var count := 5
	if scenario_id == "tarentum":
		count = 4
	var cells: Array = []
	for i in count:
		cells.append([i, 0])
	return cells


static func _offset_cell(cell: Array, origin: Vector2i) -> Array:
	return [int(cell[0]) + origin.x, int(cell[1]) + origin.y]
