class_name NavRebaker
extends Node
## Rebakes a level's navmesh after structures are placed, destroyed or
## loaded, so raiders path around them.
##
## Requests are batched: a burst (loading a save with twenty walls) gives one
## bake a moment later. Baking runs on a worker thread. The level's navmesh
## resource is duplicated before the first runtime bake, so the saved
## .tres (shared by every instance of the level) is never changed.
##
## Usage: NavRebaker.request(any_node_in_the_level). It finds the level's
## "Navigation" NavigationRegion3D by walking up from that node.

signal baked

## Seconds to wait after the last request before baking.
const DELAY := 0.15

var region: NavigationRegion3D
var _pending := false
var _wait := 0.0
var _own_mesh := false


## Asks for a rebake of the level `node` is in. Safe to call often.
static func request(node: Node) -> void:
	var region := find_region(node)
	if region == null or not region.is_inside_tree():
		return
	var rebaker := region.get_node_or_null("NavRebaker") as NavRebaker
	if rebaker == null:
		rebaker = NavRebaker.new()
		rebaker.name = "NavRebaker"
		rebaker.region = region
		region.add_child(rebaker)
	rebaker._pending = true
	rebaker._wait = DELAY


static func find_region(node: Node) -> NavigationRegion3D:
	var n := node
	while n != null:
		var r := n.get_node_or_null("Navigation") as NavigationRegion3D
		if r != null:
			return r
		n = n.get_parent()
	return null


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
