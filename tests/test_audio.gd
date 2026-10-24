extends "res://tests/test_case.gd"
## Audio: assets import correctly, buses exist, and game events trigger the
## right sound players. (Runs with the dummy audio driver: we check that
## sounds are started, not what they sound like.)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0


func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


func _drive(p: PlayerController, f: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func test_all_sounds_import() -> void:
	var dir := DirAccess.open("res://assets/audio")
	var count := 0
	for f in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		var stream := load("res://assets/audio/" + f) as AudioStreamWAV
		check(stream != null and stream.get_length() > 0.04, "%s imports with sound" % f)
		count += 1
	check(count >= 40, "at least 40 sound files (found %d)" % count)


func test_loops_loop() -> void:
	for f in ["fire_loop", "wind_loop", "heartbeat"]:
		var s := load("res://assets/audio/%s.wav" % f) as AudioStreamWAV
		check(s.loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s is imported as a loop" % f)
	var shot := load("res://assets/audio/rifle_shot_1.wav") as AudioStreamWAV
	check(shot.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shots don't loop")


func test_buses() -> void:
	for bus in ["SFX", "UI", "Ambience"]:
		check(AudioServer.get_bus_index(bus) > 0, "bus %s exists" % bus)


func test_shot_reload_and_dry_fire_sounds() -> void:
	var p := _player()
	await _drive(p, InputFrame.new(), 3)
	var shot := p.weapon.get_node("%ShotSound") as AudioStreamPlayer3D
	var reload := p.weapon.get_node("%ReloadSound") as AudioStreamPlayer3D
	var dry := p.weapon.get_node("%DryFireSound") as AudioStreamPlayer3D
	var f := InputFrame.new()
	f.fire = true
	await _drive(p, f, 1)
	check(shot.playing, "shooting plays the shot sound")
	f.fire = false
	f.reload = true
	await _drive(p, f, 1)
	check(reload.playing, "reloading plays the reload sound")
	p.weapon.cancel_reload()
	p.weapon.ammo_in_magazine = 0
	p.weapon.reserve_ammo = 0
	f.reload = false
	f.fire = true
	await _drive(p, f, 2)
	check(dry.playing, "empty trigger pull plays the dry-fire click")


func test_footsteps_follow_walking_distance() -> void:
	var p := _player()
	var audio := p.get_node("Audio") as PlayerAudio
	await _drive(p, InputFrame.new(), 5)
	var f := InputFrame.new()
	f.move = Vector2(0, -1)
	await _drive(p, f, 120)  # 2 s of walking ≈ 8.5 m
	check_between(audio.footstep_count, 8, 15, "footsteps over ~8.5 m of walking")
	var before := audio.footstep_count
	await _drive(p, InputFrame.new(), 60)
	check(audio.footstep_count - before <= 1, "no footsteps standing still")


func test_hurt_heartbeat_and_death_sounds() -> void:
	var p := _player()
	await _drive(p, InputFrame.new(), 3)
	var hurt := p.get_node("Audio/Hurt") as AudioStreamPlayer
	var heart := p.get_node("Audio/Heartbeat") as AudioStreamPlayer
	var death := p.get_node("Audio/Death") as AudioStreamPlayer
	p.health.apply_damage(DamageInfo.create(75.0, DamageInfo.Type.BALLISTIC))
	await _drive(p, InputFrame.new(), 2)
	check(hurt.playing, "taking damage plays the hurt sound")
	check(heart.playing, "heartbeat at 25% health")
	p.health.heal(60.0)
	await _drive(p, InputFrame.new(), 2)
	check(not heart.playing, "heartbeat stops after healing")
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	await _drive(p, InputFrame.new(), 2)
	check(death.playing, "dying plays the death sting")


func test_raider_alert_and_dummy_ping() -> void:
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	add_child(r)
	var d := (load("res://scenes/world/range/target_dummy.tscn") as PackedScene).instantiate() as TargetDummy
	d.position = Vector3(5, 0, 0)
	add_child(d)
	await wait_physics(2)
	r.hear_noise(r.global_position + Vector3(5, 0, 0), 60.0, null)
	check((r.get_node("%AlertSound") as AudioStreamPlayer3D).playing, "an alerted raider shouts")
	d.health.apply_damage(DamageInfo.create(10.0, DamageInfo.Type.BALLISTIC))
	check((d.get_node("%PingSound") as AudioStreamPlayer3D).playing, "hitting a range target pings")
	r.health.apply_damage(DamageInfo.create(10.0, DamageInfo.Type.BALLISTIC))
	check((r.get_node("%HitSound") as AudioStreamPlayer3D).playing, "hitting a raider plays a flesh hit")


func test_level_ambience_and_fire() -> void:
	var level := (load("res://levels/outpost_17/outpost_17.tscn") as PackedScene).instantiate()
	(level.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	add_child(level)
	await wait_physics(5)
	check((level.get_node("Ambience") as AudioStreamPlayer).playing, "wind ambience plays")
	check((level.get_node("Props/BurningBarrelYard/FireSound") as AudioStreamPlayer3D).playing, "burning barrel crackles")
