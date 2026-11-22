class_name ZoneBoundary
extends Node3D
## The edge of a zone: an ash storm on land, deep water at the coast.
##
## `polygon` is the playable area seen from above (x, z), and `edge_kinds`
## says what lies past each edge (edge i runs from point i to point i + 1):
##   STORM: the ash storm. Inside, within `warn_distance` of the edge, the
##          haze thickens and the HUD warns you. Past the edge the storm
##          hurts, more the further you go, and an invisible wall
##          (`backstop`, built by the zone) stops you `backstop_distance` out.
##   SEA:   the water gets too deep. A warning near the edge, no damage; the
##          backstop stands in the shallows.
##
## Raiders aren't affected: their navmesh ends at the edge.
##
## EXITS (Increment 25): ZoneExit children mark roads out through the storm.
## Within an exit's gap the storm doesn't hurt and the warning says where
## the road goes; a player who crosses the edge there (on foot or driving)
## is handed to WorldManager.request_travel.
##
## AUTHORITY: damage is decided here, where the game state lives (host).
## The storm's look (fog, ash, wind) is per client: StormEffects reads
## storm_level() for its own player.

enum Kind { STORM, SEA }

## Playable area from above: Vector2(x, z), in order round the edge.
@export var polygon := PackedVector2Array()
## One Kind per edge.
@export var edge_kinds := PackedByteArray()
## The warning (and the haze) starts this far inside the edge (m).
@export var warn_distance := 30.0
## Storm damage per second just past the edge, and at `backstop_distance`.
@export var damage_per_second_min := 4.0
@export var damage_per_second_max := 18.0
## Where the invisible wall stands past each edge (m).
@export var backstop_distance := 32.0
@export var sea_backstop_distance := 10.0
@export var tick_interval := 0.5
## Shown on the death screen.
@export var death_message := "Choked to death in the ash storm"

## player -> seconds until their next damage step
var _timers := {}
## player -> seconds before an exit asks to travel again (after a refusal)
var _exit_waits := {}


func _ready() -> void:
	add_to_group("zone_boundary")


## The zone's boundary (the first one under the scene), or null.
static func find_in(tree: SceneTree) -> ZoneBoundary:
	return tree.get_first_node_in_group("zone_boundary") as ZoneBoundary if tree != null else null


func is_inside(p: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), polygon)


## Distance to the edge: negative inside, positive outside (m).
func signed_distance(p: Vector3) -> float:
	var d := _nearest(Vector2(p.x, p.z))["distance"] as float
	return -d if is_inside(p) else d


## What lies past the nearest edge (Kind).
func nearest_kind(p: Vector3) -> int:
	return _nearest(Vector2(p.x, p.z))["kind"]


## How thick the storm is at `p`, for the haze and the warning: 0 well
## inside, rising through the warning band to 0.6 at the edge, 1 by 15 m
## past it. Sea edges give 0 (no storm over the water).
func storm_level(p: Vector3) -> float:
	var n := _nearest(Vector2(p.x, p.z))
	if n["kind"] != Kind.STORM:
		return 0.0
	var d := -(n["distance"] as float) if is_inside(p) else (n["distance"] as float)
	if d < -warn_distance:
		return 0.0
	if d <= 0.0:
		return 0.6 * (1.0 - (-d) / warn_distance)
	return minf(0.6 + 0.4 * d / 15.0, 1.0)


## The way out at `p` (a ZoneExit whose gap covers it), or null.
func exit_at(p: Vector3) -> ZoneExit:
	for c in get_children():
		var x := c as ZoneExit
		if x != null and x.covers(p):
			return x
	return null


## Every way out of the zone.
func exits() -> Array[ZoneExit]:
	var out: Array[ZoneExit] = []
	for c in get_children():
		if c is ZoneExit:
			out.append(c)
	return out


## The warning for someone standing at `p` ("" if none).
func warning_at(p: Vector3) -> String:
	var n := _nearest(Vector2(p.x, p.z))
	var d := -(n["distance"] as float) if is_inside(p) else (n["distance"] as float)
	if d < -warn_distance * 0.5:
		return ""
	var way_out := exit_at(p)
	if way_out != null:
		return "The road leads on through the storm to %s" % way_out.destination_name
	if n["kind"] == Kind.SEA:
		return "The water's too deep to go any further" if d > -3.0 else ""
	if d > 0.0:
		return "The ash storm is choking you. Turn back!"
	return "The ash storm is too thick ahead. Turn back"


## Storm damage per second at `p` (0 inside or at the sea).
func damage_per_second_at(p: Vector3) -> float:
	if is_inside(p) or exit_at(p) != null:
		return 0.0
	var n := _nearest(Vector2(p.x, p.z))
	if n["kind"] != Kind.STORM:
		return 0.0
	var t := clampf((n["distance"] as float) / backstop_distance, 0.0, 1.0)
	return lerpf(damage_per_second_min, damage_per_second_max, t)


func _physics_process(delta: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var player := p as PlayerController
		if player == null or player.is_dead():
			_timers.erase(p)
			continue
		_check_exit(player, delta)
		var dps := damage_per_second_at(player.global_position)
		if dps <= 0.0:
			_timers.erase(p)
			continue
		if not _timers.has(p):
			_timers[p] = tick_interval  # a moment's grace on stepping out
		_timers[p] -= delta
		if _timers[p] <= 0.0:
			_timers[p] += tick_interval
			var info := DamageInfo.create(dps * tick_interval, DamageInfo.Type.ENVIRONMENT, self)
			info.hit_position = player.global_position
			player.health.apply_damage(info)


## Crossed the edge through an exit: travel (asked once, then again a few
## seconds after a refusal).
func _check_exit(player: PlayerController, delta: float) -> void:
	if _exit_waits.has(player):
		_exit_waits[player] -= delta
		if _exit_waits[player] > 0.0:
			return
		_exit_waits.erase(player)
	if is_inside(player.global_position):
		return
	var way_out := exit_at(player.global_position)
	if way_out == null:
		return
	var world := get_node_or_null("/root/WorldManager")
	if world == null or world.is_travelling:
		return
	if not world.request_travel(player, way_out):
		_exit_waits[player] = 3.0


## The nearest edge to `q`: {"distance", "kind", "index"}.
func _nearest(q: Vector2) -> Dictionary:
	var best := INF
	var kind: int = Kind.STORM
	var index := -1
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		var c := Geometry2D.get_closest_point_to_segment(q, a, b)
		var d := q.distance_to(c)
		if d < best:
			best = d
			index = i
			kind = edge_kinds[i] if i < edge_kinds.size() else Kind.STORM
	return {"distance": best, "kind": kind, "index": index}


## The polygon pushed out by `distance` (m), with mitred corners.
static func grow(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(points, distance, Geometry2D.JOIN_MITER)
	return out[0] if out.size() > 0 else points
