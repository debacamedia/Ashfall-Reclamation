extends "res://tests/test_case.gd"
## Increment 16: the early zone's five newer places as real sites (Saint
## Mercy Clinic, Ash Creek Farms, Smuggler's Gulch, Black Ridge Mine,
## Northwatch Outpost), checked the way Halden's Crossing is: containers clear
## and searchable, everything reachable, salvage and loot placed sensibly,
## doors you can walk through, ladders you can climb, raiders in the right
## place.

const DT := 1.0 / 60.0

## Site -> [where it stands in the zone, the road in (site coordinates)]
const SITES := {
	"SaintMercyClinic": [Vector3(245, 0, -205), Vector3(27, 0, -17)],
	"AshCreekFarms": [Vector3(307, 0, -106), Vector3(0, 0, 40)],  # turned 39.5°: the road in is site +z (19.5)
	"SmugglersGulch": [Vector3(150, 0, -395), Vector3(10, 0, 30)],
	"BlackRidgeMine": [Vector3(262, 0, -552), Vector3(36, 0, 12)],
	"NorthwatchOutpost": [Vector3(400, 0, -680), Vector3(0, 0, 26)],
}
const NEW_TABLES := ["hospital_supplies", "pharmacy", "farm_shed", "barn_loft", "mine_supplies", "mine_explosives",
	"mine_office", "smuggler_stash", "comms_gear"]


func _run(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _face(p: PlayerController, target: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(target.x - eye.x, 0, target.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(target.y - eye.y, flat.length())


func _teleport(p: PlayerController, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await wait_physics(4)


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _site(zone: Node, key: String) -> Node3D:
	return zone.get_node(key) as Node3D


# ---------------------------------------------------------------- data

func test_sites_are_real_places_now() -> void:
	var zone := instance_zone()
	for key in SITES:
		var s := _site(zone, key)
		check(s.scene_file_path.begins_with("res://levels/") and not s.scene_file_path.contains("early_zone/sites"), "%s is a real site (%s)" % [key, s.scene_file_path])
		check(not s.get_meta("blockout", false), "%s is no longer a blockout" % key)
		check(s.position.is_equal_approx(SITES[key][0]), "%s where the map puts it" % key)
		var buildings := s.get_node("Buildings").get_children().filter(func(b: Node) -> bool: return b.has_meta("doors") and (b.get_meta("doors") as Array).size() > 0)
		check(buildings.size() >= 3, "%s: buildings you can walk into (%d)" % [key, buildings.size()])
		check(s.get_node("SalvageContainers").get_child_count() >= 8, "%s: 8+ containers (%d)" % [key, s.get_node("SalvageContainers").get_child_count()])
		check(s.get_node("SalvagePiles").get_child_count() >= 6, "%s: 6+ salvage piles (%d)" % [key, s.get_node("SalvagePiles").get_child_count()])
		check(s.get_node("Loot").get_child_count() >= 5, "%s: 5+ pickups (%d)" % [key, s.get_node("Loot").get_child_count()])
		var spawners := s.get_children().filter(func(n: Node) -> bool: return n is EnemySpawner)
		check(not spawners.is_empty() and spawners.all(func(sp: EnemySpawner) -> bool: return sp.active_radius > 100.0), "%s: raiders that sleep when you're away" % key)
	# Crafting where it makes sense
	check(zone.get_node_or_null("AshCreekFarms/CraftingStations/FarmWorkbench") is CraftingStation, "a workbench in the farm's tool shed")
	check(zone.get_node_or_null("BlackRidgeMine/CraftingStations/MineWorkbench") is CraftingStation, "a workbench in the mine's workshop")
	check(zone.get_node_or_null("SmugglersGulch/CraftingStations/DenWeaponsBench") is CraftingStation, "a weapons bench in the smugglers' den")
	check(zone.get_node_or_null("NorthwatchOutpost/CraftingStations/ArmoryWeaponsBench") is CraftingStation, "a gun bench in Northwatch's armory")
	zone.free()


func test_new_loot_tables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	for name in NEW_TABLES:
		var t := load("res://resources/loot/%s.tres" % name) as LootTable
		check(t != null and not t.entries.is_empty(), "%s exists" % name)
		if t == null:
			continue
		for item in t.possible_items():
			check(ItemDatabase.get_item(item.id) == item, "%s: %s registered" % [name, item.id])
		for i in 5:
			check(not t.roll(rng).is_empty(), "%s rolls something" % name)
	var explosives := load("res://resources/loot/mine_explosives.tres") as LootTable
	for i in 5:
		var ids := explosives.roll(rng).map(func(e: Dictionary) -> StringName: return (e["item"] as ItemDefinition).id)
		check(ids.has(&"gunpowder"), "the mine's explosives crate always has gunpowder")
	var smug := load("res://resources/loot/smuggler_stash.tres") as LootTable
	check(smug.possible_items().any(func(i: ItemDefinition) -> bool: return i.id == &"suppressor"), "smugglers may have a suppressor")


# ---------------------------------------------------------------- containers

func test_containers_clear_on_floors_and_searchable() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var space := zone.get_world_3d().direct_space_state
	for key in SITES:
		for c: SalvageContainer in _site(zone, key).get_node("SalvageContainers").get_children():
			check(c.loot_table != null, "%s/%s has a loot table" % [key, c.name])
			var body := c.get_node("Body") as StaticBody3D
			var shape := body.get_node("BodyShape") as CollisionShape3D
			var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size -= Vector3(0.06, 0.06, 0.06)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = shape.global_transform
			q.collision_mask = PhysicsLayers.WORLD_SOLID
			q.exclude = [body.get_rid()]
			var hits := space.intersect_shape(q, 4)
			check(hits.is_empty(), "%s/%s clear of walls and props (%s)" % [key, c.name, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))])
			var down := PhysicsRayQueryParameters3D.create(c.global_position + Vector3.UP * 0.2, c.global_position + Vector3.DOWN * 0.5, PhysicsLayers.WORLD_SOLID, [body.get_rid()])
			check(not space.intersect_ray(down).is_empty(), "%s/%s stands on a floor" % [key, c.name])
			p.close_container()
			p.health.revive(1.0)
			var front := c.global_basis.z
			front.y = 0.0
			await _teleport(p, c.global_position + front.normalized() * 1.3 + Vector3.UP * 0.05)
			_face(p, c.get_focus_point())
			await _run(p, 2)
			check(p.interactor.focused == c, "%s/%s can be searched from the front (got %s)" % [key, c.name, p.interactor.focused])
	await _free(zone)


func test_everything_reachable_on_foot_or_by_ladder() -> void:
	var zone := await load_zone()
	var map := zone.get_world_3d().navigation_map
	for key in SITES:
		var s := _site(zone, key)
		var start := NavigationServer3D.map_get_closest_point(map, s.transform * (SITES[key][1] as Vector3))
		# The site's road in joins up with the outpost
		var home := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 40)), start, true)
		check(home.size() > 1 and home[home.size() - 1].distance_to(start) < 1.0, "%s: a way there from Outpost 17" % key)
		var targets: Array[Node3D] = []
		targets.append_array(s.get_node("SalvageContainers").get_children())
		targets.append_array(s.get_node("CraftingStations").get_children())
		for c in targets:
			var front := c.global_basis.z
			front.y = 0.0
			var goal := c.global_position + front.normalized() * 1.1
			if c.global_position.y > 1.0:
				var near_ladder := false
				for l: Ladder in get_tree().get_nodes_in_group("ladders"):
					if s.is_ancestor_of(l) and absf(l.get_top_y() - c.global_position.y) < 0.6 \
							and Vector2(l.global_position.x - c.global_position.x, l.global_position.z - c.global_position.z).length() < 16.0:
						near_ladder = true
				check(near_ladder, "%s/%s (up high) has a ladder up to it" % [key, c.name])
				continue
			var path := NavigationServer3D.map_get_path(map, start, goal, true)
			check(path.size() > 0 and path[path.size() - 1].distance_to(goal) < 1.0,
				"%s/%s reachable from the road (path ends %s, goal %s)" % [key, c.name, path[path.size() - 1] if path.size() > 0 else "-", goal])
	await _free(zone)


# ---------------------------------------------------------------- salvage and loot

func test_salvage_and_pickups_placed_sensibly() -> void:
	var zone := await load_zone()
	var space := zone.get_world_3d().direct_space_state
	for key in SITES:
		var s := _site(zone, key)
		for pile: SalvagePile in s.get_node("SalvagePiles").get_children():
			var shape := pile.get_node("Shape") as CollisionShape3D
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape.shape
			if shape.shape is BoxShape3D:
				# A little smaller, so resting on an upstairs floor isn't "inside" it
				var bs := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
				bs.size -= Vector3(0.06, 0.06, 0.06)
				q.shape = bs
			q.transform = shape.global_transform
			q.collision_mask = PhysicsLayers.WORLD_SOLID
			var hits := space.intersect_shape(q, 4).filter(func(h: Dictionary) -> bool: return (h["collider"] as CollisionObject3D).collision_layer != PhysicsLayers.TERRAIN \
				and not str((h["collider"] as Node).name).begins_with("Floor"))
			check(hits.is_empty(), "%s/%s clear (%s)" % [key, pile.name, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))])
		for pk: Pickup in s.get_node("Loot").get_children():
			var down := PhysicsRayQueryParameters3D.create(pk.global_position + Vector3.UP * 0.3, pk.global_position + Vector3.DOWN * 0.3, PhysicsLayers.WORLD_SOLID)
			check(not space.intersect_ray(down).is_empty(), "%s/%s rests on something" % [key, pk.name])
			var q := PhysicsShapeQueryParameters3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.12
			q.shape = sphere
			q.transform = Transform3D(Basis.IDENTITY, pk.global_position + Vector3.UP * 0.2)
			q.collision_mask = PhysicsLayers.WORLD_SOLID
			check(space.intersect_shape(q, 1).is_empty(), "%s/%s isn't inside anything" % [key, pk.name])
	await _free(zone)


# ---------------------------------------------------------------- walking in

func test_walk_in_through_every_door() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var w := InputFrame.new()
	w.move = Vector2(0, -1)
	for key in SITES:
		var s := _site(zone, key)
		for b in s.get_node("Buildings").get_children():
			if not b.has_meta("doors"):
				continue
			for d: Array in b.get_meta("doors"):
				var door: Vector3 = s.transform * (d[0] as Vector3)
				var out: Vector3 = s.basis * (d[1] as Vector3)
				p.health.revive(1.0)
				await _teleport(p, door + out * 1.8 + Vector3.UP * 0.05)
				p.rotation.y = atan2(out.x, out.z)  # face in
				p.head.rotation.x = 0.0
				await _run(p, 75, w)
				var local: Vector3 = (b as Node3D).global_transform.affine_inverse() * p.global_position
				var size: Vector2 = b.get_meta("size")
				var inside := absf(local.x) < size.x / 2.0 and absf(local.z) < size.y / 2.0
				check(inside, "%s/%s: walked in through the door at %s (ended at %s)" % [key, b.name, door.snappedf(0.1), local.snappedf(0.1)])
	await _free(zone)


func test_climb_every_ladder() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var w := InputFrame.new()
	w.move = Vector2(0, -1)
	var climbed := 0
	for key in SITES:
		var s := _site(zone, key)
		for l: Ladder in get_tree().get_nodes_in_group("ladders"):
			if not s.is_ancestor_of(l):
				continue
			p.health.revive(1.0)
			var out := l.get_outward()
			await _teleport(p, l.global_position + out * 1.2 + Vector3.UP * 0.05)
			p.rotation.y = atan2(out.x, out.z)
			p.head.rotation.x = 0.0
			for i in 1200:
				await _run(p, 1, w)
				if p.ladder == null and p.global_position.y > l.get_top_y() - 0.3 and p.is_on_floor():
					break
			check(p.global_position.y > l.get_top_y() - 0.3 and p.is_on_floor(),
				"%s/%s: climbed to %.1f m (at %.2f)" % [key, l.name, l.get_top_y(), p.global_position.y])
			climbed += 1
	check(climbed >= 8, "ladders to climb: hospital (2), barn loft, water tower, gulch lookout, headframe, two Northwatch towers (%d)" % climbed)
	await _free(zone)


# ---------------------------------------------------------------- raiders

func test_raiders_wait_at_each_place() -> void:
	var zone := instance_zone(SITES.keys())
	var p := zone.get_node("Player") as PlayerController
	add_child(zone)
	await wait_physics(20)
	await wait_for_navigation(zone.get_world_3d().navigation_map)
	var map := zone.get_world_3d().navigation_map
	for key in SITES:
		var s := _site(zone, key)
		await _teleport(p, s.transform * (SITES[key][1] as Vector3) + Vector3.UP * 0.05)
		await get_tree().create_timer(EnemySpawner.CHECK_INTERVAL * 2.5).timeout
		await wait_physics(10)
		var count := 0
		for sp in s.get_children():
			if not sp is EnemySpawner:
				continue
			check(not (sp as EnemySpawner).dormant, "%s/%s awake with you there" % [key, sp.name])
			for e in (sp as EnemySpawner).get_alive():
				count += 1
				var at := e.global_position
				check(Vector2(at.x - s.position.x, at.z - s.position.z).length() < 70.0, "%s: raider spawned at the place (%s)" % [key, at.snappedf(0.1)])
				check(at.y > -0.5 and at.y < 2.0, "%s: raider on the ground (y %.2f)" % [key, at.y])
				var on := NavigationServer3D.map_get_closest_point(map, at)
				check(on.distance_to(at) < 1.5, "%s: raider on the navmesh" % key)
		check(count >= 2, "%s has raiders (%d)" % [key, count])
	await _free(zone)


# ---------------------------------------------------------------- lighting

func test_lit_inside_and_cheap() -> void:
	# Every roofed building has a lamp, so rooms read in the dark; lamps cast
	# no shadows and fade out with distance, so a whole zone of them is cheap
	var zone := instance_zone()
	var total := 0
	for key in SITES:
		var s := _site(zone, key)
		for b in s.get_node("Buildings").get_children():
			if not b.has_meta("size") or b.get_node_or_null("Roof") == null:
				continue
			var lamps := b.get_children().filter(func(n: Node) -> bool: return n is OmniLight3D)
			check(lamps.size() >= 1, "%s/%s has a lamp" % [key, b.name])
			var size: Vector2 = b.get_meta("size")
			var roof_y := (b.get_node("Roof") as Node3D).position.y
			for l: OmniLight3D in lamps:
				var lp := l.position
				check(absf(lp.x) < size.x / 2.0 and absf(lp.z) < size.y / 2.0 and lp.y > 2.0 and lp.y < roof_y, "%s/%s lamp inside, up by the ceiling (%s)" % [key, b.name, lp])
		for l: OmniLight3D in s.find_children("*", "OmniLight3D", true, false):
			total += 1
			if l.name.begins_with("Lamp"):
				check(not l.shadow_enabled and l.distance_fade_enabled and l.distance_fade_begin <= 60.0, "%s/%s: no shadows, fades out" % [key, l.name])
	check(find_lamp(zone, "BlackRidgeMine", "LampDeep"), "a work lamp deep in the mine tunnel")
	check(total < 60, "a modest number of lights across the places (%d)" % total)
	zone.free()


func find_lamp(zone: Node, key: String, lamp_name: String) -> bool:
	return _site(zone, key).find_child(lamp_name, true, false) is OmniLight3D


# ---------------------------------------------------------------- saving

func test_looting_the_places_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_sites"
	var zone := await load_zone()
	var taken := []
	var searched := []
	for key in SITES:
		var c := _site(zone, key).get_node("SalvageContainers").get_child(0) as SalvageContainer
		c.search()
		searched.append(str(zone.get_path_to(c)))
		var loot := _site(zone, key).get_node("Loot").get_child(0)
		taken.append(str(zone.get_path_to(loot)))
		loot.free()
	check(saves.save_game("sites_test", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("sites_test", zone2) == OK, "loaded into a fresh zone")
	await wait_physics(3)
	for path in searched:
		check((zone2.get_node(path) as SalvageContainer).is_searched, "%s stays searched" % path)
	for path in taken:
		var n := zone2.get_node_or_null(path)
		check(n == null or n.is_queued_for_deletion(), "%s stays taken" % path)
	saves.delete_save("sites_test")
	saves.save_dir = "user://saves"
	await _free(zone2)


func test_an_older_save_leaves_the_new_places_alone() -> void:
	# A save from Increment 15, when the places were empty blockouts
	var saves := get_node("/root/SaveManager")
	var zone := await load_zone()
	var data: Dictionary = saves.build_save_data(zone)
	data["version"] = 3
	data["nodes"] = (data["nodes"] as Array).filter(func(e: Dictionary) -> bool:
		return not SITES.keys().any(func(k: String) -> bool: return str(e["path"]).begins_with(k + "/")))
	data = saves._migrate(data)
	check(int(data["version"]) == 4, "migrated to version 4")
	for key in SITES:
		check((data["untouched"] as Array).has(key), "%s untouched" % key)
	var before := {}
	for key in SITES:
		before[key] = _site(zone, key).get_node("Loot").get_child_count()
	saves.apply_save_data(data, zone)
	await wait_physics(2)
	for key in SITES:
		var now := _site(zone, key).get_node("Loot").get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).size()
		check(now == before[key], "%s keeps its loot (%d of %d)" % [key, now, before[key]])
	await _free(zone)
