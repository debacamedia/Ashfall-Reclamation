class_name HUD
extends CanvasLayer
## In-game overlay: dynamic crosshair with hit markers, weapon and ammo
## readout, and a debug readout (F3) showing movement state and speed.
## Health and interaction prompts join in later increments.
##
## Scene: res://scenes/ui/hud.tscn

## Set in the Inspector (or by the level) to the local player.
@export var player: PlayerController

@onready var _debug_label: Label = %DebugLabel
@onready var _crosshair: Crosshair = %Crosshair
@onready var _ammo_label: Label = %AmmoLabel
@onready var _weapon_label: Label = %WeaponLabel

var _weapon: HitscanWeapon


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.weapon != _weapon:
		_bind_weapon(player.weapon)

	if _weapon != null:
		_crosshair.spread_degrees = _weapon.get_current_spread_degrees()
		_crosshair.camera_fov = player.camera.fov
		if _weapon.is_reloading:
			_ammo_label.text = "RELOADING  %d%%" % roundi(_weapon.get_reload_progress() * 100.0)

	if _debug_label.visible:
		_debug_label.text = "%s\n%.1f m/s\npos %s" % [
			player.get_state_name(),
			player.get_horizontal_speed(),
			player.global_position.snappedf(0.1),
		]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible


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
