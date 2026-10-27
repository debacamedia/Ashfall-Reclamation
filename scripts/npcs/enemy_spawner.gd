class_name EnemySpawner
extends Node3D
## Keeps up to `max_alive` enemies in the world. Each child Marker3D is a
## spawn point (and becomes that enemy's home). When an enemy dies, a
## replacement spawns after `respawn_delay`, at a point no player is near.
##
## In a big zone (Increment 15) a spawner can sleep: with `active_radius`
## set, its enemies only exist while a player is that close to one of its
## spawn points. When everyone's gone, enemies that aren't fighting are
## removed; when someone comes back, the spawner fills up again.
##
## AUTHORITY: spawning only happens where the game state lives (host).

signal enemy_spawned(enemy: Node3D)

@export var enemy_scene: PackedScene
@export var max_alive := 3
@export var respawn_delay := 20.0
## Spawn points closer than this to a player are skipped.
@export var min_player_distance := 25.0
## Set false to keep the level empty (e.g. in tests, or a peaceful mode).
@export var enabled := true
## Only keep enemies while a player is within this distance (m) of a spawn
## point. 0 = always.
@export var active_radius := 0.0

## True while no player is near enough (see active_radius).
var dormant := false

var _alive: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _check := 0.0
## How often (s) to check for players nearby.
const CHECK_INTERVAL := 1.0


func _ready() -> void:
	_rng.randomize()
	if not enabled:
		return
	# Wait one frame so the level (players, navigation) is fully in the tree
	await get_tree().process_frame
	if active_radius > 0.0 and not player_near():
		dormant = true
		return
	for i in max_alive:
		spawn_one()


func _process(delta: float) -> void:
	if not enabled or active_radius <= 0.0:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_INTERVAL
	var near := player_near()
	if near and dormant:
		dormant = false
		for i in max_alive - get_alive().size():
			spawn_one()
	elif not near:
		dormant = true
		# Anyone still chasing someone stays until they give up
		for e in get_alive():
			if not is_fighting(e):
				_alive.erase(e)
				e.queue_free()


## True if `enemy` is chasing or attacking someone.
static func is_fighting(enemy: Node) -> bool:
	var s: Variant = enemy.get("state")
	return s != null and (s == Raider.State.CHASE or s == Raider.State.ATTACK)


## True if a player is within active_radius of any spawn point.
func player_near() -> bool:
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		for p in get_spawn_points():
			if player.global_position.distance_to(p.global_position) <= active_radius:
				return true
	return false


func get_alive() -> Array[Node3D]:
	# Enemies can be freed while still listed here (corpses despawn after
	# 30 s, sooner than a long respawn_delay). Read each entry as a Variant:
	# a freed object can't be passed to anything typed Node3D.
	var still: Array[Node3D] = []
	for i in _alive.size():
		var e: Variant = _alive[i]
		if is_instance_valid(e) and not (e as Node3D).call("is_dead"):
			still.append(e)
	_alive = still
	return _alive


func get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child in get_children():
		if child is Marker3D:
			points.append(child)
	return points


## Spawns one enemy at a suitable point. Returns it, or null if none fit.
func spawn_one() -> Node3D:
	if enemy_scene == null or dormant or get_alive().size() >= max_alive:
		return null
	var point := _choose_point()
	if point == null:
		return null
	var enemy := enemy_scene.instantiate() as Node3D
	var offset := Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
	# Enemies join the spawner's parent: place them in its space (a site in a
	# zone isn't at the origin)
	var at := point.global_position + offset
	var parent3d := get_parent() as Node3D
	enemy.position = parent3d.to_local(at) if parent3d != null and parent3d.is_inside_tree() else at
	enemy.rotation.y = _rng.randf() * TAU
	if "home_position" in enemy:
		enemy.set("home_position", point.global_position)
	get_parent().add_child(enemy)
	_alive.append(enemy)
	if enemy.has_signal("killed"):
		enemy.connect("killed", _on_enemy_killed)
	enemy_spawned.emit(enemy)
	return enemy


func _choose_point() -> Node3D:
	var points := get_spawn_points()
	if points.is_empty():
		return null
	var players := get_tree().get_nodes_in_group("players")
	var safe: Array[Node3D] = []
	for p in points:
		var ok := true
		for player: Node3D in players:
			if player.global_position.distance_to(p.global_position) < min_player_distance:
				ok = false
				break
		if ok:
			safe.append(p)
	var choices := safe if not safe.is_empty() else points
	# Prefer the point with the fewest living enemies nearby
	choices.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _crowding(a) < _crowding(b))
	return choices[0]


func _crowding(point: Node3D) -> int:
	var n := 0
	for e in get_alive():
		if e.global_position.distance_to(point.global_position) < 8.0:
			n += 1
	return n


func _on_enemy_killed(enemy: Node3D) -> void:
	_alive.erase(enemy)  # stop tracking the corpse right away
	if not enabled:
		return
	get_tree().create_timer(respawn_delay).timeout.connect(func() -> void:
		if is_inside_tree() and enabled:
			spawn_one())
