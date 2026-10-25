extends "res://tests/test_case.gd"
## Increment 13: construction. Kits and recipes, placement rules (every
## refusal), placing / repairing / dismantling, gates, storage crates, spike
## traps, navmesh rebakes, raiders breaking through, saving (per region) and
## build mode's ghost and HUD panel.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAIDER := preload("res://scenes/enemies/raider.tscn")
const OUTPOST_PATH := "res://levels/outpost_17/outpost_17.tscn"
const DT := 1.0 / 60.0
const IDS := ["sandbag_barricade", "wooden_barricade", "wooden_wall", "metal_wall",
	"wooden_gate", "spike_trap", "storage_crate", "field_workbench"]
const AT_BENCH := ["wooden_wall", "metal_wall", "wooden_gate", "storage_crate"]

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")

var structures: Node3D


func _kit(id: String) -> ItemDefinition:
	return load("res://resources/items/kits/%s_kit.tres" % id)


## A flat 40 m floor in a "Navigation" region that bakes like the real
## levels (navigation_geometry group), plus a Structures node.
func _world(bake := false) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = PhysicsLayers.WORLD_SOLID
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navigation_geometry"
	nm.agent_radius = 0.25
	nm.agent_height = 1.75
	region.navigation_mesh = nm
	add_child(region)
	var fl := make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	fl.add_to_group("navigation_geometry")
	structures = Node3D.new()
	structures.name = "Structures"
	structures.add_to_group("navigation_geometry")
	add_child(structures)
	if bake:
		region.bake_navigation_mesh(false)
		await wait_for_navigation(region.get_world_3d().navigation_map)
	return region


func _player(at := Vector3(0, 0.05, 0)) -> PlayerController:
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = at
	add_child(p)
	return p


func _run(p: PlayerController, ticks: int) -> void:
	var f := InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		if is_instance_valid(p):
			p.simulate(f, DT)


func _look_at(p: PlayerController, point: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


## Builds a structure directly (no rules), as a placed one would be.
func _build(id: String, at: Vector3, yaw_deg := 0.0, parent: Node = null) -> Structure:
	var def: StructureDefinition = load("res://resources/structures/%s.tres" % id)
	var s := (load(def.scene_path) as PackedScene).instantiate() as Structure
	s.name = "%s_%d" % [id, Time.get_ticks_usec() % 100000000]
	s.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at)
	(parent if parent != null else structures).add_child(s)
	return s


func _rebaker(region: NavigationRegion3D) -> NavRebaker:
	return region.get_node_or_null("NavRebaker") as NavRebaker


func _wait_rebake(region: NavigationRegion3D) -> void:
	for i in 600:
		await get_tree().process_frame
		var rb := _rebaker(region)
		if rb != null and not rb.is_busy():
			break
	await wait_physics(4)


func _path(region: NavigationRegion3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := region.get_world_3d().navigation_map
	return NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from),
		NavigationServer3D.map_get_closest_point(map, to), true)


# ---------------------------------------------------------------- data

func test_kits_structures_and_recipes_are_valid() -> void:
	var recipes := RecipeDatabase.all_recipes()
	for id in IDS:
		var def: StructureDefinition = load("res://resources/structures/%s.tres" % id)
		check(def != null and def.id == StringName(id), "%s: definition" % id)
		if def == null:
			continue
		check(def.max_health > 0 and def.footprint.x > 0 and def.footprint.y > 0 and def.footprint.z > 0, "%s: health and footprint" % id)
		check(not def.repair_cost.is_empty() and not def.dismantle_return.is_empty(), "%s: repair cost and dismantle return" % id)
		var s := (load(def.scene_path) as PackedScene).instantiate()
		check(s is Structure and (s as Structure).definition == def, "%s: scene is a Structure using its definition" % id)
		var bodies := s.find_children("*", "StaticBody3D", true, false)
		check(not bodies.is_empty(), "%s: has a collision body" % id)
		for b in bodies:
			var layer := (b as StaticBody3D).collision_layer
			if def.blocks_navigation:
				check(layer == PhysicsLayers.STRUCTURES, "%s: solid body on the structures layer" % id)
			else:
				check(layer == PhysicsLayers.INTERACTABLES, "%s: walk-through body only build mode sees" % id)
		s.free()
		var kit := _kit(id)
		check(kit != null and kit.structure == def, "%s: kit builds it" % id)
		check(kit != null and kit.category == ItemDefinition.Category.STRUCTURE and kit.icon != null, "%s: kit category and icon" % id)
		var found: RecipeDefinition = null
		for r in recipes:
			if r.output == kit:
				found = r
		check(found != null, "%s: has a recipe" % id)
		if found != null:
			check(found.category == RecipeDefinition.Category.STRUCTURES, "%s: recipe in Structures" % id)
			var want := RecipeDefinition.Station.WORKBENCH if AT_BENCH.has(id) else RecipeDefinition.Station.HAND
			check(found.station == want, "%s: made at %s" % [id, RecipeDefinition.station_name(want)])
			# Crafting a kit never makes you heavier
			var in_weight := 0.0
			for item: ItemDefinition in found.inputs:
				in_weight += item.weight * found.inputs[item]
			check(kit.weight <= in_weight + 0.001, "%s: kit (%.1f kg) no heavier than its materials (%.1f kg)" % [id, kit.weight, in_weight])
			# Dismantling never gives back more than it cost
			for item: ItemDefinition in def.dismantle_return:
				check(def.dismantle_return[item] <= found.inputs.get(item, 0), "%s: dismantle returns no more %s than the recipe used" % [id, item.id])
	var trap: StructureDefinition = load("res://resources/structures/spike_trap.tres")
	check(not trap.blocks_navigation and not trap.breakable, "spike trap: raiders walk into it")


func test_hand_crafting_a_kit() -> void:
	await _world()
	var p := _player()
	var r: RecipeDefinition = load("res://resources/recipes/kit_wooden_barricade.tres")
	check(p.craft_refusal_reason(r) != "", "can't craft without planks")
	p.inventory.add_item(PLANK, 3)
	p.inventory.add_item(SCRAP, 1)
	check(p.request_craft(r), "crafting started")
	await _run(p, int(r.craft_time / DT) + 10)
	check(p.inventory.count_of(_kit("wooden_barricade").id) == 1, "made a barricade kit")
	var wall: RecipeDefinition = load("res://resources/recipes/kit_wooden_wall.tres")
	p.inventory.add_item(PLANK, 6)
	p.inventory.add_item(SCRAP, 2)
	check(p.craft_refusal_reason(wall).begins_with("Needs a"), "walls need a workbench")


# ---------------------------------------------------------------- placing

func test_placing_uses_the_kit() -> void:
	await _world()
	var p := _player()
	var kit := _kit("sandbag_barricade")
	p.inventory.add_item(kit, 2)
	await _run(p, 5)
	var placed: Array = []
	p.structure_placed.connect(func(s: Structure) -> void: placed.append(s))
	var xf := ConstructionRules.snap(Vector3(0.2, 0, -3.1), 30)
	check(xf.origin.is_equal_approx(Vector3(0, 0, -3.0)), "snapped to the 0.5 m grid")
	check(p.place_refusal_reason(kit, xf) == "", "can place: %s" % p.place_refusal_reason(kit, xf))
	var s := p.request_place_structure(kit, xf)
	check(s != null and s.get_parent() == structures, "built under Structures")
	check(p.inventory.count_of(kit.id) == 1, "one kit used")
	check(placed.size() == 1 and placed[0] == s, "structure_placed emitted")
	check(s != null and s.global_transform.is_equal_approx(xf), "at the ghost's transform")
	check(s != null and s.is_in_group("persist") and s.health == s.get_max_health(), "saved, at full health")


func test_placement_refusals() -> void:
	await _world()
	var p := _player()
	var kit := _kit("wooden_wall")
	var at := ConstructionRules.snap(Vector3(0, 0, -3), 0)
	check(p.place_refusal_reason(kit, at).begins_with("You don't have"), "no kit")
	check(p.place_refusal_reason(MEDKIT, at) == "That can't be built", "not a kit")
	p.inventory.add_item(kit, 5)
	await _run(p, 5)
	check(p.place_refusal_reason(kit, at) == "", "fine in the open")
	check(p.place_refusal_reason(kit, ConstructionRules.snap(Vector3(0, 0, -8), 0)) == "Too far away", "too far")
	# Something in the way: a crate-sized prop, a wall, another player
	var prop := make_static_box(Vector3(1, 1, 1), Vector3(0.5, 0.5, -3))
	check(p.place_refusal_reason(kit, at) == "Something's in the way", "prop in the way")
	prop.free()
	await wait_physics(2)
	var other := _player(Vector3(0.8, 0.05, -3))
	await wait_physics(3)
	check(p.place_refusal_reason(kit, at) == "Something's in the way", "a person in the way")
	other.free()
	await wait_physics(2)
	# On top of another structure
	_build("sandbag_barricade", Vector3(3, 0, -3))
	await wait_physics(2)
	var on_top := Transform3D(Basis(), Vector3(3, 1.0, -3))
	check(p.place_refusal_reason(kit, on_top) == "Can't build on another structure", "no stacking: %s" % p.place_refusal_reason(kit, on_top))
	# Uneven ground: a low step under one end
	make_static_box(Vector3(1.2, 0.6, 1.0), Vector3(-3.6, 0.3, -2), PhysicsLayers.TERRAIN)
	await wait_physics(2)
	check(p.place_refusal_reason(kit, ConstructionRules.snap(Vector3(-3, 0, -2), 0)) == "The ground is too uneven", "uneven ground")
	# Off the edge of the world
	p.global_position = Vector3(0, 0.05, -18)
	await _run(p, 3)
	check(p.place_refusal_reason(kit, ConstructionRules.snap(Vector3(0, 0, -20.5), 0)) == "Needs solid ground", "needs ground")
	p.global_position = Vector3(0, 0.05, 0)
	await _run(p, 3)
	# Keep the spawn clear
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(1, 0, -5)
	add_child(spawn)
	check(p.place_refusal_reason(kit, at) == "Keep the road in clear", "spawn kept clear")
	spawn.free()
	# Region limit
	for i in ConstructionRules.MAX_PER_REGION:
		structures.add_child(Node3D.new())
	check(p.place_refusal_reason(kit, at) == "Too many structures here", "structure limit")
	for c in structures.get_children():
		if not c is Structure:
			c.free()
	# No Structures node, nowhere to build
	structures.name = "NotStructures"
	check(p.place_refusal_reason(kit, at) == "You can't build here", "level without Structures")
	structures.name = "Structures"
	# Dead
	p.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.ENVIRONMENT, null))
	check(p.place_refusal_reason(kit, at) == "Can't build now", "dead players don't build")
	var refused: Array = []
	p.build_refused.connect(func(r: String) -> void: refused.append(r))
	var kits_before := p.inventory.count_of(kit.id)
	check(p.request_place_structure(kit, at) == null and refused.size() == 1, "refused request builds nothing and says why")
	check(p.inventory.count_of(kit.id) == kits_before and structures.get_child_count() == 1, "no kit used when refused")


# ---------------------------------------------------------------- repair / dismantle

func test_repair_and_dismantle() -> void:
	await _world()
	var p := _player()
	await _run(p, 3)
	var s := _build("wooden_barricade", Vector3(0, 0, -3))
	await wait_physics(2)
	check(p.repair_refusal_reason(s) == "Not damaged", "nothing to repair")
	s.apply_damage(120.0)
	check_near(s.health, 80.0, 0.01, "took damage")
	check(p.repair_refusal_reason(s).begins_with("Need "), "repair needs materials")
	for item: ItemDefinition in s.definition.repair_cost:
		p.inventory.add_item(item, s.definition.repair_cost[item])
	check(p.request_repair_structure(s), "repaired")
	check_near(s.health, s.get_max_health(), 0.01, "back to full")
	for item: ItemDefinition in s.definition.repair_cost:
		check(p.inventory.count_of(item.id) == 0, "repair used the %s" % item.id)
	var before := {}
	for item: ItemDefinition in s.definition.dismantle_return:
		before[item] = p.inventory.count_of(item.id)
	var def := s.definition
	check(p.request_dismantle_structure(s), "dismantled")
	await get_tree().process_frame
	check(not is_instance_valid(s), "gone")
	for item: ItemDefinition in def.dismantle_return:
		check(p.inventory.count_of(item.id) == before[item] + def.dismantle_return[item], "got back %s" % item.id)
	var far := _build("wooden_barricade", Vector3(0, 0, -12))
	await wait_physics(2)
	check(p.dismantle_refusal_reason(far) == "Too far away", "can't dismantle from afar")


func test_breaking_a_structure() -> void:
	await _world()
	var s := _build("wooden_barricade", Vector3(0, 0, -3))
	var broken: Array = []
	s.destroyed.connect(func(x: Structure) -> void: broken.append(x))
	s.apply_damage(150.0)
	check(is_instance_valid(s) and not s.is_queued_for_deletion(), "still standing at 50")
	s.apply_damage(60.0)
	check(broken.size() == 1 and s.is_queued_for_deletion(), "breaks at zero")
	s.apply_damage(60.0)
	check(broken.size() == 1, "only breaks once")


# ---------------------------------------------------------------- types

func test_gate_opens_closes_and_saves() -> void:
	await _world()
	var p := _player()
	var g := _build("wooden_gate", Vector3(0, 0, -3)) as GateStructure
	await wait_physics(2)
	var handle := g.find_children("*", "Interactable", true, false)[0] as Interactable
	check(handle.get_prompt(p).begins_with("Open"), "closed at first")
	g.set_open(true, false)
	check(g.is_open and handle.get_prompt(p).begins_with("Close"), "open")
	check(g.save_state().get("open") == true, "open state saved")
	var g2 := _build("wooden_gate", Vector3(4, 0, -3)) as GateStructure
	await get_tree().process_frame
	g2.load_state(g.save_state())
	check(g2.is_open, "open state loaded")
	# Won't swing shut on someone standing in it
	p.global_position = g.global_position + Vector3(0, 0.05, 0)
	await _run(p, 3)
	check(handle.get_block_reason(p) == "Someone's in the way", "won't close on a person")
	p.global_position = Vector3(0, 0.05, 0)
	await _run(p, 3)
	check(handle.get_block_reason(p) == "", "closes when clear")
	g.toggle()
	check(not g.is_open, "closed again")


func test_storage_crate_keeps_items_and_must_be_empty() -> void:
	await _world()
	var p := _player()
	await _run(p, 3)
	var crate := _build("storage_crate", Vector3(0, 0, -2.5)) as StorageStructure
	await wait_physics(2)
	check(crate.storage.is_searched, "nothing to search")
	check(crate.storage.inventory.get_free_slot_count() == crate.storage.inventory.slot_count, "starts empty")
	check(p.dismantle_refusal_reason(crate) == "", "empty crate can be dismantled")
	crate.storage.inventory.add_item(SCRAP, 7)
	check(p.dismantle_refusal_reason(crate) == "Empty it first", "full crate can't")


func test_spike_trap_hurts_raiders_not_players() -> void:
	await make_nav_floor()
	structures = Node3D.new()
	structures.name = "Structures"
	add_child(structures)
	var trap := _build("spike_trap", Vector3(0, 0, 0)) as SpikeTrap
	var p := _player(Vector3(0, 0.05, 0))
	await _run(p, 70)
	check_near(p.health.current_health, p.health.max_health, 0.01, "player unhurt on own trap")
	check_near(trap.health, trap.get_max_health(), 0.01, "trap untouched by the player")
	p.global_position = Vector3(15, 0.05, 15)
	await _run(p, 3)
	# A raider standing in it (brain off so it stays put)
	var r := RAIDER.instantiate() as Raider
	r.position = Vector3(0, 0.05, 0)
	add_child(r)
	r.set_physics_process(false)
	var rh := r.get_node("%HealthComponent") as HealthComponent
	var start := rh.current_health
	await wait_physics(4)
	check_near(start - rh.current_health, trap.damage, 0.01, "raider stabbed once")
	check_near(trap.health, trap.get_max_health() - trap.wear_per_hit, 0.01, "trap wears down")
	await wait_physics(30)
	check_near(start - rh.current_health, trap.damage, 0.01, "not again within a second")
	await wait_physics(40)
	check_near(start - rh.current_health, trap.damage * 2.0, 0.01, "again after a second")


func test_bench_works_and_cant_be_dismantled_in_use() -> void:
	await _world()
	var p := _player()
	await _run(p, 3)
	var b := _build("field_workbench", Vector3(0, 0, -2.2)) as BenchStructure
	await wait_physics(2)
	check(b.bench.station == RecipeDefinition.Station.WORKBENCH, "is a workbench")
	p.current_station = b.bench
	check(p.dismantle_refusal_reason(b) == "Someone's using it", "not while in use")
	p.current_station = null
	check(p.dismantle_refusal_reason(b) == "", "fine when nobody is")


# ---------------------------------------------------------------- navigation + raiders

func test_navmesh_rebakes_around_walls() -> void:
	var region := await _world(true)
	var a := Vector3(0, 0, 4)
	var b := Vector3(0, 0, -4)
	var straight := _path(region, a, b)
	check(straight.size() >= 2, "path before")
	var level_mesh := region.navigation_mesh
	# Three metal walls in a row across the path: 7.2 m wide
	for x in [-2.4, 0.0, 2.4]:
		_build("metal_wall", Vector3(x, 0, 0))
	await _wait_rebake(region)
	check(_rebaker(region) != null, "rebaker created")
	check(region.navigation_mesh != level_mesh, "baked into a copy, never the level's own navmesh")
	var around := _path(region, a, b)
	var widest := 0.0
	for pt in around:
		widest = maxf(widest, absf(pt.x))
	check(widest > 3.5, "path goes around the walls (%.2f m out)" % widest)
	# Spike traps don't change the navmesh
	var iter := NavigationServer3D.map_get_iteration_id(region.get_world_3d().navigation_map)
	_build("spike_trap", Vector3(6, 0, 6))
	await wait_physics(20)
	check(_rebaker(region).is_busy() == false, "no rebake for a trap")
	# Removing the walls opens the way again
	for s in structures.get_children():
		if (s as Structure).definition.blocks_navigation:
			s.queue_free()
	await wait_physics(2)
	await _wait_rebake(region)
	var again := _path(region, a, b)
	widest = 0.0
	for pt in again:
		widest = maxf(widest, absf(pt.x))
	check(widest < 1.0, "straight path again (%.2f m out)" % widest)
	check(iter > 0, "map was live")


func test_raider_breaks_in_when_walled_off() -> void:
	var region := await _world(true)
	# Wall the player into a 1.8 × 2.4 m box
	var walls: Array[Structure] = [
		_build("wooden_wall", Vector3(0, 0, 1.35)),
		_build("wooden_wall", Vector3(0, 0, -1.35)),
		_build("wooden_wall", Vector3(1.05, 0, 0), 90),
		_build("wooden_wall", Vector3(-1.05, 0, 0), 90),
	]
	await _wait_rebake(region)
	var p := _player(Vector3(0, 0.05, 0))
	var r := RAIDER.instantiate() as Raider
	r.position = Vector3(0, 0.1, -9)
	add_child(r)
	await wait_physics(3)
	r.alert_to(p)
	var hits := []
	p.health.damaged.connect(func(_a: float, _i: DamageInfo) -> void: hits.append(1))
	var damaged: Structure = null
	for i in 900:
		await _run(p, 1)
		for w in walls:
			if is_instance_valid(w) and w.is_damaged():
				damaged = w
		if damaged != null:
			break
	check(damaged != null, "raider hacked at a wall")
	check(hits.is_empty(), "couldn't reach the player through it")
	if damaged == null:
		return
	check(r.break_target == damaged, "targeting that wall")
	# It can't see the player through the wall, but doesn't give up
	var h := damaged.health
	for i in int((r.lose_target_time + 3.0) / DT):
		await _run(p, 1)
	check(is_instance_valid(damaged) and damaged.health < h - r.attack_damage, "still hacking long after losing sight (%.0f → %.0f)" % [h, damaged.health if is_instance_valid(damaged) else 0.0])
	if not is_instance_valid(damaged):
		return
	damaged.health = 5.0  # skip the long part
	for i in 1200:
		await _run(p, 1)
		if not hits.is_empty():
			break
	check(not is_instance_valid(damaged), "wall broken")
	check(not hits.is_empty(), "came through and hit the player")


# ---------------------------------------------------------------- saving

func test_structures_save_and_load_with_contents() -> void:
	await _world()
	var saves := get_node("/root/SaveManager")
	var wall := _build("metal_wall", Vector3(2, 0, -4), 45)
	var gate := _build("wooden_gate", Vector3(-3, 0, -4)) as GateStructure
	var crate := _build("storage_crate", Vector3(0, 0, -6)) as StorageStructure
	await wait_physics(2)
	wall.apply_damage(300.0)
	gate.set_open(true, false)
	crate.storage.inventory.add_item(SCRAP, 9)
	var wall_xf := wall.global_transform
	var data: Dictionary = saves.build_save_data(self)
	var json: Variant = JSON.parse_string(JSON.stringify(data))  # as on disk
	for s in structures.get_children():
		structures.remove_child(s)
		s.free()
	await wait_physics(2)
	saves.apply_save_data(json, self)
	await wait_physics(2)
	var loaded: Dictionary = {}
	for s in structures.get_children():
		loaded[(s as Structure).definition.id] = s
	check(loaded.size() == 3, "three structures rebuilt (%d)" % loaded.size())
	var w := loaded.get(&"metal_wall") as Structure
	check(w != null and w.global_transform.is_equal_approx(wall_xf), "wall where it was, same rotation")
	check(w != null and is_equal_approx(w.health, 600.0), "wall still damaged")
	var g := loaded.get(&"wooden_gate") as GateStructure
	check(g != null and g.is_open, "gate still open")
	var c := loaded.get(&"storage_crate") as StorageStructure
	check(c != null and c.storage.inventory.count_of(SCRAP.id) == 9, "crate still holds the scrap")
	check(c != null and c.storage.is_searched, "crate not turned into a loot crate")
	# Structures built after saving are removed on load
	_build("sandbag_barricade", Vector3(5, 0, 5))
	await wait_physics(2)
	saves.apply_save_data(json, self)
	await wait_physics(2)
	var count := 0
	for s in structures.get_children():
		if not s.is_queued_for_deletion():
			count += 1
	check(count == 3, "later barricade removed on load (%d)" % count)


func test_structures_are_remembered_per_region() -> void:
	var wm := get_node("/root/WorldManager")
	var old_states: Dictionary = (wm.get("region_states") as Dictionary).duplicate(true)
	var lvl := (load(OUTPOST_PATH) as PackedScene).instantiate() as Node3D
	for sp in lvl.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = false
	(lvl.get_node("Player") as PlayerController).controlled_locally = false
	add_child(lvl)
	await wait_physics(10)
	var root := ConstructionRules.structures_root(lvl)
	check(root != null and root.is_in_group("navigation_geometry"), "Outpost 17 has a Structures node the navmesh sees")
	var wall := _build("wooden_wall", Vector3(-6, 0, -8), 30, root)
	await wait_physics(2)
	wall.apply_damage(50.0)
	var xf := wall.global_transform
	await _wait_rebake(lvl.get_node("Navigation") as NavigationRegion3D)
	wm.call("capture_region", lvl)
	remove_child(lvl)
	lvl.free()
	await wait_physics(2)
	var lvl2 := (load(OUTPOST_PATH) as PackedScene).instantiate() as Node3D
	for sp in lvl2.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = false
	(lvl2.get_node("Player") as PlayerController).controlled_locally = false
	add_child(lvl2)
	await wait_physics(10)
	check(ConstructionRules.structures_root(lvl2).get_child_count() == 0, "a fresh copy has none")
	wm.call("enter_region", lvl2, {}, &"FromHaldens")
	await wait_physics(3)
	var kids := ConstructionRules.structures_root(lvl2).get_children()
	check(kids.size() == 1, "the wall is back on return")
	if kids.size() == 1:
		var w := kids[0] as Structure
		check(w.global_transform.is_equal_approx(xf) and is_equal_approx(w.health, 350.0), "same place, same damage")
	var town := (load("res://levels/haldens_crossing/haldens_crossing.tscn") as PackedScene).instantiate()
	check(ConstructionRules.structures_root(town) != null, "Halden's Crossing has a Structures node too")
	town.free()
	await _wait_rebake(lvl2.get_node("Navigation") as NavigationRegion3D)
	remove_child(lvl2)
	lvl2.free()
	wm.set("region_states", old_states)


# ---------------------------------------------------------------- build mode + HUD

func test_build_mode_ghost_place_and_hud() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	var refused: Array = []
	p.build_refused.connect(func(r: String) -> void: refused.append(r))
	await _run(p, 3)
	check(not bm.enter() and refused.size() == 1 and refused[0].begins_with("No structure kits"), "needs a kit to enter")
	p.inventory.add_item(_kit("wooden_barricade"), 1)
	p.inventory.add_item(_kit("sandbag_barricade"), 2)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	await get_tree().process_frame
	var panel := hud.get_node("%BuildPanel") as Control
	check(not panel.visible, "panel hidden outside build mode")
	check(bm.enter() and bm.active and p.building and p.player_input.build_mode, "in build mode")
	check(bm.kits.size() == 2, "both kinds of kit offered")
	_look_at(p, Vector3(0, 0, -3.5))
	bm.update_preview()
	check(bm.ghost_valid and bm.status_text() == "Click to build", "green ghost on open ground: %s" % bm.ghost_reason)
	var ghost := p.get_node_or_null("BuildGhost") as Node3D
	check(ghost != null and ghost.visible and ghost.get_child_count() > 0, "ghost shown (meshes only)")
	check(ghost != null and ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "ghost has no collision")
	check(get_tree().get_nodes_in_group("structures").is_empty(), "previewing builds nothing")
	await get_tree().process_frame
	check(panel.visible and (hud.get_node("%BuildTitle") as Label).text == bm.title_text(), "HUD shows the kit")
	var first := bm.current_kit()
	bm.select(1)
	check(bm.current_kit() != first, "next kit")
	bm.select(1)
	check(bm.current_kit() == first, "wraps around")
	bm.rotate()
	check(is_equal_approx(bm.yaw, 15.0), "rotated 15°")
	bm.rotate(-2)
	check(is_equal_approx(bm.yaw, 345.0), "rotated back past zero")
	bm.yaw = 0.0
	# Red ghost with the reason
	var prop := make_static_box(Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, -3.0))
	await wait_physics(2)
	_look_at(p, Vector3(0, 0.6, -3.0))
	bm.update_preview()
	check(not bm.ghost_valid and bm.status_text() == bm.ghost_reason and bm.ghost_reason != "", "red ghost says why: %s" % bm.ghost_reason)
	prop.free()
	await wait_physics(2)
	_look_at(p, Vector3(0, 0, -3.5))
	bm.select(0)
	while bm.current_kit().id != _kit("wooden_barricade").id:
		bm.select(1)
	var s := bm.place()
	check(s != null, "placed from build mode")
	check(bm.active and bm.kits.size() == 1, "still building with the sandbags left")
	# Looking at what you built: health and the repair/dismantle keys
	if s != null:
		s.apply_damage(50.0)
		_look_at(p, s.global_position + Vector3.UP * 0.6)
		bm.update_preview()
		check(bm.target == s, "targeting the barricade")
		check(bm.title_text().ends_with("75%"), "health shown: %s" % bm.title_text())
		check(bm.status_text().contains("[E] Repair") and bm.status_text().contains("[X] Dismantle"), "keys shown: %s" % bm.status_text())
		check(bm.dismantle() and p.inventory.count_of(_kit("wooden_barricade").id) == 0, "dismantled from build mode (materials back, not the kit)")
	bm.exit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not bm.active and not p.building and not p.player_input.build_mode, "left build mode")
	check(p.get_node_or_null("BuildGhost") == null or p.get_node("BuildGhost").is_queued_for_deletion(), "ghost removed")
	check(not panel.visible, "panel hidden again")


func test_build_mode_blocks_weapons_and_leaves_when_kits_run_out() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	p.inventory.add_item(_kit("sandbag_barricade"), 1)
	await _run(p, 3)
	check(bm.enter(), "entered")
	await _run(p, 2)
	check(p.weapon == null or p.weapon.lowered, "gun lowered while building")
	_look_at(p, Vector3(0, 0, -3.5))
	check(bm.place() != null, "placed the last kit")
	check(not bm.active and not p.building, "left build mode with no kits left")


func test_build_mode_can_pick_out_spike_traps() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	p.inventory.add_item(_kit("sandbag_barricade"), 1)
	await _run(p, 3)
	var trap := _build("spike_trap", Vector3(0, 0, -3))
	await wait_physics(2)
	check(bm.enter(), "entered")
	_look_at(p, Vector3(0, 0.2, -3))
	bm.update_preview()
	check(bm.target == trap, "looking at the trap targets it")
	check(bm.status_text().contains("[X] Dismantle"), "can dismantle it")
	# Players and raiders still walk through it
	p.global_position = Vector3(0, 0.05, -3)
	await _run(p, 10)
	check(p.global_position.y < 0.2, "player stands in the trap, not on it")
	bm.exit()


# ---------------------------------------------------------------- moving + undo

func test_moving_keeps_damage_rotation_and_contents() -> void:
	await _world()
	var p := _player()
	await _run(p, 3)
	var crate := _build("storage_crate", Vector3(0, 0, -2.5)) as StorageStructure
	await wait_physics(2)
	crate.apply_damage(100.0)
	crate.storage.inventory.add_item(SCRAP, 6)
	var moved: Array = []
	p.structure_moved.connect(func(s: Structure) -> void: moved.append(s))
	# A nudge that overlaps where it stands now: it doesn't block itself
	var to := ConstructionRules.snap(Vector3(0.5, 0, -2.5), 45)
	check(p.move_refusal_reason(crate, to) == "", "can nudge over its own spot: %s" % p.move_refusal_reason(crate, to))
	check(p.request_move_structure(crate, to), "moved")
	check(crate.global_transform.is_equal_approx(to), "at the new place and angle")
	check(is_equal_approx(crate.health, 150.0), "still damaged")
	check(crate.storage.inventory.count_of(SCRAP.id) == 6, "contents came along")
	check(moved.size() == 1 and moved[0] == crate, "structure_moved emitted")
	check(structures.get_child_count() == 1, "moved, not copied")
	# Refusals use the same rules as placing
	make_static_box(Vector3(1, 1, 1), Vector3(-3, 0.5, -3))
	await wait_physics(2)
	check(p.move_refusal_reason(crate, ConstructionRules.snap(Vector3(-3, 0, -3), 0)) == "Something's in the way", "not into a prop")
	check(p.move_refusal_reason(crate, ConstructionRules.snap(Vector3(0, 0, -12), 0)) == "Too far away", "not out of reach")
	var other := _build("wooden_barricade", Vector3(3, 0, -3))
	await wait_physics(2)
	check(p.move_refusal_reason(crate, ConstructionRules.snap(Vector3(3, 0, -3), 0)) == "Something's in the way", "not into another structure")
	check(not p.request_move_structure(crate, ConstructionRules.snap(Vector3(3, 0, -3), 0)) and crate.global_transform.is_equal_approx(to), "refused move leaves it put")
	check(other != null, "")
	# A bench in use can't be moved
	var b := _build("field_workbench", Vector3(-3, 0, 2)) as BenchStructure
	await wait_physics(2)
	p.current_station = b.bench
	check(p.move_refusal_reason(b, ConstructionRules.snap(Vector3(-3, 0, 3), 0)) == "Someone's using it", "bench in use stays")
	p.current_station = null


func test_moving_a_wall_rebakes_the_navmesh() -> void:
	var region := await _world(true)
	var walls: Array[Structure] = []
	for x in [-2.4, 0.0, 2.4]:
		walls.append(_build("metal_wall", Vector3(x, 0, 0)))
	await _wait_rebake(region)
	var p := _player(Vector3(1.5, 0.05, 3.5))
	await _run(p, 3)
	check(absf(_path(region, Vector3(0, 0, 4), Vector3(0, 0, -4))[1].x) > 0.5 or _path(region, Vector3(0, 0, 4), Vector3(0, 0, -4)).size() > 2, "blocked at first")
	# Swing the middle wall round to open a doorway
	check(p.request_move_structure(walls[1], ConstructionRules.snap(Vector3(0, 0, 2.0), 90)), "middle wall moved")
	await _wait_rebake(region)
	var path := _path(region, Vector3(0, 0, 4), Vector3(0, 0, -4))
	var widest := 0.0
	for pt in path:
		widest = maxf(widest, absf(pt.x))
	check(widest < 2.0, "raiders can walk through the gap now (%.2f m out)" % widest)


func test_build_mode_move_with_f() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	await _run(p, 3)
	var wall := _build("wooden_wall", Vector3(0, 0, -3))
	var start := wall.global_transform
	await wait_physics(2)
	check(bm.enter(), "build mode works with no kits when there's something to move")
	_look_at(p, wall.global_position + Vector3.UP * 1.2)
	bm.update_preview()
	check(bm.target == wall and bm.status_text().begins_with("[F] Move"), "F offered: %s" % bm.status_text())
	check(bm.start_move() and bm.moving == wall and not wall.visible, "picked up")
	check(bm.title_text() == "Moving Wooden Wall", "HUD says so")
	var ghost := p.get_node_or_null("BuildGhost") as Node3D
	check(ghost != null and ghost.get_child_count() > 0, "ghost is the wall")
	_look_at(p, Vector3(2.5, 0, -3.5))
	bm.update_preview()
	check(bm.target == null and bm.ghost_valid, "green ghost at the new spot: %s" % bm.ghost_reason)
	check(bm.status_text().begins_with("Click to put it here"), "status: %s" % bm.status_text())
	bm.cancel_move()
	check(bm.moving == null and wall.visible and wall.global_transform.is_equal_approx(start), "F again: back where it was")
	_look_at(p, wall.global_position + Vector3.UP * 1.2)
	bm.update_preview()
	check(bm.start_move(), "picked up again")
	bm.rotate(6)  # +90°
	_look_at(p, Vector3(2.5, 0, -3.5))
	var placed := bm.place()
	check(placed == wall and wall.visible and bm.moving == null, "put down")
	check(wall.global_position.distance_to(Vector3(2.5, 0, -3.5)) < 0.8, "at the new spot")
	check(absf(angle_difference(wall.global_rotation.y, start.basis.get_euler().y)) > deg_to_rad(40), "turned")
	check(structures.get_child_count() == 1, "still one wall")
	# Leaving build mode mid-move puts it back
	_look_at(p, wall.global_position + Vector3.UP * 1.2)
	bm.update_preview()
	var before := wall.global_transform
	bm.start_move()
	bm.exit()
	check(wall.visible and wall.global_transform.is_equal_approx(before), "B mid-move cancels it")


func test_dismantle_soon_after_placing_gives_the_kit_back() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	var kit := _kit("wooden_barricade")
	p.inventory.add_item(kit, 3)
	await _run(p, 3)
	var s := p.request_place_structure(kit, ConstructionRules.snap(Vector3(0, 0, -3), 0))
	check(s != null and s.can_undo(), "just placed: undo available")
	check(p.request_move_structure(s, ConstructionRules.snap(Vector3(0.5, 0, -3), 0)) and s.can_undo(), "moving it keeps the undo")
	check(bm.enter(), "build mode")
	_look_at(p, s.global_position + Vector3.UP * 0.6)
	bm.update_preview()
	check(bm.status_text().contains("[X] Dismantle (get the kit back)"), "HUD says the kit comes back: %s" % bm.status_text())
	var planks := p.inventory.count_of(PLANK.id)
	check(bm.dismantle(), "dismantled")
	check(p.inventory.count_of(kit.id) == 3 and p.inventory.count_of(PLANK.id) == planks, "kit back, no planks")
	bm.exit()
	await wait_physics(3)
	# Too late: materials
	var late := p.request_place_structure(kit, ConstructionRules.snap(Vector3(0, 0, -3), 0))
	late.placed_msec -= int(ConstructionRules.UNDO_SECONDS * 1000.0) + 10
	check(not late.can_undo(), "no undo after 30 s")
	check(p.request_dismantle_structure(late), "dismantled late")
	check(p.inventory.count_of(kit.id) == 2 and p.inventory.count_of(PLANK.id) == planks + 1, "materials, not the kit")
	await wait_physics(3)
	# Damaged: materials
	var hit := p.request_place_structure(kit, ConstructionRules.snap(Vector3(0, 0, -3), 0))
	hit.apply_damage(5.0)
	check(not hit.can_undo(), "no undo once damaged")
	await get_tree().process_frame
	# Loaded from a save: built earlier, so no undo
	var fresh := _build("wooden_barricade", Vector3(4, 0, -3))
	check(not fresh.can_undo(), "no undo for structures not placed this session")
