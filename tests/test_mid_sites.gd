extends "res://tests/test_case.gd"
## Increment 26: the mid zone's seven places built out (tools/build_mid_sites.gd),
## checked the way the early zone's are (test_sites.gd): real sites, loot
## tables, containers clear and searchable, everything reachable on foot or
## by ladder from the road in, salvage and loot placed sensibly, and raiders
## waiting, with the new Scorch Marauders at Red Mesa, Cinder Quarry and Scorch.

const DT := 1.0 / 60.0
const MID := "res://levels/mid_zone/mid_zone.tscn"

## Site -> [where it stands in the zone, the road in (site coordinates)]
const SITES := {
	"RedMesa": [Vector3(700, 0, -735), Vector3(12, 0, 80)],
	"DryRiverPumpStation": [Vector3(752, 0, -455), Vector3(-52, 0, 0)],
	"CinderQuarry": [Vector3(890, 0, -545), Vector3(-80, 0, 4)],
	"IronVeinRailYard": [Vector3(830, 0, -300), Vector3(10, 0, -42)],
	"Dusthaven": [Vector3(770, 0, -105), Vector3(0, 0, 0)],
	"BrokenSpurTruckStop": [Vector3(600, 0, 95), Vector3(26, 0, -46)],
	"RaiderCampScorch": [Vector3(740, 0, 160), Vector3(6, 0, -62)],
}
const NEW_TABLES := ["mesa_sheriff", "pump_parts", "water_treatment", "quarry_office", "rail_freight", "rail_office",
	"dusthaven_police", "diner_kitchen", "motel_room", "scorch_cache", "scorch_warlord"]
## Which raiders wait where
const ENEMIES := {
	"RedMesa": ["veteran", "marauder"], "DryRiverPumpStation": ["raider", "veteran"], "CinderQuarry": ["veteran", "marauder"],
	"IronVeinRailYard": ["raider", "veteran"], "Dusthaven": ["raider", "veteran"], "BrokenSpurTruckStop": ["raider", "veteran"],
	"RaiderCampScorch": ["marauder", "veteran", "raider"],
}


func _mid(raiders_at: Array = []) -> Node3D:
	var zone := (load(MID) as PackedScene).instantiate() as Node3D
	for n in zone.find_children("*", "Node3D", true, false):
		if n is EnemySpawner:
			var site := str(zone.get_path_to(n)).get_slice("/", 0)
			(n as EnemySpawner).enabled = raiders_at.has(site)
	var p := zone.get_node("Player") as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	add_child(zone)
	await wait_physics(30)
	await wait_for_navigation(zone.get_world_3d().navigation_map)
	return zone


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


# ---------------------------------------------------------------- data

func test_the_places_are_built() -> void:
	var zone := (load(MID) as PackedScene).instantiate()
	for key: String in SITES:
		var s := zone.get_node_or_null(key) as Node3D
		check(s != null and s.scene_file_path.begins_with("res://levels/") and s.has_meta("region_name"), "%s is a real site" % key)
		if s == null:
			continue
		check(s.position.distance_to(SITES[key][0]) < 0.5, "%s where the map puts it" % key)
		check(s.get_node("Buildings").get_child_count() >= 3, "%s has buildings (%d)" % [key, s.get_node("Buildings").get_child_count()])
		check(s.get_node("SalvageContainers").get_child_count() >= 7, "%s has containers to search (%d)" % [key, s.get_node("SalvageContainers").get_child_count()])
		check(s.get_node("SalvagePiles").get_child_count() >= 4 and s.get_node("Loot").get_child_count() >= 5, "%s has salvage and loot" % key)
		var kinds := []
		for sp in s.get_children():
			if sp is EnemySpawner:
				kinds.append(str((sp as EnemySpawner).enemy_scene.resource_path).get_file().get_basename().trim_prefix("raider_").replace("raider", "raider"))
		for want: String in ENEMIES[key]:
			check(kinds.has(want) or (want == "raider" and kinds.has("raider")), "%s has %ss (%s)" % [key, want, kinds])
	check(zone.get_node_or_null("Blockouts") == null, "no blockouts left")
	var benches := 0
	for key: String in SITES:
		benches += zone.get_node(key + "/CraftingStations").get_child_count()
	check(benches >= 7, "workbenches (and a stove and a weapons bench) to find: %d" % benches)
	zone.free()


func test_new_loot_tables() -> void:
	for t: String in NEW_TABLES:
		var table := load("res://resources/loot/%s.tres" % t) as LootTable
		check(table != null and (table.entries.size() + table.guaranteed.size()) > 0, "%s loads" % t)
	# A gun every time from the armouries
	for t: String in ["mesa_sheriff", "dusthaven_police", "scorch_warlord"]:
		var table := load("res://resources/loot/%s.tres" % t) as LootTable
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var guns := 0
		for i in 20:
			for stack: Dictionary in table.roll(rng):
				if (stack["item"] as ItemDefinition).category == ItemDefinition.Category.WEAPON:
					guns += 1
		check(guns >= 20, "%s always holds a gun (%d in 20)" % [t, guns])


func test_the_scorch_marauder() -> void:
	var m := (load("res://scenes/enemies/raider_marauder.tscn") as PackedScene).instantiate() as Raider
	var v := (load("res://scenes/enemies/raider_veteran.tscn") as PackedScene).instantiate() as Raider
	add_child(m)
	await wait_physics(2)
	check(m.display_name == "Scorch Marauder", "the Scorch Marauder")
	check(m.health.max_health > (v.get_node("HealthComponent") as HealthComponent).max_health and m.attack_damage > v.attack_damage
		and m.sight_range > v.sight_range, "tougher than a veteran: %d health, hits for %d" % [m.health.max_health, m.attack_damage])
	var shot := DamageInfo.create(40.0, DamageInfo.Type.BALLISTIC)
	var before := m.health.current_health
	m.health.apply_damage(shot)
	check_near(before - m.health.current_health, 30.0, 0.01, "its plate takes a quarter off a bullet")
	before = m.health.current_health
	m.health.apply_damage(DamageInfo.create(10.0, DamageInfo.Type.FALL))
	check_near(before - m.health.current_health, 10.0, 0.01, "but not a fall")
	check(m.drop_chance == 1.0 and m.drop_items.any(func(i: ItemDefinition) -> bool: return i.id == &"scrap_helmet"), "always drops loot, sometimes armour")
	check(v.armour == 0.0, "veterans wear none")
	m.queue_free()
	v.free()


# ---------------------------------------------------------------- placement

func test_containers_clear_on_floors_and_searchable() -> void:
	var zone := await _mid()
	var p := zone.get_node("Player") as PlayerController
	var space := zone.get_world_3d().direct_space_state
	for key: String in SITES:
		for c: SalvageContainer in zone.get_node(key + "/SalvageContainers").get_children():
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
			check(not space.intersect_ray(down).is_empty(), "%s/%s stands on something" % [key, c.name])
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
	var zone := await _mid()
	var map := zone.get_world_3d().navigation_map
	var gate := NavigationServer3D.map_get_closest_point(map, Vector3(682, 0, -291))
	for key: String in SITES:
		var s := zone.get_node(key) as Node3D
		var start := NavigationServer3D.map_get_closest_point(map, s.transform * (SITES[key][1] as Vector3))
		var there := NavigationServer3D.map_get_path(map, gate, start, true)
		check(there.size() > 1 and there[there.size() - 1].distance_to(start) < 1.0, "%s: a way there from the road in" % key)
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


func test_salvage_and_pickups_placed_sensibly() -> void:
	var zone := await _mid()
	var space := zone.get_world_3d().direct_space_state
	for key: String in SITES:
		var s := zone.get_node(key)
		for pile: SalvagePile in s.get_node("SalvagePiles").get_children():
			var shape := pile.get_node("Shape") as CollisionShape3D
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape.shape
			if shape.shape is BoxShape3D:
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


func test_the_roads_stay_open() -> void:
	# Drive-through: a clear line along each road through a place (nothing solid on it)
	var zone := await _mid()
	var space := zone.get_world_3d().direct_space_state
	for seg: Array in [["Red Mesa's street", Vector3(712, 1.0, -652), Vector3(712, 1.0, -760)],
			["Dusthaven's main street", Vector3(766, 1.0, -55), Vector3(770, 1.0, -105)],
			["into Dusthaven from the north", Vector3(762, 1.0, -160), Vector3(770, 1.0, -105)],
			["the east road past the rail yard", Vector3(790, 1.0, -346), Vector3(850, 1.0, -350)],
			["the road north past Dry River", Vector3(694, 1.0, -420), Vector3(694, 1.0, -480)]]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(seg[1], seg[2], PhysicsLayers.STRUCTURES))
		check(hit.is_empty(), "%s is clear (%s)" % [seg[0], (hit.get("collider") as Node).get_path() if not hit.is_empty() else ""])
	await _free(zone)


# ---------------------------------------------------------------- raiders

func test_raiders_wait_at_each_place() -> void:
	var zone := await _mid(SITES.keys())
	var p := zone.get_node("Player") as PlayerController
	var map := zone.get_world_3d().navigation_map
	for key: String in SITES:
		var s := zone.get_node(key) as Node3D
		await _teleport(p, s.transform * (SITES[key][1] as Vector3) + Vector3.UP * 0.05)
		await get_tree().create_timer(EnemySpawner.CHECK_INTERVAL * 2.5).timeout
		await wait_physics(10)
		var names := []
		for sp in s.get_children():
			if not sp is EnemySpawner:
				continue
			check(not (sp as EnemySpawner).dormant, "%s/%s awake with you there" % [key, sp.name])
			for e in (sp as EnemySpawner).get_alive():
				names.append((e as Raider).display_name)
				var at := e.global_position
				check(Vector2(at.x - s.position.x, at.z - s.position.z).length() < 80.0, "%s: raider spawned at the place (%s)" % [key, at.snappedf(0.1)])
				check(at.y > -0.5 and at.y < 2.0, "%s: raider on the ground (y %.2f)" % [key, at.y])
				var on := NavigationServer3D.map_get_closest_point(map, at)
				check(on.distance_to(at) < 1.5, "%s: raider on the navmesh" % key)
		check(names.size() >= 3, "%s has raiders (%s)" % [key, names])
		if ENEMIES[key].has("marauder"):
			check(names.has("Scorch Marauder"), "%s has Scorch Marauders (%s)" % [key, names])
	await _free(zone)
