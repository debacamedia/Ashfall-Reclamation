class_name Structure
extends Node3D
## A built structure: barricade, wall, gate, trap, storage crate or bench.
##
## Placed by PlayerController.request_place_structure (validated), damaged by
## raiders (apply_damage), repaired and dismantled through the player's
## request_repair_structure / request_dismantle_structure. Player bullets
## don't damage it.
##
## Saved like dropped items: in the "persist" group, removable, re-created from
## its scene under the level's "Structures" node with its transform and health.
## Placing, breaking or removing one asks NavRebaker to rebake the level's
## navmesh so raiders path around it.
##
## Scenes: res://scenes/structures/*.tscn. Root (this Node3D) → Body
## (StaticBody3D, layer 2) and meshes, plus whatever the type needs.

signal damaged(amount: float)
signal repaired
signal destroyed(structure: Structure)

@export var definition: StructureDefinition

var health := -1.0

var _hit_sound: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("structures")
	add_to_group("persist")
	if health < 0.0:
		health = definition.max_health if definition != null else 100.0
	_rng.randomize()
	_hit_sound = get_node_or_null("%HitSound")
	if definition != null and definition.blocks_navigation:
		NavRebaker.request(self)


func _exit_tree() -> void:
	if definition != null and definition.blocks_navigation and is_queued_for_deletion():
		NavRebaker.request(self)


func get_max_health() -> float:
	return definition.max_health if definition != null else 100.0


func get_health_fraction() -> float:
	return clampf(health / get_max_health(), 0.0, 1.0)


func is_damaged() -> bool:
	return health < get_max_health() - 0.01


func is_breakable() -> bool:
	return definition == null or definition.breakable


## Raiders hitting it (and traps wearing out). Breaks at 0.
func apply_damage(amount: float, _source: Node = null) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount)
	if _hit_sound != null and _hit_sound.is_inside_tree():
		_hit_sound.pitch_scale = _rng.randf_range(0.9, 1.1)
		_hit_sound.play()
	if health <= 0.0:
		destroy()


func repair_full() -> void:
	health = get_max_health()
	repaired.emit()


## Breaks apart: plays the crash where it stood and removes it.
func destroy() -> void:
	if is_queued_for_deletion():
		return
	health = 0.0
	destroyed.emit(self)
	_one_shot(load("res://assets/audio/structure_break.wav"))
	queue_free()


## Can it be dismantled right now? "" = yes, otherwise why not.
func dismantle_block_reason() -> String:
	return ""


func _one_shot(stream: AudioStream) -> void:
	if stream == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.unit_size = 4.0
	get_parent().add_child(p)
	p.global_position = global_position + Vector3.UP * 0.8
	p.finished.connect(p.queue_free)
	p.play()


## The Structure a physics collider belongs to (or null).
static func from_collider(collider: Object) -> Structure:
	var node := collider as Node
	while node != null:
		if node is Structure:
			return node as Structure
		node = node.get_parent()
	return null


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var t := global_transform
	return {
		"structure": String(definition.id) if definition != null else "",
		"health": health,
		"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z],
		"origin": [t.origin.x, t.origin.y, t.origin.z],
	}


func load_state(data: Dictionary) -> void:
	var o: Variant = data.get("origin")
	var b: Variant = data.get("basis")
	if o is Array and o.size() == 3 and b is Array and b.size() == 9 \
			and (o as Array).all(_is_number) and (b as Array).all(_is_number):
		var basis := Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])).orthonormalized()
		global_transform = Transform3D(basis, Vector3(o[0], o[1], o[2]))
	var h: Variant = data.get("health")
	if _is_number(h):
		health = clampf(float(h), 1.0, get_max_health())
	if definition != null and definition.blocks_navigation:
		NavRebaker.request(self)


func is_save_removable() -> bool:
	return true


static func _is_number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))
