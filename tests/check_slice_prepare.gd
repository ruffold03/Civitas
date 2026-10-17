extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var foundation := str(game.snapshot["foundation"])
	if game.prepare_order([[2, 2]])["ok"]:
		failures.append("стартовая зона")
	var target := _find_plain_outside_start(foundation)
	if target.is_empty():
		failures.append("не нашли клетку для теста")
	if game.prepare_order([target])["ok"]:
		failures.append("без изучения чанка")
	game.survey_order(1, 0)
	for _i in CivGeoSlice.SURVEY_TURNS:
		game.end_turn()
	if not game.prepare_order([target])["ok"]:
		failures.append("приказ подготовки")
	var turns := CivGeoSlice.preparation_turns(CivGeoSlice.terrain_at(target[0], target[1], foundation))
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
	for y in CivGeoSlice.SIZE:
		for x in CivGeoSlice.SIZE:
			if CivSliceMap.is_start_zone_cell(x, y, foundation):
				continue
			var chunk: Array = CivGeoSlice.chunk_of(x, y)
			if int(chunk[0]) != 1:
				continue
			var terrain := CivGeoSlice.terrain_at(x, y, foundation)
			if CivGeoSlice.preparation_turns(terrain) == 2:
				return [x, y]
	return []
