class_name DamageIndicator
extends Control
## Red arcs around the crosshair pointing toward where damage came from,
## relative to where the player is looking. They fade out over `duration`.
## Should fill the screen (Full Rect anchors).

@export var radius := 110.0
@export var width := 7.0
@export var arc_degrees := 40.0
@export var duration := 1.2
@export var color := Color(0.9, 0.1, 0.05, 0.85)

var player: PlayerController

## Each entry: [world direction toward the source (Vector3), seconds left]
var _hits: Array = []


## Adds an indicator for damage that came from `world_direction`
## (pointing from the player toward the source).
func add_hit(world_direction: Vector3) -> void:
	world_direction.y = 0.0
	if world_direction.length() < 0.001:
		return
	_hits.append([world_direction.normalized(), duration])
	queue_redraw()


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for h in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h: Array) -> bool: return h[1] > 0.0)
	queue_redraw()


## Angle on screen (radians, 0 = straight ahead/up, clockwise) for a world
## direction, given the player's facing.
func screen_angle_for(world_direction: Vector3) -> float:
	if player == null:
		return 0.0
	var local := player.global_basis.inverse() * world_direction
	return atan2(local.x, -local.z)


func _draw() -> void:
	if player == null:
		return
	var centre := size / 2.0
	var half := deg_to_rad(arc_degrees) / 2.0
	for h in _hits:
		var a := screen_angle_for(h[0])
		var c := Color(color, color.a * clampf(h[1] / duration, 0.0, 1.0))
		# draw_arc angles start at +X and run clockwise (screen Y is down)
		draw_arc(centre, radius, a - PI / 2.0 - half, a - PI / 2.0 + half, 24, c, width, true)
