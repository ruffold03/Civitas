extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var developed := _developed_chunk(game.snapshot)
	if developed.is_empty():
		failures.append("нет стартового чанка")
		_finish(failures)
		return
	if game.survey_order(int(developed[0]), int(developed[1]))["ok"]:
		failures.append("стартовый чанк уже изучен")
	var target := _neighbor_unsurveyed_chunk(game.snapshot)
	if target.is_empty():
		failures.append("нет соседнего чанка")
		_finish(failures)
		return
	if not game.survey_order(int(target[0]), int(target[1]))["ok"]:
		failures.append("приказ на (%d,%d)" % [target[0], target[1]])
	if game.survey_order(int(target[0]), int(target[1]))["ok"]:
		failures.append("дубль приказа")
	for _i in CivGeoSlice.SURVEY_TURNS:
		if not game.end_turn()["ok"]:
			failures.append("конец хода %d" % _i)
			break
	var chunk := _chunk(game.snapshot, int(target[0]), int(target[1]))
	if not bool(chunk.get("surveyed", false)):
		failures.append("чанк не изучен")
	if int(chunk.get("survey_timer", 0)) != 0:
		failures.append("таймер не сброшен")
	var revealed := false
	var map_cells: Dictionary = game.snapshot.get("map_cells", {})
	var x0 := int(target[0]) * CivGeoSlice.CHUNK
	var y0 := int(target[1]) * CivGeoSlice.CHUNK
	for y in range(y0, y0 + CivGeoSlice.CHUNK):
		for x in range(x0, x0 + CivGeoSlice.CHUNK):
			var record: Dictionary = CivSliceMap.visible_deposit(map_cells, x, y)
			if not record.is_empty():
				revealed = true
				break
		if revealed:
			break
	if not revealed and _any_deposit_in_chunk(map_cells, int(target[0]), int(target[1])):
		failures.append("залежи чанка не открыты")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("check_slice_survey: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _developed_chunk(snapshot: Dictionary) -> Array:
	for record in snapshot["chunks"]:
		if bool(record.get("developed", false)):
			return [int(record["x"]), int(record["y"])]
	return []


static func _neighbor_unsurveyed_chunk(snapshot: Dictionary) -> Array:
	var developed := _developed_chunk(snapshot)
	if developed.is_empty():
		return []
	var cx := int(developed[0])
	var cy := int(developed[1])
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


static func _chunk(snapshot: Dictionary, chunk_x: int, chunk_y: int) -> Dictionary:
	for record in snapshot["chunks"]:
		if int(record["x"]) == chunk_x and int(record["y"]) == chunk_y:
			return record
	return {}


static func _any_deposit_in_chunk(map_cells: Dictionary, chunk_x: int, chunk_y: int) -> bool:
	var x0 := chunk_x * CivGeoSlice.CHUNK
	var y0 := chunk_y * CivGeoSlice.CHUNK
	for y in range(y0, y0 + CivGeoSlice.CHUNK):
		for x in range(x0, x0 + CivGeoSlice.CHUNK):
			if map_cells.has(CivUtil.cell_key([x, y])):
				return true
	return false
