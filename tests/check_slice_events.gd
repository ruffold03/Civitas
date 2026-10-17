extends SceneTree

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	_advance_to_turn(game, 25)
	if str(game.snapshot.get("current_event", "")) != "settlers":
		failures.append("на 25 ходу ждём поселенцев")
	else:
		var pop_before := int(game.snapshot["pop"])
		if not game.choose_event("accept")["ok"]:
			failures.append("выбор принять")
		elif not game.end_turn()["ok"]:
			failures.append("ход после события")
		elif int(game.snapshot["pop"]) <= pop_before:
			failures.append("бонус населения")
	if failures.is_empty():
		print("check_slice_events: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _advance_to_turn(game: CivSliceMatch, target: int) -> void:
	while int(game.snapshot["turn"]) < target:
		_clear_event(game)
		if not game.end_turn()["ok"]:
			push_error("ход %d" % int(game.snapshot["turn"]))
			return


static func _clear_event(game: CivSliceMatch) -> void:
	while str(game.snapshot.get("current_event", "")) != "":
		var event_id := str(game.snapshot["current_event"])
		var options: Dictionary = CivSliceCatalog.event(event_id)["options"]
		var chosen := false
		for option_id in options:
			if game.choose_event(str(option_id))["ok"]:
				chosen = true
				break
		if not chosen:
			push_error("нет варианта для %s" % event_id)
			return
		if not game.end_turn()["ok"]:
			return
