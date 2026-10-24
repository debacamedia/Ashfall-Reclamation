class_name PlayerController
extends CharacterBody3D
## First-person character: mouse look, walk, sprint, crouch, jump, an equipped
## HitscanWeapon (fire, reload, recoil), health, fall damage, death, an
## inventory (ammo comes from it) and using items such as medkits.
##
## Movement is driven only by InputFrames passed to simulate(). The local
## player gathers its own frames from PlayerInput; remote players (co-op,
## later) and automated tests call simulate() directly with
## controlled_locally = false.
##
## Death and respawn: when health reaches zero the player enters the DEAD
## state (no movement, no weapon). Pressing jump while dead emits
## respawn_requested; the level's GameMode decides whether it is allowed yet
## and calls respawn_at(). Keeping that decision in GameMode means the host
## can enforce it in co-op.
##
## Scene: res://scenes/player/player.tscn

signal jumped
signal landed(impact_speed: float)            ## Vertical speed at touchdown (m/s).
signal stance_changed(is_crouching: bool)
signal movement_state_changed(state: MovementState)
signal died(info: DamageInfo)
signal respawn_requested
signal respawned
## Using an item (e.g. a medkit) takes time; these report its progress.
signal item_use_started(item: ItemDefinition, duration: float)
signal item_use_finished(item: ItemDefinition)
signal item_use_cancelled(item: ItemDefinition)
signal item_use_refused(reason: String)
signal item_dropped(item: ItemDefinition, quantity: int)

enum MovementState { IDLE, WALKING, SPRINTING, CROUCHING, AIRBORNE, DEAD }

@export_group("Speeds (m/s)")
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var crouch_speed := 2.2
@export var jump_velocity := 4.8

@export_group("Acceleration")
@export var ground_acceleration := 12.0
@export var ground_deceleration := 14.0
@export var air_acceleration := 2.0

@export_group("Stance (m)")
@export var stand_height := 1.8
@export var crouch_height := 1.1
## Distance from the top of the capsule down to the eyes.
@export var eye_offset := 0.12
@export var stance_transition_speed := 10.0

@export_group("Look")
@export_range(10.0, 89.0) var max_pitch_degrees := 89.0

@export_group("Head bob")
@export var head_bob_enabled := true
@export var head_bob_amplitude := 0.035
## Metres travelled per full left-right step cycle.
@export var head_bob_stride := 1.5

@export_group("Weapon handling")
## Spread multipliers by movement state (1.0 = the weapon's own spread).
@export var spread_idle := 1.0
@export var spread_walking := 1.8
@export var spread_crouching := 0.6
@export var spread_airborne := 3.0

@export_group("Fall damage (m/s)")
## Landing slower than this does no damage (≈ a 3.3 m drop).
@export var safe_fall_speed := 8.0
## Landing at this speed or faster is lethal (≈ a 16.5 m drop).
@export var lethal_fall_speed := 18.0

@export_group("Using items")
## Movement speed multiplier while using an item (bandaging, etc.).
@export var use_move_multiplier := 0.5

@export_group("Control")
## True for the player at this keyboard. False for remote players and tests,
## which drive the character by calling simulate().
@export var controlled_locally := true
## Falling below this height kills the player (out of the world).
@export var kill_plane_y := -30.0

var movement_state: MovementState = MovementState.IDLE
var is_crouching := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_height := 0.0
var _bob_distance := 0.0
var _death_tween: Tween
var _using_item: ItemDefinition = null
var _use_left := 0.0

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var head: Node3D = %Head
@onready var camera: Camera3D = %Camera
@onready var head_clearance: ShapeCast3D = %HeadClearance
@onready var player_input: PlayerInput = %PlayerInput
@onready var health: HealthComponent = %HealthComponent
## The equipped weapon, if any (scene node %Weapon under the camera).
@onready var weapon: HitscanWeapon = get_node_or_null("%Weapon")
@onready var interactor: PlayerInteractor = get_node_or_null("%Interactor")
@onready var inventory: PlayerInventory = get_node_or_null("%Inventory")


func _ready() -> void:
	add_to_group("players")
	_current_height = stand_height
	_apply_height(stand_height)
	health.died.connect(_on_health_died)
	landed.connect(_on_landed)
	if weapon != null and inventory != null:
		weapon.set_ammo_source(inventory)
	if controlled_locally:
		camera.make_current()
	else:
		player_input.process_mode = Node.PROCESS_MODE_DISABLED
		camera.current = false


func _physics_process(delta: float) -> void:
	if controlled_locally:
		simulate(player_input.gather(), delta)
	if global_position.y < kill_plane_y and not is_dead():
		var info := DamageInfo.create(health.max_health * 10.0, DamageInfo.Type.ENVIRONMENT)
		health.apply_damage(info)


func is_dead() -> bool:
	return health.is_dead()


## Advances the character by one physics tick. The same frames always give
## the same result, so the host can re-run a guest's movement.
func simulate(frame: InputFrame, delta: float) -> void:
	if is_dead():
		if interactor != null:
			interactor.tick(delta, false, null)
		_simulate_dead(frame, delta)
		return

	_apply_look(frame.look)
	_update_stance(frame.crouch, delta)
	_update_item_use(frame, delta)

	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
	elif frame.jump and not is_crouching:
		velocity.y = jump_velocity
		on_floor = false
		jumped.emit()

	# Horizontal movement relative to where the body faces
	var wish := global_basis * Vector3(frame.move.x, 0.0, frame.move.y)
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	var target := wish * _target_speed(frame)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		var rate := ground_acceleration if target.length() > 0.01 else ground_deceleration
		horizontal = horizontal.lerp(target, 1.0 - exp(-rate * delta))
	elif target.length() > 0.01:
		horizontal = horizontal.lerp(target, 1.0 - exp(-air_acceleration * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var was_on_floor := is_on_floor()
	var impact_speed := -velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor():
		landed.emit(impact_speed)
	if is_dead():
		return  # killed by the landing

	_update_movement_state()
	_update_head_bob(delta)

	if weapon != null:
		# Aim from the head (not the bobbing camera). Can't shoot mid-sprint;
		# pressing fire cancels sprint, so there is a short sprint-to-fire delay.
		weapon.lowered = is_using_item()
		var recoil := weapon.tick(delta, frame.fire, frame.reload and not is_using_item(), head.global_transform, self,
			_spread_multiplier(), movement_state != MovementState.SPRINTING and not is_using_item())
		if recoil != Vector2.ZERO:
			_apply_look(Vector2(recoil.x, -recoil.y))

	if interactor != null:
		interactor.tick(delta, frame.interact, self)


## Brings the player back to life at `spawn` with full health. Called by
## GameMode (the authority), not directly by input.
func respawn_at(spawn: Transform3D) -> void:
	if _death_tween != null:
		_death_tween.kill()
	health.revive(1.0)
	global_transform = spawn
	velocity = Vector3.ZERO
	head.rotation = Vector3.ZERO
	camera.position = Vector3.ZERO
	is_crouching = false
	_current_height = stand_height
	_apply_height(stand_height)
	if weapon != null:
		weapon.visible = true
		weapon.lowered = false
		# Never respawn without ammo; the inventory itself is kept on death for now
		if inventory != null:
			inventory.ensure_minimum_ammo(weapon.definition.ammo_type, weapon.definition.starting_reserve)
		weapon.restock()
	movement_state = MovementState.IDLE
	movement_state_changed.emit(movement_state)
	respawned.emit()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_state_name() -> String:
	return MovementState.keys()[movement_state]


## Fall damage for a given landing speed (0 when safe).
func fall_damage_for_speed(impact_speed: float) -> float:
	if impact_speed <= safe_fall_speed:
		return 0.0
	var t := (impact_speed - safe_fall_speed) / maxf(lethal_fall_speed - safe_fall_speed, 0.01)
	return health.max_health * t


# ---------------------------------------------------------------- items

func is_using_item() -> bool:
	return _using_item != null


## 0..1 progress of the current item use (-1 when not using one).
func get_item_use_progress() -> float:
	if _using_item == null:
		return -1.0
	return 1.0 - _use_left / maxf(_using_item.use_time, 0.001)


func get_item_in_use() -> ItemDefinition:
	return _using_item


## Starts using an item from the inventory (validated). Returns true if begun.
## Called for the quick-heal key and from the inventory screen.
func request_use_item(item: ItemDefinition) -> bool:
	var reason := _use_refusal_reason(item)
	if reason != "":
		item_use_refused.emit(reason)
		return false
	_using_item = item
	_use_left = item.use_time
	item_use_started.emit(item, item.use_time)
	if item.use_time <= 0.0:
		_finish_item_use()
	return true


func cancel_item_use() -> void:
	if _using_item == null:
		return
	var item := _using_item
	_using_item = null
	_use_left = 0.0
	item_use_cancelled.emit(item)


## Drops (part of) an inventory slot on the ground in front of the player.
## Returns the Pickup created, or null.
func request_drop_slot(index: int, quantity: int = -1) -> Pickup:
	if inventory == null or is_dead():
		return null
	var taken := inventory.take_from_slot(index, quantity)
	if taken.is_empty():
		return null
	var forward := -global_basis.z
	forward.y = 0.0
	var at := global_position + forward.normalized() * 1.0 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, PhysicsLayers.WORLD_SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit["position"]
	var parent := get_parent() if get_parent() != null else get_tree().current_scene
	var pickup := Pickup.spawn(parent, taken["item"], taken["qty"], at)
	item_dropped.emit(taken["item"], taken["qty"])
	return pickup


func _use_refusal_reason(item: ItemDefinition) -> String:
	if is_dead():
		return "Can't do that now"
	if item == null:
		return "No medkits"
	if inventory == null or inventory.count_of(item.id) <= 0:
		return "You don't have that"
	if is_using_item():
		return "Already busy"
	match item.category:
		ItemDefinition.Category.MEDICAL:
			if health.current_health >= health.max_health:
				return "Already at full health"
		_:
			return "Can't use that"
	return ""


func _update_item_use(frame: InputFrame, delta: float) -> void:
	if frame.use_heal:
		if is_using_item():
			cancel_item_use()
		elif inventory != null:
			request_use_item(inventory.find_best_medical())
		return
	if not is_using_item():
		return
	var sprinting := frame.sprint and frame.move.y < -0.3
	if frame.fire or sprinting:
		cancel_item_use()
		return
	_use_left -= delta
	if _use_left <= 0.0:
		_finish_item_use()


func _finish_item_use() -> void:
	var item := _using_item
	_using_item = null
	_use_left = 0.0
	# Validate again: the item could have been dropped or health topped up
	if inventory == null or inventory.count_of(item.id) <= 0:
		item_use_cancelled.emit(item)
		return
	inventory.remove_item(item.id, 1)
	if item.heal_amount > 0.0:
		health.heal(item.heal_amount)
	item_use_finished.emit(item)


# ---------------------------------------------------------------- internals

func _simulate_dead(frame: InputFrame, delta: float) -> void:
	# The body still falls and slides to a stop, but ignores all other input.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
	move_and_slide()
	if frame.jump:
		respawn_requested.emit()


func _on_landed(impact_speed: float) -> void:
	var damage := fall_damage_for_speed(impact_speed)
	if damage > 0.0:
		var info := DamageInfo.create(damage, DamageInfo.Type.FALL)
		info.direction = Vector3.DOWN
		health.apply_damage(info)


func _on_health_died(info: DamageInfo) -> void:
	cancel_item_use()
	movement_state = MovementState.DEAD
	movement_state_changed.emit(movement_state)
	if weapon != null:
		weapon.visible = false
		weapon.cancel_reload()
	# Death camera: drop towards the ground and roll onto one side
	if _death_tween != null:
		_death_tween.kill()
	_death_tween = create_tween().set_parallel()
	_death_tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(head, "rotation:z", deg_to_rad(70.0), 0.7)
	_death_tween.tween_property(head, "rotation:x", deg_to_rad(-20.0), 0.7)
	died.emit(info)


func _apply_look(look: Vector2) -> void:
	rotate_y(-look.x)
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - look.y, -limit, limit)


func _target_speed(frame: InputFrame) -> float:
	if is_using_item():
		return (crouch_speed if is_crouching else walk_speed) * use_move_multiplier
	if is_crouching:
		return crouch_speed
	# Sprint only while moving mostly forward
	if frame.sprint and frame.move.y < -0.3 and not frame.fire:
		return sprint_speed
	return walk_speed


func _spread_multiplier() -> float:
	match movement_state:
		MovementState.CROUCHING:
			return spread_crouching
		MovementState.WALKING, MovementState.SPRINTING:
			return spread_walking
		MovementState.AIRBORNE:
			return spread_airborne
	return spread_idle


func _update_stance(wants_crouch: bool, delta: float) -> void:
	var crouch := wants_crouch
	if not crouch and is_crouching and _is_head_blocked():
		crouch = true  # can't stand up under a low ceiling
	if crouch != is_crouching:
		is_crouching = crouch
		stance_changed.emit(is_crouching)

	var target_height := crouch_height if is_crouching else stand_height
	_current_height = lerpf(_current_height, target_height, 1.0 - exp(-stance_transition_speed * delta))
	if absf(_current_height - target_height) < 0.002:
		_current_height = target_height
	_apply_height(_current_height)


func _apply_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = height
	collision_shape.position.y = height / 2.0
	head.position.y = height - eye_offset


func _is_head_blocked() -> bool:
	head_clearance.force_shapecast_update()
	return head_clearance.is_colliding()


func _update_movement_state() -> void:
	var state: MovementState
	var speed := get_horizontal_speed()
	if not is_on_floor():
		state = MovementState.AIRBORNE
	elif is_crouching:
		state = MovementState.CROUCHING
	elif speed < 0.2:
		state = MovementState.IDLE
	elif speed > walk_speed + 0.5:
		state = MovementState.SPRINTING
	else:
		state = MovementState.WALKING
	if state != movement_state:
		movement_state = state
		movement_state_changed.emit(state)


func _update_head_bob(delta: float) -> void:
	var target := Vector3.ZERO
	var speed := get_horizontal_speed()
	if head_bob_enabled and is_on_floor() and speed > 0.2:
		_bob_distance += speed * delta
		var phase := _bob_distance / head_bob_stride * TAU
		var amplitude := head_bob_amplitude * clampf(speed / walk_speed, 0.0, 1.5)
		target = Vector3(sin(phase) * amplitude * 0.6, absf(sin(phase)) * amplitude, 0.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-12.0 * delta))
