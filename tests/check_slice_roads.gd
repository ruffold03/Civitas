extends SceneTree

const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	_prep_outskirts(game.snapshot, 6, 2)
	var blocked: Dictionary = game.build_order("temple", [[6, 2]])
	if blocked["ok"] or str(blocked.get("error", "")).find("дорог") < 0:
		failures.append("храм без дороги")
	game.snapshot["roads"] = [
		{"id": 91, "cells": [[3, 2]], "status": "working", "timer": 0, "born_turn": 0},
		{"id": 92, "cells": [[4, 2]], "status": "working", "timer": 0, "born_turn": 0},
		{"id": 93, "cells": [[5, 2]], "status": "working", "timer": 0, "born_turn": 0},
	]
	if not game.build_order("temple", [[6, 2]])["ok"]:
		failures.append("храм с дорогой")
	if failures.is_empty():
		print("check_slice_roads: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _prep_outskirts(snapshot: Dictionary, x: int, y: int) -> void:
	for record in snapshot["chunks"]:
		if int(record["x"]) == 1 and int(record["y"]) == 0:
			record["surveyed"] = true
			record["survey_timer"] = 0
	snapshot["cell_prep"][CivUtil.cell_key([x, y])] = {"prepared": true, "timer": 0}
