class_name TruckDoor
extends Interactable
## The driver's door of a Truck (Increment 18): E to get in and drive.

@onready var truck: Truck = get_parent() as Truck


func _ready() -> void:
	action_name = "Drive"
	object_name = truck.display_name if truck != null else "Truck"


func get_block_reason(interactor: Node3D) -> String:
	return truck.entry_refusal_reason(interactor) if truck != null else "Can't use that"


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player != null:
		player.enter_vehicle(truck)


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if truck != null:
		out.append(truck.get_rid())
	return out
