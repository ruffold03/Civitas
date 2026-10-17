class_name CivGeo
extends RefCounted

const CivUtil = preload("res://sim/civ_util.gd")

## Небольшая карта прототипа: четыре чанка 5×5, без настоящей географии.
## Крайний столбец — вода, нижний ряд кроме воды — обрыв. Обычная земля строится.

const SIZE := 10
const CHUNK := 5


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE


static func terrain_at(x: int, y: int) -> String:
	if not in_bounds(x, y):
		return ""
	if x == SIZE - 1:
		return "water"
	if y == SIZE - 1:
		return "cliff"
	return "land"


static func chunk_of(x: int, y: int) -> Array:
	return [int(x / CHUNK), int(y / CHUNK)]


static func all_chunks() -> Array:
	var chunks: Array = []
	var count := int(SIZE / CHUNK)
	for cy in count:
		for cx in count:
			chunks.append([cx, cy])
	return chunks


static func connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var present := {}
	for cell in cells:
		present[CivUtil.cell_key(cell)] = true
	var stack: Array = [cells[0]]
	var seen := {}
	while not stack.is_empty():
		var current: Array = stack.pop_back()
		var key := CivUtil.cell_key(current)
		if seen.has(key):
			continue
		seen[key] = true
		var x := int(current[0])
		var y := int(current[1])
		for next in [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]:
			if present.has(CivUtil.cell_key(next)):
				stack.append(next)
	return seen.size() == cells.size()
