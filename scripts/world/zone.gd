class_name Zone
extends Node3D
## The root of a zone level (Increment 15): one seamless stretch of the map
## holding several sites (Outpost 17, Halden's Crossing, …), with an ash-storm
## edge (ZoneBoundary). See levels/early_zone/.
##
## On load it gives every small thing a draw distance, so a town 500 m away
## costs only its big shapes: the haze hides it anyway. Before that, each
## site's plain building meshes are merged and its interiors culled early
## (StaticBatcher, Increment 16.5).

## Draw distances (m) by the size of the thing.
const SMALL := 2.5     ## props, loot, signs: under this size
const MEDIUM := 9.0    ## furniture, vehicles, sheds
const SMALL_RANGE := 130.0
const MEDIUM_RANGE := 320.0
const LARGE_RANGE := 750.0

## How many meshes were given a draw distance (read by tests).
var ranged := 0
## Per site: what StaticBatcher did (read by tests and the benchmark).
var batch_stats := {}
## Off to compare before and after (the benchmark's --no-batch).
@export var batch_sites := true


func _ready() -> void:
	if batch_sites:
		var t0 := Time.get_ticks_msec()
		for site in sites():
			batch_stats[site.name] = StaticBatcher.batch(site)
		batch_stats["_ms"] = Time.get_ticks_msec() - t0
	apply_draw_distances(self)


## The zone's map (Increment 17): map.tres beside the zone's scene, or null.
func get_map() -> ZoneMap:
	return Zone.map_for(scene_file_path)


static func map_for(scene_path: String) -> ZoneMap:
	var path := scene_path.get_base_dir().path_join("map.tres")
	return load(path) as ZoneMap if scene_path != "" and ResourceLoader.exists(path) else null


## The zone `node` is in (its nearest Zone ancestor), or null.
static func of(node: Node) -> Zone:
	var n := node
	while n != null:
		if n is Zone:
			return n
		n = n.get_parent()
	return null


## The places in the zone: each is its own level scene instanced here.
func sites() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in get_children():
		if c is Node3D and c.scene_file_path.begins_with("res://levels/") and c.has_meta("region_name"):
			out.append(c)
	return out


func apply_draw_distances(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.visibility_range_end > 0.0 or g.has_meta("no_draw_distance"):
			continue  # set already (terrain, rocks)
		var size := _size_of(g)
		if size <= 0.0:
			continue
		g.visibility_range_end = SMALL_RANGE if size < SMALL else (MEDIUM_RANGE if size < MEDIUM else LARGE_RANGE)
		g.visibility_range_end_margin = 8.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		ranged += 1


static func _size_of(g: GeometryInstance3D) -> float:
	var box := g.get_aabb()
	var s := g.global_transform.basis.get_scale() if g.is_inside_tree() else g.transform.basis.get_scale()
	var e := box.size * s.abs()
	return maxf(e.x, maxf(e.y, e.z))
