extends Node3D
class_name CityView3D

## Техсцена v0: ландшафт, плейсхолдеры зданий и дорог по снимку среза.

signal cell_clicked(x: int, y: int)

const GeoSlice = preload("res://sim/civ_geo_slice.gd")

const CELL := 1.0
const MAP_SIZE := GeoSlice.SIZE

const BUILDING_HEIGHT := {
	"domus": 0.65,
	"town_hall": 1.35,
	"sawmill": 0.55,
	"farm": 0.45,
	"well": 0.35,
	"cropland": 0.2,
}

const TYPE_COLOR := {
	"domus": Color("8d5a3c"),
	"town_hall": Color("b8860b"),
	"sawmill": Color("6b8f4e"),
	"farm": Color("a6844a"),
	"well": Color("6ea8c9"),
	"road": Color("6a5a48"),
}

const ORDER_COLORS := {
	"survey": Color("6a9ec8"),
	"prepare": Color("c9a04a"),
	"road": Color("6a5a48"),
	"build": Color("8d5a3c"),
}

@export var view_cells: int = 18

var snapshot: Dictionary = {}
var show_grid: bool = false
var selected_cells: Array = []
var draft_orders: Array = []
var _yaw_steps: int = 0
var _yaw_rad: float = 0.0
var _yaw_tween: Tween
var _zoom: float = 22.0
var _pan: Vector2 = Vector2(9.0, 9.0)
var _pan_dragging: bool = false
var _lmb_down: bool = false
var _lmb_press_pos: Vector2
var _last_mouse: Vector2

const ZOOM_MIN := 10.0
const ZOOM_MAX := 40.0
const ZOOM_STEP := 1.2
const CLICK_DRAG_THRESHOLD := 5.0
const GROUND_PLANE_Y := 0.0
const YAW_ANIM_SEC := 0.38

var _material_cache: Dictionary = {}


func _ready() -> void:
	_update_camera_transform()
	if not snapshot.is_empty():
		_rebuild_world()


func apply_snapshot(
	next_snapshot: Dictionary,
	grid_visible: bool = false,
	selected: Array = [],
	orders: Array = [],
) -> void:
	snapshot = next_snapshot
	show_grid = grid_visible
	selected_cells = selected
	draft_orders = orders
	if not is_node_ready():
		return
	_rebuild_world()


func set_show_grid(visible: bool) -> void:
	show_grid = visible
	_rebuild_grid_only()


func rotate_camera(step: int) -> void:
	if step == 0:
		return
	_yaw_steps = (_yaw_steps + step) % 4
	_start_yaw_animation(_yaw_rad + deg_to_rad(90.0 * float(step)))


func _rebuild_world() -> void:
	var terrain: Node3D = $World/Terrain
	var roads: Node3D = $World/Roads
	var buildings: Node3D = $World/Buildings
	var grid: Node3D = $World/Grid
	var selection: Node3D = $World/Selection
	_clear_children(terrain)
	_clear_children(roads)
	_clear_children(buildings)
	_clear_children(grid)
	_clear_children(selection)
	if snapshot.is_empty():
		return
	var foundation := str(snapshot.get("foundation", "latium_hills"))
	var limit := mini(view_cells, MAP_SIZE)
	for y in limit:
		for x in limit:
			terrain.add_child(_make_terrain_tile(x, y, foundation))
	_build_roads(foundation, roads)
	_build_buildings(buildings)
	_rebuild_grid_only()
	_rebuild_selection(selection)


func _rebuild_grid_only() -> void:
	var grid: Node3D = $World/Grid
	_clear_children(grid)
	if not show_grid or snapshot.is_empty():
		return
	var limit := mini(view_cells, MAP_SIZE)
	for y in limit:
		for x in limit:
			_add_cell_grid_borders(grid, x, y)


func _rebuild_selection(selection: Node3D) -> void:
	var painted: Dictionary = {}
	for cell in selected_cells:
		var x := int(cell[0])
		var y := int(cell[1])
		var key := "%d,%d" % [x, y]
		if painted.has(key):
			continue
		painted[key] = true
		selection.add_child(_make_selection_tile(x, y, Color(1.0, 0.95, 0.55, 0.55)))
	for order in draft_orders:
		var kind := str(order.get("kind", "build"))
		var color: Color = ORDER_COLORS.get(kind, Color("8d5a3c"))
		color.a = 0.45
		if kind == "survey":
			continue
		var cells: Array = order.get("cells", [])
		if cells.is_empty() and order.has("chunk_x"):
			continue
		for cell in cells:
			var x := int(cell[0])
			var y := int(cell[1])
			var key := "%d,%d" % [x, y]
			if painted.has(key):
				continue
			painted[key] = true
			selection.add_child(_make_selection_tile(x, y, color))


func _make_terrain_tile(x: int, y: int, foundation: String) -> Node3D:
	var terrain := GeoSlice.terrain_at(x, y, foundation)
	var body := StaticBody3D.new()
	body.position = Vector3.ZERO
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	var top := _terrain_top_height(terrain)
	var thickness := 0.42 if top >= 0.0 else 0.28
	box.size = Vector3(CELL, thickness, CELL)
	mesh_inst.mesh = box
	mesh_inst.material_override = _terrain_material(terrain)
	mesh_inst.position = Vector3(x * CELL + CELL * 0.5, top - thickness * 0.5, y * CELL + CELL * 0.5)
	body.add_child(mesh_inst)
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	shape.position = mesh_inst.position
	body.add_child(shape)
	if terrain == "sea" or terrain == "river":
		body.add_child(_make_water_cap(x, y, top))
	return body


func _make_water_cap(x: int, y: int, base_top: float) -> MeshInstance3D:
	var water := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(CELL, 0.03, CELL)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4a8ab0", 0.88)
	mat.roughness = 0.12
	mat.metallic = 0.05
	water.material_override = mat
	water.position = Vector3(x * CELL + CELL * 0.5, base_top + 0.015, y * CELL + CELL * 0.5)
	return water


func _add_cell_grid_borders(parent: Node3D, x: int, y: int) -> void:
	var top := _ground_height_at(x, y) + 0.05
	var thickness := 0.035
	var depth := 0.06
	var mat := _line_material()
	var cx := x * CELL + CELL * 0.5
	var cz := y * CELL + CELL * 0.5
	parent.add_child(_grid_line(Vector3(cx, top, y * CELL), Vector3(CELL, thickness, depth), mat))
	parent.add_child(_grid_line(Vector3(cx, top, y * CELL + CELL), Vector3(CELL, thickness, depth), mat))
	parent.add_child(_grid_line(Vector3(x * CELL, top, cz), Vector3(depth, thickness, CELL), mat))
	parent.add_child(_grid_line(Vector3(x * CELL + CELL, top, cz), Vector3(depth, thickness, CELL), mat))


func _grid_line(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = center
	return mesh_inst


func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_selection_tile(x: int, y: int, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL * 0.94, 0.05, CELL * 0.94)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	var top := _ground_height_at(x, y) + 0.06
	mesh_inst.position = Vector3(x * CELL + CELL * 0.5, top, y * CELL + CELL * 0.5)
	return mesh_inst


func _terrain_top_height(terrain: String) -> float:
	match terrain:
		"hill":
			return 0.38
		"coast":
			return 0.12
		"sea", "river":
			return -0.08
		"mountain":
			return 0.55
		_:
			return 0.0


func _terrain_material(terrain: String) -> StandardMaterial3D:
	if _material_cache.has(terrain):
		return _material_cache[terrain]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	match terrain:
		"sea", "river":
			mat.albedo_color = Color("3d6f8a")
		"mountain":
			mat.albedo_color = Color("5c564e")
		"hill":
			mat.albedo_color = Color("a89262")
		"coast":
			mat.albedo_color = Color("d4c48a")
		_:
			mat.albedo_color = Color("c4a574")
	_material_cache[terrain] = mat
	return mat


func _build_roads(_foundation: String, roads: Node3D) -> void:
	for road in snapshot.get("roads", []):
		for cell in road["cells"]:
			var x := int(cell[0])
			var y := int(cell[1])
			roads.add_child(
				_make_block(x, y, 1, 0.06, 1, TYPE_COLOR["road"], str(road.get("status", "working")))
			)


func _build_buildings(buildings: Node3D) -> void:
	for building in snapshot.get("buildings", []):
		var type_id := str(building["type"])
		var cells: Array = building["cells"]
		if cells.is_empty():
			continue
		var bounds := _cell_bounds(cells)
		var footprint := Vector2i(bounds["w"], bounds["h"])
		var anchor := Vector2i(int(bounds["min_x"]), int(bounds["min_y"]))
		var height: float = float(BUILDING_HEIGHT.get(type_id, 0.55))
		var color: Color = TYPE_COLOR.get(type_id, Color("9a9080"))
		var node := _make_footprint_block(
			anchor.x,
			anchor.y,
			footprint.x,
			footprint.y,
			height,
			color,
			str(building.get("status", "working")),
		)
		buildings.add_child(node)


func _make_footprint_block(
	anchor_x: int,
	anchor_y: int,
	width_cells: int,
	depth_cells: int,
	height: float,
	color: Color,
	status: String,
) -> Node3D:
	return _make_block(anchor_x, anchor_y, width_cells, height, depth_cells, color, status)


func _make_block(
	anchor_x: int,
	anchor_y: int,
	width_cells: int,
	height: float,
	depth_cells: int,
	color: Color,
	status: String,
) -> Node3D:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width_cells * CELL * 0.88, height, depth_cells * CELL * 0.88)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	match status:
		"building":
			mat.albedo_color = color.lightened(0.25)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.65
		"idle":
			mat.albedo_color = color.darkened(0.25)
		_:
			pass
	mesh_inst.material_override = mat
	var cx := anchor_x * CELL + width_cells * CELL * 0.5
	var cz := anchor_y * CELL + depth_cells * CELL * 0.5
	var ground := _rect_ground_height(anchor_x, anchor_y, width_cells, depth_cells)
	mesh_inst.position = Vector3(cx, ground + height * 0.5, cz)
	root.add_child(mesh_inst)
	return root


func _ground_height_at(x: int, y: int) -> float:
	if snapshot.is_empty():
		return 0.0
	var foundation := str(snapshot.get("foundation", "latium_hills"))
	return _terrain_top_height(GeoSlice.terrain_at(x, y, foundation))


func _rect_ground_height(anchor_x: int, anchor_y: int, width_cells: int, depth_cells: int) -> float:
	var top := 0.0
	for dy in depth_cells:
		for dx in width_cells:
			top = maxf(top, _ground_height_at(anchor_x + dx, anchor_y + dy))
	return top


func _cell_bounds(cells: Array) -> Dictionary:
	var min_x := 9999
	var min_y := 9999
	var max_x := -1
	var max_y := -1
	for cell in cells:
		var x := int(cell[0])
		var y := int(cell[1])
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
	return {
		"min_x": min_x,
		"min_y": min_y,
		"w": max_x - min_x + 1,
		"h": max_y - min_y + 1,
	}


func _clear_children(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()


func _update_camera_transform() -> void:
	if not is_node_ready():
		return
	var pivot: Node3D = $CameraPivot
	var camera: Camera3D = _camera()
	pivot.rotation.y = _yaw_rad
	pivot.position = Vector3(_pan.x, 0.0, _pan.y)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom
	camera.position = Vector3(14.0, 18.0, 14.0)
	camera.rotation_degrees = Vector3(-35.264, 45.0, 0.0)


func _start_yaw_animation(target_rad: float) -> void:
	if not is_node_ready():
		_yaw_rad = target_rad
		return
	if _yaw_tween != null and _yaw_tween.is_valid():
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.set_ease(Tween.EASE_OUT)
	_yaw_tween.set_trans(Tween.TRANS_CUBIC)
	_yaw_tween.tween_method(_apply_yaw_rad, _yaw_rad, target_rad, YAW_ANIM_SEC)


func _apply_yaw_rad(rad: float) -> void:
	_yaw_rad = rad
	_update_camera_transform()


func _camera() -> Camera3D:
	return $CameraPivot/Camera3D


func _ground_point_under_screen(screen_pos: Vector2):
	if not is_node_ready():
		return null
	var camera: Camera3D = _camera()
	var ray_o := camera.project_ray_origin(screen_pos)
	var ray_d := camera.project_ray_normal(screen_pos)
	if absf(ray_d.y) < 0.0001:
		return null
	var t := (GROUND_PLANE_Y - ray_o.y) / ray_d.y
	if t < 0.0:
		return null
	return ray_o + ray_d * t


func _zoom_at_screen(screen_pos: Vector2, delta_zoom: float) -> void:
	var before = _ground_point_under_screen(screen_pos)
	_zoom = clampf(_zoom + delta_zoom, ZOOM_MIN, ZOOM_MAX)
	_update_camera_transform()
	if before == null:
		return
	var after = _ground_point_under_screen(screen_pos)
	if after == null:
		return
	_pan.x += before.x - after.x
	_pan.y += before.z - after.z
	_update_camera_transform()


func _apply_pan_delta(delta: Vector2) -> void:
	var camera: Camera3D = _camera()
	var scale := _zoom * 0.0025
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	var move := right * (-delta.x * scale) + forward * (delta.y * scale)
	_pan.x += move.x
	_pan.y += move.z
	_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_screen(event.position, -ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_screen(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = event.pressed
			_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_lmb_down = true
				_pan_dragging = false
				_lmb_press_pos = event.position
				_last_mouse = event.position
			else:
				if _lmb_down and not _pan_dragging:
					_pick_cell(_lmb_press_pos)
				_lmb_down = false
				_pan_dragging = false
	if event is InputEventMouseMotion:
		if _lmb_down and not _pan_dragging:
			if event.position.distance_to(_lmb_press_pos) >= CLICK_DRAG_THRESHOLD:
				_pan_dragging = true
		if _pan_dragging:
			var delta: Vector2 = event.position - _last_mouse
			_last_mouse = event.position
			_apply_pan_delta(delta)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				rotate_camera(-1)
			KEY_E:
				rotate_camera(1)
			KEY_G:
				set_show_grid(not show_grid)


func _pick_cell(screen_pos: Vector2) -> void:
	if not is_node_ready():
		return
	var camera: Camera3D = _camera()
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := origin + direction * 400.0
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = 1
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	var x := clampi(int(floor(pos.x / CELL)), 0, MAP_SIZE - 1)
	var y := clampi(int(floor(pos.z / CELL)), 0, MAP_SIZE - 1)
	cell_clicked.emit(x, y)
