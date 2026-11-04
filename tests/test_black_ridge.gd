extends "res://tests/test_case.gd"
## Increment 23: Black Ridge Mine becomes a settlement. Clear its raiders and
## claim it at the notice board by the road; Miners dig Scrap Metal out of
## the tunnel into the stores. It has no fields, so food comes by truck
## (settlers eat cooked dishes from the stores). The settlement screen
## switches between your places, survivors join the nearest one with a bed,
## and raiders come for the mine like the farm.

const DT := 1.0 / 60.0
## Far from both places, inside the zone.
const AWAY := Vector3(120, 0.1, 40)

var STEW: ItemDefinition = load("res://resources/items/vegetable_stew.tres")


func _mine(zone: Node3D) -> Settlement:
	return zone.get_node("BlackRidgeMine/Settlement") as Settlement


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s (%s)" % [st.settlement_name, st.claim_refusal_reason(p)])
	st.next_raid_in = 9999.0


func _newcomer(zone: Node3D, st: Settlement, role: Settler.Role) -> Settler:
	var p := _player(zone)
	var back := p.global_position
	p.global_position = AWAY
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	if role != Settler.Role.NONE:
		check(st.request_set_role(p, s, role), "%s: %s (%s)" % [s.settler_name, Settler.ROLE_NAMES[role], st.role_refusal_reason(role)])
	return s


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _on_navmesh(zone: Node3D, at: Vector3) -> bool:
	var map := zone.get_world_3d().navigation_map
	var on := NavigationServer3D.map_get_closest_point(map, at)
	return Vector2(on.x - at.x, on.z - at.z).length() < 0.8 and absf(on.y - at.y) < 1.2


# ---------------------------------------------------------------- the place

func test_the_mine_is_a_settlement() -> void:
	var zone := await load_zone(["BlackRidgeMine"])
	var st := _mine(zone)
	check(st != null and st.settlement_id == &"black_ridge" and st.settlement_name == "Black Ridge Mine", "Black Ridge Mine has a settlement")
	check(Settlement.find(get_tree(), &"black_ridge") == st and Settlement.find(get_tree(), &"ash_creek") == _farm(zone), "found by id, beside Ash Creek's")
	check(st.claim_point != null and st.pump != null and st.store != null and st.armory != null, "a notice board, a pump on the well, stores and an Armory Locker")
	check(st.store.inventory.slot_count == 60 and st.store.get("container_name") == "Mine Stores", "the Mine Stores: 60 slots of shelving")
	check(st.mine_spots().size() == 4, "four rock faces in the tunnel")
	check(st.farm_spots().is_empty() and st.wood_spots().is_empty(), "no fields, no woodlot")
	check(st.total_beds() == 4, "beds for four")
	# Everything settlers and raiders walk to is somewhere they can stand
	var points: Array[Node3D] = []
	points.append_array(st.mine_spots())
	points.append_array(st.guard_posts())
	for n in ["ArrivalPoint", "Hangout", "Shelter"]:
		points.append(st.get_node(n) as Node3D)
	for c in st.get_node("RaidPoints").get_children():
		points.append(c as Node3D)
	for m in points:
		check(_on_navmesh(zone, m.global_position), "%s is on the navmesh (%s)" % [m.name, m.global_position])
	check(_on_navmesh(zone, st.raid_goal()), "the stores' front is reachable")
	# Claiming: not with raiders about
	var p := _player(zone)
	await wait_physics(30)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	var here := st.raiders_here()
	if here > 0:
		check(st.claim_refusal_reason(p).contains("clear the mine first"), "raiders still here: %s" % st.claim_refusal_reason(p))
		for e in get_tree().get_nodes_in_group("enemies"):
			(e as Node).queue_free()
		await wait_physics(3)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	check(st.request_claim(p), "then it's yours: %s" % st.claim_refusal_reason(p))
	check(st.is_claimed and st.food() == 8 and st.water > 0.0, "with a little food and water to start (%d vegetables)" % st.food())
	check(said.any(func(t: String) -> bool: return t.contains("Black Ridge Mine is yours")), "a notice: %s" % [said])
	var spawners := zone.get_node("BlackRidgeMine").find_children("*", "EnemySpawner", true, false)
	check(spawners.all(func(n: Node) -> bool: return not (n as EnemySpawner).enabled), "its raiders stop coming")
	var mark := false
	for n in get_tree().get_nodes_in_group("landmarks"):
		var l := n as Landmark
		if l.display_name == "Black Ridge Mine":
			mark = l.marker_color == Settlement.CLAIMED_COLOR
	check(mark, "green on the compass and map")
	check(not _farm(zone).is_claimed, "Ash Creek isn't claimed by it")
	await _free(zone)


# ---------------------------------------------------------------- miners

func test_miners_dig_scrap_metal() -> void:
	var zone := await load_zone()
	var mine := _mine(zone)
	var farm := _farm(zone)
	await _claim(zone, farm)
	await _claim(zone, mine)
	check(farm.role_refusal_reason(Settler.Role.MINER).begins_with("No mine here"), "no Miners at the farm: %s" % farm.role_refusal_reason(Settler.Role.MINER))
	check(mine.role_refusal_reason(Settler.Role.FARMER).begins_with("No fields here"), "no Farmers at the mine (until a farm plot): %s" % mine.role_refusal_reason(Settler.Role.FARMER))
	check(mine.role_refusal_reason(Settler.Role.WOODCUTTER) == "No woodlot here", "nor Woodcutters")
	var a := await _newcomer(zone, mine, Settler.Role.MINER)
	var b := await _newcomer(zone, mine, Settler.Role.MINER)
	check(a.role == Settler.Role.MINER and a.role_name() == "Miner" and a.status_text() == "Mining", "Miners: %s" % a.status_text())
	check((a.visual.get_node("HardHat") as Node3D).visible and (a.visual.get_node("HeadLamp") as Node3D).visible
		and (a.visual.get_node("RightArm/Pickaxe") as Node3D).visible, "in a hard hat with a lamp, with a pickaxe")
	var before := mine.scrap()
	mine.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 20)
	mine.simulate(3.0)
	check(mine.scrap() - before == 12, "two Miners, three hours: 12 Scrap Metal in the stores (%d)" % (mine.scrap() - before))
	check(mine.rates()["scrap"] == 4.0 and mine.rates()["miners"] == 2, "4 an hour")
	check(farm.store.inventory.count_of(&"scrap_metal") == 0, "none in the farm's own stores")
	# One to a rock face: a fifth Miner adds nothing
	for i in 2:
		await _newcomer(zone, mine, Settler.Role.MINER)
	check(mine.rates()["miners"] == 4, "four rock faces, four Miners")
	# Hungry miners stop
	mine.store.inventory.remove_item(&"vegetables", mine.food())
	for s in mine.members():
		s.unfed_hours = 2.0
	check(not a.is_working(), "hungry: they stop")
	await _free(zone)


func test_miners_walk_to_the_rock_face() -> void:
	var zone := await load_zone()
	var mine := _mine(zone)
	await _claim(zone, mine)
	mine.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 20)
	var a := await _newcomer(zone, mine, Settler.Role.MINER)
	var spot := mine.mine_spots()[0].global_position
	var there := false
	for i in 60:
		await wait_physics(60)
		if a.global_position.distance_to(spot) < 1.2:
			there = true
			break
	check(there, "walked into the tunnel to the rock face (%.1f m off)" % a.global_position.distance_to(spot))
	await wait_physics(120)
	check(a.state == Settler.State.WORK, "and is digging")
	await _free(zone)


# ---------------------------------------------------------------- food by truck

func test_settlers_eat_cooked_food_from_the_stores() -> void:
	var zone := await load_zone()
	var mine := _mine(zone)
	await _claim(zone, mine)
	mine.store.inventory.remove_item(&"vegetables", mine.food())
	check(mine.food() == 0 and mine.kitchens().is_empty(), "no vegetables, no kitchen")
	var a := await _newcomer(zone, mine, Settler.Role.MINER)
	mine.store.inventory.add_item(STEW, 2)
	check(mine.stored_dishes() == [2, 8.0], "two Vegetable Stews on the shelves: 8 meals")
	check(mine.fridge_meals() >= 8.0, "they count as food (newcomers come for them)")
	mine.simulate(mine.meal_every_hours + 0.1)
	check(a.is_working() and a.unfed_hours == 0.0, "the Miner ate")
	check(mine.stored_dishes()[0] == 1, "from a stew (%s)" % [mine.stored_dishes()])
	await _free(zone)


# ---------------------------------------------------------------- survivors

func test_old_jeb_stays_at_the_mine() -> void:
	var zone := await load_zone()
	var p := _player(zone)
	await _claim(zone, _farm(zone))
	await _claim(zone, _mine(zone))
	var jeb: Settler = null
	for n in get_tree().get_nodes_in_group("settlers"):
		if (n as Settler).settler_name == "Old Jeb":
			jeb = n
	check(jeb != null and jeb.settlement == null, "Old Jeb, waiting in the mine's bunkhouse")
	check(p.best_settlement_for_recruit(jeb.global_position) == _mine(zone), "the nearest place of yours with a bed: the mine")
	p.global_position = jeb.global_position + Vector3(0, 0, 1.5)
	await wait_physics(3)
	p.talk_to(jeb)
	check(jeb.settlement == _mine(zone), "asked, he stays at Black Ridge")
	var maya: Settler = null
	for n in get_tree().get_nodes_in_group("settlers"):
		if (n as Settler).settler_name == "Maya":
			maya = n
	check(p.best_settlement_for_recruit(maya.global_position) == _farm(zone), "Maya, at Saint Mercy, goes to the farm")
	await _free(zone)


# ---------------------------------------------------------------- the screen

func test_the_screen_switches_between_places() -> void:
	var zone := await load_zone()
	var hud := zone.get_node("HUD") as HUD
	var screen := hud.settlement_screen
	var p := _player(zone)
	var mine := _mine(zone)
	var farm := _farm(zone)
	await _claim(zone, farm)
	screen.open()
	check(screen.settlement == farm and not screen._tabs.visible, "one place: no tabs")
	screen.close()
	await _claim(zone, mine)
	var jeb := await _newcomer(zone, mine, Settler.Role.MINER)
	# At the mine, L opens the mine
	p.global_position = mine.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(3)
	screen.open()
	check(screen.settlement == mine, "at the mine, L opens the mine")
	check(screen._tabs.visible and screen._tabs.get_child_count() == 2, "tabs for both places")
	check(screen._title.text.contains("BLACK RIDGE MINE"), "titled: %s" % screen._title.text)
	check(screen._stocks.text.contains("Scrap Metal:") and screen._stocks.text.contains("Miners working:"), "the mine's stocks: %s" % screen._stocks.text.replace("\n", " | "))
	check(screen._stocks.text.contains("Cooked food in the stores:") and not screen._stocks.text.contains("Farmers working"), "food by truck, no farmers line")
	check(screen._how.text.contains("Miners dig Scrap Metal") and screen._how.text.contains("the bunkhouse"), "how it works here: %s" % screen._how.text)
	var row := screen._list.get_child(0)
	var miner_job := row.find_child("Job_Miner", true, false) as Button
	check(miner_job != null and not miner_job.disabled and miner_job.button_pressed, "the Miner job, picked")
	# Switch to the farm
	(screen._tabs.get_child(0) as Button).pressed.emit()
	check(screen.settlement == farm and screen._title.text.contains("ASH CREEK"), "the farm's tab: %s" % screen._title.text)
	check(not screen._stocks.text.contains("Scrap Metal:") and screen._stocks.text.contains("Fresh Vegetables"), "the farm's stocks")
	check(jeb.settlement == mine, "(the mine's settler stays at the mine)")
	screen.close()
	await _free(zone)


# ---------------------------------------------------------------- raids and saving

func test_raids_come_for_the_mine() -> void:
	var zone := await load_zone()
	var mine := _mine(zone)
	await _claim(zone, mine)
	var g := await _newcomer(zone, mine, Settler.Role.GUARD)
	var said := []
	mine.notice.connect(func(t: String) -> void: said.append(t))
	mine.warn_raid(0.05)
	check(mine.raid_phase == Settlement.RaidPhase.WARNED, "raiders are seen coming")
	check(said.any(func(t: String) -> bool: return t.contains("Black Ridge Mine")), "a warning naming the mine: %s" % [said])
	# You're far off: it's settled on paper, like the farm's
	_player(zone).global_position = AWAY
	await wait_physics(3)
	mine._check_player_near()
	mine.simulate(0.1)
	await wait_physics(5)
	check(mine.raid_phase == Settlement.RaidPhase.NONE and mine.next_raid_in > 0.0, "it's over, and the next one's due")
	check(said.any(func(t: String) -> bool: return t.contains("While you were away") and t.contains("Black Ridge Mine")), "reported: %s" % [said])
	check(_farm(zone).raid_phase == Settlement.RaidPhase.NONE and not _farm(zone).is_claimed, "the farm's untouched")
	await _free(zone)


func test_the_mine_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_black_ridge"
	var zone := await load_zone()
	var mine := _mine(zone)
	await _claim(zone, mine)
	var a := await _newcomer(zone, mine, Settler.Role.MINER)
	var name_a := a.settler_name
	mine.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 10)
	mine.arrival_in = 999.0  # no newcomers in the middle of this
	mine.simulate(1.25)
	var scrap := mine.scrap()
	check(saves.save_game("mine", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("mine", zone2) == OK, "loaded")
	await wait_physics(5)
	var mine2 := _mine(zone2)
	check(mine2.is_claimed and not _farm(zone2).is_claimed, "the mine is still yours, the farm isn't")
	check(mine2.scrap() == scrap, "its scrap (%d)" % mine2.scrap())
	var back := mine2.members()
	check(back.size() == 1 and back[0].settler_name == name_a and back[0].role == Settler.Role.MINER, "and its Miner (%s)" % [back.map(func(s: Settler) -> String: return "%s %s %s" % [s.settler_name, s.role_name(), s.get_path()])])
	mine2.simulate(0.75)
	check(mine2.scrap() == scrap + 2, "half a Scrap Metal carried over: 1.25 h + 0.75 h is 4 (%d)" % (mine2.scrap() - scrap))
	await _free(zone2)
