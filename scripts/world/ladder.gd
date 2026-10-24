@tool
class_name Ladder
extends Node3D
## A climbable ladder. Place it with its origin at the bottom, against the
## wall, and its +Z axis pointing out towards where the climber stands. The
## top of the ladder (origin + height) should be level with the floor you
## climb onto.
##
## The ladder has no collision of its own: PlayerController finds ladders in
## the "ladders" group, checks is_in_reach() and attaches when the player
## moves into one (or walks off the top towards it). The rails and rungs are
## generated from `height` and `width`, in the editor too.
##
## Scene: res://scenes/world/structures/ladder.tscn

## Floor-to-top climbing height (m).
@export var height := 3.0:
	set(value):
		height = maxf(value, 0.5)
		_rebuild()
## Distance between the rails (m).
@export var width := 0.55:
	set(value):
		width = maxf(value, 0.2)
		_rebuild()
## How far the rails stick up above the top, as handholds (m).
@export var handhold_height := 1.0:
	set(value):
		handhold_height = maxf(value, 0.0)
		_rebuild()
@export var rung_spacing := 0.3:
	set(value):
		rung_spacing = maxf(value, 0.1)
		_rebuild()
@export var material: Material:
	set(value):
		material = value
		_rebuild()

@export_group("Climbing")
## Distance from the ladder to the climber's centre while climbing (m).
@export var stand_off := 0.45
## How far out in front of the ladder you can grab it (m).
@export var reach_depth := 0.9

var _visual: Node3D


func _ready() -> void:
	add_to_group("ladders")
	_rebuild()


## World height of the top of the ladder (the floor you step onto).
func get_top_y() -> float:
	return global_position.y + height


## Horizontal unit vector pointing away from the wall, towards the climber.
func get_outward() -> Vector3:
	var out := global_basis.z
	out.y = 0.0
	return out.normalized()


## Where a climber's feet belong on the climbing line at a given height.
func get_climb_point(feet_y: float) -> Vector3:
	var p := global_position + get_outward() * stand_off
	p.y = feet_y
	return p


## True if a character with its feet at `feet` can grab this ladder: in front
## of it below the top, or standing on the floor just behind the top.
func is_in_reach(feet: Vector3) -> bool:
	var local := global_transform.affine_inverse() * feet
	if absf(local.x) > width / 2.0 + 0.25:
		return false
	if local.y < -0.3 or local.y > height + 0.6:
		return false
	if local.y >= height - 0.3:
		return local.z >= -0.9 and local.z <= reach_depth
	return local.z >= -0.1 and local.z <= reach_depth


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _visual != null:
		_visual.free()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual, false, Node.INTERNAL_MODE_FRONT)

	var rail_len := height + handhold_height
	var rail := BoxMesh.new()
	rail.size = Vector3(0.05, rail_len, 0.05)
	for side in [-1.0, 1.0]:
		_mesh(rail, Vector3(side * width / 2.0, rail_len / 2.0, 0.06))
	var rung := BoxMesh.new()
	rung.size = Vector3(width, 0.035, 0.035)
	var y := rung_spacing
	while y <= height + 0.01:
		_mesh(rung, Vector3(0.0, y, 0.06))
		y += rung_spacing


func _mesh(mesh: Mesh, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = material
	_visual.add_child(mi)
