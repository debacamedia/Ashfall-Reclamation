class_name ContainerProp
extends LevelProp
## Makes a salvage container (supply crate, footlocker, weapons locker) its
## parent movable (F) and scrappable (X) in build mode. The container keeps
## its own script and save data (searched, contents); this child node stands
## in for it as a Structure (the "structure_proxy" meta on the container, see
## Structure.from_collider) and saves where it is and whether it's scrapped.
##
## Contents move with it. Scrapping needs it searched and empty, so no loot
## is ever lost.
##
## Scenes: res://scenes/world/containers/*.tscn → Prop (this, at the origin).
## Removed from the storage crate you build (StorageStructure), which is a
## Structure of its own.

var container: SalvageContainer


func _ready() -> void:
	container = get_parent() as SalvageContainer
	if container != null:
		container.set_meta("structure_proxy", self)
	super._ready()


func get_visual_root() -> Node3D:
	return container if container != null else self


func move_block_reason() -> String:
	return "Someone's using it" if container != null and container.is_open() else ""


func dismantle_block_reason() -> String:
	if container == null:
		return "Can't do that now"
	if container.is_open():
		return "Someone's using it"
	if not container.is_searched:
		return "Search it first"
	if container.inventory.get_free_slot_count() < container.inventory.slot_count:
		return "Empty it first"
	return ""
