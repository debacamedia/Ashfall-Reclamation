class_name SettlerTalk
extends Interactable
## Talking to a Settler (Increment 19): a survivor you meet is asked to come
## and live at your settlement; someone who lives there opens the settlement
## screen at their name, to give them a job or a gun.

@onready var settler: Settler = get_parent() as Settler


func _ready() -> void:
	action_name = "Talk to"
	max_distance = 3.0


func get_prompt(_interactor: Node3D) -> String:
	if settler == null:
		return "Talk"
	if settler.settlement == null:
		return "Talk to %s" % settler.settler_name
	return "Talk to %s (%s)" % [settler.settler_name, settler.role_name()]


func get_block_reason(interactor: Node3D) -> String:
	return "" if interactor is PlayerController and settler != null and not settler.is_dead() else "Can't do that"


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player != null:
		player.talk_to(settler)


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if settler != null:
		out.append(settler.get_rid())
	return out
