extends "res://tests/test_case.gd"
## Level tests: Outpost 17 loads, the player spawns correctly, and key routes
## (gate, building door, culvert) are walkable at the intended stance.

const LEVEL := preload("res://levels/outpost_17/outpost_17.tscn")
const DT := 1.0 / 60.0

var _level: Node3D
var _player: PlayerController


## Raiders are off by default so earlier tests aren't interrupted by attacks.
func _load_level(raiders := false) -> void:
	_level = LEVEL.instantiate() as Node3D
	_player = _level.get_node("Player") as PlayerController
	_player.controlled_locally = false
	_player.head_bob_enabled = false
	(_level.get_node("RaiderSpawner") as EnemySpawner).enabled = raiders
	add_child(_level)
	await wait_physics(30)
	await wait_for_navigation(_level.get_world_3d().navigation_map)


func _walk(move: Vector2, ticks: int, crouch := false) -> void:
	var f := InputFrame.new()
	f.move = move
	f.crouch = crouch
	for i in ticks:
		await get_tree().physics_frame
		_player.simulate(f, DT)


func _teleport(pos: Vector3, yaw_deg: float) -> void:
	_player.global_position = pos
	_player.rotation_degrees.y = yaw_deg
	_player.velocity = Vector3.ZERO
	await wait_physics(5)


func test_level_loads_with_player_on_ground() -> void:
	await _load_level()
	check(_player != null, "Player node exists")
	var spawn := _level.get_node("PlayerSpawn") as Marker3D
	check(_player.global_position.distance_to(spawn.global_position) < 0.3, "player starts at PlayerSpawn")
	await _walk(Vector2.ZERO, 10)
	check(_player.is_on_floor(), "player stands on the terrain")
	var hud := _level.get_node("HUD") as HUD
	check(hud != null and hud.player == _player, "HUD is wired to the player")


func test_can_walk_out_through_gate() -> void:
	await _load_level()
	await _teleport(Vector3(0, 0.05, 18), 180)  # facing south (+Z)
	await _walk(Vector2(0, -1), 240)
	check(_player.global_position.z > 27.0, "walked out through the main gate (z=%.1f)" % _player.global_position.z)


func test_perimeter_wall_blocks() -> void:
	await _load_level()
	await _teleport(Vector3(10, 0.05, -21), 0)  # facing north, clear of containers
	await _walk(Vector2(0, -1), 240)
	check(_player.global_position.z > -24.5, "north wall must stop the player (z=%.1f)" % _player.global_position.z)


func test_can_enter_barracks_door() -> void:
	await _load_level()
	# Barracks at (12, 0, -16); its door faces +Z at z = -13
	await _teleport(Vector3(12, 0.05, -8), 0)
	await _walk(Vector2(0, -1), 180)
	check(_player.global_position.z < -14.5, "walked in through the barracks door (z=%.1f)" % _player.global_position.z)


func test_culvert_needs_crouch() -> void:
	await _load_level()
	# Culvert at (-24, 0, -6), running along Z from -9 to -3
	await _teleport(Vector3(-24, 0.05, -1.0), 0)
	await _walk(Vector2(0, -1), 180)
	check(_player.global_position.z > -3.2, "standing player is stopped at the culvert mouth (z=%.1f)" % _player.global_position.z)
	await _walk(Vector2(0, -1), 300, true)
	check(_player.global_position.z < -9.5, "crouching player gets through the culvert (z=%.1f)" % _player.global_position.z)


func test_firing_range_targets_take_damage() -> void:
	await _load_level()
	var dummy := _level.get_node("FiringRange/Target10mA") as TargetDummy
	check(dummy != null, "10 m target exists")
	# Stand at the firing line, aim at the torso of the 10 m target
	await _teleport(Vector3(13.5, 0.05, 34), -90)
	var torso := dummy.global_position + Vector3(0, 1.3, 0)
	var eye := _player.head.global_position
	var flat := Vector2(torso.x - eye.x, torso.z - eye.z).length()
	_player.head.rotation.x = atan2(torso.y - eye.y, flat)
	var f := InputFrame.new()
	f.fire = true
	await get_tree().physics_frame
	_player.simulate(f, DT)
	f.fire = false
	await get_tree().physics_frame
	_player.simulate(f, DT)
	check(dummy.health.current_health < dummy.health.max_health, "shot from the firing line damaged the 10 m target")
	var hud := _level.get_node("HUD") as HUD
	var ammo_label := hud.get_node("%AmmoLabel") as Label
	var expected := "%d / %d" % [_player.weapon.ammo_in_magazine, _player.weapon.reserve_ammo]
	check(_player.weapon.ammo_in_magazine == 29, "one round fired (mag=%d)" % _player.weapon.ammo_in_magazine)
	check(ammo_label.text == expected, "HUD ammo shows '%s' (got '%s')" % [expected, ammo_label.text])


# ---------------------------------------------------------------- Increment 3

func test_climb_range_tower_and_jump_off_takes_fall_damage() -> void:
	await _load_level()
	# Bottom of the ramp is at x = 26, z = 47; walk up toward -X
	await _teleport(Vector3(27.5, 0.05, 47), 90)
	await _walk(Vector2(0, -1), 300)
	check(_player.global_position.y > 5.8, "reached the 6 m platform (y=%.2f)" % _player.global_position.y)
	check_near(_player.health.current_health, 100.0, 0.01, "climbing the stairs does no damage")
	# Turn to face +Z (the open back edge) and walk off
	_player.rotation_degrees.y = 180
	await _walk(Vector2(0, -1), 150)
	check(_player.global_position.y < 0.2, "fell to the ground")
	var taken := 100.0 - _player.health.current_health
	check_between(taken, 15.0, 45.0, "a 6 m fall hurts but doesn't kill")


func test_burning_barrel_hurts_when_touched() -> void:
	await _load_level()
	var barrel := _level.get_node("Props/BurningBarrelYard") as Node3D
	await _teleport(barrel.global_position + Vector3(0.7, 0.05, 0), 0)
	await _walk(Vector2.ZERO, 60)
	check(_player.health.current_health < 100.0, "standing in the flames hurts")
	await _teleport(barrel.global_position + Vector3(4, 0.05, 0), 0)
	var hp := _player.health.current_health
	await _walk(Vector2.ZERO, 60)
	check_near(_player.health.current_health, hp, 0.01, "safe away from the fire")


func test_death_screen_and_respawn_loop() -> void:
	await _load_level()
	var gm := _level.get_node("GameMode") as GameMode
	var hud := _level.get_node("HUD") as HUD
	gm.respawn_delay = 0.3
	await _teleport(Vector3(10, 0.05, 0), 0)
	_player.health.apply_damage(DamageInfo.create(35.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	check((hud.get_node("%HealthLabel") as Label).text == "65", "HUD shows 65 health")
	_player.health.apply_damage(DamageInfo.create(100.0, DamageInfo.Type.FALL))
	await wait_physics(2)
	var death_screen := hud.get_node("%DeathScreen") as Control
	check(death_screen.visible, "death screen shown")
	check((hud.get_node("%DeathCause") as Label).text == "You fell to your death", "cause shown")
	check((hud.get_node("%RespawnPrompt") as Label).text.begins_with("Respawn in"), "countdown shown")
	await get_tree().create_timer(0.35).timeout
	await wait_physics(2)
	check((hud.get_node("%RespawnPrompt") as Label).text == "Press SPACE to respawn", "prompt after the delay")
	var f := InputFrame.new()
	f.jump = true
	await get_tree().physics_frame
	_player.simulate(f, DT)
	await wait_physics(2)
	check(not _player.is_dead(), "respawned")
	var spawn := _level.get_node("PlayerSpawn") as Marker3D
	check(_player.global_position.distance_to(spawn.global_position) < 0.5, "back at PlayerSpawn")
	check(not death_screen.visible, "death screen hidden")
	check((hud.get_node("%HealthLabel") as Label).text == "100", "HUD back to 100")


# ---------------------------------------------------------------- Increment 4

func _nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(_level.get_world_3d().navigation_map, from, to, true)


func test_navmesh_routes_through_gate_into_buildings() -> void:
	await _load_level()
	var path := _nav_path(Vector3(-6, 0, 66), Vector3(12, 0, -15.5))
	check(path.size() > 2, "path from the south spawn to the barracks exists")
	if path.size() > 0:
		check(path[path.size() - 1].distance_to(Vector3(12, 0.5, -15.5)) < 1.0, "path ends inside the barracks")
		var via_gate := false
		for pt in path:
			if absf(pt.x) < 4.0 and pt.z > 21.0 and pt.z < 28.0:
				via_gate = true
		check(via_gate, "path goes through the main gate")


func test_navmesh_culvert_too_low_for_raiders() -> void:
	await _load_level()
	var path := _nav_path(Vector3(-24, 0, 0), Vector3(-24, 0, -12))
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	check(length > 14.0, "raiders must go around the culvert (path %.1f m, straight is 12 m)" % length)


func test_spawner_fills_outside_the_walls() -> void:
	await _load_level(true)
	await wait_physics(5)
	var spawner := _level.get_node("RaiderSpawner") as EnemySpawner
	var raiders := spawner.get_alive()
	check(raiders.size() == 3, "3 raiders alive (got %d)" % raiders.size())
	for r in raiders:
		var p := r.global_position
		check(absf(p.x) > 33.0 or absf(p.z) > 26.0, "raider spawned outside the walls at %s" % p.snappedf(0.1))
		check(p.distance_to(_player.global_position) > 25.0, "not near the player")


func test_raider_comes_through_gate_and_attacks_player_in_yard() -> void:
	var spawner_node: EnemySpawner
	_level = LEVEL.instantiate() as Node3D
	_player = _level.get_node("Player") as PlayerController
	_player.controlled_locally = false
	_player.head_bob_enabled = false
	spawner_node = _level.get_node("RaiderSpawner") as EnemySpawner
	spawner_node.max_alive = 1
	add_child(_level)
	await wait_physics(30)
	await wait_for_navigation(_level.get_world_3d().navigation_map)
	await _teleport(Vector3(0, 0.05, 5), 0)
	var raider := spawner_node.get_alive()[0] as Raider
	raider.alert_to(_player)
	var passed_gate := false
	for i in 60 * 45:
		await _walk(Vector2.ZERO, 1)
		if absf(raider.global_position.x) < 4.5 and absf(raider.global_position.z - 24.5) < 2.0:
			passed_gate = true
		if _player.health.current_health < 100.0:
			break
	check(passed_gate, "came in through the main gate")
	check(_player.health.current_health < 100.0, "reached and hit the player in the yard")


func test_spawner_replaces_killed_raider() -> void:
	_level = LEVEL.instantiate() as Node3D
	_player = _level.get_node("Player") as PlayerController
	_player.controlled_locally = false
	var spawner := _level.get_node("RaiderSpawner") as EnemySpawner
	spawner.max_alive = 1
	spawner.respawn_delay = 0.3
	add_child(_level)
	await wait_physics(10)
	var first := spawner.get_alive()[0] as Raider
	first.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	check(spawner.get_alive().is_empty(), "none alive right after the kill")
	await get_tree().create_timer(0.4).timeout
	await wait_physics(2)
	var alive := spawner.get_alive()
	check(alive.size() == 1 and alive[0] != first, "a new raider spawned after the delay")


# ---------------------------------------------------------------- Increment 5

func test_loot_placed_on_surfaces() -> void:
	await _load_level()
	var loot := _level.get_node("Loot").get_children()
	check(loot.size() >= 20, "at least 20 loot pickups (%d)" % loot.size())
	var space := _level.get_world_3d().direct_space_state
	for pk: Node3D in loot:
		var from := pk.global_position + Vector3(0, 0.3, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.0, PhysicsLayers.WORLD_SOLID)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and from.y - (hit["position"] as Vector3).y < 0.45, "%s rests on a surface" % pk.name)


func test_hud_prompt_and_notice_for_range_ammo() -> void:
	await _load_level()
	var hud := _level.get_node("HUD") as HUD
	var ammo := _level.get_node("Loot/RangeAmmoA") as Pickup
	await _teleport(Vector3(10.2, 0.05, 35.4), 0)
	var eye := _player.head.global_position
	var target := ammo.global_position + Vector3(0, 0.1, 0)
	var flat := Vector3(target.x - eye.x, 0, target.z - eye.z)
	_player.rotation.y = atan2(-flat.x, -flat.z)
	_player.head.rotation.x = atan2(target.y - eye.y, flat.length())
	await _walk(Vector2.ZERO, 3)
	var prompt := hud.get_node("%PromptLabel") as Label
	check(prompt.visible and prompt.text == "[E]  Pick up Rifle Ammo ×30", "prompt: '%s'" % prompt.text)
	var reserve := _player.weapon.reserve_ammo
	var f := InputFrame.new()
	f.interact = true
	await get_tree().physics_frame
	_player.simulate(f, DT)
	await wait_physics(3)
	check(_player.weapon.reserve_ammo == reserve + 30, "reserve +30")
	var notices := hud.get_node("%Notices") as VBoxContainer
	check(notices.get_child_count() >= 1 and (notices.get_child(0) as Label).text == "+30 Rifle Ammo", "pickup notice shown")


func test_can_pick_loot_off_warehouse_shelves() -> void:
	await _load_level()
	for spec in [["WarehouseShelfScrap", Vector3(-22.8, 0.05, 13.0)], ["WarehouseShelfCloth", Vector3(-22.8, 0.05, 3.0)]]:
		var pk := _level.get_node("Loot/" + spec[0]) as Pickup
		await _teleport(spec[1], 90)
		var eye := _player.head.global_position
		var target := pk.global_position + Vector3(0, 0.1, 0)
		var flat := Vector3(target.x - eye.x, 0, target.z - eye.z)
		_player.rotation.y = atan2(-flat.x, -flat.z)
		_player.head.rotation.x = atan2(target.y - eye.y, flat.length())
		await _walk(Vector2.ZERO, 3)
		check(_player.interactor.focused == pk, "%s on the rack can be targeted" % spec[0])
		var item_id := pk.item.id
		var before := _player.inventory.count_of(item_id)
		var f := InputFrame.new()
		f.interact = true
		await get_tree().physics_frame
		_player.simulate(f, DT)
		f.interact = false
		await get_tree().physics_frame
		_player.simulate(f, DT)
		check(_player.inventory.count_of(item_id) > before, "%s actually picked up with E" % spec[0])


func test_no_loot_overlaps_solid_geometry() -> void:
	await _load_level()
	var space := _level.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.25, 0.35)
	for pk: Node3D in _level.get_node("Loot").get_children():
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = Transform3D(pk.global_basis, pk.global_position + Vector3(0, 0.2, 0))
		q.collision_mask = PhysicsLayers.WORLD_SOLID
		var hits := space.intersect_shape(q, 4)
		var names := hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))
		check(hits.is_empty(), "%s is clear of solid geometry (overlaps %s)" % [pk.name, names])
