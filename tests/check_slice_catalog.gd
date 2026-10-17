extends SceneTree

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	if CivSliceCatalog.building_ids().size() != 19:
		failures.append("ожидалось 19 типов (18 + ратуша), получено %d" % CivSliceCatalog.building_ids().size())
	var domus: Dictionary = CivSliceCatalog.building("domus")
	if int(domus["pop_capacity"]) != 6:
		failures.append("дом: вместимость")
	if int(CivSliceCatalog.VICTORY_POP) != 500:
		failures.append("победа: численность")
	for scenario_id in CivSliceScenario.scenario_ids():
		var snap: Dictionary = CivSliceScenario.opening_snapshot(scenario_id)
		if str(snap["scenario"]) != scenario_id:
			failures.append("сценарий %s: id в снимке" % scenario_id)
		if snap["stocks"].size() != CivSliceCatalog.RESOURCES.size():
			failures.append("сценарий %s: склады" % scenario_id)
	if failures.is_empty():
		print("check_slice_catalog: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
