class_name ZoneExit
extends Node3D
## A road out of the zone through the ash storm (Increment 25). It sits on
## the zone's edge, under its ZoneBoundary, where a road crosses it.
##
## Within `gap` metres of it the storm doesn't hurt and the warning says
## where the road goes. Cross the edge inside the gap, on foot or driving,
## and WorldManager takes you to `target_level`, arriving at its
## Arrivals/<arrival_id> marker (with your truck, if you're driving it).
##
## Placed by tools/build_early_zone.gd (EXITS) and build_mid_zone.gd.

## Level to open.
@export_file("*.tscn") var target_level := ""
## Marker under the target level's "Arrivals" node to arrive at.
@export var arrival_id: StringName = &""
## Shown in the warning and the travel screen ("the Mid Zone").
@export var destination_name := "the next zone"
## Half-width of the way through (m, flat distance from this point).
@export var gap := 14.0


func _ready() -> void:
	add_to_group("zone_exits")


## True if `p` is in the way through.
func covers(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() <= gap
