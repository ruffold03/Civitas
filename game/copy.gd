extends RefCounted

const Catalog = preload("res://sim/civ_catalog.gd")
const Rules = preload("res://sim/civ_rules.gd")
const Turn = preload("res://sim/civ_turn.gd")

const GENITIVE := {"food": "еды", "wood": "дерева", "stone": "камня"}


static func stats(game) -> String:
	var snap: Dictionary = game.snapshot
	var stocks: Dictionary = snap["stocks"]
	var storage: Dictionary = snap["storage"]
	var pop := int(snap["pop"])
	var need := Rules.consumption_need(pop, snap["effects"])
	var lines: PackedStringArray = [
		"Люди %d, мест %d" % [pop, int(snap["pop_capacity"])],
		growth(game),
		"Лояльность %d" % int(snap["loyalty"]),
		"Вода на %d человек" % Rules.water_coverage(snap["buildings"]),
		"На этот ход съедят %d еды" % need,
	]
	for resource in Catalog.RESOURCES:
		lines.append("%s %d/%d, свободно %d" % [
			Catalog.RESOURCE_NAMES[resource],
			int(stocks[resource]),
			int(storage[resource]),
			game.available(resource),
		])
	if not snap["loyalty_sources"].is_empty():
		lines.append("Откуда лояльность: " + _sources(snap["loyalty_sources"]))
	var effects := _effects(snap["effects"])
	if effects != "":
		lines.append(effects)
	return "\n".join(lines)


static func growth(game) -> String:
	if str(game.snapshot["mode"]) != "play":
		return "Скорость больше не считается."
	var preview: Dictionary = Turn.resolve(game.snapshot, game.draft)
	var note := _population_note(preview["notifications"])
	var lines: PackedStringArray = [
		"Скорость %+d, если закончить ход" % int(note["speed"]),
		_speed_parts(note["sources"], true),
		"Людей станет %d" % int(note["after"]),
	]
	var extra := _speed_parts(note["sources"], false)
	if extra != "":
		lines.append("Сверх скорости: %s." % extra)
	if str(game.snapshot["current_event"]) != "" and str(game.draft["event_option"]) == "":
		lines.append("Ответ на событие сюда ещё не входит.")
	return "\n".join(lines)


static func _population_note(notes: Array) -> Dictionary:
	for note in notes:
		if note["kind"] == "population":
			return note
	return {"speed": 0, "after": 0, "before": 0, "sources": []}


static func _speed_parts(sources: Array, in_speed: bool) -> String:
	var parts: PackedStringArray = []
	for source in sources:
		var counts := true
		if source.has("in_speed"):
			counts = bool(source["in_speed"])
		if counts != in_speed:
			continue
		parts.append("%s %+d" % [_source_name(str(source["source"])), int(source["amount"])])
	return ", ".join(parts)


static func pressures(snap: Dictionary) -> String:
	var lines: PackedStringArray = []
	var pop := int(snap["pop"])
	var need := Rules.consumption_need(pop, snap["effects"])
	if int(snap["stocks"]["food"]) < need:
		lines.append("Еды не хватит: есть %d, нужно %d." % [int(snap["stocks"]["food"]), need])
	var capacity := int(snap["pop_capacity"])
	if pop > capacity:
		lines.append("Тесно: %d человек на %d мест." % [pop, capacity])
	var drop := 0
	for source in snap["loyalty_sources"]:
		drop += int(source["amount"])
	if drop < 0:
		lines.append("В прошлый ход лояльность снизилась на %d." % -drop)
	for building in snap["buildings"]:
		if building["status"] == "idle":
			lines.append("%s простаивает." % Catalog.building(building["type"])["name"])
	if str(snap["current_event"]) != "":
		lines.append("Ждёт выбора: %s." % Catalog.event(snap["current_event"])["name"])
	if lines.is_empty():
		return "Явного давления нет."
	return "\n".join(lines)


static func notes(list: Array) -> String:
	var lines: PackedStringArray = []
	for note in list:
		var line := _note(note)
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return "Ход ещё не считался."
	return "\n".join(lines)


static func cost(price: Dictionary) -> String:
	if price.is_empty():
		return "бесплатно"
	var parts: PackedStringArray = []
	for resource in Catalog.RESOURCES:
		if price.has(resource) and int(price[resource]) != 0:
			parts.append("%d %s" % [int(price[resource]), GENITIVE[resource]])
	return ", ".join(parts)


static func forecast(info: Dictionary) -> String:
	if not info["ok"]:
		return str(info["error"])
	var parts: PackedStringArray = [
		"Списать %s." % cost(info["cost"]),
		"Срок %s." % _turns(int(info["build_time"])),
	]
	if int(info["pop_capacity"]) != 0:
		parts.append("+%d мест." % int(info["pop_capacity"]))
	if int(info["water"]) != 0:
		parts.append("Вода на %d человек." % int(info["water"]))
	var outputs: Dictionary = info["outputs"]
	for resource in outputs:
		parts.append("+%d %s за ход." % [int(outputs[resource]), GENITIVE[resource]])
	var extra: Dictionary = info["storage"]
	for resource in extra:
		parts.append("Вместимость %s +%d." % [GENITIVE[resource], int(extra[resource])])
	var inputs: Dictionary = info["inputs"]
	if not inputs.is_empty():
		parts.append("Каждый ход нужно %s, иначе простой." % cost(inputs))
	if int(info["loyalty"]) != 0:
		parts.append("Лояльность %+d, пока работает." % int(info["loyalty"]))
	parts.append("Дальше людей и шкалу этот прогноз не считает.")
	return " ".join(parts)


static func option_text(option: Dictionary) -> String:
	var lines: PackedStringArray = [option["name"]]
	if not option["cost"].is_empty():
		lines.append("Сразу %s." % cost(option["cost"]))
	for effect in option["effects"]:
		lines.append(_effect(effect))
	return "\n".join(lines)


static func building_catalog_blurb(type_id: String) -> String:
	var definition: Dictionary = Catalog.building(type_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d клеток · стройка %s." % [int(definition["area"]), _turns(int(definition["build_time"]))])
	if not definition["cost"].is_empty():
		lines.append("Цена: %s." % cost(definition["cost"]))
	var outputs: Dictionary = definition["outputs"]
	for resource in outputs:
		lines.append("+%d %s за ход." % [int(outputs[resource]), GENITIVE[resource]])
	var inputs: Dictionary = definition["inputs"]
	if not inputs.is_empty():
		lines.append("Расход %s за ход." % cost(inputs))
	if int(definition["pop_capacity"]) > 0:
		lines.append("+%d мест." % int(definition["pop_capacity"]))
	if int(definition["water"]) > 0:
		lines.append("Вода на %d человек." % int(definition["water"]))
	if int(definition["loyalty"]) != 0:
		lines.append("Лояльность %+d." % int(definition["loyalty"]))
	var storage: Dictionary = definition["storage"]
	for resource in storage:
		lines.append("Склад %s +%d." % [GENITIVE[resource], int(storage[resource])])
	return "\n".join(lines)


static func building_blurb(building: Dictionary) -> String:
	var definition: Dictionary = Catalog.building(building["type"])
	var status := _status(building)
	var born := "Стоит с начала партии."
	if int(building["born_turn"]) > 0:
		born = "Приказано на ходу %d." % int(building["born_turn"])
	return "%s\n%s\n%s\nКлеток: %d" % [definition["name"], status, born, building["cells"].size()]


static func order_line(order: Dictionary) -> String:
	var definition: Dictionary = Catalog.building(order["type"])
	return "%s, %s" % [definition["name"], cost(order["reserve"])]


static func _sources(sources: Array) -> String:
	var parts: PackedStringArray = []
	for source in sources:
		if int(source["amount"]) == 0:
			continue
		parts.append("%s %+d" % [_source_name(str(source["source"])), int(source["amount"])])
	if parts.is_empty():
		return "без изменений"
	return ", ".join(parts)


static func _source_name(source: String) -> String:
	if source == "base":
		return "база"
	if source == "housing":
		return "жильё"
	if source == "water":
		return "вода"
	if source == "food":
		return "еда"
	if source == "loyalty":
		return "прошлая лояльность"
	if Catalog.has_building(source):
		return str(Catalog.building(source)["name"]).to_lower()
	if Catalog.EVENTS.has(source):
		return str(Catalog.event(source)["name"]).to_lower()
	return source


static func _effects(effects: Array) -> String:
	var lines: PackedStringArray = []
	for effect in effects:
		lines.append("%s: %s" % [effect["source_name"], _effect(effect)])
	return "\n".join(lines)


static func _effect(effect: Dictionary) -> String:
	var amount := int(effect["amount"])
	var left := int(effect["remaining"])
	match str(effect["kind"]):
		"pop_bonus_once":
			return "+%d человек в ход прихода. Едят со следующего хода." % amount
		"loyalty_delta":
			return "%+d лояльности каждый ход, ещё %s." % [amount, _turns(left)]
		"consumption_half_extra":
			return "Еды нужно на половину больше, ещё %s." % _turns(left)
		"pop_speed_delta":
			return "Скорость населения %+d, ещё %s." % [amount, _turns(left)]
		"field_food_add":
			return "Каждое работающее поле %+d еды, ещё %s. Загоны не меняются." % [amount, _turns(left)]
		"field_food_replace":
			return "Каждое работающее поле даёт %d еды вместо 8, ещё %s." % [amount, _turns(left)]
		_:
			return str(effect["kind"])


static func _note(note: Dictionary) -> String:
	match str(note["kind"]):
		"consumption":
			if note["band"] == "shortage":
				return "Еды не хватило: нужно %d, было %d." % [int(note["needed"]), int(note["paid"])]
			if note["band"] == "tight":
				return "Еда вышла впритык, съели %d." % int(note["paid"])
			return "Еды хватило с запасом, съели %d." % int(note["paid"])
		"population":
			var line := "Людей стало %d, было %d. Скорость %+d: %s." % [
				int(note["after"]),
				int(note["before"]),
				int(note["speed"]),
				_speed_parts(note["sources"], true),
			]
			var extra := _speed_parts(note["sources"], false)
			if extra != "":
				line += " Сверх скорости: %s." % extra
			return line
		"loyalty":
			return "Лояльность %d (%+d)." % [int(note["after"]), int(note["delta"])]
		"completed":
			return "%s достроено." % Catalog.building(note["type"])["name"]
		"idle":
			return "%s простаивает." % Catalog.building(note["type"])["name"]
		"spoil":
			return "Лишнее пропало: %d %s." % [int(note["amount"]), GENITIVE[note["resource"]]]
		"event":
			return "Началось событие: %s." % Catalog.event(note["event"])["name"]
		"victory":
			return "В поселении сто человек. Партия выиграна."
		"defeat":
			return "Людей не осталось. Партия проиграна."
		_:
			return ""


static func _status(building: Dictionary) -> String:
	match str(building["status"]):
		"building":
			return "Строится, ещё %s." % _turns(int(building["timer"]))
		"idle":
			return "Простаивает."
		_:
			return "Работает."


static func _turns(count: int) -> String:
	var mod10 := count % 10
	var mod100 := count % 100
	if mod10 == 1 and mod100 != 11:
		return "%d ход" % count
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
		return "%d хода" % count
	return "%d ходов" % count
