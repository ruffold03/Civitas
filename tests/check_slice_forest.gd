extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceTurn = preload("res://sim/civ_slice_turn.gd")
const CivUtil = preload("res://sim/civ_util.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	if CivGeoSlice.allows_default_building("forest"):
		failures.append("лес не строится")
	if _largest_forest("latium_hills") < 40:
		failures.append("латий: лес не массив")
	if _largest_forest("campanian_coast") < 40:
		failures.append("кампания: лес не массив")
	var game = CivSliceMatch.new_game("rome")
	var cell := _any_forest(game.snapshot)
	if cell.is_empty():
		failures.append("нет доступного леса на карте рима")
	else:
		var chunk: Array = CivGeoSlice.chunk_of(int(cell[0]), int(cell[1]))
		for record in game.snapshot["chunks"]:
			if int(record["x"]) == int(chunk[0]) and int(record["y"]) == int(chunk[1]):
				record["surveyed"] = true
				record["survey_timer"] = 0
		if not game.chop_order([cell])["ok"]:
			failures.append("приказ рубки")
		var wood_before := int(game.snapshot["stocks"]["wood"])
		var draft: Dictionary = CivUtil.deep_copy(game.draft)
		game.snapshot["turn"] = 2
		var after: Dictionary = CivSliceTurn.resolve(game.snapshot, draft)
		if CivSliceMap.terrain_at_state(after, int(cell[0]), int(cell[1]), "latium_hills") != "plain":
			failures.append("после рубки не равнина")
		var gained := int(after["stocks"]["wood"]) - wood_before
		if gained < CivGeoSlice.FOREST_CHOP_WOOD:
			failures.append("дерево с рубки: %d" % gained)
		var chopped := false
		for note in after.get("notifications", []):
			if str(note.get("kind", "")) == "forest_chop":
				chopped = true
				break
		if not chopped:
			failures.append("нет записи рубки")
	if failures.is_empty():
		print("check_slice_forest: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)


static func _any_forest(snapshot: Dictionary) -> Array:
	var foundation := str(snapshot["foundation"])
	for y in CivGeoSlice.SIZE:
		for x in CivGeoSlice.SIZE:
			if CivSliceMap.terrain_at_state(snapshot, x, y, foundation) == "forest":
				return [x, y]
	return []


static func _largest_forest(foundation: String) -> int:
	var seen := {}
	var best := 0
	for y in CivGeoSlice.SIZE:
		for x in CivGeoSlice.SIZE:
			var key := "%d,%d" % [x, y]
			if seen.has(key):
				continue
			if CivGeoSlice.terrain_at(x, y, foundation) != "forest":
				continue
			var size := 0
			var stack: Array = [[x, y]]
			while not stack.is_empty():
				var cell: Array = stack.pop_back()
				var cx := int(cell[0])
				var cy := int(cell[1])
				var ckey := "%d,%d" % [cx, cy]
				if seen.has(ckey):
					continue
				if CivGeoSlice.terrain_at(cx, cy, foundation) != "forest":
					continue
				seen[ckey] = true
				size += 1
				for next in [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]]:
					stack.append(next)
			best = maxi(best, size)
	return best
