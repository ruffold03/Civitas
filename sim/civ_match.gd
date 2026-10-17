class_name CivMatch
extends RefCounted

const CivCatalog = preload("res://sim/civ_catalog.gd")
const CivGeo = preload("res://sim/civ_geo.gd")
const CivTurn = preload("res://sim/civ_turn.gd")
const CivUtil = preload("res://sim/civ_util.gd")

## Партия: снимок, черновик и журнал. Фаза игрока пишет только в черновик.
## Сохранение читается на границе хода, когда черновик пуст.

var snapshot: Dictionary
var draft: Dictionary
var journal: Array
var rng_seed: int
var rng_state: int


static func new_game():
	var game = _fresh()
	game.rng_seed = 1
	game.rng_state = 1
	game.journal = []
	game.snapshot = _opening_snapshot()
	game.draft = _empty_draft()
	return game


static func from_dict(data: Dictionary):
	var game = _fresh()
	var copied: Dictionary = CivUtil.deep_copy(data)
	game.snapshot = copied["snapshot"]
	game.draft = copied["draft"]
	game.journal = copied["journal"]
	game.rng_seed = int(copied["rng_seed"])
	game.rng_state = int(copied["rng_state"])
	return game


func to_dict() -> Dictionary:
	return {
		"snapshot": CivUtil.deep_copy(snapshot),
		"draft": CivUtil.deep_copy(draft),
		"journal": CivUtil.deep_copy(journal),
		"rng_seed": rng_seed,
		"rng_state": rng_state,
	}


func save_to_file(path: String) -> Dictionary:
	if not _draft_is_empty():
		return {"ok": false, "error": "Сохранение стоит на границе хода, до приказов."}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть файл сохранения."}
	file.store_string(var_to_str(to_dict()))
	return {"ok": true, "error": ""}


static func load_from_file(path: String):
	var text := FileAccess.get_file_as_string(path)
	return from_dict(str_to_var(text))


func build_order(type_id: String, cells: Array) -> Dictionary:
	var check := _check_build(type_id, cells)
	if not check["ok"]:
		return check
	var definition: Dictionary = CivCatalog.building(type_id)
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
	var options: Dictionary = CivCatalog.event(event_id)["options"]
	if not options.has(option_id):
		return {"ok": false, "error": "Такого варианта нет."}
	var cost: Dictionary = options[option_id]["cost"]
	var reserved := _reserved()
	for resource in draft["event_reserve"]:
		reserved[resource] -= int(draft["event_reserve"][resource])
	for resource in cost:
		var left := int(snapshot["stocks"][resource]) - int(reserved.get(resource, 0))
		if left < int(cost[resource]):
			return {"ok": false, "error": "На этот вариант не хватает запасов."}
	draft["event_option"] = option_id
	draft["event_reserve"] = CivUtil.deep_copy(cost)
	return {"ok": true, "error": ""}


func forecast_build(type_id: String, cells: Array) -> Dictionary:
	var check := _check_build(type_id, cells)
	if not check["ok"]:
		return check
	var definition: Dictionary = CivCatalog.building(type_id)
	return {
		"ok": true,
		"error": "",
		"cost": CivUtil.deep_copy(definition["cost"]),
		"build_time": int(definition["build_time"]),
		"loyalty": int(definition["loyalty"]),
		"outputs": CivUtil.deep_copy(definition["outputs"]),
		"pop_capacity": int(definition["pop_capacity"]),
		"water": int(definition["water"]),
		"storage": CivUtil.deep_copy(definition["storage"]),
		"inputs": CivUtil.deep_copy(definition["inputs"]),
	}


func end_turn() -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if str(snapshot["current_event"]) != "" and str(draft["event_option"]) == "":
		return {"ok": false, "error": "Сначала выбери вариант события."}
	var played_turn := int(snapshot["turn"])
	var recorded: Dictionary = CivUtil.deep_copy(draft)
	snapshot = CivTurn.resolve(snapshot, draft)
	journal.append({
		"turn": played_turn,
		"orders": recorded,
		"notifications": CivUtil.deep_copy(snapshot["notifications"]),
	})
	draft = _empty_draft()
	return {"ok": true, "error": ""}


func available(resource: String) -> int:
	return int(snapshot["stocks"][resource]) - int(_reserved().get(resource, 0))


static func _fresh():
	return load("res://sim/civ_match.gd").new()


static func _opening_snapshot() -> Dictionary:
	var buildings: Array = []
	var next_id := 1
	var hut_cells := [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [0, 1]]
	for cell in hut_cells:
		buildings.append(_placed(next_id, "hut", [cell]))
		next_id += 1
	buildings.append(_placed(next_id, "well", [[1, 1]]))
	next_id += 1
	var chunks: Array = []
	for chunk in CivGeo.all_chunks():
		chunks.append({"x": chunk[0], "y": chunk[1], "developed": true})
	return {
		"turn": 1,
		"era": CivCatalog.ERA,
		"mode": "play",
		"victory_id": "",
		"pop": 30,
		"pop_capacity": 30,
		"loyalty": 50,
		"loyalty_sources": [],
		"stocks": {"food": 18, "wood": 16, "stone": 8},
		"storage": CivUtil.deep_copy(CivCatalog.BASE_STORAGE),
		"buildings": buildings,
		"chunks": chunks,
		"effects": [],
		"current_event": "",
		"resolved_events": [],
		"notifications": [],
		"next_id": next_id,
	}


static func _placed(id_number: int, type_id: String, cells: Array) -> Dictionary:
	return {
		"id": id_number,
		"type": type_id,
		"cells": cells,
		"status": "working",
		"timer": 0,
		"born_turn": 0,
	}


static func _empty_draft() -> Dictionary:
	return {
		"orders": [],
		"event_option": "",
		"event_reserve": {},
		"next_order_id": 1,
	}


func _draft_is_empty() -> bool:
	return draft["orders"].is_empty() and str(draft["event_option"]) == ""


func _reserved() -> Dictionary:
	var reserved := CivCatalog.empty_stocks()
	for order in draft["orders"]:
		for resource in order["reserve"]:
			reserved[resource] += int(order["reserve"][resource])
	for resource in draft["event_reserve"]:
		reserved[resource] += int(draft["event_reserve"][resource])
	return reserved


func _can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if available(resource) < int(cost[resource]):
			return false
	return true


func _check_build(type_id: String, cells: Array) -> Dictionary:
	if snapshot["mode"] != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if not CivCatalog.has_building(type_id):
		return {"ok": false, "error": "Такого здания нет."}
	var definition: Dictionary = CivCatalog.building(type_id)
	var normalized := _normalize_cells(cells)
	if normalized.size() != int(definition["area"]):
		return {"ok": false, "error": "Нужна другая площадь."}
	if not _cells_unique(normalized):
		return {"ok": false, "error": "Клетки приказа повторяются."}
	if not CivGeo.connected(normalized):
		return {"ok": false, "error": "Клетки должны соприкасаться сторонами."}
	var occupied := _occupied()
	for cell in normalized:
		var x := int(cell[0])
		var y := int(cell[1])
		if not CivGeo.in_bounds(x, y):
			return {"ok": false, "error": "Клетка вне карты."}
		if not _chunk_developed(x, y):
			return {"ok": false, "error": "Чанк ещё не освоен."}
		if CivGeo.terrain_at(x, y) != "land":
			return {"ok": false, "error": "Здесь нельзя строить."}
		if occupied.has(CivUtil.cell_key(cell)):
			return {"ok": false, "error": "Клетка уже занята."}
	if not _can_afford(definition["cost"]):
		return {"ok": false, "error": "Не хватает запасов."}
	return {"ok": true, "error": ""}


func _chunk_developed(x: int, y: int) -> bool:
	var chunk := CivGeo.chunk_of(x, y)
	for record in snapshot["chunks"]:
		if int(record["x"]) == int(chunk[0]) and int(record["y"]) == int(chunk[1]):
			return bool(record["developed"])
	return false


func _occupied() -> Dictionary:
	var occupied := {}
	for building in snapshot["buildings"]:
		for cell in building["cells"]:
			occupied[CivUtil.cell_key(cell)] = true
	for order in draft["orders"]:
		for cell in order["cells"]:
			occupied[CivUtil.cell_key(cell)] = true
	return occupied


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
