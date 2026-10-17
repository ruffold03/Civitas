class_name CivSliceTech
extends RefCounted

const CivSliceCatalog = preload("res://sim/civ_slice_catalog.gd")
const CivSliceRules = preload("res://sim/civ_slice_rules.gd")


static func researched(state: Dictionary) -> Array:
	return state.get("technologies", [])


static func is_researched(state: Dictionary, tech_id: String) -> bool:
	return researched(state).has(tech_id)


static func progress_map(state: Dictionary) -> Dictionary:
	if not state.has("tech_progress"):
		state["tech_progress"] = {}
	return state["tech_progress"]


static func progress_of(state: Dictionary, tech_id: String) -> int:
	return int(progress_map(state).get(tech_id, 0))


static func add_progress(state: Dictionary, tech_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var progress: Dictionary = progress_map(state)
	progress[tech_id] = int(progress.get(tech_id, 0)) + amount


static func apply_research_choice(state: Dictionary, tech_id: String) -> void:
	var bank := int(state.get("science", 0))
	if bank > 0:
		add_progress(state, tech_id, bank)
		state["science"] = 0
	state["research"] = tech_id


static func clear_research(state: Dictionary) -> void:
	state["research"] = ""


static func advance_turn(state: Dictionary, notes: Array) -> void:
	var income := CivSliceRules.science_income(state["buildings"])
	var active := str(state.get("research", ""))
	if active != "":
		add_progress(state, active, income)
		var total := progress_of(state, active)
		notes.append({
			"kind": "science_gain",
			"amount": income,
			"research": active,
			"progress": total,
			"cost": int(CivSliceCatalog.technology(active)["cost"]),
		})
		if try_complete(state, active, notes):
			state["research"] = ""
		return
	var bank := int(state.get("science", 0)) + income
	state["science"] = mini(bank, income)
	notes.append({"kind": "science_bank", "amount": int(state["science"]), "income": income})


static func try_complete(state: Dictionary, tech_id: String, notes: Array) -> bool:
	if is_researched(state, tech_id):
		return false
	var cost := int(CivSliceCatalog.technology(tech_id)["cost"])
	if progress_of(state, tech_id) < cost:
		return false
	var list: Array = researched(state)
	list.append(tech_id)
	state["technologies"] = list
	progress_map(state).erase(tech_id)
	notes.append({"kind": "tech_done", "id": tech_id, "name": CivSliceCatalog.technology(tech_id)["name"]})
	return true


static func can_start_research(state: Dictionary, tech_id: String) -> Dictionary:
	if str(state.get("mode", "play")) != "play":
		return {"ok": false, "error": "Партия уже закончена."}
	if not CivSliceCatalog.has_technology_def(tech_id):
		return {"ok": false, "error": "Такой технологии нет."}
	if is_researched(state, tech_id):
		return {"ok": false, "error": "Технология уже изучена."}
	if not CivSliceCatalog.technology_prereqs_met(tech_id, researched(state)):
		return {"ok": false, "error": "Сначала изучи предшественников."}
	if str(state.get("research", "")) == tech_id:
		return {"ok": false, "error": "Уже изучается."}
	return {"ok": true, "error": ""}
