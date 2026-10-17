extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var foundation := str(game.snapshot["foundation"])
	var cell := _free_cell(game.snapshot, foundation)
	if cell.is_empty():
		failures.append("нет свободной клетки")
	else:
		var placed: Dictionary = game.build_order("domus", [cell])
		if not placed["ok"]:
			failures.append("приказ дом: %s" % str(placed.get("error", "")))
		game.end_turn()
		var built := _find_building(game.snapshot, "domus", cell)
		if built.is_empty():
			failures.append("дом не появился")
		elif str(built["status"]) != "building":
			failures.append("дом не строится")
		game.end_turn()
		built = _find_building(game.snapshot, "domus", cell)
		if built.is_empty() or str(built["status"]) != "working":
			failures.append("дом не достроен")
	if failures.is_empty():
		print("check_slice_build: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _free_cell(snapshot: Dictionary, foundation: String) -> Array:
	var occupied := {}
	for building in snapshot["buildings"]:
		for c in building["cells"]:
			occupied[CivUtil.cell_key(c)] = true
	for y in range(0, 6):
		for x in range(0, 6):
			if not CivSliceMap.is_start_zone_cell(x, y, foundation):
				continue
			if occupied.has(CivUtil.cell_key([x, y])):
				continue
			var terrain := CivGeoSlice.terrain_at(x, y, foundation)
			if not CivGeoSlice.allows_default_building(terrain):
				continue
			return [x, y]
	return []


static func _find_building(snapshot: Dictionary, type_id: String, cell: Array) -> Dictionary:
	var key := CivUtil.cell_key(cell)
	for building in snapshot["buildings"]:
		if str(building["type"]) != type_id:
			continue
		for c in building["cells"]:
			if CivUtil.cell_key(c) == key:
				return building
	return {}
