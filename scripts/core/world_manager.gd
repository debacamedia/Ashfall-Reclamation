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
##
## ZONES (Increment 25): the early and mid zones are both levels. A
## ZoneExit (a road through the storm) travels when you cross the edge
## there, so you can drive out:
##   - YOUR TRUCK comes with you: if you're driving, the truck and its cargo
##     are left out of the zone you leave, brought into the next one at the
##     arrival marker (still moving), and you're back at the wheel.
##     vehicle_zones remembers which zone each vehicle is in (saved), so a
##     zone that has one in its scene drops it while it's elsewhere.
##   - YOUR SETTLEMENTS KEEP RUNNING: time spent away from a zone is counted
##     (away_seconds, saved with the zone's state) and, when you come back,
##     its settlements catch up hour by hour (food, jobs, the supply line,
##     raids settled at the same odds as when you're away in the zone), then
##     you get a summary.

signal travel_started(destination_name: String)
## The player is in the new region (after state was applied).
signal arrived(region_name: String)
signal travel_refused(reason: String)
## Settlements caught up after you were away from their zone: what happened.
signal caught_up(summary: String)

## Raiders chasing you this close stop you leaving.
const PURSUIT_DISTANCE := 25.0
const FADE_TIME := 0.45

## Catching up settlements stops at this many hours (a week).
const MAX_CATCH_UP_HOURS := 168.0

## level path -> {"nodes": [...], "away_seconds": float} (SaveManager node
## entries, players excluded; how long you've been gone from it)
var region_states: Dictionary = {}
var is_travelling := false
## Vehicle name -> the level it's in, for vehicles that have left the zone
## their scene puts them in (Increment 25).
var vehicle_zones: Dictionary = {}
## The vehicle being driven to the next zone, while travelling:
## [{"path": "" or a path under it, "scene", "data"}, …] ("" is the vehicle).
var carried_vehicle: Array = []
var _carried_name := ""
var _carried_speed := 0.0
## What the last catch-up did (read by tests): place name -> hours.
var last_catch_up := {}

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
	vehicle_zones.clear()
	carried_vehicle.clear()


## Counts time away from every zone you're not in (not while paused or
## travelling).
func _process(delta: float) -> void:
	if is_travelling or get_tree().paused:
		return
	for level in region_states:
		var st: Dictionary = region_states[level]
		st["away_seconds"] = float(st.get("away_seconds", 0.0)) + delta


## Display name of a level root ("Outpost 17"), from its `region_name` meta
## or its node name.
static func region_name_of(root: Node) -> String:
	if root == null:
		return ""
	if root.has_meta("region_name"):
		return str(root.get_meta("region_name"))
	return str(root.name).capitalize()


# ---------------------------------------------------------------- travel

## Why `player` can't use `exit` (a RegionExit or ZoneExit) right now ("" = they can).
func travel_refusal_reason(player: PlayerController, exit: Node) -> String:
	if is_travelling:
		return "Already travelling"
	if player == null or player.is_dead():
		return "Can't travel now"
	if exit == null or str(exit.get("target_level")) == "" or not ResourceLoader.exists(str(exit.get("target_level"))):
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
func request_travel(player: PlayerController, exit: Node) -> bool:
	var reason := travel_refusal_reason(player, exit)
	if reason != "":
		travel_refused.emit(reason)
		return false
	_travel(player, str(exit.get("target_level")), exit.get("arrival_id"), str(exit.get("destination_name")))
	return true


func _travel(player: PlayerController, level: String, arrival_id: StringName, destination: String) -> void:
	is_travelling = true
	travel_started.emit(destination)
	player.player_input.set_ui_open(true)  # freeze input during the fade
	_fade_label.text = "Following the road to %s…" % destination
	await _fade_to(1.0)
	var tree := get_tree()
	var player_data := capture_region(tree.current_scene, player.vehicle if is_instance_valid(player) else null, level)
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
## data to carry to the next region. `carry` (the truck you're driving) is
## left out and taken along to `to_level`, in carried_vehicle.
func capture_region(root: Node, carry: Node3D = null, to_level := "") -> Dictionary:
	if root == null:
		return {}
	var data: Dictionary = _saves().build_save_data(root)
	var player_data := {}
	var nodes := []
	carried_vehicle.clear()
	_carried_name = ""
	if carry != null and is_instance_valid(carry) and root.is_ancestor_of(carry):
		_carried_name = str(carry.name)
		_carried_speed = (carry as Truck).forward_speed() if carry is Truck else 0.0
		vehicle_zones[_carried_name] = to_level
	for e: Dictionary in data["nodes"]:
		var n := root.get_node_or_null(NodePath(str(e["path"])))
		if n is PlayerController:
			if player_data.is_empty():
				player_data = e["data"]
		elif _carried_name != "" and n != null and (n == carry or carry.is_ancestor_of(n)):
			carried_vehicle.append({"path": str(carry.get_path_to(n)) if n != carry else "",
				"scene": e.get("scene", ""), "data": e["data"]})
		else:
			nodes.append(e)
	region_states[root.scene_file_path] = {"nodes": nodes, "away_seconds": 0.0}
	return player_data


## Applies a remembered region state (if any) to a freshly opened level, then
## puts the player at the arrival marker with their carried data (and at the
## wheel of the truck they drove here), and lets the zone's settlements
## catch up on the time you were away.
func enter_region(root: Node, player_data: Dictionary, arrival_id: StringName) -> void:
	var state: Variant = region_states.get(root.scene_file_path)
	var away := 0.0
	if state is Dictionary and (state as Dictionary).get("nodes") is Array:
		_saves().apply_save_data(state, root)
		away = float((state as Dictionary).get("away_seconds", 0.0))
	region_states.erase(root.scene_file_path)  # you're here now: nothing's remembered
	settle_vehicles(root)
	var player := find_player(root)
	_arrive(root, player, player_data, arrival_id)
	if away > 0.0:
		catch_up(root, away)


func _arrive(root: Node, player: PlayerController, player_data: Dictionary, arrival_id: StringName) -> void:
	if player == null:
		_bring_vehicle(root, null, find_arrival(root, arrival_id))
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
	_bring_vehicle(root, player, marker)


# ---------------------------------------------------------------- vehicles

## The zone a vehicle is in: where it was driven last, else the level whose
## scene it's part of.
func vehicle_zone(vehicle_name: String, default_level: String) -> String:
	return str(vehicle_zones.get(vehicle_name, default_level))


## A few words on what a settlement's new log entries say happened:
## "raided; 2 left; 1 arrived" ("quiet" if nothing).
static func describe_news(entries: Array) -> String:
	var raids := 0
	var left := 0
	var died := 0
	var came := 0
	for e in entries:
		var t := str((e as Dictionary).get("text", "")) if e is Dictionary else ""
		if t.contains("raiders hit") or t.begins_with("Raid over"):
			raids += 1
		elif t.contains(" has left "):
			left += 1
		elif t.contains("died"):
			died += 1
		elif t.contains("has arrived"):
			came += 1
	var out: Array[String] = []
	if raids > 0:
		out.append("raided" if raids == 1 else "raided %d times" % raids)
	if died > 0:
		out.append("%d died" % died)
	if left > 0:
		out.append("%d left" % left)
	if came > 0:
		out.append("%d arrived" % came)
	if out.is_empty():
		return "%d %s" % [entries.size(), "thing" if entries.size() == 1 else "things"] if not entries.is_empty() else "quiet"
	return ", ".join(out)


## Takes out of `root` any vehicle that's in another zone now.
func settle_vehicles(root: Node) -> void:
	if root == null or not root.is_inside_tree():
		return
	for v in root.get_tree().get_nodes_in_group("vehicles"):
		var n := v as Node
		if not root.is_ancestor_of(n):
			continue
		if vehicle_zone(str(n.name), root.scene_file_path) != root.scene_file_path or str(n.name) == _carried_name:
			n.remove_from_group("vehicles")
			n.remove_from_group("persist")
			n.get_parent().remove_child(n)
			n.queue_free()


## Brings the vehicle you drove here into `root` at the arrival (still
## moving) and puts `player` at the wheel.
func _bring_vehicle(root: Node, player: PlayerController, marker: Node3D) -> void:
	if _carried_name == "" or carried_vehicle.is_empty():
		_carried_name = ""
		carried_vehicle.clear()
		return
	var main: Dictionary = carried_vehicle[0]
	for e: Dictionary in carried_vehicle:
		if str(e["path"]) == "":
			main = e
	var parent := root.get_node_or_null("Vehicles")
	if parent == null:
		parent = root
	var scene := load(str(main.get("scene", ""))) as PackedScene if ResourceLoader.exists(str(main.get("scene", ""))) else null
	var vehicle_name := _carried_name
	_carried_name = ""
	if scene == null:
		carried_vehicle.clear()
		return
	var v := scene.instantiate() as Node3D
	v.name = vehicle_name
	parent.add_child(v)
	for e: Dictionary in carried_vehicle:
		var n := v if str(e["path"]) == "" else v.get_node_or_null(NodePath(str(e["path"])))
		if n != null and n.has_method("load_state") and e.get("data") is Dictionary:
			n.call("load_state", e["data"])
	carried_vehicle.clear()
	vehicle_zones[vehicle_name] = root.scene_file_path
	if marker != null:
		# A truck's nose is its +Z: turn it to face the way the marker looks
		var at := marker.global_position + Vector3.UP * 0.4
		v.global_transform = Transform3D(Basis(Vector3.UP, marker.global_rotation.y + PI), at)
		if v is RigidBody3D:
			(v as RigidBody3D).linear_velocity = v.global_basis * Vector3(0, 0, 1) * maxf(_carried_speed, 0.0)
	if player != null and v is Truck:
		player.enter_vehicle(v as Truck)


## vehicle_zones from a save (validated), then settles `root`'s vehicles.
func set_vehicle_zones(zones: Variant, root: Node) -> void:
	vehicle_zones.clear()
	if zones is Dictionary:
		for k in zones:
			var level: Variant = zones[k]
			if k is String and level is String and (level as String).begins_with("res://"):
				vehicle_zones[k] = level
	settle_vehicles(root)


# ---------------------------------------------------------------- settlements while away

## Runs the settlements under `root` through `seconds` of play you spent in
## another zone, an hour at a time, quietly, then sends a summary.
func catch_up(root: Node, seconds: float) -> void:
	last_catch_up.clear()
	if root == null or not root.is_inside_tree() or seconds <= 0.0:
		return
	var parts: Array[String] = []
	var longest := 0.0
	for n in root.get_tree().get_nodes_in_group("settlements"):
		var st := n as Settlement
		if st == null or not root.is_ancestor_of(st) or not st.is_claimed:
			continue
		var hours := minf(seconds / maxf(st.hour_seconds, 0.001), MAX_CATCH_UP_HOURS)
		longest = maxf(longest, hours)
		var logged := st.log_entries.size()
		st.catching_up = true
		var left := hours
		while left > 0.0:
			var step := minf(left, 1.0)
			st.simulate(step)
			left -= step
		st.catching_up = false
		last_catch_up[st.settlement_name] = hours
		parts.append("%s: %s" % [st.settlement_name, describe_news(st.log_entries.slice(logged))])
	if parts.is_empty():
		return
	var mins := roundi(seconds / 60.0)
	var summary := "Back in the %s after %s. While you were gone: %s (L for each place's log)" % [
		region_name_of(root), "%d min" % mins if mins < 120 else "%.1f hours" % (seconds / 3600.0), "; ".join(parts)]
	caught_up.emit(summary)


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
			var away: Variant = (s as Dictionary).get("away_seconds", 0.0)
			region_states[level] = {"nodes": (s as Dictionary)["nodes"],
				"away_seconds": maxf(float(away), 0.0) if (away is float or away is int) and is_finite(float(away)) else 0.0}


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
