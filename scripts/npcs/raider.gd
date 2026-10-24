class_name Raider
extends CharacterBody3D
## Melee raider: wanders near home, spots players by sight (range + view
## cone + line of sight) or by hearing gunshots, paths to them over the
## navigation mesh and attacks with a telegraphed swing.
##
## States:
##   IDLE    standing around for a few seconds
##   WANDER  walking to a random point near home
##   CHASE   running at a known target
##   ATTACK  wind-up, strike, recovery (can be dodged during the wind-up)
##   SEARCH  going to the last known / heard position and looking around
##   DEAD    fallen; despawns after a while
##
## AUTHORITY: AI, perception and damage run only where the game state lives
## (single-player, or the co-op host). Clients will just replicate transform,
## state and health.
##
## Scene: res://scenes/enemies/raider.tscn

signal state_changed(state: State)
signal attacked(target: Node3D, hit: bool)
signal killed(raider: Raider)

enum State { IDLE, WANDER, CHASE, ATTACK, SEARCH, DEAD }

## Name used in kill messages ("Killed by Raider").
@export var display_name := "Raider"

@export_group("Movement")
@export var walk_speed := 1.8
@export var run_speed := 5.0
@export var acceleration := 10.0
@export var turn_speed := 8.0
@export var wander_radius := 12.0
@export var idle_time_min := 2.0
@export var idle_time_max := 5.0

@export_group("Senses")
@export var sight_range := 30.0
@export_range(10.0, 360.0) var sight_fov_degrees := 120.0
## Players closer than this are noticed even outside the view cone.
@export var proximity_range := 2.5
## Multiplies the radius of noises (gunshots) this raider can hear.
@export var hearing_multiplier := 1.0
## Seconds without seeing the target before giving up the chase and searching.
@export var lose_target_time := 4.0
@export var search_time := 6.0

@export_group("Melee")
@export var attack_range := 1.7
@export var attack_damage := 20.0
@export var attack_windup := 0.45
@export var attack_recovery := 0.8
## The strike only lands if the target is within this angle in front.
@export var attack_hit_angle_degrees := 70.0

@export_group("Death")
@export var despawn_time := 30.0

var state: State = State.IDLE
## Wander area centre. Set by the spawner; defaults to the starting position.
var home_position := Vector3.INF
var target: PlayerController = null
var last_known_position := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _state_time := 0.0
var _state_duration := 0.0
var _time_since_seen := 999.0
var _sense_timer := 0.0
var _repath_timer := 0.0
var _move_goal := Vector3.ZERO
var _attack_cooldown := 0.0
var _strike_done := false
var _search_running := false
var _rng := RandomNumberGenerator.new()
var _arm_tween: Tween

@onready var health: HealthComponent = %HealthComponent
@onready var agent: NavigationAgent3D = %NavAgent
@onready var eyes: Marker3D = %Eyes
@onready var visual: Node3D = %Visual
@onready var right_arm: Node3D = %RightArm
@onready var alert_label: Label3D = %AlertLabel


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("noise_listeners")
	_rng.randomize()
	if home_position == Vector3.INF:
		home_position = global_position
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	alert_label.visible = false
	_enter(State.IDLE)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	_state_time += delta
	_attack_cooldown -= delta
	_time_since_seen += delta
	_repath_timer -= delta
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.1
		_update_perception()

	match state:
		State.IDLE:
			_brake(delta)
			if _state_time >= _state_duration:
				_enter(State.WANDER)
		State.WANDER:
			if _move_to(_move_goal, walk_speed, delta) or _state_time > 20.0:
				_enter(State.IDLE)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.SEARCH:
			_process_search(delta)

	move_and_slide()


# ---------------------------------------------------------------- public

func is_dead() -> bool:
	return state == State.DEAD


func get_state_name() -> String:
	return State.keys()[state]


## Starts chasing `player` immediately (used when hit, or by scripted events).
func alert_to(player: PlayerController) -> void:
	if is_dead() or player == null or player.is_dead():
		return
	var was_calm := state in [State.IDLE, State.WANDER, State.SEARCH]
	target = player
	last_known_position = player.global_position
	_time_since_seen = 0.0
	if state != State.ATTACK and state != State.CHASE:
		_enter(State.CHASE)
	if was_calm:
		_show_alert()


## Called (via the "noise_listeners" group) when something makes a noise,
## e.g. a gunshot. Calm raiders run to investigate.
func hear_noise(origin: Vector3, radius: float, _source: Node) -> void:
	if is_dead() or state == State.CHASE or state == State.ATTACK:
		return
	if global_position.distance_to(origin) > radius * hearing_multiplier:
		return
	last_known_position = origin
	_search_running = true
	_enter(State.SEARCH)
	_show_alert()


## True if this raider can currently see `player`.
func can_see(player: PlayerController) -> bool:
	if player == null or player.is_dead():
		return false
	var target_point := player.head.global_position
	var to_target := target_point - eyes.global_position
	var distance := to_target.length()
	if distance > sight_range:
		return false
	if distance > proximity_range:
		var forward := -global_basis.z
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.length() > 0.01 and rad_to_deg(forward.angle_to(flat)) > sight_fov_degrees / 2.0:
			return false
	var query := PhysicsRayQueryParameters3D.create(eyes.global_position, target_point,
		PhysicsLayers.WORLD_SOLID, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------- states

func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_strike_done = false
	match new_state:
		State.IDLE:
			_state_duration = _rng.randf_range(idle_time_min, idle_time_max)
			target = null if (target != null and target.is_dead()) else target
		State.WANDER:
			_move_goal = _pick_wander_point()
		State.ATTACK:
			_play_windup()
		State.SEARCH:
			_move_goal = last_known_position
	state_changed.emit(new_state)


func _process_chase(delta: float) -> void:
	if target == null or target.is_dead():
		target = null
		_enter(State.IDLE)
		return
	if _time_since_seen > lose_target_time:
		# Keep hunting: run to where the target was last seen
		_search_running = true
		_enter(State.SEARCH)
		return
	var goal := target.global_position if _time_since_seen < 0.5 else last_known_position
	var distance := global_position.distance_to(target.global_position)
	if distance <= attack_range and _time_since_seen < 0.5:
		_brake(delta)
		_face(target.global_position - global_position, delta)
		if _attack_cooldown <= 0.0:
			_enter(State.ATTACK)
		return
	_move_to(goal, run_speed, delta)


func _process_attack(delta: float) -> void:
	_brake(delta)
	if target != null and not target.is_dead():
		_face(target.global_position - global_position, delta)
	if not _strike_done and _state_time >= attack_windup:
		_strike_done = true
		_strike()
	if _state_time >= attack_windup + attack_recovery:
		_attack_cooldown = 0.0
		if target == null or target.is_dead():
			target = null
			_enter(State.IDLE)
		else:
			_enter(State.CHASE)


func _process_search(delta: float) -> void:
	var speed := run_speed if _search_running else walk_speed
	if _move_to(_move_goal, speed, delta):
		# Look around where we expected to find someone
		rotate_y(delta * 1.2)
	if _state_time > search_time + 8.0 or (_state_time > search_time and global_position.distance_to(_move_goal) < 2.0):
		_enter(State.WANDER)


func _strike() -> void:
	var hit := false
	if target != null and not target.is_dead():
		var to_target := target.global_position - global_position
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		var in_front := flat.length() < 0.01 or rad_to_deg((-global_basis.z).angle_to(flat)) <= attack_hit_angle_degrees
		if to_target.length() <= attack_range + 0.3 and in_front:
			var info := DamageInfo.create(attack_damage, DamageInfo.Type.MELEE, self)
			info.hit_position = target.global_position + Vector3.UP
			info.direction = flat.normalized()
			target.health.apply_damage(info)
			hit = true
	_play_strike()
	attacked.emit(target, hit)


# ---------------------------------------------------------------- perception

func _update_perception() -> void:
	if target != null and target.is_dead():
		target = null
	var best: PlayerController = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as PlayerController
		if player == null or not can_see(player):
			continue
		var d := global_position.distance_to(player.global_position)
		if d < best_distance:
			best = player
			best_distance = d
	if best == null:
		return
	var was_calm := state in [State.IDLE, State.WANDER, State.SEARCH]
	target = best
	last_known_position = best.global_position
	_time_since_seen = 0.0
	if was_calm:
		_enter(State.CHASE)
		_show_alert()


# ---------------------------------------------------------------- movement

## Walks toward `point` along the navigation mesh. Returns true on arrival.
func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	if _repath_timer <= 0.0 or agent.target_position.distance_to(point) > 1.0:
		agent.target_position = point
		_repath_timer = 0.25
	var flat_distance := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	if flat_distance <= agent.target_desired_distance:
		_brake(delta)
		return true
	var next := agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	if direction.length() < 0.05 and agent.is_navigation_finished():
		# No path yet (map still syncing) or right on a waypoint
		direction = Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	direction = direction.normalized()
	var weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)
	_face(direction, delta)
	return false


func _brake(delta: float) -> void:
	var weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, 0.0, weight)
	velocity.z = lerpf(velocity.z, 0.0, weight)


func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	var yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _pick_wander_point() -> Vector3:
	var map := get_world_3d().navigation_map
	for attempt in 6:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(2.0, wander_radius)
		var candidate := home_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var on_mesh := NavigationServer3D.map_get_closest_point(map, candidate)
		# Skip points on roofs and wall tops
		if absf(on_mesh.y - home_position.y) < 0.6:
			return on_mesh
	return home_position


# ---------------------------------------------------------------- reactions

func _on_damaged(_amount: float, info: DamageInfo) -> void:
	if is_dead():
		return
	# Flinch
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", deg_to_rad(10.0), 0.05)
	tween.tween_property(visual, "rotation:x", 0.0, 0.2)
	if info.source is PlayerController:
		alert_to(info.source as PlayerController)


func _on_died(_info: DamageInfo) -> void:
	state = State.DEAD
	state_changed.emit(state)
	target = null
	alert_label.visible = false
	# Bullets and players pass through the body; it still rests on the ground
	collision_layer = 0
	collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES
	remove_from_group("noise_listeners")
	if _arm_tween != null:
		_arm_tween.kill()
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "rotation:x", deg_to_rad(84.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(right_arm, "rotation:x", deg_to_rad(-30.0), 0.5)
	killed.emit(self)
	get_tree().create_timer(despawn_time).timeout.connect(queue_free)


func _show_alert() -> void:
	alert_label.visible = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(alert_label):
			alert_label.visible = false)


func _play_windup() -> void:
	if _arm_tween != null:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(right_arm, "rotation:x", deg_to_rad(150.0), attack_windup * 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_strike() -> void:
	if _arm_tween != null:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(right_arm, "rotation:x", deg_to_rad(40.0), 0.1)
	_arm_tween.tween_property(right_arm, "rotation:x", deg_to_rad(15.0), 0.4)
