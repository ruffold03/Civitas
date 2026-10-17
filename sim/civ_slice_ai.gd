class_name CivSliceAi
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivSliceTurn = preload("res://sim/civ_slice_turn.gd")
const CivSliceAiMap = preload("res://sim/civ_slice_ai_map.gd")
const CivSliceRoads = preload("res://sim/civ_slice_roads.gd")
const CivUtil = preload("res://sim/civ_util.gd")

const ECONOMY_VICTORY_MONEY := 5000

const TECH_ORDER: Array[String] = ["writing", "moneta", "military", "engineering"]


static func bootstrap_country(snapshot: Dictionary) -> void:
	var player := str(snapshot["scenario"])
	snapshot["country_winner"] = ""
	snapshot["capital_scenario"] = player
	snapshot["ai_cities"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(snapshot.get("map_seed", 1))
	for scenario_id in CivSliceScenario.scenario_ids():
		if str(scenario_id) == player:
			continue
		snapshot["ai_cities"][str(scenario_id)] = new_city_state(str(scenario_id), rng)


static func new_city_state(scenario_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var city: Dictionary = CivSliceScenario.opening_snapshot(scenario_id)
	city["name"] = str(CivSliceScenario.SCENARIOS[scenario_id]["name"])
	city["victory_goal"] = "population" if rng.randi() % 2 == 0 else "economy"
	city["current_event"] = ""
	city["resolved_events"] = []
	city["notifications"] = []
	return city


static func advance_country(state: Dictionary, notes: Array) -> void:
	if not state.has("ai_cities"):
		return
	var turn := int(state["turn"])
	var player := str(state["scenario"])
	for scenario_id in state["ai_cities"].keys():
		var city: Dictionary = state["ai_cities"][scenario_id]
		if str(city.get("mode", "play")) != "play":
			continue
		advance_city(city, turn, notes)
		var winner := victory_scenario(city)
		if winner == "":
			continue
		state["country_winner"] = winner
		notes.append({"kind": "country_victory", "scenario": winner, "ai": winner != player})
		if winner != player:
			state["mode"] = "defeat"
		else:
			state["mode"] = "victory"
			state["victory_id"] = "population_slice"
		return


static func advance_city(city: Dictionary, turn: int, notes: Array) -> void:
	city["turn"] = turn
	_try_research(city, notes)
	var draft: Dictionary = _empty_draft()
	_plan_orders(city, draft, notes)
	CivSliceTurn.resolve_npc_turn(city, draft, notes)
	if int(city["pop"]) <= 0:
		city["mode"] = "defeat"
		notes.append({"kind": "ai_defeat", "scenario": str(city["scenario"])})


static func victory_scenario(city: Dictionary) -> String:
	if str(city.get("mode", "play")) != "play":
		return ""
	if str(city.get("victory_goal", "population")) == "economy":
		if CivSliceTech.is_researched(city, "moneta"):
			if int(city["stocks"].get("money", 0)) >= ECONOMY_VICTORY_MONEY:
				return str(city["scenario"])
	if int(city["pop"]) >= CivSliceCatalog.VICTORY_POP:
		return str(city["scenario"])
	return ""


static func city_visible_summary(city: Dictionary) -> Dictionary:
	return {
		"name": str(city.get("name", "")),
		"scenario": str(city.get("scenario", "")),
		"pop": int(city.get("pop", 0)),
		"loyalty": int(city.get("loyalty", 0)),
		"prestige": int(city.get("prestige", 0)),
		"victory_goal": str(city.get("victory_goal", "population")),
		"stocks": CivUtil.deep_copy(city.get("stocks", {})),
	}


static func _plan_orders(city: Dictionary, draft: Dictionary, notes: Array) -> void:
	if not _has_building_in_progress(city["buildings"]):
		if _try_queue_build(city, draft, notes):
			return
	if _try_queue_road(city, draft, notes):
		return
	if _try_queue_prepare(city, draft, notes):
		return
	_try_queue_survey(city, draft, notes)


static func _try_queue_build(city: Dictionary, draft: Dictionary, notes: Array) -> bool:
	for type_id in _build_priorities(city):
		if not _can_build_type(city, type_id):
			continue
		var definition: Dictionary = CivSliceCatalog.building(type_id)
		if not _can_afford(city, definition["cost"]):
			continue
		var cells: Array = CivSliceAiMap.find_build_cells(city, type_id)
		if cells.is_empty():
			continue
		var order_id := int(draft["next_order_id"])
		draft["next_order_id"] = order_id + 1
		draft["orders"].append({
			"id": order_id,
			"kind": "build",
			"type": type_id,
			"cells": cells,
			"reserve": CivUtil.deep_copy(definition["cost"]),
		})
		notes.append({"kind": "ai_build", "scenario": city["scenario"], "type": type_id})
		return true
	return false


static func _try_queue_road(city: Dictionary, draft: Dictionary, notes: Array) -> bool:
	if not _can_afford(city, CivSliceRoads.COST):
		return false
	var cell: Array = CivSliceAiMap.find_road_cell(city)
	if cell.is_empty():
		return false
	var order_id := int(draft["next_order_id"])
	draft["next_order_id"] = order_id + 1
	draft["orders"].append({
		"id": order_id,
		"kind": "road",
		"cells": [cell],
		"reserve": CivUtil.deep_copy(CivSliceRoads.COST),
	})
	notes.append({"kind": "ai_road", "scenario": city["scenario"], "x": int(cell[0]), "y": int(cell[1])})
	return true


static func _try_queue_prepare(city: Dictionary, draft: Dictionary, notes: Array) -> bool:
	var cell: Array = CivSliceAiMap.find_prepare_cell(city)
	if cell.is_empty():
		return false
	var order_id := int(draft["next_order_id"])
	draft["next_order_id"] = order_id + 1
	draft["orders"].append({
		"id": order_id,
		"kind": "prepare",
		"cells": [cell],
	})
	notes.append({"kind": "ai_prepare", "scenario": city["scenario"], "x": int(cell[0]), "y": int(cell[1])})
	return true


static func _try_queue_survey(city: Dictionary, draft: Dictionary, notes: Array) -> bool:
	var chunk := CivSliceAiMap.pick_survey_chunk(city)
	if chunk.x < 0:
		return false
	var order_id := int(draft["next_order_id"])
	draft["next_order_id"] = order_id + 1
	draft["orders"].append({
		"id": order_id,
		"kind": "survey",
		"chunk_x": chunk.x,
		"chunk_y": chunk.y,
	})
	notes.append({"kind": "ai_survey", "scenario": city["scenario"], "chunk_x": chunk.x, "chunk_y": chunk.y})
	return true


static func _try_research(city: Dictionary, notes: Array) -> void:
	if str(city.get("research", "")) != "":
		return
	for tech_id in TECH_ORDER:
		var check: Dictionary = CivSliceTech.can_start_research(city, tech_id)
		if not check["ok"]:
			continue
		CivSliceTech.apply_research_choice(city, tech_id)
		notes.append({"kind": "ai_research", "scenario": city["scenario"], "tech": tech_id})
		return


static func _build_priorities(city: Dictionary) -> Array:
	var pop := int(city["pop"])
	var capacity := CivSliceRules.pop_capacity(city["buildings"])
	var food := int(city["stocks"].get("food", 0))
	var needed := CivSliceRules.consumption_need(pop, city["effects"])
	var priorities: Array = []
	if capacity <= pop:
		priorities.append("domus")
	if food < needed * 3:
		priorities.append("farm")
		priorities.append("cropland")
	if not _has_type(city["buildings"], "sawmill"):
		priorities.append("sawmill")
	if not _has_type(city["buildings"], "quarry"):
		priorities.append("quarry")
	if str(city.get("victory_goal", "")) == "economy":
		priorities.append_array(["market", "port", "pottery", "forum", "vineyard"])
	else:
		priorities.append_array(["domus", "cropland", "granary", "farm", "vineyard"])
	priorities.append_array(["well", "square", "temple", "baths", "barracks", "aqueduct"])
	return priorities


static func _can_build_type(city: Dictionary, type_id: String) -> bool:
	if not CivSliceCatalog.has_building(type_id):
		return false
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	if not bool(definition.get("player_buildable", true)):
		return false
	if type_id == "town_hall":
		return false
	var req := str(definition.get("requires_tech", ""))
	if req != "" and not CivSliceTech.is_researched(city, req):
		return false
	return true


static func _has_building_in_progress(buildings: Array) -> bool:
	for building in buildings:
		if str(building.get("status", "")) == "building":
			return true
	return false


static func _has_type(buildings: Array, type_id: String) -> bool:
	for building in buildings:
		if str(building.get("type", "")) == type_id:
			return true
	return false


static func _can_afford(city: Dictionary, cost: Dictionary) -> bool:
	for resource in cost:
		if int(city["stocks"].get(resource, 0)) < int(cost[resource]):
			return false
	return true


static func _empty_draft() -> Dictionary:
	return {"orders": [], "event_option": "", "event_reserve": {}, "next_order_id": 1}
