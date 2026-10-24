class_name HitscanWeapon
extends Node3D
## A firearm that hits instantly along a physics ray (rifles, pistols).
##
## Simulation (ammo, fire rate, spread, damage) happens in tick(), called once
## per physics tick by the owner (PlayerController, later NPC soldiers). It is
## deterministic given the same inputs and RNG seed, so the host can run it
## for every player in co-op. Visuals (recoil kick, muzzle flash) are in
## _process() and never affect gameplay.
##
## Scene: res://scenes/weapons/service_rifle.tscn

signal fired(origin: Vector3, direction: Vector3)
## A shot damaged something with health.
signal hit_confirmed(target: Node, damage: float, killed: bool, zone_multiplier: float)
## A shot hit any surface (for impact effects and audio).
signal surface_hit(position: Vector3, normal: Vector3, collider: Node)
signal ammo_changed(in_magazine: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
## Trigger pulled with an empty magazine.
signal dry_fired

const IMPACT_SCENE_PATH := "res://scenes/weapons/effects/bullet_impact.tscn"
const HIT_MASK := PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES | PhysicsLayers.PLAYER | PhysicsLayers.NPCS
const MAX_IMPACT_EFFECTS := 64

@export var definition: WeaponDefinition
## Turn off for remote players / dedicated host to save effects.
@export var spawn_impact_effects := true

var ammo_in_magazine := 0
var reserve_ammo := 0
var is_reloading := false

var _cooldown := 0.0
var _reload_left := 0.0
var _bloom := 0.0
var _time_since_shot := 999.0
var _spread_multiplier := 1.0
var _trigger_was_held := false
var _rng := RandomNumberGenerator.new()
var _impact_scene: PackedScene

# Visual-only state
var _kick := 0.0
var _flash_left := 0.0
var _model_rest := Vector3.ZERO

@onready var _model: Node3D = %Model
@onready var _muzzle_flash: Node3D = %MuzzleFlash


func _ready() -> void:
	assert(definition != null, "HitscanWeapon needs a WeaponDefinition")
	ammo_in_magazine = definition.magazine_size
	reserve_ammo = definition.starting_reserve
	_model_rest = _model.position
	_muzzle_flash.visible = false
	if spawn_impact_effects:
		_impact_scene = load(IMPACT_SCENE_PATH)


## One physics tick of weapon simulation.
## aim: where shots come from and point (-Z forward), normally the camera.
## shooter: excluded from hits so you can't shoot yourself.
## spread_multiplier: from the owner's movement (crouched < 1, moving > 1).
## Returns recoil to apply to the aim: x = yaw, y = pitch up (radians).
func tick(delta: float, trigger_held: bool, reload_pressed: bool, aim: Transform3D,
		shooter: CollisionObject3D = null, spread_multiplier := 1.0, can_fire := true) -> Vector2:
	_spread_multiplier = spread_multiplier
	_time_since_shot += delta
	if _time_since_shot >= definition.bloom_recovery_delay:
		_bloom = maxf(_bloom - definition.bloom_recovery * delta, 0.0)
	_cooldown -= delta
	var trigger_pulled := trigger_held and not _trigger_was_held
	_trigger_was_held = trigger_held

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		_cooldown = maxf(_cooldown, 0.0)
		return Vector2.ZERO

	if reload_pressed:
		start_reload()
		return Vector2.ZERO

	var wants_to_fire := trigger_held if definition.fire_mode == WeaponDefinition.FireMode.FULL_AUTO else trigger_pulled
	if not wants_to_fire or not can_fire:
		_cooldown = maxf(_cooldown, 0.0)
		return Vector2.ZERO
	if _cooldown > 0.0:
		return Vector2.ZERO

	if ammo_in_magazine <= 0:
		if trigger_pulled:
			dry_fired.emit()
			start_reload()
		_cooldown = 0.0
		return Vector2.ZERO

	_cooldown += definition.get_shot_interval()
	return _fire(aim, shooter)


## Starts reloading if it makes sense. Returns true if a reload began.
func start_reload() -> bool:
	if is_reloading or ammo_in_magazine >= definition.magazine_size or reserve_ammo <= 0:
		return false
	is_reloading = true
	_reload_left = definition.reload_time
	reload_started.emit(definition.reload_time)
	return true


## Stops a reload in progress without loading any rounds.
func cancel_reload() -> void:
	is_reloading = false
	_reload_left = 0.0


## Refills magazine and reserve to the definition's starting amounts.
## Used on respawn until ammo lives in the inventory (Increment 6).
func restock() -> void:
	cancel_reload()
	ammo_in_magazine = definition.magazine_size
	reserve_ammo = definition.starting_reserve
	_bloom = 0.0
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


## Current cone half-angle in degrees, including bloom and movement.
func get_current_spread_degrees() -> float:
	return (definition.base_spread + _bloom) * _spread_multiplier


## 0..1 progress of the current reload (for UI and animation).
func get_reload_progress() -> float:
	if not is_reloading:
		return 0.0
	return 1.0 - _reload_left / definition.reload_time


## Seeds the spread RNG (the host and client will share seeds in co-op).
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value


# ---------------------------------------------------------------- simulation

func _fire(aim: Transform3D, shooter: CollisionObject3D) -> Vector2:
	ammo_in_magazine -= 1
	var origin := aim.origin
	var direction := _apply_spread(-aim.basis.z.normalized(), aim.basis, get_current_spread_degrees())

	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * definition.max_range, HIT_MASK, exclude)
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	fired.emit(origin, direction)
	if definition.noise_radius > 0.0:
		get_tree().call_group("noise_listeners", "hear_noise", origin, definition.noise_radius, shooter)
	if not result.is_empty():
		_resolve_hit(result, origin, direction, shooter)

	_bloom = minf(_bloom + definition.spread_per_shot, definition.max_bloom)
	_time_since_shot = 0.0
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)

	_kick = 1.0
	_flash_left = 0.05
	var yaw := deg_to_rad(_rng.randf_range(-1.0, 1.0) * definition.recoil_yaw)
	return Vector2(yaw, deg_to_rad(definition.recoil_pitch))


func _apply_spread(direction: Vector3, basis: Basis, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	# Uniform random point inside the cone
	var angle := deg_to_rad(spread_degrees) * sqrt(_rng.randf())
	var axis := basis.x.normalized().rotated(direction, _rng.randf() * TAU)
	return direction.rotated(axis, angle).normalized()


func _resolve_hit(result: Dictionary, origin: Vector3, direction: Vector3, shooter: Node) -> void:
	var collider := result["collider"] as Node
	var position: Vector3 = result["position"]
	var normal: Vector3 = result["normal"]
	surface_hit.emit(position, normal, collider)
	if spawn_impact_effects and _impact_scene != null:
		_spawn_impact(position, normal)

	var zone_multiplier := _zone_multiplier(collider, result["shape"])
	var health := HealthComponent.find_on(collider)
	if health == null or zone_multiplier <= 0.0:
		return
	var info := DamageInfo.create(
		definition.damage_at_distance(origin.distance_to(position)) * zone_multiplier,
		DamageInfo.Type.BALLISTIC, shooter)
	info.hit_position = position
	info.hit_normal = normal
	info.direction = direction
	info.zone_multiplier = zone_multiplier
	var dealt := health.apply_damage(info)
	if dealt > 0.0:
		hit_confirmed.emit(health.get_parent(), dealt, health.is_dead(), zone_multiplier)


## Reads the "damage_multiplier" metadata from the CollisionShape3D that was
## hit (2.0 on heads, 0.0 on armour/stands). Defaults to 1.0.
func _zone_multiplier(collider: Node, shape_index: int) -> float:
	var body := collider as CollisionObject3D
	if body == null:
		return 1.0
	var owner_id := body.shape_find_owner(shape_index)
	var shape_node := body.shape_owner_get_owner(owner_id) as Node
	if shape_node != null and shape_node.has_meta("damage_multiplier"):
		return float(shape_node.get_meta("damage_multiplier"))
	return 1.0


func _finish_reload() -> void:
	var taken := mini(definition.magazine_size - ammo_in_magazine, reserve_ammo)
	ammo_in_magazine += taken
	reserve_ammo -= taken
	is_reloading = false
	_reload_left = 0.0
	reload_finished.emit()
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	var impacts := get_tree().get_nodes_in_group("bullet_impacts")
	if impacts.size() >= MAX_IMPACT_EFFECTS:
		impacts[0].queue_free()
	var impact := _impact_scene.instantiate() as Node3D
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(impact)
	impact.global_position = position + normal * 0.005
	if not normal.is_equal_approx(Vector3.UP) and not normal.is_equal_approx(Vector3.DOWN):
		impact.global_basis = Basis(Quaternion(Vector3.UP, normal))
	elif normal.is_equal_approx(Vector3.DOWN):
		impact.global_basis = Basis(Vector3.RIGHT, PI)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 9.0)
	var offset := Vector3(0.0, 0.0, _kick * 0.045)
	var tilt := Vector3(_kick * 0.05, 0.0, 0.0)
	if is_reloading:
		var dip := sin(get_reload_progress() * PI)
		offset.y -= dip * 0.08
		tilt.z = dip * 0.5
		tilt.x -= dip * 0.15
	_model.position = _model.position.lerp(_model_rest + offset, 1.0 - exp(-25.0 * delta))
	_model.rotation = _model.rotation.lerp(tilt, 1.0 - exp(-20.0 * delta))

	if _flash_left > 0.0:
		_muzzle_flash.visible = true
		_muzzle_flash.rotation.z = randf() * TAU
		_flash_left -= delta
	else:
		_muzzle_flash.visible = false
