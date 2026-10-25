class_name LootEntry
extends Resource
## One possible drop in a LootTable: which item, how likely, how many.

@export var item: ItemDefinition
## Relative chance against the other entries in the same table.
@export_range(0.0, 100.0, 0.1) var weight := 1.0
@export_range(1, 999) var min_quantity := 1
@export_range(1, 999) var max_quantity := 1
