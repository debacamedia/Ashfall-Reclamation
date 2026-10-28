class_name UiScale
extends RefCounted
## How big the interface is drawn (Increment 16.7).
##
## The project stretches its 2D interface with the window ("canvas_items"),
## so text and screens keep their size on a Retina Mac or in full screen.
## On top of that the player picks a size: Ctrl/Cmd + = bigger, Ctrl/Cmd + -
## smaller, Ctrl/Cmd + 0 back to the default. It's saved in
## user://settings.cfg and never goes so big that the inventory and
## container windows wouldn't fit (the interface always has at least
## MIN_SPACE of room).

const SETTINGS := "user://settings.cfg"
const DEFAULT := 1.25
const MIN := 0.8
const STEP := 0.05
## The interface is laid out for this much room at the most.
const BASE := Vector2(1600, 900)
## …and needs at least this much (the container window is 1120 × 560).
const MIN_SPACE := Vector2(1280, 720)


static func saved() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return DEFAULT
	var v: Variant = cfg.get_value("ui", "scale", DEFAULT)
	return float(v) if (v is float or v is int) else DEFAULT


static func save(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "scale", value)
	cfg.save(SETTINGS)


## The biggest size that still leaves MIN_SPACE in a window this big.
static func largest_for(window_size: Vector2) -> float:
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return DEFAULT
	var stretch := minf(window_size.x / BASE.x, window_size.y / BASE.y)
	return maxf(MIN, minf(window_size.x / (stretch * MIN_SPACE.x), window_size.y / (stretch * MIN_SPACE.y)))


## Applies `wanted` (clamped) to the window. Returns what was applied.
static func apply(window: Window, wanted: float) -> float:
	if window == null:
		return wanted
	var v := clampf(wanted, MIN, largest_for(Vector2(window.size)))
	window.content_scale_factor = v
	return v
