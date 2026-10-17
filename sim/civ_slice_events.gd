class_name CivSliceEvents
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivUtil = preload("res://sim/civ_util.gd")


static func resolve_key(event_id: String, turn: int) -> String:
	return "%s:%d" % [event_id, turn]


static func open_calendar(state: Dictionary, notes: Array) -> void:
	state["current_event"] = ""
	var turn := int(state["turn"])
	for event_id in CivSliceCatalog.event_calendar_ids():
		var definition: Dictionary = CivSliceCatalog.event(event_id)
		if not CivSliceCatalog.event_on_turn(definition, turn):
			continue
		var key := resolve_key(event_id, turn)
		if state["resolved_events"].has(key):
			continue
		if not CivSliceRules.event_matches(str(definition["condition"]), state):
			state["resolved_events"].append(key)
			notes.append({"kind": "event_skipped", "event": event_id, "turn": turn})
			continue
		if bool(definition.get("auto", false)):
			_auto_resolve(state, event_id, turn, notes)
			state["resolved_events"].append(key)
			continue
		if definition["options"].is_empty():
			state["resolved_events"].append(key)
			notes.append({"kind": "event_skipped", "event": event_id, "turn": turn})
			continue
		state["current_event"] = event_id
		notes.append({"kind": "event", "event": event_id, "turn": turn})
		return


static func apply_choice(state: Dictionary, event_id: String, option_id: String, notes: Array) -> void:
	var definition: Dictionary = CivSliceCatalog.event(event_id)
	var options: Dictionary = definition["options"]
	var option: Dictionary = options[option_id]
	_pay(state, option["cost"], notes, event_id)
	for template in option["effects"]:
		_add_effect(state, event_id, template, notes)
	var turn := int(state["turn"])
	state["resolved_events"].append(resolve_key(event_id, turn))
	state["current_event"] = ""
	notes.append({"kind": "event_choice", "event": event_id, "option": option_id})


static func event_upkeep(state: Dictionary, notes: Array) -> void:
	for effect in state["effects"]:
		if str(effect["kind"]) != "pay_per_turn":
			continue
		var resource := str(effect["resource"])
		var amount := int(effect["amount"])
		if amount <= 0:
			continue
		var have := int(state["stocks"].get(resource, 0))
		if have < amount:
			notes.append({
				"kind": "event_pay_short",
				"resource": resource,
				"need": amount,
				"source": effect["source"],
			})
			continue
		state["stocks"][resource] = have - amount
		notes.append({
			"kind": "pay",
			"resource": resource,
			"amount": amount,
			"source": str(effect["source"]),
		})


static func prestige_from_effects(state: Dictionary) -> int:
	var delta := 0
	for effect in state["effects"]:
		if str(effect["kind"]) == "prestige_delta":
			delta += int(effect["amount"])
	return delta


static func _auto_resolve(state: Dictionary, event_id: String, turn: int, notes: Array) -> void:
	match event_id:
		"capital_review":
			state["prestige"] = 0
			notes.append({
				"kind": "capital_review",
				"turn": turn,
				"capital": str(state.get("scenario", "")),
			})
		_:
			notes.append({"kind": "event_auto", "event": event_id, "turn": turn})


static func _add_effect(state: Dictionary, event_id: String, template: Dictionary, notes: Array) -> void:
	var kind := str(template["kind"])
	if kind == "prestige_once":
		state["prestige"] = int(state.get("prestige", 0)) + int(template["amount"])
		notes.append({
			"kind": "prestige",
			"amount": int(template["amount"]),
			"source": event_id,
		})
		return
	for effect in state["effects"]:
		if effect["source"] == event_id and effect["kind"] == kind:
			return
	var entry := {
		"source": event_id,
		"source_name": CivSliceCatalog.event(event_id)["name"],
		"kind": kind,
		"amount": int(template.get("amount", 0)),
		"remaining": int(template["remaining"]),
	}
	if template.has("resource"):
		entry["resource"] = str(template["resource"])
	state["effects"].append(entry)


static func _pay(state: Dictionary, cost: Dictionary, notes: Array, source: String) -> void:
	for resource in cost:
		var amount := int(cost[resource])
		if amount == 0:
			continue
		if not state["stocks"].has(resource):
			state["stocks"][resource] = 0
		state["stocks"][resource] = int(state["stocks"][resource]) - amount
		notes.append({"kind": "pay", "resource": resource, "amount": amount, "source": source})
