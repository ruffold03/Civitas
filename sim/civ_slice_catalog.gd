class_name CivSliceCatalog
extends RefCounted

## Каталог вертикального среза Италии. Числа — из «Вертикальный срез — Италия» и карточек в Контент/.

const COUNTRY_ID := "italy"
const ERA := "classical"

const RESOURCES: Array[String] = ["food", "wood", "stone", "clay", "metal", "wine", "money"]
const RESOURCE_NAMES := {
	"food": "Еда",
	"wood": "Дерево",
	"stone": "Камень",
	"clay": "Глина",
	"metal": "Металл",
	"wine": "Вино",
	"money": "Деньги",
}
const BASE_STORAGE := {
	"food": 40,
	"wood": 25,
	"stone": 15,
	"clay": 20,
	"metal": 12,
	"wine": 15,
	"money": 999,
}
const LOYALTY_MIN := 0
const LOYALTY_MAX := 100
const VICTORY_POP := 500
const TURN_LIMIT := 150

const TECHNOLOGIES := {
	"writing": {"name": "Письмено", "cost": 20, "unlocks": ["forum"]},
	"moneta": {"name": "Монета", "cost": 35, "unlocks": ["market"], "requires": ["writing"]},
	"engineering": {"name": "Инженерия", "cost": 45, "unlocks": ["aqueduct"], "requires": ["moneta"]},
	"military": {"name": "Ополчение", "cost": 30, "unlocks": ["barracks"], "requires": ["writing"]},
}

const EVENTS := {
	"hill_raiders": {
		"name": "Набег горцев",
		"text": "С холмов идут налётчики.",
		"turn": 15,
		"condition": "always",
		"options": {
			"arms": {
				"name": "Оружие",
				"cost": {"metal": 5},
				"effects": [{"kind": "prestige_once", "amount": 5, "remaining": 1}],
			},
			"tribute_wine": {
				"name": "Откуп (вино)",
				"cost": {"wine": 8},
				"effects": [],
			},
			"tribute_money": {
				"name": "Откуп (деньги)",
				"cost": {"money": 10},
				"requires_tech": "moneta",
				"effects": [],
			},
			"refuse": {
				"name": "Отказать",
				"cost": {},
				"effects": [
					{"kind": "prestige_once", "amount": -8, "remaining": 1},
					{"kind": "loyalty_delta", "amount": -2, "remaining": 2},
				],
			},
		},
	},
	"consul_feast": {
		"name": "Пир Консула",
		"text": "Консул зовёт на пир.",
		"turn": 30,
		"condition": "loyalty_at_least_45",
		"options": {
			"feast": {
				"name": "Праздник",
				"cost": {"wine": 6},
				"effects": [{"kind": "loyalty_delta", "amount": 4, "remaining": 2}],
			},
			"save": {
				"name": "Сберечь",
				"cost": {},
				"effects": [{"kind": "prestige_once", "amount": 2, "remaining": 1}],
			},
		},
	},
	"capital_review": {
		"name": "Пересмотр столицы",
		"text": "Страна выбирает столицу.",
		"turns": [50, 100, 150],
		"condition": "always",
		"auto": true,
		"options": {},
	},
	"neighbor_war": {
		"name": "Война с соседями",
		"text": "Соседи требуют уступок.",
		"turn": 60,
		"condition": "barracks_or_pop_120",
		"options": {
			"supply": {
				"name": "Снабжение",
				"cost": {},
				"effects": [
					{"kind": "pay_per_turn", "resource": "metal", "amount": 4, "remaining": 4},
					{"kind": "prestige_delta", "amount": 6, "remaining": 4},
				],
			},
			"mobilize": {
				"name": "Мобилизация",
				"cost": {},
				"effects": [{"kind": "pop_speed_delta", "amount": -2, "remaining": 4}],
			},
			"neutral": {
				"name": "Нейтралитет",
				"cost": {},
				"effects": [{"kind": "prestige_once", "amount": -10, "remaining": 1}],
			},
		},
	},
	"god_games": {
		"name": "Игры в честь богов",
		"text": "Страна готовит праздник.",
		"turn": 75,
		"condition": "has_temple",
		"options": {
			"join": {
				"name": "Участвовать",
				"cost": {"money": 15},
				"effects": [{"kind": "prestige_once", "amount": 12, "remaining": 1}],
			},
			"skip": {
				"name": "Отказаться",
				"cost": {},
				"effects": [{"kind": "loyalty_delta", "amount": -2, "remaining": 1}],
			},
		},
	},
	"trade_contest": {
		"name": "Соревнование торговли",
		"text": "Торговые города соревнуются за награду.",
		"turn": 90,
		"condition": "trade_infrastructure",
		"options": {
			"boost": {
				"name": "Поддержать торговлю",
				"cost": {"wood": 6},
				"effects": [{"kind": "prestige_delta", "amount": 3, "remaining": 3}],
			},
			"rest": {
				"name": "Не участвовать",
				"cost": {},
				"effects": [],
			},
		},
	},
	"settlers": {
		"name": "Поселенцы",
		"text": "К городу вышли люди.",
		"turn": 25,
		"condition": "pop_below_victory",
		"options": {
			"accept": {
				"name": "Принять",
				"cost": {},
				"effects": [{"kind": "pop_bonus_once", "amount": 10, "remaining": 1}],
			},
			"refuse": {
				"name": "Отказать",
				"cost": {},
				"effects": [{"kind": "loyalty_delta", "amount": -2, "remaining": 3}],
			},
		},
	},
	"disease": {
		"name": "Болезнь",
		"text": "В городе болезнь.",
		"turn": 70,
		"condition": "crowded_or_loyalty_below_40",
		"options": {
			"tend": {
				"name": "Выхаживать",
				"cost": {},
				"effects": [{"kind": "consumption_half_extra", "amount": 0, "remaining": 4}],
			},
			"wait": {
				"name": "Переждать",
				"cost": {},
				"effects": [{"kind": "pop_speed_delta", "amount": -2, "remaining": 4}],
			},
		},
	},
	"harvest": {
		"name": "Урожай",
		"text": "Год выдался добрым.",
		"turn": 120,
		"condition": "has_working_cropland",
		"options": {
			"store": {
				"name": "В закрома",
				"cost": {},
				"effects": [{"kind": "cropland_food_add", "amount": 4, "remaining": 4}],
			},
			"feast": {
				"name": "Праздник",
				"cost": {},
				"effects": [
					{"kind": "cropland_food_add", "amount": 2, "remaining": 4},
					{"kind": "loyalty_delta", "amount": 2, "remaining": 4},
				],
			},
		},
	},
	"drought": {
		"name": "Засуха",
		"text": "Поля сохнут.",
		"turn": 135,
		"condition": "has_working_cropland",
		"options": {
			"wait": {
				"name": "Переждать",
				"cost": {},
				"effects": [{"kind": "cropland_food_replace", "amount": 4, "remaining": 4}],
			},
			"water": {
				"name": "Полить",
				"cost": {"stone": 4},
				"effects": [{"kind": "cropland_food_replace", "amount": 6, "remaining": 4}],
			},
		},
	},
}

static var _buildings_cache: Dictionary = {}


static func buildings() -> Dictionary:
	if _buildings_cache.is_empty():
		_buildings_cache = _build_buildings()
	return _buildings_cache


static func _build_buildings() -> Dictionary:
	return {
	"town_hall": _mk(
		"Ратуша", 1, 0, {}, {}, {}, 0, {}, 0, 0, {"science": 1}, false
	),
	"domus": _mk("Дом", 1, 1, {"wood": 12}, {}, {}, 6),
	"well": _mk("Колодец", 1, 2, {"stone": 10}, {}, {}, 0, {}, 40, 1),
	"sawmill": _mk("Лесопильня", 2, 1, {"wood": 7}, {}, {"wood": 7}, 0, {"wood": 35}),
	"quarry": _mk("Каменоломня", 2, 2, {"wood": 8}, {}, {"stone": 3}, 0, {"stone": 25}, 0, -1),
	"square": _mk("Площадь", 1, 1, {"wood": 5, "stone": 4}, {"wood": 2}, {}, 0, {}, 0, 4),
	"cropland": _mk("Пашня", 4, 2, {"wood": 8}, {}, {"food": 10}),
	"farm": _mk("Ферма", 2, 1, {"wood": 7}, {}, {"food": 6}),
	"vineyard": _mk("Виноградник", 2, 2, {"wood": 7}, {}, {"wine": 3}),
	"pottery": _mk(
		"Гончарня", 2, 2, {"wood": 5, "clay": 3}, {"clay": 2}, {"clay": 2, "wine": 1}, 0, {"clay": 15}
	),
	"mine": _mk("Рудник", 2, 3, {"wood": 6, "stone": 4}, {}, {"metal": 2}),
	"granary": _mk("Закром", 2, 2, {"wood": 8, "stone": 4}, {}, {}, 0, {"food": 40}),
	"temple": _mk(
		"Храм", 1, 3, {"wood": 6, "stone": 10}, {}, {}, 0, {}, 0, 2, {"science": 1, "requires_road": true}
	),
	"forum": _mk(
		"Форум",
		2,
		4,
		{"wood": 8, "stone": 12},
		{},
		{},
		0,
		{},
		0,
		2,
		{"science": 2, "requires_tech": "writing", "requires_road": true},
	),
	"aqueduct": _mk(
		"Акведук", 3, 5, {"wood": 10, "stone": 15}, {}, {}, 0, {}, 80, 1, {"requires_tech": "engineering"}
	),
	"baths": _mk("Термы", 2, 3, {"wood": 6, "stone": 8}, {"wood": 1}, {}, 0, {}, 0, 3),
	"market": _mk(
		"Рынок", 2, 2, {"wood": 6, "clay": 4}, {}, {"money": 5}, 0, {}, 0, 0, {"requires_tech": "moneta", "requires_road": true}
	),
	"port": _mk(
		"Порт", 3, 4, {"wood": 10, "stone": 8}, {}, {"wine": 2, "money": 8}, 0, {}, 0, 0, {"requires_road": true}
	),
	"barracks": _mk(
		"Казарма", 2, 3, {"wood": 10, "stone": 6, "metal": 8}, {}, {}, 0, {}, 0, -1, {"requires_tech": "military"}
	),
	}


static func building(type_id: String) -> Dictionary:
	return buildings()[type_id]


static func has_building(type_id: String) -> bool:
	return buildings().has(type_id)


static func event(event_id: String) -> Dictionary:
	return EVENTS[event_id]


static func has_event(event_id: String) -> bool:
	return EVENTS.has(event_id)


static func event_on_turn(definition: Dictionary, turn: int) -> bool:
	if definition.has("turns"):
		for scheduled in definition["turns"]:
			if int(scheduled) == turn:
				return true
		return false
	return int(definition.get("turn", -1)) == turn


static func event_calendar_ids() -> Array:
	var ids: Array = []
	for event_id in EVENTS.keys():
		ids.append(event_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _event_sort_turn(EVENTS[a]) < _event_sort_turn(EVENTS[b])
	)
	return ids


static func _event_sort_turn(definition: Dictionary) -> int:
	if definition.has("turns"):
		return int(definition["turns"][0])
	return int(definition.get("turn", 0))


static func technology(tech_id: String) -> Dictionary:
	return TECHNOLOGIES[tech_id]


static func has_technology_def(tech_id: String) -> bool:
	return TECHNOLOGIES.has(tech_id)


static func technology_ids() -> Array:
	return TECHNOLOGIES.keys()


static func technology_prereqs_met(tech_id: String, researched: Array) -> bool:
	var def: Dictionary = TECHNOLOGIES.get(tech_id, {})
	for req in def.get("requires", []):
		if not researched.has(req):
			return false
	return true


static func building_requires_tech(type_id: String) -> String:
	return str(building(type_id).get("requires_tech", ""))


static func empty_stocks() -> Dictionary:
	var stocks := {}
	for resource in RESOURCES:
		stocks[resource] = 0
	return stocks


static func building_ids() -> Array:
	return buildings().keys()


static func _mk(
	name: String,
	area: int,
	build_time: int,
	cost: Dictionary,
	inputs: Dictionary = {},
	outputs: Dictionary = {},
	pop_capacity: int = 0,
	storage: Dictionary = {},
	water: int = 0,
	loyalty: int = 0,
	extras: Dictionary = {},
	player_buildable: bool = true
) -> Dictionary:
	var entry := {
		"name": name,
		"area": area,
		"build_time": build_time,
		"cost": cost,
		"inputs": inputs,
		"outputs": outputs,
		"pop_capacity": pop_capacity,
		"storage": storage,
		"water": water,
		"loyalty": loyalty,
		"science": int(extras.get("science", 0)),
		"requires_tech": str(extras.get("requires_tech", "")),
		"requires_road": bool(extras.get("requires_road", false)),
		"player_buildable": player_buildable,
	}
	return entry
