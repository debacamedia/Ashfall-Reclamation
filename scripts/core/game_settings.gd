class_name GameSettings
extends RefCounted
## The player's settings (Increment 33.1): mouse speed, sound, full screen,
## and the interface size (UiScale's). Kept in user://settings.cfg beside
## the interface size, outside the project, so updates never touch them.
## Set from the main menu's and the pause menu's Settings.

const SETTINGS := UiScale.SETTINGS
const MOUSE_MIN := 0.4
const MOUSE_MAX := 2.5

## Mouse look speed, times the default.
static var mouse_scale := 1.0
## Master volume, 0 to 1.
static var volume := 1.0
static var fullscreen := false
static var _loaded := false


static func load_all() -> void:
	var cfg := ConfigFile.new()
	_loaded = true
	if cfg.load(SETTINGS) != OK:
		return
	mouse_scale = clampf(_num(cfg.get_value("game", "mouse", 1.0), 1.0), MOUSE_MIN, MOUSE_MAX)
	volume = clampf(_num(cfg.get_value("game", "volume", 1.0), 1.0), 0.0, 1.0)
	var fs: Variant = cfg.get_value("game", "fullscreen", false)
	fullscreen = fs is bool and fs


static func ensure_loaded() -> void:
	if not _loaded:
		load_all()


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else fallback


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("game", "mouse", mouse_scale)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "fullscreen", fullscreen)
	cfg.save(SETTINGS)


## Puts the saved settings into effect (sound and full screen; the mouse is
## read as you look, the interface size by the HUD and the menu).
static func apply_all(window: Window) -> void:
	ensure_loaded()
	_apply_volume()
	_apply_fullscreen(window)


static func set_mouse(v: float) -> void:
	mouse_scale = clampf(v, MOUSE_MIN, MOUSE_MAX)
	_save()


static func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save()


static func set_fullscreen(on: bool, window: Window) -> void:
	fullscreen = on
	_apply_fullscreen(window)
	_save()


static func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)


static func _apply_fullscreen(window: Window) -> void:
	if window == null or DisplayServer.get_name() == "headless":
		return
	var want := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if (window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN) != fullscreen:
		window.mode = want
