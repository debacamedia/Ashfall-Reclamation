extends "res://tests/test_case.gd"
## Increment 23.5: Northwatch Outpost becomes a settlement. Clear its
## garrison and claim it at the notice board in front of the command post;
## Armorers make guns and rounds at the armory's weapons bench, following the
## same recipes you do (a pistol is 16 Scrap Metal through pipes, plate and
## springs), into the Armory Locker, for you to haul to your other places.

const AWAY := Vector3(120, 0.1, 40)

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var ELECTRONICS: ItemDefinition = load("res://resources/items/electronics.tres")
var GUNPOWDER: ItemDefinition = load("res://resources/items/gunpowder.tres")
var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")


func _nw(zone: Node3D) -> Settlement:
	return zone.get_node("NorthwatchOutpost/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s (%s)" % [st.settlement_name, st.claim_refusal_reason(p)])
	st.next_raid_in = 9999.0
	st.arrival_in = 9999.0


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


func _count(st: Settlement, id: StringName) -> int:
	return st.armory.inventory.count_of(id)


# ---------------------------------------------------------------- the place

func test_northwatch_is_a_settlement() -> void:
	var zone := await load_zone(["NorthwatchOutpost"])
	var st := _nw(zone)
	check(st != null and st.settlement_id == &"northwatch" and st.settlement_name == "Northwatch Outpost", "Northwatch has a settlement")
	check(st.claim_point != null and st.pump != null and st.store != null and st.armory != null, "a notice board, a pump, stores and an Armory Locker")
	check(st.store.get("container_name") == "Stores" and st.store.inventory.slot_count == 60, "Stores: 60 slots")
	check(st.armorer_spots().size() == 1, "a place at the weapons bench for an Armorer")
	var bench := zone.get_node("NorthwatchOutpost").find_child("ArmoryWeaponsBench", true, false) as Node3D
	check(bench != null and st.armorer_spots()[0].global_position.distance_to(bench.global_position) < 1.6, "in front of the armory's weapons bench")
	check(st.armory.global_position.distance_to(bench.global_position) < 6.0, "the Armory Locker is beside it")
	check(st.mine_spots().is_empty() and st.farm_spots().is_empty(), "no mine, no fields")
	var points: Array[Node3D] = []
	points.append_array(st.armorer_spots())
	points.append_array(st.guard_posts())
	for n in ["ArrivalPoint", "Hangout", "Shelter"]:
		points.append(st.get_node(n) as Node3D)
	for c in st.get_node("RaidPoints").get_children():
		points.append(c as Node3D)
	for m in points:
		check(_on_navmesh(zone, m.global_position), "%s is on the navmesh (%s)" % [m.name, m.global_position])
	check(_on_navmesh(zone, st.raid_goal()), "the stores' front is reachable")
	var p := _player(zone)
	await wait_physics(30)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	if st.raiders_here() > 0:
		check(st.claim_refusal_reason(p).contains("clear the outpost first"), "the garrison's still here: %s" % st.claim_refusal_reason(p))
		for e in get_tree().get_nodes_in_group("enemies"):
			(e as Node).queue_free()
		await wait_physics(3)
	check(st.request_claim(p), "then it's yours: %s" % st.claim_refusal_reason(p))
	check(zone.get_node("NorthwatchOutpost").find_children("*", "EnemySpawner", true, false).all(
		func(n: Node) -> bool: return not (n as EnemySpawner).enabled), "the garrison and its raiders stop coming")
	await _free(zone)


# ---------------------------------------------------------------- the armorer

func test_the_armorer_makes_guns_from_scrap() -> void:
	var zone := await load_zone()
	var st := _nw(zone)
	await _claim(zone, st)
	check(Settlement.find(get_tree(), &"ash_creek").role_refusal_reason(Settler.Role.ARMORER).begins_with("No weapons bench here"),
		"no Armorers at the farm")
	st.store.inventory.add_item(VEG, 20)
	var a := await _newcomer(zone, st, Settler.Role.ARMORER)
	check(a.role_name() == "Armorer" and (a.visual.get_node("Goggles") as Node3D).visible and (a.visual.get_node("RightArm/Hammer") as Node3D).visible,
		"an Armorer: goggles and a hammer")
	# 15 Scrap Metal: not enough for anything
	st.store.inventory.add_item(SCRAP, 15)
	st.simulate(1.0)
	check(st.armorer_status().begins_with("Nothing to make a gun from"), "15 scrap: %s" % st.armorer_status())
	check(st.scrap() == 15, "and nothing's taken")
	# 16: a pistol (receiver, barrel, trigger group, magazine: 3 plates, 2
	# pipes and 4 springs, all from scrap)
	st.store.inventory.add_item(SCRAP, 1)
	st.simulate(0.5)
	check(st.armorer_status() == "Making a Sidearm Pistol (13%)", "16 scrap: %s" % st.armorer_status())
	check(st.scrap() == 0, "its makings come out of the stores at the start")
	st.simulate(3.5)
	check(_count(st, &"pistol") == 1 and st.armory_guns() == 1, "four hours on, a Pistol in the Armory Locker")
	# With planks too, a shotgun (the better gun)
	st.store.inventory.add_item(SCRAP, 17)
	st.store.inventory.add_item(PLANK, 2)
	st.simulate(4.0)
	check(_count(st, &"shotgun") == 1 and st.scrap() == 0 and st.planks() == 0, "17 scrap and 2 planks: a Shotgun")
	check(st._stores_count(&"spring") == 1, "with a spare spring left on the shelves")
	# And an Electronics part too: a service rifle
	st.store.inventory.add_item(SCRAP, 16)
	st.store.inventory.add_item(PLANK, 2)
	st.store.inventory.add_item(ELECTRONICS, 1)
	st.simulate(4.0)
	check(_count(st, &"service_rifle") == 1, "and an Electronics part: a Service Rifle")
	# A pipe pistol, at a pinch
	st.store.inventory.add_item(SCRAP, 4)
	st.store.inventory.add_item(WOOD, 1)
	st.simulate(4.0)
	check(_count(st, &"pipe_pistol") == 1 and st.armory_guns() == 4, "4 scrap and a piece of wood: a Pipe Pistol (4 guns)")
	# Four guns: stocked (no gunpowder for rounds)
	st.store.inventory.add_item(SCRAP, 40)
	st.simulate(4.0)
	check(st.armory_guns() == 4 and st.scrap() == 40, "four guns in the locker: no more")
	check(st.armorer_status().begins_with("Armory stocked") and st.armorer_status().contains("Gunpowder"), "stocked, but no makings for rounds: %s" % st.armorer_status())
	await _free(zone)


func test_the_armorer_makes_rounds() -> void:
	var zone := await load_zone()
	var st := _nw(zone)
	await _claim(zone, st)
	st.store.inventory.add_item(VEG, 20)
	await _newcomer(zone, st, Settler.Role.ARMORER)
	st.armory.inventory.add_item(load("res://resources/items/weapons/pistol_item.tres"), 1)
	st.store.inventory.add_item(SCRAP, 10)
	st.store.inventory.add_item(GUNPOWDER, 10)
	st.simulate(1.0)
	var ammo := ItemDatabase.find_ammo_item(&"pistol_9mm")
	check(_count(st, ammo.id) == 12, "a pistol in the locker: an hour makes a box of 12 rounds for it (%d)" % _count(st, ammo.id))
	st.simulate(6.0)
	check(_count(st, ammo.id) == 84, "seven hours: 84 rounds (%d)" % _count(st, ammo.id))
	st.simulate(1.0)
	check(_count(st, ammo.id) == 96, "up to 90 and a box over")
	# Gunpowder from chemicals and wood, when there's none
	st.store.inventory.remove_item(&"gunpowder", st._stores_count(&"gunpowder"))
	st.armory.inventory.remove_item(ammo.id, 96)
	st.store.inventory.add_item(load("res://resources/items/chemicals.tres"), 1)
	st.store.inventory.add_item(WOOD, 1)
	st.simulate(1.0)
	check(_count(st, ammo.id) == 12 and st._stores_count(&"gunpowder") == 2, "no gunpowder: made from Chemicals and Wood (3), one used, 2 left over")
	await _free(zone)


func test_the_armorer_works_at_the_bench() -> void:
	var zone := await load_zone()
	var st := _nw(zone)
	await _claim(zone, st)
	st.store.inventory.add_item(VEG, 20)
	var a := await _newcomer(zone, st, Settler.Role.ARMORER)
	var spot := st.armorer_spots()[0].global_position
	var there := false
	for i in 60:
		await wait_physics(60)
		if a.global_position.distance_to(spot) < 1.0:
			there = true
			break
	check(there, "walked into the armory to the bench (%.1f m off)" % a.global_position.distance_to(spot))
	await wait_physics(120)
	check(a.state == Settler.State.WORK, "and is at work")
	await _free(zone)


# ---------------------------------------------------------------- the three places

func test_guns_from_northwatch_arm_the_farm() -> void:
	var zone := await load_zone()
	var hud := zone.get_node("HUD") as HUD
	var p := _player(zone)
	var nw := _nw(zone)
	var farm := Settlement.find(get_tree(), &"ash_creek")
	var mine := Settlement.find(get_tree(), &"black_ridge")
	for st in [farm, mine, nw]:
		await _claim(zone, st)
	hud.settlement_screen.open()
	check(hud.settlement_screen._tabs.get_child_count() == 3, "three tabs: all your places")
	hud.settlement_screen.show_settlement(nw)
	check(hud.settlement_screen._stocks.text.contains("Armorer:  nobody at the weapons bench"), "Northwatch's stocks: %s" % hud.settlement_screen._stocks.text.replace("\n", " | "))
	hud.settlement_screen.close()
	# A gun made at Northwatch, hauled to the farm's locker, arms a guard there
	farm.store.inventory.add_item(VEG, 20)
	var g := await _newcomer(zone, farm, Settler.Role.GUARD)
	check(g.gun == null, "an unarmed guard at the farm")
	nw.armory.inventory.add_item(load("res://resources/items/weapons/shotgun_item.tres"), 1)
	nw.armory.inventory.remove_item(&"shotgun", 1)
	farm.armory.inventory.add_item(load("res://resources/items/weapons/shotgun_item.tres"), 1)
	farm._supply_guards()
	check(g.gun != null and g.gun.id == &"shotgun", "takes the Shotgun from the farm's locker")
	await _free(zone)


func test_the_armory_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_northwatch"
	var zone := await load_zone()
	var st := _nw(zone)
	await _claim(zone, st)
	st.store.inventory.add_item(VEG, 20)
	await _newcomer(zone, st, Settler.Role.ARMORER)
	st.store.inventory.add_item(SCRAP, 16)
	st.simulate(2.0)
	check(st.armorer_status() == "Making a Sidearm Pistol (50%)", "half a pistol: %s" % st.armorer_status())
	check(saves.save_game("nw", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("nw", zone2) == OK, "loaded")
	await wait_physics(5)
	var st2 := _nw(zone2)
	check(st2.is_claimed and st2.armorer_status() == "Making a Sidearm Pistol (50%)", "still half a pistol: %s" % st2.armorer_status())
	st2.simulate(2.0)
	check(_count(st2, &"pistol") == 1, "and it's finished")
	await _free(zone2)
