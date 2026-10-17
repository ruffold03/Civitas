extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var seed := 4242
	var first: Dictionary = CivSliceMap.generate_map_cells("latium_hills", seed)
	var second: Dictionary = CivSliceMap.generate_map_cells("latium_hills", seed)
	if first.size() != second.size():
		failures.append("детерминизм: размер")
	for key in first:
		if str(second[key]["resource"]) != str(first[key]["resource"]):
			failures.append("детерминизм: ресурс %s" % key)
			break
	for key in first:
		var x := int(key.split(",")[0])
		var y := int(key.split(",")[1])
		if not CivGeoSlice.allows_default_building(CivGeoSlice.terrain_at(x, y, "latium_hills")):
			failures.append("залежь на нестроительной клетке")
			break
	var rome := CivSliceScenario.opening_snapshot("rome")
	if not rome.has("map_cells") or rome["map_cells"].is_empty():
		failures.append("рим: map_cells")
	for building in rome["buildings"]:
		if str(building["type"]) != "town_hall":
			continue
		for cell in building["cells"]:
			var hall_key := CivUtil.cell_key(cell)
			if rome["map_cells"].has(hall_key):
				failures.append("залежь под ратушей")
				break
	var revealed_start := false
	for key in rome["map_cells"]:
		var record: Dictionary = rome["map_cells"][key]
		if bool(record.get("revealed", false)):
			revealed_start = true
			break
	if not revealed_start:
		failures.append("рим: нет открытых залежей в старте")
	var latium_clay := 0
	var apulia_clay := 0
	var latium := CivSliceMap.generate_map_cells("latium_hills", 9001)
	var apulia := CivSliceMap.generate_map_cells("apulian_harbor", 9001)
	for key in latium:
		if str(latium[key]["resource"]) == "clay":
			latium_clay += 1
	for key in apulia:
		if str(apulia[key]["resource"]) == "clay":
			apulia_clay += 1
	if latium_clay <= apulia_clay:
		failures.append("латий: ожидалось больше глины, чем в апулии")
	for record in rome["chunks"]:
		if bool(record.get("developed", false)) and not bool(record.get("surveyed", false)):
			failures.append("освоенный чанк без survey")
	if failures.is_empty():
		print("check_slice_deposits: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
