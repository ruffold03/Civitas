extends Control

const Geo = preload("res://sim/civ_geo.gd")
const GeoSlice = preload("res://sim/civ_geo_slice.gd")
const SliceMap = preload("res://sim/civ_slice_map.gd")
const CivUtil = preload("res://sim/civ_util.gd")

const CELL_MIN := 22.0
const CELL_MAX := 80.0
const ORIGIN := Vector2(8, 8)

const MARK := {
	"hut": "хиж",
	"well": "кол",
	"wood_yard": "дрв",
	"stone_yard": "кам",
	"hearth": "огн",
	"field": "поле",
	"pen": "заг",
	"domus": "дом",
	"town_hall": "рат",
	"sawmill": "лес",
	"quarry": "кам",
	"square": "пл",
	"cropland": "паш",
	"farm": "фер",
	"vineyard": "вин",
	"pottery": "гон",
	"mine": "руд",
	"granary": "зак",
	"temple": "хр",
	"forum": "фор",
	"aqueduct": "акв",
	"baths": "тер",
	"market": "рын",
	"port": "порт",
	"barracks": "каз",
	"road": "дор",
}

const TYPE_COLOR := {
	"hut": Color("8d5a3c"),
	"well": Color("6ea8c9"),
	"wood_yard": Color("6b8f4e"),
	"stone_yard": Color("8a8378"),
	"hearth": Color("d06a3a"),
	"field": Color("c9b14a"),
	"pen": Color("a6844a"),
	"domus": Color("8d5a3c"),
	"town_hall": Color("b8860b"),
	"sawmill": Color("6b8f4e"),
	"quarry": Color("8a8378"),
	"square": Color("d06a3a"),
	"cropland": Color("c9b14a"),
	"farm": Color("a6844a"),
	"vineyard": Color("7a4a6a"),
	"pottery": Color("b08060"),
	"mine": Color("707880"),
	"granary": Color("c9a84a"),
	"temple": Color("e8e0d0"),
	"forum": Color("c0b8a8"),
	"aqueduct": Color("8aa8c0"),
	"baths": Color("9ec8d8"),
	"market": Color("d4a85a"),
	"port": Color("4a7a9a"),
	"barracks": Color("8a4a4a"),
	"road": Color("6a5a48"),
}

signal cell_pressed(x: int, y: int)

var show_grid := false
var snapshot: Dictionary = {}
var draft_orders: Array = []
var selected_cells: Array = []
var font: Font
var map_size := Geo.SIZE
var foundation := ""
var cell_size: float = 40.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_cell_size()


func set_view(next_snapshot: Dictionary, orders: Array, selected: Array, grid: bool, text_font: Font) -> void:
	snapshot = next_snapshot
	draft_orders = orders
	selected_cells = selected
	show_grid = grid
	font = text_font
	foundation = str(next_snapshot.get("foundation", ""))
	map_size = GeoSlice.SIZE if foundation != "" else Geo.SIZE
	_update_cell_size()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_cell_size()


func _update_cell_size() -> void:
	if map_size <= 0:
		return
	var inner := size - ORIGIN * 2.0
	if inner.x <= 8.0 or inner.y <= 8.0:
		return
	var fit := minf(inner.x / float(map_size), inner.y / float(map_size))
	cell_size = clampf(fit, CELL_MIN, CELL_MAX)
	queue_redraw()


func _grid_origin() -> Vector2:
	var grid := Vector2(float(map_size) * cell_size, float(map_size) * cell_size)
	var spare := size - grid
	return Vector2(maxi(8.0, spare.x * 0.5), maxi(8.0, spare.y * 0.5))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if cell.x >= 0:
			cell_pressed.emit(cell.x, cell.y)
			accept_event()


func _draw() -> void:
	var gap := 3 if show_grid else 0
	var origin := _grid_origin()
	for y in map_size:
		for x in map_size:
			var rect := Rect2(
				origin + Vector2(x * cell_size + gap, y * cell_size + gap),
				Vector2(cell_size - gap * 2, cell_size - gap * 2),
			)
			draw_rect(rect, _terrain_color(x, y))
			_draw_deposit(x, y, rect)
			_draw_cell_prep(x, y, rect)
			if show_grid:
				draw_rect(rect, Color(1, 1, 1, 0.18), false, 1.0)
	if snapshot.is_empty():
		return
	for building in snapshot["buildings"]:
		_draw_cells(building["cells"], _paint(building["type"], building["status"]), building)
	for road in snapshot.get("roads", []):
		var road_view := {
			"type": "road",
			"status": str(road.get("status", "working")),
			"timer": int(road.get("timer", 0)),
		}
		_draw_cells(road["cells"], _paint("road", road_view["status"]), road_view)
	for order in draft_orders:
		if str(order.get("kind", "")) == "survey":
			_draw_survey_draft(order, gap)
			continue
		if str(order.get("kind", "")) == "prepare":
			_draw_prepare_draft(order["cells"], gap)
			continue
		if str(order.get("kind", "")) == "road":
			_draw_cells(
				order["cells"],
				_paint("road", "draft"),
				{"type": "road", "status": "draft", "timer": 0},
			)
			continue
		if not order.has("cells"):
			continue
		_draw_cells(order["cells"], _paint(str(order["type"]), "draft"), {"type": order["type"], "status": "draft", "timer": 0})
	for cell in selected_cells:
		var rect := _rect(int(cell[0]), int(cell[1]), 3 if show_grid else 0)
		draw_rect(rect, Color(1, 1, 1, 0.95), false, 2.0)
	_draw_chunk_hints(gap)


func _draw_cell_prep(x: int, y: int, rect: Rect2) -> void:
	if foundation == "" or snapshot.is_empty() or font == null:
		return
	var prep: Dictionary = snapshot.get("cell_prep", {})
	var record: Dictionary = prep.get(CivUtil.cell_key([x, y]), {})
	if record.is_empty():
		return
	if bool(record.get("prepared", false)):
		draw_rect(rect, Color("6b9e5a", 0.22))
		draw_rect(rect, Color("d8f0c8", 0.85), false, 1.0)
		return
	var timer := int(record.get("timer", 0))
	if timer <= 0:
		return
	draw_rect(rect, Color("c9a04a", 0.25))
	var mark := "подг %d" % timer
	font.draw_string(
		get_canvas_item(),
		rect.position + Vector2(2, 12),
		mark,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("2a2418")
	)


func _draw_prepare_draft(cells: Array, gap: int) -> void:
	if font == null:
		return
	for cell in cells:
		var rect := _rect(int(cell[0]), int(cell[1]), gap)
		draw_rect(rect, Color("e8b35a", 0.45))
		draw_rect(rect, Color("fff2d6", 0.95), false, 2.0)
		font.draw_string(get_canvas_item(), rect.position + Vector2(2, rect.size.y - 4), "подг?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("1a1a1a"))


func _draw_survey_draft(order: Dictionary, gap: int) -> void:
	if foundation == "" or font == null:
		return
	var cx := int(order["chunk_x"])
	var cy := int(order["chunk_y"])
	var x0 := cx * GeoSlice.CHUNK
	var y0 := cy * GeoSlice.CHUNK
	var origin := _grid_origin()
	var rect := Rect2(
		origin + Vector2(x0 * cell_size + gap, y0 * cell_size + gap),
		Vector2(GeoSlice.CHUNK * cell_size - gap * 2, GeoSlice.CHUNK * cell_size - gap * 2),
	)
	draw_rect(rect, Color("9ec5ff", 0.35))
	draw_rect(rect, Color("e8f2ff", 0.9), false, 2.0)
	font.draw_string(get_canvas_item(), rect.position + Vector2(4, rect.size.y - 6), "изуч?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("1a1a1a"))


func _draw_chunk_hints(gap: int) -> void:
	if foundation == "" or snapshot.is_empty() or font == null:
		return
	for record in snapshot.get("chunks", []):
		var timer := int(record.get("survey_timer", 0))
		var surveyed := bool(record.get("surveyed", false))
		if timer <= 0 and surveyed:
			continue
		var cx := int(record["x"])
		var cy := int(record["y"])
		var x0 := cx * GeoSlice.CHUNK
		var y0 := cy * GeoSlice.CHUNK
		var origin := _grid_origin()
		var rect := Rect2(
			origin + Vector2(x0 * cell_size + gap, y0 * cell_size + gap),
			Vector2(GeoSlice.CHUNK * cell_size - gap * 2, GeoSlice.CHUNK * cell_size - gap * 2),
		)
		if timer > 0:
			var mark := "изуч %d" % timer
			font.draw_string(
				get_canvas_item(),
				rect.position + Vector2(4, 14),
				mark,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12,
				Color("f5f0d8")
			)
		elif not surveyed:
			draw_rect(rect, Color(1, 1, 1, 0.06), false, 1.0)


func _terrain_color(x: int, y: int) -> Color:
	var terrain := _terrain_at(x, y)
	if foundation == "":
		match terrain:
			"water":
				return Color("3d6f8a")
			"cliff":
				return Color("5c564e")
			_:
				return Color("c4a574")
	match terrain:
		"sea", "river":
			return Color("3d6f8a")
		"mountain", "cliff":
			return Color("5c564e")
		"hill":
			return Color("a89262")
		"coast":
			return Color("d4c48a")
		_:
			return Color("c4a574")


func _terrain_at(x: int, y: int) -> String:
	if foundation != "":
		return GeoSlice.terrain_at(x, y, foundation)
	return Geo.terrain_at(x, y)


func _draw_deposit(x: int, y: int, rect: Rect2) -> void:
	if foundation == "" or snapshot.is_empty():
		return
	var map_cells: Dictionary = snapshot.get("map_cells", {})
	var deposit: Dictionary = SliceMap.visible_deposit(map_cells, x, y)
	if deposit.is_empty() or font == null:
		return
	var resource := str(deposit["resource"])
	var mark := "%s%d" % [SliceMap.MARK.get(resource, "?"), int(deposit["left"])]
	var text_size := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var at := rect.position + Vector2((rect.size.x - text_size.x) * 0.5, rect.size.y - 4)
	font.draw_string(get_canvas_item(), at, mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("1a1a1a"))


func _paint(type_id: String, status: String) -> Color:
	var color: Color = TYPE_COLOR.get(type_id, Color("7a7a7a"))
	if status == "building":
		color = color.darkened(0.35)
	elif status == "idle":
		color = color.darkened(0.55)
	elif status == "draft":
		color.a = 0.55
	return color


func _draw_cells(cells: Array, color: Color, building: Dictionary) -> void:
	var gap := 3 if show_grid else 0
	var anchor: Array = cells[0]
	for cell in cells:
		var rect := _rect(int(cell[0]), int(cell[1]), gap)
		draw_rect(rect, color)
		if int(cell[0]) < int(anchor[0]) or (int(cell[0]) == int(anchor[0]) and int(cell[1]) < int(anchor[1])):
			anchor = cell
	if font == null:
		return
	var mark := str(MARK.get(building["type"], building["type"]))
	if building["status"] == "building":
		mark = "%s %d" % [mark, int(building["timer"])]
	elif building["status"] == "idle":
		mark = mark + " !"
	var min_x := int(anchor[0])
	var min_y := int(anchor[1])
	var max_x := min_x
	var max_y := min_y
	for cell in cells:
		min_x = mini(min_x, int(cell[0]))
		min_y = mini(min_y, int(cell[1]))
		max_x = maxi(max_x, int(cell[0]))
		max_y = maxi(max_y, int(cell[1]))
	var top := _rect(min_x, min_y, gap)
	var bottom := _rect(max_x, max_y, gap)
	var union := Rect2(top.position, bottom.end - top.position)
	var text_size := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var at := union.position + Vector2((union.size.x - text_size.x) * 0.5, (union.size.y + text_size.y) * 0.5 - 2)
	font.draw_string(get_canvas_item(), at, mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("1c1915"))


func _rect(x: int, y: int, gap: int) -> Rect2:
	var origin := _grid_origin()
	return Rect2(
		origin + Vector2(x * cell_size + gap, y * cell_size + gap),
		Vector2(cell_size - gap * 2, cell_size - gap * 2),
	)


func _cell_at(position: Vector2) -> Vector2i:
	var local := position - _grid_origin()
	if cell_size <= 0.0:
		return Vector2i(-1, -1)
	var x := int(local.x / cell_size)
	var y := int(local.y / cell_size)
	if local.x < 0 or local.y < 0 or x < 0 or y < 0 or x >= map_size or y >= map_size:
		return Vector2i(-1, -1)
	return Vector2i(x, y)
