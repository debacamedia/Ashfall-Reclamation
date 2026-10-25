extends "res://tests/test_case.gd"
## ASHFALL Resource Pack 2.0 in Outpost 17: what is integrated vs only
## imported, props clear of routes and loot, signs on walls, 3D ambience,
## Pack 1 untouched, and saves made before Pack 2 still load.

const LEVEL_PATH := "res://levels/outpost_17/outpost_17.tscn"
const PACK := "res://assets/ashfall_pack_v2/"
const FIXTURE := "res://tests/fixtures/outpost_save_before_pack2.json"

## Used in Outpost 17
const INTEGRATED := [
	"scenes/water_storage_tank.tscn", "scenes/portable_generator.tscn", "scenes/field_radio.tscn", "scenes/salvage_toolbox.tscn",
	"decals/water_purification.png", "decals/radio_signal.png", "decals/checkpoint_17.png", "decals/medical_triage.png",
	"decals/danger_mines.png", "decals/bullet_holes.png", "decals/rust_streaks.png",
	"audio/power_generator_loop.wav", "audio/radio_chatter_static.wav", "audio/metal_gate_rattle.wav", "audio/distant_industry.wav",
]
## Imported into the project but not used by any scene yet
const IMPORTED_ONLY := [
	"decals/market.png", "decals/soot_marks.png", "decals/scratches.png",
	"audio/alarm_short.wav", "audio/settlement_wind.wav",
	"ui/defense.png", "ui/trade.png", "ui/faction_reputation.png", "ui/morale.png", "ui/food.png", "ui/settlement.png",
]


func _load_level() -> Node3D:
	var lvl := (load(LEVEL_PATH) as PackedScene).instantiate() as Node3D
	(lvl.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	add_child(lvl)
	await wait_physics(3)
	return lvl


## Every pack resource the level uses, directly or through a material.
func _used_by_level() -> Dictionary:
	var used := {}
	var stack: Array[String] = [LEVEL_PATH]
	var seen := {}
	while not stack.is_empty():
		var path: String = stack.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		for dep in ResourceLoader.get_dependencies(path):
			var p := dep.get_slice("::", 2) if dep.contains("::") else dep
			if p.begins_with("uid://"):
				p = ResourceUID.get_id_path(ResourceUID.text_to_id(p))
			if p.begins_with(PACK):
				used[p.trim_prefix(PACK)] = true
			if p.begins_with("res://assets/materials/signs/") or p.begins_with(PACK + "scenes/"):
				stack.append(p)
	return used


func test_all_pack_files_import() -> void:
	var count := 0
	for rel in INTEGRATED + IMPORTED_ONLY:
		check(ResourceLoader.exists(PACK + rel) and load(PACK + rel) != null, "%s loads" % rel)
		count += 1
	check(count == 26, "all 26 pack files accounted for (%d)" % count)


func test_integrated_vs_imported_only_is_accurate() -> void:
	var used := _used_by_level()
	for rel in INTEGRATED:
		check(used.has(rel), "%s is used in Outpost 17" % rel)
	for rel in IMPORTED_ONLY:
		check(not used.has(rel), "%s is imported only (not in any scene)" % rel)


func test_props_clear_on_the_floor_and_navigable() -> void:
	var lvl := await _load_level()
	var space := lvl.get_world_3d().direct_space_state
	var props := lvl.get_node("Pack2/Props")
	check(props.is_in_group("navigation_geometry"), "props are part of the navmesh bake")
	check(props.get_child_count() == 4, "4 props (%d)" % props.get_child_count())
	for p: StaticBody3D in props.get_children():
		var cs := p.get_node("Collider") as CollisionShape3D
		var box := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size -= Vector3(0.04, 0.04, 0.04)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = cs.global_transform.translated(Vector3(0, 0.03, 0))
		q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.INTERACTABLES
		q.collide_with_areas = true
		q.exclude = [p.get_rid()]
		var hits := space.intersect_shape(q, 8).filter(func(h: Dictionary) -> bool: return (h["collider"] as Node).name != "Terrain")
		check(hits.is_empty(), "%s clear of walls, props and loot (%s)" % [p.name, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))])
		check(absf(p.global_position.y) < 0.01, "%s stands on the ground" % p.name)
	# Every container and bench is still reachable on foot from the spawn
	var map := lvl.get_world_3d().navigation_map
	await wait_for_navigation(map)
	var start := (lvl.get_node("PlayerSpawn") as Node3D).global_position
	var targets: Array[Node3D] = []
	for c in lvl.get_node("SalvageContainers").get_children():
		targets.append(c)
	for b in lvl.get_node("CraftingStations").get_children():
		targets.append(b)
	for t in targets:
		var front := t.global_basis.z
		front.y = 0.0
		var goal := t.global_position + front.normalized() * 1.2
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		check(path.size() > 0 and path[path.size() - 1].distance_to(goal) < 1.0, "%s still reachable" % t.name)
	remove_child(lvl)
	lvl.free()


func test_signs_and_overlays_flat_on_walls() -> void:
	var lvl := await _load_level()
	var space := lvl.get_world_3d().direct_space_state
	var quads: Array = lvl.get_node("Pack2/Signs").get_children() + lvl.get_node("Pack2/Overlays").get_children()
	check(lvl.get_node("Pack2/Signs").get_child_count() == 5 and lvl.get_node("Pack2/Overlays").get_child_count() == 2, "5 signs, 2 overlays")
	for s: MeshInstance3D in quads:
		check(s.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s has no collision" % s.name)
		var size := (s.mesh as QuadMesh).size
		var facing := s.global_basis.z.normalized()
		# All four corners and the centre have wall right behind them: not
		# floating, not hanging over an edge or a doorway
		for corner in [Vector2.ZERO, Vector2(-0.48, -0.48), Vector2(0.48, -0.48), Vector2(-0.48, 0.48), Vector2(0.48, 0.48)]:
			var at := s.global_transform * Vector3(corner.x * size.x, corner.y * size.y, 0.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + facing * 0.05, at - facing * 0.05, PhysicsLayers.WORLD_SOLID))
			check(not hit.is_empty() and at.distance_to(hit["position"]) < 0.02, "%s: wall behind %s" % [s.name, corner])
	# No two signs or overlays overlap (Pack 1 or Pack 2)
	var all: Array = quads + lvl.get_node("Signage").get_children()
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a := all[i] as MeshInstance3D
			var b := all[j] as MeshInstance3D
			var box_a := a.global_transform * a.get_aabb()
			var box_b := b.global_transform * b.get_aabb()
			check(not box_a.abs().grow(0.003).intersects(box_b.abs().grow(0.003)), "%s doesn't overlap %s" % [a.name, b.name])
	remove_child(lvl)
	lvl.free()


func test_ambience_is_3d_and_loops() -> void:
	var lvl := await _load_level()
	var s := lvl.get_node("Pack2/Sounds")
	for name in ["WaterPumpHum", "DistantIndustry"]:
		var p := s.get_node(name) as AudioStreamPlayer3D
		check(p != null and p.autoplay and (p.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s: 3D, looping" % name)
	for name in ["RadioChatter", "GateRattle"]:
		var e := s.get_node(name) as RandomSoundEmitter
		check(e != null and e.stream != null and not e.autoplay, "%s: 3D, plays now and then" % name)
	var hum := s.get_node("WaterPumpHum") as AudioStreamPlayer3D
	check(hum.global_position.distance_to((lvl.get_node("Pack2/Props/WaterPumpGenerator") as Node3D).global_position) < 1.0, "hum comes from the generator")
	var chatter := s.get_node("RadioChatter") as Node3D
	check(chatter.global_position.distance_to((lvl.get_node("Pack2/Props/FieldRadio") as Node3D).global_position) < 1.0, "chatter comes from the radio")
	# Pack 1 is untouched
	check(lvl.get_node("Signage").get_child_count() == 4 and lvl.get_node("Soundscape").get_child_count() == 4, "Pack 1 signs and sounds still there")
	remove_child(lvl)
	lvl.free()


func test_saves_from_before_pack2_still_load() -> void:
	var saves := get_node("/root/SaveManager")
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	var json := JSON.new()
	check(json.parse(f.get_as_text()) == OK, "fixture parses")
	var data: Dictionary = json.data
	check(saves.validate(data) == "", "save made before Pack 2 is valid")
	var lvl := await _load_level()
	# Pack 2 adds nothing to the save: same persist nodes as before
	var now: Dictionary = saves.build_save_data(lvl)
	var before_paths := (data["nodes"] as Array).map(func(e: Dictionary) -> String: return str(e["path"]))
	var now_paths := (now["nodes"] as Array).map(func(e: Dictionary) -> String: return str(e["path"]))
	check(now_paths.filter(func(p: String) -> bool: return p.begins_with("Pack2")).is_empty(), "no Pack 2 node is saved")
	for p in before_paths:
		check(now_paths.has(p), "%s still exists to load into" % p)
	saves.apply_save_data(data, lvl)
	await wait_physics(2)
	var player := lvl.get_node("Player") as Node3D
	check(player.global_position.distance_to(Vector3(-24.0, 0.05, -15.0)) < 0.3, "player position restored")
	var crate := lvl.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	check(crate.is_searched, "searched crate restored")
	check(lvl.get_node("Loot").get_child_count() == before_paths.filter(func(p: String) -> bool: return p.begins_with("Loot/")).size(), "taken pickup stays gone")
	remove_child(lvl)
	lvl.free()
