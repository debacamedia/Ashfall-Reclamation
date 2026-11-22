extends "res://tests/test_case.gd"
## Increment 27: your places fortified, and the Armory's gun mix.
##
## Each of your three places has defences in its plan, laid out as building
## sites when you claim it (or, claimed before, when the game loads): gates in
## Ash Creek's fence gaps, a fence right round Black Ridge Mine with a gate on
## the road in, and a gate in Northwatch's gateway. Builders work where
## they're needed, at home first, then at your other places. The gates open
## for your people and not for raiders, who have to break them down. Miners
## dig up Chemicals now and then; the Armorer makes one of each kind of gun,
## then rounds for them, then more.

const AWAY := Vector3(120, 0.1, 40)
const TEST_DIR := "user://test_saves_fortify"

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var ELECTRONICS: ItemDefinition = load("res://resources/items/electronics.tres")
var CHEMICALS: ItemDefinition = load("res://resources/items/chemicals.tres")
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")
var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")

var saves: Node
var _old_dir := ""


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old_dir = saves.save_dir
		saves.save_dir = TEST_DIR
		_clean())
	tree_exiting.connect(func() -> void:
		_clean()
		saves.autosave_enabled = false
		saves.save_dir = _old_dir)


func _clean() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _place(zone: Node3D, site: String) -> Settlement:
	return zone.get_node(site + "/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s (%s)" % [st.settlement_name, st.claim_refusal_reason(p)])
	st.next_raid_in = 9999.0
	st.arrival_in = 9999.0
	p.global_position = AWAY
	await wait_physics(2)


func _newcomer(st: Settlement, role: Settler.Role) -> Settler:
	var s := st.spawn_newcomer()
	await wait_physics(70)
	var p := _player(st.get_parent().get_parent() as Node3D)
	check(st.request_set_role(p, s, role), "%s: %s (%s)" % [s.settler_name, Settler.ROLE_NAMES[role], st.role_refusal_reason(role)])
	return s


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _keys(st: Settlement) -> Array:
	return st.sites().map(func(s: ConstructionSite) -> String: return s.key)


## Hands every site its materials and puts in all its hours: built.
func _finish_sites(st: Settlement) -> void:
	for site in st.sites():
		site.delivered = site.total_cost().duplicate()
		site.add_work(site.total_hours())
	await wait_physics(3)


## Waits for the rebake, and for the zone's map to take it in (on its own
## thread: a moment or two later).
func _wait_nav(zone: Node3D) -> void:
	var nav := NavRebaker.find_navigation(_player(zone))
	var map := zone.get_world_3d().navigation_map
	for i in 900:
		await wait_physics(1)
		if i > 10 and not NavRebaker.any_busy(nav):
			break
	var from := NavigationServer3D.map_get_iteration_id(map)
	for i in 400:
		await wait_physics(1)
		if NavigationServer3D.map_get_iteration_id(map) >= from + 2:
			break
	await wait_physics(2)


func _gate_of(st: Settlement) -> SettlementGate:
	for n in get_tree().get_nodes_in_group("settlement_gates"):
		var g := n as SettlementGate
		if g != null and g.settlement() == st and not g.is_queued_for_deletion():
			return g
	return null


func _path(zone: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := zone.get_world_3d().navigation_map
	return NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from), to, true)


## How close the path comes to the gate's opening.
func _closest_to_gate(path: PackedVector3Array, g: SettlementGate) -> float:
	var best := INF
	for i in path.size() - 1:
		var n := maxi(int(path[i].distance_to(path[i + 1]) / 0.5), 1)
		for j in n + 1:
			best = minf(best, g.distance_to(path[i].lerp(path[i + 1], float(j) / n)))
	return best


# ---------------------------------------------------------------- the plans

func test_the_defences_are_planned() -> void:
	var zone := await load_zone()
	var farm := _place(zone, "AshCreekFarms")
	var mine := _place(zone, "BlackRidgeMine")
	var nw := _place(zone, "NorthwatchOutpost")
	check(SettlementPlans.has(&"gate") and not SettlementPlans.PLANS[&"gate"]["placeable"] and SettlementPlans.piece_length(&"gate") == 8.0,
		"a Gate plan: 8 m, laid out with the place's plan rather than placed")
	check(SettlementPlans.cost(&"gate") == {&"wood_plank": 8, &"scrap_metal": 4}, "a gate takes 8 Wood Planks and 4 Scrap Metal")
	check(SettlementPlans.structure(&"gate").scene_path.ends_with("settlement_gate.tscn") and SettlementPlans.plan_for_structure(&"settlement_gate") == &"gate",
		"built as a Settlement Gate")
	# Ash Creek: a gate in each gap of its fences
	var ends: Array[Vector3] = []
	for m in farm.get_node("Plans").get_children():
		if m.get_meta("plan", "") == "fence":
			ends.append((m as Node3D).position)
			ends.append(m.get_meta("to"))
	var gates := farm.get_node("Plans").get_children().filter(func(m: Node) -> bool: return m.get_meta("plan", "") == "gate")
	check(gates.size() == 3, "Ash Creek: three gates (%d)" % gates.size())
	for g: Node3D in gates:
		var to: Vector3 = g.get_meta("to")
		check(g.get_meta("defence", false) and is_equal_approx(g.position.distance_to(to), 8.0), "%s: one of its defences, 8 m" % g.name)
		check(ends.any(func(e: Vector3) -> bool: return e.distance_to(g.position) < 0.1) and ends.any(func(e: Vector3) -> bool: return e.distance_to(to) < 0.1),
			"%s fills a gap in the fence, end to end" % g.name)
	# The mine: a closed ring of fence with a gate
	var runs := mine.get_node("Plans").get_children().filter(func(m: Node) -> bool: return m.has_meta("to"))
	var length := 0.0
	for i in runs.size():
		var a: Node3D = runs[i]
		var next: Node3D = runs[(i + 1) % runs.size()]
		check(a.get_meta("defence", false), "%s is one of the mine's defences" % a.name)
		check((a.get_meta("to") as Vector3).distance_to(next.position) < 0.01, "%s joins %s" % [a.name, next.name])
		length += a.position.distance_to(a.get_meta("to"))
	check(runs.size() == 6 and runs.filter(func(m: Node) -> bool: return m.get_meta("plan") == "gate").size() == 1,
		"the mine: five runs of fence and a gate, all the way round (%.0f m)" % length)
	var ring := PackedVector2Array()
	for r: Node3D in runs:
		ring.append(Vector2(r.position.x, r.position.z))
	var inside: Array[Node3D] = [mine.store, mine.armory, mine.get_node("ArrivalPoint"), mine.get_node("Hangout"), mine.get_node("NoticeBoard")]
	inside.append_array(mine.mine_spots())
	inside.append_array(mine.guard_posts())
	for b in zone.get_node("BlackRidgeMine/Buildings").get_children():
		inside.append(b as Node3D)
	for n in inside:
		var at := mine.to_local(n.global_position)
		check(Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), ring), "%s is inside the fence" % n.name)
	for r in mine.get_node("RaidPoints").get_children():
		var at := (r as Node3D).position
		check(not Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), ring), "raiders come from outside it (%s)" % r.get_meta("label"))
	var posts := mine.get_node("Plans").get_children().filter(func(m: Node) -> bool: return m.get_meta("plan", "") == "guard_post")
	check(posts.size() == 2 and posts.all(func(m: Node) -> bool: return m.get_meta("defence", false)), "and a guard post either side of the gate")
	# Northwatch: a gate in its gateway, widened to 8 m
	var nw_gate := nw.get_node("Plans/Gate") as Node3D
	check(nw_gate != null and nw_gate.get_meta("plan") == "gate" and nw_gate.get_meta("defence", false), "Northwatch: a gate")
	var per := zone.get_node("NorthwatchOutpost/Buildings/Perimeter")
	var gw := per.get_node("GatePostWCol") as Node3D
	var ge := per.get_node("GatePostECol") as Node3D
	check(is_equal_approx(ge.position.x - gw.position.x - 0.8, 8.0), "its gateway is 8 m between the posts (%.1f)" % (ge.position.x - gw.position.x - 0.8))
	for gp in nw.guard_posts():
		check(nw.to_local(gp.global_position).z < 13.0, "%s stands back from the gate, so a guard there doesn't hold it open" % gp.name)
	# Nothing in the way of any of them (the ground's flat)
	var space := zone.get_world_3d().direct_space_state
	for st in [farm, mine, nw]:
		for m in (st as Settlement).get_node("Plans").get_children():
			if not m.get_meta("defence", false) or not m.has_meta("to"):
				continue
			var a := (st as Settlement).to_global((m as Node3D).position)
			var b := (st as Settlement).to_global(m.get_meta("to"))
			var blocked := []
			var n := int(a.distance_to(b) / 1.0)
			for j in range(1, n):
				var q := PhysicsShapeQueryParameters3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(0.3, 1.0, 0.3)
				q.shape = box
				q.transform = Transform3D(Basis.IDENTITY, a.lerp(b, float(j) / n) + Vector3.UP * 0.8)
				q.collision_mask = PhysicsLayers.STRUCTURES
				for h in space.intersect_shape(q, 4):
					blocked.append(str((h["collider"] as Node).name))
			check(blocked.is_empty(), "%s/%s: clear all along (%s)" % [st.settlement_name, m.name, blocked])
	await _free(zone)


func test_claiming_lays_out_the_defences() -> void:
	var zone := await load_zone()
	var mine := _place(zone, "BlackRidgeMine")
	var nw := _place(zone, "NorthwatchOutpost")
	var farm := _place(zone, "AshCreekFarms")
	check(mine.sites().is_empty(), "nothing planned before it's yours")
	await _claim(zone, mine)
	var keys := _keys(mine)
	for k in ["MineFenceEastS", "MineGate", "MineFenceEastN", "MineFenceNorth", "MineFenceWest", "MineFenceSouth", "MineGatePostN", "MineGatePostS"]:
		check(keys.has(k), "the mine: %s planned" % k)
	check(mine.plans_laid and mine.defences_laid and mine.save_state()["defences_laid"] == true, "laid out, and saved as laid out")
	var gate := mine.sites().filter(func(s: ConstructionSite) -> bool: return s.key == "MineGate")[0] as ConstructionSite
	check(gate.plan_id == &"gate" and gate.pieces.size() == 1 and gate.total_cost() == {&"wood_plank": 8, &"scrap_metal": 4} and is_equal_approx(gate.total_hours(), 1.5),
		"its gate: one piece, 8 planks and 4 scrap, an hour and a half's work")
	var north := mine.sites().filter(func(s: ConstructionSite) -> bool: return s.key == "MineFenceNorth")[0] as ConstructionSite
	check(north.pieces.size() == 23 and north.total_cost()[&"wood_plank"] == 23 and north.total_cost()[&"scrap_metal"] == 6,
		"the north side: 23 lengths, 23 planks and 6 scrap (%d)" % north.pieces.size())
	var pieces := 0
	for s in mine.sites():
		if s.plan_id == &"fence":
			pieces += s.pieces.size()
	check(pieces == 82, "82 lengths of fence in all, 330 m (%d)" % pieces)
	await _claim(zone, nw)
	check(_keys(nw) == ["Gate"], "Northwatch: its gate (%s)" % [_keys(nw)])
	await _claim(zone, farm)
	keys = _keys(farm)
	check(keys.has("GateFront") and keys.has("GateBack") and keys.has("GateField") and keys.has("FenceFrontLeft"),
		"Ash Creek: its fences, guard posts and three gates (%d sites)" % keys.size())
	await _free(zone)


func test_places_claimed_before_get_their_defences() -> void:
	var zone := await load_zone()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	DirAccess.copy_absolute("res://tests/fixtures/save_24_1.json", TEST_DIR + "/fixture.json")
	check(saves.load_game("fixture", zone) == OK, "loaded a save from Increment 24")
	await wait_physics(10)
	var farm := Settlement.find(get_tree(), &"ash_creek")
	var mine := Settlement.find(get_tree(), &"black_ridge")
	var nw := Settlement.find(get_tree(), &"northwatch")
	check(farm.defences_laid and _keys(farm).has("GateFront") and _keys(farm).has("GateBack") and _keys(farm).has("GateField"),
		"the farm: its gates to build (%s)" % [_keys(farm)])
	var keys := _keys(farm)
	check(keys.all(func(k: String) -> bool: return keys.count(k) == 1), "and nothing planned twice (%s)" % [keys])
	check(mine.defences_laid and _keys(mine).has("MineGate") and _keys(mine).has("MineFenceNorth"), "the mine: its fence and gate")
	check(not nw.is_claimed and nw.sites().is_empty(), "Northwatch isn't yours: nothing")
	# Saved and loaded again: not laid out twice
	var before := farm.sites().size() + mine.sites().size()
	check(saves.save_game("again", zone) == OK, "saved")
	check(saves.load_game("again", zone) == OK, "and loaded")
	await wait_physics(10)
	farm = Settlement.find(get_tree(), &"ash_creek")
	mine = Settlement.find(get_tree(), &"black_ridge")
	check(farm.sites().size() + mine.sites().size() == before, "the same sites (%d)" % (farm.sites().size() + mine.sites().size()))
	await _free(zone)


# ---------------------------------------------------------------- builders

func test_builders_go_where_needed() -> void:
	var zone := await load_zone()
	var farm := _place(zone, "AshCreekFarms")
	var mine := _place(zone, "BlackRidgeMine")
	await _claim(zone, farm)
	await _claim(zone, mine)
	farm.store.inventory.add_item(VEG, 30)
	var b := await _newcomer(farm, Settler.Role.BUILDER)
	farm.store.inventory.add_item(PLANK, 200)
	farm.store.inventory.add_item(SCRAP, 60)
	farm._supply_sites()
	check(not farm.builder_assignment().is_empty() and farm.builder_assignment()[1] == farm and b.status_text().begins_with("Building the fence"),
		"with the farm's own building to do, at home: %s" % b.status_text())
	# The farm's all built: off to the mine (its materials from the farm's
	# stores, down the supply line)
	for s in farm.sites():
		s.free()
	mine._supply_sites()
	var a := mine.builder_assignment()
	var site := a[0] as ConstructionSite if not a.is_empty() else null
	check(not farm.builder_assignment().is_empty() and farm.builder_assignment()[1] == mine and site != null,
		"nothing left at the farm: the Builder's needed at the mine")
	if site == null:
		await _free(zone)
		return
	check(b.status_text() == "Building the %s at Black Ridge Mine" % site.display_name().to_lower(), "they say so: %s" % b.status_text())
	check(mine.builders_working_here() == 1 and farm.builders_working_here() == 0, "the mine's screen counts them")
	var work := site.work
	farm.simulate(1.0)
	check(not is_instance_valid(site) or site.work > work + 0.99, "an hour at the farm's clock: an hour's work on the mine's %s" % site.display_name().to_lower())
	# They go there: with nobody about, off-screen
	for i in 300:
		await wait_physics(1)
		if b.global_position.distance_to(mine.global_position) < mine.claim_radius:
			break
	check(b.global_position.distance_to(mine.global_position) < mine.claim_radius, "the Builder's at the mine (%.0f m off)" % b.global_position.distance_to(mine.global_position))
	# The mine's done too: home again
	for s in mine.sites():
		s.free()
	await wait_physics(2)
	check(farm.builder_assignment().is_empty() and b.status_text() == "Nothing to build", "nothing anywhere: %s" % b.status_text())
	for i in 300:
		await wait_physics(1)
		if b.global_position.distance_to(farm.global_position) < farm.claim_radius:
			break
	check(b.global_position.distance_to(farm.global_position) < farm.claim_radius, "and home they go")
	await _free(zone)


# ---------------------------------------------------------------- gates

func test_the_gate_opens_for_yours_and_not_for_raiders() -> void:
	var zone := await load_zone()
	var nw := _place(zone, "NorthwatchOutpost")
	var p := _player(zone)
	await _claim(zone, nw)
	await _finish_sites(nw)
	var g := _gate_of(nw)
	check(g != null and g.global_position.distance_to(nw.to_global(Vector3(0, 0, 18))) < 0.2, "the gate's up, in the gateway")
	check(g.get_health_fraction() == 1.0 and g.definition.max_health == 800.0, "a strong gate: 800 health (a length of fence has 250)")
	var leaf := g.get_node("%LeafL/Leaf") as CollisionObject3D
	await _wait_nav(zone)
	check(leaf.collision_layer == PhysicsLayers.STRUCTURES and leaf.is_in_group("nav_passable"), "its leaves are solid, and left out of the navmesh")
	await wait_physics(20)
	check(not g.is_open, "shut, with nobody near")
	var outside := nw.to_global(Vector3(0, 0.1, 23))
	p.global_position = outside
	await wait_physics(60)
	check(g.is_open and (g.get_node("%LeafL") as Node3D).rotation.y > 1.4 and (g.get_node("%LeafR") as Node3D).rotation.y < -1.4,
		"you walk up: it swings open, both leaves in")
	# A raider about: it stays shut, even on you
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = nw.to_global(Vector3(3, 0.1, 27))
	r.set_physics_process(false)
	await wait_physics(30)
	check(not g.is_open and g.raider_near(), "a raider near: it shuts")
	r.queue_free()
	await wait_physics(30)
	check(g.is_open, "the raider's gone: open again for you")
	# A settler of yours, close to it
	p.global_position = AWAY
	await wait_physics(30)
	check(not g.is_open, "you walk off: it shuts behind you")
	nw.store.inventory.add_item(VEG, 20)
	var s := nw.spawn_newcomer()
	await wait_physics(5)
	s.set_physics_process(false)
	s.global_position = nw.to_global(Vector3(1.5, 0.1, 20.0))
	await wait_physics(30)
	check(g.is_open, "a settler of yours at it: it opens")
	s.global_position = nw.to_global(Vector3(1.5, 0.1, 25.0))
	await wait_physics(30)
	check(not g.is_open, "and shuts once they're through")
	# Paths run through it, shut or not
	var path := _path(zone, nw.to_global(Vector3(0, 0, 40)), nw.to_global(Vector3(0, 0, 0)))
	check(path.size() > 1 and path[-1].distance_to(nw.to_global(Vector3.ZERO)) < 1.0 and _closest_to_gate(path, g) < 1.0,
		"a path in runs through the shut gate")
	# Saved shut or open
	g.set_open(true, false)
	check(g.save_state()["open"] == true, "saved open")
	g.load_state({"open": false, "health": 400.0})
	check(not g.is_open and is_equal_approx((g.get_node("%LeafL") as Node3D).rotation.y, 0.0), "loaded shut")
	await _free(zone)


func test_raiders_have_to_break_the_gate_down() -> void:
	var zone := await load_zone()
	var nw := _place(zone, "NorthwatchOutpost")
	await _claim(zone, nw)
	await _finish_sites(nw)
	await _wait_nav(zone)
	var g := _gate_of(nw)
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, nw.to_global(Vector3(0, 0, 45))) + Vector3.UP * 0.1
	nw.raid_phase = Settlement.RaidPhase.ACTIVE
	r.join_raid(nw, r.global_position)
	var opened := false
	for i in 1800:
		await wait_physics(1)
		opened = opened or g.is_open
		if g.is_damaged():
			break
	check(g.is_damaged(), "the raider makes for the stores, finds the gate shut and hacks at it (%.0f health)" % g.health)
	check(r.break_target == g, "the gate's what it's breaking")
	check(not opened, "it never opened for them")
	check(nw.to_local(r.global_position).z > 17.0, "still outside (%s)" % nw.to_local(r.global_position))
	# Broken down: it's back on the building list
	g.apply_damage(10000.0, r)
	await wait_physics(3)
	check(_keys(nw).any(func(k: String) -> bool: return k.begins_with("Rebuild")) and nw.sites()[-1].plan_id == &"gate",
		"broken: a gate goes back on the list to rebuild")
	await _free(zone)


func test_the_mine_fenced_all_round() -> void:
	var zone := await load_zone()
	var mine := _place(zone, "BlackRidgeMine")
	await _claim(zone, mine)
	await _finish_sites(mine)
	check(mine.sites().is_empty(), "all built")
	var fences := get_tree().get_nodes_in_group("settlement_buildings").filter(
		func(b: Node) -> bool: return (b as SettlementBuilding).settlement() == mine and (b as Structure).definition.id == &"farm_fence")
	check(fences.size() == 82, "82 lengths of fence (%d)" % fences.size())
	var g := _gate_of(mine)
	check(g != null and mine.to_local(g.global_position).distance_to(Vector3(44, 0, 15)) < 0.2, "the gate's on the road in")
	await _wait_nav(zone)
	var goal := mine.raid_goal()
	for rp in mine.get_node("RaidPoints").get_children():
		var path := _path(zone, (rp as Node3D).global_position, goal)
		check(path.size() > 1 and path[-1].distance_to(goal) < 1.0, "from %s: a way to the stores" % rp.get_meta("label"))
		check(_closest_to_gate(path, g) < 1.0, "from %s: only through the gate (%.1f m off it)" % [rp.get_meta("label"), _closest_to_gate(path, g)])
	# Were the gate a wall, there'd be no way in at all
	for leaf in g.find_children("Leaf", "AnimatableBody3D", true, false):
		leaf.remove_from_group("nav_passable")
	NavRebaker.request(g)
	await _wait_nav(zone)
	var shut := _path(zone, mine.get_node("RaidPoints").get_child(0).global_position, goal)
	check(shut.is_empty() or shut[-1].distance_to(goal) > 5.0, "with the gate shut to paths too: no way in (%.0f m short)" % (shut[-1].distance_to(goal) if not shut.is_empty() else INF))
	await _free(zone)


# ---------------------------------------------------------------- miners and the armory

func test_miners_dig_up_chemicals() -> void:
	var zone := await load_zone()
	var mine := _place(zone, "BlackRidgeMine")
	await _claim(zone, mine)
	mine.store.inventory.add_item(VEG, 30)
	await _newcomer(mine, Settler.Role.MINER)
	var scrap := mine.scrap()
	mine.simulate(8.0)
	check(mine.store.inventory.count_of(&"chemicals") == 2, "a Miner, 8 hours: 2 Chemicals (%d)" % mine.store.inventory.count_of(&"chemicals"))
	check(mine.scrap() == scrap + 16, "and 16 Scrap Metal, as before")
	mine.simulate(2.0)
	check(mine.save_state()["chem_progress"] == 0.5, "half way to the next, saved")
	await _free(zone)


func test_the_armory_makes_each_kind_then_more() -> void:
	var zone := await load_zone()
	var nw := _place(zone, "NorthwatchOutpost")
	await _claim(zone, nw)
	nw.store.inventory.add_item(VEG, 40)
	await _newcomer(nw, Settler.Role.ARMORER)
	check(nw.armory.inventory.slot_count == 24, "a bigger Armory Locker: 24 slots")
	var kinds := func() -> Array:
		return Settlement.ARMORY_GUNS.map(func(id: StringName) -> int: return nw.armory.inventory.count_of(id))
	# At a pinch, with the makings of nothing better and the locker empty, a
	# Pipe Pistol (4 scrap and a plank)
	nw.store.inventory.add_item(SCRAP, 4)
	nw.store.inventory.add_item(PLANK, 1)
	nw.simulate(4.0)
	check(nw.armory.inventory.count_of(&"pipe_pistol") == 1, "an empty locker and 4 scrap: a Pipe Pistol, at a pinch")
	nw.armory.inventory.remove_item(&"pipe_pistol", 1)
	nw.store.inventory.add_item(SCRAP, 200)
	nw.store.inventory.add_item(PLANK, 30)
	nw.store.inventory.add_item(ELECTRONICS, 4)
	var made: Array[String] = []
	for i in 4:
		nw.simulate(0.5)
		made.append(nw.armorer_status())
		nw.simulate(3.5)
	check(kinds.call() == [1, 1, 1, 1], "one of each kind first: pistol, shotgun, service rifle, marksman rifle (%s; %s)" % [kinds.call(), made])
	check(made[3].begins_with("Making a Marksman Rifle"), "the Marksman Rifle too: %s" % made[3])
	# Rounds for every kind, the lowest first
	nw.store.inventory.add_item(CHEMICALS, 8)
	nw.store.inventory.add_item(CLOTH, 10)
	nw.simulate(4.0)
	var rounds := [&"pistol_ammo", &"shotgun_shells", &"rifle_ammo", &"rifle_308"].map(func(id: StringName) -> int: return nw.armory.inventory.count_of(id))
	check(rounds.all(func(n: int) -> bool: return n > 0), "then rounds for each, made with Gunpowder from Chemicals and Wood Planks (%s)" % [rounds])
	check(nw._stores_count(&"chemicals") < 8, "the Chemicals are used")
	# No more makings for rounds: more guns, the fewest first, up to two each
	nw.store.inventory.remove_item(&"chemicals", nw._stores_count(&"chemicals"))
	nw.store.inventory.remove_item(&"gunpowder", nw._stores_count(&"gunpowder"))
	nw.store.inventory.add_item(ELECTRONICS, 4)
	nw.store.inventory.add_item(SCRAP, 200)
	nw.store.inventory.add_item(PLANK, 20)
	nw.simulate(20.0)
	check(kinds.call() == [2, 2, 2, 2] and nw.armory_guns() == 8, "then more: two of each (%s)" % [kinds.call()])
	nw.simulate(4.0)
	check(nw.armory_guns() == 8 and nw.armorer_status().begins_with("Armory stocked") and nw.armorer_status().contains("Chemicals"),
		"eight: stocked, and short of Chemicals for rounds: %s" % nw.armorer_status())
	await _free(zone)
