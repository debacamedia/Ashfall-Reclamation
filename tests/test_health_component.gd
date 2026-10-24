extends "res://tests/test_case.gd"
## HealthComponent and DamageInfo.


func _make(max_health := 100.0) -> HealthComponent:
	var h := HealthComponent.new()
	h.max_health = max_health
	add_child(h)
	return h


func _dmg(amount: float) -> DamageInfo:
	return DamageInfo.create(amount, DamageInfo.Type.BALLISTIC)


func test_starts_full() -> void:
	var h := _make(80.0)
	check_near(h.current_health, 80.0, 0.001, "starts at max health")
	check(not h.is_dead(), "starts alive")


func test_damage_reduces_and_reports() -> void:
	var h := _make()
	var events := []
	h.damaged.connect(func(a: float, _i: DamageInfo) -> void: events.append(a))
	var dealt := h.apply_damage(_dmg(30.0))
	check_near(dealt, 30.0, 0.001, "returns damage dealt")
	check_near(h.current_health, 70.0, 0.001, "health reduced")
	check(events == [30.0], "damaged signal carries the amount")


func test_overkill_clamps_and_dies_once() -> void:
	var h := _make()
	var deaths := [0]
	h.died.connect(func(_i: DamageInfo) -> void: deaths[0] += 1)
	var dealt := h.apply_damage(_dmg(250.0))
	check_near(dealt, 100.0, 0.001, "only remaining health counts as dealt")
	check_near(h.current_health, 0.0, 0.001, "health stops at zero")
	check(h.is_dead(), "is dead")
	h.apply_damage(_dmg(10.0))
	check(deaths[0] == 1, "died fires exactly once")


func test_ignores_invalid_damage() -> void:
	var h := _make()
	check_near(h.apply_damage(_dmg(0.0)), 0.0, 0.001, "zero damage ignored")
	check_near(h.apply_damage(_dmg(-20.0)), 0.0, 0.001, "negative damage ignored (no healing exploit)")
	check_near(h.apply_damage(null), 0.0, 0.001, "null ignored")
	h.invulnerable = true
	check_near(h.apply_damage(_dmg(50.0)), 0.0, 0.001, "invulnerable ignores damage")
	check_near(h.current_health, 100.0, 0.001, "still full")


func test_heal_clamps_and_not_when_dead() -> void:
	var h := _make()
	h.apply_damage(_dmg(40.0))
	check_near(h.heal(100.0), 40.0, 0.001, "heal capped at max")
	check_near(h.current_health, 100.0, 0.001, "back to full")
	h.apply_damage(_dmg(100.0))
	check_near(h.heal(50.0), 0.0, 0.001, "cannot heal the dead")


func test_revive() -> void:
	var h := _make()
	h.apply_damage(_dmg(100.0))
	h.revive(0.5)
	check(not h.is_dead(), "alive after revive")
	check_near(h.current_health, 50.0, 0.001, "revived at 50%")


func test_find_on_walks_up_parents() -> void:
	var owner_node := Node3D.new()
	add_child(owner_node)
	var h := HealthComponent.new()
	owner_node.add_child(h)
	var a := Node3D.new()
	owner_node.add_child(a)
	var b := StaticBody3D.new()
	a.add_child(b)
	check(HealthComponent.find_on(b) == h, "found from a nested collider")
	var lone := Node3D.new()
	add_child(lone)
	check(HealthComponent.find_on(lone) == null, "null when there is no health nearby")
