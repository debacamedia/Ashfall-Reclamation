class_name GateHandle
extends Interactable
## The E target on a GateStructure: "Open Wooden Gate" / "Close Wooden Gate".
## Validated like every Interactable (reach, line of sight); refuses to
## close on someone standing in the gateway.

@onready var gate: GateStructure = _find_gate()


func _ready() -> void:
	hold_time = 0.0
	max_distance = 2.6


func _find_gate() -> GateStructure:
	var n := get_parent()
	while n != null and not n is GateStructure:
		n = n.get_parent()
	return n as GateStructure


func get_prompt(_interactor: Node3D) -> String:
	if gate == null:
		return ""
	return ("Close " if gate.is_open else "Open ") + gate.definition.display_name


func get_block_reason(_interactor: Node3D) -> String:
	if gate == null:
		return "Can't use that"
	if gate.is_open:
		# Don't swing the door shut through a body in the gateway
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 2.0, 0.6)
		q.shape = box
		q.transform = gate.global_transform.translated_local(Vector3(0, 1.1, 0))
		q.collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.NPCS
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return "Someone's in the way"
	return ""


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if gate != null:
		for body in gate.find_children("*", "CollisionObject3D", true, false):
			out.append((body as CollisionObject3D).get_rid())
	return out


func _perform(_interactor: Node3D) -> void:
	gate.toggle()
