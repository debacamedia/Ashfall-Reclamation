class_name RegionExit
extends Interactable
## A road sign at the edge of a region: hold E to travel to another region
## ("Follow the road to Halden's Crossing").
##
## Travel itself is validated and carried out by WorldManager.request_travel
## (alive, not crafting, no raiders chasing you, the level exists). The
## player arrives at the target level's Arrivals/<arrival_id> marker.
##
## Scene: res://scenes/world/region_exit.tscn — Area3D root + Shape + sign.

## Level to open.
@export_file("*.tscn") var target_level := ""
## Marker under the target level's "Arrivals" node to arrive at.
@export var arrival_id: StringName = &""
## Shown in the prompt and the travel screen.
@export var destination_name := "Somewhere"


func _ready() -> void:
	add_to_group("region_exits")
	action_name = "Follow the road to"
	object_name = destination_name
	if hold_time <= 0.0:
		hold_time = 1.0
	for label_name in ["%SignText", "SignTextBack"]:
		var sign_text := get_node_or_null(label_name) as Label3D
		if sign_text != null:
			sign_text.text = destination_name.to_upper()


func get_prompt(_interactor: Node3D) -> String:
	return "Follow the road to %s" % destination_name


func get_block_reason(interactor: Node3D) -> String:
	var world := _world()
	return world.travel_refusal_reason(interactor as PlayerController, self) if world != null else "The road is blocked"


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	var body := get_node_or_null("Body") as CollisionObject3D
	if body != null:
		out.append(body.get_rid())
	return out


func _perform(interactor: Node3D) -> void:
	var world := _world()
	if world != null:
		world.request_travel(interactor as PlayerController, self)


## The WorldManager autoload (looked up at runtime so this script also
## compiles in tools that run before autoloads exist).
func _world() -> Node:
	return get_node_or_null("/root/WorldManager") if is_inside_tree() else null
