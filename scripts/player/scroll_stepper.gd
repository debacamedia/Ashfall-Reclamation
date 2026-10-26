class_name ScrollStepper
extends RefCounted
## Turns scrolling into single steps (next / previous), for choosing weapons
## and build kits.
##
## A mouse wheel sends one event per notch; a Magic Mouse or trackpad on
## macOS sends a stream of pan gestures (with momentum) instead. Either way,
## one swipe or notch = one step:
##   - wheel notches: at most one step per `cooldown_msec`
##   - pan gestures: one step when a swipe starts; the rest of that swipe
##     (until it's been quiet for `gesture_gap_msec`) is ignored
##
## feed() returns +1 (down / next), -1 (up / previous) or 0.

var cooldown_msec := 180
var gesture_gap_msec := 220
## Pan movement smaller than this is ignored (resting fingers).
var pan_threshold := 0.05

var _last_step_msec := -100000
var _last_pan_msec := -100000
var _pan_stepped := false
var _pan_sum := 0.0


func feed(event: InputEvent, now_msec: int = -1) -> int:
	if now_msec < 0:
		now_msec = Time.get_ticks_msec()
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := (event as InputEventMouseButton).button_index
		if b != MOUSE_BUTTON_WHEEL_UP and b != MOUSE_BUTTON_WHEEL_DOWN:
			return 0
		if now_msec - _last_step_msec < cooldown_msec:
			return 0
		_last_step_msec = now_msec
		return 1 if b == MOUSE_BUTTON_WHEEL_DOWN else -1
	if event is InputEventPanGesture:
		var dy := (event as InputEventPanGesture).delta.y
		if now_msec - _last_pan_msec > gesture_gap_msec:
			_pan_stepped = false  # a new swipe
			_pan_sum = 0.0
		_last_pan_msec = now_msec
		if _pan_stepped:
			return 0
		_pan_sum += dy
		if absf(_pan_sum) < pan_threshold:
			return 0
		_pan_stepped = true
		_last_step_msec = now_msec
		return 1 if _pan_sum > 0.0 else -1
	return 0


## True for the events feed() looks at.
static func is_scroll(event: InputEvent) -> bool:
	if event is InputEventPanGesture:
		return true
	if event is InputEventMouseButton:
		var b := (event as InputEventMouseButton).button_index
		return b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN
	return false
