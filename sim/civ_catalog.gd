class_name CivCatalog
extends RefCounted

## Каталог одной партии древности. Числа взяты из «Правил прототипа».

const RESOURCES: Array[String] = ["food", "wood", "stone"]
const RESOURCE_NAMES := {
	"food": "Еда",
	"wood": "Дерево",
	"stone": "Камень",
}
const BASE_STORAGE := {"food": 30, "wood": 20, "stone": 10}
const LOYALTY_MIN := 0
const LOYALTY_MAX := 100
const VICTORY_POP := 100
const ERA := "antiquity"

const BUILDINGS := {
	"hut": {
		"name": "Хижина",
		"area": 1,
		"build_time": 1,
		"cost": {"wood": 10},
		"inputs": {},
		"outputs": {},
		"pop_capacity": 5,
		"storage": {},
		"water": 0,
		"loyalty": 0,
	},
	"well": {
		"name": "Колодец",
		"area": 1,
		"build_time": 2,
		"cost": {"stone": 10},
		"inputs": {},
		"outputs": {},
		"pop_capacity": 0,
		"storage": {},
		"water": 40,
		"loyalty": 1,
	},
	"wood_yard": {
		"name": "Дровяной двор",
		"area": 2,
		"build_time": 1,
		"cost": {"wood": 6},
		"inputs": {},
		"outputs": {"wood": 5},
		"pop_capacity": 0,
		"storage": {"wood": 30},
		"water": 0,
		"loyalty": 0,
	},
	"stone_yard": {
		"name": "Каменный двор",
		"area": 2,
		"build_time": 2,
		"cost": {"wood": 8},
		"inputs": {},
		"outputs": {"stone": 2},
		"pop_capacity": 0,
		"storage": {"stone": 20},
		"water": 0,
		"loyalty": -1,
	},
	"hearth": {
		"name": "Кострище",
		"area": 1,
		"build_time": 1,
		"cost": {"wood": 4, "stone": 4},
		"inputs": {"wood": 2},
		"outputs": {},
		"pop_capacity": 0,
		"storage": {},
		"water": 0,
		"loyalty": 3,
	},
	"field": {
		"name": "Поле",
		"area": 4,
		"build_time": 2,
		"cost": {"wood": 8},
		"inputs": {},
		"outputs": {"food": 8},
		"pop_capacity": 0,
		"storage": {},
		"water": 0,
		"loyalty": 0,
	},
	"pen": {
		"name": "Загон",
		"area": 2,
		"build_time": 1,
		"cost": {"wood": 6},
		"inputs": {},
		"outputs": {"food": 4},
		"pop_capacity": 0,
		"storage": {},
		"water": 0,
		"loyalty": 0,
	},
}

const EVENTS := {
	"settlers": {
		"name": "Поселенцы",
		"text": "К поселению вышли люди.",
		"turn": 5,
		"condition": "pop_below_100",
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
		"text": "В поселении болезнь.",
		"turn": 10,
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
		"turn": 15,
		"condition": "has_working_field",
		"options": {
			"store": {
				"name": "В закрома",
				"cost": {},
				"effects": [{"kind": "field_food_add", "amount": 4, "remaining": 4}],
			},
			"feast": {
				"name": "Праздник",
				"cost": {},
				"effects": [
					{"kind": "field_food_add", "amount": 2, "remaining": 4},
					{"kind": "loyalty_delta", "amount": 2, "remaining": 4},
				],
			},
		},
	},
	"drought": {
		"name": "Засуха",
		"text": "Поля сохнут.",
		"turn": 20,
		"condition": "has_working_field",
		"options": {
			"wait": {
				"name": "Переждать",
				"cost": {},
				"effects": [{"kind": "field_food_replace", "amount": 4, "remaining": 4}],
			},
			"water": {
				"name": "Полить",
				"cost": {"stone": 4},
				"effects": [{"kind": "field_food_replace", "amount": 6, "remaining": 4}],
			},
		},
	},
}


static func building(type_id: String) -> Dictionary:
	return BUILDINGS[type_id]


static func has_building(type_id: String) -> bool:
	return BUILDINGS.has(type_id)


static func event(event_id: String) -> Dictionary:
	return EVENTS[event_id]


static func empty_stocks() -> Dictionary:
	return {"food": 0, "wood": 0, "stone": 0}
