extends "res://tests/test_case.gd"
## HitscanWeapon with the service rifle definition: fire rate, fire modes,
## ammo, reload, damage, hit zones, falloff, spread and recoil.

const RIFLE := preload("res://scenes/weapons/service_rifle.tscn")
const DT := 1.0 / 60.0

var _shots := 0


## A rifle at the origin aiming down -Z, with deterministic (zero) spread.
func _rifle(spread := false) -> HitscanWeapon:
	var w := RIFLE.instantiate() as HitscanWeapon
	w.definition = w.definition.duplicate()
	if not spread:
		w.definition.base_spread = 0.0
		w.definition.spread_per_shot = 0.0
	w.spawn_impact_effects = false
	add_child(w)
	w.fired.connect(func(_o: Vector3, _d: Vector3) -> void: _shots += 1)
	return w


func _aim() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0))


## Holds the trigger state for n ticks (inside physics frames).
func _hold(w: HitscanWeapon, ticks: int, trigger := true, reload := false) -> void:
	for i in ticks:
		await get_tree().physics_frame
		w.tick(DT, trigger, reload and i == 0, _aim())


## A target at `distance` m down -Z with torso (x1) and head (x2) shapes.
func _target(distance: float) -> HealthComponent:
	var root := Node3D.new()
	add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.NPCS
	body.position = Vector3(0, 0, -distance)
	root.add_child(body)
	var torso := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(0.6, 0.8, 0.1)
	torso.shape = tb
	torso.position = Vector3(0, 1.5, 0)   # aim height
	torso.set_meta("damage_multiplier", 1.0)
	body.add_child(torso)
	var head := CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = 0.15
	head.shape = hs
	head.position = Vector3(1.0, 1.5, 0)  # off to the side; aim moved to hit it
	head.set_meta("damage_multiplier", 2.0)
	body.add_child(head)
	var h := HealthComponent.new()
	h.max_health = 1000.0
	root.add_child(h)
	return h


func test_full_auto_rate() -> void:
	var w := _rifle()
	await wait_physics(2)
	_shots = 0
	await _hold(w, 60)
	# 650 rpm -> first shot at t=0 plus one every 0.0923 s within 1 s = 11
	check_between(_shots, 10, 11, "shots in one second at 650 rpm")
	check(w.ammo_in_magazine == 30 - _shots, "one round used per shot")


func test_semi_auto_needs_release() -> void:
	var w := _rifle()
	w.definition.fire_mode = WeaponDefinition.FireMode.SEMI_AUTO
	await wait_physics(2)
	_shots = 0
	await _hold(w, 60)
	check(_shots == 1, "holding the trigger fires once in semi-auto (got %d)" % _shots)
	for i in 4:
		await _hold(w, 10, false)
		await _hold(w, 2, true)
	check(_shots == 5, "each new pull fires once (got %d)" % _shots)


func test_empty_magazine_dry_fires_and_auto_reloads() -> void:
	var w := _rifle()
	w.ammo_in_magazine = 0
	var dry := [0]
	w.dry_fired.connect(func() -> void: dry[0] += 1)
	await _hold(w, 1)
	check(dry[0] == 1, "dry fire on empty pull")
	check(w.is_reloading, "auto reload started")
	check(_shots == 0, "no shot fired")


func test_reload_timing_and_ammo_transfer() -> void:
	var w := _rifle()
	await _hold(w, 6)  # fire a few
	var fired := 30 - w.ammo_in_magazine
	await _hold(w, 1, false, true)
	check(w.is_reloading, "reload started")
	await _hold(w, int(w.definition.reload_time * 60.0) - 5, false)
	check(w.is_reloading, "still reloading just before reload_time")
	await _hold(w, 10, false)
	check(not w.is_reloading, "reload finished")
	check(w.ammo_in_magazine == 30, "magazine full")
	check(w.reserve_ammo == w.definition.starting_reserve - fired, "reserve reduced by the rounds loaded")


func test_cannot_fire_while_reloading() -> void:
	var w := _rifle()
	await _hold(w, 3)
	await _hold(w, 1, false, true)
	_shots = 0
	await _hold(w, 30)
	check(_shots == 0, "no shots during reload")


func test_reload_rules() -> void:
	var w := _rifle()
	check(not w.start_reload(), "no reload when magazine is full")
	w.ammo_in_magazine = 5
	w.reserve_ammo = 0
	check(not w.start_reload(), "no reload with empty reserve")
	w.reserve_ammo = 10
	check(w.start_reload(), "reload when partially empty with reserve")
	await _hold(w, 160, false)
	check(w.ammo_in_magazine == 15 and w.reserve_ammo == 0, "only available reserve is loaded")


func test_damage_and_headshot_multiplier() -> void:
	var w := _rifle()
	var h := _target(10.0)
	var confirms := []
	w.hit_confirmed.connect(func(_t: Node, dmg: float, _k: bool, zone: float) -> void: confirms.append([dmg, zone]))
	await wait_physics(2)
	await get_tree().physics_frame
	w.tick(DT, true, false, _aim())
	check_near(h.current_health, 1000.0 - 34.0, 0.01, "torso hit deals base damage")
	# Aim at the head (1 m to the right)
	await _hold(w, 10, false)
	await get_tree().physics_frame
	w.tick(DT, true, false, Transform3D(Basis.IDENTITY, Vector3(1.0, 1.5, 0)))
	check_near(h.current_health, 1000.0 - 34.0 - 68.0, 0.01, "headshot deals double")
	check(confirms.size() == 2 and confirms[1][1] == 2.0, "hit_confirmed reports the zone multiplier")


func test_damage_falloff_at_range() -> void:
	var w := _rifle()
	var h := _target(250.0)
	await wait_physics(2)
	await get_tree().physics_frame
	w.tick(DT, true, false, _aim())
	check_near(1000.0 - h.current_health, 34.0 * 0.6, 0.05, "minimum damage beyond falloff_end")
	check_near(w.definition.damage_at_distance(125.0), 34.0 * 0.8, 0.01, "half-way through falloff")


func test_shooter_is_excluded() -> void:
	var w := _rifle()
	# A body around the aim origin, standing in for the shooter
	var shooter := StaticBody3D.new()
	shooter.collision_layer = PhysicsLayers.PLAYER
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.5
	cs.shape = s
	shooter.add_child(cs)
	shooter.position = Vector3(0, 1.5, 0)
	add_child(shooter)
	var sh := HealthComponent.new()
	shooter.add_child(sh)
	var h := _target(5.0)
	await wait_physics(2)
	await get_tree().physics_frame
	w.tick(DT, true, false, _aim(), shooter)
	check_near(sh.current_health, 100.0, 0.001, "shooter not hurt by own shot")
	check(h.current_health < 1000.0, "target behind the shooter's own collider is hit")


func test_spread_bloom_grows_and_recovers() -> void:
	var w := _rifle(true)
	var base := w.get_current_spread_degrees()
	await _hold(w, 30)
	check(w.get_current_spread_degrees() > base + 1.0, "bloom grows while firing")
	await _hold(w, 60, false)
	check_near(w.get_current_spread_degrees(), base, 0.01, "bloom recovers after a second")


func test_spread_stays_inside_cone() -> void:
	var w := _rifle(true)
	w.set_rng_seed(1234)
	var max_angle := [0.0]
	w.fired.connect(func(_o: Vector3, d: Vector3) -> void: max_angle[0] = maxf(max_angle[0], rad_to_deg(d.angle_to(Vector3.FORWARD))))
	for i in 3:
		await _hold(w, 40)
		await _hold(w, 1, false, true)
		await _hold(w, 150, false)
	var limit := (w.definition.base_spread + w.definition.max_bloom)
	check(max_angle[0] <= limit + 0.01, "every shot within the max cone (%.2f° <= %.2f°)" % [max_angle[0], limit])
	check(max_angle[0] > 0.1, "spread actually deviates shots")


func test_recoil_returned_per_shot() -> void:
	var w := _rifle()
	await get_tree().physics_frame
	var recoil := w.tick(DT, true, false, _aim())
	check_near(rad_to_deg(recoil.y), w.definition.recoil_pitch, 0.001, "pitch recoil per shot")
	check(absf(rad_to_deg(recoil.x)) <= w.definition.recoil_yaw + 0.001, "yaw recoil within limits")
	await get_tree().physics_frame
	var none := w.tick(DT, false, false, _aim())
	check(none == Vector2.ZERO, "no recoil without a shot")
