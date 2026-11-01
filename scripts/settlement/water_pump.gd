class_name WaterPump
extends Interactable
## A Settlement's pump (Increment 19). Broken at first: hold E with the parts
## (3 scrap metal, 2 metal pipes, a spring) to fix it, and it fills the water
## tank. Farmers need water to grow food. Once it runs, hold E with more
## parts to upgrade it (Increment 20.1): a Bigger Pump, then a Motor Pump.

@onready var settlement: Settlement = get_parent() as Settlement


func _ready() -> void:
	hold_time = 2.5
	max_distance = 3.0


func get_prompt(_interactor: Node3D) -> String:
	if settlement == null:
		return "Pump"
	if settlement.pump_working:
		var up := settlement.next_pump_upgrade()
		if not up.is_empty():
			return "Upgrade to a %s: %d L an hour (%s)" % [up[0], roundi(float(up[2])), Settlement.parts_text(up[1])]
		return "%s: running, %d L an hour (%d / %d L)" % [Settlement.PUMP_LEVELS[settlement.pump_level][0], roundi(settlement.pump_rate()), roundi(settlement.water), roundi(settlement.water_capacity)]
	return "Repair the pump (%s)" % Settlement.pump_parts_text()


func get_block_reason(interactor: Node3D) -> String:
	if settlement == null:
		return ""
	if settlement.pump_working:
		return "" if settlement.next_pump_upgrade().is_empty() else settlement.upgrade_refusal_reason(interactor)
	return settlement.pump_refusal_reason(interactor)


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player == null or settlement == null:
		return
	if not settlement.pump_working:
		player.request_repair_pump(settlement)
	elif not settlement.next_pump_upgrade().is_empty():
		settlement.request_upgrade_pump(player)


func _process(_delta: float) -> void:
	hold_time = 0.0 if settlement != null and settlement.pump_working and settlement.next_pump_upgrade().is_empty() else 2.5
