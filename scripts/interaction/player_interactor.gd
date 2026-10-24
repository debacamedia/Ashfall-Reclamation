class_name PlayerInteractor
extends RayCast3D
## The player's "what am I looking at" ray. Lives under the camera, points
## forward, hits interactables (layer 5) but is blocked by walls (layers 1-2).
## Tracks the focused Interactable and handles press / hold-to-interact.
##
## PlayerController calls tick() once per physics step with the frame's
## interact button state, so remote players are handled the same way.

signal focus_changed(target: Interactable)
## 0..1 while holding for a hold-time interaction; -1 when not holding.
signal hold_progress_changed(progress: float)
signal interaction_succeeded(target: Interactable)
signal interaction_refused(target: Interactable, reason: String)

var focused: Interactable = null
var hold_progress := -1.0

var _was_pressed := false
var _hold_target: Interactable = null


func _ready() -> void:
	target_position = Vector3(0, 0, -3.0)
	collision_mask = PhysicsLayers.INTERACTABLES | PhysicsLayers.WORLD_SOLID
	collide_with_areas = true
	collide_with_bodies = true
	enabled = false  # updated manually in tick()


## Pass interactor = null to clear focus (e.g. while dead).
func tick(delta: float, interact_held: bool, interactor: Node3D) -> void:
	if interactor == null:
		_set_focus(null)
		_was_pressed = false
		return
	if interactor is CollisionObject3D:
		clear_exceptions()
		add_exception(interactor as CollisionObject3D)
	force_raycast_update()
	var found: Interactable = null
	if is_colliding():
		found = Interactable.from_collider(get_collider())
		if found != null and not found.enabled:
			found = null
	_set_focus(found)

	var pressed := interact_held and not _was_pressed
	_was_pressed = interact_held

	if focused == null:
		_cancel_hold()
		return

	if focused.hold_time <= 0.0:
		if pressed:
			_attempt(focused, interactor)
		return

	# Hold-to-interact
	if interact_held and (_hold_target == focused or pressed):
		if _hold_target != focused:
			var reason := focused.get_block_reason(interactor)
			if reason != "":
				if pressed:
					interaction_refused.emit(focused, reason)
				return
			_hold_target = focused
			hold_progress = 0.0
		hold_progress += delta / focused.hold_time
		hold_progress_changed.emit(minf(hold_progress, 1.0))
		if hold_progress >= 1.0:
			var target := focused
			_cancel_hold()
			_attempt(target, interactor)
	else:
		_cancel_hold()


func _attempt(target: Interactable, interactor: Node3D) -> void:
	var reason := target.get_block_reason(interactor)
	if reason != "" or not target.try_interact(interactor, global_position):
		interaction_refused.emit(target, reason if reason != "" else "Can't reach")
		return
	interaction_succeeded.emit(target)


func _set_focus(target: Interactable) -> void:
	if target == focused:
		return
	if is_instance_valid(focused):
		focused.set_highlighted(false)
	focused = target
	if focused != null:
		focused.set_highlighted(true)
	_cancel_hold()
	focus_changed.emit(focused)


func _cancel_hold() -> void:
	if _hold_target != null or hold_progress >= 0.0:
		_hold_target = null
		hold_progress = -1.0
		hold_progress_changed.emit(-1.0)
