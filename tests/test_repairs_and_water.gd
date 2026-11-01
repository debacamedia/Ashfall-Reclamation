extends "res://tests/test_case.gd"
## Increment 20.1, from the user's playtest of raids: broken fences go back
## on the building list, Builders mend what's damaged, survivors walk out of
## the buildings they're found in, and the pump can be upgraded.

const AWAY := Vector3(520, 0.1, -180)

var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	return st


func _newcomer(zone: Node3D, role: Settler.Role) -> Settler:
	var st := _farm(zone)
	var p := _player(zone)
	var back := p.global_position
	p.global_position = AWAY
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	st.request_set_role(p, s, role)
	return s


func _finish(site: ConstructionSite) -> void:
	var inv := InventoryComponent.new()
	inv.slot_count = 40
	inv.max_weight = 0.0
	add_child(inv)
	for id: StringName in site.missing():
		inv.add_item(ItemDatabase.get_item(id), site.missing()[id])
	site.take_from(inv)
	site.add_work(site.total_hours())
	inv.queue_free()
	await wait_physics(2)


func _built(zone: Node3D, id: StringName) -> Array:
	return zone.get_node("Structures").get_children().filter(func(n: Node) -> bool:
		return n is SettlementBuilding and (n as SettlementBuilding).definition.id == id and not n.is_queued_for_deletion())


func _give(p: PlayerController, parts: Dictionary) -> void:
	p.inventory.max_weight = 0.0
	for id: StringName in parts:
		p.inventory.add_item(ItemDatabase.get_item(id), parts[id])


# ---------------------------------------------------------------- repairs

func test_a_broken_fence_goes_back_on_the_building_list() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	await _finish(st.sites_root.get_node("FenceFrontLeft") as ConstructionSite)
	var fences := _built(zone, &"farm_fence")
	check(fences.size() == 9, "36 m of fence up")
	var victim := fences[3] as SettlementBuilding
	var where := victim.global_transform
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	victim.apply_damage(9999.0)
	await wait_physics(3)
	check(_built(zone, &"farm_fence").size() == 8, "a raider breaks a length")
	var again := st.sites().filter(func(s: ConstructionSite) -> bool: return s.rebuild)
	check(again.size() == 1, "it's back on the building list")
	var site := again[0] as ConstructionSite
	check(site.display_name() == "Fence (rebuild)" and site.pieces.size() == 1 and site.total_cost() == {&"wood_plank": 1, &"scrap_metal": 1}, "%s: %s" % [site.display_name(), site.total_cost()])
	check((site.global_transform * site.pieces[0]).origin.distance_to(where.origin) < 0.05, "where it stood")
	check(said.any(func(t: String) -> bool: return t.begins_with("Raiders broke a fence")), "a notice: %s" % [said])
	await _finish(site)
	var back := _built(zone, &"farm_fence").filter(func(f: Node3D) -> bool: return f.global_position.distance_to(where.origin) < 0.05)
	check(_built(zone, &"farm_fence").size() == 9 and back.size() == 1, "and once rebuilt, the line's whole again")
	# Dismantling it yourself (X) doesn't put it back on the list
	var mine := back[0] as SettlementBuilding
	mine.take_down()
	await wait_physics(2)
	check(st.sites().filter(func(s: ConstructionSite) -> bool: return s.rebuild).is_empty(), "taking one down yourself isn't a rebuild")
	await _free(zone)


func test_builders_mend_what_raiders_damage() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	await _finish(st.sites_root.get_node("GuardPostFrontLeft") as ConstructionSite)
	var post := _built(zone, &"guard_post")[0] as SettlementBuilding
	post.apply_damage(post.get_max_health() * 0.6)
	check(post.is_damaged() and st.damaged_structures() == [post], "a guard post knocked about")
	var b := await _newcomer(zone, Settler.Role.BUILDER)
	# Nothing in the stores to mend it with: they get on with the plan instead
	check(st.builder_job() != post, "no materials: not this one yet")
	st.store.inventory.add_item(CLOTH, 2)
	st.store.inventory.add_item(PLANK, 1)
	check(st.builder_job() == post and b.status_text() == "Mending the guard post", "with them in the stores: %s" % b.status_text())
	st.simulate(1.0)
	check(not post.is_damaged(), "an hour's work: mended (%.0f / %.0f)" % [post.health, post.get_max_health()])
	check(st.store.inventory.count_of(&"cloth") == 0 and st.store.inventory.count_of(&"wood_plank") == 0, "its repair cost came from the stores")
	await _free(zone)


# ---------------------------------------------------------------- survivors

func test_recruited_survivors_walk_out_of_where_they_were_found() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	for who in ["Maya", "Tomas", "Jeb"]:
		var s := zone.get_node("Survivors/" + who) as Settler
		var start := s.global_position
		p.global_position = s.global_position + Vector3(1.5, 0.05, 0)
		await wait_physics(5)
		p.talk_to(s)
		check(s.settlement == st, "%s comes" % who)
		# You follow a few metres behind them, for 30 s
		var last := s.global_position
		for t in 30:
			await wait_physics(60)
			var went := s.global_position - last
			went.y = 0.0
			if went.length() > 0.3:
				p.global_position = s.global_position - went.normalized() * 7.0 + Vector3.UP * 0.3
			last = s.global_position
		var gone := Vector2(s.global_position.x - start.x, s.global_position.z - start.z).length()
		check(gone > 40.0 or s.has_arrived(), "%s made it out and on their way (%.0f m in 30 s)" % [who, gone])
		s.global_position = st.get_node("Hangout").global_position + Vector3.UP * 0.1
	await _free(zone)


# ---------------------------------------------------------------- the pump

func test_upgrade_the_pump() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_pump"
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	p.inventory.clear()
	check(st.pump_level == 0 and is_equal_approx(st.pump_rate(), 1.0), "broken: the rain barrel's 1 L an hour")
	_give(p, Settlement.PUMP_PARTS)
	check(st.request_repair_pump(p) and st.pump_level == 1 and is_equal_approx(st.pump_rate(), 12.0) and is_equal_approx(st.water_capacity, 200.0), "repaired: 12 L an hour, 200 L tank")
	var up := st.next_pump_upgrade()
	check(up[0] == "Bigger Pump" and is_equal_approx(float(up[2]), 24.0), "next: a Bigger Pump, 24 L an hour")
	check(st.pump.get_prompt(p).begins_with("Upgrade to a Bigger Pump"), "the pump offers it: %s" % st.pump.get_prompt(p))
	check(not st.request_upgrade_pump(p) and st.pump_level == 1, "not without the parts")
	_give(p, up[1])
	check(st.request_upgrade_pump(p) and st.pump_level == 2 and is_equal_approx(st.pump_rate(), 24.0) and is_equal_approx(st.water_capacity, 300.0), "Bigger Pump: 24 L an hour, 300 L tank")
	check((st.get_node("PumpHead/Upgrade2") as Node3D).visible and not (st.get_node("PumpHead/Motor") as Node3D).visible, "a pressure tank on the pump head")
	_give(p, st.next_pump_upgrade()[1])
	check(st.request_upgrade_pump(p) and st.pump_level == 3 and is_equal_approx(st.pump_rate(), 40.0) and is_equal_approx(st.water_capacity, 400.0), "Motor Pump: 40 L an hour, 400 L tank")
	check((st.get_node("PumpHead/Motor") as Node3D).visible, "and a motor")
	check(st.next_pump_upgrade().is_empty() and st.pump.get_prompt(p).begins_with("Motor Pump: running"), "as good as it gets: %s" % st.pump.get_prompt(p))
	check(is_equal_approx(st.rates()["water"], 40.0), "40 L an hour with nobody using it")
	st.water = 350.0
	check(saves.save_game("pump", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	saves.load_game("pump", zone2)
	await wait_physics(3)
	var st2 := _farm(zone2)
	check(st2.pump_level == 3 and is_equal_approx(st2.water_capacity, 400.0) and st2.water > 340.0, "the Motor Pump, and its full tank, after loading")
	check((st2.get_node("PumpHead/Motor") as Node3D).visible, "motor and all")
	await _free(zone2)
