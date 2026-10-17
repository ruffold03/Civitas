extends SceneTree

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceMatch = preload("res://sim/civ_slice_match.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")
const CivSliceTech = preload("res://sim/civ_slice_tech.gd")
const CivSliceTurn = preload("res://sim/civ_slice_turn.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	if CivSliceRules.tax_income(40) != 4:
		failures.append("налог 40")
	if CivSliceRules.tax_income(9) != 0:
		failures.append("налог 9")
	var game = CivSliceMatch.new_game("rome")
	game.snapshot["technologies"] = ["moneta"]
	game.snapshot["stocks"]["money"] = 0
	game.snapshot["buildings"].append(
		{
			"id": 50,
			"type": "market",
			"cells": [[0, 0]],
			"status": "working",
			"timer": 0,
			"born_turn": 0,
		}
	)
	game.snapshot["turn"] = 2
	var after: Dictionary = CivSliceTurn.resolve(game.snapshot, CivSliceMatch._empty_draft())
	var money := int(after["stocks"].get("money", 0))
	var expected := (
		5
		+ CivSliceRules.tax_income(int(game.snapshot["pop"]))
		- int(CivSliceCatalog.building("market")["money_upkeep"])
	)
	if money != expected:
		failures.append("доход рынок+налог: %d != %d" % [money, expected])
	game.snapshot = after
	game.snapshot["stocks"]["money"] = 0
	game.snapshot["buildings"] = [
		{
			"id": 51,
			"type": "baths",
			"cells": [[1, 0]],
			"status": "working",
			"timer": 0,
			"born_turn": 0,
		},
	]
	game.snapshot["turn"] = int(game.snapshot["turn"])
	after = CivSliceTurn.resolve(game.snapshot, CivSliceMatch._empty_draft())
	var upkeep_net := CivSliceRules.tax_income(int(game.snapshot["pop"])) - 2
	if int(after["stocks"]["money"]) != upkeep_net:
		failures.append("содержание терм: %d != %d" % [int(after["stocks"]["money"]), upkeep_net])
	var port_game = CivSliceMatch.new_game("tarentum")
	port_game.snapshot["technologies"] = []
	port_game.snapshot["buildings"].append(
		{
			"id": 60,
			"type": "port",
			"cells": [[0, 0], [1, 0], [2, 0]],
			"status": "working",
			"timer": 0,
			"born_turn": 0,
		}
	)
	port_game.snapshot["turn"] = 2
	after = CivSliceTurn.resolve(port_game.snapshot, CivSliceMatch._empty_draft())
	if int(after["stocks"].get("money", 0)) != 0:
		failures.append("порт без монеты не даёт денег")
	port_game.snapshot["technologies"] = ["moneta"]
	port_game.snapshot["turn"] = int(after["turn"])
	after = CivSliceTurn.resolve(port_game.snapshot, CivSliceMatch._empty_draft())
	var port_money := int(after["stocks"].get("money", 0))
	var port_expected := 8 + CivSliceRules.tax_income(int(port_game.snapshot["pop"])) - 2
	if port_money != port_expected:
		failures.append("порт с монетой: %d != %d" % [port_money, port_expected])
	if failures.is_empty():
		print("check_slice_money: OK")
		quit(0)
	else:
		for line in failures:
			push_error(line)
		quit(1)
