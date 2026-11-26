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
##    "regions": {"res://levels/…/other.tscn": {"nodes": [...], "away_seconds": 0}, ...},
##    "vehicle_zones": {"CargoTruck": "res://levels/mid_zone/mid_zone.tscn"}}
## "regions" is the remembered state of the regions you're not in
## (WorldManager, Increment 12); same node entries, no players, and how long
## you've been away (Increment 25: their settlements catch up when you're
## back). "vehicle_zones": vehicles driven into another zone (25).
## Older versions are upgraded in _migrate(); newer ones are refused.
##
## Version 3 (Increment 15): Outpost 17 and Halden's Crossing stopped being
## levels and became sites in the early zone. Older saves are moved over:
## each entry's path gains its site ("Loot/Medkit" -> "Outpost17/Loot/Medkit"),
## positions in Halden's Crossing move by where the town now stands, and
## built structures keep their own names. A site the save knew nothing about
## (a town never visited) is listed in "untouched" and left as it is.
##
## AUTOSAVE AND CONTINUE (Increment 24.1): once the boot scene has started
## the game (autosave_enabled), it's saved to the "autosave" slot every
## autosave_minutes of play and when you close the window, and the next
## launch continues from the newest of the autosave and the quick save
## (continue_game). Saves live in user://saves, outside the project, so
## pulling an update never touches them.
##
## GAMES (Increment 33.1): the main menu keeps separate games. Each is a
## folder, user://saves/games/<id>/, holding its own autosave and quick save
## and a game.json (its name, your name, where you were, when you last
## played, how long you've played). use_game() points save_dir at one; the
## quick save, autosave and Continue then work inside it. Saves from before
## (straight in user://saves) become a first game the first time the menu
## opens (migrate_legacy). Tests that set save_dir and no game work as before.
##
## AUTHORITY: in co-op only the host saves and loads (the world state lives
## there); clients will receive the result through normal replication.

signal saved(path: String)
signal loaded(path: String)
## Saving or loading didn't happen; `reason` is shown to the player.
signal failed(reason: String)

const FORMAT := "ashfall_save"
const SAVE_VERSION := 5
const QUICK_SLOT := "quicksave"
const AUTO_SLOT := "autosave"
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
## Outpost 17 rebuilt (Increment 33.2, save version 5): what's gone (a save
## from before that lists it forgets it), and where things moved (a save
## from before keeps what it says of them, but not where they were).
const O17_REMOVED := [
	"Outpost17/Buildings/CommandPost", "Outpost17/Buildings/Barracks", "Outpost17/Buildings/Warehouse",
	"Outpost17/Props/ContainerB", "Outpost17/Props/ContainerC",
	"Outpost17/Props/YardPositionN", "Outpost17/Props/YardPositionW",
	"Outpost17/FiringRange/RangeTower", "Outpost17/FiringRange/FiringLineN", "Outpost17/FiringRange/FiringLineS",
	"Outpost17/FiringRange/LaneGravel", "Outpost17/FiringRange/Target35m", "Outpost17/FiringRange/Target50m",
	"Outpost17/FiringRange/Distance35m", "Outpost17/FiringRange/Distance50m", "Outpost17/FiringRange/Backstop",
]
const O17_MOVED := ["Outpost17/Loot/", "Outpost17/Props/", "Outpost17/Pack2/", "Outpost17/Vehicles/", "Outpost17/FiringRange/"]
const PLACES_ADDED_V4 := ["SaintMercyClinic", "AshCreekFarms", "SmugglersGulch", "BlackRidgeMine", "NorthwatchOutpost"]

var save_dir := "user://saves"
## Where games are kept (save_dir points into one of them while it's played).
var root_dir := "user://saves"
## The game being played ("" before the menu picks one, and in tests).
var current_game := ""
## Seconds played in the current game (kept in its game.json).
var play_seconds := 0.0
## Your name for a new game, given to the player once its level is up.
var _pending_new_name := ""
var _pending_mode := "story"
const GAME_META := "game.json"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Minutes of play between autosaves.
@export var autosave_minutes := 5.0
## Off until the boot scene starts the game (tests and tools never autosave).
## While on, closing the window saves first.
var autosave_enabled := false:
	set(on):
		autosave_enabled = on
		autosave_left = autosave_minutes * 60.0
		if is_inside_tree():
			get_tree().set_auto_accept_quit(not on)
## Seconds until the next autosave.
var autosave_left := 300.0


func _process(delta: float) -> void:
	if current_game != "" and not get_tree().paused and get_tree().current_scene != null \
			and _player_in(get_tree().current_scene) != null:
		play_seconds += delta
	if not autosave_enabled:
		return
	autosave_left -= delta
	if autosave_left <= 0.0:
		# Not now (dead, or no game running): try again in half a minute
		autosave_left = autosave_minutes * 60.0 if autosave() == OK else 30.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave_enabled:
		autosave()
		get_tree().quit()


## Saves to the autosave slot if there's a game to save and you're alive.
## Quiet when it can't (no notice).
func autosave() -> Error:
	var root := get_tree().current_scene
	if root == null or _player_in(root) == null:
		return ERR_UNCONFIGURED
	if (_player_in(root) as PlayerController).is_dead():
		return ERR_UNAVAILABLE
	return save_game(AUTO_SLOT)


## The slot with the newest save (the autosave or the quick save), or "".
func latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot: String in [AUTO_SLOT, QUICK_SLOT]:
		if has_save(slot):
			var t := FileAccess.get_modified_time(slot_path(slot))
			if t > best_time:
				best = slot
				best_time = t
	return best


## Loads the newest save. Returns OK, or an error if there's nothing to
## continue (or it couldn't be loaded: a new game starts instead).
func continue_game() -> Error:
	var slot := latest_slot()
	if slot == "":
		return ERR_FILE_NOT_FOUND
	return load_game(slot)


## When the newest save was made, for the pause menu: "at 8:40 pm" today,
## "on 26 Oct" before that ("" if there's none).
func latest_save_time() -> String:
	var slot := latest_slot()
	if slot == "":
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(FileAccess.get_modified_time(slot_path(slot)) + bias)
	var today := Time.get_date_dict_from_system()
	if int(t["year"]) != int(today["year"]) or int(t["month"]) != int(today["month"]) or int(t["day"]) != int(today["day"]):
		const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		return "on %d %s" % [int(t["day"]), MONTHS[int(t["month"]) - 1]]
	var hour := int(t["hour"])
	return "at %d:%02d %s" % [12 if hour % 12 == 0 else hour % 12, int(t["minute"]), "am" if hour < 12 else "pm"]


static func _player_in(root: Node) -> Node:
	for p in root.get_tree().get_nodes_in_group("players"):
		if root.is_ancestor_of(p):
			return p
	return null


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
	if current_game != "":
		_update_meta(root)
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
		"vehicle_zones": _world().vehicle_zones.duplicate() if _world() != null else {},
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
		_world().set_vehicle_zones(data.get("vehicle_zones"), root)
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
		_world().set_vehicle_zones(data.get("vehicle_zones"), root)
	loaded.emit(path)


## Upgrades older save versions.
##   1 → 2: no other regions remembered yet.
##   2 → 3: Outpost 17 and Halden's Crossing became sites in the early zone.
##   3 → 4: the five new places kept as they are.
##   4 → 5: Outpost 17 rebuilt (33.2).
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
	if int(data.get("version", 4)) < 5:
		data = rebuilt_outpost_17(data)
		data["version"] = 5
	return data


## Outpost 17 rebuilt (Increment 33.2): a save from before forgets what's
## gone and lets what moved stay where the new layout has it (it still
## says what was taken, searched or scrapped). In the early zone's own
## save, or its remembered state while you're in another zone.
static func rebuilt_outpost_17(data: Dictionary) -> Dictionary:
	if str(data.get("level", "")) == ZONE_LEVEL and data.get("nodes") is Array:
		data["nodes"] = _rebuilt_o17_entries(data["nodes"])
	var regions: Variant = data.get("regions")
	if regions is Dictionary and (regions as Dictionary).get(ZONE_LEVEL) is Dictionary:
		var state: Dictionary = regions[ZONE_LEVEL]
		if state.get("nodes") is Array:
			state["nodes"] = _rebuilt_o17_entries(state["nodes"])
	return data


static func _rebuilt_o17_entries(entries: Array) -> Array:
	var out := []
	for e in entries:
		if not e is Dictionary:
			out.append(e)
			continue
		var path := str((e as Dictionary).get("path", ""))
		if O17_REMOVED.any(func(r: String) -> bool: return path == r or path.begins_with(r + "/")):
			continue
		if O17_MOVED.any(func(m: String) -> bool: return path.begins_with(m)) and (e as Dictionary).get("data") is Dictionary:
			var d: Dictionary = e["data"]
			for key in ["position", "origin", "basis", "yaw"]:
				d.erase(key)
		out.append(e)
	return out


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
# ---------------------------------------------------------------- games (33.1)

func games_dir() -> String:
	return root_dir.path_join("games")


func game_dir(id: String) -> String:
	return games_dir().path_join(id.validate_filename())


## A game's details: {"id", "name", "player_name", "place", "created",
## "last_played" (unix), "play_seconds", "has_save"}, or {} if there's no
## such game.
func game_info(id: String) -> Dictionary:
	var dir := game_dir(id)
	if not DirAccess.dir_exists_absolute(dir):
		return {}
	var meta := read_save_file(dir.path_join(GAME_META))
	var info := {"id": id, "name": str(meta.get("name", "Game")), "player_name": str(meta.get("player_name", "")),
		"place": str(meta.get("place", "Outpost 17")), "created": _num(meta.get("created"), 0.0),
		"last_played": _num(meta.get("last_played"), 0.0), "play_seconds": _num(meta.get("play_seconds"), 0.0),
		"mode": "free_play" if str(meta.get("mode", "story")) == "free_play" else "story",
		"achievements": (meta.get("achievements") as Array).filter(func(a: Variant) -> bool: return a is String) if meta.get("achievements") is Array else []}
	info["has_save"] = FileAccess.file_exists(dir.path_join(AUTO_SLOT + ".json")) or FileAccess.file_exists(dir.path_join(QUICK_SLOT + ".json"))
	return info


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else fallback


## Every game, the last played first.
func list_games() -> Array:
	var out := []
	var d := DirAccess.open(games_dir())
	if d == null:
		return out
	for id in d.get_directories():
		var info := game_info(id)
		if not info.is_empty():
			out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["last_played"]) > float(b["last_played"]))
	return out


## The game Continue would carry on (the last one played that has a save),
## or "".
func latest_game() -> String:
	for g: Dictionary in list_games():
		if g["has_save"]:
			return g["id"]
	return ""


## Makes a new game's folder and picks it. Returns its id.
func create_game(game_name: String, player_name := "") -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var id := "game_%d" % stamp
	var n := 2
	while DirAccess.dir_exists_absolute(game_dir(id)):
		id = "game_%d_%d" % [stamp, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(game_dir(id))
	var clean := game_name.strip_edges().left(40)
	_write_meta(id, {"name": clean if clean != "" else "Game %d" % (list_games().size() + 1), "player_name": player_name,
		"place": "Outpost 17", "created": stamp, "last_played": stamp, "play_seconds": 0.0})
	use_game(id)
	return id


## Points saving and loading at game `id`.
func use_game(id: String) -> void:
	current_game = id
	save_dir = game_dir(id)
	play_seconds = float(game_info(id).get("play_seconds", 0.0))


func rename_game(id: String, game_name: String) -> void:
	var clean := game_name.strip_edges().left(40)
	if clean == "" or game_info(id).is_empty():
		return
	var meta := read_save_file(game_dir(id).path_join(GAME_META))
	meta["name"] = clean
	_write_meta(id, meta)


## Deletes game `id` and its saves, for good.
func delete_game(id: String) -> void:
	var dir := game_dir(id)
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	if current_game == id:
		current_game = ""
		save_dir = root_dir


func _write_meta(id: String, meta: Dictionary) -> void:
	var f := FileAccess.open(game_dir(id).path_join(GAME_META), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "\t"))
		f.close()


## After a save: when, how long, where and who.
func _update_meta(root: Node) -> void:
	var meta := read_save_file(game_dir(current_game).path_join(GAME_META))
	meta["last_played"] = int(Time.get_unix_time_from_system())
	meta["play_seconds"] = play_seconds
	var p := _player_in(root) as PlayerController
	if p != null:
		meta["place"] = place_of(p)
		if p.player_name != "":
			meta["player_name"] = p.player_name
		# What you've earned and how you play (34), for the menu
		if p.story != null:
			meta["mode"] = "free_play" if p.story.mode == StoryProgress.Mode.FREE_PLAY else "story"
			meta["achievements"] = p.story.earned.keys().map(func(k: StringName) -> String: return String(k))
	if not meta.has("name"):
		meta["name"] = "Game"
	_write_meta(current_game, meta)


## Where `player` is, for a game's card: the place they're at, or the
## nearest place, or the zone.
static func place_of(player: Node3D) -> String:
	var best := ""
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group("landmarks"):
		var l := n as Landmark
		# Places have a radius; your truck, your gear and raid markers don't
		if l == null or l.display_name == "" or l.radius <= 0.0:
			continue
		var d := Vector2(l.global_position.x - player.global_position.x, l.global_position.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = l.display_name if d <= l.radius else "near " + l.display_name
	return best if best != "" else "The wastes"


## Saves from before games had folders (straight in root_dir) become a
## first game, "Your first game". Once; does nothing if there are none.
func migrate_legacy() -> String:
	var old := []
	for slot: String in [AUTO_SLOT, QUICK_SLOT]:
		var path := root_dir.path_join(slot + ".json")
		if FileAccess.file_exists(path):
			old.append(path)
	if old.is_empty():
		return ""
	var newest := 0
	for path: String in old:
		newest = maxi(newest, FileAccess.get_modified_time(path))
	var keep_dir := save_dir
	var keep_game := current_game
	var id := create_game("Your first game")
	for path: String in old:
		DirAccess.rename_absolute(path, game_dir(id).path_join(path.get_file()))
	var meta := read_save_file(game_dir(id).path_join(GAME_META))
	meta["last_played"] = newest
	meta["created"] = newest
	# Your name and where you were, from the newest save
	var data := read_save_file(game_dir(id).path_join((AUTO_SLOT if FileAccess.file_exists(game_dir(id).path_join(AUTO_SLOT + ".json")) else QUICK_SLOT) + ".json"))
	for e in data.get("nodes", []):
		if e is Dictionary and str(e.get("path", "")) == "Player" and e.get("data") is Dictionary:
			meta["player_name"] = str((e["data"] as Dictionary).get("player_name", ""))
	_write_meta(id, meta)
	current_game = keep_game
	save_dir = keep_dir
	return id


## Plays game `id` from its newest save (a game made but never saved starts
## fresh). Autosaving goes on.
func play_game(id: String) -> Error:
	use_game(id)
	_reset_world()
	autosave_enabled = true
	if latest_slot() != "" and continue_game() == OK:
		return OK
	get_tree().change_scene_to_file(ZONE_LEVEL)
	return OK


## Starts a new game called `game_name`, with you as `player_name`, in
## Story or Free Play (34: "story" or "free_play").
func start_new_game(game_name: String, player_name: String, mode := "story") -> String:
	var id := create_game(game_name, PlayerController.clean_name(player_name))
	var meta := read_save_file(game_dir(id).path_join(GAME_META))
	meta["mode"] = "free_play" if mode == "free_play" else "story"
	_write_meta(id, meta)
	_reset_world()
	autosave_enabled = true
	_pending_new_name = PlayerController.clean_name(player_name)
	_pending_mode = meta["mode"]
	get_tree().change_scene_to_file(ZONE_LEVEL)
	_begin_new_game.call_deferred()
	return id


func _begin_new_game() -> void:
	for i in 4:
		await get_tree().process_frame
	var p := _player_in(get_tree().current_scene) as PlayerController
	if p != null and _pending_new_name != "":
		p.set_player_name(_pending_new_name)
	_pending_new_name = ""
	# Story: you wake in the barracks, the manual in Vance's footlocker.
	# Free Play: every chapter open (34)
	if p != null and p.story != null:
		p.story.begin(StoryProgress.Mode.FREE_PLAY if _pending_mode == "free_play" else StoryProgress.Mode.STORY)
	_pending_mode = "story"
	# Saved straight away, so the game is in the menu's list
	if p != null:
		save_game(AUTO_SLOT)


## Back to the main menu (saving first).
func quit_to_menu() -> void:
	if autosave_enabled:
		autosave()
	autosave_enabled = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset_world() -> void:
	if _world() != null and _world().has_method("reset"):
		_world().reset()


func _world() -> Node:
	return get_node_or_null("/root/WorldManager")


func _fail(reason: String, err: Error) -> Error:
	failed.emit(reason)
	return err
