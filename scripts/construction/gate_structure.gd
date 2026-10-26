class_name GateStructure
extends Structure
## A wooden gate: E anywhere on it opens or closes it. Raiders can't open
## gates, so a closed gate in a wall is something they have to break; an
## open one they walk through (the navmesh is rebaked when it swings).
##
## Scene: res://scenes/structures/wooden_gate.tscn. Root → Posts (Body),
## %Door (pivot at the hinge) → DoorBody (StaticBody3D) + planks, %Handle
## (GateHandle, the E target), %SwingSound.

const OPEN_ANGLE := -100.0

var is_open := false

@onready var _door: Node3D = %Door
@onready var _swing_sound: AudioStreamPlayer3D = get_node_or_null("%SwingSound")
var _tween: Tween


func set_open(open: bool, animate := true) -> void:
	if open == is_open and animate:
		return
	is_open = open
	var target := Vector3(0, deg_to_rad(OPEN_ANGLE if open else 0.0), 0)
	if _tween != null:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_door, "rotation", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if _swing_sound != null:
			_swing_sound.play()
	else:
		_door.rotation = target
	# Open: a way through for raiders. Closed: a wall again. (Rebaked once the
	# door has finished swinging.)
	if is_inside_tree() and definition != null and definition.blocks_navigation:
		if _tween != null and _tween.is_running():
			_tween.finished.connect(func() -> void: NavRebaker.request(self), CONNECT_ONE_SHOT)
		else:
			NavRebaker.request(self)


func toggle() -> void:
	set_open(not is_open)


func save_state() -> Dictionary:
	var data := super.save_state()
	data["open"] = is_open
	return data


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var open: Variant = data.get("open", false)
	set_open(open is bool and open, false)
