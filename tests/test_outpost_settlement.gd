extends "res://tests/test_case.gd"
## Increment 33.2: Outpost 17 rebuilt, from the approved proof. The walls
## pushed east (95 x 50 m) with the firing range inside them; the test
## leftovers gone; a command post with Sgt. Vance's office, the radio room
## and the armory; a mess hall whose stove makes it the post's Kitchen; the
## barracks with eight bunks; the stores and workshop; a motor pool shed; a
## water tower with a pump; garden plots for four Farmers. And it's a place
## you can claim at the notice board on the parade ground, once you carry a
## gun. Saves from before keep loading.

const EAST_X := 61.25

var PISTOL: ItemDefinition = load("res://resources/items/weapons/pistol_item.tres")


func _o17(zone: Node3D) -> Node3D:
	return zone.get_node("Outpost17") as Node3D


func _st(zone: Node3D) -> Settlement:
	return zone.get_node("Outpost17/Settlement") as Settlement


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _on_navmesh(zone: Node3D, at: Vector3) -> bool:
	var map := zone.get_world_3d().navigation_map
	var on := NavigationServer3D.map_get_closest_point(map, at)
	return Vector2(on.x - at.x, on.z - at.z).length() < 0.8 and absf(on.y - at.y) < 1.2


func _inside_walls(p: Vector3) -> bool:
	return p.x > -31.5 and p.x < EAST_X - 0.3 and absf(p.z) < 24.2


# ---------------------------------------------------------------- the layout

func test_the_walls_reach_east_with_the_range_inside() -> void:
	var zone := await load_zone()
	var o := _o17(zone)
	var east := o.get_node("Perimeter").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("EastWall"))
	check(east.size() == 20 and east.all(func(n: Node3D) -> bool: return is_equal_approx(n.position.x, EAST_X)), "the east wall moved out to x %.2f" % EAST_X)
	var north_x := -INF
	for n: Node3D in o.get_node("Perimeter").get_children():
		if n.name.begins_with("NorthWall"):
			north_x = maxf(north_x, n.position.x)
	check(north_x > EAST_X - 2.5, "the north wall runs on to it (%.1f)" % north_x)
	# 95 x 50 m, give or take the walls' thickness
	check(is_equal_approx(EAST_X + 31.85, 93.1), "93 m between the walls, 95 over them")
	# The range: inside the walls, a firing line, targets at 10 to 40 m, a berm
	var targets := o.get_node("FiringRange").get_children().filter(func(n: Node) -> bool: return n is TargetDummy)
	check(targets.size() == 5, "five targets (%d)" % targets.size())
	for t: Node3D in targets:
		check(_inside_walls(t.global_position), "%s is inside the walls (%s)" % [t.name, t.global_position])
	var far := o.get_node("FiringRange/Target40m") as Node3D
	var bench := o.get_node("FiringRange/ShootingBench") as Node3D
	check(absf(bench.global_position.z - far.global_position.z - 40.0) < 1.0, "the far target is 40 m from the firing line")
	# (meshes are merged at load: their collision stays as built)
	check(o.get_node_or_null("FiringRange/RangeBuilt/BermCol") != null and o.get_node_or_null("FiringRange/RangeBuilt/ShelterRoofCol") != null, "an earth berm and a covered firing line")
	# The test leftovers are gone
	for gone in ["FiringRange/RangeTower", "Props/ContainerB", "Props/ContainerC", "Buildings/Warehouse"]:
		check(o.get_node_or_null(gone) == null, "%s gone" % gone)
	var space := o.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 12, -20.5), Vector3(0, -1, -20.5), PhysicsLayers.WORLD_SOLID))
	check(not hit.is_empty() and (hit["position"] as Vector3).y < 4.5, "no containers stacked by the north wall (the mess hall's roof: %.1f m)" % (hit["position"] as Vector3).y)
	await _free(zone)


func test_the_buildings() -> void:
	var zone := await load_zone()
	var o := _o17(zone)
	for b in ["CommandPost", "MessHall", "Barracks", "StoresWorkshop", "MotorPoolShed", "WaterTower", "RadioMast"]:
		check(o.get_node_or_null("Buildings/" + b) != null, "%s built" % b)
	# The city kit's steel walls on the four buildings
	for b in ["CommandPost", "MessHall", "Barracks", "StoresWorkshop"]:
		check(o.get_node_or_null("Buildings/%s/Kit" % b) != null, "%s has the kit's walls" % b)
	# Vance's office, the radio room, the armory
	var cp := o.get_node("Buildings/CommandPost") as Node3D
	var footlocker := o.get_node("SalvageContainers/VanceFootlocker") as SalvageContainer
	check(footlocker != null and footlocker.get("container_name") == "Sgt. Vance's Footlocker", "Sgt. Vance's footlocker")
	check(cp.to_local(footlocker.global_position).x < -1.6, "in her office (the west room)")
	var bench := o.get_node("CraftingStations/WeaponsBench") as Node3D
	check(cp.to_local(bench.global_position).x > 2.0, "the weapons bench in the armory (the east room)")
	check(cp.to_local((o.get_node("Pack2/Props/FieldRadio") as Node3D).global_position).x > -1.6 and cp.to_local((o.get_node("Pack2/Props/FieldRadio") as Node3D).global_position).x < 2.0, "the radio in the radio room")
	# Eight bunks
	var fixtures := o.get_node("Furniture/Fixtures")
	var bunks := fixtures.get_children().filter(func(n: Node) -> bool: return n is CollisionShape3D and n.name.begins_with("Bunk") and not n.name.begins_with("BunkTable"))
	check(bunks.size() == 8, "eight bunks (%d)" % bunks.size())
	# Everything you can search or use is reachable from where you start
	var map := zone.get_world_3d().navigation_map
	var start := (zone.get_node("PlayerSpawn") as Node3D).global_position
	var targets: Array[Node3D] = []
	for c in o.get_node("SalvageContainers").get_children():
		targets.append(c)
	for b in o.get_node("CraftingStations").get_children():
		targets.append(b)
	for t in targets:
		var front := t.global_basis.z
		front.y = 0.0
		var goal := t.global_position + front.normalized() * 1.1
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		check(path.size() > 0 and path[path.size() - 1].distance_to(goal) < 1.0, "%s reachable on foot" % t.name)
	await _free(zone)


# ---------------------------------------------------------------- the settlement

func test_outpost_17_is_a_settlement() -> void:
	var zone := await load_zone()
	var st := _st(zone)
	check(st != null and st.settlement_id == &"outpost_17" and st.settlement_name == "Outpost 17", "Outpost 17 has a settlement")
	check(st.claim_point != null and st.pump != null and st.store != null and st.armory != null, "a notice board, a pump, stores and an Armory Locker")
	check(st.store.get("container_name") == "Outpost Stores", "the Outpost Stores")
	var board := st.get_node("NoticeBoard") as Node3D
	check(absf(board.global_position.x) < 12.0 and board.global_position.z > -10.0 and board.global_position.z < 5.0, "the notice board's on the parade ground")
	check(st.total_beds() == 8, "eight beds (%d)" % st.total_beds())
	check(st.kitchens().size() == 1 and st.kitchens()[0].name == "MessKitchen", "the mess hall's stove makes it the post's Kitchen")
	check(st.farm_spots().size() == 4, "garden plots for four Farmers")
	check(st.armorer_spots().size() == 1, "a place at the weapons bench for an Armorer")
	var kitchen := st.kitchens()[0]
	check(kitchen.prebuilt and not kitchen.is_save_removable() and not kitchen.is_in_group("structures"), "built in: always there, not a raider's target")
	var labels := st.get_node("RaidPoints").get_children().map(func(n: Node) -> String: return str(n.get_meta("label")))
	check(labels == ["the road", "the east", "the dunes to the north"], "raids from the road, the east and the dunes (%s)" % [labels])
	var points: Array[Node3D] = []
	points.append_array(st.armorer_spots())
	points.append_array(st.guard_posts())
	points.append_array(st.farm_spots())
	for n in ["ArrivalPoint", "Hangout", "Shelter"]:
		points.append(st.get_node(n) as Node3D)
	for c in st.get_node("RaidPoints").get_children():
		points.append(c as Node3D)
	for c in kitchen.cook_spots():
		points.append(c)
	for m in points:
		check(_on_navmesh(zone, m.global_position), "%s is on the navmesh (%s)" % [m.name, m.global_position])
	# The walls, the range and the gardens are within its claim
	for corner in [Vector3(-31.85, 0, -24.5), Vector3(-31.85, 0, 24.5), Vector3(EAST_X, 0, -24.5), Vector3(EAST_X, 0, 24.5)]:
		check(Vector2(corner.x - st.global_position.x, corner.z - st.global_position.z).length() < st.claim_radius, "%s within the claim" % corner)
	await _free(zone)


func test_claim_it_once_you_carry_a_gun() -> void:
	var zone := await load_zone(["Outpost17"])
	var st := _st(zone)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	await wait_physics(3)
	check(not p.has_gun(), "you start with only the machete")
	check(st.claim_refusal_reason(p).begins_with("Find a gun first"), "not yet: %s" % st.claim_refusal_reason(p))
	check(not st.request_claim(p) and not st.is_claimed, "so it isn't yours yet")
	p.receive_gun(PISTOL.weapon, false)
	check(p.has_gun(), "a pistol")
	check(st.claim_refusal_reason(p) == "", "now you can (%s)" % st.claim_refusal_reason(p))
	check(st.request_claim(p) and st.is_claimed, "Outpost 17 is yours")
	check(_o17(zone).find_children("*", "EnemySpawner", true, false).all(func(n: Node) -> bool: return not (n as EnemySpawner).enabled), "its raiders stop coming")
	check(st.food() >= st.starting_food, "a little food in the Outpost Stores (%d)" % st.food())
	check(st.get_node("Plans/Gate") != null and st.sites().size() >= 1, "the Builders' first job: a gate in the gateway")
	await _free(zone)


# ---------------------------------------------------------------- saves

func test_saves_from_before_the_rebuild_load() -> void:
	var zone := await load_zone()
	var o := _o17(zone)
	var saves := get_node("/root/SaveManager")
	var f := FileAccess.open("res://tests/fixtures/save_27.json", FileAccess.READ)
	var old: Dictionary = JSON.parse_string(f.get_as_text())
	check(saves.validate(old) == "" and int(old["version"]) < 5, "a save from before the rebuild validates")
	# Where the old range tower and containers were, and old positions
	old["nodes"].append({"path": "Outpost17/FiringRange/RangeTower", "scene": "res://scenes/world/structures/range_tower.tscn", "parent": "Outpost17/FiringRange", "data": {}})
	old["nodes"].append({"path": "Outpost17/Props/ContainerC", "scene": "res://scenes/world/props/shipping_container.tscn", "parent": "Outpost17/Props", "data": {"origin": [0.5, 2.6, -20.5], "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1]}})
	var shelf_was := (o.get_node("Loot/WarehouseShelfScrap") as Node3D).global_position
	old["nodes"].append({"path": "Outpost17/Loot/WarehouseShelfScrap", "scene": "res://scenes/items/pickup.tscn", "parent": "Outpost17/Loot",
		"data": {"item": "scrap_metal", "quantity": 6, "position": [-24.5, 1.33, 13.0], "yaw": 0.0}})
	var data: Dictionary = saves._migrate(old)
	check(int(data["version"]) == 5, "brought up to version 5")
	var paths := (data["nodes"] as Array).map(func(e: Dictionary) -> String: return str(e["path"]))
	check(not paths.has("Outpost17/FiringRange/RangeTower") and not paths.has("Outpost17/Props/ContainerC"), "what's gone stays gone")
	saves.apply_save_data(data, zone)
	await wait_physics(3)
	check(o.get_node_or_null("FiringRange/RangeTower") == null and o.get_node_or_null("Props/ContainerC") == null, "not brought back by loading")
	var shelf := o.get_node_or_null("Loot/WarehouseShelfScrap") as Node3D
	check(shelf != null and shelf.global_position.distance_to(shelf_was) < 0.01, "the scrap stays on its new shelf")
	check(o.get_node_or_null("Settlement/MessKitchen") != null, "the mess kitchen's still there")
	check(not _st(zone).is_claimed, "and the post isn't yours yet")
	await _free(zone)
