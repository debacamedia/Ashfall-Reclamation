extends "res://tests/test_case.gd"
## Increment 25: the mid zone, and the way in. A second zone east of the
## early zone, laid out from the Regional Buildout Map, with its seven
## places as blockouts. The road east out of Halden's runs through a gap
## in the storm: cross the edge there and you travel, with your truck and
## its cargo if you're driving. Settlements you hold keep running while
## you're in the other zone: they catch up when you come back.

const MID := "res://levels/mid_zone/mid_zone.tscn"
const EARLY := "res://levels/early_zone/early_zone.tscn"
const MID_PLACES := {
	"RedMesa": "Red Mesa", "DryRiverPumpStation": "Dry River Pump Station", "CinderQuarry": "Cinder Quarry",
	"IronVeinRailYard": "Iron Vein Rail Yard", "Dusthaven": "Dusthaven",
	"BrokenSpurTruckStop": "Broken Spur Truck Stop", "RaiderCampScorch": "Raider Camp Scorch",
}
const AWAY := Vector3(120, 0.1, 40)

var world: Node


func _init() -> void:
	tree_entered.connect(func() -> void:
		world = get_node("/root/WorldManager")
		world.reset())
	tree_exiting.connect(func() -> void: world.reset())


func _mid() -> Node3D:
	var zone := (load(MID) as PackedScene).instantiate() as Node3D
	var p := zone.get_node("Player") as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	add_child(zone)
	await wait_physics(30)
	await wait_for_navigation(zone.get_world_3d().navigation_map)
	return zone


func _free(zone: Node) -> void:
	if zone != null and is_instance_valid(zone):
		zone.get_parent().remove_child(zone)
		zone.free()
	await wait_physics(2)


func _polygon(scene_path: String) -> PackedVector2Array:
	var zone := (load(scene_path) as PackedScene).instantiate()
	var poly: PackedVector2Array = (zone.get_node("Boundary") as ZoneBoundary).polygon
	zone.free()
	return poly


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


# ---------------------------------------------------------------- the zone

func test_the_mid_zone() -> void:
	var zone := await _mid()
	check(zone is Zone and zone.get_meta("region_name") == "Mid Zone", "a zone of its own: the Mid Zone")
	var edge := zone.get_node("Boundary") as ZoneBoundary
	var map := zone.get_world_3d().navigation_map
	var spawn := (zone.get_node("PlayerSpawn") as Node3D).global_position
	check(edge.is_inside(spawn), "you start (and respawn) inside it, where the road comes in")
	var marks := zone.get_node("Landmarks")
	check(marks.get_child_count() == 7, "seven places (%d)" % marks.get_child_count())
	var from := NavigationServer3D.map_get_closest_point(map, spawn)
	for key: String in MID_PLACES:
		var l := marks.get_node_or_null(key) as Landmark
		check(l != null and l.display_name == MID_PLACES[key], "%s is on the compass" % MID_PLACES[key])
		if l == null:
			continue
		check(edge.is_inside(l.global_position) and -edge.signed_distance(l.global_position) > l.radius * 0.8,
			"%s is well inside the edge" % l.display_name)
		check(zone.get_node("Blockouts/" + key).get_child_count() >= 6, "%s is blocked out" % l.display_name)
		var path := NavigationServer3D.map_get_path(map, from, NavigationServer3D.map_get_closest_point(map, l.global_position), true)
		var end := path[path.size() - 1] if path.size() > 0 else Vector3.INF
		check(Vector2(end.x - l.global_position.x, end.z - l.global_position.z).length() < 3.0,
			"you can walk from the road in to %s" % l.display_name)
	var m: ZoneMap = (zone as Zone).get_map()
	check(m != null and m.title == "Mid Zone" and m.texture != null, "it has its own map (M)")
	check(m.world_rect.encloses(Rect2(Vector2(300, -920), Vector2(760, 1195))), "covering all of it")
	check(zone.get_node_or_null("Roads/Rail") != null or zone.find_child("Rail*", true, false) != null, "the railway runs on through the rail yard")
	await _free(zone)


func test_the_zones_meet() -> void:
	var early := _polygon(EARLY)
	var mid := _polygon(MID)
	var overlap := 0.0
	for piece in Geometry2D.intersect_polygons(early, mid):
		overlap += _area(piece)
	check(overlap < 1.0, "the zones don't overlap (%.2f m²)" % overlap)
	check(_area(mid) > 400000.0, "the mid zone is big: %.0f m² (the early zone is %.0f)" % [_area(mid), _area(early)])
	# The way through: the same spot in both, on the road east out of Halden's
	var e := (load(EARLY) as PackedScene).instantiate()
	var md := (load(MID) as PackedScene).instantiate()
	var out_e := e.get_node("Boundary/ToMidZone") as ZoneExit
	var out_m := md.get_node("Boundary/ToEarlyZone") as ZoneExit
	check(out_e != null and out_m != null, "a way through on each side")
	check(out_e.position.distance_to(out_m.position) < 0.5, "at the same spot")
	check(out_e.target_level == MID and out_m.target_level == EARLY, "each leading to the other")
	var arrive_m := md.get_node("Arrivals/" + str(out_e.arrival_id)) as Node3D
	var arrive_e := e.get_node("Arrivals/" + str(out_m.arrival_id)) as Node3D
	check(arrive_m != null and arrive_e != null, "with somewhere to arrive")
	check(Geometry2D.is_point_in_polygon(Vector2(arrive_m.position.x, arrive_m.position.z), mid)
		and Geometry2D.is_point_in_polygon(Vector2(arrive_e.position.x, arrive_e.position.z), early), "each just inside its zone")
	check(arrive_m.position.distance_to(out_m.position) < 40.0 and arrive_e.position.distance_to(out_e.position) < 40.0, "close to the way through")
	check(e.find_child("ExitSign_MidZone", true, false) != null and md.find_child("ExitSign_EarlyZone", true, false) != null, "with a sign by the road")
	e.free()
	md.free()


func test_the_road_through_the_storm() -> void:
	var zone := await load_zone()
	var edge := zone.get_node("Boundary") as ZoneBoundary
	var through := Vector3(662, 0.1, -288)
	var beside := Vector3(662, 0.1, -330)
	check(not edge.is_inside(through) and edge.exit_at(through) != null, "past the edge, on the road")
	check(edge.damage_per_second_at(through) == 0.0, "the storm doesn't hurt on the road out")
	check(edge.warning_at(Vector3(650, 0.1, -288)).contains("the Mid Zone"), "the warning says where the road goes: %s" % edge.warning_at(Vector3(650, 0.1, -288)))
	check(edge.damage_per_second_at(beside) > 0.0 and edge.exit_at(beside) == null, "off the road it still does")
	check(edge.warning_at(beside).contains("Turn back"), "and says turn back")
	await _free(zone)


# ---------------------------------------------------------------- travel

func test_walking_to_the_mid_zone_and_back() -> void:
	var zone := await load_zone()
	var previous := get_tree().current_scene
	# Travel swaps the current scene, which has to sit under the root
	remove_child(zone)
	get_tree().root.add_child(zone)
	get_tree().current_scene = zone
	var p := zone.get_node("Player") as PlayerController
	p.inventory.add_item(load("res://resources/items/scrap_metal.tres"), 5)
	var scrap := p.inventory.count_of(&"scrap_metal")
	p.health.apply_damage(DamageInfo.create(20.0, DamageInfo.Type.FALL))
	var said := []
	var on_arrive := func(r: String) -> void: said.append(r)
	world.arrived.connect(on_arrive)
	# Walk out through the storm on the road east
	p.global_position = Vector3(661, 0.1, -288)
	await wait_physics(4)
	check(world.is_travelling, "crossing the edge on the road: on your way")
	while world.is_travelling:
		await get_tree().process_frame
	var mid := get_tree().current_scene
	check(mid != null and mid.scene_file_path == MID, "in the mid zone")
	var p2 := world.find_player(mid) as PlayerController
	check(p2 != null and p2.global_position.distance_to(Vector3(682, 0.05, -291)) < 1.0, "where the road comes in (%s)" % (p2.global_position if p2 != null else Vector3.INF))
	check(p2.inventory.count_of(&"scrap_metal") == scrap and is_equal_approx(p2.health.current_health, 80.0), "with your things and your health")
	check(said.has("Mid Zone"), "Arrived at Mid Zone")
	check(world.region_states.has(EARLY), "the early zone is remembered while you're gone")
	var screen := (mid.get_node("HUD") as HUD).settlement_screen
	screen.open()
	check(screen._empty.visible and screen._empty.text.contains("keep running"), "L: no settlements here; yours elsewhere keep running")
	screen.close()
	# And back
	p2.global_position = Vector3(651, 0.1, -288)
	await wait_physics(4)
	check(world.is_travelling, "back through the storm")
	while world.is_travelling:
		await get_tree().process_frame
	var back := get_tree().current_scene
	check(back.scene_file_path == EARLY, "in the early zone again")
	check((world.find_player(back) as PlayerController).global_position.distance_to(Vector3(630, 0.05, -285)) < 1.0, "on the road home")
	check(world.region_states.has(MID) and not world.region_states.has(EARLY), "now the mid zone's remembered")
	world.arrived.disconnect(on_arrive)
	get_tree().current_scene = previous
	await _free(back)


func test_the_truck_comes_too() -> void:
	var early := await load_zone()
	var p := early.get_node("Player") as PlayerController
	var truck := early.get_node("Vehicles/CargoTruck") as Truck
	truck.cargo.inventory.add_item(load("res://resources/items/scrap_metal.tres"), 9)
	truck.global_position = Vector3(640, 0.6, -286)
	await wait_physics(3)
	check(p.enter_vehicle(truck), "at the wheel")
	var data: Dictionary = world.capture_region(early, truck, MID)
	check(world.carried_vehicle.size() == 2, "the truck and its cargo go with you (%d)" % world.carried_vehicle.size())
	var left: Array = world.region_states[EARLY]["nodes"]
	check(not left.any(func(e: Dictionary) -> bool: return str(e["path"]).begins_with("Vehicles/CargoTruck")), "and aren't left behind")
	check(world.vehicle_zones.get("CargoTruck") == MID, "the truck's in the mid zone now")
	await _free(early)
	var mid := await _mid()
	world.enter_region(mid, data, &"FromEarlyZone")
	await wait_physics(3)
	var p2 := mid.get_node("Player") as PlayerController
	var t2 := mid.get_node_or_null("Vehicles/CargoTruck") as Truck
	check(t2 != null and p2.vehicle == t2 and t2.driver == p2, "you drive in with it")
	check(t2 != null and t2.cargo.inventory.count_of(&"scrap_metal") == 9, "its cargo too")
	check(t2 != null and t2.global_position.distance_to(Vector3(682, 0.45, -291)) < 2.0, "at the road in (%s)" % (t2.global_position if t2 != null else Vector3.INF))
	check(t2 != null and (t2.global_basis * Vector3(0, 0, 1)).x > 0.9, "facing on into the zone")
	# Park it and walk home
	p2.leave_vehicle(true)
	var data2: Dictionary = world.capture_region(mid)
	check((world.region_states[MID]["nodes"] as Array).any(func(e: Dictionary) -> bool: return str(e["path"]) == "Vehicles/CargoTruck"), "parked, it stays in the mid zone")
	await _free(mid)
	var early2 := instance_zone()
	add_child(early2)
	await wait_physics(5)
	world.enter_region(early2, data2, &"FromMidZone")
	await wait_physics(2)
	check(early2.get_node_or_null("Vehicles/CargoTruck") == null, "so it's not at Outpost 17")
	var saved: Dictionary = get_node("/root/SaveManager").build_save_data(early2)
	check(saved["vehicle_zones"].get("CargoTruck") == MID, "a save knows where it is")
	var data3: Dictionary = world.capture_region(early2)
	await _free(early2)
	# Back to the mid zone on foot: it's where you left it
	var mid2 := await _mid()
	world.enter_region(mid2, data3, &"FromEarlyZone")
	await wait_physics(2)
	var t3 := mid2.get_node_or_null("Vehicles/CargoTruck") as Truck
	check(t3 != null and t3.cargo.inventory.count_of(&"scrap_metal") == 9, "the truck's waiting, still loaded")
	await _free(mid2)
	# A save made with the truck away: loaded into the early zone, no truck there
	var early3 := instance_zone()
	add_child(early3)
	await wait_physics(5)
	world.set_vehicle_zones({"CargoTruck": MID}, early3)
	await wait_physics(1)
	check(early3.get_node_or_null("Vehicles/CargoTruck") == null, "loading a save made with the truck away leaves it away")
	world.set_vehicle_zones({}, early3)
	await _free(early3)


# ---------------------------------------------------------------- settlements while you're away

func _claim(zone: Node3D, st: Settlement) -> void:
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s" % st.settlement_name)
	st.arrival_in = 9999.0


func test_settlements_keep_running() -> void:
	var zone := await load_zone()
	var farm := Settlement.find(get_tree(), &"ash_creek")
	await _claim(zone, farm)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = AWAY
	for i in 2:
		var s := farm.spawn_newcomer()
		await wait_physics(70)
		farm.request_set_role(p, s, Settler.Role.FARMER if i == 0 else Settler.Role.GUARD)
	farm.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 30)
	farm.next_raid_in = 5.0  # raiders due while you're gone
	var hours_before := farm.clock_hours
	p.global_position = Vector3(630, 0.1, -285)
	await wait_physics(3)
	var data: Dictionary = world.capture_region(zone)
	await _free(zone)
	# 12 settlement hours in the mid zone (a minute each)
	world.region_states[EARLY]["away_seconds"] = 12.0 * 60.0
	var summaries := []
	var on_sum := func(t: String) -> void: summaries.append(t)
	world.caught_up.connect(on_sum)
	var back := instance_zone()
	add_child(back)
	await wait_physics(30)
	await wait_for_navigation(back.get_world_3d().navigation_map)
	world.enter_region(back, data, &"FromMidZone")
	var farm2 := Settlement.find(get_tree(), &"ash_creek")
	check(farm2.is_claimed and not farm2.catching_up, "the farm's still yours")
	check_near(farm2.clock_hours - hours_before, 12.0, 0.2, "12 hours went by there")
	check_near(float(world.last_catch_up.get("Ash Creek Farms", 0.0)), 12.0, 0.1, "caught up 12 hours")
	check(farm2.raid_phase == Settlement.RaidPhase.NONE and farm2.log_entries.any(func(e: Dictionary) -> bool: return str(e["text"]).begins_with("While you were away")),
		"the raid came and was settled as if you were far off")
	check(summaries.size() == 1 and summaries[0].contains("Ash Creek Farms: raided") and summaries[0].contains("12 min"), "a summary: %s" % [summaries])
	check(farm2.members().size() >= 1, "your settlers are still there (%d)" % farm2.members().size())
	world.caught_up.disconnect(on_sum)
	# A long absence stops at a week
	world.catch_up(back, 1000.0 * 60.0)
	check(is_equal_approx(float(world.last_catch_up.get("Ash Creek Farms", 0.0)), 168.0), "a long time away counts as a week at most")
	await _free(back)


func test_the_news_in_a_few_words() -> void:
	var news := func(texts: Array) -> String:
		return world.describe_news(texts.map(func(t: String) -> Dictionary: return {"hour": 0.0, "text": t}))
	check(news.call([]) == "quiet", "nothing: quiet")
	check(news.call(["While you were away, 3 raiders hit Ash Creek Farms: 2 killed, 1 got away", "Quinn has left Ash Creek Farms: nothing to eat",
		"Vic died of their wounds", "Maya has arrived at Ash Creek Farms. Give them a job (L)"]) == "raided, 1 died, 1 left, 1 arrived", "the headlines")
	check(news.call(["Raid over: 4 killed", "Raid over: 3 killed"]) == "raided 2 times", "raids counted")
	check(news.call(["The pump's tank is full"]) == "1 thing", "anything else is counted")


func test_the_wounded_dont_walk_out_hungry() -> void:
	var zone := await load_zone()
	var farm := Settlement.find(get_tree(), &"ash_creek")
	await _claim(zone, farm)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = AWAY
	var s := farm.spawn_newcomer()
	await wait_physics(70)
	farm.request_set_role(p, s, Settler.Role.GUARD)
	for c in farm.stores():
		c.inventory.remove_item(&"vegetables", c.inventory.count_of(&"vegetables"))
	s._arrived = true  # they live here
	s.knock_down()
	farm.simulate(farm.leave_after_hours + 2.0)  # hungry past leaving, not yet bled out
	check(farm.members().has(s) and s.is_down(), "down and hungry, but still there to be helped up")
	await _free(zone)


func test_time_away_is_counted_and_saved() -> void:
	world.region_states[MID] = {"nodes": [], "away_seconds": 10.0}
	world._process(2.5)
	check(is_equal_approx(world.region_states[MID]["away_seconds"], 12.5), "time away from a zone adds up")
	get_tree().paused = true
	world._process(5.0)
	get_tree().paused = false
	check(is_equal_approx(world.region_states[MID]["away_seconds"], 12.5), "but not while paused")
	var saved: Dictionary = world.get_saved_regions(EARLY)
	world.reset()
	world.set_saved_regions(saved, EARLY)
	check(is_equal_approx(world.region_states[MID]["away_seconds"], 12.5), "it's saved")
	world.set_saved_regions({MID: {"nodes": [], "away_seconds": "lots"}}, EARLY)
	check(world.region_states[MID]["away_seconds"] == 0.0, "nonsense in a save counts as none")
	world.reset()
