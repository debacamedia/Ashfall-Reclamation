class_name PlayerAudio
extends Node3D
## The player's own sounds: footsteps (by distance walked), landing, getting hurt, a heartbeat at low health, the death
## sting, pickup and item-use sounds, ladder rungs, raising the sights, and
## tools at work while crafting (saw, hammer, file: Resource Pack 3).
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

const CRAFT_SAW := preload("res://assets/ashfall_pack_v3/sets/craft_saw.tres")
const CRAFT_HAMMER := preload("res://assets/ashfall_pack_v3/sets/craft_hammer.tres")
const CRAFT_FILE := preload("res://assets/ashfall_pack_v3/sets/craft_file.tres")
const CRAFT_RUMMAGE := preload("res://assets/ashfall_pack_v3/sets/rummage.tres")
const CRAFT_DONE := preload("res://assets/ashfall_pack_v3/audio/craft_complete.wav")

var _distance := 0.0
var _craft: AudioStreamPlayer
var _craft_tools: Array[AudioStream] = []
var _craft_next := 0.0
var _craft_turn := 0
## Tool sounds played while crafting (used by tests).
var craft_sound_count := 0
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
	_craft = AudioStreamPlayer.new()
	_craft.name = "CraftSound"
	_craft.bus = &"SFX"
	_craft.volume_db = -9.0
	add_child(_craft)
	_player.crafting_started.connect(func(recipe: RecipeDefinition, _d: float) -> void:
		_craft_tools = tools_for(recipe)
		_craft_next = 0.15)
	_player.crafting_finished.connect(func(_r: RecipeDefinition) -> void:
		_craft_tools = []
		_craft.stream = CRAFT_DONE
		_craft.play())
	_player.crafting_cancelled.connect(func(_r: RecipeDefinition) -> void: _craft_tools = [])
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

	# Tools at work while a craft runs (it keeps going between items of a batch)
	if not _craft_tools.is_empty() and _player.get_crafting_progress() >= 0.0:
		_craft_next -= delta
		if _craft_next <= 0.0:
			_craft.stream = _craft_tools[_craft_turn % _craft_tools.size()]
			_craft.play()
			_craft_turn += 1
			craft_sound_count += 1
			_craft_next = randf_range(0.35, 0.6)

	var low := _player.health.get_fraction() <= heartbeat_threshold and not _player.is_dead()
	if low and not _heartbeat.playing:
		_heartbeat.play()
	elif not low and _heartbeat.playing:
		_heartbeat.stop()


## The tools you hear making a recipe: sawing and hammering for wood and
## structures, filing and hammering for gun parts and ammo, rummaging for
## medical supplies.
static func tools_for(recipe: RecipeDefinition) -> Array[AudioStream]:
	match recipe.category:
		RecipeDefinition.Category.MATERIALS, RecipeDefinition.Category.STRUCTURES:
			return [CRAFT_SAW, CRAFT_HAMMER, CRAFT_SAW]
		RecipeDefinition.Category.MEDICAL:
			return [CRAFT_RUMMAGE]
		_:
			return [CRAFT_FILE, CRAFT_HAMMER]


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
