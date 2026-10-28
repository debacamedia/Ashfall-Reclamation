class_name Landmark
extends Marker3D
## A named place in a zone: Outpost 17, Halden's Crossing, Ash Creek Farms…
##
## The HUD's compass shows landmarks, and walking within `radius` of one
## shows its name on screen ("HALDEN'S CROSSING"). Purely presentation.

@export var display_name := ""
## Inside this distance (m, measured flat) you're "at" the place.
@export var radius := 60.0
## Short label on the compass (defaults to the display name).
@export var compass_name := ""
## The compass marker's colour (your dropped gear is white, places amber).
@export var marker_color := Color(0.95, 0.75, 0.35)


func _ready() -> void:
	add_to_group("landmarks")


func get_compass_name() -> String:
	return compass_name if compass_name != "" else display_name


## Flat distance from `p` to this landmark (m).
func flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## The landmark `p` is at (the nearest whose radius contains it), or null.
static func at(tree: SceneTree, p: Vector3) -> Landmark:
	var best: Landmark = null
	var best_d := INF
	for n in tree.get_nodes_in_group("landmarks"):
		var l := n as Landmark
		if l == null:
			continue
		var d := l.flat_distance(p)
		if d <= l.radius and d < best_d:
			best = l
			best_d = d
	return best
