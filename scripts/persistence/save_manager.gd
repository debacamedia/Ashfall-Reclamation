extends Node
## Saves and loads the game as versioned JSON in user://saves/.
##
## Autoload "SaveManager" (Project Settings → Globals). Quick save F5, quick
## load F9.
##
## WHAT IS SAVED: every node in the "persist" group under the world root (the
## current level) that implements:
##   save_state() -> Dictionary      plain JSON-safe data
##   load_state(data: Dictionary)    validates and applies it
## and optionally:
##   is_save_removable() -> bool     true for things that can disappear
##                                    (pickups): if a save doesn't list one,
##                                    loading removes it.
## Today that's the player (position, view, health, inventory, magazine),
## salvage containers (searched + contents) and pickups (taken ones stay
## gone, dropped ones come back).
##
## Each entry records the node's path in the level, its scene file and its
## parent, so a node that's missing on load (a pickup taken after saving, an
## item dropped before saving) is re-created.
##
## FORMAT (version 3):
##   {"format": "ashfall_save", "version": 3, "saved_at": "...",
##    "level": "res://levels/early_zone/early_zone.tscn",
##    "nodes": [{"path": "Player", "scene": "res://...", "parent": ".",
##               "data": {...}}, ...],
##    "regions": {"res://levels/…/other.tscn": {"nodes": [...]}, ...}}
## "regions" is the remembered state of the regions you're not in
## (WorldManager, Increment 12); same node entries, no players.
## Older versions are upgraded in _migrate(); newer ones are refused.
##
## Version 3 (Increment 15): Outpost 17 and Halden's Crossing stopped being
## levels and became sites in the early zone. Older saves are moved over:
## each entry's path gains its site ("Loot/Medkit" -> "Outpost17/Loot/Medkit"),
## positions in Halden's Crossing move by where the town now stands, and
## built structures keep their own names. A site the save knew nothing about
## (a town never visited) is listed in "untouched" and left as it is.
##
## AUTHORITY: in co-op only the host saves and loads (the world state lives
## there); clients will receive the result through normal replication.

signal saved(path: String)
signal loaded(path: String)
## Saving or loading didn't happen; `reason` is shown to the player.
signal failed(reason: String)

const FORMAT := "ashfall_save"
const SAVE_VERSION := 4
const QUICK_SLOT := "quicksave"
## The level the old Outpost 17 / Halden's Crossing levels became part of.
const ZONE_LEVEL := "res://levels/early_zone/early_zone.tscn"
## Old level -> [its site node in the zone, where the site now stands].
const SITE_MIGRATION := {
	"res://levels/outpost_17/outpost_17.tscn": ["Outpost17", Vector3.ZERO],
	"res://levels/haldens_crossing/haldens_crossing.tscn": ["HaldensCrossing", Vector3(450, 0, -275)],
}

## Where saves go. Tests point this somewhere else.
## Places built out in Increment 16 (blockouts with nothing to save before):
## a version 3 save leaves everything in them as it is.
const PLACES_ADDED_V4 := ["SaintMercyClinic", "AshCreekFarms", "SmugglersGulch", "BlackRidgeMine", "NorthwatchOutpost"]

var save_dir := "user://saves"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		save_game(QUICK_SLOT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		load_game(QUICK_SLOT)
		get_viewport().set_input_as_handled()


func slot_path(slot: String) -> String:
	return save_dir.path_join(slot.validate_filename() + ".json")


func has_save(slot := QUICK_SLOT) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func delete_save(slot := QUICK_SLOT) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))


# ---------------------------------------------------------------- saving

## Writes the world under `world_root` (default: the current scene) to a
## slot. Returns OK, or an error after emitting failed(reason).
func save_game(slot := QUICK_SLOT, world_root: Node = null) -> Error:
	var root := world_root if world_root != null else get_tree().current_scene
	if root == null:
		return _fail("Nothing to save", ERR_UNCONFIGURED)
	for p in get_tree().get_nodes_in_group("players"):
		if root.is_ancestor_of(p) and (p as PlayerController).is_dead():
			return _fail("Can't save while dead", ERR_UNAVAILABLE)
	var data := build_save_data(root)
	var err := DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK and not DirAccess.dir_exists_absolute(save_dir):
		return _fail("Can't create the save folder", err)
	# Write to a temporary file first so a crash can't leave half a save
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("Can't write the save file", FileAccess.get_open_error())
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _fail("Can't write the save file", err)
	saved.emit(path)
	return OK


## The save as a Dictionary (also used by tests and, later, the network).
func build_save_data(root: Node) -> Dictionary:
	var nodes := []
	for n in get_tree().get_nodes_in_group("persist"):
		if not root.is_ancestor_of(n) or not n.has_method("save_state"):
			continue
		nodes.append({
			"path": str(root.get_path_to(n)),
			"scene": n.scene_file_path,
			"parent": str(root.get_path_to(n.get_parent())),
			"data": n.call("save_state"),
		})
	return {
		"format": FORMAT,
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"level": root.scene_file_path,
		"nodes": nodes,
		"regions": _world().get_saved_regions(root.scene_file_path) if _world() != null else {},
	}


# ---------------------------------------------------------------- loading

## Loads a slot into `world_root` (default: the current scene). Returns OK,
## or an error after emitting failed(reason). If the save is for a different
## level, that level is opened first and the save applied once it's ready.
func load_game(slot := QUICK_SLOT, world_root: Node = null) -> Error:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return _fail("No quick save yet (F5 to save)" if slot == QUICK_SLOT else "No save in slot " + slot, ERR_FILE_NOT_FOUND)
	var data := read_save_file(path)
	if data.is_empty():
		return _fail("Save file is damaged", ERR_FILE_CORRUPT)
	var check := validate(data)
	if check != "":
		return _fail(check, ERR_INVALID_DATA)
	data = _migrate(data)
	var root := world_root if world_root != null else get_tree().current_scene
	var level := str(data.get("level", ""))
	if world_root == null and level != "" and (root == null or root.scene_file_path != level):
		if not ResourceLoader.exists(level):
			return _fail("The saved level no longer exists", ERR_FILE_NOT_FOUND)
		get_tree().change_scene_to_file(level)
		_apply_after_scene_change.call_deferred(data, path)
		return OK
	if root == null:
		return _fail("Nothing to load into", ERR_UNCONFIGURED)
	apply_save_data(data, root)
	if _world() != null:
		_world().set_saved_regions(data.get("regions"), root.scene_file_path)
	loaded.emit(path)
	return OK


## Parsed JSON, or {} if the file is missing or not a JSON object.
func read_save_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


## "" if `data` is a save this version can load, otherwise the reason.
func validate(data: Dictionary) -> String:
	if data.get("format") != FORMAT:
		return "Not an Ashfall save"
	var version: Variant = data.get("version")
	if not (version is float or version is int):
		return "Save has no version"
	if int(version) > SAVE_VERSION:
		return "Save is from a newer version of the game"
	if int(version) < 1 or not data.get("nodes") is Array:
		return "Save file is damaged"
	return ""


## Applies saved state to the world under `root`.
func apply_save_data(data: Dictionary, root: Node) -> void:
	var entries: Array = data.get("nodes", [])
	var listed := {}
	for e in entries:
		if e is Dictionary:
			listed[str(e.get("path", ""))] = true
	# Sites the save knew nothing about keep everything they have
	var untouched: Array[Node] = []
	var untouched_paths: Variant = data.get("untouched", [])
	if untouched_paths is Array:
		for u in untouched_paths:
			var n := root.get_node_or_null(NodePath(str(u)))
			if n != null:
				untouched.append(n)
	# Things that were gone when the game was saved (taken pickups) or
	# appeared since (items dropped after saving) are removed first.
	for n in get_tree().get_nodes_in_group("persist"):
		if untouched.any(func(u: Node) -> bool: return u.is_ancestor_of(n)):
			continue
		if root.is_ancestor_of(n) and not listed.has(str(root.get_path_to(n))) \
				and n.has_method("is_save_removable") and n.call("is_save_removable"):
			n.get_parent().remove_child(n)
			n.queue_free()
	for e in entries:
		if not e is Dictionary or not e.get("data") is Dictionary:
			continue
		var node := root.get_node_or_null(NodePath(str(e.get("path", ""))))
		if node == null:
			node = _recreate(e, root)
		if node != null and node.has_method("load_state"):
			node.call("load_state", e["data"])


func _recreate(entry: Dictionary, root: Node) -> Node:
	var scene_path := str(entry.get("scene", ""))
	var parent := root.get_node_or_null(NodePath(str(entry.get("parent", ""))))
	if parent == null or scene_path == "" or not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path):
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	var node_name := str(entry.get("path", "")).get_file()
	if node_name != "" and not node_name.begins_with("@"):
		node.name = node_name
	parent.add_child(node)
	return node


func _apply_after_scene_change(data: Dictionary, path: String) -> void:
	# change_scene_to_file swaps the scene at the end of the frame
	for i in 3:
		await get_tree().process_frame
	var root := get_tree().current_scene
	if root == null:
		_fail("Couldn't open the saved level", ERR_CANT_OPEN)
		return
	apply_save_data(data, root)
	if _world() != null:
		_world().set_saved_regions(data.get("regions"), root.scene_file_path)
	loaded.emit(path)


## Upgrades older save versions.
##   1 → 2: no other regions remembered yet.
##   2 → 3: Outpost 17 and Halden's Crossing became sites in the early zone.
func _migrate(data: Dictionary) -> Dictionary:
	if int(data.get("version", 1)) < 2:
		data["regions"] = {}
		data["version"] = 2
	if int(data.get("version", 2)) < 3:
		data = migrate_to_zone(data)
		data["version"] = 3
	if int(data.get("version", 3)) < 4:
		data = mark_new_places_untouched(data)
		data["version"] = 4
	return data


## A save from before the five places were built knows nothing of their
## loot, so loading it must not clear them (Increment 16).
static func mark_new_places_untouched(data: Dictionary) -> Dictionary:
	var untouched: Array = data.get("untouched", []) if data.get("untouched") is Array else []
	for place in PLACES_ADDED_V4:
		var saved_any := false
		if data.get("nodes") is Array:
			for e in data["nodes"]:
				if e is Dictionary and str(e.get("path", "")).begins_with(place + "/"):
					saved_any = true
					break
		if not saved_any and not untouched.has(place):
			untouched.append(place)
	data["untouched"] = untouched
	return data


## Moves a version 2 save from the old levels into the early zone.
static func migrate_to_zone(data: Dictionary) -> Dictionary:
	var level := str(data.get("level", ""))
	if not SITE_MIGRATION.has(level):
		return data
	var nodes := []
	var seen: Array[String] = []
	nodes.append_array(_move_entries(data.get("nodes", []), level))
	seen.append(level)
	var regions: Variant = data.get("regions", {})
	var left := {}
	if regions is Dictionary:
		for other in regions:
			var state: Variant = regions[other]
			if SITE_MIGRATION.has(other) and state is Dictionary and (state as Dictionary).get("nodes") is Array:
				nodes.append_array(_move_entries(state["nodes"], other))
				seen.append(other)
			else:
				left[other] = state
	var untouched := []
	for old in SITE_MIGRATION:
		if not seen.has(old):
			untouched.append(SITE_MIGRATION[old][0])
	data["level"] = ZONE_LEVEL
	data["nodes"] = nodes
	data["regions"] = left
	data["untouched"] = untouched
	return data


static func _move_entries(entries: Variant, level: String) -> Array:
	var out := []
	if not entries is Array:
		return out
	var site: String = SITE_MIGRATION[level][0]
	var offset: Vector3 = SITE_MIGRATION[level][1]
	var n := 0
	for e in entries:
		if not e is Dictionary:
			continue
		var entry := (e as Dictionary).duplicate(true)
		var path := str(entry.get("path", ""))
		var parent := str(entry.get("parent", "."))
		if path == "Player":
			pass  # the zone's player
		elif path.begins_with("Structures/"):
			# One Structures node for the whole zone now: keep names apart
			entry["path"] = "Structures/%s_%d" % [site, n]
			n += 1
		else:
			entry["path"] = site + "/" + path
			entry["parent"] = site if parent == "." else site + "/" + parent
		if offset != Vector3.ZERO and entry.get("data") is Dictionary:
			var d: Dictionary = entry["data"]
			for key in ["position", "origin"]:
				var v: Variant = d.get(key)
				if v is Array and (v as Array).size() == 3:
					d[key] = [float(v[0]) + offset.x, float(v[1]) + offset.y, float(v[2]) + offset.z]
		out.append(entry)
	return out


## The WorldManager autoload (other regions' state), if present.
func _world() -> Node:
	return get_node_or_null("/root/WorldManager")


func _fail(reason: String, err: Error) -> Error:
	failed.emit(reason)
	return err
