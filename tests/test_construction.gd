extends "res://tests/test_case.gd"
## Increments 13 and 14: construction. Kits and recipes, placement rules (every
## refusal), placing / repairing / dismantling, gates, storage crates, spike
## traps, navmesh rebakes, raiders breaking through, saving (per region) and
## build mode's ghost and HUD panel.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAIDER := preload("res://scenes/enemies/raider.tscn")
const OUTPOST_PATH := "res://levels/outpost_17/outpost_17.tscn"
const DT := 1.0 / 60.0
const IDS := ["sandbag_barricade", "wooden_barricade", "wooden_wall", "metal_wall",
	"wooden_gate", "spike_trap", "storage_crate", "field_workbench",
	"wooden_platform", "wooden_stairs", "ladder", "chain_link_fence"]
const AT_BENCH := ["wooden_wall", "metal_wall", "wooden_gate", "storage_crate",
	"wooden_platform", "wooden_stairs", "chain_link_fence"]

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")

var structures: Node3D


func _kit(id: String) -> ItemDefinition:
	return load("res://resources/items/kits/%s_kit.tres" % id)


## A flat 40 m floor in a "Navigation" region that bakes like the real
## levels (navigation_geometry group), plus a Structures node.
## (Only a baked world is named "Navigation", so building in an unbaked one
## doesn't start rebakes that outlive the test.)
func _world(bake := false) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "Navigation" if bake else "NoNavigation"
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
	var map := region.get_world_3d().navigation_map
	var iter := NavigationServer3D.map_get_iteration_id(map)
	var saw_bake := false
	for i in 600:
		await get_tree().process_frame
		var rb := _rebaker(region)
		if rb != null and rb.is_busy():
			saw_bake = true
		if (rb != null and not rb.is_busy()) or (rb == null and i > 20):
			break
	# The new navmesh reaches the map on a later sync: wait for it
	for i in 30:
		await get_tree().physics_frame
		if not saw_bake or NavigationServer3D.map_get_iteration_id(map) > iter:
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
	check(ConstructionRules.MAX_PER_REGION == 1000, "1000 structures per region")


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
	await _wait_rebake(region)


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



# ================================================================ Increment 14

const PLATFORM := "wooden_platform"

func _def(id: String) -> StructureDefinition:
	return load("res://resources/structures/%s.tres" % id)


func _deck_top(p: Structure) -> float:
	return p.global_position.y + p.definition.footprint.y


func test_variants_and_merged_meshes() -> void:
	for kind in ["wooden", "metal"]:
		var kit := _kit(kind + "_wall")
		var vs := kit.structure.get_variants()
		check(vs.size() == 3 and vs[0] == kit.structure, "%s wall kit: 3 variants, solid first" % kind)
		check(vs.map(func(v: StructureDefinition) -> String: return v.variant_name) == ["Solid", "Window", "Doorway"], "%s variant names" % kind)
		for v in vs:
			var sc := (load(v.scene_path) as PackedScene).instantiate() as Structure
			check(sc.definition == v and v.snap == StructureDefinition.Snap.EDGE, "%s: scene and snapping" % v.id)
			sc.free()
	var lad := _kit("ladder").structure.get_variants()
	check(lad.size() == 2 and is_equal_approx(lad[1].footprint.y, 5.2), "ladder: 2.6 m and 5.2 m")
	# Rendering: each structure is one mesh per material, not dozens of pieces
	for f in DirAccess.get_files_at("res://scenes/structures/"):
		if not f.ends_with(".tscn"):
			continue
		var root := (load("res://scenes/structures/" + f) as PackedScene).instantiate()
		var own := root.find_children("*", "MeshInstance3D", true, false).filter(func(n: Node) -> bool: return n.owner == root)
		check(own.size() <= 2, "%s: merged (%d mesh nodes)" % [f, own.size()])
		for mi in own:
			check((mi as MeshInstance3D).visibility_range_end > 0.0, "%s: fades out far away" % f)
		root.free()


func test_wall_variants_place_and_doorways_let_raiders_through() -> void:
	var region := await _world(true)
	var p := _player(Vector3(0, 0.05, 4))
	var kit := _kit("wooden_wall")
	p.inventory.add_item(kit, 3)
	await _run(p, 3)
	var door := _def("wooden_wall_doorway")
	check(p.place_refusal_reason(kit, ConstructionRules.snap(Vector3(0, 0, 0), 0), _def("metal_wall_window")) == "That can't be built", "only the kit's own variants")
	var mid := p.request_place_structure(kit, ConstructionRules.snap(Vector3(0, 0, 0), 0), door)
	check(mid != null and mid.scene_file_path.ends_with("wooden_wall_doorway.tscn"), "doorway placed")
	_build("metal_wall", Vector3(-2.4, 0, 0))
	_build("metal_wall", Vector3(2.4, 0, 0))
	_build("metal_wall", Vector3(-4.8, 0, 0))
	_build("metal_wall", Vector3(4.8, 0, 0))
	await _wait_rebake(region)
	var widest := 0.0
	for pt in _path(region, Vector3(0, 0, 6), Vector3(0, 0, -6)):
		widest = maxf(widest, absf(pt.x))
	check(widest < 0.7, "raiders path through the doorway (%.2f m out)" % widest)
	# Saved and loaded as the doorway
	var data: Dictionary = get_node("/root/SaveManager").build_save_data(self)
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	mid.get_parent().remove_child(mid)
	mid.free()
	get_node("/root/SaveManager").apply_save_data(json, self)
	await wait_physics(2)
	var back := structures.get_children().filter(func(n: Node) -> bool: return (n as Structure).definition == door)
	check(back.size() == 1, "doorway comes back as a doorway")


func test_build_mode_v_cycles_variants() -> void:
	await _world()
	var p := _player()
	var bm := p.get_node("%BuildMode") as BuildMode
	p.inventory.add_item(_kit("wooden_wall"), 2)
	await _run(p, 3)
	check(bm.enter(), "build mode")
	_look_at(p, Vector3(0, 0, -3.5))
	check(bm.current_variant().variant_name == "Solid" and bm.title_text().contains("Solid [V]"), "solid first: %s" % bm.title_text())
	bm.cycle_variant()
	check(bm.current_variant().variant_name == "Window" and bm.title_text().contains("Window [V]"), "V: window")
	check(bm.ghost_definition() == _def("wooden_wall_window"), "ghost shows the window wall")
	var s := bm.place()
	check(s != null and s.definition == _def("wooden_wall_window"), "placed the window wall")
	bm.cycle_variant()
	bm.cycle_variant()
	check(bm.current_variant().variant_name == "Solid", "wraps round")
	bm.exit()


func test_walls_hinge_onto_wall_ends_at_any_angle() -> void:
	await _world()
	var p := _player(Vector3(0, 0.05, 3))
	await _run(p, 3)
	var a := _build("wooden_wall", Vector3(0, 0, 0))
	await wait_physics(2)
	var def := _def("wooden_wall")
	var end := Vector3(1.2, 0, 0)
	for angle in [0.0, 45.0, 90.0, -90.0, 30.0]:
		var snap := ConstructionRules.snap_to_built(structures, def, end + Vector3(1.0, 0, 0).rotated(Vector3.UP, deg_to_rad(angle)), angle)
		check(not snap.is_empty() and snap["to"] == a, "%d°: snapped to the wall" % angle)
		if snap.is_empty():
			continue
		var x: Transform3D = snap["xform"]
		var ends := ConstructionRules.ends_of(def, x)
		check(ends[0].distance_to(end) < 0.01 or ends[1].distance_to(end) < 0.01, "%d°: shares the end" % angle)
		var turn := rad_to_deg(absf(angle_difference(x.basis.get_euler().y, 0.0)))
		check(absf(turn - absf(angle)) < 0.5 or absf(turn - (180.0 - absf(angle))) < 0.5, "%d°: at that angle (%.0f)" % [angle, turn])
		check(p.place_refusal_reason(_kit("wooden_wall"), x) == "You don't have a Wooden Wall Kit", "%d°: only the kit missing" % angle)
		p.inventory.add_item(_kit("wooden_wall"), 1)
		check(p.place_refusal_reason(_kit("wooden_wall"), x) == "", "%d°: a corner's overlap is fine: %s" % [angle, p.place_refusal_reason(_kit("wooden_wall"), x)])
		p.inventory.remove_item(_kit("wooden_wall").id, 1)
	# Folding back over it is still in the way
	var back := ConstructionRules.snap_to_built(structures, def, end + Vector3(-1.0, 0, 0), 180.0)
	p.inventory.add_item(_kit("wooden_wall"), 1)
	check(not back.is_empty() and p.place_refusal_reason(_kit("wooden_wall"), back["xform"]) == "Something's in the way", "can't fold back onto it")
	# Far from any end: no snap
	check(ConstructionRules.snap_to_built(structures, def, Vector3(0, 0, -4), 0.0).is_empty(), "nothing to snap to out there")
	# Build mode uses it: aim just past the end
	var bm := p.get_node("%BuildMode") as BuildMode
	p.inventory.add_item(_kit("wooden_wall"), 1)
	check(bm.enter(), "build mode")
	bm.yaw = -90.0
	_look_at(p, Vector3(1.3, 0, 1.1))
	bm.update_preview()
	check(bm.snapped_to == a and bm.status_text() == "Click to build  (joined)", "ghost joins on: %s" % bm.status_text())
	var placed := bm.place()
	check(placed != null and ConstructionRules.snap_partners(structures, placed.definition, placed.global_transform).has(a), "placed joined at the corner")
	bm.exit()


func test_platforms_tile_stack_and_carry_walls() -> void:
	var region := await _world(true)
	var p := _player(Vector3(0, 0.05, 5))
	await _run(p, 3)
	var pdef := _def(PLATFORM)
	var a := _build(PLATFORM, Vector3(0, 0, 0))
	await wait_physics(2)
	var kit := _kit(PLATFORM)
	p.inventory.add_item(kit, 3)
	# Next to it: snaps edge to edge
	var snap := ConstructionRules.snap_to_built(structures, pdef, Vector3(2.0, 0, 0.3), 0.0)
	check(not snap.is_empty() and (snap["xform"] as Transform3D).origin.distance_to(Vector3(2.4, 0, 0)) < 0.01, "tiles beside it")
	var b := p.request_place_structure(kit, snap["xform"])
	check(b != null, "second platform placed: %s" % p.place_refusal_reason(kit, snap["xform"]))
	# On top: a second storey
	var up := ConstructionRules.snap_to_built(structures, pdef, Vector3(0, 2.7, 0), 0.0)
	check(not up.is_empty() and absf((up["xform"] as Transform3D).origin.y - _deck_top(a)) < 0.01, "stacks on top")
	p.global_position = Vector3(0, 2.65, 2.0)
	await _run(p, 5)
	var c := p.request_place_structure(kit, up["xform"])
	check(c != null, "upper storey placed: %s" % p.place_refusal_reason(kit, up["xform"]))
	# A wall along a platform's edge, on the deck
	var wdef := _def("wooden_wall")
	var w := ConstructionRules.snap_to_built(structures, wdef, Vector3(3.6, 2.6, 0.2), 0.0)
	check(not w.is_empty() and absf((w["xform"] as Transform3D).origin.y - _deck_top(b)) < 0.01, "wall lines up on the deck edge")
	p.inventory.add_item(_kit("wooden_wall"), 1)
	var wall := p.request_place_structure(_kit("wooden_wall"), w["xform"])
	check(wall != null, "wall on the platform: %s" % p.place_refusal_reason(_kit("wooden_wall"), w["xform"]))
	# Not on top of a wall
	p.inventory.add_item(_kit("wooden_barricade"), 1)
	check(p.place_refusal_reason(_kit("wooden_barricade"), Transform3D(Basis(), Vector3(-0.3, 2.6 + 2.6, -1.2))) != "", "not on a wall top")
	# Standing on the deck
	p.global_position = Vector3(2.4, 2.7, 0)
	await _run(p, 20)
	check(p.is_on_floor() and absf(p.global_position.y - 2.6) < 0.1, "you can stand on the deck (y %.2f)" % p.global_position.y)
	# Support: can't take out what holds things up; breaking it brings them down
	check(ConstructionRules.resting_on(b).has(wall), "the wall rests on platform b")
	check(p.dismantle_refusal_reason(b) == "Take down what's built on it first", "can't dismantle under a wall")
	check(p.move_refusal_reason(b, Transform3D(Basis(), Vector3(8, 0, 0))) == "Take down what's built on it first", "can't move it either")
	check(ConstructionRules.resting_on(a).has(c), "upper storey rests on a")
	a.destroy()
	await wait_physics(3)
	check(not is_instance_valid(c), "the storey on it came down too")
	check(is_instance_valid(b) and is_instance_valid(wall), "the other platform and its wall stand")
	await _wait_rebake(region)


func test_stairs_and_ladders_reach_the_deck() -> void:
	var region := await _world(true)
	var p := _player(Vector3(6, 0.05, 6))
	await _run(p, 3)
	var plat := _build(PLATFORM, Vector3(0, 0, 0))
	await wait_physics(2)
	# Stairs snap against an edge, facing out, high end at the deck
	var sdef := _def("wooden_stairs")
	var s := ConstructionRules.snap_to_built(structures, sdef, Vector3(0, 0, 3.0), 0.0)
	check(not s.is_empty(), "stairs snap to the platform")
	var sx: Transform3D = s["xform"]
	check(absf(sx.origin.z - (1.2 + 1.7 + 0.02)) < 0.05 and absf(sx.origin.x) < 0.7, "against the +Z edge (%s)" % sx.origin)
	p.inventory.add_item(_kit("wooden_stairs"), 1)
	p.global_position = Vector3(2.5, 0.05, 3.0)
	await _run(p, 3)
	var stairs := p.request_place_structure(_kit("wooden_stairs"), sx)
	check(stairs != null, "stairs placed: %s" % p.place_refusal_reason(_kit("wooden_stairs"), sx))
	await _wait_rebake(region)
	# Raiders can walk up them
	var path := _path(region, Vector3(0, 0, 8), Vector3(0, 2.6, 0))
	check(path.size() > 0 and path[path.size() - 1].y > 2.3, "a path up the stairs to the deck")
	# So can you: walk up them
	var bottom := sx * Vector3(0, 0.05, 1.5)
	p.global_position = bottom + Vector3.UP * 0.1
	p.rotation.y = atan2(-(-sx.basis.z.x), -(-sx.basis.z.z))
	var f := InputFrame.new()
	f.move = Vector2(0, -1)
	for i in 240:
		await get_tree().physics_frame
		p.simulate(f, DT)
		if p.global_position.y > 2.4 and absf(p.global_position.z) < 1.0:
			break
	check(p.global_position.y > 2.4, "walked up onto the deck (y %.2f)" % p.global_position.y)
	# A ladder on another edge
	var ldef := _def("ladder")
	var l := ConstructionRules.snap_to_built(structures, ldef, Vector3(-2.0, 0, 0), 0.0)
	check(not l.is_empty(), "ladder snaps to the platform")
	p.global_position = Vector3(-3.5, 0.05, 2.0)
	p.inventory.add_item(_kit("ladder"), 1)
	await _run(p, 3)
	var lad := p.request_place_structure(_kit("ladder"), l["xform"])
	check(lad != null, "ladder placed: %s" % p.place_refusal_reason(_kit("ladder"), l["xform"]))
	if lad == null:
		return
	var climb := lad.get_node("Ladder") as Ladder
	check(absf(climb.get_top_y() - _deck_top(plat)) < 0.05, "ladder top level with the deck")
	# Climb it
	p.global_position = climb.global_position + climb.get_outward() * 1.2 + Vector3(0, 0.05, 0)
	var out := climb.get_outward()
	p.rotation.y = atan2(out.x, out.z)
	p.head.rotation.x = 0.0
	await _run(p, 3)
	for i in 360:
		await get_tree().physics_frame
		p.simulate(f, DT)
		if p.ladder == null and p.global_position.y > 2.4 and p.is_on_floor():
			break
	check(p.global_position.y > 2.4 and p.ladder == null, "climbed the ladder onto the deck (y %.2f)" % p.global_position.y)
	# The tall ladder is a variant of the same kit
	check(_kit("ladder").structure.get_variants()[1] == _def("ladder_tall"), "5.2 m ladder via V")
	check(ConstructionRules.snap_to_built(structures, _def("ladder_tall"), Vector3(-2.0, 0, 0), 0.0).is_empty(), "a 5.2 m ladder doesn't snap to a one-storey deck")


func test_ladder_only_fort_keeps_raiders_off() -> void:
	var region := await _world(true)
	_build(PLATFORM, Vector3(0, 0, 0))
	var l := ConstructionRules.snap_to_built(structures, _def("ladder"), Vector3(0, 0, 2.0), 0.0)
	var lad := _build("ladder", Vector3.ZERO)
	lad.global_transform = l["xform"]
	await _wait_rebake(region)
	var path := _path(region, Vector3(0, 0, 8), Vector3(0, 2.6, 0))
	check(path.size() == 0 or path[path.size() - 1].y < 1.0, "no raider path up a ladder")


func test_chain_link_fence_joins_walls() -> void:
	await _world()
	var p := _player(Vector3(0, 0.05, 3))
	await _run(p, 3)
	var w := _build("metal_wall", Vector3(0, 0, 0))
	await wait_physics(2)
	var fdef := _def("chain_link_fence")
	var s := ConstructionRules.snap_to_built(structures, fdef, Vector3(2.4, 0, 0), 0.0)
	check(not s.is_empty() and s["to"] == w, "fence snaps onto a wall end")
	p.inventory.add_item(_kit("chain_link_fence"), 1)
	var f := p.request_place_structure(_kit("chain_link_fence"), s["xform"])
	check(f != null and f.global_position.distance_to(Vector3(2.4, 0, 0)) < 0.01, "placed in line")
	check(f != null and (f.get_node("Body") as StaticBody3D).collision_layer == PhysicsLayers.STRUCTURES, "solid to raiders")


func test_gate_opens_from_anywhere_on_it() -> void:
	await _world()
	var p := _player(Vector3(0, 0.05, 2))
	var g := _build("wooden_gate", Vector3(0, 0, 0)) as GateStructure
	await _run(p, 5)
	for spot in [Vector3(-1.1, 1.0, 0), Vector3(1.1, 2.0, 0), Vector3(0, 2.5, 0), Vector3(0.3, 0.6, 0), Vector3(-0.6, 1.8, 0)]:
		_look_at(p, spot)
		await _run(p, 2)
		check(p.interactor.focused != null and p.interactor.focused.get_prompt(p).ends_with("Wooden Gate"), "E works looking at %s" % spot)
	_look_at(p, Vector3(0.5, 1.2, 0))
	var f := InputFrame.new()
	f.interact = true
	await get_tree().physics_frame
	p.simulate(f, DT)
	check(g.is_open, "opened by looking at the middle of the door")


# ---------------------------------------------------------------- level props

func _outpost() -> Node3D:
	var lvl := (load(OUTPOST_PATH) as PackedScene).instantiate() as Node3D
	for sp in lvl.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = false
	(lvl.get_node("Player") as PlayerController).controlled_locally = false
	add_child(lvl)
	await wait_physics(10)
	return lvl


func _near(lvl: Node3D, def_id: String) -> LevelProp:
	for n in get_tree().get_nodes_in_group("level_props"):
		if lvl.is_ancestor_of(n) and (n as LevelProp).definition.id == StringName(def_id):
			return n as LevelProp
	return null


func test_outpost_props_move_scrap_and_save() -> void:
	var lvl := await _outpost()
	var p := lvl.get_node("Player") as PlayerController
	var kinds := {}
	for n in get_tree().get_nodes_in_group("level_props"):
		if lvl.is_ancestor_of(n):
			kinds[String((n as LevelProp).definition.id)] = true
	for k in ["fuel_drums", "wood_crate", "sandbag_wall", "jersey_barrier", "chain_link_fence_prop", "military_truck", "portable_generator", "field_radio"]:
		check(kinds.has(k), "%s can be moved/scrapped" % k)
	# Scrap the fuel drums: materials, gone (no collision), out of the navmesh
	var drums := _near(lvl, "fuel_drums")
	p.global_position = drums.global_position + Vector3(0, 0.05, 2.0)
	await _run(p, 5)
	var scrap0 := p.inventory.count_of(SCRAP.id)
	check(p.dismantle_refusal_reason(drums) == "", "can scrap the drums: %s" % p.dismantle_refusal_reason(drums))
	check(p.request_dismantle_structure(drums), "scrapped")
	check(drums.scrapped and not drums.visible and (drums as Node as CollisionObject3D).collision_layer == 0, "gone, no collision")
	check(p.inventory.count_of(SCRAP.id) == scrap0 + 3 and p.inventory.count_of(&"fuel") >= 1, "3 scrap and fuel")
	check(p.dismantle_refusal_reason(drums) != "", "can't scrap it twice")
	# Move a jersey barrier
	var jb := _near(lvl, "jersey_barrier")
	p.global_position = jb.global_position + Vector3(0, 0.05, 2.5)
	await _run(p, 5)
	var to := Transform3D.IDENTITY
	var found := false
	for off in [Vector3(0, 0, 3.5), Vector3(3.5, 0, 0), Vector3(-3.5, 0, 0), Vector3(0, 0, -3.5), Vector3(0, 0, 1.5)]:
		var at: Vector3 = jb.global_position + off
		var gy := ConstructionRules.ground_y(lvl.get_world_3d().direct_space_state, at)
		if is_nan(gy):
			continue
		at.y = gy
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(30)), at)
		if p.move_refusal_reason(jb, xf) == "":
			to = xf
			found = true
			break
	check(found, "found somewhere to move the barrier")
	if found:
		check(p.request_move_structure(jb, to) and jb.global_transform.is_equal_approx(to), "barrier moved")
	# Trucks: scrap only
	var truck := _near(lvl, "military_truck")
	check(p.move_refusal_reason(truck, truck.global_transform) == "Can't move that", "trucks don't move")
	# Save, then a fresh copy of the level
	var saves := get_node("/root/SaveManager")
	var data: Variant = JSON.parse_string(JSON.stringify(saves.build_save_data(lvl)))
	var drums_path := lvl.get_path_to(drums)
	var jb_path := lvl.get_path_to(jb)
	await _settle(lvl)
	remove_child(lvl)
	lvl.free()
	var lvl2 := await _outpost()
	saves.apply_save_data(data, lvl2)
	await wait_physics(2)
	var d2 := lvl2.get_node(drums_path) as LevelProp
	check(d2.scrapped and not d2.visible, "drums still scrapped after loading")
	if found:
		check((lvl2.get_node(jb_path) as Node3D).global_transform.is_equal_approx(to), "barrier where you moved it")
	# Loading a save from before scrapping brings it back
	var before: Dictionary = (data as Dictionary).duplicate(true)
	for e in before["nodes"]:
		if str(e["path"]) == str(drums_path):
			e["data"]["scrapped"] = false
	saves.apply_save_data(before, lvl2)
	check(not d2.scrapped and d2.visible and (d2 as Node as CollisionObject3D).collision_layer != 0, "un-scrapped by an older save")
	await _settle(lvl2)
	remove_child(lvl2)
	lvl2.free()


## Lets a level's pending navmesh rebake finish before it's freed.
func _settle(lvl: Node3D) -> void:
	await _wait_rebake(lvl.get_node("Navigation") as NavigationRegion3D)


func test_build_mode_targets_props() -> void:
	var lvl := await _outpost()
	var p := lvl.get_node("Player") as PlayerController
	var truck := _near(lvl, "military_truck")
	p.global_position = truck.global_position + truck.global_basis.x * 3.5 + Vector3(0, 0.05, 0)
	await _run(p, 5)
	_look_at(p, truck.global_position + Vector3.UP * 1.4)
	var bm := p.get_node("%BuildMode") as BuildMode
	check(bm.enter(), "build mode with no kits")
	bm.update_preview()
	check(bm.target == truck, "targets the truck")
	check(bm.title_text() == "Military Truck" and not bm.status_text().contains("[F] Move") and bm.status_text().contains("[X] Scrap"), "scrap only: %s" % bm.status_text())
	check(not bm.start_move(), "F refuses to move a truck")
	check(bm.dismantle() and truck.scrapped, "X scraps it")
	check(p.inventory.count_of(SCRAP.id) >= 12, "a big haul of scrap")
	bm.exit()
	await _settle(lvl)
	remove_child(lvl)
	lvl.free()


# ================================================================ Increment 14 follow-ups

func _pan(dy: float) -> InputEventPanGesture:
	var e := InputEventPanGesture.new()
	e.delta = Vector2(0, dy)
	return e


func _wheel(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	return e


func test_scroll_steps_once_per_notch_or_swipe() -> void:
	var s := ScrollStepper.new()
	# Wheel: one step per notch, but not faster than the cooldown
	check(s.feed(_wheel(true), 1000) == 1 and s.feed(_wheel(true), 1050) == 0 and s.feed(_wheel(false), 1300) == -1, "wheel notches")
	# Magic Mouse swipe: a stream of pan events with momentum = one step
	var steps := 0
	var t := 5000
	for i in 40:
		steps += absi(s.feed(_pan(0.4 if i < 10 else 0.1), t))
		t += 16
	check(steps == 1, "one step per swipe (%d)" % steps)
	check(s.feed(_pan(0.5), t + 400) == 1, "next swipe after a pause steps again")
	check(s.feed(_pan(-0.5), t + 1000) == -1, "swipe the other way: back")
	check(s.feed(_pan(0.01), t + 1600) == 0, "a resting finger does nothing")


func test_spike_trap_slows_raiders_to_a_quarter() -> void:
	await make_nav_floor()
	structures = Node3D.new()
	structures.name = "Structures"
	add_child(structures)
	var trap := _build("spike_trap", Vector3(0, 0, 0)) as SpikeTrap
	check(is_equal_approx(trap.slow_factor, 0.25), "a quarter speed")
	var p := _player(Vector3(0, 0.05, -14))
	var r := RAIDER.instantiate() as Raider
	r.position = Vector3(0, 0.1, 8)
	add_child(r)
	await wait_physics(3)
	r.alert_to(p)
	var free_speed := 0.0
	var trap_speed := 0.0
	var in_trap := 0
	for i in 600:
		await _run(p, 1)
		var v := Vector2(r.get_real_velocity().x, r.get_real_velocity().z).length()
		if r.global_position.z > 3.0:
			free_speed = maxf(free_speed, v)
		elif absf(r.global_position.z) < 0.4:
			trap_speed = maxf(trap_speed, v)
			in_trap += 1
		if r.global_position.z < -2.5:
			break
	check(r.get_speed_factor() == 1.0, "full speed again once out")
	check(in_trap > 0 and trap_speed < free_speed * 0.35, "wades through at ~1/4 speed (%.2f vs %.2f m/s)" % [trap_speed, free_speed])
	check(r.global_position.z < -2.5, "still gets through")


func test_salvage_containers_move_and_scrap() -> void:
	var lvl := await _outpost()
	var p := lvl.get_node("Player") as PlayerController
	var crate := lvl.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	var prop := crate.get_node("Prop") as ContainerProp
	check(prop != null and Structure.from_collider(crate.get_node("Body")) == prop, "build mode can target the crate")
	p.global_position = crate.global_position + crate.global_basis.z * 1.8 + Vector3(0, 0.05, 0)
	await _run(p, 5)
	check(p.dismantle_refusal_reason(prop) == "Search it first", "unsearched: search it first")
	crate.search()
	var loot := str(crate.inventory.to_data())
	if crate.inventory.get_free_slot_count() < crate.inventory.slot_count:
		check(p.dismantle_refusal_reason(prop) == "Empty it first", "loot inside: empty it first")
	# Move it, loot and all
	var to := Transform3D.IDENTITY
	var found := false
	for off in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(1.0, 0, 1.0)]:
		var at: Vector3 = crate.global_position + off
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(90)), at)
		if p.move_refusal_reason(prop, xf) == "":
			to = xf
			found = true
			break
	check(found, "somewhere to move it")
	if found:
		check(p.request_move_structure(prop, to) and crate.global_transform.is_equal_approx(to), "the crate moved")
		check(str(crate.inventory.to_data()) == loot and crate.is_searched, "same loot, still searched")
	# Empty it and scrap it
	p.inventory.max_weight = 999.0
	for i in crate.inventory.slot_count:
		crate.inventory.transfer_slot_to(i, p.inventory)
	var wood0 := p.inventory.count_of(&"wood")
	check(p.dismantle_refusal_reason(prop) == "", "empty: can scrap: %s" % p.dismantle_refusal_reason(prop))
	check(p.request_dismantle_structure(prop), "scrapped")
	check(prop.scrapped and not crate.visible and crate.collision_layer == 0 and (crate.get_node("Body") as StaticBody3D).collision_layer == 0, "gone, can't be searched or bumped into")
	check(p.inventory.count_of(&"wood") == wood0 + 2, "2 wood back")
	# Saved
	var saves := get_node("/root/SaveManager")
	var data: Variant = JSON.parse_string(JSON.stringify(saves.build_save_data(lvl)))
	await _settle(lvl)
	remove_child(lvl)
	lvl.free()
	var lvl2 := await _outpost()
	saves.apply_save_data(data, lvl2)
	await wait_physics(2)
	var crate2 := lvl2.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	check((crate2.get_node("Prop") as ContainerProp).scrapped and not crate2.visible, "still scrapped after loading")
	var other := lvl2.get_node("SalvageContainers/BarracksLocker") as SalvageContainer
	check(other.visible and not (other.get_node("Prop") as ContainerProp).scrapped, "others untouched")
	await _settle(lvl2)
	remove_child(lvl2)
	lvl2.free()


func test_built_storage_crate_is_not_a_level_prop() -> void:
	await _world()
	var crate := _build("storage_crate", Vector3(0, 0, -3)) as StorageStructure
	await wait_physics(2)
	check(crate.storage.get_node_or_null("Prop") == null, "the crate scene's stand-in is removed")
	check(Structure.from_collider(crate.storage.get_node("Body")) == crate, "targets the storage crate itself")


func test_raiders_walk_through_an_open_gate() -> void:
	var region := await _world(true)
	# A long wall with a gate in the middle
	var gate := _build("wooden_gate", Vector3(0, 0, 0)) as GateStructure
	for x in [-2.4, 2.4, -4.8, 4.8, -7.2, 7.2, -9.6, 9.6, -12.0, 12.0]:
		_build("metal_wall", Vector3(x, 0, 0))
	await _wait_rebake(region)
	var widest := func() -> float:
		var w := 0.0
		var path := _path(region, Vector3(0, 0, 6), Vector3(0, 0, -6))
		for pt in path:
			w = maxf(w, absf(pt.x))
		return w if path.size() > 0 else 99.0
	check(widest.call() > 5.0, "closed: the way through is blocked (%.1f m out)" % widest.call())
	gate.set_open(true)
	await get_tree().create_timer(0.7).timeout  # the door swings (0.45 s), then the rebake
	await _wait_rebake(region)
	check(widest.call() < 1.2, "open: raiders path straight through (%.2f m out)" % widest.call())
	# A raider chasing you walks through instead of hacking at it
	var p := _player(Vector3(0, 0.05, -8))
	var r := RAIDER.instantiate() as Raider
	r.position = Vector3(0, 0.1, 8)
	add_child(r)
	await wait_physics(3)
	r.alert_to(p)
	var went_through := false
	for i in 600:
		await _run(p, 1)
		if r.global_position.z < -1.0:
			went_through = true
			break
	check(went_through, "the raider came through the open gate")
	check(not gate.is_damaged(), "and didn't attack it")
	gate.set_open(false, false)
	await _wait_rebake(region)
	check(widest.call() > 5.0, "closed again: blocked")


func test_modify_weapons_opens_on_the_gun_in_hand() -> void:
	await _world()
	var p := _player()
	await _run(p, 3)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	await get_tree().process_frame
	var bench := (load("res://scenes/world/stations/weapons_bench.tscn") as PackedScene).instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.5)
	add_child(bench)
	await wait_physics(2)
	p.current_station = bench
	p.weapon_slots.equip_immediately(1)  # the rifle (pistol is slot 2)
	var rifle_slot := p.weapon.base_definition.slot
	var screen := hud.find_child("CraftingScreen", true, false)
	screen.call("open")
	screen.call("show_gunsmith", true)
	var gs := screen.get_node("%GunsmithPanel") as GunsmithPanel
	check(gs.selected_slot == rifle_slot, "the rifle in your hand is selected (slot %d, got %d)" % [rifle_slot, gs.selected_slot])
	screen.call("close")
	p.current_station = null
