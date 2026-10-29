class_name Settler
extends CharacterBody3D
## A friendly person (Increment 19): a survivor you meet, or a newcomer who
## turns up, who lives at a Settlement and does a job there.
##
##   Farmer   works the fields; the settlement turns that into vegetables
##            (with water).
##   Guard    stands at a guard post or tower once some are built (until
##            then, walks the patrol points) and fights raiders who come
##            near: with a gun if they have one (yours, or from the
##            armory), otherwise with a machete.
##   Builder  puts up what's planned at the settlement (ConstructionSites),
##            once it has its materials (Increment 19.6). A hard hat.
##   No job   helps out round the farmhouse.
##
## Unfed for too long, they stop working; longer, and they leave.
## Survivors waiting elsewhere (Saint Mercy, Halden's, Black Ridge) come when
## you ask, once you have somewhere with a free bed. They walk with you; left
## alone, they turn up at the end of the farm's lane and walk in.
##
## AUTHORITY: AI and combat run on the host. Players change jobs and guns
## through the Settlement's request_* methods.
##
## Scene: res://scenes/npcs/settler.tscn (built by tools/build_settler.gd).

signal role_changed(role: Role)
signal armed_changed

enum Role { NONE, FARMER, GUARD, BUILDER }
enum State { WAIT, TRAVEL, IDLE, WALK, WORK, PATROL, FIGHT, LEAVING, DEAD }

const ROLE_NAMES := {Role.NONE: "No job", Role.FARMER: "Farmer", Role.GUARD: "Guard", Role.BUILDER: "Builder"}
## A guard keeps about this many rounds (topped up from you or the armory).
const AMMO_TARGET := 60
const SHOT_SOUNDS := {
	&"pipe_pistol": "res://assets/audio/pistol_shot_1.wav",
	&"pistol": "res://assets/audio/pistol_shot_2.wav",
	&"shotgun": "res://assets/audio/shotgun_shot_1.wav",
	&"service_rifle": "res://assets/audio/rifle_shot_1.wav",
	&"scoped_rifle": "res://assets/audio/sniper_shot_1.wav",
}
const SHIRTS := [Color(0.55, 0.32, 0.25), Color(0.3, 0.38, 0.5), Color(0.45, 0.45, 0.32), Color(0.5, 0.48, 0.44),
	Color(0.35, 0.42, 0.3), Color(0.58, 0.5, 0.36), Color(0.42, 0.3, 0.42)]
const SKINS := [Color(0.88, 0.72, 0.6), Color(0.72, 0.55, 0.42), Color(0.55, 0.4, 0.3), Color(0.4, 0.28, 0.2), Color(0.95, 0.8, 0.7)]

@export var settler_name := "Survivor"
@export var role: Role = Role.NONE
## A survivor waiting somewhere, who'll come if you ask.
@export var recruitable := true
## What they say when you first talk to them.
@export_multiline var greeting := ""
## Picks their shirt and skin colours.
@export var look_seed := 0

@export_group("Movement")
@export var walk_speed := 1.6
@export var run_speed := 4.2
@export var acceleration := 10.0
@export var turn_speed := 8.0

@export_group("Guarding")
## Raiders this close (and in sight) get shot at (m).
@export var guard_range := 40.0
@export var melee_damage := 18.0

## Where they live (null for a survivor not yet asked).
var settlement: Settlement
var gun: ItemDefinition
## Rounds carried, and in the gun.
var ammo := 0
var magazine := 0
## Hours to their next meal, and how long they've gone without.
var next_meal := 4.0
var unfed_hours := 0.0
## A farmer with no water to work with.
var short_of_water := false
## A farmer with no field free to work (more farmers than farm spots).
var no_field := false
var state: State = State.WAIT
var target: Node3D
## Made at runtime (a newcomer), not placed in the world (a survivor).
var spawned := false

var _arrived := false
var _goal := Vector3.INF
var _state_time := 0.0
var _state_length := 0.0
var _sense := 0.0
var _cooldown := 0.0
var _reloading := 0.0
var _repath := 0.0
var _label_check := 0.0
var _travel_check := 0.0
var _post := 0
var _gone := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()

@onready var health: HealthComponent = %HealthComponent
@onready var agent: NavigationAgent3D = %NavAgent
@onready var eyes: Marker3D = %Eyes
@onready var visual: Node3D = %Visual
@onready var name_label: Label3D = %NameLabel
@onready var talk: Interactable = %Talk
@onready var shot_sound: AudioStreamPlayer3D = get_node_or_null("%ShotSound")
@onready var hit_sound: AudioStreamPlayer3D = get_node_or_null("%HitSound")


func _ready() -> void:
	add_to_group("settlers")
	add_to_group("persist")
	_rng.randomize()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_apply_look()
	_update_visuals()
	name_label.visible = false
	if state == State.WAIT and settlement != null:
		state = State.IDLE


# ---------------------------------------------------------------- state

func is_dead() -> bool:
	return health.is_dead()


## They live at their settlement now (not still on the way).
func has_arrived() -> bool:
	return settlement != null and _arrived


## Fed, at home, with a job.
func is_working() -> bool:
	return has_arrived() and not is_dead() and role != Role.NONE and not is_hungry()


func is_hungry() -> bool:
	return settlement != null and unfed_hours >= settlement.hungry_after_hours


## What they're doing, for the settlement screen.
func status_text() -> String:
	if is_dead():
		return "Dead"
	if settlement == null:
		return "Waiting"
	if not _arrived:
		return "On the way"
	if is_hungry():
		return "Hungry: not working"
	match role:
		Role.FARMER:
			if no_field:
				return "No field free"
			return "No water to farm" if short_of_water else "Farming"
		Role.GUARD:
			if state == State.FIGHT:
				return "Fighting"
			return "Guarding" if gun != null else "Guarding (machete)"
		Role.BUILDER:
			var site := settlement.current_site()
			if site != null:
				return "Building the %s" % site.display_name().to_lower()
			for other in settlement.sites():
				if not other.is_supplied():
					return "Waiting for materials"
			return "Nothing to build"
	return "Helping out"


func role_name() -> String:
	return ROLE_NAMES[role]


func gun_text() -> String:
	if gun == null:
		return "Unarmed"
	return "%s · %d rounds" % [gun.display_name, ammo + magazine]


# ---------------------------------------------------------------- orders

## Joins `s` and heads there (called by the Settlement).
func join(s: Settlement) -> void:
	settlement = s
	recruitable = false
	_arrived = false
	next_meal = s.meal_every_hours
	_enter(State.TRAVEL)


func set_role(r: Role) -> void:
	if r == role:
		return
	role = r
	target = null
	_update_visuals()
	role_changed.emit(r)
	if _arrived:
		_enter(State.IDLE)


func arm(item: ItemDefinition, rounds: int) -> void:
	gun = item
	ammo = maxi(rounds, 0)
	magazine = 0
	_update_visuals()
	armed_changed.emit()


func disarm() -> void:
	gun = null
	ammo = 0
	magazine = 0
	_update_visuals()
	armed_changed.emit()


## Walks off for good (no food), leaving their gun in the armory.
func leave() -> void:
	if settlement != null and gun != null:
		settlement._return_gun(self, null)
	var from := settlement
	settlement = null
	_arrived = false
	role = Role.NONE
	_update_visuals()
	_enter(State.LEAVING)
	if from != null:
		var away := global_position - from.global_position
		away.y = 0.0
		_goal = global_position + (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 60.0


# ---------------------------------------------------------------- AI

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD:
		_brake(delta)
		move_and_slide()
		return
	_state_time += delta
	_cooldown -= delta
	_label_check -= delta
	if _label_check <= 0.0:
		_label_check = 0.5
		_update_label()
	match state:
		State.WAIT:
			_brake(delta)
			_face_player(delta)
		State.TRAVEL:
			_travel(delta)
		State.LEAVING:
			if _move_to(_goal, walk_speed, delta) or _state_time > 40.0:
				_vanish()
		State.FIGHT:
			_fight(delta)
		_:
			_home_life(delta)
	move_and_slide()


func _enter(s: State) -> void:
	state = s
	_state_time = 0.0
	_state_length = _rng.randf_range(6.0, 12.0)
	_goal = Vector3.INF


func _travel(delta: float) -> void:
	var dest := _hangout()
	if Vector2(dest.x - global_position.x, dest.z - global_position.z).length() < 4.0:
		_arrive()
		return
	# Out of everyone's sight, the walk is quicker: they turn up at the farm
	_travel_check -= delta
	if _travel_check <= 0.0:
		_travel_check = 1.0
		if not _player_within(90.0):
			# Nobody's with them: the long walk is done off-screen. They turn
			# up at the end of the lane and walk in (or, if nobody's at the
			# farm either, simply arrive).
			var lane := settlement.get_node_or_null("ArrivalPoint") as Node3D
			if lane != null and global_position.distance_to(lane.global_position) > 6.0 and global_position.distance_to(dest) > lane.global_position.distance_to(dest) + 2.0:
				global_position = lane.global_position + Vector3.UP * 0.1
			elif not _player_near_place(dest, 90.0):
				global_position = dest + Vector3.UP * 0.1
				velocity = Vector3.ZERO
				_arrive()
				return
			velocity = Vector3.ZERO
	_move_to(dest, walk_speed, delta)


func _arrive() -> void:
	_arrived = true
	_enter(State.IDLE)
	settlement.on_arrived(self)


## Life at the settlement: work, guard or help out; idle when hungry.
func _home_life(delta: float) -> void:
	if settlement == null:
		_brake(delta)
		return
	if role == Role.GUARD and not is_hungry():
		_sense -= delta
		if _sense <= 0.0:
			_sense = 0.3
			var r := _find_raider()
			if r != null:
				target = r
				_enter(State.FIGHT)
				return
	if is_hungry() or role == Role.NONE or (role == Role.FARMER and (short_of_water or no_field)):
		_wander(_hangout(), 6.0, delta)
		return
	match role:
		Role.FARMER:
			_farm(delta)
		Role.GUARD:
			_patrol(delta)
		Role.BUILDER:
			_build(delta)


func _farm(delta: float) -> void:
	if _goal == Vector3.INF:
		_goal = _pick_from(settlement.farm_spots(), 3.0)
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(8.0, 14.0)
		return
	# Working the soil: bent over, bobbing
	_brake(delta)
	visual.rotation.x = deg_to_rad(25.0 + sin(_state_time * 3.0) * 8.0)
	if _state_time > _state_length:
		visual.rotation.x = 0.0
		_goal = Vector3.INF


func _patrol(delta: float) -> void:
	if _goal == Vector3.INF:
		# A guard post or tower of their own once some are built (one guard
		# each, in turn); otherwise walk the patrol points
		var posts := settlement.guard_posts()
		if not posts.is_empty():
			var guards := settlement.members().filter(func(s: Settler) -> bool: return s.role == Role.GUARD and s.has_arrived())
			var mine := maxi(guards.find(self), 0)
			if mine < posts.size():
				_goal = posts[mine].global_position
			else:
				_goal = _pick_from(settlement.patrol_points(), 2.0)
		else:
			var points := settlement.patrol_points()
			if points.is_empty():
				_goal = _hangout()
			else:
				_post = (_post + 1 + _rng.randi() % 2) % points.size()
				_goal = points[_post].global_position
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.PATROL
			_state_time = 0.0
			_state_length = _rng.randf_range(8.0, 15.0)
		return
	_brake(delta)
	rotation.y += sin(_state_time * 0.6) * 0.6 * delta  # looking round
	if _state_time > _state_length:
		_goal = Vector3.INF


## Builders: to the site, then hammering.
func _build(delta: float) -> void:
	var site := settlement.current_site()
	if site == null:
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	if _goal == Vector3.INF or state == State.IDLE:
		_goal = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, site.work_point())
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		_swing(false)
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(10.0, 16.0)
		return
	_brake(delta)
	_face(_next_piece_at(site) - global_position, delta)
	_swing(true)
	if _state_time > _state_length:
		_goal = Vector3.INF


func _next_piece_at(site: ConstructionSite) -> Vector3:
	var i := clampi(site.built, 0, maxi(site.pieces.size() - 1, 0))
	return site.global_transform * site.pieces[i].origin if not site.pieces.is_empty() else site.global_position


## The hammer arm going up and down.
func _swing(on: bool) -> void:
	var arm := visual.get_node_or_null("RightArm") as Node3D
	if arm == null:
		return
	arm.rotation.x = (0.26 - 1.1 + absf(sin(_state_time * 5.0)) * 1.1) if on else 0.26


func _wander(around: Vector3, radius: float, delta: float) -> void:
	visual.rotation.x = 0.0
	if _goal == Vector3.INF or _goal.distance_to(around) > radius + 1.0:
		var angle := _rng.randf() * TAU
		var p := around + Vector3(cos(angle), 0, sin(angle)) * _rng.randf_range(0.5, radius)
		_goal = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		if _move_to(_goal, walk_speed, delta) or _state_time > 30.0:
			state = State.IDLE
			_state_time = 0.0
			_state_length = _rng.randf_range(5.0, 12.0)
		return
	_brake(delta)
	_face_player(delta)
	if _state_time > _state_length:
		_goal = Vector3.INF


## The nearest living raider in sight, within range and inside the
## settlement's defended area.
func _find_raider() -> Node3D:
	var best: Node3D = null
	var best_d := guard_range
	for n in get_tree().get_nodes_in_group("enemies"):
		var r := n as Node3D
		if r == null or (r.has_method("is_dead") and r.call("is_dead")):
			continue
		var d := global_position.distance_to(r.global_position)
		if d > best_d or r.global_position.distance_to(settlement.global_position) > settlement.defend_radius:
			continue
		if not _can_see(r):
			continue
		best = r
		best_d = d
	return best


func _can_see(n: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eyes.global_position, n.global_position + Vector3.UP * 1.2, PhysicsLayers.WORLD_SOLID, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _fight(delta: float) -> void:
	var gone: bool = target == null or not is_instance_valid(target) or (target.has_method("is_dead") and bool(target.call("is_dead")))
	if gone or global_position.distance_to(target.global_position) > guard_range * 1.3 \
			or target.global_position.distance_to(settlement.global_position) > settlement.defend_radius * 1.2:
		target = null
		_enter(State.IDLE)
		return
	var to := target.global_position - global_position
	if gun != null and (magazine > 0 or ammo > 0):
		_brake(delta)
		_face(to, delta)
		if _reloading > 0.0:
			_reloading -= delta
			if _reloading <= 0.0:
				var take := mini(gun.weapon.magazine_size, ammo)
				magazine += take
				ammo -= take
			return
		if magazine <= 0:
			_reloading = gun.weapon.reload_time
			return
		if _cooldown <= 0.0 and _can_see(target):
			_shoot(target)
		return
	# No gun (or no rounds): the machete
	if to.length() > 1.6:
		_move_to(target.global_position, run_speed, delta)
		return
	_brake(delta)
	_face(to, delta)
	if _cooldown <= 0.0:
		_cooldown = 1.0
		var info := DamageInfo.create(melee_damage, DamageInfo.Type.MELEE, self)
		info.direction = to.normalized()
		var h := HealthComponent.find_on(target)
		if h != null:
			h.apply_damage(info)


func _shoot(t: Node3D) -> void:
	var w := gun.weapon
	magazine -= 1
	_cooldown = maxf(60.0 / maxf(w.rounds_per_minute, 1.0), 0.45)
	var from := eyes.global_position
	var aim := (t.global_position + Vector3.UP * 1.1 - from).normalized()
	var spread := deg_to_rad(1.5 + w.base_spread * 2.0)
	var space := get_world_3d().direct_space_state
	for p in w.pellets:
		var axis := aim.cross(Vector3.UP).normalized().rotated(aim, _rng.randf() * TAU)
		var dir := aim.rotated(axis, _rng.randf() * spread) if axis.length() > 0.5 else aim
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * w.max_range, PhysicsLayers.WORLD_SOLID | PhysicsLayers.NPCS, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var h := HealthComponent.find_on(hit["collider"])
		if h == null or hit["collider"] is Settler:
			continue
		var dist := from.distance_to(hit["position"])
		var fall := 1.0 if dist <= w.falloff_start else lerpf(1.0, w.falloff_min_multiplier, clampf((dist - w.falloff_start) / maxf(w.falloff_end - w.falloff_start, 1.0), 0.0, 1.0))
		var info := DamageInfo.create(w.damage * fall, DamageInfo.Type.BALLISTIC, self)
		info.direction = dir
		info.hit_position = hit["position"]
		h.apply_damage(info)
	if shot_sound != null:
		var path: String = SHOT_SOUNDS.get(w.id, SHOT_SOUNDS[&"pistol"])
		shot_sound.stream = load(path)
		shot_sound.play()
	get_tree().call_group("noise_listeners", "hear_noise", global_position, w.noise_radius, self)


# ---------------------------------------------------------------- movement

func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	_repath -= delta
	if _repath <= 0.0 or agent.target_position.distance_to(point) > 1.0:
		agent.target_position = point
		_repath = 0.3
	if Vector2(point.x - global_position.x, point.z - global_position.z).length() <= agent.target_desired_distance:
		_brake(delta)
		return true
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05 and agent.is_navigation_finished():
		dir = Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	dir = dir.normalized()
	var weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, weight)
	velocity.z = lerpf(velocity.z, dir.z * speed, weight)
	_face(dir, delta)
	return false


func _brake(delta: float) -> void:
	var weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, 0.0, weight)
	velocity.z = lerpf(velocity.z, 0.0, weight)


func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-turn_speed * delta))


func _face_player(delta: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var pc := p as Node3D
		if pc != null and pc.global_position.distance_to(global_position) < 6.0:
			_face(pc.global_position - global_position, delta)
			return


func _player_near_place(p: Vector3, d: float) -> bool:
	for pl in get_tree().get_nodes_in_group("players"):
		if (pl as Node3D).global_position.distance_to(p) <= d:
			return true
	return false


func _player_within(d: float) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if (p as Node3D).global_position.distance_to(global_position) <= d:
			return true
	return false


func _hangout() -> Vector3:
	var h := settlement.get_node_or_null("Hangout") as Node3D if settlement != null else null
	return h.global_position if h != null else (settlement.global_position if settlement != null else global_position)


## One of `spots` at random, nudged up to `jitter` m.
func _pick_from(spots: Array[Node3D], jitter: float) -> Vector3:
	if spots.is_empty():
		return _hangout()
	var m := spots[_rng.randi() % spots.size()]
	var p := m.global_position + Vector3(_rng.randf_range(-jitter, jitter), 0, _rng.randf_range(-jitter, jitter))
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


## A random child of `group` (a Marker3D), nudged up to `jitter` m.
func _pick(group: Node, jitter: float) -> Vector3:
	if group == null or group.get_child_count() == 0:
		return _hangout()
	var m := group.get_child(_rng.randi() % group.get_child_count()) as Node3D
	var p := m.global_position + Vector3(_rng.randf_range(-jitter, jitter), 0, _rng.randf_range(-jitter, jitter))
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


# ---------------------------------------------------------------- looks

func _apply_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed if look_seed != 0 else hash(settler_name)
	var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta("tint"):
			var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = shirt if mi.get_meta("tint") == "shirt" else skin
			mi.material_override = m


func _update_visuals() -> void:
	if not is_node_ready():
		return
	for pair in [["Hat", role == Role.FARMER], ["Vest", role == Role.GUARD], ["Helmet", role == Role.GUARD],
			["HardHat", role == Role.BUILDER], ["ToolBelt", role == Role.BUILDER]]:
		var n := visual.get_node_or_null(pair[0]) as Node3D
		if n != null:
			n.visible = pair[1]
	var g := visual.get_node_or_null("RightArm/Gun") as Node3D
	if g != null:
		g.visible = gun != null
	var blade := visual.get_node_or_null("RightArm/Machete") as Node3D
	if blade != null:
		blade.visible = gun == null and role == Role.GUARD
	var hammer := visual.get_node_or_null("RightArm/Hammer") as Node3D
	if hammer != null:
		hammer.visible = gun == null and role == Role.BUILDER
	if role != Role.BUILDER:
		_swing(false)


## Name and job float over them when you're close.
func _update_label() -> void:
	var near := _player_within(10.0) and not is_dead()
	name_label.visible = near
	if near:
		name_label.text = settler_name if settlement == null else "%s\n%s" % [settler_name, role_name() if _arrived else "On the way"]
		name_label.modulate = Color(0.75, 0.95, 0.75) if settlement != null else Color(0.95, 0.9, 0.75)


func _on_damaged(_amount: float, info: DamageInfo) -> void:
	if hit_sound != null and not is_dead():
		hit_sound.play()
	# A guard hit by a raider fights back
	if role == Role.GUARD and has_arrived() and info != null and info.source is Node3D \
			and (info.source as Node).is_in_group("enemies") and state != State.FIGHT:
		target = info.source
		_enter(State.FIGHT)


func _on_died(_info: DamageInfo) -> void:
	var home := settlement
	_enter(State.DEAD)
	talk.enabled = false
	name_label.visible = false
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", deg_to_rad(-88.0), 0.6)
	if home != null:
		if gun != null:
			home._return_gun(self, null)
		home.on_settler_died(self)
	settlement = null
	get_tree().create_timer(30.0).timeout.connect(_vanish)


## Gone: newcomers are removed; placed survivors are hidden (so a load
## doesn't bring them back from the scene).
func _vanish() -> void:
	if not is_inside_tree():
		return
	if spawned:
		queue_free()
		return
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	collision_layer = 0
	talk.enabled = false
	_gone = true


# ---------------------------------------------------------------- saving

func is_save_removable() -> bool:
	return spawned


func save_state() -> Dictionary:
	var p := global_position
	return {
		"name": settler_name, "role": role, "position": [p.x, p.y, p.z], "yaw": rotation.y,
		"settlement": String(settlement.settlement_id) if settlement != null else "",
		"arrived": _arrived, "recruitable": recruitable, "spawned": spawned, "look": look_seed,
		"gun": String(gun.id) if gun != null else "", "ammo": ammo + magazine,
		"health": health.current_health, "next_meal": next_meal, "unfed": unfed_hours,
		"gone": _gone or is_dead() or state == State.LEAVING,
	}


func load_state(data: Dictionary) -> void:
	if data.get("gone") is bool and data["gone"]:
		spawned = data.get("spawned") is bool and data["spawned"]
		_vanish_now()
		return
	settler_name = str(data.get("name", settler_name))
	spawned = data.get("spawned") is bool and data["spawned"]
	recruitable = data.get("recruitable") is bool and data["recruitable"]
	look_seed = int(Settlement._num(data.get("look"), look_seed))
	_apply_look()
	var r := int(Settlement._num(data.get("role"), 0))
	role = r as Role if r >= 0 and r <= Role.BUILDER else Role.NONE
	var raw_p: Variant = data.get("position")
	if raw_p is Array and raw_p.size() == 3 and raw_p.all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))):
		global_position = Vector3(raw_p[0], raw_p[1], raw_p[2])
	rotation.y = Settlement._num(data.get("yaw"), rotation.y)
	velocity = Vector3.ZERO
	settlement = Settlement.find(get_tree(), StringName(str(data.get("settlement", ""))))
	_arrived = settlement != null and data.get("arrived") is bool and data["arrived"]
	var item := ItemDatabase.get_item(StringName(str(data.get("gun", ""))))
	gun = item if item != null and item.weapon != null else null
	ammo = maxi(int(Settlement._num(data.get("ammo"), 0)), 0) if gun != null else 0
	magazine = 0
	next_meal = Settlement._num(data.get("next_meal"), 4.0)
	unfed_hours = maxf(Settlement._num(data.get("unfed"), 0.0), 0.0)
	var hp := Settlement._num(data.get("health"), health.max_health)
	health.revive(clampf(hp, 1.0, health.max_health) / health.max_health)
	target = null
	collision_layer = PhysicsLayers.NPCS
	talk.enabled = true
	if settlement == null:
		_enter(State.WAIT)
	elif not _arrived:
		_enter(State.TRAVEL)
	else:
		_enter(State.IDLE)
	visual.rotation = Vector3.ZERO
	_update_visuals()


func _vanish_now() -> void:
	if spawned:
		queue_free()
	else:
		_vanish()
