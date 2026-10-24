extends "res://tests/test_case.gd"
## TargetDummy: damage numbers, falling when killed, resetting.

const DUMMY := preload("res://scenes/world/range/target_dummy.tscn")


func _dummy() -> TargetDummy:
	var d := DUMMY.instantiate() as TargetDummy
	d.reset_delay = 0.5
	add_child(d)
	return d


func _hit(d: TargetDummy, amount: float, zone := 1.0) -> void:
	var info := DamageInfo.create(amount, DamageInfo.Type.BALLISTIC)
	info.zone_multiplier = zone
	d.health.apply_damage(info)


func test_shows_damage_number() -> void:
	var d := _dummy()
	await wait_physics(2)
	_hit(d, 34.0)
	check(d.damage_label.visible, "damage label shown")
	check(d.damage_label.text == "34", "label shows damage (got '%s')" % d.damage_label.text)
	_hit(d, 68.0, 2.0)
	check(d.damage_label.text.ends_with("!"), "headshots are marked")


func test_falls_when_killed_then_resets() -> void:
	var d := _dummy()
	var resets := [0]
	d.reset_finished.connect(func() -> void: resets[0] += 1)
	await wait_physics(2)
	_hit(d, 150.0)
	check(d.health.is_dead(), "dead after lethal damage")
	await wait_physics(30)
	check(d.hinge.rotation_degrees.x < -80.0, "fell over (x=%.1f)" % d.hinge.rotation_degrees.x)
	await wait_physics(90)
	check(resets[0] == 1, "reset after the delay")
	check(not d.health.is_dead(), "alive again")
	check_near(d.health.current_health, d.health.max_health, 0.01, "health restored")
	check(absf(d.hinge.rotation_degrees.x) < 1.0, "standing again")


func test_has_head_and_torso_zones() -> void:
	var d := _dummy()
	var body := d.get_node("Hinge/TargetBody")
	check(float(body.get_node("HeadShape").get_meta("damage_multiplier")) == 2.0, "head x2")
	check(float(body.get_node("TorsoShape").get_meta("damage_multiplier")) == 1.0, "torso x1")
	check(float(d.get_node("Stand/StandShape").get_meta("damage_multiplier")) == 0.0, "stand takes no damage")
