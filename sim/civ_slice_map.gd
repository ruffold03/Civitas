class_name CivSliceMap
extends RefCounted

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivUtil = preload("res://sim/civ_util.gd")

## Природные залежи на клетках среза. Остаток и видимость — в снимке партии (`map_cells`).

const DEPOSIT_RESOURCES: Array[String] = ["wood", "stone", "clay", "metal", "wine"]

const AMOUNT_RANGE := {
	"wood": {"min": 36, "max": 64},
	"stone": {"min": 28, "max": 52},
	"clay": {"min": 32, "max": 56},
	"metal": {"min": 20, "max": 36},
	"wine": {"min": 24, "max": 44},
}

const MARK := {
	"wood": "Д",
	"stone": "К",
	"clay": "Г",
	"metal": "М",
	"wine": "В",
}


static func generate_map_cells(foundation_id: String, map_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var cells := {}
	for y in CivGeoSlice.SIZE:
		for x in CivGeoSlice.SIZE:
			var terrain := CivGeoSlice.terrain_at(x, y, foundation_id)
			if not CivGeoSlice.allows_default_building(terrain):
				continue
			var resource := _roll_resource(foundation_id, terrain, x, y, rng)
			if resource == "":
				continue
			var span: Dictionary = AMOUNT_RANGE[resource]
			var left := rng.randi_range(int(span["min"]), int(span["max"]))
			cells[CivUtil.cell_key([x, y])] = {
				"resource": resource,
				"left": left,
				"revealed": false,
			}
	return cells


static func clear_cells_under_buildings(map_cells: Dictionary, buildings: Array) -> void:
	for building in buildings:
		for cell in building["cells"]:
			map_cells.erase(CivUtil.cell_key(cell))


static func reveal_start_zone(map_cells: Dictionary, foundation_id: String) -> void:
	var zone: Dictionary = CivGeoSlice.START_ZONE.get(foundation_id, CivGeoSlice.START_ZONE["latium_hills"])
	var x0 := int(zone["x"])
	var y0 := int(zone["y"])
	var w := int(zone["w"])
	var h := int(zone["h"])
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_reveal_at(map_cells, x, y)


static func reveal_chunk(map_cells: Dictionary, chunk_x: int, chunk_y: int) -> void:
	var x0 := chunk_x * CivGeoSlice.CHUNK
	var y0 := chunk_y * CivGeoSlice.CHUNK
	for y in range(y0, y0 + CivGeoSlice.CHUNK):
		for x in range(x0, x0 + CivGeoSlice.CHUNK):
			_reveal_at(map_cells, x, y)


static func cell_record(map_cells: Dictionary, x: int, y: int) -> Dictionary:
	return map_cells.get(CivUtil.cell_key([x, y]), {})


static func visible_deposit(map_cells: Dictionary, x: int, y: int) -> Dictionary:
	var record: Dictionary = cell_record(map_cells, x, y)
	if record.is_empty():
		return {}
	if not bool(record.get("revealed", false)):
		return {}
	if int(record.get("left", 0)) <= 0:
		return {}
	return record


static func count_deposits(map_cells: Dictionary, resource: String = "") -> int:
	var total := 0
	for key in map_cells:
		var record: Dictionary = map_cells[key]
		if int(record.get("left", 0)) <= 0:
			continue
		if resource == "" or str(record.get("resource", "")) == resource:
			total += 1
	return total


static func scenario_map_seed(scenario_id: String, extra: int = 0) -> int:
	return int(hash("%s:%d" % [scenario_id, extra])) & 0x7fffffff


static func is_start_zone_cell(x: int, y: int, foundation_id: String) -> bool:
	var zone: Dictionary = CivGeoSlice.START_ZONE.get(foundation_id, CivGeoSlice.START_ZONE["latium_hills"])
	var x0 := int(zone["x"])
	var y0 := int(zone["y"])
	return x >= x0 and x < x0 + int(zone["w"]) and y >= y0 and y < y0 + int(zone["h"])


static func prep_record(state: Dictionary, x: int, y: int) -> Dictionary:
	var prep: Dictionary = state.get("cell_prep", {})
	var key := CivUtil.cell_key([x, y])
	if not prep.has(key):
		return {}
	return prep[key]


static func is_prepared_for_build(state: Dictionary, x: int, y: int, foundation_id: String) -> bool:
	if is_start_zone_cell(x, y, foundation_id):
		return true
	var record: Dictionary = prep_record(state, x, y)
	return bool(record.get("prepared", false))


static func chunk_is_surveyed(state: Dictionary, chunk_x: int, chunk_y: int) -> bool:
	for record in state.get("chunks", []):
		if int(record["x"]) == chunk_x and int(record["y"]) == chunk_y:
			return bool(record.get("surveyed", false))
	return false


static func set_prep_timer(state: Dictionary, x: int, y: int, turns: int) -> void:
	if not state.has("cell_prep"):
		state["cell_prep"] = {}
	var key := CivUtil.cell_key([x, y])
	state["cell_prep"][key] = {"timer": turns, "prepared": false}


static func is_cell_occupied(state: Dictionary, x: int, y: int) -> bool:
	return is_cell_blocked(state, x, y)


static func is_cell_blocked(state: Dictionary, x: int, y: int) -> bool:
	var key := CivUtil.cell_key([x, y])
	for building in state.get("buildings", []):
		for cell in building["cells"]:
			if CivUtil.cell_key(cell) == key:
				return true
	for road in state.get("roads", []):
		for cell in road["cells"]:
			if CivUtil.cell_key(cell) == key:
				return true
	return false


static func _reveal_at(map_cells: Dictionary, x: int, y: int) -> void:
	var key := CivUtil.cell_key([x, y])
	if not map_cells.has(key):
		return
	map_cells[key]["revealed"] = true


static func _roll_resource(foundation_id: String, terrain: String, x: int, y: int, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = _base_weights(terrain)
	_apply_foundation_weights(weights, foundation_id, terrain, x, y)
	if CivGeoSlice.foot_of_mountain(x, y, foundation_id):
		weights["metal"] = int(weights.get("metal", 0)) + 14
		weights["stone"] = int(weights.get("stone", 0)) + 6
	var empty_weight := 88
	var total := empty_weight
	for resource in DEPOSIT_RESOURCES:
		total += int(weights.get(resource, 0))
	var roll := rng.randi_range(1, total)
	if roll <= empty_weight:
		return ""
	roll -= empty_weight
	for resource in DEPOSIT_RESOURCES:
		roll -= int(weights.get(resource, 0))
		if roll <= 0:
			return resource
	return ""


static func _base_weights(terrain: String) -> Dictionary:
	match terrain:
		"hill":
			return {"stone": 22, "clay": 12, "metal": 8, "wood": 6, "wine": 10}
		"coast":
			return {"wood": 14, "clay": 10, "wine": 16, "stone": 4, "metal": 2}
		_:
			return {"wood": 18, "clay": 14, "wine": 8, "stone": 6, "metal": 3}


static func _apply_foundation_weights(
	weights: Dictionary,
	foundation_id: String,
	terrain: String,
	_x: int,
	_y: int
) -> void:
	match foundation_id:
		"latium_hills":
			if terrain == "hill":
				weights["clay"] = int(weights.get("clay", 0)) + 12
				weights["stone"] = int(weights.get("stone", 0)) + 10
		"campanian_coast":
			weights["clay"] = int(weights.get("clay", 0)) + 14
			if terrain == "plain":
				weights["clay"] = int(weights.get("clay", 0)) + 6
		"apulian_harbor":
			weights["wood"] = int(weights.get("wood", 0)) + 12
			weights["wine"] = int(weights.get("wine", 0)) + 10
