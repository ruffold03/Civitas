extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	if game.survey_order(0, 0)["ok"]:
		failures.append("стартовый чанк уже изучен")
	if not game.survey_order(1, 0)["ok"]:
		failures.append("приказ на (1,0)")
	if game.survey_order(1, 0)["ok"]:
		failures.append("дубль приказа")
	for _i in CivGeoSlice.SURVEY_TURNS:
		if not game.end_turn()["ok"]:
			failures.append("конец хода %d" % _i)
			break
	var chunk := _chunk(game.snapshot, 1, 0)
	if not bool(chunk.get("surveyed", false)):
		failures.append("чанк не изучен")
	if int(chunk.get("survey_timer", 0)) != 0:
		failures.append("таймер не сброшен")
	var revealed := false
	var map_cells: Dictionary = game.snapshot.get("map_cells", {})
	for y in range(0, CivGeoSlice.CHUNK):
		for x in range(CivGeoSlice.CHUNK, CivGeoSlice.CHUNK * 2):
			var record: Dictionary = CivSliceMap.visible_deposit(map_cells, x, y)
			if not record.is_empty():
				revealed = true
				break
		if revealed:
			break
	if not revealed and _any_deposit_in_chunk(map_cells, 1, 0):
		failures.append("залежи чанка не открыты")
	if failures.is_empty():
		print("check_slice_survey: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


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
