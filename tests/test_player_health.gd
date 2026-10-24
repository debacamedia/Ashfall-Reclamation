extends "res://tests/test_case.gd"
## Player health: fall damage, death state, kill plane, GameMode respawn,
## DamageZone.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0


func _spawn(at := Vector3(0, 0.05, 0)) -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.controlled_locally = false
	player.head_bob_enabled = false
	player.position = at
	add_child(player)
	return player


func _drive(player: PlayerController, frame: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		player.simulate(frame, DT)


func _frame(move := Vector2.ZERO, jump := false, fire := false) -> InputFrame:
	var f := InputFrame.new()
	f.move = move
	f.jump = jump
	f.fire = fire
	return f


func _game_mode(player: PlayerController, delay: float) -> GameMode:
	var spawn := Marker3D.new()
	spawn.position = Vector3(5, 0.05, 5)
	add_child(spawn)
	var gm := GameMode.new()
	gm.respawn_delay = delay
	gm.spawn_point = spawn
	add_child(gm)
	gm.register_player(player)
	return gm


func _kill(player: PlayerController, type := DamageInfo.Type.BALLISTIC) -> void:
	player.health.apply_damage(DamageInfo.create(500.0, type))


# ---------------------------------------------------------------- fall damage

func test_starts_with_full_health() -> void:
	var p := _spawn()
	await wait_physics(2)
	check_near(p.health.current_health, 100.0, 0.01, "player starts at 100")


func test_short_drop_is_safe() -> void:
	var p := _spawn(Vector3(0, 3.0, 0))
	await _drive(p, _frame(), 90)
	check(p.is_on_floor(), "landed")
	check_near(p.health.current_health, 100.0, 0.01, "a 3 m drop does no damage")


func test_eight_metre_fall_hurts_proportionally() -> void:
	var p := _spawn(Vector3(0, 8.0, 0))
	var landings := []
	p.landed.connect(func(v: float) -> void: landings.append(v))
	await _drive(p, _frame(), 120)
	check(landings.size() == 1, "landed once")
	var expected := p.fall_damage_for_speed(sqrt(2.0 * 9.8 * 8.0))
	check_near(100.0 - p.health.current_health, expected, 4.0, "fall damage matches the impact-speed curve")
	check(not p.is_dead(), "survives an 8 m fall")


func test_long_fall_is_lethal() -> void:
	var p := _spawn(Vector3(0, 25.0, 0))
	var causes := []
	p.died.connect(func(info: DamageInfo) -> void: causes.append(info.type))
	await _drive(p, _frame(), 180)
	check(p.is_dead(), "a 25 m fall kills")
	check(causes == [DamageInfo.Type.FALL], "died from FALL damage")


func test_fall_damage_curve() -> void:
	var p := _spawn()
	await wait_physics(1)
	check_near(p.fall_damage_for_speed(7.9), 0.0, 0.001, "below safe speed: none")
	check_near(p.fall_damage_for_speed(13.0), 50.0, 0.001, "half-way: half health")
	check(p.fall_damage_for_speed(18.0) >= 100.0, "lethal speed: full health")


func test_kill_plane_kills() -> void:
	var p := _spawn()
	await wait_physics(2)
	p.global_position = Vector3(0, -40, 0)
	await wait_physics(2)
	check(p.is_dead(), "falling out of the world kills")


# ---------------------------------------------------------------- death state

func test_dead_player_cannot_move_or_shoot() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	_kill(p)
	check(p.movement_state == PlayerController.MovementState.DEAD, "state is DEAD")
	var start := p.global_position
	await _drive(p, _frame(Vector2(0, -1), false, true), 60)
	check(Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() < 0.05, "no movement while dead")
	check(p.weapon.ammo_in_magazine == 30, "no shots while dead")
	check(not p.weapon.visible, "weapon hidden while dead")


func test_death_camera_drops() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	_kill(p)
	await wait_physics(60)
	check(p.head.position.y < 0.6, "camera dropped toward the ground (y=%.2f)" % p.head.position.y)


func test_jump_while_dead_requests_respawn() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	var requests := [0]
	p.respawn_requested.connect(func() -> void: requests[0] += 1)
	await _drive(p, _frame(Vector2.ZERO, true), 1)
	check(requests[0] == 0, "no request while alive")
	_kill(p)
	await _drive(p, _frame(Vector2.ZERO, true), 1)
	check(requests[0] == 1, "jump while dead requests respawn")


# ---------------------------------------------------------------- GameMode

func test_respawn_waits_for_delay_then_restores_player() -> void:
	var p := _spawn()
	var gm := _game_mode(p, 0.4)
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2.ZERO, false, true), 20)  # spend some ammo
	_kill(p)
	await _drive(p, _frame(Vector2.ZERO, true), 1)
	check(p.is_dead(), "respawn refused before the delay")
	check(gm.get_respawn_time_left(p) > 0.0, "time left is reported")
	await get_tree().create_timer(0.45).timeout
	check(gm.can_respawn(p), "allowed after the delay")
	await _drive(p, _frame(Vector2.ZERO, true), 1)
	check(not p.is_dead(), "respawned")
	check_near(p.health.current_health, 100.0, 0.01, "full health")
	check(p.global_position.distance_to(Vector3(5, 0.05, 5)) < 0.3, "at the spawn point")
	check(p.weapon.visible and p.weapon.ammo_in_magazine == 30, "weapon visible and restocked")
	check(absf(p.head.rotation.z) < 0.001, "camera upright again")
	await _drive(p, _frame(Vector2(0, -1)), 60)
	check(p.get_horizontal_speed() > 4.0, "can move again")


func test_death_causes() -> void:
	check(GameMode.describe_cause(DamageInfo.create(1, DamageInfo.Type.FALL)) == "You fell to your death", "fall")
	var zone := DamageZone.new()
	zone.death_message = "You burned to death"
	var burn := DamageInfo.create(1, DamageInfo.Type.ENVIRONMENT, zone)
	check(GameMode.describe_cause(burn) == "You burned to death", "zone message")
	var shooter := Node3D.new()
	shooter.name = "Raider"
	check(GameMode.describe_cause(DamageInfo.create(1, DamageInfo.Type.BALLISTIC, shooter)) == "Killed by Raider", "named source")
	zone.free()
	shooter.free()


# ---------------------------------------------------------------- DamageZone

func _zone(at: Vector3, dps := 20.0) -> DamageZone:
	var zone := DamageZone.new()
	zone.damage_per_second = dps
	zone.tick_interval = 0.25
	zone.collision_layer = PhysicsLayers.TRIGGERS
	zone.collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.NPCS
	zone.position = at
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	cs.shape = box
	cs.position = Vector3(0, 1, 0)
	zone.add_child(cs)
	add_child(zone)
	return zone


func test_damage_zone_hurts_over_time_and_stops_outside() -> void:
	var p := _spawn(Vector3(10, 0.05, 0))
	_zone(Vector3.ZERO)
	await _drive(p, _frame(), 5)
	check_near(p.health.current_health, 100.0, 0.01, "safe outside the zone")
	p.global_position = Vector3(0, 0.05, 0)
	await _drive(p, _frame(), 60)  # 1 s inside at 20 dps
	check_between(100.0 - p.health.current_health, 15.0, 25.0, "about 20 damage in one second")
	p.global_position = Vector3(10, 0.05, 0)
	await _drive(p, _frame(), 5)
	var after_leaving := p.health.current_health
	await _drive(p, _frame(), 60)
	check_near(p.health.current_health, after_leaving, 0.01, "no damage after leaving")


func test_damage_zone_hurts_npcs_too() -> void:
	_zone(Vector3.ZERO)
	var npc := CharacterBody3D.new()
	npc.collision_layer = PhysicsLayers.NPCS
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	cs.position = Vector3(0, 1, 0)
	npc.add_child(cs)
	var h := HealthComponent.new()
	npc.add_child(h)
	add_child(npc)
	await wait_physics(40)
	check(h.current_health < 100.0, "NPC with health is hurt by the zone")
