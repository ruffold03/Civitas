extends SceneTree

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	if game.build_order("forum", [[3, 3]])["ok"]:
		failures.append("форум без письмена")
	if not game.research_order("writing")["ok"]:
		failures.append("выбор письмена")
	for _i in 20:
		_clear_event(game)
		game.end_turn()
	if not CivSliceTech.is_researched(game.snapshot, "writing"):
		failures.append("письмено не изучено")
	var after: Dictionary = game.build_order("forum", [[3, 3]])
	if not after["ok"] and str(after.get("error", "")).find("технолог") >= 0:
		failures.append("форум всё ещё закрыт технологией")
	if failures.is_empty():
		print("check_slice_tech: OK")
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
				game.end_turn()
				return
