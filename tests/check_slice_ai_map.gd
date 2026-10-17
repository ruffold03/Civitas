extends SceneTree

const CivSliceAiMap = preload("res://sim/civ_slice_ai_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var snap: Dictionary = CivSliceScenario.opening_snapshot("rome")
	var cells: Array = CivSliceAiMap.find_build_cells(snap, "domus")
	if cells.size() != 1:
		failures.append("дом: ожидалась 1 клетка, %d" % cells.size())
	var game = CivSliceMatch.new_game("rome")
	for _i in 40:
		game.end_turn()
		if game.snapshot["mode"] != "play":
			break
	for city in game.snapshot["ai_cities"].values():
		var count := int(city["buildings"].size())
		if count < 10:
			failures.append("ИИ слишком мало построек на карте: %d" % count)
		for building in city["buildings"]:
			var bcells: Array = building["cells"]
			if bcells.is_empty():
				failures.append("здание без клеток")
				break
			if int(bcells[0][0]) > 50:
				failures.append("подозрительные координаты ИИ")
				break
	if failures.is_empty():
		print("check_slice_ai_map: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
