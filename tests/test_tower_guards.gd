extends "res://tests/fortify_helpers.gd"
## Increment 28.1: guards hold their towers.
##
## From the user's playtest at the mine: six raiders, three guards up the
## watchtowers; the guards came down, went out through the palisade and were
## killed. Now a guard up a tower stays there and shoots from it, seeing
## further (60 m) and along the wall it stands against, with a steadier aim;
## guards on the ground stay on their side of the walls; nobody's moved
## through a wall when stuck; guards shoot a quarter faster; and raids
## settled on paper have the raiders break the gate first, under fire from
## the towers.

var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")
var SHOTGUN_W: WeaponDefinition = load("res://resources/items/weapons/shotgun.tres")
var RIFLE_W: WeaponDefinition = load("res://resources/items/weapons/service_rifle.tres")


func _walled_mine(zone: Node3D) -> Settlement:
	var mine := _place(zone, "BlackRidgeMine")
	await _claim(zone, mine)
	mine.away_range = 100000.0
	await _finish_sites(mine)
	await _finish_sites(mine)
	await _wait_nav(zone)
	mine.store.inventory.add_item(VEG, 200)
	return mine


func _raider(zone: Node3D, at: Vector3, frozen := true) -> Raider:
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = at
	if frozen:
		r.set_physics_process(false)
	return r


func _tower(mine: Settlement, local: Vector3) -> SettlementBuilding:
	for b in mine.buildings():
		if b.definition.id == &"watchtower" and mine.to_local(b.global_position).distance_to(local) < 0.6:
			return b
	return null


func test_shooting_faster_and_from_towers() -> void:
	check_near(Settler.shot_interval(RIFLE_W), 0.36, 0.001, "a guard's rifle: a shot every 0.36 s (was 0.45)")
	check_near(Settler.shot_interval(SHOTGUN_W), 60.0 / SHOTGUN_W.rounds_per_minute / 1.25, 0.001, "the shotgun a quarter faster too")
	# On paper the same, and a steadier aim from a tower
	var ground: Array = RaidOnPaper.shot_odds(RIFLE_W, false)
	var up: Array = RaidOnPaper.shot_odds(RIFLE_W, true)
	check(float(up[0]) > float(ground[0]), "from a tower a shot lands more often (%.2f against %.2f)" % [up[0], ground[0]])
	var paper := RaidOnPaper.new(5)
	paper.add_raider("r", 100000.0, 0.0, 1.25)
	paper.add_guard("g", 100.0, RIFLE_W, 30, 300)
	paper.run()
	# 400 s at most; reloads aside, a rifle's 0.36 s
	check(paper.guards[0].shots > 300, "on paper a rifle fires at the new rate (%d shots)" % paper.guards[0].shots)


func test_guards_hold_the_towers_in_a_raid() -> void:
	var zone := await load_zone()
	var mine := await _walled_mine(zone)
	var guards: Array[Settler] = []
	for i in 3:
		var g := await _newcomer(mine, Settler.Role.GUARD)
		g.arm(RIFLE, 120)
		guards.append(g)
	for i in 5:
		await _newcomer(mine, Settler.Role.MINER)
	for i in 6000:
		await wait_physics(1)
		if guards.all(func(s: Settler) -> bool: return s.up_tower()):
			break
	check(guards.all(func(s: Settler) -> bool: return s.up_tower()), "all three guards up a watchtower each")
	check(mine.tower_guards().size() == 3, "the settlement counts three guards up towers")
	# The playtest's raid: six of them, up the road to the gate
	mine.warn_raid(0.0)
	var road := mine.get_node("RaidPoints").get_child(0) as Node3D
	mine.raid_from = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, road.global_position)
	check(mine.raid_size == 6, "a raid of six (%d)" % mine.raid_size)
	mine.start_raid()
	var inside := mine.store.global_position + Vector3.UP
	var off := 0
	var out := 0
	var t := 0
	while mine.raid_active() and t < 240:
		await wait_physics(60)
		t += 1
		for g in guards:
			if not g.up_tower() and not g.is_down():
				off += 1
			if g.wall_between(g.global_position + Vector3.UP, inside):
				out += 1
	var rep := mine.raid_report
	check(off == 0, "nobody came down from their tower (%d guard-seconds off one)" % off)
	check(out == 0, "nobody went out through the walls")
	check(int(rep["killed"]) >= 5, "the towers killed the raiders (%s)" % rep)
	check((rep["wounded"] as Array).is_empty(), "and none of the guards went down")
	await _free(zone)


func test_towers_see_further_and_along_their_wall() -> void:
	var zone := await load_zone()
	var mine := await _walled_mine(zone)
	var guard := await _newcomer(mine, Settler.Role.GUARD)
	guard.arm(RIFLE, 60)
	for i in 6000:
		await wait_physics(1)
		if guard.up_tower():
			break
	check(guard.up_tower(), "the guard up a tower")
	check_near(guard.sight_range(), 60.0, 0.01, "up a tower: sees 60 m (40 on the ground)")
	guard.set_physics_process(false)
	# On the gate tower: raiders anywhere along that side's wall, at its foot
	var tower := _tower(mine, Vector3(40.4, 0, 0.5))
	guard.global_position = tower.guard_spots()[0].global_position + Vector3.UP * 0.05
	guard._spot = tower.guard_spots()[0]
	await wait_physics(3)
	var seen := 0
	var by_wall := 0
	var tried := 0
	for z in range(-40, 44, 6):
		var r := _raider(zone, mine.to_global(Vector3(44.9, 0, z)))
		await wait_physics(2)
		tried += 1
		if guard.sees(r):
			seen += 1
			if not guard._can_see(r):
				by_wall += 1
		r.queue_free()
	check(seen == tried, "a raider anywhere along the wall the tower stands against is seen (%d of %d; %d only past the wall)" % [seen, tried, by_wall])
	# Right down at the wall's foot, below the line over its top: the wall
	# itself doesn't count against a tower's view
	var wall_x := -INF
	for b in mine.buildings():
		if b.definition.id in Settler.WALL_IDS and b.global_position.distance_to(tower.global_position) < 6.0:
			wall_x = maxf(wall_x, mine.to_local(b.global_position).x)
	var foot := mine.to_global(Vector3(wall_x + 0.45, 0.1, -3))
	var plain := zone.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(guard.eyes.global_position, foot, PhysicsLayers.WORLD_SOLID, [guard.get_rid()]))
	check(not plain.is_empty() and Structure.from_collider(plain["collider"]) != null, "a sight line to the very foot of the wall runs into its top")
	check(guard._clear_but_walls(guard.eyes.global_position, foot), "but from the tower it's seen past the wall")
	check(guard._on_my_wall(foot) and not guard._on_my_wall(mine.to_global(Vector3(20, 0, -8))), "along its wall, not across the yard")
	# 60 m from up there: a raider far along the wall is picked out
	var far := _raider(zone, mine.to_global(Vector3(44.9, 0, -48)))
	await wait_physics(2)
	var d := guard.global_position.distance_to(far.global_position)
	check(d > 45.0 and guard._find_raider() == far, "a raider %.0f m off along the wall is picked out from the tower" % d)
	far.queue_free()
	# Shot from up there, over the palisade, not into it
	var r2 := _raider(zone, mine.to_global(Vector3(44.9, 0, -25)))
	await wait_physics(2)
	var h := HealthComponent.find_on(r2)
	var before := h.current_health
	var walls := mine.buildings().filter(func(b: SettlementBuilding) -> bool: return b.definition.id in Settler.WALL_IDS)
	var wall_health: float = walls.reduce(func(a: float, b: SettlementBuilding) -> float: return a + b.health, 0.0)
	for i in 30:
		guard._cooldown = 0.0
		guard._shoot(r2)
		await wait_physics(1)
	check(h.current_health < before, "shots from the tower hit the raider at the wall's foot (%.0f → %.0f)" % [before, h.current_health])
	check_near(walls.reduce(func(a: float, b: SettlementBuilding) -> float: return a + b.health, 0.0), wall_health, 0.01, "and never their own palisade")
	# On the ground inside, a raider the far side of the palisade isn't seen
	guard._spot = null
	guard.global_position = mine.to_global(Vector3(40, 0.1, 13))
	r2.global_position = mine.to_global(Vector3(44.9, 0, 13))
	await wait_physics(3)
	check(not guard.sees(r2) and guard.sight_range() == 40.0, "on the ground: the wall hides it, and 40 m")
	await _free(zone)


func test_ground_guards_stay_inside_the_walls() -> void:
	var zone := await load_zone()
	var mine := await _walled_mine(zone)
	# No gun: no tower for them, and a machete
	var guard := await _newcomer(mine, Settler.Role.GUARD)
	for i in 600:
		await wait_physics(1)
	check(not guard.holds_tower(), "a guard with no gun isn't sent up a tower")
	mine.warn_raid(0.0)
	mine.start_raid()
	for r in mine.raiders:
		(r as Raider).set_physics_process(false)
		r.global_position = mine.to_global(Vector3(52, 0.1, 6 + mine.raiders.find(r) * 1.5))
	await wait_physics(5)
	var outside_r := mine.raiders[0] as Raider
	check(guard.across_walls(outside_r.global_position), "a raider outside the palisade is across the walls")
	var inside := mine.store.global_position + Vector3.UP
	var out := 0
	for i in 20:
		await wait_physics(60)
		if guard.wall_between(guard.global_position + Vector3.UP, inside):
			out += 1
	check(out == 0, "the guard stays inside, not out through the gate after them")
	# One gets in: the guard goes for it
	var r := mine.raiders[0] as Raider
	# (somewhere inside well away from the guard: by the stores, or the board)
	var spots := [mine.store.global_position + mine.store.global_basis.z * 2.5, mine.claim_point.global_position]
	spots.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.distance_to(guard.global_position) > y.distance_to(guard.global_position))
	r.global_position = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, spots[0]) + Vector3.UP * 0.1
	var start := guard.global_position.distance_to(r.global_position)
	for i in 600:
		await wait_physics(1)
		if guard.global_position.distance_to(r.global_position) < 3.0:
			break
	check(guard.global_position.distance_to(r.global_position) < start - 5.0, "a raider inside: the guard goes after it (%.0f m → %.0f m)" % [start, guard.global_position.distance_to(r.global_position)])
	await _free(zone)


func test_nobody_hops_through_a_wall() -> void:
	var zone := await load_zone()
	var mine := await _walled_mine(zone)
	var s := await _newcomer(mine, Settler.Role.MINER)
	s.set_physics_process(false)
	var gate := _gate_of(mine)
	gate.set_physics_process(false)  # it stays shut
	# Just inside the shut gate, told to go just outside: the path runs
	# through it, and pressed against it they'd once have been popped through
	var inward := (mine.global_position - gate.global_position)
	inward.y = 0.0
	inward = inward.normalized()
	s.global_position = gate.global_position + inward * 1.0 + Vector3.UP * 0.1
	var outside := gate.global_position - inward * 2.0
	s.set_physics_process(true)
	s.state = Settler.State.LEAVING
	s._goal = outside
	s._state_time = -100.0
	var crossed := false
	for i in 600:
		await wait_physics(1)
		if (s.global_position - gate.global_position).dot(inward) < -0.3:
			crossed = true
			break
	check(not crossed, "stuck at a shut gate, a settler isn't moved through it")
	await _free(zone)


func test_paper_raids_break_the_gate_under_the_towers() -> void:
	# Six raiders against one rifle: up a tower behind a palisade gate,
	# and on the open ground as before
	var walled := {"wounded": 0, "killed": 0, "breached": 0}
	var open := {"wounded": 0, "killed": 0}
	for run in 100:
		for w in 2:
			var paper := RaidOnPaper.new(run + 1)
			for i in 6:
				paper.add_raider("r", 120.0 if i % 4 == 3 else 80.0, 20.0, 1.25)
			for i in 1:
				paper.add_guard("g%d" % i, 100.0, RIFLE_W, 30, 30).raised = w == 0
			for i in 5:
				paper.add_sheltering("m%d" % i, 100.0)
			paper.stores = {&"vegetables": 100}
			paper.carry = {&"vegetables": 15}
			if w == 0:
				paper.breach_health = 1400.0
				paper.gate_seen_from_ground = false
			var res := paper.run()
			var into: Dictionary = walled if w == 0 else open
			into["wounded"] += (res["wounded"] as Array).size()
			into["killed"] += res["killed"]
			if w == 0 and res["breached"]:
				walled["breached"] += 1
	check(walled["wounded"] < open["wounded"], "behind walls, up towers: fewer guards go down (%d against %d in 100 raids)" % [walled["wounded"], open["wounded"]])
	check(walled["killed"] >= open["killed"], "and as many raiders killed (%d against %d)" % [walled["killed"], open["killed"]])
	# At the mine: its gate, the guards up towers, and a breach breaks the gate
	var zone := await load_zone()
	var mine := await _walled_mine(zone)
	var g := await _newcomer(mine, Settler.Role.GUARD)
	g.arm(RIFLE, 60)
	var u := await _newcomer(mine, Settler.Role.GUARD)
	var up_now := mine.tower_guards()
	check(up_now.size() == 1 and up_now[0] == g, "the armed guard is the one up a tower")
	mine.warn_raid(0.0)
	var road := mine.get_node("RaidPoints").get_child(0) as Node3D
	mine.raid_from = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, road.global_position)
	var gate := mine._paper_gate()
	check(gate != null and gate.definition.id == &"palisade_gate", "raiders up the road would have to break the palisade gate")
	# Weak enough to give, and nobody to shoot (the guard's gun taken back):
	# it's broken through
	gate.health = 10.0
	g.disarm()
	mine.away_range = 0.0
	g.global_position = AWAY
	u.global_position = AWAY
	var rep := mine.settle_raid_on_paper(7)
	await wait_physics(3)
	check(not is_instance_valid(gate) or gate.is_queued_for_deletion() or gate.health <= 0.0, "broken through on paper: the gate's broken (%s)" % rep)
	await wait_physics(3)
	check(mine.sites().any(func(x: ConstructionSite) -> bool: return x.rebuild and x.plan_id == &"palisade_gate"), "and back on the building list")
	await _free(zone)
