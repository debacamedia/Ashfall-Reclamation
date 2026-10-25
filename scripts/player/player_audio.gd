class_name PlayerAudio
extends Node3D
## The player's own sounds: footsteps (by distance walked), landing, getting
## hurt, a heartbeat at low health, the death sting, pickup and item-use
## sounds, ladder rungs and raising the sights.
## Purely presentation: reads the player, never changes game state.
##
## Child of the Player scene; its sound players are child nodes.

## Metres between footsteps when walking (sprinting adds 25%). At walk speed
## (4.5 m/s) 1.3 m gives ~3.5 steps a second.
@export var step_length := 1.3
## Health fraction at or below which the heartbeat plays.
@export var heartbeat_threshold := 0.3

@onready var _player: PlayerController = get_parent()
@onready var _footsteps: AudioStreamPlayer3D = %Footsteps
@onready var _land: AudioStreamPlayer3D = %Land
@onready var _hurt: AudioStreamPlayer = %Hurt
@onready var _heartbeat: AudioStreamPlayer = %Heartbeat
@onready var _death: AudioStreamPlayer = %Death
@onready var _pickup: AudioStreamPlayer = %Pickup
@onready var _ladder_step: AudioStreamPlayer3D = get_node_or_null("%LadderStep")
@onready var _aim: AudioStreamPlayer = get_node_or_null("%AimSound")
@onready var _draw: AudioStreamPlayer = get_node_or_null("%DrawSound")

var _distance := 0.0
## How many footstep sounds have played (used by tests).
var footstep_count := 0


func _ready() -> void:
	# Children are ready before their parent; wait for the player's @onready vars
	if not _player.is_node_ready():
		await _player.ready
	_player.landed.connect(_on_landed)
	_player.died.connect(func(_info: DamageInfo) -> void:
		_heartbeat.stop()
		_death.play())
	_player.respawned.connect(func() -> void: _death.stop())
	_player.health.damaged.connect(_on_damaged)
	if _player.inventory != null:
		_player.inventory.item_received.connect(_on_item_received)
	if _ladder_step != null:
		_player.ladder_step.connect(_ladder_step.play)
		_player.ladder_grabbed.connect(func(_l: Ladder) -> void: _ladder_step.play())
	if _aim != null:
		_player.aim_changed.connect(func(aiming: bool) -> void:
			if aiming:
				_aim.play())
	if _draw != null and _player.weapon_slots != null:
		_player.weapon_slots.switch_started.connect(func(_slot: int) -> void: _draw.play())
	_player.weapon_picked_up.connect(func(def: WeaponDefinition) -> void:
		var item := ItemDatabase.find_weapon_item(def.id)
		if item != null and item.pickup_sound != null:
			_pickup.stream = item.pickup_sound
			_pickup.play())
	_player.item_use_finished.connect(func(item: ItemDefinition) -> void:
		if item.use_sound != null:
			_pickup.stream = item.use_sound
			_pickup.play())


func _physics_process(delta: float) -> void:
	if _player.is_dead():
		return
	var speed := _player.get_horizontal_speed()
	if _player.is_on_floor() and speed > 0.5:
		_distance += speed * delta
		var stride := step_length * (1.25 if _player.movement_state == PlayerController.MovementState.SPRINTING else 1.0)
		if _distance >= stride:
			_distance = 0.0
			_footsteps.volume_db = -17.0 if _player.is_crouching else -10.0
			_footsteps.play()
			footstep_count += 1
	else:
		_distance = step_length * 0.6  # first step comes quickly when starting to move

	var low := _player.health.get_fraction() <= heartbeat_threshold and not _player.is_dead()
	if low and not _heartbeat.playing:
		_heartbeat.play()
	elif not low and _heartbeat.playing:
		_heartbeat.stop()


func _on_landed(impact_speed: float) -> void:
	if impact_speed > 3.0:
		_land.volume_db = clampf(-12.0 + impact_speed * 1.2, -12.0, 2.0)
		_land.play()


func _on_damaged(_amount: float, info: DamageInfo) -> void:
	if info.type != DamageInfo.Type.ENVIRONMENT or not _hurt.playing:
		_hurt.play()


func _on_item_received(item: ItemDefinition, _quantity: int) -> void:
	if item.pickup_sound != null:
		_pickup.stream = item.pickup_sound
		_pickup.play()
