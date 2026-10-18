class_name CivSliceTurn
extends RefCounted

const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivSliceEvents = preload("res://sim/civ_slice_events.gd")
const CivSliceRoads = preload("res://sim/civ_slice_roads.gd")
const CivSliceAi = preload("res://sim/civ_slice_ai.gd")
const CivUtil = preload("res://sim/civ_util.gd")


static func resolve(snapshot: Dictionary, draft: Dictionary) -> Dictionary:
	var state: Dictionary = CivUtil.deep_copy(snapshot)
	var notes: Array = []
	var ctx := {
		"pop_start": int(state["pop"]),
		"loyalty_start": int(state["loyalty"]),
		"needed": 0,
		"band": "tight",
	}
	_apply_orders(state, draft, notes)
	CivSliceEvents.event_upkeep(state, notes)
	_tick_surveys(state, notes)
	_tick_prepare(state, notes)
	_construction(state, notes)
	_construction_roads(state, notes)
	_production(state, notes)
	_money_settlement(state, ctx, notes)
	_consumption(state, ctx, notes)
	_warehouses(state, notes)
	_population(state, ctx, notes)
	_loyalty(state, ctx, notes)
	_prestige(state, notes)
	CivSliceTech.advance_turn(state, notes)
	_deferred(state, notes)
	_victory(state, notes)
	if str(state.get("mode", "play")) == "play":
		CivSliceAi.advance_country(state, notes)
	_finish_turn(state, notes)
	return state


static func resolve_npc_turn(state: Dictionary, draft: Dictionary, notes: Array) -> void:
	var ctx := {
		"pop_start": int(state["pop"]),
		"loyalty_start": int(state["loyalty"]),
		"needed": 0,
		"band": "tight",
	}
	_apply_orders(state, draft, notes)
	CivSliceEvents.event_upkeep(state, notes)
	_tick_surveys(state, notes)
	_tick_prepare(state, notes)
	_construction(state, notes)
	_construction_roads(state, notes)
	_production(state, notes)
	_money_settlement(state, ctx, notes)
	_consumption(state, ctx, notes)
	_warehouses(state, notes)
	_population(state, ctx, notes)
	_loyalty(state, ctx, notes)
	CivSliceTech.advance_turn(state, notes)
	_deferred(state, notes)


static func _apply_orders(state: Dictionary, draft: Dictionary, notes: Array) -> void:
	var foundation := str(state.get("foundation", "latium_hills"))
	for order in draft["orders"]:
		match str(order["kind"]):
			"survey":
				var cx := int(order["chunk_x"])
				var cy := int(order["chunk_y"])
				var chunk: Dictionary = _chunk_record(state, cx, cy)
				chunk["survey_timer"] = CivGeoSlice.SURVEY_TURNS
				notes.append({"kind": "survey_ordered", "chunk_x": cx, "chunk_y": cy, "timer": chunk["survey_timer"]})
			"chop":
				for cell in order["cells"]:
					var x := int(cell[0])
					var y := int(cell[1])
					if CivSliceMap.terrain_at_state(state, x, y, foundation) != "forest":
						continue
					state["stocks"]["wood"] = int(state["stocks"].get("wood", 0)) + CivGeoSlice.FOREST_CHOP_WOOD
					CivSliceMap.set_cell_terrain(state, x, y, "plain")
					notes.append({
						"kind": "forest_chop",
						"x": x,
						"y": y,
						"wood": CivGeoSlice.FOREST_CHOP_WOOD,
					})
			"prepare":
				for cell in order["cells"]:
					var x := int(cell[0])
					var y := int(cell[1])
					var terrain := CivSliceMap.terrain_at_state(state, x, y, foundation)
					var turns := CivGeoSlice.preparation_turns(terrain)
					CivSliceMap.set_prep_timer(state, x, y, turns)
					notes.append({"kind": "prepare_ordered", "x": x, "y": y, "timer": turns})
			"build":
				_pay(state, order["reserve"], notes, order["type"])
				var definition: Dictionary = CivSliceCatalog.building(order["type"])
				var building := {
					"id": int(state["next_id"]),
					"type": order["type"],
					"cells": CivUtil.deep_copy(order["cells"]),
					"status": "building",
					"timer": int(definition["build_time"]),
					"born_turn": int(state["turn"]),
				}
				state["next_id"] = int(state["next_id"]) + 1
				state["buildings"].append(building)
				CivSliceMap.clear_cells_under_buildings(state.get("map_cells", {}), [building])
				notes.append({
					"kind": "ordered",
					"type": order["type"],
					"id": building["id"],
					"timer": building["timer"],
				})
			"road":
				_pay(state, order["reserve"], notes, "road")
				if not state.has("roads"):
					state["roads"] = []
				var road := {
					"id": int(state["next_id"]),
					"cells": CivUtil.deep_copy(order["cells"]),
					"status": "building",
					"timer": CivSliceRoads.BUILD_TIME,
					"born_turn": int(state["turn"]),
				}
				state["next_id"] = int(state["next_id"]) + 1
				state["roads"].append(road)
				notes.append({
					"kind": "road_ordered",
					"id": road["id"],
					"timer": road["timer"],
				})
	var option_id := str(draft.get("event_option", ""))
	if option_id == "":
		return
	var event_id := str(state["current_event"])
	if event_id == "":
		return
	CivSliceEvents.apply_choice(state, event_id, option_id, notes)


static func _prestige(state: Dictionary, notes: Array) -> void:
	var delta := CivSliceEvents.prestige_from_effects(state)
	if delta == 0:
		return
	state["prestige"] = int(state.get("prestige", 0)) + delta
	notes.append({"kind": "prestige", "amount": delta, "source": "effects"})


static func _pay(state: Dictionary, cost: Dictionary, notes: Array, source: String) -> void:
	for resource in cost:
		var amount := int(cost[resource])
		if amount == 0:
			continue
		if not state["stocks"].has(resource):
			state["stocks"][resource] = 0
		state["stocks"][resource] = int(state["stocks"][resource]) - amount
		notes.append({"kind": "pay", "resource": resource, "amount": amount, "source": source})


static func _construction_roads(state: Dictionary, notes: Array) -> void:
	for road in state.get("roads", []):
		if str(road.get("status", "")) != "building":
			continue
		if int(road["born_turn"]) == int(state["turn"]):
			continue
		road["timer"] = int(road["timer"]) - 1
		if int(road["timer"]) > 0:
			continue
		road["timer"] = 0
		road["status"] = "working"
		notes.append({"kind": "road_completed", "id": road["id"]})


static func _construction(state: Dictionary, notes: Array) -> void:
	for building in state["buildings"]:
		if building["status"] != "building":
			continue
		if int(building["born_turn"]) == int(state["turn"]):
			continue
		building["timer"] = int(building["timer"]) - 1
		if int(building["timer"]) > 0:
			continue
		building["timer"] = 0
		building["status"] = "working"
		notes.append({"kind": "completed", "id": building["id"], "type": building["type"]})


static func _production(state: Dictionary, notes: Array) -> void:
	var producers: Array = []
	var consumers: Array = []
	for building in state["buildings"]:
		if building["status"] != "working" and building["status"] != "idle":
			continue
		var inputs: Dictionary = CivSliceCatalog.building(building["type"])["inputs"]
		if inputs.is_empty():
			producers.append(building)
		else:
			consumers.append(building)
	producers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	consumers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for building in producers:
		_produce(state, building, notes)
	for building in consumers:
		var definition: Dictionary = CivSliceCatalog.building(building["type"])
		if _stock_covers(state, definition["inputs"]):
			_pay(state, definition["inputs"], notes, building["type"])
			building["status"] = "working"
			_produce(state, building, notes)
		else:
			building["status"] = "idle"
			notes.append({"kind": "idle", "id": building["id"], "type": building["type"]})


static func _produce(state: Dictionary, building: Dictionary, notes: Array) -> void:
	var definition: Dictionary = CivSliceCatalog.building(building["type"])
	if building["type"] == "cropland":
		var food := CivSliceRules.cropland_food(state["effects"])
		state["stocks"]["food"] = int(state["stocks"]["food"]) + food
		notes.append({"kind": "produce", "resource": "food", "amount": food, "source": "cropland", "id": building["id"]})
		return
	var outputs: Dictionary = definition["outputs"]
	for resource in outputs:
		if resource == "money" and not CivSliceRules.money_economy_active(state):
			continue
		var amount := int(outputs[resource])
		if not state["stocks"].has(resource):
			state["stocks"][resource] = 0
		state["stocks"][resource] = int(state["stocks"][resource]) + amount
		notes.append({
			"kind": "produce",
			"resource": resource,
			"amount": amount,
			"source": building["type"],
			"id": building["id"],
		})


static func _stock_covers(state: Dictionary, cost: Dictionary) -> bool:
	for resource in cost:
		var have := int(state["stocks"].get(resource, 0))
		if have < int(cost[resource]):
			return false
	return true


static func _money_settlement(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	CivSliceRules.apply_money_settlement(state, int(ctx["pop_start"]), notes)


static func _consumption(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var needed := CivSliceRules.consumption_need(int(ctx["pop_start"]), state["effects"])
	var stock := int(state["stocks"]["food"])
	var paid := mini(stock, needed)
	state["stocks"]["food"] = stock - paid
	ctx["needed"] = needed
	ctx["band"] = CivSliceRules.food_band(needed, stock)
	notes.append({"kind": "consumption", "needed": needed, "paid": paid, "band": ctx["band"]})


static func _warehouses(state: Dictionary, notes: Array) -> void:
	var caps: Dictionary = CivSliceRules.storage_caps(state["buildings"], state.get("technologies", []))
	for resource in CivSliceCatalog.RESOURCES:
		var amount := int(state["stocks"].get(resource, 0))
		var cap := int(caps.get(resource, 0))
		if amount > cap:
			notes.append({"kind": "spoil", "resource": resource, "amount": amount - cap})
			amount = cap
		if amount < 0:
			amount = 0
		state["stocks"][resource] = amount
	state["storage"] = caps


static func _population(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var pop_start := int(ctx["pop_start"])
	var capacity := CivSliceRules.pop_capacity(state["buildings"])
	var housing := CivSliceRules.housing(capacity - pop_start)
	var water := CivSliceRules.water_speed(pop_start, CivSliceRules.water_coverage(state["buildings"]))
	var food := CivSliceRules.food_speed(str(ctx["band"]))
	var past := CivSliceRules.past_loyalty_speed(int(ctx["loyalty_start"]))
	var speed := 1 + int(housing["speed"]) + water + food + past
	var bonus := 0
	for effect in state["effects"]:
		if effect["kind"] == "pop_speed_delta":
			speed += int(effect["amount"])
		elif effect["kind"] == "pop_bonus_once":
			bonus += int(effect["amount"])
	var pop := maxi(0, pop_start + speed + bonus)
	state["pop"] = pop
	state["pop_capacity"] = capacity
	notes.append({"kind": "population", "before": pop_start, "after": pop, "speed": speed, "bonus": bonus})
	ctx["housing_loyalty"] = int(housing["loyalty"])


static func _loyalty(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var delta := int(ctx["housing_loyalty"])
	for building in state["buildings"]:
		if building["status"] != "working":
			continue
		delta += int(CivSliceCatalog.building(building["type"])["loyalty"])
	delta += CivSliceRules.food_loyalty(str(ctx["band"]))
	for effect in state["effects"]:
		if effect["kind"] == "loyalty_delta":
			delta += int(effect["amount"])
	var loyalty := CivSliceRules.clamp_loyalty(int(ctx["loyalty_start"]) + delta)
	state["loyalty"] = loyalty
	state["loyalty_sources"] = []
	notes.append({"kind": "loyalty", "before": int(ctx["loyalty_start"]), "after": loyalty, "delta": delta})


static func _deferred(state: Dictionary, _notes: Array) -> void:
	var kept: Array = []
	for effect in state["effects"]:
		effect["remaining"] = int(effect["remaining"]) - 1
		if int(effect["remaining"]) > 0:
			kept.append(effect)
	state["effects"] = kept


static func _tick_prepare(state: Dictionary, notes: Array) -> void:
	var prep: Dictionary = state.get("cell_prep", {})
	for key in prep:
		var record: Dictionary = prep[key]
		if bool(record.get("prepared", false)):
			continue
		var timer := int(record.get("timer", 0))
		if timer <= 0:
			continue
		timer -= 1
		record["timer"] = timer
		if timer > 0:
			continue
		record["prepared"] = true
		var parts: PackedStringArray = key.split(",")
		notes.append({"kind": "prepare_done", "x": int(parts[0]), "y": int(parts[1])})


static func _tick_surveys(state: Dictionary, notes: Array) -> void:
	var map_cells: Dictionary = state.get("map_cells", {})
	for record in state["chunks"]:
		var timer := int(record.get("survey_timer", 0))
		if timer <= 0 or bool(record.get("surveyed", false)):
			continue
		timer -= 1
		record["survey_timer"] = timer
		if timer > 0:
			continue
		record["surveyed"] = true
		CivSliceMap.reveal_chunk(map_cells, int(record["x"]), int(record["y"]))
		notes.append({"kind": "survey_done", "chunk_x": int(record["x"]), "chunk_y": int(record["y"])})


static func _victory(state: Dictionary, notes: Array) -> void:
	if int(state["pop"]) <= 0:
		state["mode"] = "defeat"
		state["victory_id"] = ""
		notes.append({"kind": "defeat"})
		return
	if int(state["pop"]) >= CivSliceCatalog.VICTORY_POP:
		state["mode"] = "victory"
		state["victory_id"] = "population_slice"
		notes.append({"kind": "victory", "id": "population_slice"})


static func _finish_turn(state: Dictionary, notes: Array) -> void:
	state["turn"] = int(state["turn"]) + 1
	if state["mode"] == "play":
		CivSliceEvents.open_calendar(state, notes)
	state["notifications"] = notes


static func _chunk_record(state: Dictionary, chunk_x: int, chunk_y: int) -> Dictionary:
	for record in state["chunks"]:
		if int(record["x"]) == chunk_x and int(record["y"]) == chunk_y:
			return record
	var fresh := {
		"x": chunk_x,
		"y": chunk_y,
		"developed": false,
		"surveyed": false,
		"survey_timer": 0,
	}
	state["chunks"].append(fresh)
	return fresh
