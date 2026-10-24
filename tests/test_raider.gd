extends "res://tests/test_case.gd"
## Raider AI: wandering, sight (range, cone, walls), hearing, pathfinding,
## telegraphed melee, dodging, death and despawn.

const RAIDER := preload("res://scenes/enemies/raider.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0


func _raider(at: Vector3, facing_yaw_deg := 0.0) -> Raider:
	var r := RAIDER.instantiate() as Raider
	r.position = at
	r.rotation_degrees.y = facing_yaw_deg  # 0 = facing -Z
	add_child(r)
	return r


func _player(at: Vector3) -> PlayerController:
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = at
	add_child(p)
	return p


## Keeps the player idle (but simulated) for n physics ticks.
func _idle(p: PlayerController, ticks: int, fire := false) -> void:
	var f := InputFrame.new()
	f.fire = fire
	for i in ticks:
		await get_tree().physics_frame
		if is_instance_valid(p):
			p.simulate(f, DT)


func test_idles_then_wanders_near_home() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0))
	r.idle_time_min = 0.2
	r.idle_time_max = 0.4
	var states := []
	r.state_changed.connect(func(s: Raider.State) -> void: states.append(s))
	var farthest := 0.0
	for i in 480:
		await get_tree().physics_frame
		farthest = maxf(farthest, Vector2(r.global_position.x, r.global_position.z).length())
	check(states.has(Raider.State.WANDER), "wandered at some point")
	check(farthest > 1.0, "actually moved (%.1f m)" % farthest)
	check(farthest <= r.wander_radius + 1.5, "stayed near home (%.1f m)" % farthest)


func test_sees_player_in_front() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	var p := _player(Vector3(0, 0.05, -15))
	await _idle(p, 20)
	check(r.state == Raider.State.CHASE or r.state == Raider.State.ATTACK, "chasing a player 15 m in front (state %s)" % r.get_state_name())
	check(r.target == p, "target set")


func test_does_not_see_player_behind() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	r.idle_time_min = 10.0
	r.idle_time_max = 10.0
	var p := _player(Vector3(0, 0.05, 15))
	await _idle(p, 40)
	check(r.state != Raider.State.CHASE, "a player 15 m behind is not noticed")


func test_wall_blocks_sight() -> void:
	await make_nav_floor(Vector3(60, 1, 60), [[Vector3(10, 4, 0.5), Vector3(0, 2, -6)]])
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	r.idle_time_min = 10.0
	r.idle_time_max = 10.0
	var p := _player(Vector3(0, 0.05, -12))
	await _idle(p, 40)
	check(r.state != Raider.State.CHASE, "no chase when a wall is in the way")
	check(not r.can_see(p), "can_see() is false through the wall")


func test_out_of_sight_range() -> void:
	await make_nav_floor(Vector3(100, 1, 100))
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	r.idle_time_min = 10.0
	r.idle_time_max = 10.0
	var p := _player(Vector3(0, 0.05, -40))
	await _idle(p, 30)
	check(r.state != Raider.State.CHASE, "a player 40 m away is not noticed (range 30 m)")


func test_hears_gunshot_and_investigates() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	r.idle_time_min = 10.0
	r.idle_time_max = 10.0
	var p := _player(Vector3(0, 0.05, 20))   # behind the raider
	p.rotation_degrees.y = 90.0              # player shooting off to the side
	await _idle(p, 5)
	await _idle(p, 2, true)                  # one shot
	check(r.state == Raider.State.SEARCH or r.state == Raider.State.CHASE, "reacted to the gunshot (state %s)" % r.get_state_name())
	await _idle(p, 90)
	check(r.global_position.z > 3.0, "moved toward the shot (z=%.1f)" % r.global_position.z)


func test_noise_out_of_range_ignored() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	r.idle_time_min = 10.0
	r.idle_time_max = 10.0
	await wait_physics(2)
	r.hear_noise(Vector3(0, 0, 100), 60.0, null)
	check(r.state == Raider.State.IDLE, "a noise 100 m away (radius 60) is ignored")


func test_paths_around_wall_reaches_and_hits_player() -> void:
	# Long wall between raider and player with a gap at the east end
	await make_nav_floor(Vector3(60, 1, 60), [[Vector3(20, 4, 0.5), Vector3(-4, 2, -6)]])
	var r := _raider(Vector3(-4, 0.1, 0), 0.0)
	var p := _player(Vector3(-4, 0.05, -12))
	await wait_physics(2)
	r.alert_to(p)
	var hits := []
	p.health.damaged.connect(func(a: float, info: DamageInfo) -> void: hits.append([Time.get_ticks_msec(), a, info.source]))
	var went_around := false
	for i in 900:
		await _idle(p, 1)
		if r.global_position.x > 5.5:
			went_around = true
		if hits.size() >= 2:
			break
	check(went_around, "walked around the end of the wall")
	check(hits.size() >= 2, "reached the player and hit twice (hits=%d)" % hits.size())
	if hits.size() >= 2:
		check_near(hits[0][1], 20.0, 0.01, "20 damage per hit")
		check(hits[0][2] == r, "damage source is the raider")
		var gap: float = (hits[1][0] - hits[0][0]) / 1000.0
		check(gap >= r.attack_windup + r.attack_recovery - 0.1, "hits spaced by the attack cycle (%.2f s)" % gap)


func test_dodging_the_windup_avoids_damage() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	var p := _player(Vector3(0, 0.05, -1.4))
	await wait_physics(2)
	r.alert_to(p)
	for i in 30:
		await _idle(p, 1)
		if r.state == Raider.State.ATTACK:
			break
	check(r.state == Raider.State.ATTACK, "started an attack")
	# Step away during the wind-up
	p.global_position = Vector3(0, 0.05, -6)
	await _idle(p, int(r.attack_windup * 60.0) + 5)
	check_near(p.health.current_health, 100.0, 0.01, "no damage after dodging the wind-up")


func test_rifle_kills_raider_headshot_bonus_and_despawn() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, -10), 180.0)  # facing the shooter
	r.despawn_time = 0.5
	r.sight_range = 0.0                             # stays put for the test
	var rifle := (load("res://scenes/weapons/service_rifle.tscn") as PackedScene).instantiate() as HitscanWeapon
	rifle.definition = rifle.definition.duplicate()
	rifle.definition.base_spread = 0.0
	rifle.definition.spread_per_shot = 0.0
	rifle.spawn_impact_effects = false
	add_child(rifle)
	var kills := [0]
	r.killed.connect(func(_r: Raider) -> void: kills[0] += 1)
	await wait_physics(3)
	var head := Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))
	var body := Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
	rifle.tick(DT, true, false, head)
	check_near(r.health.current_health, 80.0 - 68.0, 0.5, "headshot deals 68 (x2)")
	await wait_physics(10)
	rifle.tick(1.0, false, false, body)   # let the fire-rate cooldown expire
	rifle.tick(DT, true, false, body)
	check(r.is_dead(), "dead after headshot + body shot")
	check(kills[0] == 1, "killed signal once")
	check(r.collision_layer == 0, "corpse no longer blocks shots or players")
	await get_tree().create_timer(0.7).timeout
	check(not is_instance_valid(r), "despawned after despawn_time")


func test_loses_interest_in_dead_player() -> void:
	await make_nav_floor()
	var r := _raider(Vector3(0, 0.1, 0), 0.0)
	var p := _player(Vector3(0, 0.05, -12))
	await _idle(p, 10)
	check(r.state == Raider.State.CHASE, "chasing")
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	await _idle(p, 15)
	check(r.state != Raider.State.CHASE and r.state != Raider.State.ATTACK, "stopped chasing a dead player (state %s)" % r.get_state_name())
	check(r.target == null, "target cleared")


func test_kill_message_names_raider() -> void:
	var r := RAIDER.instantiate() as Raider
	var info := DamageInfo.create(20.0, DamageInfo.Type.MELEE, r)
	check(GameMode.describe_cause(info) == "Killed by Raider", "cause: '%s'" % GameMode.describe_cause(info))
	r.free()
