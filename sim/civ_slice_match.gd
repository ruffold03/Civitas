class_name CivSliceMatch
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceScenario = preload("res://sim/civ_slice_scenario.gd")
const CivSliceTurn = preload("res://sim/civ_slice_turn.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivSliceRoads = preload("res://sim/civ_slice_roads.gd")
const CivSliceMap = preload("res://sim/civ_slice_map.gd")
const CivGeoSlice = preload("res://sim/civ_geo_slice.gd")
const CivSliceAi = preload("res://sim/civ_slice_ai.gd")
const CivUtil = preload("res://sim/civ_util.gd")

var snapshot: Dictionary
var draft: Dictionary
var journal: Array


static func new_game(scenario_id: String = "rome"):
	var game = load("res://sim/civ_slice_match.gd").new()
	if not CivSliceScenario.has_scenario(scenario_id):
		scenario_id = "rome"
	game.snapshot = CivSliceScenario.opening_snapshot(scenario_id)
	CivSliceAi.bootstrap_country(game.snapshot)
	game.draft = _empty_draft()
	game.journal = []
	return game


func research_order(tech_id: String) -> Dictionary:
	var check: Dictionary = CivSliceTech.can_start_research(snapshot, tech_id)
	if not check["ok"]:
		return check
	CivSliceTech.apply_research_choice(snapshot, tech_id)
	var notes: Array = []
	if CivSliceTech.try_complete(snapshot, tech_id, notes):
		snapshot["research"] = ""
	return {"ok": true, "error": ""}


func stop_research() -> Dictionary:
	if str(snapshot.get("research", "")) == "":
		return {"ok": false, "error": "Ничего не изучается."}
	CivSliceTech.clear_research(snapshot)
	return {"ok": true, "error": ""}


func build_order(type_id: String, cells: Array) -> Dictionary:
	var check := _check_build(type_id, cells)
	if not check["ok"]:
		return check
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	var order := {
		"id": int(draft["next_order_id"]),
		"kind": "build",
		"type": type_id,
		"cells": _normalize_cells(cells),
		"reserve": CivUtil.deep_copy(definition["cost"]),
	}
	draft["next_order_id"] = int(draft["next_order_id"]) + 1
	draft["orders"].append(order)
	return {"ok": true, "error": "", "order_id": order["id"]}


func road_order(cell: Array) -> Dictionary:
	var check := _check_road(cell)
	if not check["ok"]:
		return check
	var order := {
		"id": int(draft["next_order_id"]),
		"kind": "road",
		"cells": _normalize_cells([cell]),
		"reserve": CivUtil.deep_copy(CivSliceRoads.COST),
	}
	draft["next_order_id"] = int(draft["next_order_id"]) + 1
	draft["orders"].append(order)
	return {"ok": true, "error": "", "order_id": order["id"]}


func prepare_order(cells: Array) -> Dictionary:
	var check := _check_prepare(cells)
	if not check["ok"]:
		return check
	var order := {
		"id": int(draft["next_order_id"]),
		"kind": "prepare",
		"cells": _normalize_cells(cells),
	}
	draft["next_order_id"] = int(draft["next_order_id"]) + 1
	draft["orders"].append(order)
	return {"ok": true, "error": "", "order_id": order["id"]}


func chop_order(cells: Array) -> Dictionary:
	var check := _check_chop(cells)
	if not check["ok"]:
		return check
	var order := {
		"id": int(draft["next_order_id"]),
		"kind": "chop",
		"cells": _normalize_cells(cells),
	}
	draft["next_order_id"] = int(draft["next_order_id"]) + 1
	draft["orders"].append(order)
	return {"ok": true, "error": "", "order_id": order["id"]}


func survey_order(chunk_x: int, chunk_y: int) -> Dictionary:
	var check := _check_survey(chunk_x, chunk_y)
	if not check["ok"]:
		return check
	var order := {
		"id": int(draft["next_order_id"]),
		"kind": "survey",
		"chunk_x": chunk_x,
		"chunk_y": chunk_y,
	}
	draft["next_order_id"] = int(draft["next_order_id"]) + 1
	draft["orders"].append(order)
	return {"ok": true, "error": "", "order_id": order["id"]}


func cancel_order(order_id: int) -> Dictionary:
	var kept: Array = []
	var found := false
	for order in draft["orders"]:
		if int(order["id"]) == order_id:
			found = true
			continue
		kept.append(order)
	if not found:
		return {"ok": false, "error": "Такого приказа нет."}
	draft["orders"] = kept
	return {"ok": true, "error": ""}


func choose_event(option_id: String) -> Dictionary:
	var event_id := str(snapshot["current_event"])
	if event_id == "":
		return {"ok": false, "error": "Сейчас нет события."}
	var definition: Dictionary = CivSliceCatalog.event(event_id)
	var options: Dictionary = definition["options"]
	if not options.has(option_id):
		return {"ok": false, "error": "Такого варианта нет."}
	var option: Dictionary = options[option_id]
	var req := str(option.get("requires_tech", ""))
	if req != "" and not CivSliceTech.is_researched(snapshot, req):
		return {"ok": false, "error": "Нужна технология «%s»." % CivSliceCatalog.technology(req)["name"]}
	var cost: Dictionary = option["cost"]
	var reserved := _reserved()
	for resource in draft["event_reserve"]:
		reserved[resource] = int(reserved.get(resource, 0)) - int(draft["event_reserve"][resource])
	for resource in cost:
		var left := int(snapshot["stocks"].get(resource, 0)) - int(reserved.get(resource, 0))
		if left < int(cost[resource]):
			return {"ok": false, "error": "На этот вариант не хватает запасов."}
	draft["event_option"] = option_id
	draft["event_reserve"] = CivUtil.deep_copy(cost)
	return {"ok": true, "error": ""}


func end_turn() -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if str(snapshot["current_event"]) != "" and str(draft.get("event_option", "")) == "":
		return {"ok": false, "error": "Сначала выбери вариант события."}
	var played_turn := int(snapshot["turn"])
	var recorded: Dictionary = CivUtil.deep_copy(draft)
	snapshot = CivSliceTurn.resolve(snapshot, draft)
	journal.append({"turn": played_turn, "orders": recorded, "notifications": CivUtil.deep_copy(snapshot["notifications"])})
	draft = _empty_draft()
	return {"ok": true, "error": ""}


func chunk_at_cell(x: int, y: int) -> Array[int]:
	var coords: Array = CivGeoSlice.chunk_of(x, y)
	return [int(coords[0]), int(coords[1])]


static func _empty_draft() -> Dictionary:
	return {"orders": [], "event_option": "", "event_reserve": {}, "next_order_id": 1}


func _check_survey(chunk_x: int, chunk_y: int) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if chunk_x < 0 or chunk_y < 0 or chunk_x >= int(CivGeoSlice.SIZE / CivGeoSlice.CHUNK):
		return {"ok": false, "error": "Чанк вне карты."}
	var record := _find_chunk(chunk_x, chunk_y)
	if record.is_empty():
		return {"ok": false, "error": "Такого чанка нет."}
	if bool(record.get("surveyed", false)):
		return {"ok": false, "error": "Чанк уже изучен."}
	if int(record.get("survey_timer", 0)) > 0:
		return {"ok": false, "error": "Чанк уже изучается."}
	for order in draft["orders"]:
		if str(order["kind"]) == "survey" and int(order["chunk_x"]) == chunk_x and int(order["chunk_y"]) == chunk_y:
			return {"ok": false, "error": "Приказ на этот чанк уже в очереди."}
	return {"ok": true, "error": ""}


func _find_chunk(chunk_x: int, chunk_y: int) -> Dictionary:
	for record in snapshot["chunks"]:
		if int(record["x"]) == chunk_x and int(record["y"]) == chunk_y:
			return record
	return {}


func _check_prepare(cells: Array) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	var normalized := _normalize_cells(cells)
	if normalized.is_empty():
		return {"ok": false, "error": "Выбери клетки."}
	if not _cells_unique(normalized):
		return {"ok": false, "error": "Клетки приказа повторяются."}
	var foundation := str(snapshot["foundation"])
	var reserved := _cells_in_draft_prepare()
	for cell in normalized:
		var x := int(cell[0])
		var y := int(cell[1])
		if not CivGeoSlice.in_bounds(x, y):
			return {"ok": false, "error": "Клетка вне карты."}
		if CivSliceMap.is_start_zone_cell(x, y, foundation):
			return {"ok": false, "error": "Стартовая зона уже готова к стройке."}
		var terrain := CivSliceMap.terrain_at_state(snapshot, x, y, foundation)
		if not CivGeoSlice.allows_default_building(terrain):
			return {"ok": false, "error": "Здесь нельзя готовить местность."}
		var chunk: Array = CivGeoSlice.chunk_of(x, y)
		if not CivSliceMap.chunk_is_surveyed(snapshot, int(chunk[0]), int(chunk[1])):
			return {"ok": false, "error": "Сначала изучи чанк."}
		if CivSliceMap.is_cell_occupied(snapshot, x, y):
			return {"ok": false, "error": "Клетка занята."}
		var key := CivUtil.cell_key(cell)
		if reserved.has(key):
			return {"ok": false, "error": "Клетка уже в приказе подготовки."}
		var prep: Dictionary = CivSliceMap.prep_record(snapshot, x, y)
		if bool(prep.get("prepared", false)):
			return {"ok": false, "error": "Клетка уже подготовлена."}
		if int(prep.get("timer", 0)) > 0:
			return {"ok": false, "error": "Клетка уже готовится."}
		if CivGeoSlice.preparation_turns(terrain) < 0:
			return {"ok": false, "error": "Для этой местности подготовка не нужна."}
	return {"ok": true, "error": ""}


func _check_chop(cells: Array) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	var normalized := _normalize_cells(cells)
	if normalized.size() != 1:
		return {"ok": false, "error": "Рубка — одна клетка леса."}
	var cell: Array = normalized[0]
	var x := int(cell[0])
	var y := int(cell[1])
	if not CivGeoSlice.in_bounds(x, y):
		return {"ok": false, "error": "Клетка вне карты."}
	var foundation := str(snapshot["foundation"])
	var terrain := CivSliceMap.terrain_at_state(snapshot, x, y, foundation)
	if terrain != "forest":
		return {"ok": false, "error": "Здесь нет леса для рубки."}
	var chunk: Array = CivGeoSlice.chunk_of(x, y)
	if (
		not CivSliceMap.is_start_zone_cell(x, y, foundation)
		and not CivSliceMap.chunk_is_surveyed(snapshot, int(chunk[0]), int(chunk[1]))
	):
		return {"ok": false, "error": "Сначала изучи чанк."}
	if CivSliceMap.is_cell_occupied(snapshot, x, y):
		return {"ok": false, "error": "Клетка занята."}
	var key := CivUtil.cell_key(cell)
	if _cells_in_draft_chop().has(key):
		return {"ok": false, "error": "Рубка этой клетки уже в очереди."}
	return {"ok": true, "error": ""}


func _check_build(type_id: String, cells: Array) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if not CivSliceCatalog.has_building(type_id):
		return {"ok": false, "error": "Такого здания нет."}
	var definition: Dictionary = CivSliceCatalog.building(type_id)
	if not bool(definition.get("player_buildable", true)):
		return {"ok": false, "error": "Это здание нельзя строить."}
	var normalized := _normalize_cells(cells)
	if normalized.size() != int(definition["area"]):
		return {"ok": false, "error": "Нужна другая площадь."}
	if not _cells_unique(normalized):
		return {"ok": false, "error": "Клетки приказа повторяются."}
	if not CivGeoSlice.connected(normalized):
		return {"ok": false, "error": "Клетки должны соприкасаться сторонами."}
	var foundation := str(snapshot["foundation"])
	var occupied := _occupied()
	for cell in normalized:
		var x := int(cell[0])
		var y := int(cell[1])
		if not CivGeoSlice.in_bounds(x, y):
			return {"ok": false, "error": "Клетка вне карты."}
		var terrain := CivSliceMap.terrain_at_state(snapshot, x, y, foundation)
		if not CivGeoSlice.allows_default_building(terrain):
			return {"ok": false, "error": "Здесь нельзя строить."}
		var chunk: Array = CivGeoSlice.chunk_of(x, y)
		if not CivSliceMap.chunk_is_surveyed(snapshot, int(chunk[0]), int(chunk[1])):
			return {"ok": false, "error": "Сначала изучи чанк."}
		if not CivSliceMap.is_prepared_for_build(snapshot, x, y, foundation):
			return {"ok": false, "error": "Сначала подготовь клетку."}
		if occupied.has(CivUtil.cell_key(cell)):
			return {"ok": false, "error": "Клетка уже занята."}
	if not _can_afford(definition["cost"]):
		return {"ok": false, "error": "Не хватает запасов."}
	var req_tech := str(definition.get("requires_tech", ""))
	if req_tech != "" and not CivSliceTech.is_researched(snapshot, req_tech):
		var tech_name: String = CivSliceCatalog.technology(req_tech)["name"]
		return {"ok": false, "error": "Нужна технология «%s»." % tech_name}
	if bool(definition.get("requires_road", false)):
		if CivSliceRoads.needs_outside_road_check(normalized, foundation):
			if not CivSliceRoads.building_linked_to_town(snapshot, normalized, foundation):
				return {"ok": false, "error": "Нужна дорога к ратуше."}
	return {"ok": true, "error": ""}


func _check_road(cell: Array) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	var normalized := _normalize_cells([cell])
	if normalized.is_empty():
		return {"ok": false, "error": "Выбери клетку."}
	var x := int(normalized[0][0])
	var y := int(normalized[0][1])
	var foundation := str(snapshot["foundation"])
	var occupied := _occupied()
	if occupied.has(CivUtil.cell_key([x, y])):
		return {"ok": false, "error": "Клетка уже занята."}
	var place := CivSliceRoads.can_place_road(snapshot, x, y, foundation)
	if not place["ok"]:
		return place
	if not _can_afford(CivSliceRoads.COST):
		return {"ok": false, "error": "Не хватает запасов."}
	return {"ok": true, "error": ""}


func available(resource: String) -> int:
	return int(snapshot["stocks"].get(resource, 0)) - int(_reserved().get(resource, 0))


func _can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if available(resource) < int(cost[resource]):
			return false
	return true


func _reserved() -> Dictionary:
	var reserved := CivSliceCatalog.empty_stocks()
	for order in draft["orders"]:
		if not order.has("reserve"):
			continue
		for resource in order["reserve"]:
			reserved[resource] = int(reserved.get(resource, 0)) + int(order["reserve"][resource])
	for resource in draft.get("event_reserve", {}):
		reserved[resource] = int(reserved.get(resource, 0)) + int(draft["event_reserve"][resource])
	return reserved


func _occupied() -> Dictionary:
	var occupied := {}
	for building in snapshot["buildings"]:
		for cell in building["cells"]:
			occupied[CivUtil.cell_key(cell)] = true
	for order in draft["orders"]:
		var kind := str(order.get("kind", ""))
		if kind != "build" and kind != "road":
			continue
		for cell in order["cells"]:
			occupied[CivUtil.cell_key(cell)] = true
	return occupied


func _cells_in_draft_prepare() -> Dictionary:
	var reserved := {}
	for order in draft["orders"]:
		if str(order.get("kind", "")) != "prepare":
			continue
		for cell in order["cells"]:
			reserved[CivUtil.cell_key(cell)] = true
	return reserved


func _cells_in_draft_chop() -> Dictionary:
	var reserved := {}
	for order in draft["orders"]:
		if str(order.get("kind", "")) != "chop":
			continue
		for cell in order["cells"]:
			reserved[CivUtil.cell_key(cell)] = true
	return reserved


func _cells_unique(cells: Array) -> bool:
	var seen := {}
	for cell in cells:
		var key := CivUtil.cell_key(cell)
		if seen.has(key):
			return false
		seen[key] = true
	return true


func _normalize_cells(cells: Array) -> Array:
	var normalized: Array = []
	for cell in cells:
		normalized.append([int(cell[0]), int(cell[1])])
	return normalized
