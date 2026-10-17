extends Control

## Превью техсцены 3D. Запуск сцены F6. F1–F3 — сценарии, T — статусы, G — сетка, Q/E — поворот камеры.

const CivSliceMatch = preload("res://sim/civ_slice_match.gd")

@onready var _viewport: SubViewport = $ViewportContainer/SubViewport
@onready var _city: Node3D = $ViewportContainer/SubViewport/CityView3D
@onready var _title: Label = $Overlay/Title
@onready var _hint: Label = $Overlay/Hint
@onready var _pick: Label = $Overlay/Pick

var _game
var _scenario := "rome"
var _show_grid := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _city.has_signal("cell_clicked"):
		_city.cell_clicked.connect(_on_cell_clicked)
	_load("rome")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_load("rome")
			KEY_F2:
				_load("neapolis")
			KEY_F3:
				_load("tarentum")
			KEY_G:
				_show_grid = not _show_grid
				_refresh()
			KEY_SPACE:
				if _game != null:
					_game.end_turn()
					_refresh()
			KEY_T:
				_cycle_demo_status()


func _load(scenario_id: String) -> void:
	_scenario = scenario_id
	_game = CivSliceMatch.new_game(scenario_id)
	_refresh()


func _refresh() -> void:
	if _game == null:
		return
	_city.call("apply_snapshot", _game.snapshot, _show_grid, [], [])
	var snap: Dictionary = _game.snapshot
	_title.text = "Техсцена 3D · %s · ход %d" % [_scenario, int(snap["turn"])]
	_hint.text = "F1–F3 города · Space ход · T статусы · G сетка · Q/E камера · ЛКМ сдвиг · колёсико · СКМ сдвиг"


func _cycle_demo_status() -> void:
	if _game == null:
		return
	var order: Array[String] = ["working", "idle", "building"]
	var seen := {}
	for building in _game.snapshot.get("buildings", []):
		var type_id := str(building.get("type", ""))
		if seen.has(type_id):
			continue
		seen[type_id] = true
		var current := str(building.get("status", "working"))
		var idx := order.find(current)
		building["status"] = order[(idx + 1) % order.size()]
	_refresh()


func _on_cell_clicked(x: int, y: int) -> void:
	_pick.text = "Клетка (%d, %d)" % [x, y]
