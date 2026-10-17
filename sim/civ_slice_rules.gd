class_name CivSliceRules
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivUtil = preload("res://sim/civ_util.gd")


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


static func cropland_food(effects: Array) -> int:
	var amount := 10
	for effect in effects:
		if effect["kind"] == "cropland_food_replace":
			amount = int(effect["amount"])
	for effect in effects:
		if effect["kind"] == "cropland_food_add":
			amount += int(effect["amount"])
	return amount


static func clamp_loyalty(value: int) -> int:
	return clampi(value, CivSliceCatalog.LOYALTY_MIN, CivSliceCatalog.LOYALTY_MAX)


static func pop_capacity(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if building["status"] != "working":
			continue
		total += int(CivSliceCatalog.building(building["type"])["pop_capacity"])
	return total


static func water_coverage(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if building["status"] != "working":
			continue
		total += int(CivSliceCatalog.building(building["type"])["water"])
	return total


static func event_matches(condition: String, snapshot: Dictionary) -> bool:
	var pop := int(snapshot["pop"])
	var loyalty := int(snapshot["loyalty"])
	var capacity := pop_capacity(snapshot["buildings"])
	match condition:
		"always":
			return true
		"pop_below_victory":
			return pop < CivSliceCatalog.VICTORY_POP
		"loyalty_at_least_45":
			return loyalty >= 45
		"crowded_or_loyalty_below_40":
			return pop > capacity or loyalty < 40
		"has_working_cropland":
			return _has_working(snapshot["buildings"], "cropland")
		"has_temple":
			return _has_working(snapshot["buildings"], "temple")
		"barracks_or_pop_120":
			return _has_working(snapshot["buildings"], "barracks") or pop >= 120
		"trade_infrastructure":
			return _trade_infrastructure(snapshot["buildings"])
		_:
			return false


static func _has_working(buildings: Array, type_id: String) -> bool:
	for building in buildings:
		if str(building["type"]) == type_id and str(building["status"]) == "working":
			return true
	return false


static func _trade_infrastructure(buildings: Array) -> bool:
	var trade := 0
	for building in buildings:
		if str(building["status"]) != "working":
			continue
		var type_id := str(building["type"])
		if type_id == "market" or type_id == "port":
			trade += 1
	return trade >= 2


static func science_income(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if building["status"] != "working":
			continue
		total += int(CivSliceCatalog.building(building["type"])["science"])
	return total


static func money_economy_active(state: Dictionary) -> bool:
	return CivSliceTech.is_researched(state, "moneta")


static func tax_income(pop: int) -> int:
	if pop <= 0:
		return 0
	return int(pop / CivSliceCatalog.MONEY_TAX_POP)


static func money_upkeep_due(buildings: Array) -> int:
	var total := 0
	for building in buildings:
		if str(building.get("status", "")) != "working":
			continue
		total += int(CivSliceCatalog.building(building["type"]).get("money_upkeep", 0))
	return total


static func apply_money_settlement(state: Dictionary, pop: int, notes: Array) -> void:
	if not money_economy_active(state):
		return
	var tax := tax_income(pop)
	if tax > 0:
		_add_money(state, tax, notes, "tax")
	var upkeep := money_upkeep_due(state["buildings"])
	if upkeep <= 0:
		return
	var have := int(state["stocks"].get("money", 0))
	var paid := mini(have, upkeep)
	state["stocks"]["money"] = have - paid
	notes.append({"kind": "money_upkeep", "amount": paid, "due": upkeep})
	if paid < upkeep:
		notes.append({"kind": "money_upkeep_short", "need": upkeep, "paid": paid})


static func _add_money(state: Dictionary, amount: int, notes: Array, source: String) -> void:
	if amount <= 0:
		return
	if not state["stocks"].has("money"):
		state["stocks"]["money"] = 0
	state["stocks"]["money"] = int(state["stocks"]["money"]) + amount
	notes.append({"kind": "tax_income", "amount": amount, "source": source})


static func storage_caps(buildings: Array, technologies: Array = []) -> Dictionary:
	var caps: Dictionary = CivUtil.deep_copy(CivSliceCatalog.BASE_STORAGE)
	if not technologies.has("moneta"):
		caps["money"] = 0
	for building in buildings:
		if building["status"] != "working":
			continue
		var extra: Dictionary = CivSliceCatalog.building(building["type"])["storage"]
		for resource in extra:
			caps[resource] = int(caps.get(resource, 0)) + int(extra[resource])
	return caps
