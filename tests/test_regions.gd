extends "res://tests/test_case.gd"
## Increment 12: regions and travel (WorldManager, RegionExit, saves with
## other regions) and Halden's Crossing (ruined town + raider camp).
##
## Since Increment 15 the outpost and the town are sites in one zone, walked
## between rather than travelled between. Travel between regions is still
## how zones will join (Increment 16), so it's tested here on two small
## fixture regions (tests/fixtures/region_a.tscn, region_b.tscn). The town
## is tested where it now stands in the early zone.

const REGION_A := "res://tests/fixtures/region_a.tscn"
const REGION_B := "res://tests/fixtures/region_b.tscn"
const DT := 1.0 / 60.0

var RIFLE: WeaponDefinition = load("res://resources/items/weapons/service_rifle.tres")


func _wm() -> Node:
	return get_node("/root/WorldManager")


func _sm() -> Node:
	return get_node("/root/SaveManager")


func _load(path: String) -> Node3D:
	var lvl := (load(path) as PackedScene).instantiate() as Node3D
	var p := lvl.get_node("Player") as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	add_child(lvl)
	await wait_physics(10)
	return lvl


## The early zone with the player standing in Halden's Crossing (so the
## town's spawners are awake when `raiders` is on).
func _town_zone(raiders := false) -> Node3D:
	var zone := instance_zone(["HaldensCrossing"] if raiders else [])
	(zone.get_node("Player") as Node3D).position = HALDENS_AT + Vector3(0, 0.05, -90)
	add_child(zone)
	await wait_physics(30)
	await wait_for_navigation(zone.get_world_3d().navigation_map)
	return zone


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

func test_regions_link_both_ways() -> void:
	var a := (load(REGION_A) as PackedScene).instantiate()
	var b := (load(REGION_B) as PackedScene).instantiate()
	check(_wm().region_name_of(a) == "Region A" and _wm().region_name_of(b) == "Region B", "region names")
	for pair in [[a, b, REGION_B], [b, a, REGION_A]]:
		var exits: Array = pair[0].get_node("Exits").get_children()
		check(exits.size() == 1, "%s has a road out" % pair[0].name)
		var exit := exits[0] as RegionExit
		check(exit.target_level == pair[2], "%s: leads to %s" % [pair[0].name, exit.target_level])
		check(_wm().find_arrival(pair[1], exit.arrival_id) != null
			and _wm().find_arrival(pair[1], exit.arrival_id).name == String(exit.arrival_id),
			"%s: arrival %s exists" % [pair[0].name, exit.arrival_id])
	a.free()
	b.free()
	# The zone names its places for the compass; it has no road out yet
	var zone := instance_zone()
	check(_wm().region_name_of(zone) == "Early Zone", "zone name: %s" % _wm().region_name_of(zone))
	check(_wm().region_name_of(zone.get_node("HaldensCrossing")) == "Halden's Crossing", "town keeps its name")
	check(zone.get_node_or_null("Exits") == null and zone.get_node("HaldensCrossing").get_node_or_null("Exits") == null, "no road signs: you walk between the places")
	zone.free()


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
	var a := await _load(REGION_A)
	var p := _player(a)
	p.give_weapon(RIFLE)
	p.inventory.add_item(ItemDatabase.get_item(&"electronics"), 3)
	p.health.apply_damage(DamageInfo.create(37.0, DamageInfo.Type.FALL))
	# Loot A a little: take a pickup, search the crate
	a.get_node("Loot/Scrap").free()
	var crate := a.get_node("SalvageContainers/Crate") as SalvageContainer
	crate.search()
	var crate_contents := crate.inventory.to_data()
	var carried: Dictionary = _wm().capture_region(a)
	check(not carried.is_empty(), "player data carried")
	check(_wm().region_states.has(REGION_A), "A's state kept")
	await _unload(a)

	var b := await _load(REGION_B)
	_wm().enter_region(b, carried, &"FromA")
	await wait_physics(3)
	p = _player(b)
	check(p.global_position.distance_to((b.get_node("Arrivals/FromA") as Node3D).global_position) < 0.5, "arrived at the road in (%s)" % p.global_position)
	check(p.weapon_slots.get_weapon(1) != null and p.weapon_slots.get_weapon(1).base_definition == RIFLE, "rifle carried")
	check(p.weapon_slots.get_weapon(5) != null, "machete carried")
	check(p.inventory.count_of(&"electronics") == 3, "inventory carried")
	check_near(p.health.current_health, 63.0, 0.01, "health carried")
	# Loot B
	b.get_node("Loot/Cloth").free()
	var pile := b.get_node("SalvagePiles/Pallet") as SalvagePile
	pile._perform(p)
	carried = _wm().capture_region(b)
	await _unload(b)

	a = await _load(REGION_A)
	_wm().enter_region(a, carried, &"FromB")
	await wait_physics(3)
	p = _player(a)
	check(p.global_position.distance_to((a.get_node("Arrivals/FromB") as Node3D).global_position) < 0.5, "back at A's road in")
	check(a.get_node_or_null("Loot/Scrap") == null, "the pickup you took is still gone")
	crate = a.get_node("SalvageContainers/Crate") as SalvageContainer
	check(crate.is_searched and crate.inventory.to_data() == crate_contents, "the crate is searched, same contents")
	check(p.inventory.count_of(&"wood") == 3, "the pallet's wood came with you")
	carried = _wm().capture_region(a)
	await _unload(a)

	b = await _load(REGION_B)
	_wm().enter_region(b, carried, &"FromA")
	await wait_physics(3)
	check(b.get_node_or_null("Loot/Cloth") == null, "B remembers too")
	check(b.get_node_or_null("SalvagePiles/Pallet") == null, "broken pallet stays gone")
	check(b.get_node_or_null("Loot/Scrap") != null, "untouched loot is still there")
	await _unload(b)
	_wm().reset()


func test_travel_refusals() -> void:
	_wm().reset()
	var a := await _load(REGION_A)
	var p := _player(a)
	var exit := a.get_node("Exits/RoadToB") as RegionExit
	check(_wm().travel_refusal_reason(p, exit) == "", "allowed normally")
	check(exit.get_prompt(p) == "Follow the road to Region B", "prompt: %s" % exit.get_prompt(p))
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
	a.add_child(raider)
	await wait_physics(2)
	raider.alert_to(p)
	await wait_physics(2)
	check(_wm().travel_refusal_reason(p, exit) == "Raiders are on your tail", "not with a raider chasing: '%s'" % _wm().travel_refusal_reason(p, exit))
	raider.queue_free()
	await wait_physics(2)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	check(_wm().travel_refusal_reason(p, exit) == "Can't travel now", "not while dead")
	await _unload(a)


func test_hold_e_at_the_sign_really_travels() -> void:
	# End to end through the real scene change: A becomes the current
	# scene, the player holds E at the road sign.
	_wm().reset()
	var a := (load(REGION_A) as PackedScene).instantiate() as Node3D
	var p := _player(a)
	p.controlled_locally = false
	get_tree().root.add_child(a)
	get_tree().current_scene = a
	await wait_physics(20)
	p.inventory.add_item(ItemDatabase.get_item(&"electronics"), 2)
	var exit := a.get_node("Exits/RoadToB") as RegionExit
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
	check(started == ["Region B"], "travel started: %s" % [started])
	for i in 300:
		await get_tree().process_frame
		if not arrived.is_empty():
			break
	check(arrived == ["Region B"], "arrived: %s" % [arrived])
	var b := get_tree().current_scene
	check(b != null and b.scene_file_path == REGION_B, "Region B is the current scene")
	if b != null and b.scene_file_path == REGION_B:
		var p2 := _player(b)
		check(p2.global_position.distance_to((b.get_node("Arrivals/FromA") as Node3D).global_position) < 0.6, "at the road in")
		check(p2.inventory.count_of(&"electronics") == 2, "inventory came along")
		check(not p2.player_input.ui_open, "controls handed back after the fade")
		check(_wm().region_states.has(REGION_A), "A remembered")
	get_tree().unload_current_scene()
	await wait_physics(3)
	_wm().reset()


func test_save_and_load_remembers_the_other_region() -> void:
	_wm().reset()
	_sm().save_dir = "user://test_saves_regions"
	var a := await _load(REGION_A)
	a.get_node("Loot/Scrap").free()
	var carried: Dictionary = _wm().capture_region(a)
	await _unload(a)
	var b := await _load(REGION_B)
	_wm().enter_region(b, carried, &"FromA")
	var p := _player(b)
	await _teleport(p, Vector3(-12, 0.05, 2))
	check(_sm().save_game("regions_test", b) == OK, "saved in B")
	var data: Dictionary = _sm().read_save_file(_sm().slot_path("regions_test"))
	check(int(data.get("version")) == 4 and data.get("level") == REGION_B, "version 4, B's level")
	check((data.get("regions") as Dictionary).has(REGION_A), "A's state is in the save")
	# Forget everything, then load
	_wm().reset()
	await _teleport(p, Vector3(0, 0.05, -15))
	check(_sm().load_game("regions_test", b) == OK, "loaded")
	check(p.global_position.distance_to(Vector3(-12, 0.05, 2)) < 0.3, "position restored in B")
	check(_wm().region_states.has(REGION_A), "A's state restored from the save")
	await _unload(b)
	a = await _load(REGION_A)
	_wm().enter_region(a, {}, &"FromB")
	check(a.get_node_or_null("Loot/Scrap") == null, "and applied when you go back")
	await _unload(a)
	# A version-1 save still loads (no regions)
	var v1 := {"format": "ashfall_save", "version": 1, "level": REGION_A, "nodes": []}
	check(_sm().validate(v1) == "", "v1 accepted")
	check(_sm()._migrate(v1).get("regions") == {} and int(v1["version"]) == 4, "v1 migrated")
	_sm().delete_save("regions_test")
	_sm().save_dir = "user://saves"
	_wm().reset()


# ---------------------------------------------------------------- the town

func test_town_containers_clear_on_the_ground_and_searchable() -> void:
	var zone := await _town_zone()
	var town := zone.get_node("HaldensCrossing") as Node3D
	var p := _player(zone)
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
	await _unload(zone)


func test_every_ground_container_reachable_on_foot() -> void:
	var zone := await _town_zone()
	var town := zone.get_node("HaldensCrossing") as Node3D
	var map := town.get_world_3d().navigation_map
	# From the main road where it comes in from Outpost 17 (the south end)
	var start := NavigationServer3D.map_get_closest_point(map, HALDENS_AT + Vector3(0, 0, 100))
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
			"%s reachable from the main road (path ends %s, goal %s)" % [c.name, path[path.size() - 1] if path.size() > 0 else "-", goal])
	check(high == 3, "3 stashes up high: hotel roof, hotel upstairs, water tower (%d)" % high)
	await _unload(zone)


func test_salvage_and_pickups_placed_sensibly() -> void:
	var zone := await _town_zone()
	var town := zone.get_node("HaldensCrossing") as Node3D
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
		var hits := space.intersect_shape(q, 4).filter(func(h: Dictionary) -> bool: return (h["collider"] as CollisionObject3D).collision_layer != PhysicsLayers.TERRAIN)
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
	await _unload(zone)


func test_climb_to_the_sightlines() -> void:
	var zone := await _town_zone()
	var town := zone.get_node("HaldensCrossing") as Node3D
	var p := _player(zone)
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
	await _unload(zone)


func test_walk_in_through_doors() -> void:
	var zone := await _town_zone()
	var p := _player(zone)
	# [start on the street, facing yaw, building, interior point]
	for spec in [[Vector3(-4.5, 0.05, -60), 90.0, "GeneralStore", -11.5], [Vector3(-4.5, 0.05, -22), 90.0, "Hotel", -10.5],
			[Vector3(4.5, 0.05, -58), -90.0, "Garage", 10.5], [Vector3(-4.5, 0.05, 22), 90.0, "Church", -12.0]]:
		await _teleport(p, HALDENS_AT + spec[0])
		p.rotation_degrees.y = spec[1]
		var w := InputFrame.new()
		w.move = Vector2(0, -1)
		await _run(p, 150, w)
		var x := p.global_position.x - HALDENS_AT.x  # in the town's own coordinates
		var inside: bool = x < spec[3] if spec[1] > 0 else x > spec[3]
		check(inside, "walked into the %s (x=%.1f)" % [spec[2], x])
	await _unload(zone)


func test_camp_spawns_veterans_inside() -> void:
	var zone := await _town_zone(true)
	var town := zone.get_node("HaldensCrossing") as Node3D
	await wait_physics(10)
	var vets := 0
	var basics := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		var r := n as Raider
		if r == null or not town.is_ancestor_of(r):
			continue
		if r.display_name == "Raider Veteran":
			vets += 1
			var at := r.global_position - HALDENS_AT  # in the town's own coordinates
			check(at.x > 26 and at.x < 62 and at.z > 12 and at.z < 52, "veteran inside the camp (%s)" % at)
		else:
			basics += 1
	check(vets == 4, "4 veterans in the camp (%d)" % vets)
	check(basics == 3, "3 raiders roaming the town (%d)" % basics)
	await _unload(zone)
