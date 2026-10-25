class_name ScopeOverlay
extends Control
## Full-screen scope view for weapons with scope_overlay (the scoped rifle):
## black surround, a round field of view, fine crosshairs and range marks.
## The HUD shows it once the sights are fully raised; the gun model hides.

@export var reticle_color := Color(0.05, 0.05, 0.05, 0.95)
@export var line_width := 1.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.46
	# Black outside the circle: a ring thick enough to reach the corners
	var outer := c.length() + 4.0
	draw_arc(c, (r + outer) / 2.0, 0.0, TAU, 128, Color.BLACK, outer - r + 2.0, true)
	# Lens edge
	draw_arc(c, r, 0.0, TAU, 128, Color(0.12, 0.12, 0.1), 6.0, true)
	# Thick outer posts, fine centre cross
	var gap := r * 0.12
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(c + d * r * 0.55, c + d * r, reticle_color, 5.0, true)
	draw_line(c + Vector2.UP * r * 0.55, c + Vector2.UP * r, reticle_color, 5.0, true)
	draw_line(c + Vector2(-r * 0.55, 0), c + Vector2(r * 0.55, 0), reticle_color, line_width, true)
	draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, r * 0.55), reticle_color, line_width, true)
	# Range marks below centre (holdover)
	for i in range(1, 4):
		var y := c.y + gap * i
		var w := 10.0 - i * 2.0
		draw_line(Vector2(c.x - w, y), Vector2(c.x + w, y), reticle_color, line_width, true)
	draw_circle(c, 1.6, Color(0.8, 0.1, 0.05))
