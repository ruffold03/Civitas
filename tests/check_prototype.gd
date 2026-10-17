extends SceneTree

const MatchScript = preload("res://sim/civ_match.gd")
const RulesScript = preload("res://sim/civ_rules.gd")
const GeoScript = preload("res://sim/civ_geo.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_rules()
	_placement()
	_three_turns()
	_timers_and_stocks()
	_events()
	_endings()
	_same_snapshot_twice()
	_save_roundtrip()
	if _failed == 0:
		print("Прототип: все проверки сошлись.")
		quit(0)
	else:
		print("Прототип: провалов %d." % _failed)
		quit(1)


func _rules() -> void:
	expect(RulesScript.consumption_need(30, []) == 6, "30 человек едят 6")
	expect(RulesScript.consumption_need(33, []) == 7, "33 человека едят 7")
	var tend: Array = [{"kind": "consumption_half_extra", "amount": 0, "remaining": 4}]
	expect(RulesScript.consumption_need(30, tend) == 9, "выхаживание: 6 и ещё 3")
	expect(RulesScript.consumption_need(35, tend) == 11, "35 человек при выхаживании едят 11")
	expect(RulesScript.food_band(6, 12) == "surplus", "остаток не меньше расхода")
	expect(RulesScript.food_band(7, 12) == "tight", "еды хватило впритык")
	expect(RulesScript.food_band(7, 5) == "shortage", "еды не хватило")
	expect(RulesScript.field_food([]) == 8, "поле даёт 8")
	expect(RulesScript.field_food([{"kind": "field_food_replace", "amount": 4}]) == 4, "засуха режет поле до 4")
	expect(RulesScript.field_food([{"kind": "field_food_replace", "amount": 6}]) == 6, "полив оставляет полю 6")
	expect(RulesScript.field_food([{"kind": "field_food_add", "amount": 4}]) == 12, "закрома добавляют 4")
	expect(RulesScript.clamp_loyalty(150) == 100, "лояльность не выше 100")
	expect(RulesScript.clamp_loyalty(-4) == 0, "лояльность не ниже 0")
	expect(not GeoScript.connected([[0, 0], [1, 1]]), "угол не связывает клетки")
	expect(GeoScript.connected([[0, 0], [1, 0], [1, 1], [0, 1]]), "квадрат поля связан")


func _placement() -> void:
	var game = MatchScript.new_game()
	expect(not game.build_order("hut", [[9, 0]])["ok"], "вода недоступна")
	expect(not game.build_order("hut", [[0, 9]])["ok"], "обрыв недоступен")
	expect(not game.build_order("pen", [[5, 5], [6, 6]])["ok"], "диагональ не годится")
	expect(game.build_order("hut", [[4, 1]])["ok"], "хижина ставится")
	expect(game.build_order("wood_yard", [[2, 1], [3, 1]])["ok"], "двор забирает остаток дерева")
	expect(not game.build_order("pen", [[5, 2], [6, 2]])["ok"], "второе дерево уже зарезервировано")
	expect(game.cancel_order(1)["ok"], "отмена снимает резерв")
	expect(game.build_order("hut", [[4, 1]])["ok"], "после отмены хижина снова доступна")
	var forecast: Dictionary = MatchScript.new_game().forecast_build("hearth", [[5, 0]])
	expect(forecast["ok"], "прогноз кострища")
	expect(int(forecast["cost"]["wood"]) == 4 and int(forecast["cost"]["stone"]) == 4, "прогноз показывает цену")
	expect(int(forecast["build_time"]) == 1, "прогноз показывает срок")
	expect(int(forecast["loyalty"]) == 3, "прогноз показывает лояльность")


func _three_turns() -> void:
	var game = MatchScript.new_game()
	expect(game.build_order("wood_yard", [[2, 1], [3, 1]])["ok"], "ход 1: двор")
	expect(game.build_order("hut", [[4, 1]])["ok"], "ход 1: хижина")
	expect(game.end_turn()["ok"], "ход 1 считается")
	_expect_city(game, 2, 33, 52, 12, 0, 8, "после хода 1")
	_expect_status(game, "wood_yard", "building", 1)
	_expect_status(game, "hut", "building", 1)
	expect(game.end_turn()["ok"], "ход 2 считается")
	_expect_city(game, 3, 34, 53, 5, 5, 8, "после хода 2")
	_expect_status(game, "wood_yard", "working", 0)
	expect(game.build_order("hearth", [[5, 0]])["ok"], "ход 3: кострище")
	expect(game.end_turn()["ok"], "ход 3 считается")
	_expect_city(game, 4, 31, 51, 0, 6, 4, "после хода 3")
	_expect_status(game, "hearth", "building", 1)
	_expect_note(game, "consumption", {"band": "shortage", "needed": 7, "paid": 5})
	print("Три хода: 33/52 → 34/53 → 31/51, склады сошлись с ручным счётом.")


func _timers_and_stocks() -> void:
	var well = _with_stocks({"stone": 20})
	expect(well.build_order("well", [[2, 1]])["ok"], "колодец заказан")
	expect(well.end_turn()["ok"], "оплата колодца")
	_expect_born_status(well, "well", "building", 2)
	expect(well.end_turn()["ok"], "таймер колодца уменьшился")
	_expect_born_status(well, "well", "building", 1)
	expect(well.end_turn()["ok"], "колодец достроен")
	_expect_born_status(well, "well", "working", 0)

	var spoil = _with_stocks({"wood": 25})
	expect(spoil.end_turn()["ok"], "лишнее дерево списывается")
	expect(int(spoil.snapshot["stocks"]["wood"]) == 20, "дерево обрезано вместимостью 20")
	_expect_note(spoil, "spoil", {"resource": "wood", "amount": 5})

	var idle = _with_building("hearth", [[5, 0]], {"wood": 1})
	expect(idle.end_turn()["ok"], "кострище без двух дров")
	_expect_status(idle, "hearth", "idle", 0)
	expect(int(idle.snapshot["loyalty"]) == 52, "погасшее кострище не даёт лояльность")
	expect(int(idle.snapshot["stocks"]["wood"]) == 1, "дрова без двора не появились")

	var fed = _with_building("hearth", [[5, 0]], {"wood": 0})
	_add_working(fed, "wood_yard", [[2, 1], [3, 1]])
	expect(fed.end_turn()["ok"], "двор кормит кострище в тот же ход")
	_expect_status(fed, "hearth", "working", 0)
	expect(int(fed.snapshot["stocks"]["wood"]) == 3, "5 дров двора минус 2 кострища")
	expect(int(fed.snapshot["loyalty"]) == 55, "кострище добавило 3 лояльности")

	var drought = _with_building("field", [[5, 1], [6, 1], [7, 1], [8, 1]], {"food": 10, "pop": 10})
	_add_working(drought, "pen", [[5, 2], [6, 2]])
	drought.snapshot["effects"] = [{
		"source": "drought",
		"source_name": "Засуха",
		"kind": "field_food_replace",
		"amount": 4,
		"remaining": 2,
	}]
	expect(drought.end_turn()["ok"], "засуха считается")
	expect(int(drought.snapshot["stocks"]["food"]) == 16, "поле дало 4, загон 4, съели 2")

	var harvest = _with_building("field", [[5, 1], [6, 1], [7, 1], [8, 1]], {"food": 10, "pop": 10})
	_add_working(harvest, "pen", [[5, 2], [6, 2]])
	harvest.snapshot["effects"] = [{
		"source": "harvest",
		"source_name": "Урожай",
		"kind": "field_food_add",
		"amount": 4,
		"remaining": 2,
	}]
	expect(harvest.end_turn()["ok"], "урожай считается")
	expect(int(harvest.snapshot["stocks"]["food"]) == 24, "поле дало 12, загон 4, съели 2")

	var capped = _with_stocks({"pop": 10, "loyalty": 98, "food": 30})
	expect(capped.end_turn()["ok"], "лояльность у потолка")
	expect(int(capped.snapshot["loyalty"]) == 100, "лояльность остановилась на 100")


func _events() -> void:
	var refused = MatchScript.new_game()
	for _i in 4:
		expect(refused.end_turn()["ok"], "пустой ход до поселенцев")
	expect(int(refused.snapshot["turn"]) == 5, "событие открывается на ходе 5")
	expect(str(refused.snapshot["current_event"]) == "settlers", "пришли поселенцы")
	expect(int(refused.snapshot["pop"]) == 27, "к ходу 5 без строек осталось 27 человек")
	var blocked = refused.to_dict()
	expect(not refused.end_turn()["ok"], "без выбора ход не кончается")
	expect(_same(blocked, refused.to_dict()), "отказ закончить ход не меняет снимок")
	expect(refused.choose_event("refuse")["ok"], "поселенцам отказали")
	expect(refused.end_turn()["ok"], "отказ учтён")
	expect(int(refused.snapshot["loyalty"]) == 43, "первый ход штрафа")
	expect(refused.end_turn()["ok"], "второй ход штрафа")
	expect(int(refused.snapshot["loyalty"]) == 39, "штраф ещё держится")
	expect(refused.end_turn()["ok"], "третий ход штрафа")
	expect(int(refused.snapshot["loyalty"]) == 36, "штраф кончается")
	expect(refused.end_turn()["ok"], "после штрафа")
	expect(int(refused.snapshot["loyalty"]) == 35, "на четвёртый ход штраф уже не действует")

	var accepted = MatchScript.new_game()
	for _i in 4:
		expect(accepted.end_turn()["ok"], "пустой ход до приёма")
	expect(accepted.choose_event("accept")["ok"], "поселенцев приняли")
	expect(accepted.end_turn()["ok"], "приём учтён")
	expect(int(accepted.snapshot["pop"]) == 35, "10 человек сверх скорости")
	_expect_note(accepted, "consumption", {"needed": 6})
	expect(int(accepted.snapshot["loyalty"]) == 45, "в ход прихода жильё считалось по старым людям")

	var quiet = _with_stocks({"turn": 9, "pop": 20, "food": 30, "loyalty": 50})
	expect(quiet.end_turn()["ok"], "ход болезни без условия")
	expect(str(quiet.snapshot["current_event"]) == "", "болезнь не пришла")
	var sick = _with_stocks({"turn": 9, "pop": 40, "food": 30, "loyalty": 50})
	expect(sick.end_turn()["ok"], "ход болезни при тесноте")
	expect(str(sick.snapshot["current_event"]) == "disease", "болезнь пришла из-за переполнения")

	var dry = _with_stocks({"turn": 19, "stone": 3})
	_add_working(dry, "field", [[5, 1], [6, 1], [7, 1], [8, 1]])
	expect(dry.end_turn()["ok"], "подход к засухе")
	expect(str(dry.snapshot["current_event"]) == "drought", "засуха пришла")
	expect(not dry.choose_event("water")["ok"], "полить нельзя без 4 камня")
	expect(dry.choose_event("wait")["ok"], "засуху пережидают")


func _endings() -> void:
	var victory = _with_stocks({"pop": 98, "loyalty": 50, "food": 40})
	for _i in 16:
		_add_working(victory, "hut", [[5, 2]])
	_add_working(victory, "well", [[6, 2]])
	_add_working(victory, "well", [[7, 2]])
	expect(victory.end_turn()["ok"], "ход победы")
	expect(str(victory.snapshot["mode"]) == "victory", "победа при 100 и больше")
	expect(int(victory.snapshot["pop"]) == 102, "люди дошли до победы в этом ходу")
	expect(not victory.end_turn()["ok"], "после победы ход не играется")

	var defeat = _with_stocks({"pop": 1, "loyalty": 0, "food": 0})
	for building in defeat.snapshot["buildings"]:
		building["status"] = "idle"
	expect(defeat.end_turn()["ok"], "ход поражения")
	expect(int(defeat.snapshot["pop"]) == 0, "численность не ниже нуля")
	expect(str(defeat.snapshot["mode"]) == "defeat", "ноль людей заканчивает партию")


func _same_snapshot_twice() -> void:
	var left = MatchScript.new_game()
	var right = MatchScript.from_dict(left.to_dict())
	left.build_order("wood_yard", [[2, 1], [3, 1]])
	right.build_order("wood_yard", [[2, 1], [3, 1]])
	expect(left.end_turn()["ok"] and right.end_turn()["ok"], "повтор двух партий")
	expect(_same(left.snapshot, right.snapshot), "один снимок и те же приказы дают тот же результат")


func _save_roundtrip() -> void:
	var game = MatchScript.new_game()
	expect(game.build_order("pen", [[5, 2], [6, 2]])["ok"], "загон перед сохранением")
	expect(game.end_turn()["ok"], "ход перед сохранением")
	var path := "user://civitas_prototype_check.save"
	expect(game.save_to_file(path)["ok"], "сохранение на границе хода")
	var loaded = MatchScript.load_from_file(path)
	var twin = MatchScript.from_dict(game.to_dict())
	expect(loaded.end_turn()["ok"] and twin.end_turn()["ok"], "ход после загрузки")
	expect(_same(loaded.snapshot, twin.snapshot), "загрузка продолжает ту же партию")
	var mid = MatchScript.new_game()
	mid.build_order("hut", [[4, 1]])
	expect(not mid.save_to_file(path)["ok"], "черновик на границе хода не пишется")


func _with_stocks(overrides: Dictionary):
	var game = MatchScript.from_dict(MatchScript.new_game().to_dict())
	for key in overrides:
		if key in ["food", "wood", "stone"]:
			game.snapshot["stocks"][key] = int(overrides[key])
		else:
			game.snapshot[key] = overrides[key]
	return game


func _with_building(type_id: String, cells: Array, overrides: Dictionary):
	var game = _with_stocks(overrides)
	_add_working(game, type_id, cells)
	return game


func _add_working(game, type_id: String, cells: Array) -> void:
	var id_number := int(game.snapshot["next_id"])
	game.snapshot["next_id"] = id_number + 1
	game.snapshot["buildings"].append({
		"id": id_number,
		"type": type_id,
		"cells": cells,
		"status": "working",
		"timer": 0,
		"born_turn": 0,
	})


func _expect_city(game, turn: int, pop: int, loyalty: int, food: int, wood: int, stone: int, label: String) -> void:
	var snap: Dictionary = game.snapshot
	var stocks: Dictionary = snap["stocks"]
	expect(int(snap["turn"]) == turn, "%s: ход %d, а не %d" % [label, turn, int(snap["turn"])])
	expect(int(snap["pop"]) == pop, "%s: людей %d, а не %d" % [label, pop, int(snap["pop"])])
	expect(int(snap["loyalty"]) == loyalty, "%s: лояльность %d, а не %d" % [label, loyalty, int(snap["loyalty"])])
	expect(int(stocks["food"]) == food, "%s: еда %d, а не %d" % [label, food, int(stocks["food"])])
	expect(int(stocks["wood"]) == wood, "%s: дерево %d, а не %d" % [label, wood, int(stocks["wood"])])
	expect(int(stocks["stone"]) == stone, "%s: камень %d, а не %d" % [label, stone, int(stocks["stone"])])


func _expect_status(game, type_id: String, status: String, timer: int) -> void:
	for building in game.snapshot["buildings"]:
		if building["type"] != type_id:
			continue
		if int(building["born_turn"]) == 0 and status == "building":
			continue
		if building["status"] != status or int(building["timer"]) != timer:
			fail("%s: ждали %s/%d, получили %s/%d" % [type_id, status, timer, building["status"], int(building["timer"])])
		return
	fail("нет здания %s" % type_id)


func _expect_born_status(game, type_id: String, status: String, timer: int) -> void:
	for building in game.snapshot["buildings"]:
		if building["type"] != type_id or int(building["born_turn"]) == 0:
			continue
		expect(building["status"] == status and int(building["timer"]) == timer, "%s после приказа: %s, таймер %d" % [type_id, building["status"], int(building["timer"])])
		return
	fail("новый %s не найден" % type_id)


func _expect_note(game, kind: String, fields: Dictionary) -> void:
	for note in game.snapshot["notifications"]:
		if note["kind"] != kind:
			continue
		var matches := true
		for key in fields:
			if str(note[key]) != str(fields[key]):
				matches = false
				break
		if matches:
			return
	fail("нет уведомления %s %s" % [kind, fields])


func _same(left: Variant, right: Variant) -> bool:
	return var_to_str(left) == var_to_str(right)


func expect(condition: bool, message: String) -> void:
	if condition:
		return
	fail(message)


func fail(message: String) -> void:
	_failed += 1
	print("FAIL: ", message)
