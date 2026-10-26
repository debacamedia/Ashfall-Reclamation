class_name ConstructionRules
extends RefCounted
## Where structures may go. Used by PlayerController.request_place_structure
## and request_move_structure (authoritative) and by build mode (to colour
## the ghost), so the preview and the real check can never disagree.
##
## A placement is a Transform3D: origin on the ground (or on a platform's
## deck), rotated about Y only.
##
## Snapping (snap_to_built) is only a convenience for the ghost: it moves the
## ghost onto a wall's end or a platform's edge. Whatever it suggests still
## has to pass refusal_reason.

const REACH := 6.0              ## eyes to the structure's centre (m)
const GRID := 0.5               ## positions snap to this (m)
const ROTATE_STEP := 15.0       ## degrees per R press
const MAX_PER_REGION := 1000
const KEEP_CLEAR_RADIUS := 3.5  ## around spawns, arrivals and road signs (m)
const GROUND_TOLERANCE := 0.35  ## max height difference under the footprint (m)
const UNDO_SECONDS := 30.0      ## dismantle within this, undamaged: kit back
const SNAP_RADIUS := 1.5        ## how close the ghost must be to snap (m)
const END_MATCH := 0.06         ## wall ends this close count as joined (m)


## The node structures are added to in `level` (null = can't build there).
static func structures_root(level: Node) -> Node3D:
	return level.get_node_or_null("Structures") as Node3D if level != null else null


## Snaps a point and a yaw (degrees) to the build grid.
static func snap(point: Vector3, yaw_degrees: float) -> Transform3D:
	var p := Vector3(snappedf(point.x, GRID), point.y, snappedf(point.z, GRID))
	var yaw := deg_to_rad(snappedf(yaw_degrees, ROTATE_STEP))
	return Transform3D(Basis(Vector3.UP, yaw), p)


## Ground height under `at` (searching 1.5 m up and down), or NAN.
static func ground_y(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID] = []) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 1.5, PhysicsLayers.WORLD_SOLID, exclude))
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


## "" if `def` can be placed at `xform` by `player`, otherwise why not.
## `moving`: a structure being moved, left out of every check (it's where
## it was until the move is done).
static func refusal_reason(player: PlayerController, def: StructureDefinition, xform: Transform3D, moving: Structure = null) -> String:
	if player == null or player.is_dead():
		return "Can't build now"
	var level := player.get_parent()
	var root := structures_root(level)
	if root == null:
		return "You can't build here"
	var centre := xform.origin + Vector3.UP * (def.footprint.y * 0.5)
	if player.head.global_position.distance_to(centre) > REACH:
		return "Too far away"
	if moving == null and root.get_child_count() >= MAX_PER_REGION:
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
	var ignore: Array[RID] = moving.get_collision_rids() if moving != null else ([] as Array[RID])
	# Walls joined end to end (at an angle their corners overlap a little)
	var overlap_ignore := ignore.duplicate()
	for p in snap_partners(root, def, xform):
		if p != moving:
			overlap_ignore.append_array(p.get_collision_rids())
	# Nothing in the way: walls, props, people, loot, benches, signs
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = def.footprint - Vector3(0.06, 0.06, 0.06)
	q.shape = box
	q.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * (def.footprint.y * 0.5 + 0.08))
	q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.PLAYER | PhysicsLayers.NPCS | PhysicsLayers.INTERACTABLES
	q.collide_with_areas = true
	q.exclude = overlap_ignore
	for hit in space.intersect_shape(q, 16):
		var obj := hit["collider"] as CollisionObject3D
		if obj == null or obj.collision_layer == PhysicsLayers.TERRAIN:
			continue  # the ground itself (the box sits just above it)
		return "Something's in the way"
	# Solid, fairly flat ground (or a platform's deck) under it: the centre and
	# corners, or for thin walls the centre line. Not on other structures.
	for at in support_points(def, xform):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 1.0, PhysicsLayers.WORLD_SOLID, overlap_ignore))
		if hit.is_empty():
			return "Needs solid ground"
		var under := Structure.from_collider(hit["collider"])
		if under != null and (under.definition == null or not under.definition.supports_building):
			return "Can't build on another structure"
		if absf((hit["position"] as Vector3).y - xform.origin.y) > GROUND_TOLERANCE:
			return "The ground is too uneven"
	return ""


## Points that must stand on something: the centre plus the four corners, or
## for thin things (walls, fences) the centre line, so a wall can stand along
## the very edge of a platform.
static func support_points(def: StructureDefinition, xform: Transform3D) -> Array[Vector3]:
	var hx := def.footprint.x * 0.45
	var hz := def.footprint.z * 0.45
	var pts: Array[Vector3] = [xform.origin]
	if def.footprint.z < 0.5:
		pts.append(xform * Vector3(-hx, 0, 0))
		pts.append(xform * Vector3(hx, 0, 0))
	else:
		for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
			pts.append(xform * Vector3(c.x, 0.0, c.y))
	return pts


## Built structures standing on `s` (a wall on a platform). They come down
## with it, and it can't be dismantled or moved while they're there.
static func resting_on(s: Structure) -> Array[Structure]:
	var out: Array[Structure] = []
	if s == null or not s.is_inside_tree() or s.definition == null or not s.definition.supports_building:
		return out
	var space := s.get_world_3d().direct_space_state
	var reach := s.definition.footprint.length() + 4.0
	for c in s.get_parent().get_children():
		var other := c as Structure
		if other == null or other == s or other.is_queued_for_deletion() or other.definition == null:
			continue
		if other.global_position.distance_to(s.global_position) > reach:
			continue
		for at in support_points(other.definition, other.global_transform):
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 0.4, PhysicsLayers.WORLD_SOLID, other.get_collision_rids()))
			if not hit.is_empty() and Structure.from_collider(hit["collider"]) == s:
				out.append(other)
				break
	return out


# ---------------------------------------------------------------- snapping

## The two ends of a wall-like structure (±X, on the ground line).
static func ends_of(def: StructureDefinition, xform: Transform3D) -> Array[Vector3]:
	return [xform * Vector3(-def.footprint.x * 0.5, 0, 0), xform * Vector3(def.footprint.x * 0.5, 0, 0)]


## Built EDGE structures joined end to end with `def` at `xform`. (Not ones
## folded back over it: those really are in the way.)
static func snap_partners(root: Node3D, def: StructureDefinition, xform: Transform3D) -> Array[Structure]:
	var out: Array[Structure] = []
	if root == null or def.snap != StructureDefinition.Snap.EDGE:
		return out
	var mine := ends_of(def, xform)
	for c in root.get_children():
		var s := c as Structure
		if s == null or s.definition == null or s.definition.snap != StructureDefinition.Snap.EDGE or s.is_queued_for_deletion():
			continue
		var theirs := ends_of(s.definition, s.global_transform)
		for a in mine:
			for b in theirs:
				if a.distance_to(b) > END_MATCH:
					continue
				# The way each one runs away from the shared end
				var my_dir := _flat(xform.origin - a)
				var their_dir := _flat(s.global_position - b)
				if my_dir.angle_to(their_dir) > deg_to_rad(40.0):
					out.append(s)
				break
			if out.has(s):
				break
	return out


## Where the ghost of `def` would snap to near `aim`, given the player's
## extra rotation `yaw_offset` (degrees). Returns {"xform": Transform3D,
## "to": Structure} or {} if there's nothing to snap to.
##   EDGE   hinge onto the nearest wall end at yaw_offset (0 = straight on,
##          R steps of 15°: 45° and 90° corners), or line up along a
##          platform edge
##   TILE   next to a platform (same rotation), or on top of one
##   ATTACH stairs/ladder against a platform edge of the right height
static func snap_to_built(root: Node3D, def: StructureDefinition, aim: Vector3, yaw_offset: float, ignore: Structure = null) -> Dictionary:
	if root == null or def == null or def.snap == StructureDefinition.Snap.NONE:
		return {}
	var best := {}
	var best_d := SNAP_RADIUS if def.snap != StructureDefinition.Snap.TILE else SNAP_RADIUS + 0.6
	for c in root.get_children():
		var s := c as Structure
		if s == null or s == ignore or s.definition == null or s.is_queued_for_deletion():
			continue
		if s.global_position.distance_to(aim) > s.definition.footprint.length() + def.footprint.length() + SNAP_RADIUS:
			continue
		for cand in _candidates(def, s, yaw_offset):
			var x: Transform3D = cand
			var d := (x.origin + Vector3.UP * 0.01).distance_to(aim)
			if d < best_d:
				best_d = d
				best = {"xform": x, "to": s}
	return best


static func _candidates(def: StructureDefinition, s: Structure, yaw_offset: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var sd := s.definition
	var st := s.global_transform
	var sx := _flat(st.basis.x)
	var sz := _flat(st.basis.z)
	match def.snap:
		StructureDefinition.Snap.EDGE:
			if sd.snap == StructureDefinition.Snap.EDGE:
				# Hinge onto either end, running on at the chosen angle
				for sign: float in [-1.0, 1.0]:
					var e := st * Vector3(sign * sd.footprint.x * 0.5, 0, 0)
					var d := (sx * sign).rotated(Vector3.UP, deg_to_rad(yaw_offset))
					out.append(_along(d, e + d * def.footprint.x * 0.5))
			elif sd.supports_building:
				# Along each edge of a platform's deck
				var top := Vector3.UP * sd.footprint.y
				for sign: float in [-1.0, 1.0]:
					out.append(_along(sz, st.origin + top + sx * sign * sd.footprint.x * 0.5))
					out.append(_along(sx, st.origin + top + sz * sign * sd.footprint.z * 0.5))
		StructureDefinition.Snap.TILE:
			if sd.snap == StructureDefinition.Snap.TILE:
				var b := Basis(Vector3.UP, atan2(-sx.z, sx.x))
				for off: Vector3 in [sx * sd.footprint.x, -sx * sd.footprint.x, sz * sd.footprint.z, -sz * sd.footprint.z, Vector3.UP * sd.footprint.y]:
					out.append(Transform3D(b, st.origin + off))
		StructureDefinition.Snap.ATTACH:
			# Only platforms whose deck is as high as the stairs/ladder
			if sd.supports_building and absf(sd.footprint.y - def.footprint.y) < 0.3:
				for side in 4:
					var n: Vector3 = [sx, -sx, sz, -sz][side]
					var along: Vector3 = [sz, sz, sx, sx][side]
					var half: float = sd.footprint.x * 0.5 if side < 2 else sd.footprint.z * 0.5
					var span: float = sd.footprint.z * 0.5 if side < 2 else sd.footprint.x * 0.5
					for slide: float in [-1.0, 0.0, 1.0]:
						var offset := clampf(span - def.footprint.x * 0.5, 0.0, 99.0) * slide
						var edge := st.origin + n * half + along * offset
						out.append(Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), edge + n * (def.footprint.z * 0.5 + 0.02)))
	return out


## A transform at `at` whose X axis runs along `dir`.
static func _along(dir: Vector3, at: Vector3) -> Transform3D:
	var d := _flat(dir)
	return Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), at)


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.0001 else Vector3.RIGHT
