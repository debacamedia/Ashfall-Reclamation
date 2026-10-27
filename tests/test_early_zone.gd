extends "res://tests/test_case.gd"
## Increment 15: the early zone. Laid out from the Regional Buildout Map
## (Outpost 17 on the coast, Halden's Crossing to the north-east, five
## more places, built out in Increment 16), walkable end to end, an ash-storm edge instead of
## border walls, the compass and place names, sleeping spawners, navmesh
## tiles, and saves from the old levels moved into the zone.

const DT := 1.0 / 60.0

## Where each place stands (x, z) and roughly how far from Outpost 17 (m)
const PLACES := {
	"Outpost17": Vector2(0, 5),
	"HaldensCrossing": Vector2(450, -275),
	"SaintMercyClinic": Vector2(245, -205),
	"AshCreekFarms": Vector2(340, -90),
	"SmugglersGulch": Vector2(150, -395),
	"BlackRidgeMine": Vector2(262, -552),
	"NorthwatchOutpost": Vector2(400, -680),
}


func _run(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _teleport(p: PlayerController, pos: Vector3, yaw_deg := 0.0) -> void:
	p.global_position = pos
	p.rotation_degrees.y = yaw_deg
	p.velocity = Vector3.ZERO
	await wait_physics(4)


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


# ---------------------------------------------------------------- layout

func test_the_zone_is_the_game() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == ZONE_PATH, "the game starts in the early zone")
	var zone := instance_zone()
	check(zone is Zone, "zone root script")
	for n in ["Lighting/WorldEnvironment", "Terrain/Ground", "Terrain/Sea", "Roads/MainRoad", "Roads/Railway", "Rocks",
			"Landmarks", "Boundary", "Boundary/Backstop", "Navigation", "Structures", "PlayerSpawn", "Player", "HUD",
			"GameMode", "StormEffects", "Ambience", "DistantWind"]:
		check(zone.get_node_or_null(n) != null, "has %s" % n)
	# Each old level's infrastructure is gone from the sites (no second player, HUD, sky…)
	for site in ["Outpost17", "HaldensCrossing"]:
		var s := zone.get_node(site)
		for n in ["Player", "HUD", "GameMode", "Lighting", "Terrain", "Navigation", "Structures", "Exits", "Arrivals", "Ambience"]:
			check(s.get_node_or_null(n) == null, "%s has no %s of its own" % [site, n])
	zone.free()


func test_places_where_the_map_puts_them() -> void:
	var zone := instance_zone()
	check((zone.get_node("Outpost17") as Node3D).position == Vector3.ZERO, "Outpost 17 at the origin (its coordinates unchanged)")
	check((zone.get_node("HaldensCrossing") as Node3D).position == HALDENS_AT, "Halden's Crossing at %s" % HALDENS_AT)
	var marks := zone.get_node("Landmarks")
	check(marks.get_child_count() == PLACES.size(), "a landmark per place")
	for key in PLACES:
		var site := zone.get_node_or_null(key) as Node3D
		check(site != null, "%s is in the zone" % key)
		var l := marks.get_node_or_null(key) as Landmark
		check(l != null and Vector2(l.position.x, l.position.z).distance_to(PLACES[key]) < 1.0 and l.display_name != "", "%s landmark" % key)
		if site != null and key != "Outpost17" and key != "HaldensCrossing":
			check(not site.get_meta("blockout", false), "%s is a real place now (Increment 16)" % key)
			check(site.find_children("*", "StaticBody3D", true, false).size() > 0, "%s is solid" % key)
	# The map's directions: north is -z, east is +x
	var h: Vector2 = PLACES["HaldensCrossing"]
	check(h.x > 300 and h.y < -200, "Halden's is north-east of the outpost")
	check(Vector2.ZERO.distance_to(h) > 450 and Vector2.ZERO.distance_to(h) < 600, "a few minutes' walk (%.0f m)" % Vector2.ZERO.distance_to(h))
	var n: Vector2 = PLACES["NorthwatchOutpost"]
	check(n.y < PLACES["BlackRidgeMine"].y and n.y < h.y, "Northwatch furthest north")
	# Coast to the west of the outpost: the boundary's sea edges
	var edge := zone.get_node("Boundary") as ZoneBoundary
	check(edge.nearest_kind(Vector3(-150, 0, 0)) == ZoneBoundary.Kind.SEA, "sea to the west of the outpost")
	check(edge.nearest_kind(Vector3(655, 0, -300)) == ZoneBoundary.Kind.STORM, "storm to the east of Halden's")
	for key in PLACES:
		var c: Vector2 = PLACES[key]
		check(edge.signed_distance(Vector3(c.x, 0, c.y)) < -60.0, "%s well inside the edge" % key)
	zone.free()


func test_flat_ground_under_every_place() -> void:
	var zone := await load_zone()
	var space := zone.get_world_3d().direct_space_state
	var ground := zone.get_node("Terrain/Ground") as StaticBody3D
	for key in PLACES:
		var c: Vector2 = PLACES[key]
		for off in [Vector2(-30, 0), Vector2(30, 0), Vector2(0, 40), Vector2(0, -40)]:
			var at := Vector3(c.x + off.x, 50, c.y + off.y)
			var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 100, PhysicsLayers.TERRAIN)
			var hit := space.intersect_ray(q)
			check(not hit.is_empty() and hit["collider"] == ground and absf((hit["position"] as Vector3).y) < 0.01,
				"%s: flat ground at %s" % [key, off])
	await _free(zone)


func test_draw_distances_keep_far_places_cheap() -> void:
	var zone := await load_zone()
	check((zone as Zone).ranged > 1000, "small things get a draw distance (%d)" % (zone as Zone).ranged)
	var small := 0
	for g in zone.get_node("HaldensCrossing").find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).visibility_range_end > 0.0 and (g as GeometryInstance3D).visibility_range_end <= Zone.SMALL_RANGE:
			small += 1
	check(small > 100, "the town's clutter isn't drawn from far away (%d)" % small)
	var env := (zone.get_node("Lighting/WorldEnvironment") as WorldEnvironment).environment
	check(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_depth_end > 400.0 and env.fog_depth_end < 800.0,
		"dust haze closes in by %.0f m" % env.fog_depth_end)
	await _free(zone)


# ---------------------------------------------------------------- walking it

func test_every_place_reachable_on_foot() -> void:
	var zone := await load_zone()
	var map := zone.get_world_3d().navigation_map
	var gate := NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 40))
	var tiles := zone.get_node("Navigation").get_child_count()
	check(tiles > 50, "navmesh in tiles (%d)" % tiles)
	for key in PLACES:
		if key == "Outpost17":
			continue
		var c: Vector2 = PLACES[key]
		# The edge of the place, toward the outpost (30 m out, clear of the buildings)
		var r := 30.0 if key != "HaldensCrossing" else 0.0
		var goal := Vector3(c.x, 0, c.y) + Vector3(-c.x, 0, -c.y).normalized() * r
		goal = NavigationServer3D.map_get_closest_point(map, goal)
		var path := NavigationServer3D.map_get_path(map, gate, goal, true)
		var length := 0.0
		for k in range(1, path.size()):
			length += path[k].distance_to(path[k - 1])
		check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 1.0, "%s reachable from the outpost gate" % key)
		check(length > Vector2(c.x, c.y - 40).length() * 0.8 and length < 1600.0, "%s: %.0f m on foot" % [key, length])
	await _free(zone)


func test_walk_the_main_road_out_of_the_outpost() -> void:
	# The player really walks: out of the south gate onto the road, past where
	# the old border berm stood (75 m), with nothing in the way
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	await _teleport(p, Vector3(0, 0.05, 30), 180)
	var w := InputFrame.new()
	w.move = Vector2(0, -1)
	await _run(p, 60 * 14, w)
	check(p.global_position.z > 85.0, "walked south past the old berm (z=%.1f)" % p.global_position.z)
	check(p.is_on_floor() and absf(p.global_position.y) < 0.2, "on the ground")
	await _free(zone)


# ---------------------------------------------------------------- the edge

func test_storm_edge_warns_hurts_and_stops_you() -> void:
	var zone := await load_zone()
	var edge := zone.get_node("Boundary") as ZoneBoundary
	var p := zone.get_node("Player") as PlayerController
	# East of Halden's: the storm side
	var inside := Vector3(560, 0.05, -300)
	check(edge.is_inside(inside) and edge.storm_level(inside) == 0.0 and edge.warning_at(inside) == "", "calm well inside")
	var near := Vector3(645, 0, -300)  # ~11 m inside the edge
	check(edge.storm_level(near) > 0.0 and edge.warning_at(near).contains("Turn back"), "haze and a warning near the edge")
	check(edge.damage_per_second_at(near) == 0.0, "no damage before the edge")
	var out := Vector3(680, 0, -300)
	check(not edge.is_inside(out) and edge.damage_per_second_at(out) > edge.damage_per_second_min * 0.99, "past the edge the storm hurts")
	check(edge.damage_per_second_at(Vector3(685, 0, -300)) > edge.damage_per_second_at(Vector3(670, 0, -300)), "more the further you go")
	# Walk east into it: hurt, and stopped by the backstop
	await _teleport(p, Vector3(600, 0.05, -300), -90)
	var w := InputFrame.new()
	w.move = Vector2(0, -1)
	await _run(p, 60 * 22, w)
	var past := edge.signed_distance(p.global_position)
	check(past > 0.0 and past < edge.backstop_distance + 1.5, "stopped by the wall %.0f m past the edge (%.1f)" % [edge.backstop_distance, past])
	check(p.health.current_health < 100.0, "the storm hurt (%.0f HP left)" % p.health.current_health)
	# Stay in it and it kills
	await _run(p, 60 * 12)
	check(p.is_dead(), "the storm kills if you stay")
	await _free(zone)


func test_storm_cause_of_death() -> void:
	var zone := await load_zone()
	var edge := zone.get_node("Boundary") as ZoneBoundary
	var p := zone.get_node("Player") as PlayerController
	var gm := zone.get_node("GameMode") as GameMode
	p.health.current_health = 3.0
	await _teleport(p, Vector3(690, 0.05, -300))
	await wait_physics(60)
	check(p.is_dead(), "died in the storm")
	check(gm.get_death_cause(p) == edge.death_message, "cause: %s" % gm.get_death_cause(p))
	await _free(zone)


func test_sea_edge_warns_and_stops_but_never_hurts() -> void:
	var zone := await load_zone()
	var edge := zone.get_node("Boundary") as ZoneBoundary
	var p := zone.get_node("Player") as PlayerController
	await _teleport(p, Vector3(-120, 0.05, 0), 90)  # facing west, toward the sea
	var w := InputFrame.new()
	w.move = Vector2(0, -1)
	await _run(p, 60 * 16, w)
	var past := edge.signed_distance(p.global_position)
	check(past > 0.0 and past < edge.sea_backstop_distance + 1.5, "stopped in the shallows (%.1f m out)" % past)
	check(p.health.current_health == 100.0, "the sea doesn't hurt")
	check(edge.warning_at(p.global_position).contains("water"), "told the water's too deep")
	check(edge.storm_level(p.global_position) == 0.0, "no storm over the sea")
	await _free(zone)


func test_storm_effects_follow_your_player() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var fx := zone.get_node("StormEffects") as StormEffects
	var we := zone.get_node("Lighting/WorldEnvironment") as WorldEnvironment
	await wait_physics(10)
	check(fx.level < 0.01 and fx.warning == "", "clear at the outpost")
	await _teleport(p, Vector3(668, 0.05, -300))
	await get_tree().create_timer(1.5).timeout
	check(fx.level > 0.5, "the haze closes in (%.2f)" % fx.level)
	check(fx.warning != "" and (fx.get_node("StormWarning") as Label).visible, "warning shown: %s" % fx.warning)
	var file_env := load("res://levels/early_zone/early_zone_environment.tres") as Environment
	check(we.environment != file_env and we.environment.fog_depth_end < file_env.fog_depth_end * 0.5,
		"fog thickens on a copy (%.0f m; the level's environment file is untouched at %.0f m)" % [we.environment.fog_depth_end, file_env.fog_depth_end])
	check((fx.get_node("Ash") as ColorRect).visible, "ash blows across the screen")
	await _teleport(p, Vector3(0, 0.05, 14))
	await get_tree().create_timer(1.5).timeout
	check(fx.level < 0.01 and not (fx.get_node("Ash") as ColorRect).visible, "clears again back home")
	await _free(zone)


func test_no_border_walls_inside_the_zone() -> void:
	# The old 150 m and 210 m berms are gone: open ground runs on to the haze
	var zone := await load_zone()
	var space := zone.get_world_3d().direct_space_state
	for line in [[Vector3(-70, 1, 0), Vector3(-80, 1, 0)], [Vector3(0, 1, 70), Vector3(0, 1, 80)],
			[HALDENS_AT + Vector3(100, 1, 30), HALDENS_AT + Vector3(110, 1, 30)], [HALDENS_AT + Vector3(-30, 1, -100), HALDENS_AT + Vector3(-30, 1, -110)]]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(line[0], line[1], PhysicsLayers.WORLD_SOLID))
		check(hit.is_empty(), "no wall where the old border was (%s)" % line[0])
	await _free(zone)


# ---------------------------------------------------------------- HUD

func test_compass_bearings() -> void:
	check(is_equal_approx(CompassBar.heading_of(0.0), 0.0), "yaw 0 faces north")
	check(is_equal_approx(CompassBar.heading_of(-PI / 2.0), 90.0), "turning right faces east")
	check(is_equal_approx(CompassBar.heading_of(PI / 2.0), 270.0), "turning left faces west")
	check(is_equal_approx(CompassBar.bearing(Vector3.ZERO, Vector3(0, 0, -10)), 0.0), "north is 0°")
	check(is_equal_approx(CompassBar.bearing(Vector3.ZERO, Vector3(10, 0, 0)), 90.0), "east is 90°")
	var h := CompassBar.bearing(Vector3.ZERO, HALDENS_AT)
	check(h > 45.0 and h < 75.0, "Halden's is north-east of the outpost (%.0f°)" % h)


func test_compass_and_place_names_on_the_hud() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var hud := zone.get_node("HUD") as HUD
	await wait_physics(30)
	var compass := hud.compass
	check(compass != null and compass.visible and compass.player == p, "compass on the HUD")
	check(compass.current_place != null and compass.current_place.display_name == "Outpost 17", "at Outpost 17")
	await _teleport(p, HALDENS_AT + Vector3(0, 0.05, 60))
	await get_tree().create_timer(0.8).timeout
	check(compass.current_place != null and compass.current_place.display_name == "Halden's Crossing", "walked into Halden's Crossing")
	check(compass.last_banner == "Halden's Crossing", "its name shown on arrival")
	await _teleport(p, Vector3(200, 0.05, -120))
	await get_tree().create_timer(0.8).timeout
	check(compass.current_place == null, "out in the open between places")
	await _free(zone)


func test_signposts_point_the_way() -> void:
	var zone := instance_zone()
	var posts := zone.get_node("Roads/Signposts").get_children()
	check(posts.size() >= 6, "signposts at the junctions (%d)" % posts.size())
	var first := posts[0] as Node3D
	var arm := first.get_node("ToHaldensCrossing") as Node3D
	check(arm != null, "the outpost's road sign points to Halden's")
	if arm != null:
		var label := arm.get_node("TextFront") as Label3D
		check(label.text.begins_with("Halden's Crossing") and label.text.ends_with("km"), "with the distance: %s" % label.text)
		# The board runs along the arm's -X: that should point at the town
		var dir := -arm.global_basis.x if arm.is_inside_tree() else -(first.transform * arm.transform).basis.x
		var to := (HALDENS_AT - first.position).normalized()
		check(Vector2(dir.x, dir.z).normalized().dot(Vector2(to.x, to.z)) > 0.95, "pointing the right way")
	zone.free()


# ---------------------------------------------------------------- raiders

func test_far_spawners_sleep_until_you_come() -> void:
	var zone := await load_zone(["Outpost17", "HaldensCrossing"])
	await wait_physics(30)
	var camp := zone.get_node("HaldensCrossing/CampSpawner") as EnemySpawner
	var outpost := zone.get_node("Outpost17/RaiderSpawner") as EnemySpawner
	check(camp.active_radius > 100.0 and outpost.active_radius > 100.0, "spawners sleep beyond %.0f m" % camp.active_radius)
	check(camp.dormant and camp.get_alive().is_empty(), "no veterans while you're at the outpost")
	check(not outpost.dormant and outpost.get_alive().size() > 0, "the outpost's raiders are out")
	var p := zone.get_node("Player") as PlayerController
	await _teleport(p, HALDENS_AT + Vector3(0, 0.05, -90))
	await get_tree().create_timer(EnemySpawner.CHECK_INTERVAL * 2.5).timeout
	await wait_physics(5)
	check(not camp.dormant and camp.get_alive().size() == camp.max_alive, "the camp fills when you reach the town (%d)" % camp.get_alive().size())
	check(outpost.dormant and outpost.get_alive().all(func(e: Node3D) -> bool: return EnemySpawner.is_fighting(e)),
		"the outpost's raiders go when you're far away (only ones still chasing you stay: %d)" % outpost.get_alive().size())
	# Lose them, and they go too
	for e in outpost.get_alive():
		(e as Raider).state = Raider.State.SEARCH
	await get_tree().create_timer(EnemySpawner.CHECK_INTERVAL * 1.5).timeout
	check(outpost.get_alive().is_empty(), "once they give up they're gone")
	await _free(zone)


func test_town_raiders_drop_loot_where_they_fall() -> void:
	# The town isn't at the origin: drops must land at the raider's feet
	var zone := await load_zone()
	var vet := (load("res://scenes/enemies/raider_veteran.tscn") as PackedScene).instantiate() as Raider
	var town := zone.get_node("HaldensCrossing") as Node3D
	vet.position = Vector3(10, 0.1, 40)  # in the town's own space
	town.add_child(vet)
	await wait_physics(10)
	var at := vet.global_position
	check(at.distance_to(HALDENS_AT + Vector3(10, 0, 40)) < 0.5, "stands where it was put (%s)" % at)
	var before := town.get_child_count()
	vet.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(3)
	var drops: Array = []
	for c in town.get_children().slice(before - 1):
		if c is Pickup:
			drops.append(c)
	check(not drops.is_empty(), "a veteran always drops something")
	for d: Pickup in drops:
		check(Vector2(d.global_position.x - at.x, d.global_position.z - at.z).length() < 1.5, "dropped at its feet (%s)" % d.global_position)
	await _free(zone)


# ---------------------------------------------------------------- building

func test_building_rebakes_only_nearby_tiles() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var kit := load("res://resources/items/kits/wooden_wall_kit.tres") as ItemDefinition
	p.inventory.add_item(kit, 1)
	await _teleport(p, Vector3(30, 0.05, 90))
	var at := ConstructionRules.snap(Vector3(30, 0, 86), 0)
	check(p.place_refusal_reason(kit, at) == "", "can build out in the open: %s" % p.place_refusal_reason(kit, at))
	check(p.request_place_structure(kit, at) != null, "placed")
	var wall := ConstructionRules.structures_root(zone).get_child(0) as Structure
	var regions := NavRebaker.regions_for(wall)
	var tiles := zone.get_node("Navigation").get_child_count()
	check(regions.size() >= 1 and regions.size() <= 4, "%d of %d tiles rebake" % [regions.size(), tiles])
	for i in 600:
		await get_tree().process_frame
		if i > 10 and not NavRebaker.any_busy(zone.get_node("Navigation")):
			break
	# The navigation map takes in the new tile on its own thread (a second or
	# two, longer when the machine is busy): wait up to 20 s of real time
	var map := zone.get_world_3d().navigation_map
	var on := Vector3.ZERO
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
		on = NavigationServer3D.map_get_closest_point(map, wall.global_position + Vector3.UP * 0.5)
		if Vector2(on.x - wall.global_position.x, on.z - wall.global_position.z).length() > 0.2:
			break
	check(Vector2(on.x - wall.global_position.x, on.z - wall.global_position.z).length() > 0.2, "raiders path round the new wall")
	# Far tiles still join up: the whole zone is still walkable
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 40)),
		NavigationServer3D.map_get_closest_point(map, HALDENS_AT), true)
	check(path.size() > 1 and path[path.size() - 1].distance_to(HALDENS_AT) < 2.0, "still a way to Halden's")
	await _free(zone)


# ---------------------------------------------------------------- saves

func _v2_save_in_town() -> Dictionary:
	# What a version 2 save looked like, made in Halden's Crossing after
	# looting the outpost (paths and positions in each level's own space)
	return {
		"format": "ashfall_save", "version": 2, "saved_at": "2026-10-20 10:00:00",
		"level": "res://levels/haldens_crossing/haldens_crossing.tscn",
		"nodes": [
			{"path": "Player", "scene": "res://scenes/player/player.tscn", "parent": ".",
				"data": {"position": [-30.0, 0.05, 2.0], "yaw": 0.5, "pitch": 0.0, "health": 64.0, "inventory": [], "magazine": 0, "loadout": {}}},
			{"path": "SalvageContainers/StoreCrate", "scene": "", "parent": "SalvageContainers",
				"data": {"id": "StoreCrate", "searched": true, "items": []}},
			{"path": "Structures/wooden_wall_1", "scene": "res://scenes/structures/wooden_wall.tscn", "parent": "Structures",
				"data": {"structure": "wooden_wall", "health": 300.0, "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "origin": [-60.0, 0.0, 70.0]}},
		],
		"regions": {"res://levels/outpost_17/outpost_17.tscn": {"nodes": [
			{"path": "SalvageContainers/WarehouseCrateNorth", "scene": "", "parent": "SalvageContainers",
				"data": {"id": "WarehouseCrateNorth", "searched": true, "items": []}},
			{"path": "Structures/wooden_wall_1", "scene": "res://scenes/structures/wooden_wall.tscn", "parent": "Structures",
				"data": {"structure": "wooden_wall", "health": 350.0, "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "origin": [-6.0, 0.0, -8.0]}},
		]}},
	}


func test_old_saves_move_into_the_zone() -> void:
	var saves := get_node("/root/SaveManager")
	var old := _v2_save_in_town()
	check(saves.validate(old) == "", "a version 2 save is still valid")
	var data: Dictionary = saves._migrate(old.duplicate(true))
	check(int(data["version"]) == 4 and data["level"] == ZONE_PATH, "now a version 4 save of the zone")
	check((data["regions"] as Dictionary).is_empty(), "both old levels are part of the zone now")
	var by_path := {}
	for e: Dictionary in data["nodes"]:
		by_path[str(e["path"])] = e
	check(by_path.has("Player") and by_path.has("HaldensCrossing/SalvageContainers/StoreCrate") and by_path.has("Outpost17/SalvageContainers/WarehouseCrateNorth"),
		"paths gain their site: %s" % [by_path.keys()])
	var pos: Array = by_path["Player"]["data"]["position"]
	check(Vector3(pos[0], pos[1], pos[2]).distance_to(HALDENS_AT + Vector3(-30, 0.05, 2)) < 0.01, "the player moves with the town")
	var walls := (data["nodes"] as Array).filter(func(e: Dictionary) -> bool: return str(e["path"]).begins_with("Structures/"))
	check(walls.size() == 2 and walls[0]["path"] != walls[1]["path"], "both regions' walls kept, with names that don't clash")
	# Into a real zone
	var zone := await load_zone()
	saves.apply_save_data(data, zone)
	await wait_physics(3)
	var p := zone.get_node("Player") as PlayerController
	check(p.global_position.distance_to(HALDENS_AT + Vector3(-30, 0.05, 2)) < 0.3, "you're in the town where you saved")
	check_near(p.health.current_health, 64.0, 0.01, "health kept")
	check((zone.get_node("HaldensCrossing/SalvageContainers/StoreCrate") as SalvageContainer).is_searched, "the town's crate is searched")
	check((zone.get_node("Outpost17/SalvageContainers/WarehouseCrateNorth") as SalvageContainer).is_searched, "and the outpost's")
	var built := ConstructionRules.structures_root(zone).get_children()
	check(built.size() == 2, "both walls rebuilt (%d)" % built.size())
	var origins := built.map(func(s: Node) -> Vector3: return (s as Node3D).global_position)
	check(origins.any(func(o: Vector3) -> bool: return o.distance_to(HALDENS_AT + Vector3(-60, 0, 70)) < 0.01), "the town's wall in the town")
	check(origins.any(func(o: Vector3) -> bool: return o.distance_to(Vector3(-6, 0, -8)) < 0.01), "the outpost's wall at the outpost")
	for i in 600:
		await get_tree().process_frame
		if i > 10 and not NavRebaker.any_busy(zone.get_node("Navigation")):
			break
	await _free(zone)


func test_a_place_the_old_save_never_saw_keeps_its_loot() -> void:
	var saves := get_node("/root/SaveManager")
	# Saved at the outpost before ever going to the town
	var old := {"format": "ashfall_save", "version": 2, "level": "res://levels/outpost_17/outpost_17.tscn",
		"nodes": [{"path": "Player", "scene": "res://scenes/player/player.tscn", "parent": ".",
			"data": {"position": [3.0, 0.05, 10.0], "yaw": 0.0, "pitch": 0.0, "health": 100.0, "inventory": [], "magazine": 0, "loadout": {}}}],
		"regions": {}}
	var data: Dictionary = saves._migrate(old)
	check((data["untouched"] as Array).has("HaldensCrossing") and not (data["untouched"] as Array).has("Outpost17"), "the town is marked untouched")
	var zone := await load_zone()
	var town_loot := zone.get_node("HaldensCrossing/Loot").get_child_count()
	var outpost_loot := zone.get_node("Outpost17/Loot").get_child_count()
	saves.apply_save_data(data, zone)
	await wait_physics(2)
	check(zone.get_node("HaldensCrossing/Loot").get_child_count() == town_loot, "the town keeps all its loot (%d)" % town_loot)
	var left := 0
	for c in zone.get_node("Outpost17/Loot").get_children():
		if not c.is_queued_for_deletion():
			left += 1
	check(left == 0 and outpost_loot > 0, "the outpost's pickups weren't in the save, so they're gone (taken)")
	await _free(zone)


func test_save_and_load_across_the_zone() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_zone"
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	(zone.get_node("Outpost17/Loot/GateMedkit") as Node).free()
	var crate := zone.get_node("HaldensCrossing/SalvageContainers").get_child(0) as SalvageContainer
	crate.search()
	await _teleport(p, HALDENS_AT + Vector3(-20, 0.05, 10))
	check(saves.save_game("zone_test", zone) == OK, "saved in the town")
	var data: Dictionary = saves.read_save_file(saves.slot_path("zone_test"))
	check(int(data["version"]) == 4 and data["level"] == ZONE_PATH and not data.has("untouched"), "one level, version 4")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("zone_test", zone2) == OK, "loaded into a fresh zone")
	await wait_physics(3)
	var p2 := zone2.get_node("Player") as PlayerController
	check(p2.global_position.distance_to(HALDENS_AT + Vector3(-20, 0.05, 10)) < 0.3, "back in the town")
	check(zone2.get_node_or_null("Outpost17/Loot/GateMedkit") == null or zone2.get_node("Outpost17/Loot/GateMedkit").is_queued_for_deletion(), "the outpost medkit stays taken")
	check((zone2.get_node("HaldensCrossing/SalvageContainers").get_child(0) as SalvageContainer).is_searched, "the town crate stays searched")
	saves.delete_save("zone_test")
	saves.save_dir = "user://saves"
	await _free(zone2)
