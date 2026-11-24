extends "res://tests/test_case.gd"
## Increment 30: the developer's fast-forward (F4 in a debug build).


class StepProbe extends Node:
	var deltas: Array[float] = []

	func _physics_process(delta: float) -> void:
		deltas.append(delta)


func test_fast_forward() -> void:
	check(GameSpeed.allowed() == OS.is_debug_build(), "only in a debug build (Run from the editor)")
	var base := GameSpeed.base_ticks()
	check(base == 60, "the project runs physics at 60 a second")
	GameSpeed.set_speed(2.0)
	check(is_equal_approx(Engine.time_scale, 2.0) and Engine.physics_ticks_per_second == 120, "2×: time twice as fast, twice the physics ticks")
	# Each physics step is still 1/60 s of game time, so everything behaves
	# as at 1×
	var probe := StepProbe.new()
	add_child(probe)
	await wait_physics(10)
	var steady := probe.deltas.slice(2)
	check(steady.all(func(d: float) -> bool: return absf(d - 1.0 / 60.0) < 0.0005), "each step still 1/60 s of game time (%s)" % [steady.slice(0, 3)])
	probe.queue_free()
	# F4 steps through 1×, 2×, 4× and back
	GameSpeed.set_speed(1.0)
	var seen: Array[float] = []
	for i in 3:
		seen.append(GameSpeed.cycle())
	check(seen == [2.0, 4.0, 1.0], "F4: 2×, 4×, back to 1× (%s)" % [seen])
	check(Engine.physics_ticks_per_second == base and is_equal_approx(Engine.time_scale, 1.0), "back to normal")
	GameSpeed.set_speed(1.0)


func test_the_hud_badge() -> void:
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	await wait_physics(1)
	var f4 := InputEventKey.new()
	f4.physical_keycode = KEY_F4
	f4.pressed = true
	hud._unhandled_input(f4)
	var badge := hud.get_node_or_null("SpeedLabel") as Label
	if OS.is_debug_build():
		check(is_equal_approx(GameSpeed.current(), 2.0) and badge != null and badge.visible and badge.text.contains("2×"), "F4: 2×, and a badge says so")
		hud._unhandled_input(f4)
		hud._unhandled_input(f4)
		check(is_equal_approx(GameSpeed.current(), 1.0) and not badge.visible, "back to 1×: the badge goes")
	else:
		check(is_equal_approx(GameSpeed.current(), 1.0) and badge == null, "a release build ignores F4")
	GameSpeed.set_speed(1.0)
	hud.queue_free()
