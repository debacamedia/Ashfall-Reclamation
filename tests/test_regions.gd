extends "res://tests/test_case.gd"
## Increment 12: regions and travel (WorldManager, RegionExit, save version
## 2) and the Halden's Crossing level (ruined town + raider camp).

const OUTPOST_PATH := "res://levels/outpost_17/outpost_17.tscn"
const HALDENS_PATH := "res://levels/haldens_crossing/haldens_crossing.tscn"
const DT := 1.0 / 60.0

var RIFLE: WeaponDefinition = load("res://resources/items/weapons/service_rifle.tres")


func _wm() -> Node:
	return get_node("/root/WorldManager")


func _sm() -> Node:
	return get_node("/root/SaveManager")


func _load(path: String, raiders := false) -> Node3D:
	var lvl := (load(path) as PackedScene).instantiate() as Node3D
	for sp in lvl.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = raiders
	var p := lvl.get_node("Player") as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	add_child(lvl)
	await wait_physics(20)
	await wait_for_navigation(lvl.get_world_3d().navigation_map)
	return lvl


func _unload(lvl: Node) -> void:
	remove_child(lvl)
	lvl.free()
	await wait_physics(2)


func _player(lvl: Node) -> PlayerController:
	return lvl.get_node("Player") as PlayerController


func _run(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _face(p: PlayerController, target: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(target.x - eye.x, 0, target.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(target.y - eye.y, flat.length())


func _teleport(p: PlayerController, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await wait_physics(4)


# ---------------------------------------------------------------- data

func test_levels_link_both_ways() -> void:
	var outpost := (load(OUTPOST_PATH) as PackedScene).instantiate()
	var haldens := (load(HALDENS_PATH) as PackedScene).instantiate()
	check(_wm().region_name_of(outpost) == "Outpost 17", "outpost name: %s" % _wm().region_name_of(outpost))
	check(_wm().region_name_of(haldens) == "Halden's Crossing", "town name: %s" % _wm().region_name_of(haldens))
	for pair in [[outpost, haldens, HALDENS_PATH], [haldens, outpost, OUTPOST_PATH]]:
		var exits: Array = pair[0].get_node("Exits").get_children()
		check(exits.size() == 1, "%s has a road out" % pair[0].name)
		var exit := exits[0] as RegionExit
		check(exit.target_level == pair[2], "%s: leads to %s" % [pair[0].name, exit.target_level])
		check(_wm().find_arrival(pair[1], exit.arrival_id) != null
			and _wm().find_arrival(pair[1], exit.arrival_id).name == String(exit.arrival_id),
			"%s: arrival %s exists" % [pair[0].name, exit.arrival_id])
	outpost.free()
	haldens.free()


func test_veterans_and_loot_tables() -> void:
	var vet := (load("res://scenes/enemies/raider_veteran.tscn") as PackedScene).instantiate() as Raider
	var basic := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	check(vet.display_name == "Raider Veteran", "named")
	var vh := (vet.get_node("%HealthComponent") as HealthComponent).max_health
	var bh := (basic.get_node("%HealthComponent") as HealthComponent).max_health
	check(vh >= bh * 1.5, "much tougher (%d vs %d HP)" % [vh, bh])
	check(vet.attack_damage > basic.attack_damage and vet.drop_chance == 1.0, "hits harder, always drops loot")
	vet.free()
	basic.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for name in ["town_household", "town_supplies", "garage_parts", "clinic_cabinet", "raider_camp_cache", "sniper_stash", "bank_safe"]:
		var t := load("res://resources/loot/%s.tres" % name) as LootTable
		check(t != null, "%s exists" % name)
		for item in t.possible_items():
			check(ItemDatabase.get_item(item.id) == item, "%s: %s registered" % [name, item.id])
	var cache := load("res://resources/loot/raider_camp_cache.tres") as LootTable
	for i in 10:
		var ids := cache.roll(rng).map(func(e: Dictionary) -> StringName: return (e["item"] as ItemDefinition).id)
		check(ids.has(&"gun_barrel") and ids.has(&"trigger_group"), "the raider cache always has gun parts (%s)" % [ids])


# ---------------------------------------------------------------- travel

func test_travel_round_trip_keeps_player_and_region_state() -> void:
	_wm().reset()
	var outpost := await _load(OUTPOST_PATH)
	var p := _player(outpost)
	p.give_weapon(RIFLE)
	p.inventory.add_item(ItemDatabase.get_item(&"electronics"), 3)
	p.health.apply_damage(DamageInfo.create(37.0, DamageInfo.Type.FALL))
	# Loot the outpost a little: take a pickup, search a crate
	var loot := outpost.get_node("Loot")
	var taken := loot.get_child(0).name
	loot.get_child(0).free()
	var crate := outpost.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	crate.search()
	var crate_contents := crate.inventory.to_data()
	var carried: Dictionary = _wm().capture_region(outpost)
	check(not carried.is_empty(), "player data carried")
	check(_wm().region_states.has(OUTPOST_PATH), "outpost state kept")
	await _unload(outpost)

	var town := await _load(HALDENS_PATH)
	_wm().enter_region(town, carried, &"FromOutpost")
	await wait_physics(3)
	p = _player(town)
	var arrival := town.get_node("Arrivals/FromOutpost") as Node3D
	check(p.global_position.distance_to(arrival.global_position) < 0.5, "arrived at the north road (%s)" % p.global_position)
	check(p.weapon_slots.get_weapon(1) != null and p.weapon_slots.get_weapon(1).base_definition == RIFLE, "rifle carried")
	check(p.weapon_slots.get_weapon(5) != null, "machete carried")
	check(p.inventory.count_of(&"electronics") == 3, "inventory carried")
	check_near(p.health.current_health, 63.0, 0.01, "health carried")
	# Loot the town
	var cloth := town.get_node("Loot/StoreCloth")
	cloth.free()
	var pile := town.get_node("SalvagePiles/StorePallet") as SalvagePile
	pile._perform(p)
	carried = _wm().capture_region(town)
	await _unload(town)

	outpost = await _load(OUTPOST_PATH)
	_wm().enter_region(outpost, carried, &"FromHaldens")
	await wait_physics(3)
	p = _player(outpost)
	check(p.global_position.distance_to(outpost.get_node("Arrivals/FromHaldens").global_position) < 0.5, "back at the outpost's south road")
	check(outpost.get_node("Loot").get_node_or_null(NodePath(taken)) == null, "the pickup you took is still gone")
	crate = outpost.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	check(crate.is_searched and crate.inventory.to_data() == crate_contents, "the crate is searched, same contents")
	check(p.inventory.count_of(&"wood") == 3, "the pallet's wood came with you")
	carried = _wm().capture_region(outpost)
	await _unload(outpost)

	town = await _load(HALDENS_PATH)
	_wm().enter_region(town, carried, &"FromOutpost")
	await wait_physics(3)
	check(town.get_node("Loot").get_node_or_null("StoreCloth") == null, "the town remembers too")
	check(town.get_node("SalvagePiles").get_node_or_null("StorePallet") == null, "broken pallet stays gone")
	check(town.get_node("Loot").get_node_or_null("StoreScrap") != null, "untouched loot is still there")
	await _unload(town)
	_wm().reset()


func test_travel_refusals() -> void:
	_wm().reset()
	var outpost := await _load(OUTPOST_PATH)
	var p := _player(outpost)
	var exit := outpost.get_node("Exits/RoadToHaldens") as RegionExit
	check(_wm().travel_refusal_reason(p, exit) == "", "allowed normally")
	check(exit.get_prompt(p) == "Follow the road to Halden's Crossing", "prompt: %s" % exit.get_prompt(p))
	var bad := RegionExit.new()
	bad.target_level = "res://levels/nowhere.tscn"
	check(_wm().travel_refusal_reason(p, bad) == "The road is blocked", "missing level")
	bad.free()
	p.inventory.add_item(ItemDatabase.get_item(&"cloth"), 2)
	p.request_craft(load("res://resources/recipes/bandage.tres"))
	check(_wm().travel_refusal_reason(p, exit) == "Finish crafting first", "not mid-craft")
	p.cancel_crafting()
	var raider := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	raider.position = p.global_position + Vector3(8, 0, 0)
	outpost.add_child(raider)
	await wait_physics(2)
	raider.alert_to(p)
	await wait_physics(2)
	check(_wm().travel_refusal_reason(p, exit) == "Raiders are on your tail", "not with a raider chasing: '%s'" % _wm().travel_refusal_reason(p, exit))
	raider.queue_free()
	await wait_physics(2)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	check(_wm().travel_refusal_reason(p, exit) == "Can't travel now", "not while dead")
	await _unload(outpost)


func test_hold_e_at_the_sign_really_travels() -> void:
	# End to end through the real scene change: the outpost becomes the
	# current scene, the player holds E at the road sign.
	_wm().reset()
	var outpost := (load(OUTPOST_PATH) as PackedScene).instantiate() as Node3D
	(outpost.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	var p := _player(outpost)
	p.controlled_locally = false
	get_tree().root.add_child(outpost)
	get_tree().current_scene = outpost
	await wait_physics(20)
	p.inventory.add_item(ItemDatabase.get_item(&"electronics"), 2)
	var exit := outpost.get_node("Exits/RoadToHaldens") as RegionExit
	await _teleport(p, exit.global_position + exit.global_basis.z * 1.6 + Vector3.UP * 0.05)
	_face(p, exit.get_focus_point())
	await _run(p, 3)
	check(p.interactor.focused == exit, "looking at the sign (got %s)" % p.interactor.focused)
	var started := []
	var arrived := []
	_wm().travel_started.connect(func(n: String) -> void: started.append(n), CONNECT_ONE_SHOT)
	_wm().arrived.connect(func(n: String) -> void: arrived.append(n), CONNECT_ONE_SHOT)
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 20, e)
	check(started.is_empty(), "a short press does nothing (hold 1 s)")
	await _run(p, 50, e)
	check(started == ["Halden's Crossing"], "travel started: %s" % [started])
	for i in 300:
		await get_tree().process_frame
		if not arrived.is_empty():
			break
	check(arrived == ["Halden's Crossing"], "arrived: %s" % [arrived])
	var town := get_tree().current_scene
	check(town != null and town.scene_file_path == HALDENS_PATH, "Halden's Crossing is the current scene")
	if town != null and town.scene_file_path == HALDENS_PATH:
		var p2 := _player(town)
		check(p2.global_position.distance_to(town.get_node("Arrivals/FromOutpost").global_position) < 0.6, "at the north road")
		check(p2.inventory.count_of(&"electronics") == 2, "inventory came along")
		check(not p2.player_input.ui_open, "controls handed back after the fade")
		check(_wm().region_states.has(OUTPOST_PATH), "outpost remembered")
	get_tree().unload_current_scene()
	await wait_physics(3)
	_wm().reset()


func test_save_and_load_in_the_town_remembers_the_outpost() -> void:
	_wm().reset()
	_sm().save_dir = "user://test_saves_regions"
	var outpost := await _load(OUTPOST_PATH)
	var taken := outpost.get_node("Loot").get_child(0).name
	outpost.get_node("Loot").get_child(0).free()
	var carried: Dictionary = _wm().capture_region(outpost)
	await _unload(outpost)
	var town := await _load(HALDENS_PATH)
	_wm().enter_region(town, carried, &"FromOutpost")
	var p := _player(town)
	await _teleport(p, Vector3(-30, 0.05, 2))
	check(_sm().save_game("regions_test", town) == OK, "saved in the town")
	var data: Dictionary = _sm().read_save_file(_sm().slot_path("regions_test"))
	check(int(data.get("version")) == 2 and data.get("level") == HALDENS_PATH, "version 2, town level")
	check((data.get("regions") as Dictionary).has(OUTPOST_PATH), "the outpost's state is in the save")
	# Forget everything, then load
	_wm().reset()
	await _teleport(p, Vector3(0, 0.05, -60))
	check(_sm().load_game("regions_test", town) == OK, "loaded")
	check(p.global_position.distance_to(Vector3(-30, 0.05, 2)) < 0.3, "position restored in the town")
	check(_wm().region_states.has(OUTPOST_PATH), "outpost state restored from the save")
	await _unload(town)
	outpost = await _load(OUTPOST_PATH)
	_wm().enter_region(outpost, {}, &"FromHaldens")
	check(outpost.get_node("Loot").get_node_or_null(NodePath(taken)) == null, "and applied when you go back")
	await _unload(outpost)
	# A version-1 save still loads (no regions)
	var v1 := {"format": "ashfall_save", "version": 1, "level": OUTPOST_PATH, "nodes": []}
	check(_sm().validate(v1) == "", "v1 accepted")
	check(_sm()._migrate(v1).get("regions") == {} and int(v1["version"]) == 2, "v1 migrated")
	_sm().delete_save("regions_test")
	_sm().save_dir = "user://saves"
	_wm().reset()


# ---------------------------------------------------------------- the town

func test_town_containers_clear_on_the_ground_and_searchable() -> void:
	var town := await _load(HALDENS_PATH)
	var p := _player(town)
	var space := town.get_world_3d().direct_space_state
	var containers := town.get_node("SalvageContainers").get_children()
	check(containers.size() >= 20, "20+ containers (%d)" % containers.size())
	var ids := {}
	for c: SalvageContainer in containers:
		check(c.loot_table != null, "%s has a loot table" % c.name)
		ids[str(town.get_path_to(c))] = true
		var body := c.get_node("Body") as StaticBody3D
		var shape := body.get_node("BodyShape") as CollisionShape3D
		var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size -= Vector3(0.06, 0.06, 0.06)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = shape.global_transform
		q.collision_mask = PhysicsLayers.WORLD_SOLID
		q.exclude = [body.get_rid()]
		var hits := space.intersect_shape(q, 4)
		check(hits.is_empty(), "%s clear of walls and props (%s)" % [c.name, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))])
		var down := PhysicsRayQueryParameters3D.create(c.global_position + Vector3.UP * 0.2, c.global_position + Vector3.DOWN * 0.5, PhysicsLayers.WORLD_SOLID, [body.get_rid()])
		check(not space.intersect_ray(down).is_empty(), "%s stands on a floor" % c.name)
		# Searchable from the front
		p.close_container()
		var front := c.global_basis.z
		front.y = 0.0
		await _teleport(p, c.global_position + front.normalized() * 1.3 + Vector3.UP * 0.05)
		_face(p, c.get_focus_point())
		await _run(p, 2)
		check(p.interactor.focused == c, "%s can be searched from the front (got %s)" % [c.name, p.interactor.focused])
	await _unload(town)


func test_every_ground_container_reachable_on_foot() -> void:
	var town := await _load(HALDENS_PATH)
	var map := town.get_world_3d().navigation_map
	var start := (town.get_node("Arrivals/FromOutpost") as Node3D).global_position
	var high := 0
	for c: SalvageContainer in town.get_node("SalvageContainers").get_children():
		var front := c.global_basis.z
		front.y = 0.0
		var goal := c.global_position + front.normalized() * 1.2
		if c.global_position.y > 1.0:
			# Up a ladder: the floor it's on must connect to a ladder top
			high += 1
			var near_ladder := false
			for l: Ladder in get_tree().get_nodes_in_group("ladders"):
				if town.is_ancestor_of(l) and absf(l.get_top_y() - c.global_position.y) < 0.6 \
						and Vector2(l.global_position.x - c.global_position.x, l.global_position.z - c.global_position.z).length() < 16.0:
					near_ladder = true
			check(near_ladder, "%s (up high) has a ladder up to it" % c.name)
			continue
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		check(path.size() > 0 and path[path.size() - 1].distance_to(goal) < 1.0,
			"%s reachable from the north road (path ends %s, goal %s)" % [c.name, path[path.size() - 1] if path.size() > 0 else "-", goal])
	check(high == 3, "3 stashes up high: hotel roof, hotel upstairs, water tower (%d)" % high)
	await _unload(town)


func test_salvage_and_pickups_placed_sensibly() -> void:
	var town := await _load(HALDENS_PATH)
	var space := town.get_world_3d().direct_space_state
	var piles := town.get_node("SalvagePiles").get_children()
	check(piles.size() >= 20, "20+ salvage piles (%d)" % piles.size())
	var scrap_heaps := 0
	for pile: SalvagePile in piles:
		if pile.pile_name == "Scrap Heap":
			scrap_heaps += 1
		var shape := pile.get_node("Shape") as CollisionShape3D
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape.shape
		q.transform = shape.global_transform
		q.collision_mask = PhysicsLayers.WORLD_SOLID
		var hits := space.intersect_shape(q, 4).filter(func(h: Dictionary) -> bool: return (h["collider"] as Node).name != "Terrain")
		check(hits.is_empty(), "%s clear (%s)" % [pile.name, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))])
	check(scrap_heaps >= 6, "scrap heaps for bulk scrap (%d)" % scrap_heaps)
	for pk: Pickup in town.get_node("Loot").get_children():
		var down := PhysicsRayQueryParameters3D.create(pk.global_position + Vector3.UP * 0.3, pk.global_position + Vector3.DOWN * 0.3, PhysicsLayers.WORLD_SOLID)
		check(not space.intersect_ray(down).is_empty(), "%s rests on something" % pk.name)
		var q := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.12
		q.shape = sphere
		q.transform = Transform3D(Basis.IDENTITY, pk.global_position + Vector3.UP * 0.2)
		q.collision_mask = PhysicsLayers.WORLD_SOLID
		check(space.intersect_shape(q, 1).is_empty(), "%s isn't inside anything" % pk.name)
	await _unload(town)


func test_climb_to_the_sightlines() -> void:
	var town := await _load(HALDENS_PATH)
	var p := _player(town)
	for path in ["WaterTower/Ladder", "Buildings/Hotel/RoofLadder", "Buildings/Hotel/InnerLadder1"]:
		var l := town.get_node(path) as Ladder
		p.health.revive(1.0)
		var out := l.get_outward()
		await _teleport(p, l.global_position + out * 1.2 + Vector3.UP * 0.05)
		p.rotation.y = atan2(out.x, out.z)  # face the ladder
		p.head.rotation.x = 0.0
		var w := InputFrame.new()
		w.move = Vector2(0, -1)
		for i in 900:
			await _run(p, 1, w)
			if p.ladder == null and p.global_position.y > l.get_top_y() - 0.3 and p.is_on_floor():
				break
		check(p.global_position.y > l.get_top_y() - 0.3 and p.is_on_floor(),
			"%s: climbed to %.1f m (at %.2f)" % [path, l.get_top_y(), p.global_position.y])
	await _unload(town)


func test_walk_in_through_doors() -> void:
	var town := await _load(HALDENS_PATH)
	var p := _player(town)
	# [start on the street, facing yaw, building, interior point]
	for spec in [[Vector3(-4.5, 0.05, -60), 90.0, "GeneralStore", -11.5], [Vector3(-4.5, 0.05, -22), 90.0, "Hotel", -10.5],
			[Vector3(4.5, 0.05, -58), -90.0, "Garage", 10.5], [Vector3(-4.5, 0.05, 22), 90.0, "Church", -12.0]]:
		await _teleport(p, spec[0])
		p.rotation_degrees.y = spec[1]
		var w := InputFrame.new()
		w.move = Vector2(0, -1)
		await _run(p, 150, w)
		var inside: bool = p.global_position.x < spec[3] if spec[1] > 0 else p.global_position.x > spec[3]
		check(inside, "walked into the %s (x=%.1f)" % [spec[2], p.global_position.x])
	await _unload(town)


func test_camp_spawns_veterans_inside() -> void:
	var town := await _load(HALDENS_PATH, true)
	await wait_physics(10)
	var vets := 0
	var basics := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		var r := n as Raider
		if r == null or not town.is_ancestor_of(r):
			continue
		if r.display_name == "Raider Veteran":
			vets += 1
			var at := r.global_position
			check(at.x > 26 and at.x < 62 and at.z > 12 and at.z < 52, "veteran inside the camp (%s)" % at)
		else:
			basics += 1
	check(vets == 4, "4 veterans in the camp (%d)" % vets)
	check(basics == 3, "3 raiders roaming the town (%d)" % basics)
	await _unload(town)
