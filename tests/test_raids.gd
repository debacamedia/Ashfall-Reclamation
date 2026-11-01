extends "res://tests/test_case.gd"
## Increment 20: raids on Ash Creek. Scheduled after you claim it, a
## warning a couple of hours ahead, raiders who come for the stores and run
## off with what they can carry, guards who fight, settlers who shelter or
## go down wounded (helped up with a bandage), fences hacked through, saved.

const AWAY := Vector3(520, 0.1, -180)

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var BANDAGE: ItemDefinition = load("res://resources/items/bandage.tres")
var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")


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
	p.global_position = AWAY
	# These raids are played out for real, as if you were there (with nobody
	# within 200 m they're settled on paper since 20.5: test_away.gd)
	st.away_range = 100000.0
	await wait_physics(2)
	return st


func _newcomer(zone: Node3D, role: Settler.Role) -> Settler:
	var st := _farm(zone)
	var s := st.spawn_newcomer()
	await wait_physics(70)
	st.request_set_role(_player(zone), s, role)
	return s


## A raid that starts close by (in the lane, outside the gateway) so the
## test doesn't wait for a long walk.
func _raid_close(st: Settlement, size := 2) -> void:
	st.warn_raid(0.0)
	var site := st.get_parent() as Node3D
	st.raid_from = NavigationServer3D.map_get_closest_point(st.get_world_3d().navigation_map, site.to_global(Vector3(0, 0, 44)))
	st.raid_size = size
	st.start_raid()


func _wait_raid_over(st: Settlement, frames: int) -> int:
	var n := 0
	while st.raid_phase != Settlement.RaidPhase.NONE and n < frames:
		await wait_physics(1)
		n += 1
	return n


# ---------------------------------------------------------------- when

func test_raids_come_every_couple_of_days_with_a_warning() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	st.simulate(200.0)
	check(st.raid_phase == Settlement.RaidPhase.NONE, "no raids on a farm you haven't claimed")
	await _claimed(zone)
	check(st.next_raid_in >= 36.0 and st.next_raid_in <= 60.0, "the first raid in about two days (%.0f h)" % st.next_raid_in)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	st.next_raid_in = 2.4
	st.simulate(0.5)
	check(st.raid_phase == Settlement.RaidPhase.WARNED, "two hours out: a warning")
	check(said.any(func(t: String) -> bool: return t.begins_with("Raiders seen coming for Ash Creek Farms")), "a notice: %s" % [said])
	check(st.raid_size == 2, "two raiders for an empty farm")
	var mark := st.get_node_or_null("RaidMarker") as Landmark
	check(mark != null and mark.marker_color == Settlement.RAID_COLOR and mark.get_compass_name() == "Raiders", "a red Raiders marker on the compass")
	check(mark.global_position.distance_to(st.global_position) > 90.0, "out where they were seen (%.0f m off)" % mark.global_position.distance_to(st.global_position))
	var hud := zone.get_node("HUD") as HUD
	hud.map_screen.view.player = _player(zone)
	check(hud.map_screen.view.markers().any(func(m: Dictionary) -> bool: return m["kind"] == "raid"), "and on the map")
	st.simulate(1.95)
	check(st.raid_phase == Settlement.RaidPhase.ACTIVE and st.raiders.size() == 2, "then they arrive")
	for r in st.raiders:
		check(r.raid == st and r.raid_phase == Raider.RaidPhase.APPROACH, "%s is raiding" % r.name)
	await _free(zone)


func test_bigger_farms_draw_bigger_raids() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	for i in 6:
		await _newcomer(zone, Settler.Role.FARMER)
	st.warn_raid(2.0)
	check(st.raid_size == 5, "six settlers: five raiders (%d)" % st.raid_size)
	st.start_raid()
	var vets := st.raiders.filter(func(r: Raider) -> bool: return r.display_name != "Raider")
	check(st.raiders.size() == 5 and vets.size() == 1, "one of them a veteran")
	await _free(zone)


# ---------------------------------------------------------------- what they do

func test_raiders_take_from_the_stores_and_run_off() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	for site in st.sites():
		site.queue_free()  # (so the fences don't take the planks first)
	await wait_physics(1)
	st.store.inventory.add_item(VEG, 60 - st.food())
	st.store.inventory.add_item(PLANK, 20)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	_raid_close(st, 2)
	var raider := st.raiders[0]
	var looted := false
	var n := 0
	while st.raid_phase != Settlement.RaidPhase.NONE and n < 3600:
		await wait_physics(1)
		n += 1
		if is_instance_valid(raider) and raider.raid_phase == Raider.RaidPhase.FLEE:
			looted = true
	check(looted, "they reached the barn and loaded up")
	check(st.raid_phase == Settlement.RaidPhase.NONE, "the raid's over (%.1f s)" % (n / 60.0))
	check(st.food() == 30 and st.planks() == 4, "two raiders took 30 vegetables and 16 planks (left: %d, %d)" % [st.food(), st.planks()])
	check(int(st.raid_report["escaped"]) == 2, "both got away")
	check(said.any(func(t: String) -> bool: return t.contains("Raid over") and t.contains("30 Fresh Vegetables")), "the report: %s" % [said.back() if not said.is_empty() else ""])
	check(st.next_raid_in > 30.0, "the next one in a couple of days")
	check(st.get_node_or_null("RaidMarker") == null, "the marker's gone")
	await _free(zone)


func test_guards_fight_them_off_and_dropped_loot_is_kept() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	st.store.inventory.add_item(VEG, 40)
	var g := await _newcomer(zone, Settler.Role.GUARD)
	g.arm(RIFLE, 120)
	g.global_position = st.raid_goal() + Vector3.UP * 0.2
	_raid_close(st, 2)
	await _wait_raid_over(st, 3600)
	check(st.raid_phase == Settlement.RaidPhase.NONE and int(st.raid_report["killed"]) == 2, "the guard killed both (%s)" % st.raid_report)
	check(int(st.raid_report["escaped"]) == 0, "nobody got away")
	var stolen: Dictionary = st.raid_report["stolen"]
	check(stolen.values().all(func(v: Variant) -> bool: return int(v) == 0), "nothing lost for good: %s" % stolen)
	await _free(zone)


func test_guards_go_to_raiders_they_cant_see() -> void:
	# A guard at a post round the far side of the farm: before 20.5 they
	# stood there while raiders from the other side emptied the barn
	var zone := await load_zone()
	var st := await _claimed(zone)
	st.store.inventory.add_item(VEG, 40)
	var g := await _newcomer(zone, Settler.Role.GUARD)
	g.arm(RIFLE, 120)
	var site := st.get_parent() as Node3D
	g.global_position = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, site.to_global(Vector3(-40, 0, -40))) + Vector3.UP * 0.2
	st.warn_raid(0.0)
	st.raid_from = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, site.to_global(Vector3(70, 0, 10)))
	st.raid_size = 2
	st.start_raid()
	var r := st.raiders[0]
	check(not g._can_see(r) or g.global_position.distance_to(r.global_position) > g.guard_range, "out of the guard's sight to start with")
	var start := g.global_position
	await wait_physics(240)
	check(g.global_position.distance_to(start) > 5.0 or g.state == Settler.State.FIGHT, "the guard heads for them (%.0f m)" % g.global_position.distance_to(start))
	await _wait_raid_over(st, 3600)
	check(int(st.raid_report["killed"]) == 2 and int(st.raid_report["escaped"]) == 0, "and kills both: %s" % st.raid_report)
	await _free(zone)


func test_settlers_shelter_or_go_down_wounded() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var f := await _newcomer(zone, Settler.Role.FARMER)
	_raid_close(st, 2)
	await wait_physics(10)
	check(st.raid_active() and f.status_text() == "Sheltering from the raid", "the farmer shelters: %s" % f.status_text())
	var shelter := st.get_node("Shelter") as Node3D
	check(f._goal.distance_to(shelter.global_position) < 3.0, "in the farmhouse")
	# A raider gets to them
	var r := st.raiders[0]
	f.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.MELEE, r))
	await wait_physics(2)
	check(f.is_down() and not f.is_dead() and st.members().has(f), "down, wounded, not dead")
	check(f.status_text().begins_with("Wounded") and not f.is_working(), "status: %s" % f.status_text())
	check((st.raid_report["wounded"] as Array).has(f.settler_name), "on the raid's report")
	check(not Raider.is_alive_target(f), "raiders leave the downed alone")
	# Help them up
	p.inventory.clear()
	check(not st.request_help_up(p, f), "no bandage: can't")
	p.inventory.add_item(BANDAGE, 1)
	await wait_physics(1)
	check(f.talk.get_prompt(p).begins_with("Help ") and is_equal_approx(f.talk.hold_time, 2.0), "E (held): %s" % f.talk.get_prompt(p))
	p.talk_to(f)
	check(not f.is_down() and is_equal_approx(f.health.get_fraction(), 0.5) and p.inventory.count_of(&"bandage") == 0, "a bandage: back up at half health")
	await _free(zone)


func test_left_down_too_long_they_die() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var f := await _newcomer(zone, Settler.Role.FARMER)
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = st.global_position + Vector3(0, 0.1, 300)
	f.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.MELEE, r))
	check(f.is_down(), "down")
	st.simulate(11.0)
	check(f.is_down(), "still holding on after 11 hours")
	st.simulate(1.5)
	check(f.is_dead() and not st.members().has(f), "12 hours down: they die")
	await _free(zone)


func test_raiders_hack_through_fences_in_the_way() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	# One raider boxed in by four lengths of fence
	var at := st.global_position + st.global_basis * Vector3(0, 0, 60)
	at = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, at)
	var def := SettlementPlans.structure(&"fence")
	var fences: Array[Structure] = []
	for i in 4:
		var f := (load(def.scene_path) as PackedScene).instantiate() as Structure
		var yaw := i * PI / 2.0
		zone.get_node("Structures").add_child(f)
		f.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Basis(Vector3.UP, yaw) * Vector3(0, 0, 2.0))
		fences.append(f)
	await wait_physics(30)
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = at + Vector3.UP * 0.1
	st.raid_phase = Settlement.RaidPhase.ACTIVE
	r.join_raid(st, at + Vector3(0, 0, 40))
	var hit := false
	for i in 900:
		await wait_physics(1)
		if fences.any(func(f: Structure) -> bool: return not is_instance_valid(f) or f.is_damaged()):
			hit = true
			break
	check(hit, "it hacks at a fence to get out")
	await _free(zone)


# ---------------------------------------------------------------- saving

func test_a_raid_on_its_way_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_raids"
	var zone := await load_zone()
	var st := await _claimed(zone)
	st.warn_raid(1.5)
	var from := st.raid_from
	var size := st.raid_size
	check(saves.save_game("raid", zone) == OK, "saved with raiders on their way")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("raid", zone2) == OK, "loaded")
	await wait_physics(4)
	var st2 := _farm(zone2)
	check(st2.raid_phase == Settlement.RaidPhase.WARNED and st2.raid_from.distance_to(from) < 0.5 and st2.raid_size == size, "still coming, from the same side")
	check(st2.next_raid_in <= 1.5 and st2.next_raid_in >= 0.25, "about as far off (%.2f h)" % st2.next_raid_in)
	check(st2.get_node_or_null("RaidMarker") != null, "with its marker")
	# A raid under way when saved comes back as raiders close by
	st2.away_range = 100000.0
	st2.start_raid()
	check(saves.save_game("raid2", zone2) == OK, "saved mid-raid")
	await _free(zone2)
	var zone3 := await load_zone()
	saves.load_game("raid2", zone3)
	await wait_physics(4)
	var st3 := _farm(zone3)
	check(st3.raid_phase == Settlement.RaidPhase.WARNED and st3.next_raid_in <= 0.26, "they are back at the edge of the farm, about to come in (%s, %.2f)" % [st3.raid_phase, st3.next_raid_in])
	await _free(zone3)
