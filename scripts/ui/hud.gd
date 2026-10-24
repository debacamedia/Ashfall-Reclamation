class_name HUD
extends CanvasLayer
## In-game overlay: crosshair and a debug readout (F3) showing the player's
## movement state and speed. Health, ammo and prompts join in later increments.
##
## Scene: res://scenes/ui/hud.tscn

## Set in the Inspector (or by the level) to the local player.
@export var player: PlayerController

@onready var _debug_label: Label = %DebugLabel


func _process(_delta: float) -> void:
	if player == null or not _debug_label.visible:
		return
	_debug_label.text = "%s\n%.1f m/s\npos %s" % [
		player.get_state_name(),
		player.get_horizontal_speed(),
		player.global_position.snappedf(0.1),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
