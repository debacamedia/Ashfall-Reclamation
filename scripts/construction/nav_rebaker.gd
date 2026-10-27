class_name NavRebaker
extends Node
## Rebakes a level's navmesh after structures are placed, destroyed or
## loaded, so raiders path around them.
##
## Requests are batched: a burst (loading a save with twenty walls) gives one
## bake a moment later. Baking runs on a worker thread. The level's navmesh
## resource is duplicated before the first runtime bake, so the saved
## resource (shared by every instance of the level) is never changed.
##
## A level's "Navigation" node is either one NavigationRegion3D, or (in a
## zone, Increment 15) a node holding a NavigationRegion3D per 100 m tile.
## With tiles, only the tiles near the change are rebaked.
##
## Usage: NavRebaker.request(any_node_in_the_level). It finds the level's
## "Navigation" node by walking up from that node.

signal baked

## Seconds to wait after the last request before baking.
const DELAY := 0.15
## A change this close to a tile's edge rebakes the neighbouring tile too (m).
const TILE_MARGIN := 10.0

var region: NavigationRegion3D
var _pending := false
var _wait := 0.0
var _own_mesh := false


## Asks for a rebake where `node` is. Safe to call often.
static func request(node: Node) -> void:
	for region in regions_for(node):
		if not region.is_inside_tree():
			continue
		var rebaker := region.get_node_or_null("NavRebaker") as NavRebaker
		if rebaker == null:
			rebaker = NavRebaker.new()
			rebaker.name = "NavRebaker"
			rebaker.region = region
			region.add_child(rebaker)
		rebaker._pending = true
		rebaker._wait = DELAY


## The level's "Navigation" node above `node`: a NavigationRegion3D, or the
## node holding a zone's tiles (null if there's none).
static func find_navigation(node: Node) -> Node:
	var n := node
	while n != null:
		var nav := n.get_node_or_null("Navigation")
		if nav is NavigationRegion3D or (nav != null and _has_tiles(nav)):
			return nav
		n = n.get_parent()
	return null


## The single region of a level that has one (null for tiled zones).
static func find_region(node: Node) -> NavigationRegion3D:
	return find_navigation(node) as NavigationRegion3D


## The regions a change at `node` affects: the level's only region, or the
## tiles within TILE_MARGIN of the node's position.
static func regions_for(node: Node) -> Array[NavigationRegion3D]:
	var out: Array[NavigationRegion3D] = []
	var nav := find_navigation(node)
	if nav == null:
		return out
	if nav is NavigationRegion3D:
		out.append(nav)
		return out
	var n3 := node as Node3D
	if n3 == null or not n3.is_inside_tree():
		return out
	var p := n3.global_position
	for c in nav.get_children():
		var r := c as NavigationRegion3D
		if r == null or r.navigation_mesh == null:
			continue
		var box := r.navigation_mesh.filter_baking_aabb
		if p.x >= box.position.x - TILE_MARGIN and p.x <= box.end.x + TILE_MARGIN \
				and p.z >= box.position.z - TILE_MARGIN and p.z <= box.end.z + TILE_MARGIN:
			out.append(r)
	return out


## Every region under a level's Navigation node.
static func all_regions(nav: Node) -> Array[NavigationRegion3D]:
	var out: Array[NavigationRegion3D] = []
	if nav is NavigationRegion3D:
		out.append(nav)
	elif nav != null:
		for c in nav.get_children():
			if c is NavigationRegion3D:
				out.append(c)
	return out


## True while any region under `nav` is waiting for or running a rebake.
static func any_busy(nav: Node) -> bool:
	for r in all_regions(nav):
		var rb := r.get_node_or_null("NavRebaker") as NavRebaker
		if rb != null and rb.is_busy():
			return true
	return false


static func _has_tiles(nav: Node) -> bool:
	for c in nav.get_children():
		if c is NavigationRegion3D:
			return true
	return false


## True while a rebake is waiting or running.
func is_busy() -> bool:
	return _pending or (region != null and region.is_baking())


func _ready() -> void:
	if region == null:
		region = get_parent() as NavigationRegion3D
	region.bake_finished.connect(func() -> void: baked.emit())


func _process(delta: float) -> void:
	if not _pending or region == null or region.is_baking():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_pending = false
	if not _own_mesh and region.navigation_mesh != null:
		region.navigation_mesh = region.navigation_mesh.duplicate() as NavigationMesh
		_own_mesh = true
	region.bake_navigation_mesh(true)
