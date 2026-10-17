class_name CivTurn
extends RefCounted

const CivCatalog = preload("res://sim/civ_catalog.gd")
const CivRules = preload("res://sim/civ_rules.gd")
const CivUtil = preload("res://sim/civ_util.gd")

## Фаза расчёта. Порядок шагов совпадает с «Ходом и порядком симуляции».
## Таймер стройки не уменьшается в тот расчёт, где списали оплату.
## Здание без входов производит раньше здания с входами: двор кормит кострище в тот же ход.
## Событие календаря открывается на снимке того хода, который увидит игрок.


static func resolve(snapshot: Dictionary, draft: Dictionary) -> Dictionary:
	var state: Dictionary = CivUtil.deep_copy(snapshot)
	var orders: Dictionary = CivUtil.deep_copy(draft)
	var notes: Array = []
	var ctx := {
		"pop_start": int(state["pop"]),
		"loyalty_start": int(state["loyalty"]),
		"needed": 0,
		"band": "tight",
	}
	_orders(state, orders, notes)
	_construction(state, notes)
	_upkeep(state, notes)
	_production(state, notes)
	_consumption(state, ctx, notes)
	_warehouses(state, notes)
	_ecology(state, notes)
	_population(state, ctx, notes)
	_policies(state, notes)
	_loyalty(state, ctx, notes)
	_deferred(state, notes)
	_thresholds(state, notes)
	_world(state, notes)
	_victory(state, notes)
	_era(state, notes)
	_snapshot(state, notes)
	return state


static func _orders(state: Dictionary, draft: Dictionary, notes: Array) -> void:
	for order in draft["orders"]:
		if order["kind"] != "build":
			continue
		_pay(state, order["reserve"], notes, order["type"])
		var definition: Dictionary = CivCatalog.building(order["type"])
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
		notes.append({
			"kind": "ordered",
			"type": order["type"],
			"id": building["id"],
			"timer": building["timer"],
		})
	var option_id := str(draft["event_option"])
	if option_id == "":
		return
	var event_id := str(state["current_event"])
	var option: Dictionary = CivCatalog.event(event_id)["options"][option_id]
	_pay(state, option["cost"], notes, event_id)
	for template in option["effects"]:
		_add_effect(state, event_id, template)
	state["resolved_events"].append(event_id)
	state["current_event"] = ""
	notes.append({"kind": "event_choice", "event": event_id, "option": option_id})


static func _add_effect(state: Dictionary, event_id: String, template: Dictionary) -> void:
	var kind := str(template["kind"])
	for effect in state["effects"]:
		if effect["source"] == event_id and effect["kind"] == kind:
			return
	state["effects"].append({
		"source": event_id,
		"source_name": CivCatalog.event(event_id)["name"],
		"kind": kind,
		"amount": int(template["amount"]),
		"remaining": int(template["remaining"]),
	})


static func _pay(state: Dictionary, cost: Dictionary, notes: Array, source: String) -> void:
	for resource in cost:
		var amount := int(cost[resource])
		if amount == 0:
			continue
		state["stocks"][resource] = int(state["stocks"][resource]) - amount
		notes.append({
			"kind": "pay",
			"resource": resource,
			"amount": amount,
			"source": source,
		})


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
		notes.append({
			"kind": "completed",
			"id": building["id"],
			"type": building["type"],
		})


static func _upkeep(_state: Dictionary, _notes: Array) -> void:
	pass


static func _production(state: Dictionary, notes: Array) -> void:
	var producers: Array = []
	var consumers: Array = []
	for building in state["buildings"]:
		if building["status"] != "working" and building["status"] != "idle":
			continue
		var inputs: Dictionary = CivCatalog.building(building["type"])["inputs"]
		if inputs.is_empty():
			producers.append(building)
		else:
			consumers.append(building)
	producers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	consumers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for building in producers:
		_produce(state, building, notes)
	for building in consumers:
		var definition: Dictionary = CivCatalog.building(building["type"])
		if _stock_covers(state, definition["inputs"]):
			_pay(state, definition["inputs"], notes, building["type"])
			building["status"] = "working"
			_produce(state, building, notes)
		else:
			building["status"] = "idle"
			notes.append({"kind": "idle", "id": building["id"], "type": building["type"]})


static func _produce(state: Dictionary, building: Dictionary, notes: Array) -> void:
	var definition: Dictionary = CivCatalog.building(building["type"])
	var outputs: Dictionary = definition["outputs"]
	if building["type"] == "field":
		var food := CivRules.field_food(state["effects"])
		state["stocks"]["food"] = int(state["stocks"]["food"]) + food
		notes.append({"kind": "produce", "resource": "food", "amount": food, "source": "field", "id": building["id"]})
		return
	for resource in outputs:
		var amount := int(outputs[resource])
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
		if int(state["stocks"][resource]) < int(cost[resource]):
			return false
	return true


static func _consumption(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var needed := CivRules.consumption_need(int(ctx["pop_start"]), state["effects"])
	var stock := int(state["stocks"]["food"])
	var paid := mini(stock, needed)
	state["stocks"]["food"] = stock - paid
	ctx["needed"] = needed
	ctx["band"] = CivRules.food_band(needed, stock)
	notes.append({
		"kind": "consumption",
		"needed": needed,
		"paid": paid,
		"band": ctx["band"],
	})


static func _warehouses(state: Dictionary, notes: Array) -> void:
	var caps: Dictionary = CivRules.storage_caps(state["buildings"])
	for resource in CivCatalog.RESOURCES:
		var amount := int(state["stocks"][resource])
		var cap := int(caps[resource])
		if amount > cap:
			notes.append({
				"kind": "spoil",
				"resource": resource,
				"amount": amount - cap,
			})
			amount = cap
		if amount < 0:
			amount = 0
		state["stocks"][resource] = amount
	state["storage"] = caps


static func _ecology(_state: Dictionary, _notes: Array) -> void:
	pass


static func _population(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var pop_start := int(ctx["pop_start"])
	var capacity := CivRules.pop_capacity(state["buildings"])
	var housing := CivRules.housing(capacity - pop_start)
	var water := CivRules.water_speed(pop_start, CivRules.water_coverage(state["buildings"]))
	var food := CivRules.food_speed(str(ctx["band"]))
	var past := CivRules.past_loyalty_speed(int(ctx["loyalty_start"]))
	var speed := 1 + int(housing["speed"]) + water + food + past
	var bonus := 0
	var speed_notes: Array = [
		{"source": "base", "amount": 1, "in_speed": true},
		{"source": "housing", "amount": int(housing["speed"]), "in_speed": true},
		{"source": "water", "amount": water, "in_speed": true},
		{"source": "food", "amount": food, "in_speed": true},
		{"source": "loyalty", "amount": past, "in_speed": true},
	]
	for effect in state["effects"]:
		if effect["kind"] == "pop_speed_delta":
			speed += int(effect["amount"])
			speed_notes.append({"source": effect["source"], "amount": int(effect["amount"]), "in_speed": true})
		elif effect["kind"] == "pop_bonus_once":
			bonus += int(effect["amount"])
			speed_notes.append({"source": effect["source"], "amount": int(effect["amount"]), "in_speed": false})
	var pop := maxi(0, pop_start + speed + bonus)
	state["pop"] = pop
	state["pop_capacity"] = capacity
	notes.append({
		"kind": "population",
		"before": pop_start,
		"after": pop,
		"speed": speed,
		"bonus": bonus,
		"sources": speed_notes,
	})
	ctx["housing_loyalty"] = int(housing["loyalty"])


static func _policies(_state: Dictionary, _notes: Array) -> void:
	pass


static func _loyalty(state: Dictionary, ctx: Dictionary, notes: Array) -> void:
	var sources: Array = [{"source": "housing", "amount": int(ctx["housing_loyalty"])}]
	var delta := int(ctx["housing_loyalty"])
	var buildings: Array = state["buildings"].duplicate()
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for building in buildings:
		if building["status"] != "working":
			continue
		var amount := int(CivCatalog.building(building["type"])["loyalty"])
		if amount == 0:
			continue
		delta += amount
		sources.append({"source": building["type"], "id": building["id"], "amount": amount})
	var food_amount := CivRules.food_loyalty(str(ctx["band"]))
	delta += food_amount
	sources.append({"source": "food", "amount": food_amount})
	for effect in state["effects"]:
		if effect["kind"] != "loyalty_delta":
			continue
		delta += int(effect["amount"])
		sources.append({"source": effect["source"], "amount": int(effect["amount"])})
	var loyalty := CivRules.clamp_loyalty(int(ctx["loyalty_start"]) + delta)
	state["loyalty"] = loyalty
	state["loyalty_sources"] = sources
	notes.append({
		"kind": "loyalty",
		"before": int(ctx["loyalty_start"]),
		"after": loyalty,
		"delta": delta,
		"sources": sources,
	})


static func _deferred(state: Dictionary, _notes: Array) -> void:
	var kept: Array = []
	for effect in state["effects"]:
		effect["remaining"] = int(effect["remaining"]) - 1
		if int(effect["remaining"]) > 0:
			kept.append(effect)
	state["effects"] = kept


static func _thresholds(_state: Dictionary, _notes: Array) -> void:
	pass


static func _world(_state: Dictionary, _notes: Array) -> void:
	pass


static func _victory(state: Dictionary, notes: Array) -> void:
	if int(state["pop"]) <= 0:
		state["mode"] = "defeat"
		state["victory_id"] = ""
		notes.append({"kind": "defeat"})
		return
	if int(state["pop"]) >= CivCatalog.VICTORY_POP:
		state["mode"] = "victory"
		state["victory_id"] = "population"
		notes.append({"kind": "victory", "id": "population"})


static func _era(_state: Dictionary, _notes: Array) -> void:
	pass


static func _snapshot(state: Dictionary, notes: Array) -> void:
	state["turn"] = int(state["turn"]) + 1
	if state["mode"] == "play":
		_open_calendar(state, notes)
	state["notifications"] = notes


static func _open_calendar(state: Dictionary, notes: Array) -> void:
	state["current_event"] = ""
	for event_id in CivCatalog.EVENTS:
		var definition: Dictionary = CivCatalog.event(event_id)
		if int(definition["turn"]) != int(state["turn"]):
			continue
		if state["resolved_events"].has(event_id):
			continue
		if not CivRules.event_matches(str(definition["condition"]), state):
			state["resolved_events"].append(event_id)
			notes.append({"kind": "event_skipped", "event": event_id})
			return
		state["current_event"] = event_id
		notes.append({"kind": "event", "event": event_id})
		return
