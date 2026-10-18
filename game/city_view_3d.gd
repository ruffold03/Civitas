extends Node3D
class_name CityView3D

## Техсцена: ландшафт по terrain_at, здания из art/italy/classical/buildings/<type>.glb.

signal cell_clicked(x: int, y: int)

const GeoSlice = preload("res://sim/civ_geo_slice.gd")
const SliceMap = preload("res://sim/civ_slice_map.gd")

const CELL := 1.0
const MAP_SIZE := GeoSlice.SIZE
const RIVER_WATER := -0.20
const SEA_WATER := -0.24
const TERRAIN_BOTTOM := -0.82
const WATER_SHADER_PATH := "res://art/italy/classical/water.gdshader"
const GROUND_DIR := "res://art/italy/classical/ground"
const GROUND_TEXTURE := {
	"plain": "plain.png",
	"hill": "hill.png",
	"forest": "forest_floor.png",
	"coast": "coast.png",
	"mountain": "rock.png",
	"river": "coast.png",
	"sea": "coast.png",
}
const TREE_GLB := "res://art/italy/classical/trees/forest.glb"
const TREES_PER_CELL := 1
const BUILDING_GLB_DIR := "res://art/italy/classical/buildings"

## Четвёртое здание: положить <type>.glb в BUILDING_GLB_DIR и добавить id в BUILDING_GLB.
const BUILDING_GLB := {
	"domus": "domus.glb",
	"town_hall": "town_hall.glb",
	"farm": "farm.glb",
	"well": "well.glb",
	"sawmill": "sawmill.glb",
}

const BUILDING_HEIGHT := {
	"domus": 0.74,
	"town_hall": 1.22,
	"sawmill": 0.55,
	"farm": 0.72,
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
	"chop": Color("4a7a3a"),
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
var _gltf_cache: Dictionary = {}
var _tree_meshes: Array = []


func _ready() -> void:
	_update_camera_transform()
	if not snapshot.is_empty() and $World/Terrain.get_child_count() == 0:
		_rebuild_world()


func _exit_tree() -> void:
	for key in _gltf_cache.keys():
		var cached = _gltf_cache[key]
		if cached is Node:
			cached.free()
	_gltf_cache.clear()


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
	if has_node("World"):
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
	var trees := _trees_root()
	var grid: Node3D = $World/Grid
	var selection: Node3D = $World/Selection
	_clear_children(terrain)
	_clear_children(roads)
	_clear_children(buildings)
	_clear_children(trees)
	_clear_children(grid)
	_clear_children(selection)
	if snapshot.is_empty():
		return
	var foundation := str(snapshot.get("foundation", "latium_hills"))
	var limit := mini(view_cells, MAP_SIZE)
	for y in limit:
		for x in limit:
			terrain.add_child(_make_terrain_tile(x, y, foundation))
	_build_forest(trees, foundation)
	_build_roads(foundation, roads)
	_build_buildings(buildings)
	_rebuild_grid_only()
	_rebuild_selection(selection)


func _trees_root() -> Node3D:
	var world: Node3D = $World
	var trees := world.get_node_or_null("Trees") as Node3D
	if trees == null:
		trees = Node3D.new()
		trees.name = "Trees"
		world.add_child(trees)
	return trees


func _build_forest(trees: Node3D, foundation: String) -> void:
	var meshes := _tree_meshes_ready()
	if meshes.is_empty():
		return
	var xforms: Array[Transform3D] = []
	var limit := mini(view_cells, MAP_SIZE)
	for y in limit:
		for x in limit:
			if _terrain_at(x, y, foundation) != "forest":
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = int(x) * 374761393 + int(y) * 668265263
			for _i in TREES_PER_CELL:
				var ox := rng.randf_range(0.46, 0.54)
				var oz := rng.randf_range(0.46, 0.54)
				var scale := rng.randf_range(0.92, 1.06)
				var yaw := rng.randf_range(0.0, TAU)
				var height := _surface_height_at(float(x) + ox, float(y) + oz, foundation)
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
				xforms.append(Transform3D(basis, Vector3(float(x) + ox, height, float(y) + oz)))
	if xforms.is_empty():
		return
	for mesh in meshes:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = xforms.size()
		for i in xforms.size():
			multi.set_instance_transform(i, xforms[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Forest"
		inst.multimesh = multi
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		trees.add_child(inst)


func _tree_meshes_ready() -> Array:
	if not _tree_meshes.is_empty():
		return _tree_meshes
	if not FileAccess.file_exists(TREE_GLB):
		return []
	var scene: Node = null
	if ResourceLoader.exists(TREE_GLB):
		var packed = load(TREE_GLB)
		if packed is PackedScene:
			scene = (packed as PackedScene).instantiate()
	if scene == null:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(TREE_GLB, state) != OK:
			return []
		scene = doc.generate_scene(state)
	if scene == null:
		return []
	_collect_tree_meshes(scene)
	scene.free()
	return _tree_meshes


func _collect_tree_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			_tree_meshes.append(mesh)
	for child in node.get_children():
		_collect_tree_meshes(child)


func _surface_height_at(wx: float, wz: float, foundation: String) -> float:
	var x0 := clampi(int(floor(wx)), 0, MAP_SIZE)
	var z0 := clampi(int(floor(wz)), 0, MAP_SIZE)
	var x1 := mini(x0 + 1, MAP_SIZE)
	var z1 := mini(z0 + 1, MAP_SIZE)
	var tx := clampf(wx - float(x0), 0.0, 1.0)
	var tz := clampf(wz - float(z0), 0.0, 1.0)
	var h00 := _grid_height(x0, z0, foundation)
	var h10 := _grid_height(x1, z0, foundation)
	var h01 := _grid_height(x0, z1, foundation)
	var h11 := _grid_height(x1, z1, foundation)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


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
	var terrain := _terrain_at(x, y, foundation)
	var body := StaticBody3D.new()
	body.position = Vector3.ZERO
	body.collision_layer = 1
	body.collision_mask = 0
	var h00: float
	var h10: float
	var h11: float
	var h01: float
	if _is_water(terrain):
		var bed := _terrain_surface_height(terrain, x, y, foundation)
		h00 = bed
		h10 = bed
		h11 = bed
		h01 = bed
	else:
		h00 = _grid_height(x, y, foundation)
		h10 = _grid_height(x + 1, y, foundation)
		h11 = _grid_height(x + 1, y + 1, foundation)
		h01 = _grid_height(x, y + 1, foundation)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _make_cell_mesh(x, y, h00, h10, h11, h01, terrain)
	mesh_inst.material_override = _land_material(terrain)
	body.add_child(mesh_inst)
	var hmax := maxf(maxf(h00, h10), maxf(h11, h01))
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	var thickness := hmax - TERRAIN_BOTTOM
	col.size = Vector3(CELL, maxf(thickness, 0.08), CELL)
	shape.shape = col
	shape.position = Vector3(
		x * CELL + CELL * 0.5,
		TERRAIN_BOTTOM + col.size.y * 0.5,
		y * CELL + CELL * 0.5,
	)
	body.add_child(shape)
	if _is_water(terrain):
		body.add_child(_make_water_cap(x, y, terrain))
	if terrain == "coast" and _touches_water(x, y, foundation):
		body.add_child(_make_shore_foam(x, y, foundation, h00, h10, h11, h01))
	return body


func _make_cell_mesh(
	x: int,
	y: int,
	h00: float,
	h10: float,
	h11: float,
	h01: float,
	terrain: String,
) -> ArrayMesh:
	var x0 := x * CELL
	var x1 := x0 + CELL
	var z0 := y * CELL
	var z1 := z0 + CELL
	var top := Color.WHITE if _ground_texture(terrain) != null else _terrain_color(terrain)
	var side := Color(0.62, 0.54, 0.42)
	var v00 := Vector3(x0, h00, z0)
	var v10 := Vector3(x1, h10, z0)
	var v11 := Vector3(x1, h11, z1)
	var v01 := Vector3(x0, h01, z1)
	var b00 := Vector3(x0, TERRAIN_BOTTOM, z0)
	var b10 := Vector3(x1, TERRAIN_BOTTOM, z0)
	var b11 := Vector3(x1, TERRAIN_BOTTOM, z1)
	var b01 := Vector3(x0, TERRAIN_BOTTOM, z1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_quad(st, v00, v10, v11, v01, top, top, top, top, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	_st_quad(st, b00, v00, v10, b10, side, top, top, side, Vector3(0, 0, -1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_st_quad(st, b10, v10, v11, b11, side, top, top, side, Vector3.RIGHT, Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_st_quad(st, b11, v11, v01, b01, side, top, top, side, Vector3.BACK, Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_st_quad(st, b01, v01, v00, b00, side, top, top, side, Vector3.LEFT, Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	return st.commit()


func _st_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	ca: Color,
	cb: Color,
	cc: Color,
	cd: Color,
	n: Vector3,
	ua: Vector2,
	ub: Vector2,
	uc: Vector2,
	ud: Vector2,
) -> void:
	_st_tri(st, a, b, c, ca, cb, cc, n, ua, ub, uc)
	_st_tri(st, a, c, d, ca, cc, cd, n, ua, uc, ud)


func _st_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	ca: Color,
	cb: Color,
	cc: Color,
	n: Vector3,
	ua: Vector2,
	ub: Vector2,
	uc: Vector2,
) -> void:
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(uc)
	st.add_vertex(c)


func _make_water_cap(x: int, y: int, terrain: String) -> MeshInstance3D:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL, CELL)
	water.mesh = plane
	water.material_override = _water_material(terrain)
	var level := RIVER_WATER if terrain == "river" else SEA_WATER
	water.position = Vector3(x * CELL + CELL * 0.5, level, y * CELL + CELL * 0.5)
	return water


func _make_shore_foam(
	x: int,
	y: int,
	foundation: String,
	h00: float,
	h10: float,
	h11: float,
	h01: float,
) -> MeshInstance3D:
	var foam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL * 0.96, 0.012, CELL * 0.96)
	foam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.93, 0.84, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.85
	foam.material_override = mat
	var top := (h00 + h10 + h11 + h01) * 0.25
	if _touches_water(x, y, foundation):
		top = maxf(top, SEA_WATER + 0.02)
	foam.position = Vector3(x * CELL + CELL * 0.5, top + 0.02, y * CELL + CELL * 0.5)
	return foam


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


func _terrain_surface_height(terrain: String, x: int, y: int, foundation: String) -> float:
	match terrain:
		"mountain":
			return 0.92
		"hill":
			return 0.50
		"plain":
			return 0.06
		"coast":
			return -0.14 if _touches_water(x, y, foundation) else -0.04
		"river":
			return -0.44
		"sea":
			return -0.50
		_:
			return 0.06


func _grid_height(gx: int, gy: int, foundation: String) -> float:
	var land: Array = []
	var water: Array = []
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			var cx: int = gx + dx
			var cy: int = gy + dy
			if not GeoSlice.in_bounds(cx, cy):
				continue
			var kind := _terrain_at(cx, cy, foundation)
			var h := _terrain_surface_height(kind, cx, cy, foundation)
			if _is_water(kind):
				water.append(h)
			else:
				land.append(h)
	if land.is_empty() and water.is_empty():
		return 0.0
	if land.is_empty():
		return _mean(water)
	if water.is_empty():
		return _mean(land)
	return _mean(land) * 0.82 + _mean(water) * 0.18


func _terrain_color(terrain: String) -> Color:
	match terrain:
		"mountain":
			return Color("6e6860")
		"hill":
			return Color("7f9144")
		"coast":
			return Color("e4d4a4")
		"river":
			return Color("3e5a48")
		"sea":
			return Color("2f4e5c")
		"forest":
			return Color("3d5c32")
		_:
			return Color("c3a45c")


func _terrain_at(x: int, y: int, foundation: String) -> String:
	if snapshot.is_empty():
		return GeoSlice.terrain_at(x, y, foundation)
	return SliceMap.terrain_at_state(snapshot, x, y, foundation)


func _ground_texture(terrain: String) -> Texture2D:
	var key := "ground_tex_%s" % terrain
	if _material_cache.has(key):
		return _material_cache[key]
	var file_name: String = GROUND_TEXTURE.get(terrain, "plain.png")
	var tex := load("%s/%s" % [GROUND_DIR, file_name]) as Texture2D
	_material_cache[key] = tex
	return tex


func _land_material(terrain: String) -> StandardMaterial3D:
	var key := "land_%s" % terrain
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex := _ground_texture(terrain)
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material_cache[key] = mat
	return mat


func _water_material(terrain: String) -> ShaderMaterial:
	var key := "water_%s" % terrain
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := ShaderMaterial.new()
	var shader: Shader = load(WATER_SHADER_PATH) as Shader
	if shader == null:
		shader = Shader.new()
		shader.code = _embedded_water_shader()
	mat.shader = shader
	if terrain == "river":
		mat.set_shader_parameter("shallow_color", Color(0.58, 0.78, 0.55, 1.0))
		mat.set_shader_parameter("deep_color", Color(0.12, 0.38, 0.34, 1.0))
		mat.set_shader_parameter("foam_color", Color(0.93, 0.90, 0.74, 1.0))
		mat.set_shader_parameter("foam", 0.48)
	else:
		mat.set_shader_parameter("shallow_color", Color(0.42, 0.78, 0.76, 1.0))
		mat.set_shader_parameter("deep_color", Color(0.07, 0.30, 0.46, 1.0))
		mat.set_shader_parameter("foam_color", Color(0.94, 0.92, 0.82, 1.0))
		mat.set_shader_parameter("foam", 0.32)
	_material_cache[key] = mat
	return mat


func _embedded_water_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 shallow_color : source_color = vec4(0.42, 0.70, 0.74, 0.88);
uniform vec4 deep_color : source_color = vec4(0.16, 0.38, 0.52, 0.94);
uniform float speed = 0.28;
uniform float foam = 0.35;
varying vec2 world_xz;
void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	vec2 uv = world_xz * 0.42;
	float waves = (sin(uv.x * 11.0 + TIME * speed * 4.0) + sin(uv.y * 8.5 - TIME * speed * 2.6)) * 0.5;
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, 0.45 + waves * 0.22);
	ALBEDO = col + vec3(0.08) * max(waves, 0.0) * foam;
	ROUGHNESS = 0.16;
	ALPHA = mix(deep_color.a, shallow_color.a, 0.5);
}
"""


func _is_water(terrain: String) -> bool:
	return terrain == "sea" or terrain == "river"


func _touches_water(x: int, y: int, foundation: String) -> bool:
	for offset in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var nx: int = x + int(offset[0])
		var ny: int = y + int(offset[1])
		if GeoSlice.in_bounds(nx, ny) and _is_water(_terrain_at(nx, ny, foundation)):
			return true
	return false


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var acc := 0.0
	for value in values:
		acc += float(value)
	return acc / float(values.size())


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
		var footprint := Vector2i(int(bounds["w"]), int(bounds["h"]))
		var anchor := Vector2i(int(bounds["min_x"]), int(bounds["min_y"]))
		var status := str(building.get("status", "working"))
		buildings.add_child(_make_building(type_id, anchor, footprint, status))


func _make_building(type_id: String, anchor: Vector2i, footprint: Vector2i, status: String) -> Node3D:
	var root := Node3D.new()
	root.name = "B_%s" % type_id
	var ground := _rect_ground_height(anchor.x, anchor.y, footprint.x, footprint.y)
	root.position = Vector3(anchor.x * CELL, ground, anchor.y * CELL)
	root.set_meta("building_type", type_id)
	root.set_meta("status", status)
	var height: float = float(BUILDING_HEIGHT.get(type_id, 0.55))
	var model := _instantiate_building_model(type_id)
	if model != null:
		model.name = "Model"
		_orient_model(model, footprint)
		root.add_child(model)
		root.set_meta("from_glb", true)
		_apply_status_materials(model, status)
	else:
		var color: Color = TYPE_COLOR.get(type_id, Color("9a9080"))
		var placeholder := _make_block_local(footprint.x, footprint.y, height, color, status)
		placeholder.name = "Model"
		root.add_child(placeholder)
		root.set_meta("from_glb", false)
	_add_status_fx(root, type_id, status, float(footprint.x) * CELL, float(footprint.y) * CELL, height)
	return root


func _orient_model(model: Node3D, footprint: Vector2i) -> void:
	if footprint.y <= footprint.x:
		return
	model.rotation.y = deg_to_rad(90.0)
	model.position.z += float(footprint.y) * CELL


func _instantiate_building_model(type_id: String) -> Node3D:
	if not BUILDING_GLB.has(type_id):
		return null
	if _gltf_cache.has(type_id):
		return _clone_cached_model(type_id)
	var path := "%s/%s" % [BUILDING_GLB_DIR, str(BUILDING_GLB[type_id])]
	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			_gltf_cache[type_id] = packed
			return packed.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var generated := doc.generate_scene(state)
	if generated == null:
		return null
	_gltf_cache[type_id] = generated
	return generated.duplicate() as Node3D


func _clone_cached_model(type_id: String) -> Node3D:
	var cached = _gltf_cache[type_id]
	if cached is PackedScene:
		return cached.instantiate() as Node3D
	return (cached as Node).duplicate() as Node3D


func _apply_status_materials(node: Node, status: String) -> void:
	if status == "working":
		return
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var src: Material = mesh_inst.material_override
		if src == null:
			src = mesh_inst.get_active_material(0)
		if src is BaseMaterial3D:
			var mat: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
			match status:
				"building":
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					var tint := mat.albedo_color.lightened(0.22)
					tint.a = 0.52
					mat.albedo_color = tint
				"idle":
					mat.albedo_color = mat.albedo_color.darkened(0.28)
					mat.roughness = clampf(mat.roughness + 0.12, 0.0, 1.0)
			mesh_inst.material_override = mat
	for child in node.get_children():
		_apply_status_materials(child, status)


func _add_status_fx(
	root: Node3D,
	type_id: String,
	status: String,
	width: float,
	depth: float,
	height: float,
) -> void:
	match status:
		"building":
			_add_scaffold(root, width, depth, height)
		"idle":
			var model := root.get_node_or_null("Model")
			if model != null:
				_add_silhouette(root, model)
		_:
			_add_smoke(root, type_id, width, depth, height)


func _add_scaffold(root: Node3D, width: float, depth: float, height: float) -> void:
	var group := Node3D.new()
	group.name = "StatusScaffold"
	var mat := _scaffold_material()
	var inset := 0.07
	var post_h := height + 0.16
	var xs := [inset, width - inset]
	var zs := [inset, depth - inset]
	for x in xs:
		for z in zs:
			group.add_child(_fx_box(Vector3(x, post_h * 0.5, z), Vector3(0.045, post_h, 0.045), mat))
	for y_ratio in [0.34, 0.72]:
		var y := post_h * float(y_ratio)
		group.add_child(_fx_box(Vector3(width * 0.5, y, inset), Vector3(width - inset * 2.0, 0.032, 0.032), mat))
		group.add_child(_fx_box(Vector3(width * 0.5, y, depth - inset), Vector3(width - inset * 2.0, 0.032, 0.032), mat))
		group.add_child(_fx_box(Vector3(inset, y, depth * 0.5), Vector3(0.032, 0.032, depth - inset * 2.0), mat))
		group.add_child(_fx_box(Vector3(width - inset, y, depth * 0.5), Vector3(0.032, 0.032, depth - inset * 2.0), mat))
	root.add_child(group)


func _add_silhouette(root: Node3D, source: Node) -> void:
	var ghost := source.duplicate()
	ghost.name = "StatusSilhouette"
	_paint_silhouette(ghost)
	root.add_child(ghost)


func _paint_silhouette(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.14, 0.11, 0.09, 0.38)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		mat.grow = true
		mat.grow_amount = 0.035
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_paint_silhouette(child)


func _add_smoke(root: Node3D, type_id: String, width: float, depth: float, height: float) -> void:
	var amount := _smoke_amount(type_id)
	if amount <= 0:
		return
	var particles := CPUParticles3D.new()
	particles.name = "StatusSmoke"
	particles.amount = amount
	particles.lifetime = 2.4
	particles.preprocess = 1.4
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.05
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 14.0
	particles.gravity = Vector3(0.03, 0.14, 0.02)
	particles.initial_velocity_min = 0.16
	particles.initial_velocity_max = 0.36
	particles.scale_amount_min = 0.45
	particles.scale_amount_max = 1.05
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18)
	particles.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.84, 0.84, 0.86, 0.4)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.86, 0.86, 0.88, 0.48),
		Color(0.76, 0.76, 0.78, 0.22),
		Color(0.7, 0.7, 0.72, 0.0),
	])
	particles.color_ramp = ramp
	match type_id:
		"domus":
			particles.position = Vector3(0.26, 0.78, 0.28)
		"farm":
			particles.position = Vector3(0.22, 0.64, 0.28)
		"sawmill":
			particles.position = Vector3(width * 0.5, height + 0.06, depth * 0.5)
		_:
			particles.position = Vector3(width * 0.45, height + 0.04, depth * 0.4)
	root.add_child(particles)


func _smoke_amount(type_id: String) -> int:
	match type_id:
		"sawmill":
			return 22
		"farm":
			return 14
		"domus":
			return 8
		"town_hall", "well", "cropland", "road":
			return 0
		_:
			return 10


func _scaffold_material() -> StandardMaterial3D:
	if _material_cache.has("scaffold"):
		return _material_cache["scaffold"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8a6a3e")
	mat.roughness = 0.9
	_material_cache["scaffold"] = mat
	return mat


func _fx_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	return mesh_inst


func _make_block_local(
	width_cells: int,
	depth_cells: int,
	height: float,
	color: Color,
	status: String,
) -> MeshInstance3D:
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
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(width_cells * CELL * 0.5, height * 0.5, depth_cells * CELL * 0.5)
	return mesh_inst


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
	var mesh_inst := _make_block_local(width_cells, depth_cells, height, color, status)
	var ground := _rect_ground_height(anchor_x, anchor_y, width_cells, depth_cells)
	root.position = Vector3(anchor_x * CELL, ground, anchor_y * CELL)
	root.add_child(mesh_inst)
	return root


func _ground_height_at(x: int, y: int) -> float:
	if snapshot.is_empty():
		return 0.0
	var foundation := str(snapshot.get("foundation", "latium_hills"))
	return maxf(
		maxf(_grid_height(x, y, foundation), _grid_height(x + 1, y, foundation)),
		maxf(_grid_height(x, y + 1, foundation), _grid_height(x + 1, y + 1, foundation)),
	)


func _rect_ground_height(anchor_x: int, anchor_y: int, width_cells: int, depth_cells: int) -> float:
	var top := -999.0
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
	while node.get_child_count() > 0:
		var child := node.get_child(0)
		node.remove_child(child)
		child.free()


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
