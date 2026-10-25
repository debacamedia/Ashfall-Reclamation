class_name ItemDatabase
extends RefCounted
## Looks up ItemDefinitions by id. Scans res://resources/items/ (recursively)
## the first time it's used. Saves, trades and network messages refer to
## items by id, and turn them back into definitions here.

const ROOT := "res://resources/items"

static var _by_id: Dictionary = {}
static var _weapons: Dictionary = {}
static var _loaded := false


static func get_item(id: StringName) -> ItemDefinition:
	_ensure_loaded()
	return _by_id.get(id)


static func all_items() -> Array[ItemDefinition]:
	_ensure_loaded()
	var out: Array[ItemDefinition] = []
	for item in _by_id.values():
		out.append(item)
	return out


## The first AMMO item that feeds `ammo_type` (e.g. rifle_556 → Rifle Ammo).
static func find_ammo_item(ammo_type: StringName) -> ItemDefinition:
	_ensure_loaded()
	for item: ItemDefinition in _by_id.values():
		if item.category == ItemDefinition.Category.AMMO and item.ammo_type == ammo_type:
			return item
	return null


## A WeaponDefinition by its id (saves store weapon ids).
static func get_weapon(id: StringName) -> WeaponDefinition:
	_ensure_loaded()
	return _weapons.get(id)


## The WEAPON item that gives this gun (for dropping or showing it).
static func find_weapon_item(weapon_id: StringName) -> ItemDefinition:
	_ensure_loaded()
	for item: ItemDefinition in _by_id.values():
		if item.category == ItemDefinition.Category.WEAPON and item.weapon != null and item.weapon.id == weapon_id:
			return item
	return null


## Forces a rescan (after adding item files at runtime, e.g. in tools).
static func reload() -> void:
	_loaded = false
	_by_id.clear()
	_weapons.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scan(ROOT)


static func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(path.path_join(sub))
	for file in dir.get_files():
		# Exported games list "x.tres.remap" instead of "x.tres"
		var name := file.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var res := load(path.path_join(name))
		if res is ItemDefinition:
			_by_id[(res as ItemDefinition).id] = res
		elif res is WeaponDefinition:
			_weapons[(res as WeaponDefinition).id] = res
