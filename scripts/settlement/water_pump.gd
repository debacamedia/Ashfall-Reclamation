class_name WaterPump
extends Interactable
## A Settlement's pump (Increment 19). Broken at first: hold E with the parts
## (3 scrap metal, 2 metal pipes, a spring) to fix it, and it fills the water
## tank. Farmers need water to grow food.

@onready var settlement: Settlement = get_parent() as Settlement


func _ready() -> void:
	hold_time = 2.5
	max_distance = 3.0


func get_prompt(_interactor: Node3D) -> String:
	if settlement == null:
		return "Pump"
	if settlement.pump_working:
		return "Water pump: running (%d / %d L)" % [roundi(settlement.water), roundi(settlement.water_capacity)]
	return "Repair the pump (%s)" % Settlement.pump_parts_text()


func get_block_reason(interactor: Node3D) -> String:
	if settlement == null or settlement.pump_working:
		return ""
	return settlement.pump_refusal_reason(interactor)


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player != null and settlement != null and not settlement.pump_working:
		player.request_repair_pump(settlement)


func _process(_delta: float) -> void:
	hold_time = 0.0 if settlement != null and settlement.pump_working else 2.5
