class_name TruckFuelCap
extends Interactable
## A Truck's fuel cap (Increment 18): hold E to empty a Fuel Can (10 L)
## into the tank.

@onready var truck: Truck = get_parent() as Truck


func _ready() -> void:
	action_name = "Refuel"
	hold_time = 1.2


func get_prompt(_interactor: Node3D) -> String:
	if truck == null:
		return "Refuel"
	return "Refuel %s  (%d / %d L)" % [truck.display_name, roundi(truck.fuel), roundi(truck.fuel_capacity)]


func get_block_reason(interactor: Node3D) -> String:
	return truck.refuel_refusal_reason(interactor) if truck != null else "Can't use that"


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player != null:
		player.request_refuel(truck)


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if truck != null:
		out.append(truck.get_rid())
	return out
