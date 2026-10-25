class_name RecipeDatabase
extends RefCounted
## All RecipeDefinitions under res://resources/recipes/, by id. Loaded the
## first time it's used.

const ROOT := "res://resources/recipes"

static var _by_id: Dictionary = {}
static var _loaded := false


static func get_recipe(id: StringName) -> RecipeDefinition:
	_ensure_loaded()
	return _by_id.get(id)


## Every recipe, sorted by category then name.
static func all_recipes() -> Array[RecipeDefinition]:
	_ensure_loaded()
	var out: Array[RecipeDefinition] = []
	for r in _by_id.values():
		out.append(r)
	out.sort_custom(func(a: RecipeDefinition, b: RecipeDefinition) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.get_display_name() < b.get_display_name())
	return out


## Recipes whose output is `item` (e.g. "how do I make gunpowder?").
static func recipes_for(item: ItemDefinition) -> Array[RecipeDefinition]:
	var out: Array[RecipeDefinition] = []
	for r in all_recipes():
		if r.output == item:
			out.append(r)
	return out


static func reload() -> void:
	_loaded = false
	_by_id.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var r := load(ROOT.path_join(name)) as RecipeDefinition
		if r != null:
			_by_id[r.id] = r
