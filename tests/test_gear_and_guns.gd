extends "res://tests/test_case.gd"
## Increment 16.6: dying leaves your gear in a chest where you fell; guns
## you can find (Smuggler's Gulch, Northwatch); a gun bench at Northwatch;
## the Saint Mercy signpost out of the staff house.

const PISTOL := preload("res://resources/items/weapons/pistol_item.tres")
const SHOTGUN := preload("res://resources/items/weapons/shotgun_item.tres")
const SCRAP := preload("res://resources/items/scrap_metal.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const PISTOL_AMMO := preload("res://resources/items/pistol_ammo.tres")
const RED_DOT := preload("res://resources/items/red_dot.tres")


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _put(p: PlayerController, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await wait_physics(4)


func _kill(p: PlayerController) -> void:
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)


## A player carrying scrap, medkits and a pistol with a red dot and 7 rounds.
func _kit_out(p: PlayerController) -> void:
	p.inventory.clear()
	p.inventory.add_item(SCRAP, 5)
	p.inventory.add_item(MEDKIT, 2)
	p.inventory.add_item(PISTOL_AMMO, 20)
	check(p.give_weapon(PISTOL.weapon), "given a pistol")
	var w := p.weapon_slots.get_weapon(PISTOL.weapon.slot)
	w.fit_attachment(RED_DOT.attachment)
	w.ammo_in_magazine = 7


func _caches(zone: Node) -> Array:
	return zone.find_children("*", "DeathCache", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func _open(p: PlayerController, c: SalvageContainer) -> void:
	await _put(p, c.global_position + Vector3(0, 0.05, 1.3))
	check(c.try_interact(p, p.head.global_position), "opened %s" % c.name)
	await wait_physics(2)


# ---------------------------------------------------------------- dying

func test_dying_leaves_your_gear_where_you_fell() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var gm := zone.get_node("GameMode") as GameMode
	gm.respawn_delay = 0.0
	var spot := Vector3(60, 0.05, 40)
	await _put(p, spot)
	_kit_out(p)
	await _kill(p)
	var caches := _caches(zone)
	check(caches.size() == 1, "one chest where you fell (%d)" % caches.size())
	var c := caches[0] as DeathCache
	check(Vector2(c.global_position.x - spot.x, c.global_position.z - spot.z).length() < 0.5 and absf(c.global_position.y) < 0.5, "on the ground where you died (%s)" % c.global_position)
	check(c.inventory.count_of(&"scrap_metal") == 5 and c.inventory.count_of(&"medkit") == 2 and c.inventory.count_of(&"pistol_ammo") == 20, "your backpack is in it")
	check(c.inventory.count_of(PISTOL.id) == 1, "and your pistol")
	check(gm.get_dropped_gear(p) == c, "the game mode knows where it is")
	check(p.inventory.get_free_slot_count() == p.inventory.slot_count, "your backpack is empty")
	check(p.weapon_slots.owned().all(func(w: HitscanWeapon) -> bool: return w.definition.melee), "only your blade left")
	var marker := c.get_node("Marker") as Landmark
	check(marker != null and marker.is_in_group("landmarks") and marker.get_compass_name() == "Your gear", "on the compass as \"Your gear\"")
	# Respawn with nothing
	check(gm.try_respawn(p), "respawned")
	await wait_physics(2)
	check(p.inventory.count_of(&"pistol_ammo") == 0 and p.inventory.count_of(&"scrap_metal") == 0, "you come back with nothing (no free ammo either)")
	check(p.weapon != null and p.weapon.definition.melee, "blade in hand")
	# Walk back and take it all
	await _open(p, c)
	check(p.current_container == c, "your gear opens straight away (no searching)")
	p.request_take_all()
	check(p.inventory.count_of(&"scrap_metal") == 5 and p.inventory.count_of(&"medkit") == 2 and p.inventory.count_of(&"pistol_ammo") == 20, "everything's back in your backpack")
	var pistol := p.weapon_slots.get_weapon(PISTOL.weapon.slot)
	check(pistol != null and pistol.base_definition.id == PISTOL.weapon.id, "your pistol's back in its slot")
	check(pistol != null and pistol.get_attachment(RED_DOT.attachment.slot) == RED_DOT.attachment, "with its red dot")
	check(pistol != null and pistol.ammo_in_magazine == 7, "and the 7 rounds that were in it (%d)" % (pistol.ammo_in_magazine if pistol else -1))
	p.close_container()
	await wait_physics(2)
	check(_caches(zone).is_empty(), "the empty chest is gone")
	await _free(zone)


func test_nothing_to_drop_no_chest() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.inventory.clear()
	await _put(p, Vector3(60, 0.05, 40))
	await _kill(p)
	check(_caches(zone).is_empty(), "no chest when you carried nothing but a blade")
	await _free(zone)


func test_dying_in_the_storm_leaves_gear_where_you_can_reach_it() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var edge := ZoneBoundary.find_in(get_tree())
	# Walk east from Halden's until 8 m into the storm
	var at := Vector3(450, 0.05, -300)
	while edge.signed_distance(at) < 8.0 and at.x < 2000.0:
		at.x += 1.0
	await _put(p, at)
	check(edge.signed_distance(p.global_position) > 0.0, "out in the ash storm (%.1f m past the edge)" % edge.signed_distance(p.global_position))
	p.inventory.add_item(SCRAP, 3)
	await _kill(p)
	var c := _caches(zone)[0] as DeathCache
	check(edge.signed_distance(c.global_position) <= -DeathCache.EDGE_MARGIN + 0.5, "the chest is pulled back inside, clear of the storm (%.1f m)" % edge.signed_distance(c.global_position))
	check(absf(c.global_position.y) < 1.0, "on the ground")
	await _free(zone)


func test_dropped_gear_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_gear"
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var gm := zone.get_node("GameMode") as GameMode
	gm.respawn_delay = 0.0
	await _put(p, Vector3(60, 0.05, 40))
	_kit_out(p)
	await _kill(p)
	var at := (_caches(zone)[0] as Node3D).global_position
	gm.try_respawn(p)
	await wait_physics(2)
	check(saves.save_game("gear_test", zone) == OK, "saved after dying")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("gear_test", zone2) == OK, "loaded")
	await wait_physics(3)
	var caches := _caches(zone2)
	check(caches.size() == 1, "your gear is still out there")
	if caches.size() == 1:
		var c := caches[0] as DeathCache
		check(c.global_position.distance_to(at) < 0.05, "where you left it")
		check(c.inventory.count_of(&"scrap_metal") == 5 and c.inventory.count_of(PISTOL.id) == 1, "with everything in it")
		var p2 := zone2.get_node("Player") as PlayerController
		await _open(p2, c)
		p2.request_take_all()
		var pistol := p2.weapon_slots.get_weapon(PISTOL.weapon.slot)
		check(pistol != null and pistol.get_attachment(RED_DOT.attachment.slot) == RED_DOT.attachment and pistol.ammo_in_magazine == 7, "the pistol comes back as it was")
	saves.delete_save("gear_test")
	saves.save_dir = "user://saves"
	await _free(zone2)


# ---------------------------------------------------------------- guns

func test_guns_to_find_in_the_gulch_and_at_northwatch() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 166
	for table in ["smuggler_guns", "garrison_armory"]:
		var t := load("res://resources/loot/%s.tres" % table) as LootTable
		for i in 20:
			var guns := t.roll(rng).filter(func(e: Dictionary) -> bool: return (e["item"] as ItemDefinition).weapon != null)
			check(guns.size() == 1 and guns[0]["qty"] == 1, "%s: always exactly one gun (%d)" % [table, guns.size()])
	var zone := instance_zone()
	for path in ["SmugglersGulch/SalvageContainers/GunCabinet", "NorthwatchOutpost/SalvageContainers/ArmoryLockerA", "NorthwatchOutpost/SalvageContainers/ArmoryLockerB"]:
		var c := zone.get_node(path) as SalvageContainer
		check(c.loot_table != null and c.loot_table.one_of.any(func(e: LootEntry) -> bool: return e.item.weapon != null), "%s holds a gun" % path)
	# Better loot all round
	for path in ["SmugglersGulch/SalvageContainers/ContrabandA", "SmugglersGulch/SalvageContainers/LookoutCache",
			"NorthwatchOutpost/SalvageContainers/ArmoryAmmo", "NorthwatchOutpost/SalvageContainers/BarracksCrate",
			"NorthwatchOutpost/SalvageContainers/StoresCrate", "NorthwatchOutpost/SalvageContainers/OfficersLocker"]:
		var c := zone.get_node(path) as SalvageContainer
		var t := c.loot_table
		check(t.max_rolls >= 3 or not t.guaranteed.is_empty(), "%s: a better haul (%s)" % [path, t.resource_path.get_file()])
		for item in t.possible_items():
			check(ItemDatabase.get_item(item.id) == item, "%s: %s is a real item" % [path, item.id])
	check((zone.get_node("SmugglersGulch/SalvageContainers/LookoutCache") as SalvageContainer).loot_table.possible_items().has(load("res://resources/items/weapons/scoped_rifle_item.tres")),
		"the gulch's lookout may hold a scoped rifle")
	zone.free()


func test_a_gun_from_a_container_goes_into_your_hands() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var cab := zone.get_node("SmugglersGulch/SalvageContainers/GunCabinet") as SalvageContainer
	cab.search()
	cab.inventory.clear()
	cab.inventory.add_item(SHOTGUN, 1)
	cab.inventory.add_item(SHOTGUN, 1)
	await _open(p, cab)
	var slot := -1
	for i in cab.inventory.slot_count:
		if cab.inventory.get_slot_item(i) == SHOTGUN:
			slot = i
			break
	check(p.request_take(slot) == 1, "took the shotgun")
	var gun := p.weapon_slots.get_weapon(SHOTGUN.weapon.slot)
	check(gun != null and gun.base_definition.id == SHOTGUN.weapon.id, "it's in its weapon slot, ready to use")
	check(p.inventory.count_of(SHOTGUN.id) == 0, "not stuffed in the backpack")
	# A second one: you already have it, so it's a spare in your backpack
	check(p.request_take_all() == 1, "took the second")
	check(p.inventory.count_of(SHOTGUN.id) == 1, "as a spare, since you have one (Increment 16.7)")
	check(cab.inventory.count_of(SHOTGUN.id) == 0, "the cabinet is empty")
	await _free(zone)


func test_gun_bench_at_northwatch() -> void:
	var zone := instance_zone()
	var bench := zone.get_node_or_null("NorthwatchOutpost/CraftingStations/ArmoryWeaponsBench") as CraftingStation
	check(bench != null, "a weapons bench at Northwatch")
	var armory := zone.get_node("NorthwatchOutpost/Buildings/Armory") as Node3D
	var local := armory.to_local(bench.global_position) if armory.is_inside_tree() else armory.transform.affine_inverse() * bench.position
	var size: Vector2 = armory.get_meta("size")
	check(absf(local.x) < size.x / 2.0 and absf(local.z) < size.y / 2.0, "inside the armory (%s)" % local)
	zone.free()


# ---------------------------------------------------------------- signposts

func test_signposts_stand_in_the_open() -> void:
	var zone := await load_zone()
	var space := zone.get_world_3d().direct_space_state
	var posts := zone.get_node("Roads/Signposts").get_children()
	check(posts.size() >= 7, "the signposts (%d)" % posts.size())
	var mine: Array[RID] = []
	for p: StaticBody3D in posts:
		mine.append(p.get_rid())
	for post: StaticBody3D in posts:
		# Its post and arms reach ~3 m: nothing solid may be within that
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 3.1
		sh.height = 2.8
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, post.global_position + Vector3(0, 1.6, 0))
		q.collision_mask = PhysicsLayers.STRUCTURES
		q.exclude = mine
		var hits := space.intersect_shape(q, 4)
		check(hits.is_empty(), "signpost at %s stands in the open%s" % [post.global_position.snappedf(1),
			"" if hits.is_empty() else " (in %s)" % (hits[0]["collider"] as Node).name])
	await _free(zone)
