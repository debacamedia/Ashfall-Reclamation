extends Node
## Regions and travel between them.
##
## Autoload "WorldManager" (Project Settings → Globals). Each region is its own
## level scene: since Increment 15 a whole zone (the early zone holds Outpost
## 17, Halden's Crossing and five more places; the mid and late zones come
## later). Hold E on a RegionExit at a zone's edge to travel: this region's
## state is kept, the next level opens, and
## the player arrives at the matching arrival marker with their health,
## inventory and loadout.
##
## REGION STATE: when you leave a region, everything in its "persist" group
## except players (containers searched and their contents, pickups taken or
## dropped, salvage piles broken down) is captured in memory with the same
## format SaveManager uses, and re-applied when you come back. SaveManager
## writes the other regions' state into the save file ("regions") so a save
## made in Halden's Crossing still remembers what you looted at the outpost.
##
## Raiders aren't saved: spawners repopulate a region when you return.
##
## AUTHORITY: travel is decided here (host-side in co-op). RegionExit only
## asks; request_travel() validates the player and the exit.
##
## Testable without changing scenes: capture_region(root) and
## enter_region(root, player_data, arrival_id) do the work on any level root.

signal travel_started(destination_name: String)
## The player is in the new region (after state was applied).
signal arrived(region_name: String)
signal travel_refused(reason: String)

## Raiders chasing you this close stop you leaving.
const PURSUIT_DISTANCE := 25.0
const FADE_TIME := 0.45

## level path -> {"nodes": [...]} (SaveManager node entries, players excluded)
var region_states: Dictionary = {}
var is_travelling := false

var _overlay: CanvasLayer
var _fade: ColorRect
var _fade_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	add_child(_overlay)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)
	_fade_label = Label.new()
	_fade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_size_override("font_size", 30)
	_fade_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	_fade_label.modulate.a = 0.0
	_overlay.add_child(_fade_label)


## Forgets every region (a new game).
func reset() -> void:
	region_states.clear()


## Display name of a level root ("Outpost 17"), from its `region_name` meta
## or its node name.
static func region_name_of(root: Node) -> String:
	if root == null:
		return ""
	if root.has_meta("region_name"):
		return str(root.get_meta("region_name"))
	return str(root.name).capitalize()


# ---------------------------------------------------------------- travel

## Why `player` can't use `exit` right now ("" = they can).
func travel_refusal_reason(player: PlayerController, exit: RegionExit) -> String:
	if is_travelling:
		return "Already travelling"
	if player == null or player.is_dead():
		return "Can't travel now"
	if exit == null or exit.target_level == "" or not ResourceLoader.exists(exit.target_level):
		return "The road is blocked"
	if player.is_crafting():
		return "Finish crafting first"
	for n in player.get_tree().get_nodes_in_group("enemies"):
		var r := n as Raider
		if r != null and not r.is_dead() and r.target == player \
				and (r.state == Raider.State.CHASE or r.state == Raider.State.ATTACK) \
				and r.global_position.distance_to(player.global_position) < PURSUIT_DISTANCE:
			return "Raiders are on your tail"
	return ""


## Validated travel: fade out, keep this region, open the next, fade in.
func request_travel(player: PlayerController, exit: RegionExit) -> bool:
	var reason := travel_refusal_reason(player, exit)
	if reason != "":
		travel_refused.emit(reason)
		return false
	_travel(player, exit.target_level, exit.arrival_id, exit.destination_name)
	return true


func _travel(player: PlayerController, level: String, arrival_id: StringName, destination: String) -> void:
	is_travelling = true
	travel_started.emit(destination)
	player.player_input.set_ui_open(true)  # freeze input during the fade
	_fade_label.text = "Following the road to %s…" % destination
	await _fade_to(1.0)
	var tree := get_tree()
	var player_data := capture_region(tree.current_scene)
	tree.change_scene_to_file(level)
	for i in 3:
		await tree.process_frame
	var root := tree.current_scene
	var p: PlayerController = null
	if root != null:
		enter_region(root, player_data, arrival_id)
		p = find_player(root)
		if p != null:
			p.player_input.set_ui_open(true)
		_fade_label.text = region_name_of(root).to_upper()
		await tree.create_timer(0.7).timeout
	await _fade_to(0.0)
	is_travelling = false
	if p != null and is_instance_valid(p):
		p.player_input.set_ui_open(false)
		p.player_input.capture_mouse()
	if root != null:
		arrived.emit(region_name_of(root))


func _fade_to(alpha: float) -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_fade, "color:a", alpha, FADE_TIME)
	t.tween_property(_fade_label, "modulate:a", alpha, FADE_TIME)
	await t.finished


# ---------------------------------------------------------------- region state

## Stores the state of the region under `root` and returns the player's own
## data to carry to the next region.
func capture_region(root: Node) -> Dictionary:
	if root == null:
		return {}
	var data: Dictionary = _saves().build_save_data(root)
	var player_data := {}
	var nodes := []
	for e: Dictionary in data["nodes"]:
		var n := root.get_node_or_null(NodePath(str(e["path"])))
		if n is PlayerController:
			if player_data.is_empty():
				player_data = e["data"]
		else:
			nodes.append(e)
	region_states[root.scene_file_path] = {"nodes": nodes}
	return player_data


## Applies a remembered region state (if any) to a freshly opened level, then
## puts the player at the arrival marker with their carried data.
func enter_region(root: Node, player_data: Dictionary, arrival_id: StringName) -> void:
	var state: Variant = region_states.get(root.scene_file_path)
	if state is Dictionary and (state as Dictionary).get("nodes") is Array:
		_saves().apply_save_data(state, root)
	var player := find_player(root)
	if player == null:
		return
	var data := player_data.duplicate(true)
	var marker := find_arrival(root, arrival_id)
	if marker != null:
		var p := marker.global_position
		data["position"] = [p.x, p.y, p.z]
		data["yaw"] = marker.global_rotation.y
		data["pitch"] = 0.0
	if not data.is_empty():
		player.load_state(data)
	elif marker != null:
		player.respawn_at(marker.global_transform)


## State of every region except `current_level`, for the save file.
func get_saved_regions(current_level: String) -> Dictionary:
	var out := {}
	for level in region_states:
		if level != current_level:
			out[level] = region_states[level]
	return out


## Replaces the remembered regions with those from a save (validated).
func set_saved_regions(regions: Variant, current_level: String) -> void:
	region_states.clear()
	if not regions is Dictionary:
		return
	for level in regions:
		var s: Variant = regions[level]
		if level is String and level != current_level and (level as String).begins_with("res://") \
				and s is Dictionary and (s as Dictionary).get("nodes") is Array:
			region_states[level] = {"nodes": (s as Dictionary)["nodes"]}


## The SaveManager autoload (looked up at runtime, the project's convention).
func _saves() -> Node:
	return get_node("/root/SaveManager")


static func find_player(root: Node) -> PlayerController:
	for p in root.get_tree().get_nodes_in_group("players") if root.is_inside_tree() else []:
		if root.is_ancestor_of(p):
			return p as PlayerController
	return root.get_node_or_null("Player") as PlayerController


## The Marker3D players arrive at: a RegionArrival child of "Arrivals" whose
## name is `arrival_id`, else the level's PlayerSpawn.
static func find_arrival(root: Node, arrival_id: StringName) -> Node3D:
	if arrival_id != &"":
		var m := root.get_node_or_null(NodePath("Arrivals/" + String(arrival_id))) as Node3D
		if m != null:
			return m
	return root.get_node_or_null("PlayerSpawn") as Node3D
