extends SceneTree

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceAi = preload("res://sim/civ_slice_ai.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var snap: Dictionary = game.snapshot
	if not snap.has("ai_cities"):
		failures.append("нет ai_cities в снимке")
	elif snap["ai_cities"].size() != 2:
		failures.append("ожидалось 2 ИИ-города, получено %d" % snap["ai_cities"].size())
	for neighbor in snap.get("ai_cities", {}).values():
		var goal := str(neighbor.get("victory_goal", ""))
		if goal != "population" and goal != "economy":
			failures.append("некорректная цель ИИ: %s" % goal)
		if not neighbor.has("map_cells") or neighbor["map_cells"].is_empty():
			failures.append("ИИ без карты map_cells")
		if str(neighbor.get("foundation", "")) == "":
			failures.append("ИИ без foundation")
	var start_pop := int(snap["ai_cities"]["neapolis"]["pop"])
	for _i in 30:
		_clear_event(game)
		game.end_turn()
		snap = game.snapshot
		if snap["mode"] != "play":
			break
	var ai_pop := int(snap["ai_cities"]["neapolis"]["pop"])
	if ai_pop == start_pop and snap["mode"] == "play":
		failures.append("ИИ Неаполя не изменил численность за 30 ходов")
	var summary: Dictionary = CivSliceAi.city_visible_summary(snap["ai_cities"]["tarentum"])
	if not summary.has("stocks"):
		failures.append("сводка ИИ без складов")
	if failures.is_empty():
		print("check_slice_ai: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _clear_event(game: CivSliceMatch) -> void:
	while str(game.snapshot.get("current_event", "")) != "":
		var event_id := str(game.snapshot["current_event"])
		var options: Dictionary = CivSliceCatalog.event(event_id)["options"]
		for option_id in options:
			if game.choose_event(str(option_id))["ok"]:
				return
