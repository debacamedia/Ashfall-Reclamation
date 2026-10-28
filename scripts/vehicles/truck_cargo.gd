class_name TruckCargo
extends SalvageContainer
## A Truck's bed (Increment 18): opened at the tailgate like any container,
## no search. It holds far more than a backpack and goes where the truck
## goes; walk (or drive) away and it closes. Saved like other containers.

## The bed's limit (kg). Containers normally have none.
@export var carry_weight := 400.0

@onready var truck: Truck = get_parent() as Truck


func _ready() -> void:
	is_searched = true
	search_time = 0.0
	super._ready()
	inventory.max_weight = carry_weight


func get_prompt(_interactor: Node3D) -> String:
	var used := inventory.slot_count - inventory.get_free_slot_count()
	return "Open %s  (%d / %d slots, %.0f / %.0f kg)" % [container_name, used, inventory.slot_count, inventory.get_total_weight(), carry_weight]


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out := super._get_line_of_sight_exclusions()
	if truck != null:
		out.append(truck.get_rid())
	return out


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	inventory.max_weight = carry_weight
	is_searched = true
	_update_prompt()
