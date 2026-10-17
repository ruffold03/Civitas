extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")

const GENITIVE := {
	"food": "еды",
	"wood": "дерева",
	"stone": "камня",
	"clay": "глины",
	"metal": "металла",
	"wine": "вина",
	"money": "денег",
}


static func stats(game) -> String:
	var snap: Dictionary = game.snapshot
	var stocks: Dictionary = snap["stocks"]
	var storage: Dictionary = snap["storage"]
	var pop := int(snap["pop"])
	var need := CivSliceRules.consumption_need(pop, snap["effects"])
	var scenario: Dictionary = CivSliceScenario.SCENARIOS.get(str(snap.get("scenario", "rome")), {})
	var name := str(scenario.get("name", snap.get("scenario", "")))
	var lines: PackedStringArray = [
		"%s · %s" % [name, str(snap.get("foundation", ""))],
		"Люди %d, мест %d" % [pop, int(snap["pop_capacity"])],
		"Лояльность %d · престиж %d" % [int(snap["loyalty"]), int(snap.get("prestige", 0))],
		"Вода на %d человек" % CivSliceRules.water_coverage(snap["buildings"]),
		"На ход нужно %d еды" % need,
	]
	var research := str(snap.get("research", ""))
	if research != "":
		var prog := int(snap.get("tech_progress", {}).get(research, 0))
		var cost := int(CivSliceCatalog.technology(research)["cost"])
		lines.append(
			"Наука: %s %d/%d" % [CivSliceCatalog.technology(research)["name"], prog, cost]
		)
	else:
		lines.append("Запас науки %d" % int(snap.get("science", 0)))
	for resource in CivSliceCatalog.RESOURCES:
		var cap := int(storage.get(resource, 0))
		if cap <= 0 and resource == "money":
			continue
		lines.append(
			"%s %d/%d, свободно %d" % [
				CivSliceCatalog.RESOURCE_NAMES[resource],
				int(stocks.get(resource, 0)),
				cap,
				game.available(resource),
			]
		)
	return "\n".join(lines)


static func pressures(snap: Dictionary) -> String:
	var lines: PackedStringArray = []
	var pop := int(snap["pop"])
	var need := CivSliceRules.consumption_need(pop, snap["effects"])
	if int(snap["stocks"]["food"]) < need:
		lines.append("Еды не хватит: есть %d, нужно %d." % [int(snap["stocks"]["food"]), need])
	var capacity := int(snap["pop_capacity"])
	if pop > capacity:
		lines.append("Тесно: %d человек на %d мест." % [pop, capacity])
	for building in snap["buildings"]:
		if building["status"] == "idle":
			lines.append("%s простаивает." % CivSliceCatalog.building(building["type"])["name"])
	if str(snap.get("current_event", "")) != "":
		lines.append("Ждёт выбора: %s." % CivSliceCatalog.event(snap["current_event"])["name"])
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
	for resource in CivSliceCatalog.RESOURCES:
		if price.has(resource) and int(price[resource]) != 0:
			parts.append("%d %s" % [int(price[resource]), GENITIVE.get(resource, resource)])
	return ", ".join(parts)


static func order_line(order: Dictionary) -> String:
	match str(order.get("kind", "build")):
		"survey":
			return "Изучить чанк (%d,%d)" % [int(order["chunk_x"]), int(order["chunk_y"])]
		"prepare":
			return "Подготовить %d клеток" % order["cells"].size()
		"road":
			return "Дорога, %s" % cost(order["reserve"])
		_:
			var definition: Dictionary = CivSliceCatalog.building(order["type"])
			return "%s, %s" % [definition["name"], cost(order["reserve"])]


static func option_text(option: Dictionary) -> String:
	var lines: PackedStringArray = [option["name"]]
	if not option["cost"].is_empty():
		lines.append("Сразу %s." % cost(option["cost"]))
	for effect in option.get("effects", []):
		lines.append(_effect(effect))
	return "\n".join(lines)


static func building_blurb(building: Dictionary) -> String:
	var definition: Dictionary = CivSliceCatalog.building(building["type"])
	var status := _status(building)
	return "%s\n%s\nКлеток: %d" % [definition["name"], status, building["cells"].size()]


static func building_catalog_blurb(type_id: String) -> String:
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d клеток · стройка %d х." % [int(definition["area"]), int(definition["build_time"])])
	if not definition["cost"].is_empty():
		lines.append("Цена: %s" % cost(definition["cost"]))
	var outputs: Dictionary = definition["outputs"]
	for resource in outputs:
		lines.append("+%d %s за ход" % [int(outputs[resource]), CivSliceCatalog.RESOURCE_NAMES.get(resource, resource)])
	var inputs: Dictionary = definition["inputs"]
	if not inputs.is_empty():
		lines.append("Расход: %s за ход" % cost(inputs))
	if int(definition["pop_capacity"]) > 0:
		lines.append("+%d мест для людей" % int(definition["pop_capacity"]))
	if int(definition["water"]) > 0:
		lines.append("Вода на %d человек" % int(definition["water"]))
	if int(definition["loyalty"]) != 0:
		lines.append("Лояльность %+d" % int(definition["loyalty"]))
	if int(definition["science"]) > 0:
		lines.append("+%d науки за ход" % int(definition["science"]))
	var storage: Dictionary = definition["storage"]
	for resource in storage:
		lines.append("Склад %s +%d" % [CivSliceCatalog.RESOURCE_NAMES.get(resource, resource), int(storage[resource])])
	var tech := str(definition.get("requires_tech", ""))
	if tech != "":
		lines.append("Нужна технология: %s" % CivSliceCatalog.technology(tech)["name"])
	if bool(definition.get("requires_road", false)):
		lines.append("Дорога к ратуше вне старта")
	var upkeep := int(definition.get("money_upkeep", 0))
	if upkeep > 0:
		lines.append("Содержание %d денег за ход (после Монеты)" % upkeep)
	return "\n".join(lines)


static func _effect(effect: Dictionary) -> String:
	var amount := int(effect.get("amount", 0))
	var left := int(effect.get("remaining", 0))
	match str(effect["kind"]):
		"pop_bonus_once":
			return "+%d человек в ход прихода." % amount
		"loyalty_delta":
			return "%+d лояльности, ещё %d ход." % [amount, left]
		"prestige_once", "prestige_delta":
			return "%+d престижа." % amount
		"cropland_food_add":
			return "Пашня %+d еды, ещё %d ход." % [amount, left]
		"cropland_food_replace":
			return "Пашня даёт %d еды, ещё %d ход." % [amount, left]
		_:
			return str(effect["kind"])


static func _note(note: Dictionary) -> String:
	match str(note.get("kind", "")):
		"survey_done":
			return "Чанк (%d,%d) изучен." % [int(note["chunk_x"]), int(note["chunk_y"])]
		"prepare_done":
			return "Клетка (%d,%d) подготовлена." % [int(note["x"]), int(note["y"])]
		"road_completed":
			return "Дорога готова."
		"tech_done":
			return "Изучено: %s." % note.get("name", note.get("id", ""))
		"event":
			return "Событие: %s." % CivSliceCatalog.event(str(note["event"]))["name"]
		"capital_review":
			return "Пересмотр столицы. Престиж обнулён."
		"completed":
			return "%s достроено." % CivSliceCatalog.building(note["type"])["name"]
		"victory":
			return "Население %d. Победа среза." % CivSliceCatalog.VICTORY_POP
		"defeat":
			return "Людей не осталось."
		"country_victory":
			if bool(note.get("ai", false)):
				return "Другой город страны достиг победы."
			return "Победа страны."
		"tax_income":
			if str(note.get("source", "")) == "tax":
				return "Налог: +%d денег." % int(note["amount"])
			return "+%d денег." % int(note["amount"])
		"money_upkeep":
			return "Содержание построек: −%d денег." % int(note["amount"])
		"money_upkeep_short":
			return "Не хватило денег на содержание (нужно %d, уплачено %d)." % [
				int(note["need"]),
				int(note["paid"]),
			]
		"consumption", "population", "loyalty":
			return ""
		_:
			return ""


static func _status(building: Dictionary) -> String:
	match str(building["status"]):
		"building":
			return "Строится, ещё %d ход." % int(building["timer"])
		"idle":
			return "Простаивает."
		_:
			return "Работает."
