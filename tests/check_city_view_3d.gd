extends SceneTree

const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const GLB := {
	"domus": "res://art/italy/classical/buildings/domus.glb",
	"town_hall": "res://art/italy/classical/buildings/town_hall.glb",
	"farm": "res://art/italy/classical/buildings/farm.glb",
}


func _initialize() -> void:
	var failures: Array[String] = []
	for type_id in GLB:
		if not FileAccess.file_exists(GLB[type_id]):
			failures.append("нет модели %s" % type_id)
	var packed: PackedScene = load("res://game/city_view_3d.tscn")
	if packed == null:
		failures.append("не загружается city_view_3d.tscn")
		_finish(failures)
		return
	var city: Node3D = packed.instantiate()
	root.add_child(city)
	var game = CivSliceMatch.new_game("rome")
	city.apply_snapshot(game.snapshot, true)
	if city.get_child_count() < 2:
		failures.append("пустая сцена после apply_snapshot")
	if city.snapshot.is_empty():
		failures.append("снимок не сохранён")
	var buildings: Node3D = city.get_node_or_null("World/Buildings")
	if buildings == null or buildings.get_child_count() == 0:
		failures.append("нет зданий")
	else:
		var glb_count := 0
		var smoke_count := 0
		for node in buildings.get_children():
			if bool(node.get_meta("from_glb", false)):
				glb_count += 1
			if node.find_child("StatusSmoke", true, false) != null:
				smoke_count += 1
		if glb_count < 3:
			failures.append("мало glb-зданий: %d" % glb_count)
		if smoke_count < 1:
			failures.append("нет дыма на working")
		_assign_first(game.snapshot, "domus", "idle")
		_assign_first(game.snapshot, "town_hall", "building")
		_assign_first(game.snapshot, "farm", "working")
		city.apply_snapshot(game.snapshot, true)
		if _find_status(buildings, "idle") == null:
			failures.append("нет силуэта idle")
		if _find_named(buildings, "StatusScaffold") == null:
			failures.append("нет лесов building")
		if _find_named(buildings, "StatusSmoke") == null:
			failures.append("нет дыма working после смены статуса")
	var terrain: Node3D = city.get_node_or_null("World/Terrain")
	if terrain == null or terrain.get_child_count() < 18 * 18:
		failures.append("рельеф неполный")
	if not FileAccess.file_exists("res://art/italy/classical/trees/stone_pine.glb"):
		failures.append("нет модели леса")
	var trees: Node3D = city.get_node_or_null("World/Trees")
	if trees == null or trees.get_child_count() == 0:
		failures.append("нет деревьев на лесу")
	else:
		var grove := trees.get_child(0) as MultiMeshInstance3D
		if grove == null or grove.multimesh == null or grove.multimesh.instance_count < 10:
			failures.append("роща слишком редкая")
	_finish(failures)


func _assign_first(snapshot: Dictionary, type_id: String, status: String) -> void:
	for building in snapshot.get("buildings", []):
		if str(building.get("type", "")) == type_id:
			building["status"] = status
			return


func _find_status(buildings: Node3D, status: String) -> Node:
	for node in buildings.get_children():
		if str(node.get_meta("status", "")) == status:
			if status == "idle" and node.find_child("StatusSilhouette", true, false) != null:
				return node
			if status == "building" and node.find_child("StatusScaffold", true, false) != null:
				return node
			if status == "working" and node.find_child("StatusSmoke", true, false) != null:
				return node
	return null


func _find_named(buildings: Node3D, node_name: String) -> Node:
	for node in buildings.get_children():
		var found := node.find_child(node_name, true, false)
		if found != null:
			return found
	return null


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("check_city_view_3d: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
