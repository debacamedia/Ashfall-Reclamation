class_name GameMode
extends Node
## The level's rules for players: death bookkeeping and respawning.
##
## AUTHORITY: GameMode runs where the game state lives — the local machine in
## single-player, the host in co-op. Players only *request* a respawn (by
## pressing jump while dead); GameMode decides when it is allowed and where
## they come back. More rules (death penalties, spawn selection between
## settlements, co-op revives) will live here too.
##
## Lives in the level scene; see levels/outpost_17/outpost_17.tscn.

signal player_died(player: PlayerController, info: DamageInfo)
signal player_respawned(player: PlayerController)

## Seconds a dead player must wait before they can respawn.
@export var respawn_delay := 5.0
## Where players come back to life.
@export var spawn_point: Node3D
## The player(s) this game mode manages. In co-op, joined players are added
## with register_player().
@export var players: Array[PlayerController] = []

## player -> time of death (seconds, from Time.get_ticks_msec)
var _death_times := {}
## Cause text for the HUD, per player.
var _death_causes := {}


func _ready() -> void:
	for p in players:
		register_player(p)


func register_player(player: PlayerController) -> void:
	if player == null:
		return
	if not players.has(player):
		players.append(player)
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died.bind(player))
		player.respawn_requested.connect(_on_respawn_requested.bind(player))


## Seconds left before `player` may respawn (0 when allowed or alive).
func get_respawn_time_left(player: PlayerController) -> float:
	if not _death_times.has(player):
		return 0.0
	var elapsed := (Time.get_ticks_msec() - int(_death_times[player])) / 1000.0
	return maxf(respawn_delay - elapsed, 0.0)


func can_respawn(player: PlayerController) -> bool:
	return player.is_dead() and get_respawn_time_left(player) <= 0.0


func get_death_cause(player: PlayerController) -> String:
	return _death_causes.get(player, "")


## Respawns immediately if allowed. Returns true on success.
func try_respawn(player: PlayerController) -> bool:
	if not can_respawn(player):
		return false
	var spawn := spawn_point.global_transform if spawn_point != null else Transform3D.IDENTITY
	_death_times.erase(player)
	_death_causes.erase(player)
	player.respawn_at(spawn)
	player_respawned.emit(player)
	return true


func _on_player_died(info: DamageInfo, player: PlayerController) -> void:
	_death_times[player] = Time.get_ticks_msec()
	_death_causes[player] = describe_cause(info)
	player_died.emit(player, info)


func _on_respawn_requested(player: PlayerController) -> void:
	try_respawn(player)


## Human-readable cause of death for the HUD.
static func describe_cause(info: DamageInfo) -> String:
	if info == null:
		return "You died"
	if info.source != null:
		var message: Variant = info.source.get("death_message")
		if message is String and message != "":
			return message
	match info.type:
		DamageInfo.Type.FALL:
			return "You fell to your death"
		DamageInfo.Type.ENVIRONMENT:
			return "You were consumed by the wasteland"
		DamageInfo.Type.EXPLOSIVE:
			return "Killed by an explosion"
	if info.source != null:
		var source_name: Variant = info.source.get("display_name")
		if source_name is String and source_name != "":
			return "Killed by %s" % source_name
		return "Killed by %s" % info.source.name
	match info.type:
		DamageInfo.Type.MELEE:
			return "Beaten to death"
	return "You died"
