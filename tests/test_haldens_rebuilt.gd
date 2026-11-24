extends "res://tests/test_case.gd"
## Increment 31: Halden's Crossing rebuilt from Quaternius's Downtown City
## MegaKit (CC0). Same town, same footprints, doors, floors and roofs, same
## loot; new walls of brick, stone and steel, with open windows, shopfronts,
## corner columns, cornices and broken tops on the ruins.

const LEVEL := "res://levels/haldens_crossing/haldens_crossing.tscn"
const KIT := "res://assets/models/quaternius/city/"
const T := 0.3

var _lvl: Node3D


func _buildings() -> Array:
	return (load("res://tools/rebuild_haldens.gd") as GDScript).get_script_constant_map()["BUILDINGS"]


func _height(spec: Dictionary) -> float:
	return spec.get("height", spec.get("floors", 1) * 3.3)


func _ruined(spec: Dictionary) -> bool:
	return spec.get("ruin", 0.0) > 0.0 and spec.get("roof", "full") != "full"


func _load() -> Node3D:
	_lvl = (load(LEVEL) as PackedScene).instantiate() as Node3D
	for sp in _lvl.find_children("*", "EnemySpawner", true, false):
		(sp as EnemySpawner).enabled = false
	add_child(_lvl)
	await wait_physics(4)
	return _lvl


func _unload() -> void:
	remove_child(_lvl)
	_lvl.free()
	await wait_physics(2)


## Solid wall boxes of a building (building space)
func _wall_boxes(b: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for c in b.get_children():
		if c is CollisionShape3D and c.name.begins_with("Wall"):
			var bx := ((c as CollisionShape3D).shape as BoxShape3D).size
			out.append((c as CollisionShape3D).transform * AABB(-bx / 2.0, bx))
	return out


## A wall's ray from outside to inside, at `along` (from the wall's middle,
## like the doors' offsets) and `y`: what it hits of the building
func _through(b: StaticBody3D, spec: Dictionary, side: String, along: float, y: float) -> bool:
	var w: float = spec["w"]
	var d: float = spec["d"]
	var o: Vector3 = {"n": Vector3.FORWARD, "s": Vector3.BACK, "w": Vector3.LEFT, "e": Vector3.RIGHT}[side]
	var axis := Vector3.RIGHT if side in ["n", "s"] else Vector3.BACK
	var half := d / 2.0 if side in ["n", "s"] else w / 2.0
	var outside := b.global_transform * (o * (half + 0.6) + axis * along + Vector3.UP * y)
	var inside := b.global_transform * (o * (half - 0.9) + axis * along + Vector3.UP * y)
	var q := PhysicsRayQueryParameters3D.create(outside, inside, PhysicsLayers.STRUCTURES)
	# (Past anything else in the way: rubble, a car)
	for i in 4:
		var hit := b.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit["collider"] == b:
			return false
		q.exclude = q.exclude + [hit["rid"]]
	return true


func test_the_kit_and_its_licence() -> void:
	check(FileAccess.get_file_as_string(KIT + "LICENSE_Downtown_City_MegaKit.txt").contains("CC0"), "the city kit: CC0 (free in a game that's sold)")
	var register := FileAccess.get_file_as_string("res://docs/ASSET_LICENSES.md")
	check(register.contains("Downtown City MegaKit"), "in the asset licence register")
	var lvl := (load(LEVEL) as PackedScene).instantiate() as Node3D
	for spec: Dictionary in _buildings():
		var b := lvl.get_node("Buildings/" + spec["name"]) as Node3D
		var kit := b.get_node_or_null("Kit")
		check(kit != null and kit.get_meta("shell", false), "%s: walls built from the kit" % spec["name"])
		var pieces := 0
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			var path := mi.mesh.resource_path
			if path.begins_with(KIT + "built/") or path.begins_with("res://levels/haldens_crossing/kit/"):
				pieces += 1
			check(not (mi.name.begins_with("Wall") and mi.mesh is BoxMesh), "%s: no old box wall left (%s)" % [spec["name"], mi.name])
		# (A ruin's broken walls are one mesh)
		check(pieces >= (1 if _ruined(spec) else 8), "%s: %d kit pieces" % [spec["name"], pieces])
		check(b.has_node("Kit/BrokenWalls") == _ruined(spec), "%s: broken walls if it's a ruin" % spec["name"])
	# The kit's own colours and textures, weathered, not darkened to black;
	# no glass left in the windows
	var brick := load(KIT + "built/materials/mi_red_brick.tres") as StandardMaterial3D
	check(brick.albedo_texture != null and brick.normal_texture != null and brick.albedo_color.get_luminance() > 0.6, "the kit's brick, textured")
	var window := load(KIT + "built/brick_window_trim.res") as ArrayMesh
	var glass := false
	for s in window.get_surface_count():
		glass = glass or window.surface_get_material(s).resource_name in ["MI_Glass", "MI_FakeInterior"]
	check(not glass, "windows without their glass")
	lvl.free()


func test_walls_where_they_were() -> void:
	var lvl := await _load()
	var space := lvl.get_world_3d().direct_space_state
	for spec: Dictionary in _buildings():
		var b := lvl.get_node("Buildings/" + spec["name"]) as StaticBody3D
		var boxes := _wall_boxes(b)
		var all := boxes[0]
		for a in boxes:
			all = all.merge(a)
		var h := _height(spec)
		check(absf(all.size.x - float(spec["w"])) < 0.05 and absf(all.size.z - float(spec["d"])) < 0.05,
			"%s: the same footprint, %s x %s (%s)" % [spec["name"], spec["w"], spec["d"], all.size])
		check(all.position.y > -0.01 and all.end.y < h + 0.05 and all.end.y > h - 0.3, "%s: as tall as before (%.2f)" % [spec["name"], all.end.y])
		# 0.3 m walls: the room inside's as big as it was
		for a in boxes:
			var inward := minf(minf(a.position.x + spec["w"] / 2.0, spec["w"] / 2.0 - a.end.x), minf(a.position.z + spec["d"] / 2.0, spec["d"] / 2.0 - a.end.z))
			if a.size.x < T + 0.01 or a.size.z < T + 0.01:
				check(inward < 0.01, "%s: a wall box in the walls' line" % spec["name"])
		var q := PhysicsShapeQueryParameters3D.new()
		var room := BoxShape3D.new()
		room.size = Vector3(spec["w"] - 2 * T - 0.1, 1.2, spec["d"] - 2 * T - 0.1)
		q.shape = room
		q.transform = b.global_transform * Transform3D(Basis(), Vector3(0, 1.0, 0))
		q.collision_mask = PhysicsLayers.STRUCTURES
		var in_room := space.intersect_shape(q, 64).filter(func(r: Dictionary) -> bool:
			var owner_id := b.shape_find_owner(r["shape"]) if r["collider"] == b else -1
			return r["collider"] == b and owner_id >= 0 and str((b.shape_owner_get_owner(owner_id) as Node).name).begins_with("Wall"))
		check(in_room.is_empty(), "%s: no wall standing in the room" % spec["name"])
	await _unload()


func test_doors_open_windows_low_shut() -> void:
	var lvl := await _load()
	for spec: Dictionary in _buildings():
		var b := lvl.get_node("Buildings/" + spec["name"]) as StaticBody3D
		var doors: Dictionary = spec.get("doors", {})
		var seen := false
		for side in ["n", "e", "s", "w"]:
			var length: float = spec["w"] if side in ["n", "s"] else spec["d"]
			var spans := []
			for dd: Array in doors.get(side, []):
				spans.append(dd)
				# Through the doorway at waist and head height, either side of the middle
				for at in [-0.3, 0.0, 0.3]:
					for y in [0.5, 1.7]:
						check(_through(b, spec, side, dd[0] + at * minf(1.0, dd[1] / 1.3), y), "%s: the %s door's open (%.1f, %.1f m up)" % [spec["name"], side, at, y])
			var x := -length / 2.0 + 0.6
			while x < length / 2.0 - 0.6:
				var by_door := spans.any(func(dd: Array) -> bool: return absf(x - dd[0]) < dd[1] / 2.0 + 1.2)
				if not by_door:
					# Low down the walls are solid (windows are boarded below 1 m)
					check(not _through(b, spec, side, x, 0.5), "%s: %s wall solid at waist height (%.1f)" % [spec["name"], side, x])
					seen = seen or _through(b, spec, side, x, 1.7)
				x += 0.25
		check(seen, "%s: windows you can see through" % spec["name"])
	await _unload()


func test_broken_tops_are_jagged() -> void:
	var lvl := await _load()
	var space := lvl.get_world_3d().direct_space_state
	for spec: Dictionary in _buildings():
		if not _ruined(spec):
			continue
		var b := lvl.get_node("Buildings/" + spec["name"]) as StaticBody3D
		var h := _height(spec)
		var ruin: float = spec["ruin"]
		var tops := {}
		var lowest := INF
		var w: float = spec["w"]
		var d: float = spec["d"]
		# Down onto the south and east walls' tops from above
		for side in ["s", "e"]:
			var length := w if side == "s" else d
			var x := -length / 2.0 + 0.8
			while x < length / 2.0 - 0.8:
				var local := Vector3(x, h + 1.0, d / 2.0 - T / 2.0) if side == "s" else Vector3(w / 2.0 - T / 2.0, h + 1.0, x)
				var from := b.global_transform * local
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, PhysicsLayers.STRUCTURES))
				if not hit.is_empty() and hit["collider"] == b:
					var top := (hit["position"] as Vector3).y - b.global_position.y
					if top > 2.4:
						tops[snappedf(top, 0.1)] = true
						lowest = minf(lowest, top)
				x += 0.3
		check(tops.size() >= 4, "%s: a broken, uneven top (%d heights)" % [spec["name"], tops.size()])
		check(lowest > h - ruin - 0.2, "%s: no lower than it was broken before (%.2f)" % [spec["name"], lowest])
	await _unload()


func test_walls_cast_shadows_and_stay_in_view() -> void:
	var lvl := await _load()
	StaticBatcher._mark_interiors(lvl, StaticBatcher.building_shells(lvl), StaticBatcher.Stats.new())
	var walls := 0
	var bad := []
	for spec: Dictionary in _buildings():
		for mi: MeshInstance3D in lvl.get_node("Buildings/%s/Kit" % spec["name"]).get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D):
			walls += 1
			if mi.has_meta("interior") or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or mi.visibility_range_end > 0.0:
				bad.append("%s/%s" % [spec["name"], mi.name])
	check(walls > 200 and bad.is_empty(), "the walls (%d) aren't treated as things inside: drawn from afar, casting shadows (%s)" % [walls, bad.slice(0, 4)])
	# What is inside still is
	var counter := lvl.find_child("StoreCounter", true, false) as GeometryInstance3D
	check(counter != null and counter.has_meta("interior"), "the store's counter is still inside")
	await _unload()


func test_loot_clear_of_the_walls_and_nothing_new_saved() -> void:
	var lvl := await _load()
	var buildings := lvl.get_node("Buildings")
	var stuck := []
	var containers := lvl.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is ContainerProp)
	check(containers.size() >= 10, "the town's containers (%d)" % containers.size())
	for c in containers:
		var p := (c as Node3D).global_position
		for spec: Dictionary in _buildings():
			var b := buildings.get_node(spec["name"]) as Node3D
			for a in _wall_boxes(b):
				var g := a.grow(-0.05)
				if g.size.x > 0.0 and g.size.y > 0.0 and g.size.z > 0.0 and g.has_point(b.global_transform.affine_inverse() * (p + Vector3.UP * 0.3)):
					stuck.append(c.name)
	check(stuck.is_empty(), "no container stands in a wall (%s)" % [stuck])
	var data: Dictionary = get_node("/root/SaveManager").build_save_data(lvl)
	check((data["nodes"] as Array).all(func(e: Dictionary) -> bool: return not str(e["path"]).contains("/Kit")), "the new walls aren't saved")
	await _unload()


func test_raiders_can_walk_in() -> void:
	var zone := await load_zone()
	var map := zone.get_world_3d().navigation_map
	var town := zone.get_node("HaldensCrossing") as Node3D
	for spec: Dictionary in _buildings():
		var b := town.get_node("Buildings/" + spec["name"]) as Node3D
		for side: String in (spec.get("doors", {}) as Dictionary):
			var dd: Array = spec["doors"][side][0]
			var o: Vector3 = {"n": Vector3.FORWARD, "s": Vector3.BACK, "w": Vector3.LEFT, "e": Vector3.RIGHT}[side]
			var axis := Vector3.RIGHT if side in ["n", "s"] else Vector3.BACK
			var half: float = spec["d"] / 2.0 if side in ["n", "s"] else spec["w"] / 2.0
			var outside := b.global_transform * (o * (half + 3.0) + axis * float(dd[0]))
			var inside := b.global_transform * (o * (half - 2.0) + axis * float(dd[0]))
			var path := NavigationServer3D.map_get_path(map, outside, inside, true)
			check(not path.is_empty() and path[-1].distance_to(inside) < 1.0, "%s: a way in through the %s door" % [spec["name"], side])
	remove_child(zone)
	zone.free()
	await wait_physics(2)
