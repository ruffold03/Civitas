extends Control

const MatchScript = preload("res://sim/civ_match.gd")
const SliceMatch = preload("res://sim/civ_slice_match.gd")
const Catalog = preload("res://sim/civ_catalog.gd")
const SliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const SliceMap = preload("res://sim/civ_slice_map.gd")
const SliceTech = preload("res://sim/civ_slice_tech.gd")
const Geo = preload("res://sim/civ_geo.gd")
const Copy = preload("res://game/copy.gd")
const SliceCopy = preload("res://game/slice_copy.gd")
const BoardScript = preload("res://game/board.gd")
const HudWidgets = preload("res://game/hud_widgets.gd")
const CityView3DScene = preload("res://game/city_view_3d.tscn")

const SAVE_PATH := "user://civitas_party.save"

var game
var party := "slice"
var slice_scenario := "rome"
var mode := "overview"
var selected_type := ""
var selected_cells: Array = []
var prepare_cells: Array = []
var road_cell: Array = []
var tech_pick := ""
var neighbor_peek := ""
var map_view_scenario := ""
var map_3d := false
var font: Font

var title_label: Label
var stats_host: VBoxContainer
var neighbors_host: VBoxContainer
var pressure_host: HFlowContainer
var notes_host: VBoxContainer
var message_label: Label
var forecast_label: Label
var inspect_label: Label
var orders_box: VBoxContainer
var event_box: VBoxContainer
var build_box: VBoxContainer
var end_button: Button
var overview_button: Button
var inspect_button: Button
var build_button: Button
var slice_modes: HFlowContainer
var slice_mode_buttons: Dictionary = {}
var tech_box: VBoxContainer
var party_box: HFlowContainer
var board: Control
var map_viewport_container: SubViewportContainer
var map_subviewport: SubViewport
var city_view: Node3D
var view3d_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	theme = ui_theme
	_start_party("slice", "rome")
	_build_ui()
	_refresh()


func _start_party(next_party: String, scenario: String = "rome") -> void:
	party = next_party
	slice_scenario = scenario
	mode = "overview"
	selected_type = ""
	selected_cells = []
	prepare_cells = []
	road_cell = []
	tech_pick = ""
	neighbor_peek = ""
	map_view_scenario = ""
	map_3d = false
	if party == "slice":
		game = SliceMatch.new_game(slice_scenario)
	else:
		game = MatchScript.new_game()


func _choose_party(next_party: String) -> void:
	if party == next_party:
		return
	if next_party == "slice":
		_start_party("slice", slice_scenario)
	else:
		_start_party("prototype")
	_refresh()


func _choose_scenario(scenario: String) -> void:
	if party == "slice" and slice_scenario == scenario:
		return
	_start_party("slice", scenario)
	_refresh()


func _peek_neighbor(scenario_id: String) -> void:
	if neighbor_peek == scenario_id:
		neighbor_peek = ""
	else:
		neighbor_peek = scenario_id
	_refresh()


func _peek_neighbor_map(scenario_id: String) -> void:
	if map_view_scenario == scenario_id:
		map_view_scenario = ""
	else:
		map_view_scenario = scenario_id
		mode = "inspect"
		neighbor_peek = scenario_id
		map_3d = true
	_refresh()


func _view_player_map() -> void:
	map_view_scenario = ""
	_refresh()


func _toggle_map_3d() -> void:
	if party != "slice":
		return
	map_3d = not map_3d
	if map_3d and map_view_scenario == "" and mode == "overview":
		enter_inspect()
	_refresh()


func _board_snapshot() -> Dictionary:
	var snap: Dictionary = game.snapshot
	if map_view_scenario != "" and snap.has("ai_cities"):
		var cities: Dictionary = snap["ai_cities"]
		if cities.has(map_view_scenario):
			return cities[map_view_scenario]
	return snap


func enter_overview() -> void:
	if _over():
		return
	mode = "overview"
	selected_type = ""
	selected_cells = []
	_refresh()


func enter_inspect() -> void:
	if _over():
		return
	mode = "inspect"
	selected_type = ""
	selected_cells = []
	_refresh()


func enter_build() -> void:
	if _over():
		return
	mode = "build"
	selected_cells = []
	_refresh()


func enter_slice_mode(next_mode: String) -> void:
	if party != "slice" or _over():
		return
	mode = next_mode
	selected_type = ""
	selected_cells = []
	prepare_cells = []
	road_cell = []
	tech_pick = ""
	_refresh()


func pick_building(type_id: String) -> void:
	if _over():
		return
	if party == "slice":
		if mode != "build":
			return
		if not _slice_building_tech_unlocked(type_id):
			return
	else:
		if mode != "build":
			return
	selected_type = type_id
	selected_cells = []
	_refresh()


func click_cell(x: int, y: int) -> void:
	if _over():
		return
	if party == "slice":
		_click_slice_cell(x, y)
		return
	if mode == "inspect":
		inspect_label.text = _inspect_at(x, y)
		return
	if mode != "build" or selected_type == "":
		message_label.text = "Сначала выбери здание."
		return
	var cell := [x, y]
	if _selected_has(cell):
		selected_cells = _without(selected_cells, cell)
		_refresh()
		return
	if Geo.terrain_at(x, y) != "land":
		message_label.text = "Здесь нельзя строить."
		return
	if _occupied(cell):
		message_label.text = "Клетка уже занята."
		return
	var area := int(Catalog.building(selected_type)["area"])
	if selected_cells.size() >= area:
		message_label.text = "Площадь уже набрана."
		return
	selected_cells.append(cell)
	message_label.text = ""
	_refresh()


func confirm_selection() -> String:
	if party == "slice":
		return _confirm_slice()
	if mode != "build" or selected_type == "":
		return "Нечего подтверждать."
	var result: Dictionary = game.build_order(selected_type, selected_cells)
	if not result["ok"]:
		message_label.text = str(result["error"])
		return str(result["error"])
	selected_cells = []
	message_label.text = "Приказ записан. Город изменится в конце хода."
	_refresh()
	return ""


func cancel_order(order_id: int) -> void:
	if party == "slice":
		if _over():
			return
	elif mode != "build":
		return
	var result: Dictionary = game.cancel_order(order_id)
	message_label.text = "" if result["ok"] else str(result["error"])
	_refresh()


func choose_option(option_id: String) -> void:
	var result: Dictionary = game.choose_event(option_id)
	message_label.text = "" if result["ok"] else str(result["error"])
	_refresh()


func finish_turn() -> String:
	var result: Dictionary = game.end_turn()
	if not result["ok"]:
		message_label.text = str(result["error"])
		_refresh()
		return str(result["error"])
	mode = "overview"
	selected_type = ""
	selected_cells = []
	message_label.text = ""
	_refresh()
	return ""


func restart() -> void:
	_start_party(party, slice_scenario)
	message_label.text = ""
	_refresh()


func save_party() -> void:
	if party != "prototype":
		message_label.text = "Сохранение пока только у прототипа."
		return
	var result: Dictionary = game.save_to_file(SAVE_PATH)
	message_label.text = "Партия сохранена." if result["ok"] else str(result["error"])


func load_party() -> void:
	if party != "prototype":
		message_label.text = "Загрузка пока только у прототипа."
		return
	if not FileAccess.file_exists(SAVE_PATH):
		message_label.text = "Сохранения нет."
		return
	game = MatchScript.load_from_file(SAVE_PATH)
	mode = "overview"
	selected_type = ""
	selected_cells = []
	message_label.text = "Партия загружена."
	_refresh()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("1c1915")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shell := VBoxContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 12
	shell.offset_top = 12
	shell.offset_right = -12
	shell.offset_bottom = -12
	shell.add_theme_constant_override("separation", 8)
	add_child(shell)

	title_label = _label("", 20)
	shell.add_child(title_label)

	var root := HBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	shell.add_child(root)

	var left_column := VBoxContainer.new()
	left_column.custom_minimum_size = Vector2(340, 0)
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 6)
	root.add_child(left_column)

	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_column.add_child(info_scroll)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	info_scroll.add_child(info)

	stats_host = VBoxContainer.new()
	pressure_host = HFlowContainer.new()
	pressure_host.add_theme_constant_override("h_separation", 6)
	pressure_host.add_theme_constant_override("v_separation", 6)
	notes_host = VBoxContainer.new()
	notes_host.add_theme_constant_override("separation", 4)
	message_label = _wrapped("")
	info.add_child(_panel("Город", stats_host))
	neighbors_host = VBoxContainer.new()
	neighbors_host.add_theme_constant_override("separation", 6)
	info.add_child(_panel("Соседи", neighbors_host))
	info.add_child(_panel("Внимание", pressure_host))
	info.add_child(_scroll_panel("Прошлый ход", notes_host))
	orders_box = VBoxContainer.new()
	info.add_child(_panel_box("Приказы", orders_box))
	event_box = VBoxContainer.new()
	info.add_child(event_box)
	inspect_label = _wrapped("Осмотр: кликни клетку на карте.")
	info.add_child(inspect_label)
	info.add_child(message_label)

	var map_side := VBoxContainer.new()
	map_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_side.size_flags_stretch_ratio = 1.6
	root.add_child(map_side)

	board = BoardScript.new()
	board.font = font
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(click_cell)
	map_side.add_child(board)

	map_viewport_container = SubViewportContainer.new()
	map_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_viewport_container.stretch = true
	map_viewport_container.visible = false
	map_viewport_container.resized.connect(_sync_map_viewport_size)
	map_side.add_child(map_viewport_container)
	map_subviewport = SubViewport.new()
	map_subviewport.handle_input_locally = true
	map_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_viewport_container.add_child(map_subviewport)
	city_view = CityView3DScene.instantiate()
	map_subviewport.add_child(city_view)
	if city_view.has_signal("cell_clicked"):
		city_view.cell_clicked.connect(click_cell)

	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size = Vector2(360, 0)
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 6)
	root.add_child(right_column)

	right_column.add_child(_label("Действия", 16))

	party_box = HFlowContainer.new()
	party_box.add_theme_constant_override("h_separation", 6)
	party_box.add_theme_constant_override("v_separation", 6)
	right_column.add_child(party_box)
	party_box.add_child(_button("Срез", func() -> void: _choose_party("slice")))
	party_box.add_child(_button("Прототип", func() -> void: _choose_party("prototype")))
	party_box.add_child(_button("Рим", func() -> void: _choose_scenario("rome")))
	party_box.add_child(_button("Неап.", func() -> void: _choose_scenario("neapolis")))
	party_box.add_child(_button("Тарент", func() -> void: _choose_scenario("tarentum")))

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	right_column.add_child(modes)
	overview_button = _button("Обзор", enter_overview)
	inspect_button = _button("Осмотр", enter_inspect)
	build_button = _button("Строительство", enter_build)
	modes.add_child(overview_button)
	modes.add_child(inspect_button)
	modes.add_child(build_button)
	view3d_button = _button("3D", _toggle_map_3d)
	modes.add_child(view3d_button)

	slice_modes = HFlowContainer.new()
	slice_modes.add_theme_constant_override("h_separation", 4)
	slice_modes.add_theme_constant_override("v_separation", 4)
	right_column.add_child(slice_modes)
	slice_mode_buttons = {
		"survey": _mode_button("Изуч.", "survey"),
		"prepare": _mode_button("Подг.", "prepare"),
		"road": _mode_button("Дорога", "road"),
		"build": _mode_button("Стройка", "build"),
		"research": _mode_button("Наука", "research"),
	}
	for key in slice_mode_buttons:
		slice_modes.add_child(slice_mode_buttons[key])

	var tools_scroll := ScrollContainer.new()
	tools_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_column.add_child(tools_scroll)
	var tools := VBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_theme_constant_override("separation", 6)
	tools_scroll.add_child(tools)
	build_box = VBoxContainer.new()
	build_box.add_theme_constant_override("separation", 4)
	tools.add_child(build_box)
	tech_box = VBoxContainer.new()
	tech_box.add_theme_constant_override("separation", 4)
	tools.add_child(tech_box)
	forecast_label = _wrapped("")
	tools.add_child(forecast_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	right_column.add_child(actions)
	end_button = _button("Конец хода", finish_turn)
	end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(end_button)
	actions.add_child(_button("Заново", restart))
	var file_actions := HBoxContainer.new()
	file_actions.add_theme_constant_override("separation", 6)
	right_column.add_child(file_actions)
	file_actions.add_child(_button("Сохранить", save_party))
	file_actions.add_child(_button("Загрузить", load_party))


func _refresh() -> void:
	var snap: Dictionary = game.snapshot
	var playing: bool = snap["mode"] == "play"
	title_label.text = _title(snap)
	if party == "slice":
		HudWidgets.fill_slice_dashboard(stats_host, game, font)
		HudWidgets.fill_neighbors(
			neighbors_host,
			snap,
			font,
			neighbor_peek,
			map_view_scenario,
			_peek_neighbor,
			_peek_neighbor_map,
			_view_player_map,
		)
		neighbors_host.get_parent().visible = true
	else:
		HudWidgets.fill_proto_dashboard(stats_host, game, font)
		neighbors_host.get_parent().visible = false
	HudWidgets.fill_pressures(pressure_host, snap, party == "slice", font)
	HudWidgets.fill_notes(notes_host, snap["notifications"], party == "slice", font)
	_highlight_modes()
	overview_button.disabled = not playing
	inspect_button.disabled = not playing
	build_button.disabled = not playing or party == "slice"
	build_button.visible = party == "prototype"
	view3d_button.visible = party == "slice"
	if party != "slice":
		map_3d = false
	slice_modes.visible = party == "slice" and playing and map_view_scenario == ""
	party_box.visible = true
	end_button.visible = playing
	var event_open := str(snap.get("current_event", "")) != "" and str(game.draft.get("event_option", "")) == ""
	end_button.disabled = event_open
	end_button.text = "Сначала событие" if event_open else "Закончить ход"
	var selected := _board_selection()
	var show_grid := playing and _map_edit_mode()
	var board_snap: Dictionary = _board_snapshot()
	var board_orders: Array = [] if map_view_scenario != "" else game.draft["orders"]
	var board_selected: Array = [] if map_view_scenario != "" else selected
	var board_grid: bool = show_grid and map_view_scenario == ""
	board.visible = party == "prototype" or (party == "slice" and not map_3d)
	map_viewport_container.visible = party == "slice" and map_3d
	if map_viewport_container.visible:
		_sync_map_viewport_size()
		city_view.call("apply_snapshot", board_snap, board_grid, board_selected, board_orders)
	board.set_view(board_snap, board_orders, board_selected, board_grid, font)
	_fill_orders()
	_fill_event()
	if party == "slice":
		_fill_slice_build()
		_fill_slice_tech()
	else:
		_fill_build()
	tech_box.visible = party == "slice" and mode == "research" and playing
	inspect_label.visible = playing and (mode == "inspect" or map_view_scenario != "")
	if map_3d and playing and party == "slice":
		if map_view_scenario != "":
			inspect_label.text = "3D · карта соседа. ЛКМ — сдвиг, клик — осмотр. Q/E, G сетка, колёсико к курсору."
		else:
			inspect_label.text = "3D-карта. ЛКМ — сдвиг, клик — как на сетке. Q/E, G, колёсико к курсору."
	elif map_view_scenario != "" and playing:
		inspect_label.text = "Карта соседа — только просмотр. Кликни клетку."
	forecast_label.visible = party == "prototype" and mode == "build" and playing
	if forecast_label.visible:
		forecast_label.text = _forecast_text()
	if not playing:
		message_label.text = SliceCopy.notes(snap["notifications"]) if party == "slice" else Copy.notes(snap["notifications"])


func _title(snap: Dictionary) -> String:
	var turn := "Ход %d" % int(snap["turn"])
	var era := "Древность" if party == "prototype" else "Срез · Италия"
	if snap["mode"] == "victory":
		return "Civitas · %s · победа · %s" % [era, turn]
	if snap["mode"] == "defeat":
		return "Civitas · %s · поражение · %s" % [era, turn]
	var where := _mode_label()
	if party == "slice" and map_view_scenario != "":
		var cities: Dictionary = snap.get("ai_cities", {})
		var city: Dictionary = cities.get(map_view_scenario, {})
		var cname := str(city.get("name", map_view_scenario))
		var view_tag := "3D · " if map_3d else ""
		return "Civitas · %s · %s · %sкарта: %s" % [era, turn, view_tag, cname]
	if party == "slice" and map_3d:
		return "Civitas · %s · %s · 3D · %s" % [era, turn, where]
	return "Civitas · %s · %s · %s" % [era, turn, where]


func _fill_orders() -> void:
	_clear(orders_box)
	var playing: bool = game.snapshot["mode"] == "play"
	var orders: Array = game.draft["orders"]
	if orders.is_empty():
		orders_box.add_child(_wrapped("Приказов нет — можно сразу завершить ход."))
		return
	for order in orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var card := HudWidgets.order_card(order, party == "slice", font)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		if playing and (party == "slice" or mode == "build"):
			var order_id := int(order["id"])
			row.add_child(_button("×", func() -> void: cancel_order(order_id)))
		orders_box.add_child(row)


func _fill_event() -> void:
	_clear(event_box)
	var event_id := str(game.snapshot["current_event"])
	event_box.visible = event_id != "" and game.snapshot["mode"] == "play"
	if not event_box.visible:
		return
	var definition: Dictionary = (
		SliceCatalog.event(event_id) if party == "slice" else Catalog.event(event_id)
	)
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("3a3028")
	frame_style.border_color = Color("e8c878")
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(8)
	frame_style.set_content_margin_all(12)
	frame.add_theme_stylebox_override("panel", frame_style)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	frame.add_child(inner)
	inner.add_child(
		HudWidgets.event_header(definition["name"], str(definition.get("text", "")), font)
	)
	for option_id in definition["options"]:
		var option: Dictionary = definition["options"][option_id]
		var captured := str(option_id)
		var label := SliceCopy.option_text(option) if party == "slice" else Copy.option_text(option)
		var button := _button(label, func() -> void: choose_option(captured))
		button.disabled = not _option_affordable(option)
		if str(game.draft["event_option"]) == captured:
			button.modulate = Color("e0a45a")
		inner.add_child(button)
	event_box.add_child(frame)


func _fill_build() -> void:
	_clear(build_box)
	build_box.visible = mode == "build" and game.snapshot["mode"] == "play"
	if not build_box.visible:
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	build_box.add_child(row)
	for type_id in Catalog.BUILDINGS:
		var captured := str(type_id)
		var definition: Dictionary = Catalog.BUILDINGS[type_id]
		var button := _button("%s\n%s" % [definition["name"], Copy.cost(definition["cost"])], func() -> void: pick_building(captured))
		button.tooltip_text = Copy.building_catalog_blurb(captured)
		if captured == selected_type:
			button.modulate = Color("e0a45a")
		row.add_child(button)
	if selected_type != "":
		var area := int(Catalog.building(selected_type)["area"])
		build_box.add_child(_wrapped(Copy.building_catalog_blurb(selected_type)))
		build_box.add_child(_wrapped("Клетки сторонами, %d из %d." % [selected_cells.size(), area]))
		var confirm := _button("Подтвердить постройку", confirm_selection)
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		build_box.add_child(confirm)
		build_box.add_child(_button("Сбросить клетки", _clear_cells))


func _forecast_text() -> String:
	if selected_type == "":
		return "Выбери здание. Сетка видна только здесь."
	var area := int(Catalog.building(selected_type)["area"])
	if selected_cells.size() != area:
		return "Отметь %d клеток. Сейчас %d. Сетка видна только в строительстве." % [area, selected_cells.size()]
	return Copy.forecast(game.forecast_build(selected_type, selected_cells))


func _inspect_at(x: int, y: int) -> String:
	if party == "slice":
		return _inspect_slice_state(_board_snapshot(), x, y)
	for building in game.snapshot["buildings"]:
		for cell in building["cells"]:
			if int(cell[0]) == x and int(cell[1]) == y:
				return Copy.building_blurb(building)
	return "На этой клетке ничего нет."


func _occupied(cell: Array) -> bool:
	var key := "%d,%d" % [int(cell[0]), int(cell[1])]
	for building in game.snapshot["buildings"]:
		for other in building["cells"]:
			if "%d,%d" % [int(other[0]), int(other[1])] == key:
				return true
	for order in game.draft["orders"]:
		for other in order["cells"]:
			if "%d,%d" % [int(other[0]), int(other[1])] == key:
				return true
	return false


func _selected_has(cell: Array) -> bool:
	for other in selected_cells:
		if int(other[0]) == int(cell[0]) and int(other[1]) == int(cell[1]):
			return true
	return false


func _without(cells: Array, cell: Array) -> Array:
	var kept: Array = []
	for other in cells:
		if int(other[0]) == int(cell[0]) and int(other[1]) == int(cell[1]):
			continue
		kept.append(other)
	return kept


func _slice_building_tech_unlocked(type_id: String) -> bool:
	var req := str(SliceCatalog.building(type_id).get("requires_tech", ""))
	if req == "":
		return true
	return SliceTech.is_researched(game.snapshot, req)


func _option_affordable(option: Dictionary) -> bool:
	for resource in option["cost"]:
		if game.available(resource) < int(option["cost"][resource]):
			return false
	return true


func _clear_cells() -> void:
	selected_cells = []
	prepare_cells = []
	road_cell = []
	_refresh()


func _mode_label() -> String:
	if party == "prototype":
		if mode == "inspect":
			return "осмотр"
		if mode == "build":
			return "строительство"
		return "обзор"
	match mode:
		"inspect":
			return "осмотр"
		"survey":
			return "изучение чанка"
		"prepare":
			return "подготовка"
		"road":
			return "дорога"
		"build":
			return "стройка"
		"research":
			return "наука"
		_:
			return "обзор"


func _map_edit_mode() -> bool:
	if party == "prototype":
		return mode == "build"
	return mode in ["survey", "prepare", "road", "build"]


func _board_selection() -> Array:
	if party != "slice":
		return selected_cells
	if mode == "prepare":
		return prepare_cells
	if mode == "road" and not road_cell.is_empty():
		return [road_cell]
	if mode == "build":
		return selected_cells
	return []


func _inspect_slice_state(state: Dictionary, x: int, y: int) -> String:
	for building in state["buildings"]:
		for cell in building["cells"]:
			if int(cell[0]) == x and int(cell[1]) == y:
				return SliceCopy.building_blurb(building)
	for road in state.get("roads", []):
		for cell in road["cells"]:
			if int(cell[0]) == x and int(cell[1]) == y:
				return "Дорога\n%s" % SliceCopy._status(
					{"status": road.get("status", "working"), "timer": road.get("timer", 0)}
				)
	var deposit: Dictionary = SliceMap.visible_deposit(state.get("map_cells", {}), x, y)
	if not deposit.is_empty():
		return "Залежь %s, осталось %d." % [deposit["resource"], int(deposit["left"])]
	return "Пустая клетка карты среза."


func _sync_map_viewport_size() -> void:
	if map_subviewport == null or map_viewport_container == null:
		return
	var sz := map_viewport_container.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	map_subviewport.size = Vector2i(int(sz.x), int(sz.y))


func _click_slice_cell(x: int, y: int) -> void:
	if map_view_scenario != "":
		inspect_label.text = _inspect_at(x, y)
		_refresh()
		return
	if mode == "inspect":
		inspect_label.text = _inspect_at(x, y)
		return
	match mode:
		"survey":
			var chunk: Array = game.chunk_at_cell(x, y)
			var result: Dictionary = game.survey_order(int(chunk[0]), int(chunk[1]))
			message_label.text = "" if result["ok"] else str(result["error"])
		"prepare":
			_toggle_prepare_cell(x, y)
		"road":
			road_cell = [x, y]
		"build":
			if selected_type == "":
				message_label.text = "Сначала выбери здание."
				return
			var cell := [x, y]
			if _selected_has(cell):
				selected_cells = _without(selected_cells, cell)
			else:
				var area := int(SliceCatalog.building(selected_type)["area"])
				if selected_cells.size() >= area:
					message_label.text = "Площадь уже набрана."
					return
				selected_cells.append(cell)
		_:
			message_label.text = "Выбери режим карты: изучение, подготовка, дорога или стройка."
	_refresh()


func _toggle_prepare_cell(x: int, y: int) -> void:
	for i in prepare_cells.size():
		var cell: Array = prepare_cells[i]
		if int(cell[0]) == x and int(cell[1]) == y:
			prepare_cells.remove_at(i)
			_refresh()
			return
	prepare_cells.append([x, y])
	_refresh()


func _confirm_slice() -> String:
	match mode:
		"prepare":
			if prepare_cells.is_empty():
				return "Нечего подтверждать."
			var result: Dictionary = game.prepare_order(prepare_cells)
			if not result["ok"]:
				message_label.text = str(result["error"])
				return str(result["error"])
			prepare_cells = []
		"road":
			if road_cell.is_empty():
				return "Нечего подтверждать."
			var road_result: Dictionary = game.road_order(road_cell)
			if not road_result["ok"]:
				message_label.text = str(road_result["error"])
				return str(road_result["error"])
			road_cell = []
		"build":
			if selected_type == "" or selected_cells.is_empty():
				return "Нечего подтверждать."
			var build_result: Dictionary = game.build_order(selected_type, selected_cells)
			if not build_result["ok"]:
				message_label.text = str(build_result["error"])
				return str(build_result["error"])
			selected_cells = []
		"research":
			if tech_pick == "":
				return "Выбери технологию."
			var tech_result: Dictionary = game.research_order(tech_pick)
			if not tech_result["ok"]:
				message_label.text = str(tech_result["error"])
				return str(tech_result["error"])
			tech_pick = ""
		_:
			return "В этом режиме нет подтверждения."
	message_label.text = "Приказ записан."
	_refresh()
	return ""


func pick_technology(tech_id: String) -> void:
	if party != "slice" or mode != "research" or _over():
		return
	tech_pick = tech_id
	_refresh()


func _fill_slice_build() -> void:
	_clear(build_box)
	var playing: bool = game.snapshot["mode"] == "play"
	build_box.visible = playing and mode in ["prepare", "road", "build"]
	if not build_box.visible:
		return
	if mode == "prepare":
		build_box.add_child(_wrapped("Отметь клетки на карте. Сетка включена."))
		build_box.add_child(_wrapped("Выбрано: %d." % prepare_cells.size()))
		build_box.add_child(_button("Подтвердить подготовку", confirm_selection))
		build_box.add_child(_button("Сбросить клетки", _clear_cells))
		return
	if mode == "road":
		build_box.add_child(_wrapped("Кликни клетку дороги. 2 дерева, 1 ход."))
		build_box.add_child(_button("Подтвердить дорогу", confirm_selection))
		return
	if selected_type != "" and not _slice_building_tech_unlocked(selected_type):
		selected_type = ""
		selected_cells = []
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	build_box.add_child(row)
	for type_id in SliceCatalog.building_ids():
		var definition: Dictionary = SliceCatalog.building(type_id)
		if not bool(definition.get("player_buildable", true)):
			continue
		var captured := str(type_id)
		var unlocked := _slice_building_tech_unlocked(captured)
		var button := _building_button(definition["name"], SliceCopy.cost(definition["cost"]), captured)
		button.tooltip_text = SliceCopy.building_catalog_blurb(captured)
		button.disabled = not unlocked
		if captured == selected_type and unlocked:
			button.modulate = Color("e0a45a")
		row.add_child(button)
	if selected_type != "":
		var area := int(SliceCatalog.building(selected_type)["area"])
		build_box.add_child(_wrapped(SliceCopy.building_catalog_blurb(selected_type)))
		build_box.add_child(_wrapped("Клетки сторонами, %d из %d." % [selected_cells.size(), area]))
		build_box.add_child(_button("Подтвердить постройку", confirm_selection))
		build_box.add_child(_button("Сбросить клетки", _clear_cells))


func _fill_slice_tech() -> void:
	_clear(tech_box)
	if party != "slice" or mode != "research" or game.snapshot["mode"] != "play":
		return
	for tech_id in SliceCatalog.technology_ids():
		var definition: Dictionary = SliceCatalog.technology(tech_id)
		var captured := str(tech_id)
		var button := _button(
			"%s\n%d науки" % [definition["name"], int(definition["cost"])],
			func() -> void: pick_technology(captured),
		)
		if captured == tech_pick:
			button.modulate = Color("e0a45a")
		tech_box.add_child(button)
	tech_box.add_child(_button("Начать изучение", confirm_selection))


func _over() -> bool:
	return game.snapshot["mode"] != "play"


func _panel(title: String, body: Control) -> PanelContainer:
	var box := VBoxContainer.new()
	box.add_child(_label(title, 16))
	box.add_child(body)
	return _wrap(box)


func _panel_box(title: String, body: Control) -> PanelContainer:
	var box := VBoxContainer.new()
	box.add_child(_label(title, 16))
	box.add_child(body)
	return _wrap(box)


func _scroll_panel(title: String, body: Control) -> PanelContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 72)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var box := VBoxContainer.new()
	box.add_child(_label(title, 16))
	box.add_child(scroll)
	return _wrap(box)


func _wrap(child: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a241c")
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(child)
	return panel


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f3ead7"))
	return label


func _wrapped(text: String) -> Label:
	var label := _label(text, 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: call_deferred("_call", callback))
	button.add_theme_color_override("font_color", Color("1c1915"))
	button.add_theme_color_override("font_hover_color", Color("1c1915"))
	button.add_theme_font_size_override("font_size", 14)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("e7d7b8")
	normal.set_content_margin_all(8)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate()
	hover.bg_color = Color("f3ead7")
	var disabled := normal.duplicate()
	disabled.bg_color = Color("6d6456")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	return button


func _call(callback: Callable) -> void:
	callback.call()


func _mode_button(caption: String, slice_mode: String) -> Button:
	return _button(caption, func() -> void: enter_slice_mode(slice_mode))


func _building_button(title: String, cost_line: String, type_id: String) -> Button:
	var button := _button("%s\n%s" % [title, cost_line], func() -> void: pick_building(type_id))
	var style := button.get_theme_stylebox("normal") as StyleBoxFlat
	if style != null:
		style.border_color = HudWidgets.ORDER_COLORS.get("build", Color.GRAY)
		style.set_border_width_all(0)
		style.border_width_left = 4
	return button


func _highlight_modes() -> void:
	var active := Color("f3ead7")
	var idle := Color("8a8070")
	for key in slice_mode_buttons:
		var button: Button = slice_mode_buttons[key]
		var on: bool = party == "slice" and mode == key
		button.modulate = active if on else idle
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		if style != null:
			style.bg_color = Color("e7d7b8") if on else Color("c8bca4")
	overview_button.modulate = active if mode == "overview" else idle
	inspect_button.modulate = active if mode == "inspect" else idle
	build_button.modulate = active if mode == "build" and party == "prototype" else idle
	if view3d_button != null:
		view3d_button.modulate = active if party == "slice" and map_3d else idle
		view3d_button.text = "2D" if map_3d else "3D"
		var vstyle := view3d_button.get_theme_stylebox("normal") as StyleBoxFlat
		if vstyle != null:
			vstyle.bg_color = Color("e7d7b8") if map_3d else Color("c8bca4")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()
