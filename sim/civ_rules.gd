class_name CivRules
extends RefCounted

const CivCatalog = preload("res://sim/civ_catalog.gd")
const CivUtil = preload("res://sim/civ_util.gd")

## Формулы прототипа. Шаг расчёта решает, когда их вызывать. Здесь нет порядка хода.


static func consumption_need(pop: int, effects: Array) -> int:
	if pop <= 0:
		return 0
	var normal := int((pop + 4) / 5)
	for effect in effects:
		if effect["kind"] == "consumption_half_extra":
			normal += int((normal + 1) / 2)
			break
	return normal


static func food_band(needed: int, stock: int) -> String:
	if needed <= 0:
		return "tight"
	if stock < needed:
		return "shortage"
	var remainder := stock - needed
	if remainder >= needed:
		return "surplus"
	return "tight"


static func food_loyalty(band: String) -> int:
	if band == "surplus":
		return 1
	if band == "shortage":
		return -3
	return 0


static func food_speed(band: String) -> int:
	if band == "surplus":
		return 1
	if band == "shortage":
		return -4
	return 0


static func housing(free_places: int) -> Dictionary:
	if free_places >= 11:
		return {"loyalty": 2, "speed": 1}
	if free_places >= 6:
		return {"loyalty": 1, "speed": 1}
	if free_places >= 1:
		return {"loyalty": 0, "speed": 0}
	if free_places == 0:
		return {"loyalty": 0, "speed": 0}
	var overflow := -free_places
	if overflow <= 4:
		return {"loyalty": -1, "speed": -1}
	if overflow <= 9:
		return {"loyalty": -2, "speed": -2}
	return {"loyalty": -3, "speed": -3}


static func water_speed(pop: int, coverage: int) -> int:
	if coverage <= 0:
		return -2
	if pop > coverage:
		return -1
	if coverage - pop >= 10:
		return 1
	return 0


static func past_loyalty_speed(loyalty: int) -> int:
	if loyalty >= 60:
		return 1
	if loyalty >= 30:
		return 0
	return -1


static func field_food(effects: Array) -> int:
	var amount := 8
	for effect in effects:
		if effect["kind"] == "field_food_replace":
			amount = int(effect["amount"])
	for effect in effects:
		if effect["kind"] == "field_food_add":
			amount += int(effect["amount"])
	return amount


static func clamp_loyalty(value: int) -> int:
	return clampi(value, CivCatalog.LOYALTY_MIN, CivCatalog.LOYALTY_MAX)


static func pop_capacity(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if building["status"] != "working":
			continue
		total += int(CivCatalog.building(building["type"])["pop_capacity"])
	return total


static func water_coverage(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if building["status"] != "working":
			continue
		total += int(CivCatalog.building(building["type"])["water"])
	return total


static func storage_caps(buildings: Array) -> Dictionary:
	var caps: Dictionary = CivUtil.deep_copy(CivCatalog.BASE_STORAGE)
	for building in buildings:
		if building["status"] != "working":
			continue
		var extra: Dictionary = CivCatalog.building(building["type"])["storage"]
		for resource in extra:
			caps[resource] += int(extra[resource])
	return caps


static func event_matches(condition: String, snapshot: Dictionary) -> bool:
	var pop := int(snapshot["pop"])
	var loyalty := int(snapshot["loyalty"])
	var capacity := pop_capacity(snapshot["buildings"])
	match condition:
		"pop_below_100":
			return pop < CivCatalog.VICTORY_POP
		"crowded_or_loyalty_below_40":
			return pop > capacity or loyalty < 40
		"has_working_field":
			return _has_working(snapshot["buildings"], "field")
		_:
			return false


static func _has_working(buildings: Array, type_id: String) -> bool:
	for building in buildings:
		if building["type"] == type_id and building["status"] == "working":
			return true
	return false
