extends "res://tests/test_case.gd"
## Level tests: Outpost 17 loads, the player spawns correctly, and key routes
## (gate, building door, culvert) are walkable at the intended stance.

const LEVEL := preload("res://levels/outpost_17/outpost_17.tscn")
const DT := 1.0 / 60.0

var _level: Node3D
var _player: PlayerController


func _load_level() -> void:
	_level = LEVEL.instantiate() as Node3D
	_player = _level.get_node("Player") as PlayerController
	_player.controlled_locally = false
	_player.head_bob_enabled = false
	add_child(_level)
	await wait_physics(30)


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
