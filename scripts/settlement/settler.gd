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
##   Woodcutter  cuts timber at the settlement's woodlot: Wood Planks in the
##            stores every hour (Increment 19.7). An axe.
##   No job   helps out round the farmhouse.
##
## Unfed for too long, they stop working; longer, and they leave.
##
## Raids (Increment 20): while raiders are at the settlement, everyone but
## the guards shelters in the farmhouse. A settler beaten by raiders goes
## down wounded instead of dying: help them up (E, with a Bandage or a
## Medkit). Left down for `Settlement.bleed_out_hours`, they die.
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

enum Role { NONE, FARMER, GUARD, BUILDER, WOODCUTTER, COOK, RANCHER, MINER, ARMORER, TAILOR }
enum State { WAIT, TRAVEL, IDLE, WALK, WORK, PATROL, FIGHT, LEAVING, DEAD, DOWN }

const ROLE_NAMES := {Role.NONE: "No job", Role.FARMER: "Farmer", Role.GUARD: "Guard", Role.BUILDER: "Builder", Role.WOODCUTTER: "Woodcutter",
	Role.COOK: "Cook", Role.RANCHER: "Rancher", Role.MINER: "Miner",
	Role.ARMORER: "Armorer", Role.TAILOR: "Tailor"}
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
## Work trousers and boots (29: with the shirt, on the body's clothes)
const TROUSERS := [Color(0.28, 0.27, 0.24), Color(0.24, 0.26, 0.32), Color(0.36, 0.3, 0.22), Color(0.3, 0.3, 0.27), Color(0.22, 0.2, 0.18)]
const BOOTS := [Color(0.22, 0.16, 0.11), Color(0.15, 0.13, 0.12), Color(0.3, 0.22, 0.14)]
## What armour looks like over the clothes (22, 28): [colour, metal]
const ARMOUR_LOOKS := {"leather": [Color(0.42, 0.27, 0.15), 0.0], "plated": [Color(0.45, 0.46, 0.48), 0.6],
	"wool": [Color(0.82, 0.77, 0.66), 0.0], "padded": [Color(0.42, 0.4, 0.28), 0.0]}

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
## Up a tower (28.1): they see this far, and along the wall it stands against.
@export var tower_range := 60.0

## Guards shoot this much faster than the gun's own rate, floored (28.1).
const FIRE_RATE := 1.25
## A tower's steadier aim: its spread is this share of the ground's (28.1).
const TOWER_SPREAD := 0.75
## A guard spot this far above its building's floor is up a tower (m).
const RAISED := 1.5
## Built walls: no hopping through them, and guards on the ground don't go
## after raiders on the far side of one (28.1).
const WALL_IDS := [&"farm_fence", &"palisade", &"reinforced_palisade", &"settlement_gate", &"palisade_gate"]
## Within this far of the wall a tower stands against (m): seen from it.
const ON_WALL := 3.5

## Where they live (null for a survivor not yet asked).
var settlement: Settlement
var gun: ItemDefinition
## Clothing and armour (Increment 22): guards can wear it.
var armour := ArmourSet.new()
## Rounds carried, and in the gun.
var ammo := 0
var magazine := 0
## Hours to their next meal, and how long they've gone without.
var next_meal := 4.0
var unfed_hours := 0.0
## A farmer with no water to work with.
var short_of_water := false
## Hours spent down, wounded (Increment 20).
var down_hours := 0.0
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
## The guard spot they were given (a post or a tower's deck), if any (28.1).
var _spot: Node3D = null
## [origin, along] of each wall length their tower stands against.
var _tower_walls: Array = []
var _tower_walls_for: Node3D = null
## At the foot of their tower's stair, on the way up it.
var _climbing := false
## The person (29), their gear by name, and what they're doing with their
## hands.
var body: HumanBody
var _parts := {}
var _working := false
var _act := 0.0
var _act_anim := &""
var _stuck := 0
var _probe_left := 0.0
var _probe_from := Vector3.INF
var _probe_next := Vector3.INF
var _side_left := 0.0
var _side_dir := Vector3.ZERO
## Which way a Miner faces at the rock face (23).
var _work_facing := Vector3.FORWARD
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
	# Follow the path's corners closely (22.1): turning for the next point
	# 0.8 m early cut them round a stair's newel post and into it
	agent.path_desired_distance = 0.45
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	health.damage_modifier = func(info: DamageInfo) -> float: return armour.absorb(info.amount, info.type)
	armour.changed.connect(_update_visuals)
	body = visual.get_node_or_null("Body") as HumanBody
	_apply_look()
	_update_visuals()
	name_label.visible = false
	if state == State.WAIT and settlement != null:
		state = State.IDLE


# ---------------------------------------------------------------- state

func is_dead() -> bool:
	return state == State.DEAD or (health.is_dead() and state != State.DOWN)


## Down, wounded by raiders: alive, but needs helping up.
func is_down() -> bool:
	return state == State.DOWN


## They live at their settlement now (not still on the way).
func has_arrived() -> bool:
	return settlement != null and _arrived


## Fed, at home, with a job.
func is_working() -> bool:
	return has_arrived() and not is_dead() and not is_down() and role != Role.NONE and not is_hungry()


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
	if is_down():
		return "Wounded: help them up (E, a Bandage)"
	if settlement.raid_active() and role != Role.GUARD:
		return "Sheltering from the raid"
	if is_hungry():
		return "Hungry: not working"
	match role:
		Role.FARMER:
			if _shearing():
				return "Shearing the sheep"
			if no_field:
				return "No field free"
			return "No water to farm" if short_of_water else "Farming"
		Role.GUARD:
			if state == State.FIGHT:
				return "Fighting"
			return "Guarding" if gun != null else "Guarding (machete)"
		Role.BUILDER:
			var a := settlement.builder_assignment()
			var at := ""
			if not a.is_empty() and a[1] != settlement:
				at = " at %s" % (a[1] as Settlement).settlement_name
			if not a.is_empty() and a[0] is Structure:
				return "Mending the %s%s" % [(a[0] as Structure).definition.display_name.to_lower(), at]
			if not a.is_empty():
				return "Building the %s%s" % [(a[0] as ConstructionSite).display_name().to_lower(), at]
			for st in settlement.network():
				for other in st.sites():
					if not other.is_supplied():
						return "Waiting for materials"
			return "Nothing to build"
		Role.WOODCUTTER:
			return "Cutting wood" if not settlement.wood_spots().is_empty() else "No woodlot here"
		Role.COOK:
			return settlement.cook_status()
		Role.RANCHER:
			return settlement.rancher_status()
		Role.MINER:
			return "Mining" if not settlement.mine_spots().is_empty() else "No mine here"
		Role.ARMORER:
			return settlement.armorer_status() if not settlement.armorer_spots().is_empty() else "No weapons bench here"
		Role.TAILOR:
			return settlement.tailor_status()
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
	if settlement != null and not armour.is_empty():
		settlement._return_armour(self, null)
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

func _process(_delta: float) -> void:
	_update_gun()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD or state == State.DOWN:
		_brake(delta)
		move_and_slide()
		_animate(delta)
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
	NpcStep.step_up(self)
	_animate(delta)


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
	_move_to(dest, walk_speed * 1.5, delta)  # a brisk walk to their new home (20.1)


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
	# A raid, and no raider in sight: guards on the ground go to where the
	# raiders are, rather than wait at their posts while the barn's emptied
	# (20.5); but only to raiders on their side of the walls, and a guard up a
	# tower stays up it (28.1)
	if role == Role.GUARD and settlement.raid_active() and not is_hungry() and not holds_tower():
		var near := _nearest_raid_raider()
		if near != null:
			_swing(false)
			_move_to(near.global_position, run_speed, delta)
			return
	# A raid: into the farmhouse, everyone but the guards
	if settlement.raid_active() and role != Role.GUARD:
		var shelter := settlement.get_node_or_null("Shelter") as Node3D
		_swing(false)
		_wander(shelter.global_position if shelter != null else _hangout(), 1.5, delta)
		return
	var shear := role == Role.FARMER and _shearing()
	if shear != _was_shearing:
		# Off to the sheep pen, or back to the fields: a fresh start
		_was_shearing = shear
		_goal = Vector3.INF
		state = State.IDLE
	if shear:
		# A fleece grown at the sheep pen (28): the first Farmer goes to shear
		_work_at(settlement.pen_to_shear().shear_spots(), 0.4, delta)
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
		Role.WOODCUTTER:
			_cut_wood(delta)
		Role.COOK:
			_cook(delta)
		Role.RANCHER:
			_tend(delta)
		Role.MINER:
			_dig(delta)
		Role.ARMORER:
			_forge(delta)
		Role.TAILOR:
			_sew(delta)


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
	# Working the soil: down on one knee
	_brake(delta)
	_working = true
	if _state_time > _state_length:
		_working = false
		_goal = Vector3.INF


func _patrol(delta: float) -> void:
	if _goal == Vector3.INF:
		# A guard post or tower of their own once some are built (one guard
		# each, in turn); otherwise walk the patrol points
		var posts := settlement.guard_posts()
		_spot = null
		_climbing = false
		if not posts.is_empty():
			# Guards with a gun take the towers first: up there, a machete
			# is no use (28.1)
			var guards := settlement.members().filter(func(s: Settler) -> bool: return s.role == Role.GUARD and s.has_arrived())
			var order := guards.filter(func(s: Settler) -> bool: return s.can_shoot()) + guards.filter(func(s: Settler) -> bool: return not s.can_shoot())
			var mine := maxi(order.find(self), 0)
			if mine < posts.size() and (can_shoot() or not is_raised(posts[mine])):
				_spot = posts[mine]
				_goal = _spot.global_position
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
		# Up a tower: to the foot of its stair first, then up it (28.1:
		# coming at it from the side, the way on was missed)
		var way := _way_up()
		var there := _move_to(way if way != Vector3.INF else _goal, walk_speed, delta)
		if (there and way == Vector3.INF) or _state_time > 60.0:
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
	var a := settlement.builder_assignment()
	if a.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	var job: Node3D = a[0]
	var site := job as ConstructionSite
	var spot := site.work_point() if site != null else job.global_position + job.global_basis.z * 1.3
	# Work at another of your places (27): off along the road to it
	if _far_from(spot):
		_go_far(spot, a[1] as Settlement, delta)
		return
	if _goal == Vector3.INF or state == State.IDLE or _goal.distance_to(spot) > 6.0:
		_goal = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spot)
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
	_face((_next_piece_at(site) if site != null else job.global_position) - global_position, delta)
	_swing(true)
	if _state_time > _state_length:
		_goal = Vector3.INF


## Woodcutters: to a spot in the woodlot, then chopping at the nearest tree.
func _cut_wood(delta: float) -> void:
	var spots := settlement.wood_spots()
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	if _goal == Vector3.INF or state == State.IDLE:
		_goal = _pick_from(spots, 1.5)
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		_swing(false)
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(10.0, 18.0)
		return
	_brake(delta)
	var tree := _nearest_tree(7.0)
	if tree != null:
		_face(tree.global_position - global_position, delta)
	_swing(true)
	if _state_time > _state_length:
		_goal = Vector3.INF


## Miners (23): at the rock face in the mine tunnel, swinging a pickaxe.
func _dig(delta: float) -> void:
	var spots := settlement.mine_spots()
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	if _goal == Vector3.INF or state == State.IDLE:
		# A spot of their own, in turn (one miner to a spot)
		var miners := settlement.members().filter(func(s: Settler) -> bool: return s.role == Role.MINER and s.has_arrived())
		var mine := maxi(miners.find(self), 0)
		_goal = spots[mine % spots.size()].global_position
		_work_facing = spots[mine % spots.size()].global_basis.z * -1.0
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		_swing(false)
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(14.0, 24.0)
		return
	_brake(delta)
	_face(_work_facing, delta)
	_swing(true)
	if _state_time > _state_length:
		state = State.IDLE


var _was_shearing := false


## Farmers (28): the first working Farmer here shears the sheep when a fleece
## has grown (the shearing itself is done each settlement hour).
func _shearing() -> bool:
	if role != Role.FARMER or settlement == null or is_hungry() or settlement.raid_active():
		return false
	if settlement.pen_to_shear() == null:
		return false
	var farmers := settlement.members().filter(func(s: Settler) -> bool: return s.role == Role.FARMER and s.has_arrived() and not s.is_hungry())
	return not farmers.is_empty() and farmers[0] == self


## Tailors (28): at the Tailor's Table, sewing.
func _sew(delta: float) -> void:
	var spots := settlement.tailor_spots()
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	_work_at(spots, 0.3, delta)


## Armorers (23.5): at the weapons bench, hammering.
func _forge(delta: float) -> void:
	var spots := settlement.armorer_spots()
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	if _goal == Vector3.INF or state == State.IDLE:
		var smiths := settlement.members().filter(func(s: Settler) -> bool: return s.role == Role.ARMORER and s.has_arrived())
		var mine := maxi(smiths.find(self), 0)
		_goal = spots[mine % spots.size()].global_position
		_work_facing = spots[mine % spots.size()].global_basis.z * -1.0
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		_swing(false)
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(14.0, 24.0)
		return
	_brake(delta)
	_face(_work_facing, delta)
	_swing(true)
	if _state_time > _state_length:
		state = State.IDLE


## Cooks (21.5): at the kitchen's stove, stirring.
func _cook(delta: float) -> void:
	var spots: Array[Node3D] = []
	for k in settlement.kitchens():
		spots.append_array(k.cook_spots())
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	_work_at(spots, 0.3, delta)


## Ranchers (21.5): from pen to pen, at the troughs.
func _tend(delta: float) -> void:
	var spots: Array[Node3D] = []
	for pen in settlement.pens():
		spots.append_array(pen.tend_spots())
	if spots.is_empty():
		_swing(false)
		_wander(_hangout(), 6.0, delta)
		return
	_work_at(spots, 0.8, delta)


## Walk to one of `spots`, then work there a while (swinging), then another.
func _work_at(spots: Array[Node3D], jitter: float, delta: float) -> void:
	if _goal == Vector3.INF or state == State.IDLE:
		_goal = _pick_from(spots, jitter)
		state = State.WALK
		_state_time = 0.0
	if state == State.WALK:
		_swing(false)
		if _move_to(_goal, walk_speed, delta) or _state_time > 60.0:
			state = State.WORK
			_state_time = 0.0
			_state_length = _rng.randf_range(10.0, 18.0)
		return
	_brake(delta)
	_swing(true)
	if _state_time > _state_length:
		_goal = Vector3.INF


func _nearest_tree(within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for n in get_tree().get_nodes_in_group("timber"):
		var t := n as Timber
		if t == null or t.cut:
			continue
		var d := t.global_position.distance_to(global_position)
		if d < best_d:
			best = t
			best_d = d
	return best


func _next_piece_at(site: ConstructionSite) -> Vector3:
	var i := clampi(site.built, 0, maxi(site.pieces.size() - 1, 0))
	return site.global_transform * site.pieces[i].origin if not site.pieces.is_empty() else site.global_position


## At work with their hands (a hammer, a pick, the stove…): animated by
## _animate (29).
func _swing(on: bool) -> void:
	_working = on


func _wander(around: Vector3, radius: float, delta: float) -> void:
	_working = false
	if _far_from(around):
		# Away at another place (a Builder, 27): home first
		_go_far(around, settlement, delta)
		return
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
	var best_d := sight_range()
	for n in get_tree().get_nodes_in_group("enemies"):
		var r := n as Node3D
		if r == null or (r.has_method("is_dead") and r.call("is_dead")):
			continue
		var d := global_position.distance_to(r.global_position)
		if d > best_d or r.global_position.distance_to(settlement.global_position) > settlement.defend_radius:
			continue
		if not sees(r):
			continue
		best = r
		best_d = d
	return best


# ---------------------------------------------------------------- towers (28.1)

## They've a gun with rounds in it or to load.
func can_shoot() -> bool:
	return gun != null and gun.weapon != null and not gun.weapon.melee and (magazine > 0 or ammo > 0)


## A guard spot up a tower (a deck, not a sandbagged post on the ground).
static func is_raised(spot: Node3D) -> bool:
	if spot == null or not is_instance_valid(spot):
		return false
	var b := spot.get_parent().get_parent() as Node3D if spot.get_parent() != null else null
	var floor_y := b.global_position.y if b != null else 0.0
	return spot.global_position.y - floor_y > RAISED


## Given a tower to man: they stay up it through a raid.
func holds_tower() -> bool:
	return role == Role.GUARD and is_raised(_spot)


## Up their tower now (on its deck, not on the stair).
func up_tower() -> bool:
	if not holds_tower():
		return false
	var p := _spot.global_position
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < 2.5 and absf(p.y - global_position.y) < 1.0


func sight_range() -> float:
	return tower_range if up_tower() else guard_range


## In sight: nothing in the way, or (up a tower) anyone along the wall it
## stands against, seen over its top.
func sees(n: Node3D) -> bool:
	if _can_see(n):
		return true
	return up_tower() and _on_my_wall(n.global_position) and _clear_but_walls(eyes.global_position, n.global_position + Vector3.UP * 1.2)


## Within ON_WALL of a wall length the tower stands against, or of the line
## it runs along (the rest of that side), within the tower's sight.
func _on_my_wall(p: Vector3) -> bool:
	if _tower_walls_for != _spot:
		_tower_walls_for = _spot
		_tower_walls.clear()
		var at := _spot.global_position
		for n in get_tree().get_nodes_in_group("settlement_buildings"):
			var b := n as Structure
			if b == null or b.definition == null or not WALL_IDS.has(b.definition.id) or b.is_queued_for_deletion():
				continue
			if Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length() > 6.0:
				continue
			var along := b.global_basis.x
			along.y = 0.0
			_tower_walls.append([b.global_position, along.normalized()])
	for w: Array in _tower_walls:
		var o: Vector3 = w[0]
		var along: Vector3 = w[1]
		var rel := Vector3(p.x - o.x, 0.0, p.z - o.z)
		var across := (rel - along * rel.dot(along)).length()
		if across <= ON_WALL and absf(rel.dot(along)) <= tower_range:
			return true
	return false


## Nothing but built walls (and the guard's own tower) between a and b.
func _clear_but_walls(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = [get_rid()]
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(a, b, PhysicsLayers.WORLD_SOLID, skip)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var s := Structure.from_collider(hit["collider"])
		var ok := s != null and s.definition != null and (WALL_IDS.has(s.definition.id) or s.definition.id == &"watchtower" or s.definition.id == &"guard_tower")
		if not ok:
			return false
		skip.append(hit["rid"])
	return false


## A built wall (fence, palisade or gate) between a and b (28.1).
func wall_between(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = [get_rid()]
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(a, b, PhysicsLayers.WORLD_SOLID, skip)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var s := Structure.from_collider(hit["collider"])
		if s != null and s.definition != null and WALL_IDS.has(s.definition.id):
			return true
		skip.append(hit["rid"])
	return false


## On the far side of this place's walls: a built wall in a straight line,
## or the way there runs out through one of its gates (Northwatch's own
## walls aren't built ones) (28.1).
func across_walls(p: Vector3) -> bool:
	if wall_between(global_position + Vector3.UP, p + Vector3.UP):
		return true
	var gates := get_tree().get_nodes_in_group("settlement_gates").filter(func(g: Node) -> bool:
		return not g.is_queued_for_deletion() and (g as SettlementGate).settlement() == settlement)
	if gates.is_empty():
		return false
	var map := get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, global_position, NavigationServer3D.map_get_closest_point(map, p), true)
	for g: Node in gates:
		var at := (g as Node3D).global_position
		for i in path.size() - 1:
			if Settlement._flat_distance_to_segment(at, path[i], path[i + 1]) < 1.5:
				return true
	return false


## In front of the foot of the stair up to their tower, while they're still
## on the ground and haven't got there yet; INF otherwise.
func _way_up() -> Vector3:
	if _climbing or not holds_tower() or _goal != _spot.global_position:
		return Vector3.INF
	if global_position.y > _spot.global_position.y - 1.5:
		return Vector3.INF
	var b := _spot.get_parent().get_parent() as Node3D
	var ramp := b.find_child("Ramp", true, false) as CollisionShape3D if b != null else null
	if ramp == null or not (ramp.shape is ConvexPolygonShape3D):
		return Vector3.INF
	var foot_z := -INF
	var xs := 0.0
	var n := 0
	for pt: Vector3 in (ramp.shape as ConvexPolygonShape3D).points:
		if pt.y < 0.01 and pt.z > foot_z + 0.01:
			foot_z = pt.z
			xs = 0.0
			n = 0
		if pt.y < 0.01 and absf(pt.z - foot_z) <= 0.01:
			xs += pt.x
			n += 1
	if n == 0:
		return Vector3.INF
	var way := ramp.global_transform * Vector3(xs / n, 0.0, foot_z + 1.0)
	way = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, way)
	if Vector2(way.x - global_position.x, way.z - global_position.z).length() < 0.7:
		_climbing = true  # at the foot: on up
		return Vector3.INF
	return way


## Seconds between shots with `w`: a quarter faster than before 28.1, and
## the same on paper.
static func shot_interval(w: WeaponDefinition) -> float:
	return maxf(60.0 / maxf(w.rounds_per_minute, 1.0), 0.45) / FIRE_RATE


## The nearest raider of this settlement's raid that's inside the farm, on
## this side of its walls (28.1).
func _nearest_raid_raider() -> Raider:
	var best: Raider = null
	var best_d := INF
	for v: Variant in settlement.raiders:
		if not is_instance_valid(v):
			continue
		var r := v as Raider
		if r.is_dead():
			continue
		if r.global_position.distance_to(settlement.global_position) > settlement.defend_radius:
			continue
		var d := r.global_position.distance_to(global_position)
		if d < best_d and not across_walls(r.global_position):
			best = r
			best_d = d
	return best


func _can_see(n: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eyes.global_position, n.global_position + Vector3.UP * 1.2, PhysicsLayers.WORLD_SOLID, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _fight(delta: float) -> void:
	var gone: bool = target == null or not is_instance_valid(target) or (target.has_method("is_dead") and bool(target.call("is_dead")))
	if gone or global_position.distance_to(target.global_position) > sight_range() * 1.3 \
			or target.global_position.distance_to(settlement.global_position) > settlement.defend_radius * 1.2:
		target = null
		_enter(State.IDLE)
		return
	var to := target.global_position - global_position
	# Up a tower they stay up it; on the ground they don't go out through
	# the walls after anyone (28.1)
	if not can_shoot() and ((holds_tower() and to.length() > 2.5) \
			or (to.length() > 1.6 and across_walls(target.global_position))):
		target = null
		_enter(State.IDLE)
		return
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
		if _cooldown <= 0.0 and sees(target):
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
		_act_once(&"Sword_Attack", 0.9)
		var info := DamageInfo.create(melee_damage, DamageInfo.Type.MELEE, self)
		info.direction = to.normalized()
		var h := HealthComponent.find_on(target)
		if h != null:
			h.apply_damage(info)


func _shoot(t: Node3D) -> void:
	var w := gun.weapon
	magazine -= 1
	_cooldown = shot_interval(w)
	_act_once(&"Pistol_Shoot", minf(_cooldown, 0.3))
	var from := eyes.global_position
	var aim := (t.global_position + Vector3.UP * 1.2 - from).normalized()  # where they look (28.1: was 1.1, under the sight line)
	var up := up_tower()
	var spread := deg_to_rad(1.5 + w.base_spread * 2.0) * (TOWER_SPREAD if up else 1.0)
	var space := get_world_3d().direct_space_state
	for p in w.pellets:
		var axis := aim.cross(Vector3.UP).normalized().rotated(aim, _rng.randf() * TAU)
		var dir := aim.rotated(axis, _rng.randf() * spread) if axis.length() > 0.5 else aim
		var skip: Array[RID] = [get_rid()]
		var hit := {}
		for i in 6:
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * w.max_range, PhysicsLayers.WORLD_SOLID | PhysicsLayers.NPCS, skip)
			hit = space.intersect_ray(q)
			# From a tower, over the top of its own walls (28.1)
			var s := Structure.from_collider(hit["collider"]) if not hit.is_empty() else null
			if up and s != null and s.definition != null and (WALL_IDS.has(s.definition.id) or s.definition.id in [&"watchtower", &"guard_tower"]):
				skip.append(hit["rid"])
				continue
			break
		if hit.is_empty():
			continue
		# Never their own place's buildings (28.1: a shot into the palisade
		# used to chip it)
		if Structure.from_collider(hit["collider"]) != null:
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
	# Keep to the path already chosen while the goal stays put: asking again
	# every moment can flip between two equal ways round a building, and
	# they'd dither at the fork (20.1)
	_repath -= delta
	if agent.target_position.distance_to(point) > 1.0 or (_repath <= 0.0 and agent.is_navigation_finished()):
		agent.target_position = point
		_repath = 0.3
	# There, and on the same level: not underneath a tower deck (22.1)
	if Vector2(point.x - global_position.x, point.z - global_position.z).length() <= agent.target_desired_distance \
			and absf(point.y - global_position.y) < 1.2:
		_brake(delta)
		return true
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05 and agent.is_navigation_finished():
		dir = Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	dir = dir.normalized()
	# Snagged on a door frame or a table (Increment 20.1): step aside; still
	# stuck after a few tries, hop to the next point on the path
	if _side_left > 0.0:
		_side_left -= delta
		dir = _side_dir
	# Judged by how much closer they got to the next point on the path in the
	# last moment (0.4 s), not by speed this instant: pressed against a corner they
	# jitter back and forth, and stepping aside doesn't get them any closer
	_probe_left -= delta
	if _probe_left <= 0.0:
		_probe_left = 0.4
		# Nothing to judge mid-step, or with a new point to head for
		if _side_left <= 0.0 and _probe_from != Vector3.INF and _probe_next.distance_to(next) < 0.1:
			var gained := Vector2(next.x - _probe_from.x, next.z - _probe_from.z).length() - Vector2(next.x - global_position.x, next.z - global_position.z).length()
			if gained >= speed * 0.4 * 0.3:
				_stuck = maxi(_stuck - 1, 0)
			else:
				_stuck += 1
				if _stuck >= 4:
					# A few tries and still getting nowhere: hop on to the next point
					_stuck = 0
					var hop := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, next)
					# Never through a fence, palisade or shut gate (28.1)
					if hop.distance_to(global_position) < 3.0 \
							and not wall_between(global_position + Vector3.UP * 0.5, hop + Vector3.UP * 0.5) \
							and not wall_between(global_position + Vector3.UP * 1.2, hop + Vector3.UP * 1.2):
						global_position = hop + Vector3.UP * 0.05
						velocity = Vector3.ZERO
				else:
					_side_dir = (dir.cross(Vector3.UP) * _away_from_wall(dir) - dir * 0.3).normalized()
					_side_left = 0.4
					_probe_left = 0.4
					agent.target_position = point + Vector3(0.01 * _stuck, 0, 0)  # a fresh path from here
		_probe_from = global_position if _side_left <= 0.0 else Vector3.INF
		_probe_next = next
	var weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, weight)
	velocity.z = lerpf(velocity.z, dir.z * speed, weight)
	_face(dir, delta)
	return false


## Which way to step aside (+1 or -1 along dir × up): away from the wall
## they've walked into, so a doorway's jamb sends them into the doorway. With
## nothing to go by, either way.
func _away_from_wall(dir: Vector3) -> float:
	var side := dir.cross(Vector3.UP)
	for i in get_slide_collision_count():
		var k := get_slide_collision(i)
		if k.get_normal().y < 0.5:
			var off := k.get_position() - global_position
			var along := side.dot(Vector3(off.x, 0, off.z))
			if absf(along) > 0.005:
				return -signf(along)
	return 1.0 if _rng.randf() < 0.5 else -1.0


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


## Further than this from where they're going, a settler's off on a long
## walk between your places (27).
const FAR_WALK := 170.0


func _far_from(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() > FAR_WALK


## The long walk to `dest` at another of your places (`place`), or home. As
## with newcomers (20.1), it's done off-screen when nobody's with them: they
## turn up at the end of the place's lane and walk in, or, with nobody there
## either, simply arrive.
func _go_far(dest: Vector3, place: Settlement, delta: float) -> void:
	_swing(false)
	if state != State.WALK:
		state = State.WALK
		_state_time = 0.0
	_goal = Vector3.INF
	_travel_check -= delta
	if _travel_check <= 0.0:
		_travel_check = 1.0
		if not _player_within(90.0):
			var lane := place.get_node_or_null("ArrivalPoint") as Node3D if place != null else null
			var to := dest
			if lane != null and _player_near_place(dest, 90.0) and global_position.distance_to(dest) > lane.global_position.distance_to(dest) + 2.0:
				to = lane.global_position
			elif _player_near_place(dest, 90.0):
				to = global_position
			if to != global_position:
				global_position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, to) + Vector3.UP * 0.1
				velocity = Vector3.ZERO
				state = State.IDLE
				return
	_move_to(dest, walk_speed * 1.5, delta)


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
	if body == null:
		return
	var seed_value := look_seed if look_seed != 0 else hash(settler_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	body.shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	body.trousers = TROUSERS[rng.randi() % TROUSERS.size()]
	body.boots = BOOTS[rng.randi() % BOOTS.size()]
	body.long_sleeves = rng.randf() < 0.55
	body.pick_looks(seed_value)
	body.rebuild()
	_parts.clear()
	for n in visual.find_children("*", "Node3D", true, false):
		var key := String(n.get_meta("part", n.name))
		if n.has_meta("slot"):
			if not _parts.has(key):
				_parts[key] = []
			(_parts[key] as Array).append(n)
	_update_visuals()


## A piece of their gear by name ("HardHat", "Pickaxe"…), or null (29).
func part(part_name: String) -> Node3D:
	var list: Array = _parts.get(part_name, [])
	return list[0] if not list.is_empty() else null


func _show(part_name: String, on: bool) -> void:
	for n: Node3D in _parts.get(part_name, []):
		n.visible = on


func _update_visuals() -> void:
	if not is_node_ready() or body == null:
		return
	for pair in [["Hat", role == Role.FARMER],
			["Helmet", role == Role.GUARD and armour.worn(ArmourSet.HEAD) == null],
			["HardHat", role == Role.BUILDER or role == Role.MINER], ["ToolBelt", role == Role.BUILDER or role == Role.ARMORER],
			["ChefHat", role == Role.COOK], ["Apron", role == Role.COOK or role == Role.TAILOR], ["CowboyHat", role == Role.RANCHER],
			["HeadLamp", role == Role.MINER], ["Goggles", role == Role.ARMORER]]:
		_show(pair[0], pair[1])
	# What they wear (22): over the clothes (29.1: as an outfit's pieces), a
	# leather coat the Ranger's, plate the Ranger's greyed with plates and
	# pauldrons, Wool Clothes the Peasant's, padded the Ranger's green (28);
	# a leather or padded cap as the Ranger's hood, a helmet as it was
	var head := armour.worn(ArmourSet.HEAD)
	var hood := head != null and _armour_kind(head) in ["leather", "padded"]
	body.wear(&"head", _armour_kind(head) if hood else "")
	_show("ArmourHead", head != null and not hood)
	if head != null and not hood:
		var look: Array = ARMOUR_LOOKS[_armour_kind(head)]
		for n: Node3D in _parts.get("ArmourHead", []):
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m := StandardMaterial3D.new()
				m.albedo_color = look[0]
				m.metallic = look[1]
				m.roughness = 0.6 if look[1] > 0.0 else 0.9
				(mi as MeshInstance3D).material_override = m
	for pair in [[ArmourSet.BODY, &"body"], [ArmourSet.LEGS, &"legs"]]:
		var it := armour.worn(pair[0])
		body.wear(pair[1], _armour_kind(it) if it != null else "")
	# Knee plates on plated trousers; a guard with no coat wears pauldrons
	var legs := armour.worn(ArmourSet.LEGS)
	_show("ArmourLegs", legs != null and _armour_kind(legs) == "plated")
	body.wear(&"shoulders", "guard" if role == Role.GUARD and armour.worn(ArmourSet.BODY) == null else "")
	_show("Gun", gun != null)
	_show("Machete", gun == null and role == Role.GUARD)
	_show("Hammer", gun == null and (role == Role.BUILDER or role == Role.ARMORER))
	_show("Axe", gun == null and role == Role.WOODCUTTER)
	_show("Pickaxe", gun == null and role == Role.MINER)
	if role not in [Role.BUILDER, Role.WOODCUTTER, Role.COOK, Role.RANCHER, Role.MINER, Role.ARMORER, Role.TAILOR, Role.FARMER]:
		_swing(false)


static func _armour_kind(it: ItemDefinition) -> String:
	var id := String(it.id)
	if id.begins_with("plated") or id.begins_with("scrap"):
		return "plated"
	if id.begins_with("wool"):
		return "wool"
	if id.begins_with("padded"):
		return "padded"
	return "leather"


# ---------------------------------------------------------------- animation (29)

## Their body's animation for what they're doing now.
func _animate(delta: float) -> void:
	if body == null or body.anim == null:
		return
	_act -= delta
	if state == State.DEAD or state == State.DOWN:
		body.play(&"Death01", 1.0, 0.15, false, false)
		return
	if _act > 0.0:
		return  # a shot or a blow playing out
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 2.6:
		body.play(&"Jog_Fwd", clampf(speed / 3.6, 0.7, 1.5))
	elif speed > 0.25:
		body.play(&"Walk", clampf(speed / 1.4, 0.6, 1.6))
	elif state == State.FIGHT:
		body.play(&"Pistol_Idle" if can_shoot() else &"Sword_Idle", 1.0, 0.2, false, false)
	elif _working:
		match role:
			Role.MINER, Role.WOODCUTTER:
				body.play(&"Sword_Attack", 0.8)
			Role.BUILDER, Role.ARMORER, Role.FARMER:
				body.play(&"Fixing_Kneeling", 1.0)
			_:
				body.play(&"Interact", 0.8)
	elif settlement != null and settlement.raid_active() and role != Role.GUARD and has_arrived():
		body.play(&"Crouch_Idle")
	else:
		body.play(&"Idle")


## A shot or a blow, played over whatever they were doing.
func _act_once(anim_name: StringName, seconds: float) -> void:
	if body == null or body.anim == null:
		return
	body.play(anim_name, maxf(body.length_of(anim_name) / maxf(seconds, 0.05), 0.5), 0.05, true)
	_act = seconds


## The gun points where they face (the hand's own turn would point it every
## which way): set after the animation's moved the hand, each frame.
func _update_gun() -> void:
	if gun == null:
		return
	for g: Node3D in _parts.get("Gun", []):
		if not g.visible:
			continue
		var hand := g.get_parent() as Node3D
		g.global_transform = Transform3D(visual.global_basis.orthonormalized(), hand.global_transform * Vector3(0, 0.08, 0))

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
	if not is_dead() and not is_down() and _act <= 0.0:
		_act_once(&"Hit_Chest", 0.3)
	# A guard hit by a raider fights back
	if role == Role.GUARD and has_arrived() and info != null and info.source is Node3D \
			and (info.source as Node).is_in_group("enemies") and state != State.FIGHT:
		target = info.source
		_enter(State.FIGHT)


func _on_died(info: DamageInfo) -> void:
	# Beaten by raiders at home: down, not dead
	if has_arrived() and info != null and info.source is Node and (info.source as Node).is_in_group("enemies"):
		_go_down()
		return
	_die_for_good()


func _go_down() -> void:
	target = null
	_swing(false)
	_enter(State.DOWN)
	down_hours = 0.0
	collision_layer = 0
	if settlement != null:
		settlement.on_settler_down(self)


## Beaten in a raid settled on paper (20.5): down, as if a raider had done it.
func knock_down() -> void:
	if is_down() or is_dead():
		return
	health.current_health = 0.0
	_go_down()


## Helped up (by the Settlement, after a player bandages them).
func help_up(health_fraction := 0.5) -> void:
	if not is_down():
		return
	health.revive(health_fraction)
	down_hours = 0.0
	collision_layer = PhysicsLayers.NPCS
	_enter(State.IDLE)
	_update_visuals()


## Left down too long.
func bleed_out() -> void:
	if not is_down():
		return
	state = State.DEAD
	_die_for_good()


func _die_for_good() -> void:
	var home := settlement
	_enter(State.DEAD)
	talk.enabled = false
	name_label.visible = false
	collision_layer = 0
	if home != null:
		if gun != null:
			home._return_gun(self, null)
		if not armour.is_empty():
			home._return_armour(self, null)
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
		"down": is_down(), "down_hours": down_hours,
		"armour": armour.to_data(),
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
	role = r as Role if r >= 0 and r <= Role.ARMORER else Role.NONE
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
	armour.from_data(data.get("armour", {}))
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
	_update_visuals()
	if _arrived and data.get("down") is bool and data["down"]:
		_go_down()
		down_hours = maxf(Settlement._num(data.get("down_hours"), 0.0), 0.0)


func _vanish_now() -> void:
	if spawned:
		queue_free()
	else:
		_vanish()
