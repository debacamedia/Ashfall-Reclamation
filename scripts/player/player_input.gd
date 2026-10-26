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
## Click aim (right mouse / Q) once to raise the sights, again to lower them.
## On by default: a Mac Magic Mouse can't hold right and left click at once.
## Off = hold to aim.
@export var aim_toggle := true

## True while a menu (inventory) is open: the mouse is free and gameplay
## input is ignored.
var ui_open := false
## Build mode (B): mouse look and movement as normal, but the mouse buttons,
## R, E and the number keys belong to BuildMode, not the gun.
var build_mode := false

var _look_accumulator := Vector2.ZERO
var _crouch_latched := false
## After a click recaptures the mouse, ignore that click as a trigger pull.
var _fire_blocked_until_release := false
## Toggle-aim state: true while the sights are "clicked up".
var _aim_latched := false
var _aim_was_held := false
## After a menu closes, ignore Interact until the key is released (the E
## press that closed a container must not reopen it).
var _interact_blocked_until_release := false
## Mouse-wheel weapon cycling waiting for the next tick (+1 / -1).
var _pending_cycle := 0
var _last_cycle_msec := -10000
var _scroll := ScrollStepper.new()
## Ignore wheel events closer together than this (a Magic Mouse swipe sends
## many) so one swipe moves one weapon.
@export var wheel_cooldown_msec := 180
## Ignore the aim press that recaptured the mouse.
var _aim_blocked_until_release := false


func _ready() -> void:
	capture_mouse()
	# Things that take the rifle out of your hands also drop toggled aim
	var player := get_parent() as PlayerController
	if player != null:
		if not player.is_node_ready():
			await player.ready
		player.ladder_grabbed.connect(func(_l: Ladder) -> void: cancel_aim())
		player.item_use_started.connect(func(_i: ItemDefinition, _d: float) -> void: cancel_aim())
		player.died.connect(func(_info: DamageInfo) -> void: cancel_aim())
		if player.weapon_slots != null:
			player.weapon_slots.switch_started.connect(func(_slot: int) -> void: cancel_aim())


## Magic Mouse / trackpad swipes arrive as pan gestures, which the GUI
## would otherwise swallow before _unhandled_input: catch them here. (In
## build mode BuildMode uses them to choose kits instead.)
func _input(event: InputEvent) -> void:
	if ui_open or build_mode or not event is InputEventPanGesture or not is_mouse_captured():
		return
	_cycle_from_scroll(event)
	get_viewport().set_input_as_handled()


func _cycle_from_scroll(event: InputEvent) -> void:
	_scroll.cooldown_msec = wheel_cooldown_msec
	var step := _scroll.feed(event)
	if step != 0:
		_last_cycle_msec = Time.get_ticks_msec()
		_pending_cycle = step


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
		_aim_blocked_until_release = true
		get_viewport().set_input_as_handled()
	elif crouch_toggle and event.is_action_pressed("crouch") and is_mouse_captured():
		_crouch_latched = not _crouch_latched
	elif ScrollStepper.is_scroll(event) and is_mouse_captured():
		_cycle_from_scroll(event)  # mouse wheel: one weapon per notch


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
	var interact_held := Input.is_action_pressed("interact")
	if _interact_blocked_until_release:
		if not interact_held:
			_interact_blocked_until_release = false
		interact_held = false
	frame.interact = interact_held
	frame.use_heal = Input.is_action_just_pressed("use_medkit")
	var aim_held := Input.is_action_pressed("aim")
	if _aim_blocked_until_release:
		if not aim_held:
			_aim_blocked_until_release = false
		aim_held = false
	var sprinting := frame.sprint and frame.move.y < -0.3
	frame.aim = update_aim(aim_held, sprinting)
	for i in range(1, 6):
		if Input.is_action_just_pressed("weapon_%d" % i):
			frame.slot = i
	frame.cycle = _pending_cycle
	_pending_cycle = 0
	_look_accumulator = Vector2.ZERO
	if build_mode:
		frame.fire = false
		frame.reload = false
		frame.interact = false
		frame.aim = false
		frame.slot = 0
		frame.cycle = 0
		frame.use_heal = false
	return frame


## Turns the aim button state into "wants to aim" for this tick. Toggle mode
## flips on each new press; sprinting lowers the sights. Hold mode passes the
## button straight through.
func update_aim(aim_held: bool, sprinting: bool) -> bool:
	var pressed := aim_held and not _aim_was_held
	_aim_was_held = aim_held
	if not aim_toggle:
		return aim_held and not sprinting
	if pressed:
		_aim_latched = not _aim_latched
	if sprinting:
		_aim_latched = false
	return _aim_latched


## Mouse wheel: queue one weapon step for the next tick (rate-limited).
func queue_cycle(direction: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cycle_msec < wheel_cooldown_msec:
		return
	_last_cycle_msec = now
	_pending_cycle = signi(direction)


## Lowers toggled sights (ladder, medkit, death).
func cancel_aim() -> void:
	_aim_latched = false


func is_aiming_toggled() -> bool:
	return _aim_latched


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
		# Don't treat the click or key that closed the menu as gameplay input
		_fire_blocked_until_release = true
		_interact_blocked_until_release = true
