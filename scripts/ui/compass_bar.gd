class_name CompassBar
extends Control
## The compass strip at the top of the screen: the way you're facing, the
## cardinal points, and the zone's landmarks with their distance. Walking
## into a landmark's area shows its name in large letters for a moment.
##
## Built by the HUD in code. Purely presentation.

const WIDTH := 640.0
const HEIGHT := 40.0
## Text sizes (Increment 16.7: bigger, easier to read)
const CARDINAL_SIZE := 22
const INTERCARDINAL_SIZE := 16
const NAME_SIZE := 18
## Degrees of view across the strip.
const SPAN := 120.0
const BANNER_TIME := 3.2

const POINTS := {0.0: "N", 45.0: "NE", 90.0: "E", 135.0: "SE", 180.0: "S", 225.0: "SW", 270.0: "W", 315.0: "NW"}

var player: PlayerController
## Where the player is now (the Landmark, or null); read by tests.
var current_place: Landmark
## The last place name shown in the banner.
var last_banner := ""

var _banner: Label
var _banner_left := 0.0
var _check := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT + 30)
	size = custom_minimum_size
	_centre()
	_banner = Label.new()
	_banner.name = "PlaceBanner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(-120, HEIGHT + 86)
	_banner.size = Vector2(WIDTH + 240, 52)
	_banner.add_theme_font_size_override("font_size", 38)
	_banner.add_theme_color_override("font_color", Color(0.95, 0.86, 0.62))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.modulate.a = 0.0
	add_child(_banner)


## Compass bearing (degrees, 0 = north, 90 = east) the player faces.
static func heading_of(yaw: float) -> float:
	# Yaw 0 looks along -Z (north); turning left (positive yaw) faces west.
	return fposmod(-rad_to_deg(yaw), 360.0)


## Bearing (degrees) from `from` to `to`.
static func bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


## Top middle of the screen (placed in code: the HUD is a CanvasLayer).
func _centre() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	position = Vector2(roundf((vp.x - WIDTH) / 2.0), 10)


func _process(delta: float) -> void:
	visible = player != null and is_instance_valid(player) and not player.is_dead()
	if not visible:
		return
	_centre()
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		var here := Landmark.at(get_tree(), player.global_position)
		if here != current_place:
			current_place = here
			if here != null:
				show_banner(here.display_name)
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(minf(_banner_left, BANNER_TIME - _banner_left) * 2.0, 0.0, 1.0)
	queue_redraw()


func show_banner(text: String) -> void:
	last_banner = text
	_banner.text = text.to_upper()
	_banner_left = BANNER_TIME


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(0.05, 0.05, 0.04, 0.55))
	var heading := heading_of(player.rotation.y)
	# Ticks every 15°, letters on the cardinal and intercardinal points
	for step in range(0, 360, 15):
		var x := _x_for(float(step), heading)
		if is_nan(x):
			continue
		var label: Variant = POINTS.get(float(step))
		if label != null:
			var s := CARDINAL_SIZE if String(label).length() == 1 else INTERCARDINAL_SIZE
			var col := Color(1.0, 0.82, 0.45) if label == "N" else Color(0.95, 0.93, 0.87)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
			draw_string_outline(font, Vector2(x - w / 2.0, HEIGHT - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, s, 3, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(x - w / 2.0, HEIGHT - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)
		else:
			draw_line(Vector2(x, HEIGHT - 11), Vector2(x, HEIGHT - 3), Color(0.9, 0.88, 0.8, 0.65), 1.5)
	# Landmarks: a diamond each along the top; the one nearest the middle
	# gets its name and distance under the strip
	var named: Landmark = null
	var named_x := 0.0
	for n in get_tree().get_nodes_in_group("landmarks"):
		var l := n as Landmark
		if l == null or l == current_place:
			continue
		var x := _x_for(bearing(player.global_position, l.global_position), heading)
		if is_nan(x):
			continue
		var c := Vector2(x, 7)
		var d := 6.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), l.marker_color)
		draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), Color(0, 0, 0, 0.6), 1.0)
		if absf(x - WIDTH / 2.0) < 80.0 and (named == null or absf(x - WIDTH / 2.0) < absf(named_x - WIDTH / 2.0)):
			named = l
			named_x = x
	if named != null:
		var text := "%s  %s" % [named.get_compass_name(), _distance_text(named.flat_distance(player.global_position))]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		var tx := clampf(named_x - w / 2.0, 6.0, WIDTH - w - 6.0)
		draw_rect(Rect2(tx - 8, HEIGHT + 3, w + 16, NAME_SIZE + 9), Color(0.05, 0.05, 0.04, 0.6))
		draw_string(font, Vector2(tx, HEIGHT + NAME_SIZE + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, named.marker_color.lerp(Color(1, 0.92, 0.75), 0.3))
	# The way you're facing
	draw_line(Vector2(WIDTH / 2.0, 0), Vector2(WIDTH / 2.0, 9), Color(1, 1, 1, 0.95), 2.5)


func _x_for(bearing_deg: float, heading: float) -> float:
	var rel := wrapf(bearing_deg - heading, -180.0, 180.0)
	if absf(rel) > SPAN / 2.0:
		return NAN
	return WIDTH / 2.0 + rel / (SPAN / 2.0) * (WIDTH / 2.0)


static func _distance_text(m: float) -> String:
	return "%d m" % int(round(m / 10.0) * 10.0) if m < 1000.0 else "%.1f km" % (m / 1000.0)
