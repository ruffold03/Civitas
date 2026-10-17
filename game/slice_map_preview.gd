extends Control

## Tab — режим. Space — конец хода. Enter — подтвердить подготовку/стройку/технологию.
## Стройка: 1 дом, 2 колодец, 3 лесопильня, 4 ферма.
## Наука: 1 письмено, 2 монета, 3 инженерия, 4 ополчение.

const BoardScript = preload("res://game/board.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")

enum Mode { SURVEY, PREPARE, ROAD, BUILD, TECH }

const BUILD_HOTKEYS := {
	KEY_1: "domus",
	KEY_2: "well",
	KEY_3: "sawmill",
	KEY_4: "farm",
}

const TECH_HOTKEYS := {
	KEY_1: "writing",
	KEY_2: "moneta",
	KEY_3: "engineering",
	KEY_4: "military",
}

var board: Control
var label: Label
var hint_label: Label
var event_label: Label
var scenario_id := "rome"
var font: Font
var game: CivSliceMatch
var mode := Mode.SURVEY
var prepare_cells: Array = []
var road_cell: Array = []
var build_type := ""
var build_cells: Array = []
var tech_pick := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	label = Label.new()
	label.position = Vector2(12, 8)
	add_child(label)
	hint_label = Label.new()
	hint_label.position = Vector2(12, 28)
	add_child(hint_label)
	event_label = Label.new()
	event_label.position = Vector2(12, 48)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.custom_minimum_size = Vector2(900, 0)
	add_child(event_label)
	board = BoardScript.new()
	board.position = Vector2(0, 88)
	board.cell_pressed.connect(_on_cell_pressed)
	add_child(board)
	_start("rome")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if _event_open():
			var picked := _event_hotkey_option(event.keycode)
			if picked != "":
				var note: String = str(game.choose_event(picked).get("error", ""))
				_refresh(note)
				return
		if mode == Mode.BUILD and BUILD_HOTKEYS.has(event.keycode):
			build_type = BUILD_HOTKEYS[event.keycode]
			build_cells = []
			_refresh("")
			return
		if mode == Mode.TECH and TECH_HOTKEYS.has(event.keycode):
			tech_pick = TECH_HOTKEYS[event.keycode]
			_refresh("")
			return
		match event.keycode:
			KEY_F1:
				_start("rome")
			KEY_F2:
				_start("neapolis")
			KEY_F3:
				_start("tarentum")
			KEY_TAB:
				mode = ((mode + 1) % 5) as Mode
				_clear_selection()
				_refresh("")
			KEY_ENTER, KEY_KP_ENTER:
				_confirm()
			KEY_ESCAPE:
				_clear_selection()
				_refresh("")
			KEY_SPACE:
				_end_turn()


func _start(next_id: String) -> void:
	scenario_id = next_id
	game = CivSliceMatch.new_game(scenario_id)
	mode = Mode.SURVEY
	_clear_selection()
	_refresh("")


func _clear_selection() -> void:
	prepare_cells = []
	road_cell = []
	build_type = ""
	build_cells = []
	tech_pick = ""


func _on_cell_pressed(x: int, y: int) -> void:
	var note := ""
	match mode:
		Mode.SURVEY:
			var chunk: Array = game.chunk_at_cell(x, y)
			note = str(game.survey_order(int(chunk[0]), int(chunk[1])).get("error", ""))
		Mode.PREPARE:
			note = _toggle_prepare_cell(x, y)
		Mode.ROAD:
			road_cell = [x, y]
		Mode.BUILD:
			if build_type == "":
				note = "Сначала выбери тип: 1–4."
			else:
				note = _toggle_build_cell(x, y)
	_refresh(note)


func _toggle_prepare_cell(x: int, y: int) -> String:
	for i in prepare_cells.size():
		var cell: Array = prepare_cells[i]
		if int(cell[0]) == x and int(cell[1]) == y:
			prepare_cells.remove_at(i)
			return ""
	prepare_cells.append([x, y])
	return ""


func _toggle_build_cell(x: int, y: int) -> String:
	var area := int(CivSliceCatalog.building(build_type)["area"])
	for i in build_cells.size():
		var cell: Array = build_cells[i]
		if int(cell[0]) == x and int(cell[1]) == y:
			build_cells.remove_at(i)
			return ""
	if build_cells.size() >= area:
		return "Достаточно клеток для этой постройки."
	build_cells.append([x, y])
	return ""


func _confirm() -> void:
	var note := ""
	match mode:
		Mode.PREPARE:
			if not prepare_cells.is_empty():
				note = str(game.prepare_order(prepare_cells).get("error", ""))
				if note == "":
					prepare_cells = []
		Mode.ROAD:
			if not road_cell.is_empty():
				note = str(game.road_order(road_cell).get("error", ""))
				if note == "":
					road_cell = []
		Mode.BUILD:
			if build_type != "" and not build_cells.is_empty():
				note = str(game.build_order(build_type, build_cells).get("error", ""))
				if note == "":
					build_type = ""
					build_cells = []
		Mode.TECH:
			if tech_pick != "":
				note = str(game.research_order(tech_pick).get("error", ""))
				if note == "":
					tech_pick = ""
	_refresh(note)


func _end_turn() -> void:
	var result: Dictionary = game.end_turn()
	var note := ""
	if not result["ok"]:
		note = str(result["error"])
	else:
		for entry in game.snapshot["notifications"]:
			match str(entry.get("kind", "")):
				"survey_done":
					note = "Чанк (%d,%d) изучен." % [int(entry["chunk_x"]), int(entry["chunk_y"])]
				"prepare_done":
					note = "Клетка (%d,%d) подготовлена." % [int(entry["x"]), int(entry["y"])]
				"completed":
					note = "Построено: %s." % entry["type"]
				"tech_done":
					note = "Изучено: %s." % entry.get("name", entry["id"])
				"event":
					note = "Событие: %s." % CivSliceCatalog.event(str(entry["event"]))["name"]
				"event_choice":
					note = "Выбор в событии."
	_refresh(note)


func _event_open() -> bool:
	return str(game.snapshot.get("current_event", "")) != ""


func _event_option_ids() -> Array:
	var event_id := str(game.snapshot["current_event"])
	if event_id == "":
		return []
	var options: Dictionary = CivSliceCatalog.event(event_id)["options"]
	var ids: Array = []
	for option_id in options:
		ids.append(option_id)
	return ids


func _event_hotkey_option(keycode: int) -> String:
	var index := -1
	match keycode:
		KEY_1:
			index = 0
		KEY_2:
			index = 1
		KEY_3:
			index = 2
		KEY_4:
			index = 3
		KEY_5:
			index = 4
	if index < 0:
		return ""
	var ids: Array = _event_option_ids()
	if index >= ids.size():
		return ""
	return str(ids[index])


func _event_panel_text() -> String:
	if not _event_open():
		return ""
	var event_id := str(game.snapshot["current_event"])
	var definition: Dictionary = CivSliceCatalog.event(event_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s — %s" % [definition["name"], definition.get("text", "")])
	var ids: Array = _event_option_ids()
	for i in ids.size():
		var option_id: String = str(ids[i])
		var option: Dictionary = definition["options"][option_id]
		lines.append("%d) %s" % [i + 1, option["name"]])
	if str(game.draft.get("event_option", "")) != "":
		lines.append("(вариант выбран — Space, конец хода)")
	else:
		lines.append("Цифра — выбор. Space — ход только после выбора.")
	return "\n".join(lines)


func _refresh(note: String) -> void:
	var snap: Dictionary = game.snapshot
	var mode_name: String = ["изучение чанка", "подготовка", "дорога", "стройка", "наука"][mode]
	var research := str(snap.get("research", ""))
	var science_line := "запас %d" % int(snap.get("science", 0))
	if research != "":
		var prog: int = int(snap.get("tech_progress", {}).get(research, 0))
		var cost: int = int(CivSliceCatalog.technology(research)["cost"])
		science_line = "%s %d/%d" % [CivSliceCatalog.technology(research)["name"], prog, cost]
	label.text = "Ход %d — %s (%s)  наука: %s  еда %d  дерево %d" % [
		int(snap["turn"]),
		snap["scenario"],
		mode_name,
		science_line,
		int(snap["stocks"]["food"]),
		int(snap["stocks"]["wood"]),
	]
	var orders := int(game.draft["orders"].size())
	var extra := ""
	if mode == Mode.PREPARE:
		extra = " Выбрано: %d. Enter — приказ." % prepare_cells.size()
	elif mode == Mode.ROAD:
		extra = " Клетка дороги. Enter — приказ (2 дерева, 1 ход)."
	elif mode == Mode.BUILD:
		var name: String = build_type if build_type != "" else "—"
		extra = " Тип: %s, клеток: %d. Enter — приказ." % [name, build_cells.size()]
	elif mode == Mode.TECH:
		var pick: String = tech_pick if tech_pick != "" else "—"
		extra = " Технология: %s. Enter — изучать." % pick
	var selected: Array = []
	if mode == Mode.PREPARE:
		selected = prepare_cells
	elif mode == Mode.ROAD and not road_cell.is_empty():
		selected = [road_cell]
	elif mode == Mode.BUILD:
		selected = build_cells
	var event_hint := ""
	if _event_open():
		event_hint = " Событие блокирует ход."
	hint_label.text = "Tab режим. 1–4 (здание или тех). Enter. Space — ход. Приказов: %d.%s%s %s" % [
		orders, extra, event_hint, note,
	]
	event_label.text = _event_panel_text()
	board.set_view(snap, game.draft["orders"], selected, true, font)
