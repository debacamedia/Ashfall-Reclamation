class_name SettlementBuilding
extends Structure
## Something your settlers built at a settlement (Increment 19.6): a length
## of farm fence, a guard post or tower, a bunkhouse, a storehouse or a farm
## plot. It's a Structure like the walls you build yourself (saved under the
## level's "Structures" node, in the navmesh, raiders can break it), and it
## counts toward the settlement it stands in:
##
##   beds         more people can live there (bunkhouse)
##   %Storage     a SalvageContainer added to the settlement's stores
##                (storehouse shelves)
##   GuardSpots/* where guards stand (guard post, tower)
##   FarmSpots/*  where farmers work: two per field (farm plot)
##
## Built by ConstructionSite when a site's work is done. Scenes are made by
## tools/build_settlement_buildings.gd.

## More beds for the settlement.
@export var beds := 0

@onready var storage: SalvageContainer = get_node_or_null("%Storage")


func _ready() -> void:
	super._ready()
	add_to_group("settlement_buildings")
	if storage != null:
		var proxy := storage.get_node_or_null("Prop")
		if proxy != null:
			storage.remove_child(proxy)
			proxy.queue_free()
		storage.is_searched = true
		storage.inventory.max_weight = 0.0
		storage.call("_update_prompt")


## The settlement it stands in (within that settlement's claim radius), or null.
func settlement() -> Settlement:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("settlements"):
		var s := n as Settlement
		if s != null and Vector2(global_position.x - s.global_position.x, global_position.z - s.global_position.z).length() <= s.claim_radius:
			return s
	return null


func guard_spots() -> Array[Node3D]:
	return _markers("GuardSpots")


func farm_spots() -> Array[Node3D]:
	return _markers("FarmSpots")


func _markers(group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var g := get_node_or_null(group)
	if g != null:
		for c in g.get_children():
			if c is Node3D:
				out.append(c)
	return out


func dismantle_block_reason() -> String:
	if storage != null:
		if storage.inventory.get_free_slot_count() < storage.inventory.slot_count:
			return "Empty it first"
		if storage.is_open():
			return "Someone's using it"
	return ""


func move_block_reason() -> String:
	return "Too big to move"
