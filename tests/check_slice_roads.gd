extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = CivSliceMatch.new_game("rome")
	var hall := _town_hall_cell(game.snapshot)
	if hall.is_empty():
		failures.append("нет ратуши")
		_finish(failures)
		return
	var target := _temple_site(game.snapshot, hall)
	if target.is_empty():
		failures.append("нет клетки для храма")
		_finish(failures)
		return
	_prep_outskirts(game.snapshot, target[0], target[1])
	var blocked: Dictionary = game.build_order("temple", [target])
	if blocked["ok"] or str(blocked.get("error", "")).find("дорог") < 0:
		failures.append("храм без дороги")
	var roads: Array = []
	var road_id := 90
	for x in range(hall[0] + 1, target[0]):
		roads.append(
			{
				"id": road_id,
				"cells": [[x, hall[1]]],
				"status": "working",
				"timer": 0,
				"born_turn": 0,
			}
		)
		road_id += 1
	game.snapshot["roads"] = roads
	if not game.build_order("temple", [target])["ok"]:
		failures.append("храм с дорогой")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("check_slice_roads: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _town_hall_cell(snapshot: Dictionary) -> Array:
	for building in snapshot["buildings"]:
		if str(building["type"]) == "town_hall":
			return building["cells"][0]
	return []


static func _temple_site(snapshot: Dictionary, hall: Array) -> Array:
	var foundation := str(snapshot["foundation"])
	var hx := int(hall[0])
	var hy := int(hall[1])
	for dx in range(3, 8):
		var x := hx + dx
		var y := hy
		if not CivGeoSlice.in_bounds(x, y):
			continue
		if CivSliceMap.is_start_zone_cell(x, y, foundation):
			continue
		if CivGeoSlice.terrain_at(x, y, foundation) != "plain":
			continue
		return [x, y]
	return []


static func _prep_outskirts(snapshot: Dictionary, x: int, y: int) -> void:
	var chunk: Array = CivGeoSlice.chunk_of(x, y)
	var cx := int(chunk[0])
	var cy := int(chunk[1])
	for record in snapshot["chunks"]:
		if int(record["x"]) == cx and int(record["y"]) == cy:
			record["surveyed"] = true
			record["survey_timer"] = 0
			break
	snapshot["cell_prep"][CivUtil.cell_key([x, y])] = {"prepared": true, "timer": 0}
