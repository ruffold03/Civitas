class_name HudWidgets
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")
const CivCatalog = preload("res://sim/civ_catalog.gd")
const CivRules = preload("res://sim/civ_rules.gd")
const SliceCopy = preload("res://game/slice_copy.gd")
const Copy = preload("res://game/copy.gd")

const RESOURCE_COLORS := {
	"food": Color("c9a84a"),
	"wood": Color("6b8f4e"),
	"stone": Color("8a8378"),
	"clay": Color("b08060"),
	"metal": Color("707880"),
	"wine": Color("7a4a6a"),
	"money": Color("d4a85a"),
}

const ORDER_COLORS := {
	"survey": Color("6a9ec8"),
	"prepare": Color("c9a04a"),
	"road": Color("6a5a48"),
	"chop": Color("4a7a3a"),
	"build": Color("8d5a3c"),
}


static func clear(host: Control) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()


static func fill_slice_dashboard(host: VBoxContainer, game, font: Font) -> void:
	clear(host)
	var snap: Dictionary = game.snapshot
	var scenario: Dictionary = CivSliceScenario.SCENARIOS.get(str(snap.get("scenario", "rome")), {})
	host.add_child(_city_header(str(scenario.get("name", "Город")), int(snap["turn"]), font))
	host.add_child(_chip_row(font, [
		_chip("Люди", "%d / %d" % [int(snap["pop"]), int(snap["pop_capacity"])], Color("d8c4a0")),
		_chip("Лояльн.", str(int(snap["loyalty"])), _loyalty_color(int(snap["loyalty"]))),
		_chip("Престиж", str(int(snap.get("prestige", 0))), Color("9ec5ff")),
	]))
	var need: int = CivSliceRules.consumption_need(int(snap["pop"]), snap["effects"])
	var food_stock := int(snap["stocks"].get("food", 0))
	host.add_child(
		_chip_row(font, [
			_chip("Еда/ход", "%d нужно" % need, Color("c9a84a") if food_stock >= need else Color("c85a4a")),
			_chip("Вода", str(CivSliceRules.water_coverage(snap["buildings"])), Color("6ea8c9")),
		])
	)
	host.add_child(_section_label("Наука", font))
	host.add_child(_science_block(snap, font))
	host.add_child(_section_label("Склады", font))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	host.add_child(grid)
	for resource in CivSliceCatalog.RESOURCES:
		var cap := int(snap["storage"].get(resource, 0))
		if cap <= 0 and resource == "money":
			continue
		grid.add_child(
			_resource_bar(
				font,
				CivSliceCatalog.RESOURCE_NAMES[resource],
				int(snap["stocks"].get(resource, 0)),
				cap,
				game.available(resource),
				RESOURCE_COLORS.get(resource, Color.GRAY),
			)
		)
static func fill_proto_dashboard(host: VBoxContainer, game, font: Font) -> void:
	clear(host)
	var snap: Dictionary = game.snapshot
	host.add_child(_city_header("Поселение", int(snap["turn"]), font))
	host.add_child(_chip_row(font, [
		_chip("Люди", "%d / %d" % [int(snap["pop"]), int(snap["pop_capacity"])], Color("d8c4a0")),
		_chip("Лояльн.", str(int(snap["loyalty"])), _loyalty_color(int(snap["loyalty"]))),
	]))
	var need: int = CivRules.consumption_need(int(snap["pop"]), snap["effects"])
	host.add_child(
		_chip_row(font, [
			_chip("Еда/ход", str(need), Color("c9a84a")),
			_chip("Вода", str(CivRules.water_coverage(snap["buildings"])), Color("6ea8c9")),
		])
	)
	host.add_child(_section_label("Склады", font))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 6)
	host.add_child(grid)
	for resource in CivCatalog.RESOURCES:
		grid.add_child(
			_resource_bar(
				font,
				CivCatalog.RESOURCE_NAMES[resource],
				int(snap["stocks"][resource]),
				int(snap["storage"][resource]),
				game.available(resource),
				RESOURCE_COLORS.get(resource, Color.GRAY),
			)
		)


static func fill_neighbors(
	host: VBoxContainer,
	snap: Dictionary,
	font: Font,
	peek_id: String,
	map_view_id: String,
	on_peek: Callable,
	on_map: Callable,
	on_home: Callable,
) -> void:
	clear(host)
	if not snap.has("ai_cities") or snap["ai_cities"].is_empty():
		return
	if map_view_id != "":
		var home := Button.new()
		home.text = "Мой город на карте"
		home.add_theme_font_size_override("font_size", 13)
		home.pressed.connect(func() -> void: on_home.call())
		host.add_child(home)
	for scenario_id in snap["ai_cities"].keys():
		var city: Dictionary = snap["ai_cities"][scenario_id]
		var sid := str(scenario_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var goal := "население" if str(city.get("victory_goal", "")) == "population" else "экономика"
		var title := _chip(
			str(city.get("name", sid)),
			"%d чел. · %s" % [int(city.get("pop", 0)), goal],
			Color("a8b8c8"),
		)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var stock := Button.new()
		stock.text = "Склад" if peek_id != sid else "Скрыть"
		stock.add_theme_font_size_override("font_size", 13)
		stock.pressed.connect(func() -> void: on_peek.call(sid))
		row.add_child(stock)
		var map_btn := Button.new()
		map_btn.text = "Карта" if map_view_id != sid else "Закрыть"
		map_btn.add_theme_font_size_override("font_size", 13)
		map_btn.pressed.connect(func() -> void: on_map.call(sid))
		row.add_child(map_btn)
		host.add_child(row)
	if peek_id == "" or not snap["ai_cities"].has(peek_id):
		return
	var city: Dictionary = snap["ai_cities"][peek_id]
	host.add_child(_section_label("Склад · %s" % str(city.get("name", peek_id)), font))
	host.add_child(
		_chip_row(font, [
			_chip("Люди", str(int(city.get("pop", 0))), Color("d8c4a0")),
			_chip("Лояльн.", str(int(city.get("loyalty", 0))), _loyalty_color(int(city.get("loyalty", 0)))),
			_chip("Престиж", str(int(city.get("prestige", 0))), Color("9ec5ff")),
		])
	)
	var caps: Dictionary = CivSliceRules.storage_caps(city["buildings"], city.get("technologies", []))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	host.add_child(grid)
	for resource in CivSliceCatalog.RESOURCES:
		var cap := int(caps.get(resource, 0))
		if cap <= 0 and resource == "money":
			continue
		grid.add_child(
			_resource_bar(
				font,
				CivSliceCatalog.RESOURCE_NAMES[resource],
				int(city["stocks"].get(resource, 0)),
				cap,
				int(city["stocks"].get(resource, 0)),
				RESOURCE_COLORS.get(resource, Color.GRAY),
			)
		)


static func fill_pressures(host: Control, snap: Dictionary, slice: bool, font: Font) -> void:
	clear(host)
	var items: Array = _pressure_items(snap, slice)
	if items.is_empty():
		host.add_child(_muted_label("Всё спокойно", font))
		return
	for item in items:
		host.add_child(_alert_pill(str(item["text"]), str(item["level"]), font))


static func fill_notes(host: VBoxContainer, notifications: Array, slice: bool, font: Font) -> void:
	clear(host)
	var lines: PackedStringArray = PackedStringArray()
	if slice:
		lines = SliceCopyLines.from_notifications(notifications)
	else:
		lines = ProtoCopyLines.from_notifications(notifications)
	if lines.is_empty():
		host.add_child(_muted_label("Ход ещё не считался", font))
		return
	for line in lines:
		host.add_child(_note_row(str(line), font))


static func order_card(order: Dictionary, slice: bool, font: Font) -> Control:
	var kind := str(order.get("kind", "build"))
	var color: Color = ORDER_COLORS.get(kind, Color("8d5a3c"))
	var title := ""
	var subtitle := ""
	if slice:
		title = _slice_order_title(order)
		subtitle = SliceCopyLines.order_subtitle(order)
	else:
		title = CivCatalog.building(order["type"])["name"]
		subtitle = ProtoCopyLines.cost_line(order["reserve"])
	return _card(color, title, subtitle, font)


static func event_header(name: String, body: String, font: Font) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_section_label(name, font, Color("e8c878")))
	box.add_child(_muted_label(body, font))
	return box


static func _pressure_items(snap: Dictionary, slice: bool) -> Array:
	var items: Array = []
	var pop := int(snap["pop"])
	var need: int = (
		CivSliceRules.consumption_need(pop, snap["effects"])
		if slice
		else CivRules.consumption_need(pop, snap["effects"])
	)
	var food := int(snap["stocks"]["food"])
	if food < need:
		items.append({"text": "Еды мало: %d / %d" % [food, need], "level": "danger"})
	var capacity := int(snap["pop_capacity"])
	if pop > capacity:
		items.append({"text": "Переполнение жилья", "level": "danger"})
	for building in snap["buildings"]:
		if str(building["status"]) == "idle":
			var bname: String = (
				CivSliceCatalog.building(building["type"])["name"]
				if slice
				else CivCatalog.building(building["type"])["name"]
			)
			items.append({"text": "%s простаивает" % bname, "level": "warn"})
	if str(snap.get("current_event", "")) != "":
		var ename: String = (
			CivSliceCatalog.event(snap["current_event"])["name"]
			if slice
			else CivCatalog.event(snap["current_event"])["name"]
		)
		items.append({"text": "Событие: %s" % ename, "level": "info"})
	return items


static func _slice_order_title(order: Dictionary) -> String:
	match str(order.get("kind", "build")):
		"survey":
			return "Изучение чанка"
		"prepare":
			return "Подготовка (%d)" % order["cells"].size()
		"road":
			return "Дорога"
		"chop":
			return "Рубка леса"
		_:
			return CivSliceCatalog.building(order["type"])["name"]


static func _city_header(city: String, turn: int, font: Font) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := _label(city, 18, Color("f3ead7"))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(_chip("Ход", str(turn), Color("4a4238")))
	return row


static func _science_block(snap: Dictionary, font: Font) -> Control:
	var research := str(snap.get("research", ""))
	if research != "":
		var prog := int(snap.get("tech_progress", {}).get(research, 0))
		var cost := int(CivSliceCatalog.technology(research)["cost"])
		return _meter_bar(font, CivSliceCatalog.technology(research)["name"], prog, cost, Color("9ec5ff"))
	var bank := int(snap.get("science", 0))
	return _meter_bar(font, "Запас науки", bank, maxi(bank, 1), Color("b8a888"))


static func _chip_row(font: Font, chips: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for chip in chips:
		row.add_child(chip)
	return row


static func _chip(title: String, value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2f2a22")
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	col.add_child(_label(title, 11, Color("a89a82")))
	col.add_child(_label(value, 16, Color("f3ead7")))
	return panel


static func _resource_bar(
	font: Font,
	title: String,
	amount: int,
	cap: int,
	free: int,
	fill_color: Color
) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	head.add_child(_label(title, 13, Color("d8c4a0")))
	head.add_child(_spacer())
	head.add_child(_label("%d / %d" % [amount, cap], 13, Color("f3ead7")))
	box.add_child(head)
	box.add_child(_bar(amount, cap, fill_color))
	box.add_child(_muted_label("Свободно для приказа: %d" % free, font))
	return box


static func _meter_bar(font: Font, title: String, value: int, max_value: int, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label("%s  %d / %d" % [title, value, max_value], 13, Color("e8dcc8")))
	box.add_child(_bar(value, max_value, color))
	return box


static func _bar(value: int, max_value: int, fill_color: Color) -> Control:
	var back := PanelContainer.new()
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color("1a1714")
	back_style.set_corner_radius_all(4)
	back.add_theme_stylebox_override("panel", back_style)
	back.custom_minimum_size = Vector2(0, 10)
	var ratio: float = 0.0 if max_value <= 0 else clampf(float(value) / float(max_value), 0.0, 1.0)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.anchor_right = ratio
	fill.anchor_bottom = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return back


static func _card(accent: Color, title: String, subtitle: String, font: Font) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a241c")
	style.border_color = accent
	style.set_border_width_all(0)
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(_label(title, 15, Color("f3ead7")))
	if subtitle != "":
		col.add_child(_muted_label(subtitle, font))
	return panel


static func _alert_pill(text: String, level: String, font: Font) -> PanelContainer:
	var color: Color = Color("6a9ec8")
	match level:
		"danger":
			color = Color("c85a4a")
		"warn":
			color = Color("c9a04a")
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(_label(text, 13, Color("f3ead7")))
	return panel


static func _note_row(text: String, font: Font) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = Color("9ec5ff")
	row.add_child(dot)
	var label := _muted_label(text, font)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


static func _section_label(text: String, font: Font, color: Color = Color("a89a82")) -> Label:
	return _label(text, 12, color)


static func _muted_label(text: String, font: Font) -> Label:
	var label := _label(text, 13, Color("a89a82"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func _spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func _loyalty_color(value: int) -> Color:
	if value >= 55:
		return Color("6b9e5a")
	if value >= 35:
		return Color("c9a04a")
	return Color("c85a4a")


class SliceCopyLines:
	extends RefCounted

	static func order_subtitle(order: Dictionary) -> String:
		match str(order.get("kind", "build")):
			"survey":
				return "Чанк %d,%d · 3 хода" % [int(order["chunk_x"]), int(order["chunk_y"])]
			"prepare":
				return "%d клеток" % order["cells"].size()
			"road":
				return "2 дерева · 1 ход"
			"chop":
				return "+8 дерева · 1 ход"
			_:
				return _cost(order["reserve"])

	static func from_notifications(notifications: Array) -> PackedStringArray:
		var text := SliceCopy.notes(notifications)
		if text == "Ход ещё не считался.":
			return []
		return text.split("\n", false)

	static func _cost(price: Dictionary) -> String:
		var parts: PackedStringArray = []
		for resource in price:
			if int(price[resource]) != 0:
				parts.append("%d %s" % [int(price[resource]), resource])
		return ", ".join(parts)


class ProtoCopyLines:
	extends RefCounted

	static func cost_line(price: Dictionary) -> String:
		var parts: PackedStringArray = []
		for resource in CivCatalog.RESOURCES:
			if price.has(resource) and int(price[resource]) != 0:
				parts.append("%d %s" % [int(price[resource]), resource])
		return ", ".join(parts)

	static func from_notifications(notifications: Array) -> PackedStringArray:
		var text := Copy.notes(notifications)
		if text == "Ход ещё не считался.":
			return []
		return text.split("\n", false)
