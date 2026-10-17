extends SceneTree

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen = load("res://game/main.tscn").instantiate()
	root.add_child(screen)
	expect(screen.board.show_grid == false, "в обзоре сетки нет")
	expect("Люди 30" in screen.stats_label.text, screen.stats_label.text)
	expect("Скорость +3" in screen.stats_label.text, screen.stats_label.text)
	expect("Людей станет 33" in screen.stats_label.text, screen.stats_label.text)
	screen.enter_build()
	expect(screen.board.show_grid, "в строительстве сетка есть")
	screen.pick_building("hut")
	screen.click_cell(9, 0)
	expect("нельзя" in screen.message_label.text, screen.message_label.text)
	screen.pick_building("pen")
	screen.click_cell(5, 2)
	screen.click_cell(6, 2)
	expect(screen.confirm_selection() == "", "загон в черновик")
	var order_id := int(screen.game.draft["orders"][0]["id"])
	screen.cancel_order(order_id)
	expect(screen.game.draft["orders"].is_empty(), "отмена снимает приказ")
	screen.pick_building("wood_yard")
	screen.click_cell(2, 1)
	screen.click_cell(3, 1)
	expect(screen.confirm_selection() == "", "двор")
	screen.pick_building("hut")
	screen.click_cell(4, 1)
	expect(screen.confirm_selection() == "", "хижина")
	expect(screen.finish_turn() == "", "ход 1")
	expect("Люди 33" in screen.stats_label.text, screen.stats_label.text)
	expect("Лояльность 52" in screen.stats_label.text, screen.stats_label.text)
	expect("Скорость +1" in screen.stats_label.text, screen.stats_label.text)
	expect("Людей станет 34" in screen.stats_label.text, screen.stats_label.text)
	expect(screen.board.show_grid == false, "после хода снова обзор")
	screen.enter_inspect()
	screen.click_cell(0, 0)
	expect("Хижина" in screen.inspect_label.text, screen.inspect_label.text)
	for _i in 3:
		expect(screen.finish_turn() == "", "пустой ход")
	expect(screen.finish_turn() != "", "без выбора ход закрыт")
	expect(str(screen.game.snapshot["current_event"]) == "settlers", "пришли поселенцы")
	screen.choose_option("refuse")
	expect(screen.finish_turn() == "", "отказ записан в ход")
	if _failed == 0:
		print("Экран: партия через интерфейс сошлась.")
		quit(0)
	else:
		print("Экран: провалов %d." % _failed)
		quit(1)


func expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed += 1
	print("FAIL: ", message)
