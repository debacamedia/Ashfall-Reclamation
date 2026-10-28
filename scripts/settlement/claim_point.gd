class_name ClaimPoint
extends Interactable
## The notice board where you claim a Settlement (Increment 19): hold E once
## its raiders are gone. Afterwards it opens the settlement screen.

@onready var settlement: Settlement = get_parent() as Settlement


func _ready() -> void:
	hold_time = 2.0


func get_prompt(_interactor: Node3D) -> String:
	if settlement == null:
		return "Notice board"
	if settlement.is_claimed:
		return "%s: settlement board" % settlement.settlement_name
	return "Claim %s" % settlement.settlement_name


func get_block_reason(interactor: Node3D) -> String:
	if settlement == null or settlement.is_claimed:
		return ""
	return settlement.claim_refusal_reason(interactor)


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player == null:
		return
	if settlement.is_claimed:
		player.settlement_board_opened.emit(settlement)
	else:
		player.request_claim(settlement)


func _process(_delta: float) -> void:
	# A tap opens the board once it's yours; claiming is a hold
	hold_time = 0.0 if settlement != null and settlement.is_claimed else 2.0
