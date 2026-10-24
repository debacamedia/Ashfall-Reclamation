class_name HUD
extends CanvasLayer
## In-game overlay: health bar, damage feedback (red flash, low-health pulse,
## direction arcs), death screen with respawn countdown, dynamic crosshair
## with hit markers, weapon and ammo readout, interaction prompt with hold
## progress, pickup notices, carried resources, UI sounds, debug readout (F3).
##
## Scene: res://scenes/ui/hud.tscn

## Set in the Inspector (or by the level) to the local player.
@export var player: PlayerController
## The level's GameMode, for the respawn countdown and cause of death.
@export var game_mode: GameMode
## Health fraction below which the screen edges pulse red.
@export var low_health_threshold := 0.3

@onready var _debug_label: Label = %DebugLabel
@onready var _crosshair: Crosshair = %Crosshair
@onready var _ammo_label: Label = %AmmoLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _health_label: Label = %HealthLabel
@onready var _health_fill: ColorRect = %HealthFill
@onready var _health_trail: ColorRect = %HealthTrail
@onready var _damage_vignette: TextureRect = %DamageVignette
@onready var _damage_indicator: DamageIndicator = %DamageIndicator
@onready var _death_screen: Control = %DeathScreen
@onready var _death_cause: Label = %DeathCause
@onready var _respawn_prompt: Label = %RespawnPrompt
@onready var _prompt_label: Label = %PromptLabel
@onready var _prompt_reason: Label = %PromptReason
@onready var _hold_bar: ProgressBar = %HoldBar
@onready var _notices: VBoxContainer = %Notices
@onready var _quick_slot: Label = %QuickSlotLabel
@onready var _use_label: Label = %UseLabel
@onready var _use_bar: ProgressBar = %UseBar
@onready var inventory_screen: InventoryScreen = %InventoryScreen
@onready var _ui_sound: AudioStreamPlayer = %UISound

const SOUND_HIT := preload("res://assets/audio/ui_hit.wav")
const SOUND_KILL := preload("res://assets/audio/ui_kill.wav")
const SOUND_DENIED := preload("res://assets/audio/ui_denied.wav")

var _weapon: HitscanWeapon
var _health: HealthComponent
var _interactor: PlayerInteractor
var _inventory: PlayerInventory
var _player_signals_bound: PlayerController = null
var _flash := 0.0
var _pulse_time := 0.0
var _trail_fraction := 1.0
var _bar_width := 0.0


func _ready() -> void:
	_bar_width = _health_fill.size.x
	_death_screen.visible = false
	_damage_vignette.modulate.a = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	if player.weapon != _weapon:
		_bind_weapon(player.weapon)
	if player.health != _health:
		_bind_health(player.health)
		_damage_indicator.player = player
	if player.interactor != _interactor:
		_bind_interactor(player.interactor)
	if player.inventory != _inventory:
		_bind_inventory(player.inventory)
	if _player_signals_bound != player:
		_player_signals_bound = player
		player.item_use_refused.connect(func(_r: String) -> void: _play_ui(SOUND_DENIED))
		inventory_screen.player = player
	_update_prompt()
	_update_item_use()
	_update_notices(delta)

	if _weapon != null:
		_crosshair.spread_degrees = _weapon.get_current_spread_degrees()
		_crosshair.camera_fov = player.camera.fov
		if _weapon.is_reloading:
			_ammo_label.text = "RELOADING  %d%%" % roundi(_weapon.get_reload_progress() * 100.0)

	_update_health_visuals(delta)
	_update_death_screen()

	if _debug_label.visible:
		_debug_label.text = "%s\n%.1f m/s\npos %s\nHP %.1f" % [
			player.get_state_name(),
			player.get_horizontal_speed(),
			player.global_position.snappedf(0.1),
			player.health.current_health,
		]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible


# ---------------------------------------------------------------- health

func _bind_health(health: HealthComponent) -> void:
	if _health != null:
		_health.health_changed.disconnect(_on_health_changed)
		_health.damaged.disconnect(_on_damaged)
	_health = health
	if health == null:
		return
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	_trail_fraction = health.get_fraction()
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_label.text = "%d" % ceili(current)
	var fraction := current / maximum if maximum > 0.0 else 0.0
	_health_fill.size.x = _bar_width * fraction
	_health_fill.color = Color(0.85, 0.2, 0.15) if fraction <= low_health_threshold else Color(0.85, 0.85, 0.8)


func _on_damaged(amount: float, info: DamageInfo) -> void:
	_flash = clampf(_flash + amount / 40.0, 0.25, 0.8)
	var direction := Vector3.ZERO
	if info.source is Node3D and is_instance_valid(info.source):
		direction = (info.source as Node3D).global_position - player.global_position
	elif info.direction != Vector3.ZERO and info.type != DamageInfo.Type.FALL:
		direction = -info.direction
	if direction != Vector3.ZERO:
		_damage_indicator.add_hit(direction)


func _update_health_visuals(delta: float) -> void:
	if _health == null:
		return
	# Damage flash plus a slow pulse while health is low
	_flash = move_toward(_flash, 0.0, delta * 1.2)
	var fraction := _health.get_fraction()
	var pulse := 0.0
	if fraction <= low_health_threshold and not _health.is_dead():
		_pulse_time += delta
		pulse = (0.25 + 0.15 * sin(_pulse_time * 4.0)) * (1.0 - fraction / low_health_threshold * 0.5)
	_damage_vignette.modulate.a = clampf(maxf(_flash, pulse), 0.0, 1.0)
	# The pale "trail" shows recent damage, catching up after a moment
	_trail_fraction = move_toward(_trail_fraction, fraction, delta * 0.6) if _trail_fraction > fraction else fraction
	_health_trail.size.x = _bar_width * _trail_fraction


func _update_death_screen() -> void:
	var dead := player.is_dead()
	_death_screen.visible = dead
	_crosshair.visible = not dead
	if not dead:
		return
	var left := game_mode.get_respawn_time_left(player) if game_mode != null else 0.0
	_death_cause.text = game_mode.get_death_cause(player) if game_mode != null else ""
	_respawn_prompt.text = "Respawn in %d" % ceili(left) if left > 0.0 else "Press SPACE to respawn"


# ---------------------------------------------------------------- weapon

func _bind_weapon(weapon: HitscanWeapon) -> void:
	if _weapon != null:
		_weapon.ammo_changed.disconnect(_on_ammo_changed)
		_weapon.hit_confirmed.disconnect(_on_hit_confirmed)
	_weapon = weapon
	_ammo_label.visible = weapon != null
	_weapon_label.visible = weapon != null
	if weapon == null:
		return
	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	_weapon_label.text = weapon.definition.display_name.to_upper()
	_on_ammo_changed(weapon.ammo_in_magazine, weapon.reserve_ammo)


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [in_magazine, reserve]
	_ammo_label.modulate = Color(1.0, 0.4, 0.3) if in_magazine == 0 else Color.WHITE


func _on_hit_confirmed(_target: Node, _damage: float, killed: bool, zone_multiplier: float) -> void:
	_crosshair.show_hit_marker(killed, zone_multiplier > 1.0)
	_play_ui(SOUND_KILL if killed else SOUND_HIT)


# ---------------------------------------------------------------- interaction

func _bind_interactor(interactor: PlayerInteractor) -> void:
	if _interactor != null:
		_interactor.interaction_refused.disconnect(_on_interaction_refused)
	_interactor = interactor
	if interactor != null:
		interactor.interaction_refused.connect(_on_interaction_refused)


func _update_prompt() -> void:
	var target := _interactor.focused if _interactor != null else null
	if target == null or not is_instance_valid(target) or player.is_dead():
		_prompt_label.visible = false
		_prompt_reason.visible = false
		_hold_bar.visible = false
		return
	_prompt_label.visible = true
	var key := "Hold E" if target.hold_time > 0.0 else "E"
	_prompt_label.text = "[%s]  %s" % [key, target.get_prompt(player)]
	var reason := target.get_block_reason(player)
	_prompt_reason.visible = reason != ""
	_prompt_reason.text = reason
	_prompt_label.modulate = Color(1, 1, 1, 0.5) if reason != "" else Color.WHITE
	_hold_bar.visible = _interactor.hold_progress >= 0.0
	_hold_bar.value = maxf(_interactor.hold_progress, 0.0) * 100.0


func _on_interaction_refused(_target: Interactable, _reason: String) -> void:
	_play_ui(SOUND_DENIED)


# ---------------------------------------------------------------- inventory

func _bind_inventory(inventory: PlayerInventory) -> void:
	if _inventory != null:
		_inventory.item_received.disconnect(_on_item_received)
		_inventory.contents_changed.disconnect(_on_inventory_changed)
	_inventory = inventory
	if inventory != null:
		inventory.item_received.connect(_on_item_received)
		inventory.contents_changed.connect(_on_inventory_changed)
	_on_inventory_changed(PackedInt32Array())


func _on_inventory_changed(_slots: PackedInt32Array) -> void:
	var medkits := _inventory.count_medical() if _inventory != null else 0
	_quick_slot.text = "[H]  MEDKIT ×%d" % medkits
	_quick_slot.modulate = Color.WHITE if medkits > 0 else Color(1, 1, 1, 0.35)


func _update_item_use() -> void:
	var progress := player.get_item_use_progress()
	_use_bar.visible = progress >= 0.0
	_use_label.visible = progress >= 0.0
	if progress >= 0.0:
		_use_bar.value = progress * 100.0
		_use_label.text = "Using %s…  (fire or sprint to cancel)" % player.get_item_in_use().display_name


func _on_item_received(item: ItemDefinition, quantity: int) -> void:
	var text := "+%d %s" % [quantity, item.display_name]
	var notice := Label.new()
	notice.text = text
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_constant_override("outline_size", 5)
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	notice.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	notice.set_meta("time_left", 2.5)
	_notices.add_child(notice)
	while _notices.get_child_count() > 5:
		_notices.get_child(0).free()


func _update_notices(delta: float) -> void:
	for notice in _notices.get_children():
		var left: float = notice.get_meta("time_left") - delta
		notice.set_meta("time_left", left)
		notice.modulate.a = clampf(left / 0.6, 0.0, 1.0)
		if left <= 0.0:
			notice.queue_free()


func _play_ui(stream: AudioStream) -> void:
	_ui_sound.stream = stream
	_ui_sound.play()
