class_name PlayerInventory
extends InventoryComponent
## The player's backpack: an InventoryComponent plus a starting loadout and a
## few player-specific helpers (finding medkits, topping up ammo on respawn).
##
## Child of the Player scene, named "Inventory" (%Inventory).

## Given once when the game starts (not on respawn).
@export var starting_items: Dictionary[ItemDefinition, int] = {}

var _loadout_given := false


func _ready() -> void:
	super._ready()
	give_starting_items()


func give_starting_items() -> void:
	if _loadout_given:
		return
	_loadout_given = true
	for item: ItemDefinition in starting_items:
		add_item(item, starting_items[item])


## The medical item to use for a quick heal (largest heal first), or null.
func find_best_medical() -> ItemDefinition:
	var best: ItemDefinition = null
	for i in slot_count:
		var item := get_slot_item(i)
		if item != null and item.category == ItemDefinition.Category.MEDICAL:
			if best == null or item.heal_amount > best.heal_amount:
				best = item
	return best


func count_medical() -> int:
	var total := 0
	for i in slot_count:
		var item := get_slot_item(i)
		if item != null and item.category == ItemDefinition.Category.MEDICAL:
			total += get_slot_quantity(i)
	return total


## Makes sure at least `minimum` rounds of `ammo_type` are carried (used on
## respawn so a player is never left without ammo). Ignores weight limits.
func ensure_minimum_ammo(ammo_type: StringName, minimum: int) -> void:
	var missing := minimum - count_ammo(ammo_type)
	if missing <= 0:
		return
	var item := ItemDatabase.find_ammo_item(ammo_type)
	if item == null:
		return
	var saved_limit := max_weight
	max_weight = 0.0
	add_item(item, missing)
	max_weight = saved_limit
