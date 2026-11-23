extends "res://tests/fortify_helpers.gd"
## Scratch (28.1): real raids against paper ones, behind walls and towers.

var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")
const PAPER_RUNS := 200


func test_calibrate() -> void:
	# [site, finishes, armed guards, unarmed guards, others, other role]
	var cases := [
		["BlackRidgeMine", 2, 3, 0, 5, Settler.Role.MINER],
		["BlackRidgeMine", 2, 1, 1, 4, Settler.Role.MINER],
		["NorthwatchOutpost", 2, 2, 0, 2, Settler.Role.NONE],
		["AshCreekFarms", 1, 2, 0, 4, Settler.Role.FARMER],
	]
	for c: Array in cases:
		for point in 3:
			await _one(c, point)


func _one(c: Array, point: int) -> void:
	var zone := await load_zone()
	var st := _place(zone, c[0])
	await _claim(zone, st)
	st.away_range = 100000.0
	for i in int(c[1]):
		await _finish_sites(st)
	await _wait_nav(zone)
	st.store.inventory.add_item(VEG, 200)
	var guards: Array[Settler] = []
	for i in int(c[2]) + int(c[3]):
		var g := await _newcomer(st, Settler.Role.GUARD)
		if i < int(c[2]):
			g.arm(RIFLE, 120)
		guards.append(g)
	for i in int(c[4]):
		await _newcomer(st, c[5])
	# Up the towers, or at the posts
	for i in 3600:
		await wait_physics(1)
		if guards.all(func(s: Settler) -> bool: return s.state == Settler.State.PATROL or not s.holds_tower()) and i > 600:
			break
	st.warn_raid(0.0)
	var p := st.get_node("RaidPoints").get_child(point) as Node3D
	st.raid_from = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, p.global_position)
	# Paper first, from the same guards
	var up := st.tower_guards()
	var gate := st._paper_gate()
	var sums := {"killed": 0.0, "escaped": 0.0, "wounded": 0.0, "rounds": 0.0, "breached": 0.0, "food": 0.0}
	for run in PAPER_RUNS:
		var paper := RaidOnPaper.new(run + 1)
		for i in st.raid_size:
			var vet := i % 4 == 3
			var stats := st._raider_stats(vet)
			paper.add_raider("r", stats[0], stats[1], stats[2])
		for s in st.members():
			if s.role == Settler.Role.GUARD:
				var f := paper.add_guard(s.settler_name, s.health.current_health, s.gun.weapon if s.gun != null else null, s.magazine, s.ammo)
				f.raised = up.has(s)
			else:
				paper.add_sheltering(s.settler_name, s.health.current_health)
		paper.stores = {&"vegetables": 200, &"wood_plank": 0}
		paper.carry = {&"vegetables": st.raid_carry_food, &"wood_plank": st.raid_carry_planks}
		if gate != null:
			paper.breach_health = gate.health
			paper.gate_seen_from_ground = gate.definition.id == &"settlement_gate"
		var res := paper.run()
		sums["killed"] += res["killed"]
		sums["escaped"] += res["escaped"]
		sums["wounded"] += (res["wounded"] as Array).size()
		sums["rounds"] += res["rounds"]
		sums["breached"] += 1.0 if res["breached"] else 0.0
		sums["food"] += 200 - int(paper.stores[&"vegetables"])
	for k in sums:
		sums[k] = snappedf(sums[k] / PAPER_RUNS, 0.01)
	var food0 := st._count_in_stores(&"vegetables")
	var rounds0 := guards.reduce(func(a: int, s: Settler) -> int: return a + s.magazine + s.ammo, 0)
	st.start_raid()
	var t := 0
	var off := 0
	while st.raid_active() and t < 300:
		await wait_physics(60)
		t += 1
		for g in guards:
			if g.holds_tower() and not g.up_tower() and not g.is_down():
				off += 1
	var rounds1 := guards.reduce(func(a: int, s: Settler) -> int: return a + s.magazine + s.ammo, 0)
	var rep := st.raid_report
	var g2 := gate if gate != null and is_instance_valid(gate) and not gate.is_queued_for_deletion() else null
	print("CAL %s pt%d size%d up%d gate%s | REAL k%d e%d w%d r%d food%d broke%s %ds off%d | PAPER %s" % [c[0], point, st.raid_size, up.size(),
		"-" if gate == null else str(int(gate.get_max_health())), rep["killed"], rep["escaped"], (rep["wounded"] as Array).size(), rounds0 - rounds1,
		food0 - st._count_in_stores(&"vegetables"), "y" if (gate != null and g2 == null) else "n", t, off, sums])
	await _free(zone)
