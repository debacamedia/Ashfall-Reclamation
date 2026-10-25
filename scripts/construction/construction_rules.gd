class_name ConstructionRules
extends RefCounted
## Where structures may go. Used by PlayerController.request_place_structure
## (authoritative) and by build mode (to colour the ghost), so the preview
## and the real check can never disagree.
##
## A placement is a Transform3D: origin on the ground, rotated about Y only.

const REACH := 6.0              ## eyes to the structure's centre (m)
const GRID := 0.5               ## positions snap to this (m)
const ROTATE_STEP := 15.0       ## degrees per R press
const MAX_PER_REGION := 80
const KEEP_CLEAR_RADIUS := 3.5  ## around spawns, arrivals and road signs (m)
const GROUND_TOLERANCE := 0.35  ## max height difference under the footprint (m)


## The node structures are added to in `level` (null = can't build there).
static func structures_root(level: Node) -> Node3D:
	return level.get_node_or_null("Structures") as Node3D if level != null else null


## Snaps a point and a yaw (degrees) to the build grid.
static func snap(point: Vector3, yaw_degrees: float) -> Transform3D:
	var p := Vector3(snappedf(point.x, GRID), point.y, snappedf(point.z, GRID))
	var yaw := deg_to_rad(snappedf(yaw_degrees, ROTATE_STEP))
	return Transform3D(Basis(Vector3.UP, yaw), p)


## Ground height under `at` (searching 1.5 m up and down), or NAN.
static func ground_y(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 1.5, PhysicsLayers.WORLD_SOLID))
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


## "" if `def` can be placed at `xform` by `player`, otherwise why not.
static func refusal_reason(player: PlayerController, def: StructureDefinition, xform: Transform3D) -> String:
	if player == null or player.is_dead():
		return "Can't build now"
	var level := player.get_parent()
	var root := structures_root(level)
	if root == null:
		return "You can't build here"
	var centre := xform.origin + Vector3.UP * (def.footprint.y * 0.5)
	if player.head.global_position.distance_to(centre) > REACH:
		return "Too far away"
	if root.get_child_count() >= MAX_PER_REGION:
		return "Too many structures here"
	# Keep spawns, arrivals and road signs clear
	var keep_clear: Array[Node3D] = []
	for path in ["PlayerSpawn", "Arrivals", "Exits"]:
		var n := level.get_node_or_null(path)
		if n is Marker3D:
			keep_clear.append(n)
		elif n != null:
			for c in n.get_children():
				if c is Node3D:
					keep_clear.append(c)
	for n in keep_clear:
		var d := Vector2(n.global_position.x - xform.origin.x, n.global_position.z - xform.origin.z).length()
		if d < KEEP_CLEAR_RADIUS + maxf(def.footprint.x, def.footprint.z) * 0.5:
			return "Keep the road in clear"
	var space := player.get_world_3d().direct_space_state
	# Nothing in the way: walls, props, people, loot, benches, signs
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = def.footprint - Vector3(0.06, 0.06, 0.06)
	q.shape = box
	q.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * (def.footprint.y * 0.5 + 0.08))
	q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.PLAYER | PhysicsLayers.NPCS | PhysicsLayers.INTERACTABLES
	q.collide_with_areas = true
	for hit in space.intersect_shape(q, 16):
		var obj := hit["collider"] as CollisionObject3D
		if obj == null or obj.collision_layer == PhysicsLayers.TERRAIN:
			continue  # the ground itself (the box sits just above it)
		return "Something's in the way"
	# Solid, fairly flat ground under the centre and the four corners; no
	# building on top of other structures
	var half := Vector2(def.footprint.x, def.footprint.z) * 0.45
	for corner in [Vector2.ZERO, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		var at := xform * Vector3(corner.x, 0.0, corner.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 1.0, PhysicsLayers.WORLD_SOLID))
		if hit.is_empty():
			return "Needs solid ground"
		if Structure.from_collider(hit["collider"]) != null:
			return "Can't build on another structure"
		if absf((hit["position"] as Vector3).y - xform.origin.y) > GROUND_TOLERANCE:
			return "The ground is too uneven"
	return ""
