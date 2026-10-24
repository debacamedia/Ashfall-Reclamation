class_name PlayerInput
extends Node
## Reads the local keyboard and mouse and produces one InputFrame per physics
## tick. Also owns mouse capture: Esc releases the mouse, clicking the game
## window captures it again. (A real pause menu arrives with the UI increment.)

signal mouse_capture_changed(captured: bool)

@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0022
@export var invert_y := false
## Press crouch once to crouch, again to stand (instead of holding).
@export var crouch_toggle := false

## True while a menu (inventory) is open: the mouse is free and gameplay
## input is ignored.
var ui_open := false

var _look_accumulator := Vector2.ZERO
var _crouch_latched := false
## After a click recaptures the mouse, ignore that click as a trigger pull.
var _fire_blocked_until_release := false


func _ready() -> void:
	capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if ui_open:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		var delta := (event as InputEventMouseMotion).relative * mouse_sensitivity
		if invert_y:
			delta.y = -delta.y
		_look_accumulator += delta
	elif event.is_action_pressed("pause"):
		release_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed() and not is_mouse_captured():
		capture_mouse()
		_fire_blocked_until_release = true
		get_viewport().set_input_as_handled()
	elif crouch_toggle and event.is_action_pressed("crouch") and is_mouse_captured():
		_crouch_latched = not _crouch_latched


## Called by PlayerController once per physics tick.
func gather() -> InputFrame:
	var frame := InputFrame.new()
	frame.crouch = _crouch_latched if crouch_toggle else false
	if ui_open or not is_mouse_captured():
		_look_accumulator = Vector2.ZERO
		return frame  # neutral frame while the mouse is free or a menu is open

	frame.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	frame.look = _look_accumulator
	frame.jump = Input.is_action_just_pressed("jump")
	frame.sprint = Input.is_action_pressed("sprint")
	if not crouch_toggle:
		frame.crouch = Input.is_action_pressed("crouch")
	var fire_held := Input.is_action_pressed("fire")
	if _fire_blocked_until_release:
		if not fire_held:
			_fire_blocked_until_release = false
		fire_held = false
	frame.fire = fire_held
	frame.reload = Input.is_action_just_pressed("reload")
	frame.interact = Input.is_action_pressed("interact")
	frame.use_heal = Input.is_action_just_pressed("use_medkit")
	frame.aim = Input.is_action_pressed("aim")
	_look_accumulator = Vector2.ZERO
	return frame


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_capture_changed.emit(true)


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(false)


## Opens or closes "menu mode" (mouse free, gameplay input ignored).
func set_ui_open(open: bool) -> void:
	ui_open = open
	if open:
		release_mouse()
	else:
		capture_mouse()
		# Don't treat the click that closed the menu as a trigger pull
		_fire_blocked_until_release = true
