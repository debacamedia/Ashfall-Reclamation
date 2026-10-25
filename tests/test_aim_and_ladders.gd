extends "res://tests/test_case.gd"
## Aiming down sights (zoom, spread, recoil, speed, sensitivity, sight
## alignment) and ladders (grab, climb, step off the top, climb down from the
## top, jump off, hands busy).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const LADDER_SCENE := preload("res://scenes/world/structures/ladder.tscn")
const DT := 1.0 / 60.0


func _player(at := Vector3(0, 0.05, 0), yaw_deg := 0.0) -> PlayerController:
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = at
	p.rotation_degrees.y = yaw_deg
	add_child(p)
	return p


func _frame(move := Vector2.ZERO, aim := false) -> InputFrame:
	var f := InputFrame.new()
	f.move = move
	f.aim = aim
	return f


func _run(p: PlayerController, f: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


## Floor, a 4 m high block (its top is a platform from z = -4 to 0) and a
## 4 m ladder on its +Z face. The player starts 2 m in front, facing it.
func _ladder_rig(player_at := Vector3(0, 0.05, 2.0), yaw_deg := 0.0) -> Array:
	make_static_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	make_static_box(Vector3(4, 4, 4), Vector3(0, 2, -2))
	var ladder := LADDER_SCENE.instantiate() as Ladder
	ladder.height = 4.0
	ladder.position = Vector3(0, 0, 0.03)
	add_child(ladder)
	var p := _player(player_at, yaw_deg)
	await wait_physics(5)
	return [p, ladder]


# ---------------------------------------------------------------- aiming

func test_aim_raises_sights_and_zooms() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	var base_fov := p.camera.fov
	var changes := []
	p.aim_changed.connect(func(a: bool) -> void: changes.append(a))
	await _run(p, _frame(Vector2.ZERO, true), 6)
	check(p.aim_amount > 0.2 and p.aim_amount < 0.8, "sights come up over time (%.2f after 0.1 s)" % p.aim_amount)
	await _run(p, _frame(Vector2.ZERO, true), 12)
	check_near(p.aim_amount, 1.0, 0.001, "fully aimed after ads_time (0.2 s)")
	check(p.is_aiming, "is_aiming")
	check_near(p.camera.fov, base_fov / p.weapon.definition.ads_zoom, 0.05, "FOV zoomed by ads_zoom")
	await _run(p, _frame(), 15)
	check_near(p.aim_amount, 0.0, 0.001, "lowered again on release")
	check_near(p.camera.fov, base_fov, 0.01, "FOV restored")
	check(changes == [true, false], "aim_changed on and off: %s" % [changes])


func test_aim_tightens_spread_and_recoil() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	p.weapon.set_rng_seed(7)
	await wait_physics(3)
	await _run(p, _frame(), 30)  # settle onto the floor
	var hip_spread := p.weapon.get_current_spread_degrees()
	var fire := _frame()
	fire.fire = true
	var pitch := p.head.rotation.x
	await _run(p, fire, 1)
	var hip_kick := rad_to_deg(p.head.rotation.x - pitch)
	await _run(p, _frame(), 60)  # bloom recovers
	await _run(p, _frame(Vector2.ZERO, true), 15)
	var ads_spread := p.weapon.get_current_spread_degrees()
	var def := p.weapon.definition
	check_near(ads_spread / hip_spread, def.ads_spread_multiplier, 0.01, "spread × %.2f while aiming (%.3f° → %.3f°)" % [def.ads_spread_multiplier, hip_spread, ads_spread])
	fire.aim = true
	pitch = p.head.rotation.x
	await _run(p, fire, 1)
	var ads_kick := rad_to_deg(p.head.rotation.x - pitch)
	check_near(hip_kick, def.recoil_pitch, 0.01, "hip recoil %.3f°" % hip_kick)
	check_near(ads_kick, def.recoil_pitch * def.ads_recoil_multiplier, 0.01, "aimed recoil %.3f°" % ads_kick)


func test_aim_slows_movement_and_blocks_sprint() -> void:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	var f := _frame(Vector2(0, -1), true)
	f.sprint = true
	await _run(p, f, 90)
	var expected := p.walk_speed * p.weapon.definition.ads_move_multiplier
	check_near(p.get_horizontal_speed(), expected, 0.1, "aimed walk %.2f m/s (sprint ignored)" % p.get_horizontal_speed())
	check(p.movement_state != PlayerController.MovementState.SPRINTING, "not sprinting while aiming")


func test_aim_slows_mouse_look() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	await _run(p, _frame(Vector2.ZERO, true), 15)
	var yaw := p.rotation.y
	var f := _frame(Vector2.ZERO, true)
	f.look = Vector2(0.14, 0)
	await _run(p, f, 1)
	check_near(yaw - p.rotation.y, 0.14 / p.weapon.definition.ads_zoom, 0.0005, "look scaled by 1/zoom")


func test_cannot_aim_while_reloading_or_healing() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	p.weapon.ammo_in_magazine = 5
	var f := _frame(Vector2.ZERO, true)
	f.reload = true
	await _run(p, f, 1)
	await _run(p, _frame(Vector2.ZERO, true), 15)
	check(p.weapon.is_reloading and p.aim_amount == 0.0, "no aiming during a reload")
	await _run(p, _frame(Vector2.ZERO, true), 150)
	check(not p.weapon.is_reloading and p.aim_amount > 0.99, "aims once the reload finishes")
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	check(p.request_use_item(p.inventory.find_best_medical()), "heal started")
	await _run(p, _frame(Vector2.ZERO, true), 15)
	check(p.aim_amount == 0.0, "no aiming while using a medkit")


func _settle() -> void:
	for i in 90:  # let the visual pose settle (it eases in _process)
		await get_tree().process_frame
		await get_tree().physics_frame


func test_sight_lines_up_with_screen_centre() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	# Iron sights (no optic fitted): rear notch and front post on the centre line
	await _run(p, _frame(Vector2.ZERO, true), 15)
	await _settle()
	var to_cam := p.camera.global_transform.affine_inverse()
	var rear := to_cam * (p.weapon.get_node("%SightAnchor") as Node3D).global_position
	var post := to_cam * (p.weapon.get_node("%IronSights/FrontPost") as Node3D).global_position
	check(absf(rear.x) < 0.0015 and absf(rear.y) < 0.0015, "irons: rear sight on the centre line (%s)" % rear)
	check(absf(post.x) < 0.002 and absf(post.y) < 0.012, "irons: front post on the centre line (%s)" % post)
	# Fit a red dot: the irons fold away and the dot sits on the centre line
	await _run(p, _frame(), 15)
	p.weapon.fit_attachment(ItemDatabase.get_attachment(&"red_dot"))
	check(not (p.weapon.get_node("%IronSights") as Node3D).visible, "irons hidden under the optic")
	await _run(p, _frame(Vector2.ZERO, true), 15)
	await _settle()
	to_cam = p.camera.global_transform.affine_inverse()
	var optic := p.weapon.get_node("%OpticMount").get_child(0)
	var dot := to_cam * (optic.get_node("Dot") as Node3D).global_position
	var anchor := to_cam * (optic.get_node("Sight") as Node3D).global_position
	check(absf(dot.x) < 0.0015 and absf(dot.y) < 0.0015, "red dot on the centre line (%s)" % dot)
	check(absf(anchor.x) < 0.0015 and absf(anchor.y) < 0.0015, "rear of sight on the centre line (%s)" % anchor)
	check_near(-anchor.z, p.weapon.definition.ads_eye_distance, 0.005, "sight %.3f m from the eye" % -anchor.z)
	var barrel := (to_cam.basis * -(p.weapon.get_node("Model") as Node3D).global_basis.z).normalized()
	check(barrel.dot(Vector3.FORWARD) > 0.9995, "barrel parallel to the view")
	# Hip pose is different (sights are not centred)
	await _run(p, _frame(), 15)
	await _settle()
	var hip := to_cam * (optic.get_node("Dot") as Node3D).global_position
	check(absf(hip.x) > 0.03, "back to the hip afterwards")


func test_untrusted_aim_flag() -> void:
	check(InputFrame.from_dict({"a": "yes"}).aim == false, "non-boolean aim rejected")
	var f := _frame(Vector2.ZERO, true)
	check(InputFrame.from_dict(f.to_dict()).aim, "aim survives a round trip")


# ---------------------------------------------------------------- toggle aim

func test_toggle_aim_is_default() -> void:
	var p := _player()
	await wait_physics(2)
	var input := p.player_input
	check(input.aim_toggle, "toggle aim on by default (Magic Mouse friendly)")
	check(input.update_aim(true, false), "first click raises the sights")
	check(input.update_aim(true, false), "still up while the button is held")
	check(input.update_aim(false, false), "stays up after letting go")
	check(input.update_aim(false, false), "and keeps staying up")
	check(not input.update_aim(true, false), "second click lowers them")
	check(not input.update_aim(false, false), "stays down")


func test_toggle_aim_lets_you_fire_with_one_button() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	var input := p.player_input
	# Click aim once, release, then hold fire only (what a Magic Mouse can do)
	var f := _frame()
	f.aim = input.update_aim(true, false)
	await _run(p, f, 1)
	var ammo := p.weapon.ammo_in_magazine
	for i in 30:
		f = _frame()
		f.aim = input.update_aim(false, false)
		f.fire = true
		await _run(p, f, 1)
	check(p.aim_amount > 0.99, "still aimed while firing")
	check(p.weapon.ammo_in_magazine < ammo - 3, "fired while aimed (%d rounds)" % (ammo - p.weapon.ammo_in_magazine))


func test_sprint_ladder_medkit_and_death_drop_toggled_aim() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var input := p.player_input
	input.update_aim(true, false)
	input.update_aim(false, false)
	check(not input.update_aim(false, true), "sprinting lowers the sights")
	check(not input.update_aim(false, false), "and they stay down after the sprint")
	input.update_aim(true, false)
	input.update_aim(false, false)
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	check(p.ladder != null and not input.is_aiming_toggled(), "grabbing a ladder lowers the sights")
	input.update_aim(true, false)
	input.update_aim(false, false)
	p.health.apply_damage(DamageInfo.create(30.0, DamageInfo.Type.FALL))
	var jump := _frame()
	jump.jump = true
	await _run(p, jump, 1)
	await _run(p, _frame(), 120)
	check(p.request_use_item(p.inventory.find_best_medical()) and not input.is_aiming_toggled(), "using a medkit lowers the sights")
	input.update_aim(true, false)
	input.update_aim(false, false)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	check(not input.is_aiming_toggled(), "dying lowers the sights")


func test_reload_pauses_toggled_aim_then_resumes() -> void:
	make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := _player()
	await wait_physics(3)
	var input := p.player_input
	input.update_aim(true, false)
	p.weapon.ammo_in_magazine = 3
	var f := _frame(Vector2.ZERO, input.update_aim(false, false))
	f.reload = true
	await _run(p, f, 1)
	await _run(p, _frame(Vector2.ZERO, input.update_aim(false, false)), 20)
	check(p.aim_amount == 0.0, "sights down during the reload")
	await _run(p, _frame(Vector2.ZERO, input.update_aim(false, false)), 150)
	check(p.aim_amount > 0.99, "back up after the reload without clicking again")


func test_hold_aim_option() -> void:
	var p := _player()
	await wait_physics(2)
	var input := p.player_input
	input.aim_toggle = false
	check(input.update_aim(true, false), "held: aiming")
	check(not input.update_aim(false, false), "released: not aiming")
	check(not input.update_aim(true, true), "no aiming while sprinting")


# ---------------------------------------------------------------- ladders

func test_ladder_reach() -> void:
	var rig: Array = await _ladder_rig()
	var l: Ladder = rig[1]
	check(l.is_in_reach(Vector3(0, 0, 0.5)), "in front at the bottom")
	check(not l.is_in_reach(Vector3(0, 0, 1.5)), "too far out")
	check(not l.is_in_reach(Vector3(1.5, 0, 0.5)), "too far to the side")
	check(l.is_in_reach(Vector3(0, 4.0, -0.6)), "standing on the top, just behind it")
	check(not l.is_in_reach(Vector3(0, 2.0, -0.6)), "not through the wall halfway up")
	check_near(l.get_top_y(), 4.0, 0.001, "top height")
	check(l.get_outward().is_equal_approx(Vector3.BACK), "outward is +Z")
	check(l.get_child_count(true) > 0, "rails and rungs generated")


func test_walk_into_ladder_climb_and_step_off_top() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var grabbed := []
	var steps := [0]
	p.ladder_grabbed.connect(func(l: Ladder) -> void: grabbed.append(l))
	p.ladder_step.connect(func() -> void: steps[0] += 1)
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	check(p.ladder == rig[1] and grabbed.size() == 1, "walking into the ladder grabs it")
	check(p.movement_state == PlayerController.MovementState.CLIMBING, "state CLIMBING")
	var y0 := p.global_position.y
	await _run(p, w, 60)
	check_between(p.global_position.y - y0, 2.2, 2.7, "climbs ~2.6 m/s (%.2f m in 1 s)" % (p.global_position.y - y0))
	check(absf(p.global_position.z - 0.48) < 0.05, "held on the climbing line (z %.2f)" % p.global_position.z)
	for i in 120:
		await _run(p, w, 1)
		if p.ladder == null and p.is_on_floor():
			break
	await _run(p, _frame(), 10)  # let go of W once standing on top
	check(p.ladder == null, "let go at the top")
	check(p.is_on_floor() and p.global_position.y > 3.95 and p.global_position.y < 4.1, "standing on the platform (y %.2f)" % p.global_position.y)
	check(p.global_position.z < -0.2, "stepped forward onto it (z %.2f)" % p.global_position.z)
	check(steps[0] >= 6, "rung sounds while climbing (%d)" % steps[0])
	check_near(p.health.current_health, 100.0, 0.01, "no damage")


func test_climb_down_from_the_top() -> void:
	# Start on the platform, facing out over the edge where the ladder is
	var rig: Array = await _ladder_rig(Vector3(0, 4.05, -0.8), 180.0)
	var p: PlayerController = rig[0]
	var w := _frame(Vector2(0, -1))
	for i in 90:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	check(p.ladder != null, "walking off the top towards the ladder grabs it")
	await _run(p, w, 60)
	check(p.ladder != null and p.global_position.y < 3.2, "W climbs down with your back to the ladder (y %.2f)" % p.global_position.y)
	await _run(p, w, 120)
	check(p.ladder == null and p.is_on_floor() and p.global_position.y < 0.2, "let go at the bottom (y %.2f)" % p.global_position.y)
	check_near(p.health.current_health, 100.0, 0.01, "no fall damage")


func test_hang_still_and_look_down_to_descend() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	await _run(p, w, 60)
	var y := p.global_position.y
	await _run(p, _frame(), 60)
	check_near(p.global_position.y, y, 0.01, "no input: hangs in place (no gravity)")
	p.head.rotation.x = deg_to_rad(-60.0)
	await _run(p, w, 30)
	check(p.global_position.y < y - 1.0, "W while looking down climbs down")
	var s := _frame(Vector2(0, 1))
	var y2 := p.global_position.y
	await _run(p, s, 20)
	check(p.global_position.y > y2 + 0.5, "S while looking down climbs up")


func test_jump_off_ladder() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	await _run(p, w, 45)
	var jump := _frame()
	jump.jump = true
	await _run(p, jump, 1)
	check(p.ladder == null, "jump lets go")
	check(p.velocity.z > 2.0, "pushed away from the ladder (vz %.2f)" % p.velocity.z)
	await _run(p, _frame(), 120)
	check(p.is_on_floor() and p.global_position.z > 1.0, "landed in front of it")
	check(p.ladder == null, "didn't re-grab")


func test_hands_busy_on_ladder() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	var ammo := p.weapon.ammo_in_magazine
	var f := _frame(Vector2.ZERO, true)
	f.fire = true
	await _run(p, f, 20)
	check(p.weapon.ammo_in_magazine == ammo, "can't fire on a ladder")
	check(p.aim_amount == 0.0, "can't aim on a ladder")
	check(p.weapon.lowered, "rifle lowered")
	p.health.apply_damage(DamageInfo.create(30.0, DamageInfo.Type.FALL))
	check(not p.request_use_item(p.inventory.find_best_medical()), "can't use a medkit on a ladder")


func test_death_lets_go_of_ladder() -> void:
	var rig: Array = await _ladder_rig()
	var p: PlayerController = rig[0]
	var w := _frame(Vector2(0, -1))
	for i in 120:
		await _run(p, w, 1)
		if p.ladder != null:
			break
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	check(p.ladder == null, "dead players let go")
	await _run(p, _frame(), 60)
	check(p.global_position.y < 0.3, "and fall")
