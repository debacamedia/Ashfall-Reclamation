class_name PlayerInventory
extends InventoryComponent
## The player's backpack: an InventoryComponent plus a starting loadout and a
## few player-specific helpers (finding medkits, topping up ammo on respawn).
##
## Child of the Player scene, named "Inventory" (%Inventory).

## Given once when the game starts (not on respawn).
@export var starting_items: Dictionary[ItemDefinition, int] = {}

## What you carry with no backpack on: the satchel you start with
## (Increment 16.8). It can't be lost.
const SATCHEL_SLOTS := 24
const SATCHEL_WEIGHT := 30.0

## The backpack you're wearing (an item with pack_slots), or null for the
## satchel. Change it through PlayerController.request_wear_pack.
var pack: ItemDefinition


static func slots_for(def: ItemDefinition) -> int:
	return def.pack_slots if def != null and def.is_pack() else SATCHEL_SLOTS


static func weight_for(def: ItemDefinition) -> float:
	return def.pack_carry_weight if def != null and def.is_pack() else SATCHEL_WEIGHT


## Puts on `def` (null = back to the satchel) if everything still fits.
## Doesn't move the pack items themselves (PlayerController does).
func set_pack(def: ItemDefinition) -> bool:
	if not set_capacity(slots_for(def), weight_for(def)):
		return false
	pack = def
	return true

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
