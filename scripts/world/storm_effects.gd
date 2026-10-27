class_name StormEffects
extends CanvasLayer
## What the ash storm at a zone's edge looks and sounds like, for this
## machine's own player: the haze closes in, ash blows across the screen,
## the wind howls and a warning says to turn back.
##
## Purely presentation (each client draws its own); ZoneBoundary decides the
## damage. Lives in the zone scene.

const STORM_WIND := preload("res://assets/audio/wind_loop.wav")
const ASH_SHADER := preload("res://assets/shaders/ash_storm.gdshader")
## How fast the effect follows you (per second).
const FOLLOW := 1.6

## Storm level now (0..1), smoothed; read by tests.
var level := 0.0
## The warning showing now ("" if none).
var warning := ""

var _boundary: ZoneBoundary
var _player: PlayerController
var _overlay: ColorRect
var _label: Label
var _wind: AudioStreamPlayer
var _env: Environment
var _base_fog_begin := 0.0
var _base_fog_end := 0.0
var _base_fog_color := Color()

const ASH_FOG := Color(0.5, 0.44, 0.38)


func _ready() -> void:
	layer = 4
	_overlay = ColorRect.new()
	_overlay.name = "Ash"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ASH_SHADER
	_overlay.material = mat
	_overlay.visible = false
	add_child(_overlay)
	_label = Label.new()
	_label.name = "StormWarning"
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-300, 92)
	_label.size = Vector2(600, 30)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_wind = AudioStreamPlayer.new()
	_wind.name = "StormWind"
	_wind.stream = STORM_WIND
	_wind.bus = &"Ambience"
	_wind.volume_db = -60.0
	add_child(_wind)


func _process(delta: float) -> void:
	if _boundary == null or not is_instance_valid(_boundary):
		_boundary = ZoneBoundary.find_in(get_tree())
	if _player == null or not is_instance_valid(_player):
		_player = _find_local_player()
	var target := 0.0
	warning = ""
	if _boundary != null and _player != null and not _player.is_dead():
		target = _boundary.storm_level(_player.global_position)
		warning = _boundary.warning_at(_player.global_position)
	level = move_toward(level, target, FOLLOW * delta)
	_apply()


func _apply() -> void:
	var shown := level > 0.01
	_overlay.visible = shown
	if shown:
		(_overlay.material as ShaderMaterial).set_shader_parameter("intensity", level * 0.9)
	_label.text = warning
	_label.visible = warning != ""
	if shown and not _wind.playing:
		_wind.play()
	elif not shown and _wind.playing:
		_wind.stop()
	_wind.volume_db = linear_to_db(maxf(level, 0.001)) + 2.0
	_apply_fog()


func _apply_fog() -> void:
	if _env == null:
		var we := _find_world_environment()
		if we == null or we.environment == null:
			return
		# Our own copy, so the level's resource is never changed
		we.environment = we.environment.duplicate() as Environment
		_env = we.environment
		_base_fog_begin = _env.fog_depth_begin
		_base_fog_end = _env.fog_depth_end
		_base_fog_color = _env.fog_light_color
	var k := smoothstep(0.0, 1.0, level)
	_env.fog_depth_begin = lerpf(_base_fog_begin, 0.0, k)
	_env.fog_depth_end = lerpf(_base_fog_end, 40.0, k)
	_env.fog_light_color = _base_fog_color.lerp(ASH_FOG, level)


func _find_local_player() -> PlayerController:
	for p in get_tree().get_nodes_in_group("players"):
		var pc := p as PlayerController
		if pc != null and pc.controlled_locally:
			return pc
	var first := get_tree().get_first_node_in_group("players")
	return first as PlayerController


func _find_world_environment() -> WorldEnvironment:
	var root := get_parent()
	if root == null:
		return null
	return root.find_child("WorldEnvironment", true, false) as WorldEnvironment
