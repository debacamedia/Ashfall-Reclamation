extends "res://tests/test_case.gd"
## PlayerController movement tests. The player is driven with InputFrames
## (controlled_locally = false), exactly as a remote co-op player will be.

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


## Applies the same frame for n physics ticks.
func _drive(player: PlayerController, frame: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		player.simulate(frame, DT)


func _frame(move := Vector2.ZERO, sprint := false, crouch := false, jump := false) -> InputFrame:
	var f := InputFrame.new()
	f.move = move
	f.sprint = sprint
	f.crouch = crouch
	f.jump = jump
	return f


func test_settles_on_floor() -> void:
	var p := _spawn(Vector3(0, 0.5, 0))
	await _drive(p, _frame(), 40)
	check(p.is_on_floor(), "player should be on the floor")
	check_near(p.global_position.y, 0.0, 0.05, "feet should rest at y=0")


func test_walk_reaches_walk_speed_forward() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2(0, -1)), 90)
	check_near(p.get_horizontal_speed(), p.walk_speed, 0.25, "walk speed")
	check(p.global_position.z < -4.0, "forward (W) should move toward -Z")
	check(p.movement_state == PlayerController.MovementState.WALKING, "state should be WALKING")


func test_sprint_is_faster() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2(0, -1), true), 90)
	check_near(p.get_horizontal_speed(), p.sprint_speed, 0.3, "sprint speed")
	check(p.movement_state == PlayerController.MovementState.SPRINTING, "state should be SPRINTING")


func test_no_sprint_backwards() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2(0, 1), true), 90)
	check_near(p.get_horizontal_speed(), p.walk_speed, 0.25, "backwards sprint should be capped at walk speed")


func test_stops_when_input_released() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2(0, -1)), 60)
	await _drive(p, _frame(), 30)
	check(p.get_horizontal_speed() < 0.1, "should come to a stop")
	check(p.movement_state == PlayerController.MovementState.IDLE, "state should be IDLE")


func test_jump_height_and_landing() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 10)
	var landings := []
	p.landed.connect(func(speed: float) -> void: landings.append(speed))
	var jumps := [0]
	p.jumped.connect(func() -> void: jumps[0] += 1)
	await _drive(p, _frame(Vector2.ZERO, false, false, true), 1)
	var peak := 0.0
	for i in 90:
		await _drive(p, _frame(), 1)
		peak = maxf(peak, p.global_position.y)
	var expected := p.jump_velocity * p.jump_velocity / (2.0 * 9.8)
	check_near(peak, expected, 0.1, "jump apex height")
	check(jumps[0] == 1, "jumped signal should fire once")
	check(landings.size() == 1, "landed signal should fire once")
	check(p.is_on_floor(), "should be back on the floor")


func test_no_double_jump() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 10)
	await _drive(p, _frame(Vector2.ZERO, false, false, true), 1)
	await _drive(p, _frame(), 10)
	var vy_before := p.velocity.y
	await _drive(p, _frame(Vector2.ZERO, false, false, true), 1)
	check(p.velocity.y < vy_before, "jumping in mid-air must not add upward speed")


func test_crouch_lowers_height_and_speed() -> void:
	var p := _spawn()
	await _drive(p, _frame(), 5)
	var standing_head := p.head.position.y
	await _drive(p, _frame(Vector2(0, -1), false, true), 90)
	check(p.is_crouching, "should be crouching")
	var capsule := p.collision_shape.shape as CapsuleShape3D
	check_near(capsule.height, p.crouch_height, 0.01, "capsule height while crouched")
	check(p.head.position.y < standing_head - 0.5, "camera should drop when crouching")
	check_near(p.get_horizontal_speed(), p.crouch_speed, 0.2, "crouch speed")
	check(p.movement_state == PlayerController.MovementState.CROUCHING, "state should be CROUCHING")


func test_cannot_jump_while_crouched() -> void:
	var p := _spawn()
	await _drive(p, _frame(Vector2.ZERO, false, true), 30)
	await _drive(p, _frame(Vector2.ZERO, false, true, true), 1)
	await _drive(p, _frame(Vector2.ZERO, false, true), 5)
	check(p.global_position.y < 0.05, "crouch-jump from the ground should do nothing")


func test_stays_crouched_under_low_ceiling() -> void:
	var p := _spawn()
	# Slab whose underside is 1.4 m above the floor, centred at x = 0..4
	make_static_box(Vector3(4, 0.3, 4), Vector3(0, 1.55, 0))
	await _drive(p, _frame(Vector2.ZERO, false, true), 40)
	await _drive(p, _frame(), 30)  # release crouch under the slab
	check(p.is_crouching, "must stay crouched with a ceiling overhead")
	# Walk out (+X) from under the slab, then the player can stand
	p.rotation.y = 0.0
	await _drive(p, _frame(Vector2(1, 0)), 120)
	await _drive(p, _frame(), 40)
	check(not p.is_crouching, "should stand up once clear of the ceiling")
	var capsule := p.collision_shape.shape as CapsuleShape3D
	check_near(capsule.height, p.stand_height, 0.01, "full height after standing")


func test_wall_blocks_movement() -> void:
	var p := _spawn()
	make_static_box(Vector3(10, 3, 0.5), Vector3(0, 1.5, -3))
	await _drive(p, _frame(), 5)
	await _drive(p, _frame(Vector2(0, -1), true), 180)
	check(p.global_position.z > -2.8, "player must not pass through the wall (z=%.2f)" % p.global_position.z)


func test_look_pitch_clamped() -> void:
	var p := _spawn()
	var f := _frame()
	f.look = Vector2(0, 10.0)
	await _drive(p, f, 1)
	check_near(p.head.rotation_degrees.x, -p.max_pitch_degrees, 0.01, "look-down clamp")
	f.look = Vector2(0, -20.0)
	await _drive(p, f, 1)
	check_near(p.head.rotation_degrees.x, p.max_pitch_degrees, 0.01, "look-up clamp")


func test_yaw_turns_body() -> void:
	var p := _spawn()
	var f := _frame()
	f.look = Vector2(PI / 2.0, 0)
	await _drive(p, f, 1)
	await _drive(p, _frame(Vector2(0, -1)), 60)
	check(p.global_position.x > 2.0, "after turning right 90°, forward should move toward +X")


func test_kill_plane_respawns() -> void:
	var p := _spawn(Vector3(5, 0.05, 5))
	await wait_physics(2)
	p.global_position = Vector3(0, -40, 0)
	await wait_physics(2)
	check(p.global_position.distance_to(Vector3(5, 0.05, 5)) < 0.5, "should return to spawn")


func test_input_frame_from_untrusted_data_is_clamped() -> void:
	var f := InputFrame.from_dict({"m": Vector2(5, 5), "l": Vector2(100, -100), "j": "yes"})
	check(f.move.length() <= 1.0001, "move must be clamped to length 1")
	check(absf(f.look.x) <= PI + 1e-5 and absf(f.look.y) <= PI + 1e-5, "look must be clamped (Vector2 is 32-bit)")
	check(f.jump == false, "non-boolean jump must be rejected")
	var round_trip := InputFrame.from_dict(_frame(Vector2(0.5, -0.5), true, true, true).to_dict())
	check(round_trip.sprint and round_trip.crouch and round_trip.jump, "round trip keeps flags")
