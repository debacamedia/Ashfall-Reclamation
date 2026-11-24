class_name GameSpeed
## A developer's fast-forward (Increment 30): F4 in a debug build (Run from
## the Godot editor) steps the game through 1×, 2× and 4× speed, for
## testing things that take a while: crops, settlement hours, raids.
##
## Everything goes faster together. Engine.time_scale stretches each frame's
## time, and the physics ticks per second go up by the same factor, so every
## physics step is still 1/60 s of game time: movement, collisions, guns and
## AI behave exactly as at 1×, just more of them a second. Sound plays at its
## normal pitch. Not saved: each launch starts at 1×.

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]


## Whether the fast-forward is allowed: only in a debug build (Run from the
## editor), never in a released game.
static func allowed() -> bool:
	return OS.is_debug_build()


static func current() -> float:
	return Engine.time_scale


## The project's own physics rate (60), whatever the speed now.
static func base_ticks() -> int:
	return int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))


static func set_speed(speed: float) -> void:
	speed = maxf(speed, 0.1)
	Engine.time_scale = speed
	Engine.physics_ticks_per_second = roundi(base_ticks() * speed)
	# Room to catch up on a slow frame at the higher rate
	Engine.max_physics_steps_per_frame = maxi(8, ceili(8 * speed))


## The next speed in SPEEDS after the current one (back to 1× after the last).
static func cycle() -> float:
	var i := SPEEDS.find(current())
	var next: float = SPEEDS[(i + 1) % SPEEDS.size()] if i >= 0 else 1.0
	set_speed(next)
	return next
