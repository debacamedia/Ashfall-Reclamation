class_name StorageStructure
extends Structure
## A storage crate you build: an empty SalvageContainer that keeps whatever
## you put in it (saved with the region). It can only be dismantled empty.
##
## Scene: res://scenes/structures/storage_crate.tscn. Root → %Storage (a
## SalvageContainer with no loot table) → Body, Inventory...

@onready var storage: SalvageContainer = %Storage


func _ready() -> void:
	super._ready()
	if not storage.is_searched:
		storage.is_searched = true  # nothing to search: it's yours
		storage.inventory.max_weight = 0.0
		storage._update_prompt()


func move_block_reason() -> String:
	return "Someone's using it" if storage.is_open() else ""


func dismantle_block_reason() -> String:
	if storage.inventory.get_free_slot_count() < storage.inventory.slot_count:
		return "Empty it first"
	if storage.is_open():
		return "Someone's using it"
	return ""
