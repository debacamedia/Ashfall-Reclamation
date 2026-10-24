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


## Compact form for sending to the host later.
func to_dict() -> Dictionary:
	return {"m": move, "l": look, "j": jump, "s": sprint, "c": crouch}


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
	return frame


## Only a real `true` counts; strings, numbers and nulls are treated as false.
static func _strict_bool(value: Variant) -> bool:
	return value is bool and value
