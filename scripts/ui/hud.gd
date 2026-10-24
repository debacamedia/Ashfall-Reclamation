class_name HUD
extends CanvasLayer
## In-game overlay: health bar, damage feedback (red flash, low-health pulse,
## direction arcs), death screen with respawn countdown, dynamic crosshair
## with hit markers, weapon and ammo readout, and a debug readout (F3).
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

var _weapon: HitscanWeapon
var _health: HealthComponent
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
