class_name CivUtil
extends RefCounted

## Копия словарей и массивов. Числа остаются числами, в отличие от обхода через JSON.


static func deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var copied := {}
		for key in value:
			copied[key] = deep_copy(value[key])
		return copied
	if value is Array:
		var copied: Array = []
		for item in value:
			copied.append(deep_copy(item))
		return copied
	return value


static func cell_key(cell: Array) -> String:
	return "%d,%d" % [int(cell[0]), int(cell[1])]
