extends SceneTree

const CivSliceMatch = preload("res://sim/civ_slice_match.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var packed: PackedScene = load("res://game/city_view_3d.tscn")
	if packed == null:
		failures.append("не загружается city_view_3d.tscn")
	else:
		var city: Node3D = packed.instantiate()
		root.add_child(city)
		var game = CivSliceMatch.new_game("rome")
		city.apply_snapshot(game.snapshot, true)
		if city.get_child_count() < 2:
			failures.append("пустая сцена после apply_snapshot")
		if city.snapshot.is_empty():
			failures.append("снимок не сохранён")
	if failures.is_empty():
		print("check_city_view_3d: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
