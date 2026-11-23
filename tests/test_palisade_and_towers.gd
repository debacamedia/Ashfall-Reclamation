extends "res://tests/fortify_helpers.gd"
## Increment 27.1: the mine's palisade, and what comes after it.
##
## Black Ridge Mine's wall is a palisade (tall sharpened stakes patched with
## scrap) with a palisade gate, not a split-rail fence. Once a place's first
## defences are built, the next stage is laid out by itself: watchtowers at
## all three places (a guard up there sees over the wall), and at the mine the
## palisade reinforced with scrap, length by length where it stands. A save
## from 27 gets the palisade in place of its fence. And the gates' leaves now
## really move: open, you can walk through.


const FIXTURE_27 := "res://tests/fixtures/save_27.json"


func _built(st: Settlement, id: StringName) -> Array:
	return get_tree().get_nodes_in_group("settlement_buildings").filter(
		func(b: Node) -> bool: return not b.is_queued_for_deletion() and (b as SettlementBuilding).settlement() == st and (b as Structure).definition.id == id)


func _finish(st: Settlement, keys: Array) -> void:
	for site in st.sites():
		if keys.is_empty() or keys.has(site.key):
			site.delivered = site.total_cost().duplicate()
			site.add_work(site.total_hours())
	await wait_physics(4)


func test_the_palisade_and_its_gate() -> void:
	for row: Array in [[&"palisade", 600.0, 0.3, {&"wood_plank": 2, &"scrap_metal": 1}],
			[&"reinforced_palisade", 1200.0, 0.3, {&"scrap_metal": 3, &"wood_plank": 1}],
			[&"palisade_gate", 1400.0, 2.0, {&"wood_plank": 10, &"scrap_metal": 6}]]:
		var def := SettlementPlans.structure(row[0])
		check(def != null and def.max_health == row[1] and is_equal_approx(SettlementPlans.hours(row[0]), row[2]) and SettlementPlans.cost(row[0]) == row[3],
			"%s: %d health, %s, %.1f h a length" % [row[0], row[1], row[3], row[2]])
		var scene := (load(def.scene_path) as PackedScene).instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() <= 6 if row[0] == &"palisade_gate" else meshes.size() == 1, "%s: drawn as few meshes (%d), a surface per material" % [row[0], meshes.size()])
		scene.free()
	check(SettlementPlans.replaces(&"palisade").has(&"farm_fence") and SettlementPlans.replaces(&"reinforced_palisade").has(&"palisade")
		and SettlementPlans.replaces(&"palisade_gate").has(&"settlement_gate"), "each takes the place of what it improves on")
	check(SettlementPlans.upgrades_of(&"palisade") == [&"reinforced_palisade"], "the palisade's upgrade: the reinforced palisade")
	# Tall and solid: in the way at 2.2 m, all along
	var zone := await load_zone()
	var p := Node3D.new()
	zone.add_child(p)
	var wall := (load("res://scenes/settlement/palisade.tscn") as PackedScene).instantiate() as Structure
	p.add_child(wall)
	wall.global_position = Vector3(120, 0, 60)
	await wait_physics(3)
	var space := zone.get_world_3d().direct_space_state
	var hits := 0
	for x in [-1.9, -1.0, 0.0, 1.0, 1.9]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(120 + x, 2.2, 63), Vector3(120 + x, 2.2, 57), PhysicsLayers.STRUCTURES)
		if not space.intersect_ray(q).is_empty():
			hits += 1
	check(hits == 5, "a palisade length is solid 2.2 m up, end to end (%d of 5)" % hits)
	await _free(zone)


## The 27.1 fix: the leaves' collision follows them when they swing.
func test_gates_open_to_walk_through() -> void:
	var zone := await load_zone()
	var nw := _place(zone, "NorthwatchOutpost")
	var mine := _place(zone, "BlackRidgeMine")
	var p := _player(zone)
	await _claim(zone, nw)
	await _claim(zone, mine)
	await _finish(nw, ["Gate"])
	await _finish(mine, ["MineGate"])
	for st: Settlement in [nw, mine]:
		var g := _gate_of(st)
		var line := g.global_transform
		var outside := line * Vector3(0.5, 0.1, 3.0)
		var through := line.basis * Vector3(0, 0, -6.0)
		p.global_position = AWAY
		await wait_physics(30)
		check(not g.is_open and p.test_move(Transform3D(p.global_basis, outside), through), "%s's %s, shut: you can't walk through" % [st.settlement_name, g.definition.display_name.to_lower()])
		p.global_position = outside
		await wait_physics(60)
		check(g.is_open, "you walk up: it opens")
		check(not p.test_move(Transform3D(p.global_basis, outside), through), "and you can walk through (the leaves really move)")
		var leaf := g.get_node("%LeafL/Leaf") as CollisionObject3D
		check(not (leaf as AnimatableBody3D).sync_to_physics, "its leaves follow their hinges")
	await _free(zone)


func test_the_defences_come_in_stages() -> void:
	var zone := await load_zone()
	var mine := _place(zone, "BlackRidgeMine")
	var farm := _place(zone, "AshCreekFarms")
	var nw := _place(zone, "NorthwatchOutpost")
	var notices: Array[String] = []
	mine.notice.connect(func(t: String) -> void: notices.append(t))
	await _claim(zone, mine)
	check(mine.defence_stage == 1 and mine.save_state()["defence_stage"] == 1 and mine.save_state()["defences_version"] == 2, "first stage laid out, saved")
	# All but the last of the first stage: nothing more yet
	var keys := _keys(mine).filter(func(k: String) -> bool: return k != "MineGatePostS")
	await _finish(mine, keys)
	check(mine.defence_stage == 1 and _keys(mine) == ["MineGatePostS"], "one site of the first stage left: the next waits")
	await _finish(mine, [])
	keys = _keys(mine)
	check(mine.defence_stage == 2, "the first stage built: the second laid out by itself")
	for k in ["MineTowerGateN", "MineTowerGateS", "MineTowerNorthwest", "MineTowerSouthwest", "MineReinforceEastS", "MineReinforceEastN", "MineReinforceNorth", "MineReinforceWest", "MineReinforceSouth"]:
		check(keys.has(k), "%s planned" % k)
	check(keys.find("MineTowerGateN") < keys.find("MineReinforceEastS"), "the towers first")
	check(notices.any(func(t: String) -> bool: return t.contains("defences are built") and t.contains("watchtower") and t.contains("reinforced palisade")),
		"a notice says what's next: %s" % [notices.filter(func(t: String) -> bool: return t.contains("defences"))])
	var east := mine.sites().filter(func(s: ConstructionSite) -> bool: return s.key == "MineReinforceEastS")[0] as ConstructionSite
	check(east.total_cost() == {&"scrap_metal": 15, &"wood_plank": 5}, "reinforcing takes more scrap: 15 for the 5 lengths of the east side's south end (%s)" % east.total_cost())
	# Reinforced where it stands
	var before := _built(mine, &"palisade").size()
	var spots := east.pieces.map(func(t: Transform3D) -> Vector3: return (east.global_transform * t).origin)
	await _finish(mine, ["MineReinforceEastS"])
	await wait_physics(3)
	var reinforced := _built(mine, &"reinforced_palisade")
	check(_built(mine, &"palisade").size() == before - 5 and reinforced.size() == 5, "5 lengths reinforced: 5 palisade lengths fewer (%d → %d)" % [before, _built(mine, &"palisade").size()])
	check(reinforced.all(func(r: Node3D) -> bool: return spots.any(func(at: Vector3) -> bool: return at.distance_to(r.global_position) < 0.1)), "each just where the palisade stood")
	# One broken: it's rebuilt reinforced
	(reinforced[0] as Structure).apply_damage(100000.0, null)
	await wait_physics(3)
	check(mine.sites().any(func(s: ConstructionSite) -> bool: return s.key.begins_with("Rebuild") and s.plan_id == &"reinforced_palisade"), "broken, a reinforced length goes back on the list as one")
	# And the third stage? There's none: the next is up to you
	check(mine.save_state()["defence_stage"] == 2, "saved at the second stage")
	# The other places: watchtowers after their gates
	await _claim(zone, farm)
	await _claim(zone, nw)
	await _finish(farm, [])  # (28: everything at the farm, not just its gates)
	await _finish(nw, [])
	check(farm.defence_stage == 2 and _keys(farm).has("TowerFrontLeft") and _keys(farm).has("TowerFrontRight"), "Ash Creek: its gates (and the rest) built, then two watchtowers by the front gate")
	check(nw.defence_stage == 2 and _keys(nw).has("TowerGateW") and _keys(nw).has("TowerGateE"), "Northwatch: its gate built, then a watchtower either side")
	await _free(zone)


func test_watchtowers_see_over_the_wall() -> void:
	var zone := await load_zone()
	var mine := _place(zone, "BlackRidgeMine")
	var farm := _place(zone, "AshCreekFarms")
	var nw := _place(zone, "NorthwatchOutpost")
	for st in [mine, farm, nw]:
		await _claim(zone, st)
		await _finish(st, [])
		await _finish(st, [])
	await wait_physics(10)
	var towers := []
	for st in [mine, farm, nw]:
		towers.append_array(_built(st, &"watchtower"))
	check(towers.size() == 8, "eight watchtowers built: 4 at the mine, 2 at Ash Creek, 2 at Northwatch (%d)" % towers.size())
	# Nothing in their way where they stand
	var space := zone.get_world_3d().direct_space_state
	for t: Structure in towers:
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 2.0, t.definition.footprint.z - 0.3)
		q.shape = box
		q.transform = t.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, -1.7 + (t.definition.footprint.z - 0.3) / 2.0 - 1.5))
		q.collision_mask = PhysicsLayers.STRUCTURES
		q.exclude = [(t.get_node("Body") as CollisionObject3D).get_rid()]
		var hits := space.intersect_shape(q, 4).map(func(h: Dictionary) -> String: return str((h["collider"] as Node).get_parent().name) + "/" + str((h["collider"] as Node).name))
		check(hits.is_empty(), "%s at %s: clear of everything (%s)" % [t.definition.display_name, (t.settlement() as Settlement).settlement_name, hits])
	# A guard up the mine's gate tower sees a raider at the shut gate; one on
	# the ground doesn't
	mine.store.inventory.add_item(VEG, 30)
	var guard := await _newcomer(mine, Settler.Role.GUARD)
	guard.set_physics_process(false)
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.set_physics_process(false)
	r.global_position = mine.to_global(Vector3(44.8, 0, 13))
	var tower := towers.filter(func(t: Structure) -> bool: return mine.to_local(t.global_position).distance_to(Vector3(40.4, 0, 0.5)) < 0.5)[0] as SettlementBuilding
	guard.global_position = tower.guard_spots()[0].global_position + Vector3.UP * 0.05
	await wait_physics(3)
	check(guard._can_see(r), "on the mine's gate tower: a guard sees the raider at the gate, over the palisade")
	r.global_position = mine.to_global(Vector3(44.8, 0, -10))
	await wait_physics(2)
	check(guard._can_see(r), "and one at the foot of the wall further along")
	guard.global_position = mine.to_global(Vector3(40, 0.1, 13))
	r.global_position = mine.to_global(Vector3(44.8, 0, 13))
	await wait_physics(3)
	check(not guard._can_see(r), "on the ground inside: the wall hides it")
	await _free(zone)


func test_guards_climb_the_watchtowers() -> void:
	var zone := await load_zone()
	var nw := _place(zone, "NorthwatchOutpost")
	await _claim(zone, nw)
	await _finish(nw, [])
	await _finish(nw, [])
	await _wait_nav(zone)
	check(_built(nw, &"watchtower").size() == 2, "Northwatch's two watchtowers up")
	check(nw.guard_posts().size() == 2 and nw.guard_posts()[0].global_position.y > 3.0, "the towers' spots come first")
	nw.store.inventory.add_item(VEG, 40)
	var a := await _newcomer(nw, Settler.Role.GUARD)
	var b := await _newcomer(nw, Settler.Role.GUARD)
	# (28.1: towers go to guards with a gun)
	var rifle: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")
	a.arm(rifle, 30)
	b.arm(rifle, 30)
	var up := 0
	for i in 2400:
		await wait_physics(1)
		up = [a, b].filter(func(s: Settler) -> bool: return s.global_position.y > 3.2).size()
		if up == 2:
			break
	check(up == 2, "both guards climb a watchtower each (%s, %s)" % [nw.to_local(a.global_position), nw.to_local(b.global_position)])
	check(a.global_position.distance_to(b.global_position) > 5.0, "one to each tower")
	await _free(zone)


func test_a_27_save_gets_the_palisade() -> void:
	var zone := await load_zone()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	DirAccess.copy_absolute(FIXTURE_27, TEST_DIR + "/fixture27.json")
	check(saves.load_game("fixture27", zone) == OK, "loaded a save from Increment 27")
	await wait_physics(10)
	var mine := Settlement.find(get_tree(), &"black_ridge")
	var farm := Settlement.find(get_tree(), &"ash_creek")
	var by_key := {}
	for s in mine.sites():
		by_key[s.key] = s
	check(mine.defences_version == 2 and mine.defence_stage == 1, "brought up to date (version 2), still at the first stage")
	for k in ["MineFenceEastS", "MineFenceEastN", "MineFenceNorth", "MineFenceWest", "MineFenceSouth"]:
		check(by_key.has(k) and (by_key[k] as ConstructionSite).plan_id == &"palisade", "%s: a palisade to build in place of the fence" % k)
	check(by_key.has("MineGate") and (by_key["MineGate"] as ConstructionSite).plan_id == &"palisade_gate", "and a palisade gate in place of the gate")
	check(by_key.has("MineGatePostS") and (by_key["MineGatePostS"] as ConstructionSite).plan_id == &"guard_post", "the unbuilt guard post left as it was")
	check(mine.store.inventory.count_of(&"wood_plank") >= 22, "what was handed over for the fence back in the stores (%d planks)" % mine.store.inventory.count_of(&"wood_plank"))
	var fences := _built(mine, &"farm_fence").size()
	check(fences == 11 and _built(mine, &"settlement_gate").size() == 1, "the fence lengths and the gate built in 27 still stand till they're replaced (%d)" % fences)
	check(not farm.sites().any(func(s: ConstructionSite) -> bool: return s.plan_id == &"palisade"), "Ash Creek keeps its own fences")
	await _finish(mine, ["MineFenceEastS", "MineGate"])
	check(_built(mine, &"farm_fence").size() == fences - 5 and _built(mine, &"palisade").size() == 5, "the palisade built: 5 fence lengths gone, 5 of palisade")
	check(_built(mine, &"settlement_gate").is_empty() and _built(mine, &"palisade_gate").size() == 1, "and the palisade gate in place of the old one")
	await _free(zone)
