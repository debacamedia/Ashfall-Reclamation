class_name QuickBar
extends InventoryComponent
## The quick bar (Increment 32): eight slots, keys 1-8, that you fill
## yourself with anything you can hold: guns and blades (each its own, with
## its rounds and attachments), medkits and bandages, food, and later the
## Field Manual. Two pistols side by side if you like.
##
## It's part of what you carry: PlayerInventory counts its medkits and food
## (H and J use them too) and their weight, and dying drops what's on it
## (but your blade) into your gear. Guns and blades on the bar weigh nothing,
## as they did in the old weapon slots: they're slung and belted, and a save
## that carried five guns still carries them. WeaponSlots holds the guns in
## your hands.
##
## A child of the player's Inventory node, made by PlayerController.

const SIZE := 8

## The backpack whose weight limit this shares (set by PlayerController).
var owner_inventory: InventoryComponent
## Called before a gun's state is read or it leaves the bar: WeaponSlots
## writes its live guns' rounds and attachments back into their entries.
var sync: Callable


func _init() -> void:
	slot_count = SIZE
	max_weight = 0.0
	super._init()


## Can `item` go on the quick bar at all?
static func holdable(item: ItemDefinition) -> bool:
	if item == null:
		return false
	return item.weapon != null or item.holdable or item.category == ItemDefinition.Category.MEDICAL \
		or item.category == ItemDefinition.Category.FOOD


## Does `item` stay with you when you die (your blade, the Field Manual)?
static func kept_on_death(item: ItemDefinition) -> bool:
	return item != null and (item.keep_on_death or (item.weapon != null and item.weapon.melee))


## Why `item` can't go on the bar ("" = it can).
static func refusal_reason(item: ItemDefinition) -> String:
	if item == null:
		return "Nothing there"
	if holdable(item):
		return ""
	if item.category == ItemDefinition.Category.AMMO:
		return "Rounds stay in your backpack"
	if item.is_pack() or item.is_armour():
		return "Wear it instead"
	return "You can't hold a " + item.display_name


## What the bar weighs: its medkits and food (guns and blades are free).
func get_total_weight() -> float:
	var total := 0.0
	for s in _slots:
		if s != null and (s["item"] as ItemDefinition).weapon == null:
			total += (s["item"] as ItemDefinition).weight * s["qty"]
	return total


## Only things you can hold; medkits and food within what you can carry.
func can_add(item: ItemDefinition, quantity: int) -> int:
	if not holdable(item):
		return 0
	var fit := super.can_add(item, quantity)
	if item.weapon == null and owner_inventory != null and owner_inventory.max_weight > 0.0 and item.weight > 0.0:
		var by_weight := int(floor((owner_inventory.max_weight - owner_inventory.get_total_weight()) / item.weight + 0.0001))
		fit = mini(fit, maxi(by_weight, 0))
	return fit


## The first empty slot (0-based), or -1.
func first_empty() -> int:
	for i in slot_count:
		if is_slot_empty(i):
			return i
	return -1


## The entry itself (not a copy): WeaponSlots ties a live gun to it.
func entry(index: int) -> Variant:
	return _slots[index] if index >= 0 and index < _slots.size() else null


func _sync() -> void:
	if sync.is_valid():
		sync.call()


func add_to_slot(index: int, item: ItemDefinition, quantity: int, state: Dictionary = {}, ignore_weight := false) -> int:
	var limit := owner_inventory.max_weight if owner_inventory != null else 0.0
	if ignore_weight and owner_inventory != null:
		owner_inventory.max_weight = 0.0
	var n := super.add_to_slot(index, item, quantity, state, ignore_weight)
	if owner_inventory != null:
		owner_inventory.max_weight = limit
	return n


func get_slot_state(index: int) -> Dictionary:
	_sync()
	return super.get_slot_state(index)


func take_from_slot(index: int, quantity: int = -1) -> Dictionary:
	_sync()
	return super.take_from_slot(index, quantity)


func transfer_slot_to(index: int, other: InventoryComponent, quantity: int = -1) -> int:
	_sync()
	return super.transfer_slot_to(index, other, quantity)


func to_data() -> Array:
	_sync()
	return super.to_data()
