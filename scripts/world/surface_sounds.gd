class_name SurfaceSounds
extends RefCounted
## What something is made of, for bullet impacts (Resource Pack 3 sound
## sets): &"gravel", &"concrete", &"metal" or &"wood".
##
## A node can say for itself with the metadata "surface" (on it or a parent
## up to three levels). Otherwise:
##   - built structures: metal walls, chain-link fence → metal; sandbags →
##     gravel; the rest (wood walls, platforms, stairs, crates) → wood
##   - level props: trucks, fuel drums, generators, toolboxes, water tanks,
##     chain-link fences, weapons lockers, shipping containers → metal;
##     wooden crates, footlockers, supply crates → wood; sandbag walls →
##     gravel; jersey barriers → concrete
##   - the ground (terrain layer) → gravel
##   - anything else solid (buildings, walls, floors) → concrete

const IMPACTS := {
	&"gravel": preload("res://assets/ashfall_pack_v3/sets/impact_dirt.tres"),
	&"concrete": preload("res://assets/ashfall_pack_v3/sets/impact_concrete.tres"),
	&"metal": preload("res://assets/ashfall_pack_v3/sets/impact_metal.tres"),
	&"wood": preload("res://assets/audio/sets/structure_hit.tres"),
}

const METAL_WORDS := ["metal", "chain_link", "truck", "drum", "generator", "toolbox", "tank", "locker", "container", "radio"]
const WOOD_WORDS := ["wood", "platform", "stairs", "ladder", "crate", "footlocker", "gate", "barricade", "bench", "pallet"]


static func of(collider: Object) -> StringName:
	var node := collider as Node
	if node == null:
		return &"concrete"
	# Explicit tag
	var n := node
	for i in 4:
		if n == null:
			break
		if n.has_meta("surface"):
			return StringName(str(n.get_meta("surface")))
		n = n.get_parent()
	# Built structures and level props say what they are by their definition
	var s := Structure.from_collider(node)
	if s != null and s.definition != null:
		var id := String(s.definition.id)
		if id.contains("sandbag"):
			return &"gravel"
		if id.contains("footlocker"):
			return &"wood"
		if id.contains("jersey"):
			return &"concrete"
		if _has_any(id, METAL_WORDS):
			return &"metal"
		return &"wood"
	# Scenes we know by file
	n = node
	for i in 3:
		if n == null:
			break
		var path := n.scene_file_path
		if path.contains("shipping_container") or path.contains("military_truck"):
			return &"metal"
		n = n.get_parent()
	if node is CollisionObject3D and (node as CollisionObject3D).collision_layer == PhysicsLayers.TERRAIN:
		return &"gravel"
	return &"concrete"


static func impact(surface: StringName) -> AudioStream:
	return IMPACTS.get(surface, IMPACTS[&"concrete"])


static func _has_any(text: String, words: Array) -> bool:
	for w: String in words:
		if text.contains(w):
			return true
	return false
