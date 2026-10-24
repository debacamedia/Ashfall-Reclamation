class_name Crosshair
extends Control
## Dynamic crosshair: the gap shows the weapon's real spread cone, so it
## widens while moving or firing. Shows a hit marker (white, yellow for
## headshots, red for kills) when shots connect.
## Should fill the screen (Full Rect anchors); draws at its centre.

@export var color := Color(1, 1, 1, 0.9)
@export var line_length := 8.0
@export var thickness := 2.0
@export var min_gap := 3.0
@export var hit_marker_time := 0.22

## Set every frame by the HUD.
var spread_degrees := 0.0:
	set(value):
		if not is_equal_approx(value, spread_degrees):
			spread_degrees = value
			queue_redraw()
var camera_fov := 75.0
## 0..1 visibility of the reticle lines (fades out while aiming down sights).
## Hit markers still show.
var reticle_alpha := 1.0:
	set(value):
		if not is_equal_approx(value, reticle_alpha):
			reticle_alpha = value
			queue_redraw()

var _hit_left := 0.0
var _hit_color := Color.WHITE


func show_hit_marker(killed: bool, headshot: bool) -> void:
	_hit_left = hit_marker_time
	_hit_color = Color(1.0, 0.25, 0.2) if killed else (Color(1.0, 0.85, 0.2) if headshot else Color.WHITE)
	queue_redraw()


func _process(delta: float) -> void:
	if _hit_left > 0.0:
		_hit_left -= delta
		queue_redraw()


func _draw() -> void:
	var centre := size / 2.0
	# Pixels per unit of tan(angle) at the screen centre
	var focal := (size.y / 2.0) / tan(deg_to_rad(camera_fov / 2.0))
	var gap := maxf(min_gap, tan(deg_to_rad(spread_degrees)) * focal)
	if reticle_alpha > 0.01:
		var line_color := Color(color, color.a * reticle_alpha)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(centre + dir * gap, centre + dir * (gap + line_length), line_color, thickness, true)
		draw_circle(centre, 1.0, line_color)

	if _hit_left > 0.0:
		var c := Color(_hit_color, clampf(_hit_left / hit_marker_time, 0.0, 1.0))
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := d.normalized()
			draw_line(centre + n * (gap + 3.0), centre + n * (gap + 11.0), c, 2.5, true)
