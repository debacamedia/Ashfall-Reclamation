class_name InputFrame
extends RefCounted
## One physics tick of player intent.
##
## Local input (PlayerInput), future network clients and tests all produce
## InputFrames. PlayerController.simulate() is the only consumer. Keeping
## intent as plain data is what lets the host run the same movement code for
## remote players in co-op.

var move := Vector2.ZERO   ## x = strafe (right +), y = forward/back (back +). Length <= 1.
var look := Vector2.ZERO   ## Radians this tick: x = yaw, y = pitch (down +).
var jump := false          ## True only on the tick jump was pressed.
var sprint := false
var crouch := false
var fire := false           ## Trigger held this tick.
var reload := false         ## True only on the tick reload was pressed.
var interact := false       ## Interact key held this tick.
var use_heal := false       ## True only on the tick the quick-heal key was pressed.
var aim := false            ## Aim-down-sights held this tick.
var slot := 0               ## Weapon slot (1-4) picked this tick, 0 = none.
var cycle := 0              ## Mouse wheel this tick: +1 next weapon, -1 previous.


## Compact form for sending to the host later.
func to_dict() -> Dictionary:
	return {"m": move, "l": look, "j": jump, "s": sprint, "c": crouch, "f": fire, "r": reload, "i": interact, "h": use_heal, "a": aim, "w": slot, "y": cycle}


## Builds a frame from untrusted data (e.g. a network peer). Values are
## clamped so a modified client can't move faster or spin impossibly.
static func from_dict(data: Dictionary) -> InputFrame:
	var frame := InputFrame.new()
	var move_value: Variant = data.get("m", Vector2.ZERO)
	var look_value: Variant = data.get("l", Vector2.ZERO)
	frame.move = (move_value as Vector2).limit_length(1.0) if move_value is Vector2 else Vector2.ZERO
	frame.look = (look_value as Vector2).clampf(-PI, PI) if look_value is Vector2 else Vector2.ZERO
	frame.jump = _strict_bool(data.get("j", false))
	frame.sprint = _strict_bool(data.get("s", false))
	frame.crouch = _strict_bool(data.get("c", false))
	frame.fire = _strict_bool(data.get("f", false))
	frame.reload = _strict_bool(data.get("r", false))
	frame.interact = _strict_bool(data.get("i", false))
	frame.use_heal = _strict_bool(data.get("h", false))
	frame.aim = _strict_bool(data.get("a", false))
	frame.slot = _small_int(data.get("w", 0), 0, 4)
	frame.cycle = _small_int(data.get("y", 0), -1, 1)
	return frame


## Only a real `true` counts; strings, numbers and nulls are treated as false.
static func _strict_bool(value: Variant) -> bool:
	return value is bool and value


## Whole numbers in [lo, hi] only; anything else becomes 0.
static func _small_int(value: Variant, lo: int, hi: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	var i := int(value)
	return i if i >= lo and i <= hi and float(i) == float(value) else 0
