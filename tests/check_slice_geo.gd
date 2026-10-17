extends SceneTree

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	if CivGeoSlice.SIZE != 18 or CivGeoSlice.CHUNK != 6:
		failures.append("размер карты")
	if CivGeoSlice.all_chunks().size() != 9:
		failures.append("чанки")
	for foundation in CivGeoSlice.FOUNDATIONS:
		for y in CivGeoSlice.SIZE:
			for x in CivGeoSlice.SIZE:
				var terrain := CivGeoSlice.terrain_at(x, y, foundation)
				if terrain == "":
					failures.append("%s: пустая клетка %d,%d" % [foundation, x, y])
	if not CivGeoSlice.allows_default_building("plain"):
		failures.append("равнина")
	if CivGeoSlice.allows_default_building("river"):
		failures.append("река строится")
	if CivGeoSlice.terrain_at(7, 10, "latium_hills") != "river":
		failures.append("латий: тибр")
	var naples_coast := false
	for x in CivGeoSlice.SIZE:
		if CivGeoSlice.terrain_at(x, 15, "campanian_coast") == "coast":
			naples_coast = true
	if not naples_coast:
		failures.append("кампания: берег")
	if CivGeoSlice.terrain_at(13, 14, "apulian_harbor") != "sea":
		failures.append("апулия: гавань")
	var rome_zone := CivGeoSlice.start_zone_origin("latium_hills")
	if not CivGeoSlice.allows_default_building(CivGeoSlice.terrain_at(rome_zone.x + 2, rome_zone.y + 2, "latium_hills")):
		failures.append("рим: стартовая зона")
	var chunks := CivGeoSlice.initial_chunks("latium_hills")
	var developed := 0
	for record in chunks:
		if record["developed"]:
			developed += 1
	if developed != 1:
		failures.append("латий: один освоенный чанк")
	if failures.is_empty():
		print("check_slice_geo: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
