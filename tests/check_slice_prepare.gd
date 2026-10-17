extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var foundation := str(game.snapshot["foundation"])
	var origin := CivGeoSlice.start_zone_origin(foundation)
	var start_probe := [origin.x + 2, origin.y + 2]
	if game.prepare_order([start_probe])["ok"]:
		failures.append("стартовая зона")
	var target := _find_plain_outside_start(foundation)
	if target.is_empty():
		failures.append("не нашли клетку для теста")
	elif game.prepare_order([target])["ok"]:
		failures.append("без изучения чанка")
	else:
		var survey_chunk := _neighbor_unsurveyed_chunk(game.snapshot)
		if survey_chunk.is_empty():
			failures.append("нет чанка для изучения")
		else:
			game.survey_order(int(survey_chunk[0]), int(survey_chunk[1]))
			for _i in CivGeoSlice.SURVEY_TURNS:
				game.end_turn()
			if not game.prepare_order([target])["ok"]:
				failures.append("приказ подготовки")
			var turns := CivGeoSlice.preparation_turns(
				CivGeoSlice.terrain_at(target[0], target[1], foundation)
			)
			for _i in turns:
				game.end_turn()
			if not CivSliceMap.is_prepared_for_build(game.snapshot, target[0], target[1], foundation):
				failures.append("клетка не подготовлена")
	if failures.is_empty():
		print("check_slice_prepare: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _find_plain_outside_start(foundation: String) -> Array:
	var survey_chunk := _neighbor_unsurveyed_chunk_for_foundation(foundation)
	if survey_chunk.is_empty():
		return []
	var cx := int(survey_chunk[0])
	var cy := int(survey_chunk[1])
	var x0 := cx * CivGeoSlice.CHUNK
	var y0 := cy * CivGeoSlice.CHUNK
	for y in range(y0, y0 + CivGeoSlice.CHUNK):
		for x in range(x0, x0 + CivGeoSlice.CHUNK):
			if CivSliceMap.is_start_zone_cell(x, y, foundation):
				continue
			var terrain := CivGeoSlice.terrain_at(x, y, foundation)
			if CivGeoSlice.preparation_turns(terrain) == 2:
				return [x, y]
	return []


static func _neighbor_unsurveyed_chunk(snapshot: Dictionary) -> Array:
	for record in snapshot["chunks"]:
		if not bool(record.get("developed", false)):
			continue
		var cx := int(record["x"])
		var cy := int(record["y"])
		for offset in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
			var nx := cx + int(offset[0])
			var ny := cy + int(offset[1])
			if nx < 0 or ny < 0 or nx >= 3 or ny >= 3:
				continue
			var neighbor := _chunk(snapshot, nx, ny)
			if neighbor.is_empty() or bool(neighbor.get("surveyed", false)):
				continue
			return [nx, ny]
	return []


static func _neighbor_unsurveyed_chunk_for_foundation(foundation: String) -> Array:
	var zone: Dictionary = CivGeoSlice.start_zone(foundation)
	var developed := CivGeoSlice.chunk_of(int(zone["x"]), int(zone["y"]))
	var cx := int(developed[0])
	var cy := int(developed[1])
	for offset in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
		var nx := cx + int(offset[0])
		var ny := cy + int(offset[1])
		if nx >= 0 and ny >= 0 and nx < 3 and ny < 3:
			return [nx, ny]
	return []


static func _chunk(snapshot: Dictionary, chunk_x: int, chunk_y: int) -> Dictionary:
	for record in snapshot["chunks"]:
		if int(record["x"]) == chunk_x and int(record["y"]) == chunk_y:
			return record
	return {}
