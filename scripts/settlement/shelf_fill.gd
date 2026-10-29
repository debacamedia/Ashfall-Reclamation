class_name ShelfFill
extends MultiMeshInstance3D
## Crates of produce on a settlement's Food Shelves (Increment 19.5). As the
## shelves' inventory fills, more crates appear, bottom shelf first, so you
## can see how full the store is from across the barn.
##
## The crate spots are kept as plain data (`spots`, `colors`) and put into
## the MultiMesh when it loads: a MultiMesh's own instance data isn't kept
## when a scene is saved by the headless build tools.

## The container whose inventory this shows.
@export var container_path: NodePath = ^".."
## Where each crate sits, in the order they fill.
@export var spots: Array[Transform3D] = []
## The produce colour in each crate.
@export var colors: PackedColorArray = PackedColorArray()

var _inv: InventoryComponent


func _ready() -> void:
	if multimesh != null and not spots.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = multimesh.mesh
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, spots[i])
			mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
		multimesh = mm
	var c := get_node_or_null(container_path)
	if c != null:
		_inv = c.get_node_or_null("Inventory") as InventoryComponent
	if _inv != null:
		_inv.contents_changed.connect(func(_slots: PackedInt32Array) -> void: refresh())
		_inv.capacity_changed.connect(refresh)
	refresh.call_deferred()


## How full the shelves are, 0..1 (by slots used).
func fill_fraction() -> float:
	if _inv == null or _inv.slot_count <= 0:
		return 0.0
	return float(_inv.slot_count - _inv.get_free_slot_count()) / float(_inv.slot_count)


func refresh() -> void:
	if multimesh == null:
		return
	var f := fill_fraction()
	multimesh.visible_instance_count = 0 if f <= 0.0 else clampi(ceili(f * multimesh.instance_count), 1, multimesh.instance_count)
