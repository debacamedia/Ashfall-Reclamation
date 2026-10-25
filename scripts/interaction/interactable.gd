class_name Interactable
extends Area3D
## Something the player can look at and press Interact on (default E):
## pickups now, containers, doors, workbenches and NPCs later.
##
## Put this Area3D (with a CollisionShape3D child) on the "interactables"
## layer (5). The player's interaction ray finds it. Subclasses override
## get_prompt(), can_interact() and _perform().
##
## AUTHORITY: try_interact() validates distance, line of sight and
## can_interact() before doing anything, so in co-op the host can call it
## with a guest's request and trust the result.

signal interacted(interactor: Node3D)

## Verb shown in the prompt: "[E] Pick up Scrap Metal".
@export var action_name := "Use"
## Object name shown in the prompt.
@export var object_name := "Object"
## Seconds the key must be held (0 = instant press).
@export var hold_time := 0.0
## Furthest an interactor's eyes may be from this object.
@export var max_distance := 3.0
@export var enabled := true
## Point (local) that reach and line of sight are measured to, e.g. the
## middle of a crate rather than its base.
@export var focus_offset := Vector3.ZERO


func _init() -> void:
	collision_layer = PhysicsLayers.INTERACTABLES
	collision_mask = 0
	monitoring = false


## Prompt text, e.g. "Pick up Scrap Metal ×3".
func get_prompt(_interactor: Node3D) -> String:
	return "%s %s" % [action_name, object_name]


## Why the interaction is not possible right now ("" = allowed).
func get_block_reason(_interactor: Node3D) -> String:
	return ""


func can_interact(interactor: Node3D) -> bool:
	return enabled and get_block_reason(interactor) == ""


## Validates and performs the interaction. Returns true if it happened.
## `eye_position` is where the interactor is looking from.
func try_interact(interactor: Node3D, eye_position: Vector3) -> bool:
	if not is_inside_tree() or not can_interact(interactor):
		return false
	if not is_within_reach(eye_position):
		return false
	# Nothing solid between the interactor and this object
	var target := get_focus_point()
	var query := PhysicsRayQueryParameters3D.create(eye_position, target, PhysicsLayers.WORLD_SOLID)
	var exclude := _get_line_of_sight_exclusions()
	if interactor is CollisionObject3D:
		exclude.append((interactor as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(target) > 0.6:
		return false
	_perform(interactor)
	interacted.emit(interactor)
	return true


## World point used for reach and line-of-sight checks.
func get_focus_point() -> Vector3:
	return global_transform * focus_offset


## True if eyes at `eye_position` are close enough to use this.
func is_within_reach(eye_position: Vector3) -> bool:
	return eye_position.distance_to(get_focus_point()) <= max_distance + 0.75


## Override: bodies that belong to this object and shouldn't block its own
## line of sight (e.g. a crate's solid body).
func _get_line_of_sight_exclusions() -> Array[RID]:
	return []


## Highlight on/off while the player is looking at it (visual only).
func set_highlighted(_on: bool) -> void:
	pass


## Override: what actually happens.
func _perform(_interactor: Node3D) -> void:
	pass


## Finds the Interactable a ray hit: the collider itself or one of its parents.
static func from_collider(collider: Object) -> Interactable:
	var node := collider as Node
	for i in 3:
		if node == null:
			return null
		if node is Interactable:
			return node
		node = node.get_parent()
	return null
