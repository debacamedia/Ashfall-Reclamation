class_name SettingsPanel
extends VBoxContainer
## Settings (Increment 33.1), in the main menu and the pause menu: the
## interface size, mouse speed, volume and full screen. Each change is kept
## at once (GameSettings, UiScale).

const TEXT := Color(0.86, 0.84, 0.78)
const DIM := Color(0.62, 0.6, 0.55)

var _ui: HSlider
var _mouse: HSlider
var _volume: HSlider
var _full: CheckButton
var _values := {}


func _init() -> void:
	name = "Settings"
	add_theme_constant_override("separation", 14)
	GameSettings.ensure_loaded()
	_ui = _slider("Interface size", "UiSize", UiScale.MIN, 1.6, 0.05, UiScale.saved(), func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_ui.value_changed.connect(func(v: float) -> void:
		var applied := UiScale.apply(get_window(), v)
		UiScale.save(applied)
		for h in get_tree().get_nodes_in_group("hud"):
			h.call("refresh_ui_scale")
		_show(_ui, applied))
	_mouse = _slider("Mouse speed", "Mouse", GameSettings.MOUSE_MIN, GameSettings.MOUSE_MAX, 0.05, GameSettings.mouse_scale, func(v: float) -> String: return "%.2f×" % v)
	_mouse.value_changed.connect(func(v: float) -> void: GameSettings.set_mouse(v); _show(_mouse, v))
	_volume = _slider("Volume", "Volume", 0.0, 1.0, 0.05, GameSettings.volume, func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_volume.value_changed.connect(func(v: float) -> void: GameSettings.set_volume(v); _show(_volume, v))
	_full = CheckButton.new()
	_full.name = "Fullscreen"
	_full.text = "Full screen"
	_full.focus_mode = Control.FOCUS_NONE
	_full.add_theme_font_size_override("font_size", 18)
	_full.add_theme_color_override("font_color", TEXT)
	_full.button_pressed = GameSettings.fullscreen
	_full.toggled.connect(func(on: bool) -> void: GameSettings.set_fullscreen(on, get_window()))
	add_child(_full)
	var hint := Label.new()
	hint.text = "In game, Ctrl/Cmd + and − change the interface size too."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", DIM)
	add_child(hint)


func _ready() -> void:
	# The biggest interface that fits this window
	_ui.max_value = maxf(UiScale.MIN, UiScale.largest_for(Vector2(get_window().size)))
	_ui.set_value_no_signal(clampf(UiScale.saved(), _ui.min_value, _ui.max_value))
	_show(_ui, _ui.value)


func _slider(title: String, id: String, lo: float, hi: float, step: float, now: float, fmt: Callable) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", TEXT)
	head.add_child(l)
	var v := Label.new()
	v.name = id + "Value"
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", Color(0.95, 0.72, 0.38))
	head.add_child(v)
	row.add_child(head)
	var s := HSlider.new()
	s.name = id
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = now
	s.custom_minimum_size = Vector2(320, 24)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	add_child(row)
	_values[s] = [v, fmt]
	_show(s, now)
	return s


func _show(s: HSlider, v: float) -> void:
	var pair: Array = _values.get(s, [])
	if not pair.is_empty():
		(pair[0] as Label).text = (pair[1] as Callable).call(v)
