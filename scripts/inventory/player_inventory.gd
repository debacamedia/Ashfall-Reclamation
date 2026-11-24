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
## The quick bar (Increment 32): part of what you carry. Its medkits and
## food count toward your weight (its guns don't) and are found and used with
## the backpack's (backpack first).
var bar: QuickBar


func get_total_weight() -> float:
	return super.get_total_weight() + (bar.get_total_weight() if bar != null else 0.0)


func count_of(id: StringName) -> int:
	return super.count_of(id) + (bar.count_of(id) if bar != null else 0)


## Backpack first, then the quick bar.
func remove_item(id: StringName, quantity: int) -> int:
	var n := super.remove_item(id, quantity)
	if n < quantity and bar != null:
		n += bar.remove_item(id, quantity - n)
	return n


## A crafting check mustn't take anything off the bar for good either.
func can_exchange(remove: Dictionary, item: ItemDefinition, quantity: int) -> bool:
	if bar == null:
		return super.can_exchange(remove, item, quantity)
	var saved := bar._slots.duplicate()
	var qtys := bar._slots.map(func(e: Variant) -> int: return e["qty"] if e != null else 0)
	bar.set_block_signals(true)
	var fits := super.can_exchange(remove, item, quantity)
	bar._slots = saved
	for i in bar._slots.size():
		if bar._slots[i] != null:
			bar._slots[i]["qty"] = qtys[i]
	bar.set_block_signals(false)
	return fits


## Every item carried, backpack and quick bar.
func _carried() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for i in slot_count:
		if get_slot_item(i) != null:
			out.append(get_slot_item(i))
	if bar != null:
		for i in bar.slot_count:
			if bar.get_slot_item(i) != null:
				out.append(bar.get_slot_item(i))
	return out


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
	for item in _carried():
		if item.category == ItemDefinition.Category.MEDICAL:
			if best == null or item.heal_amount > best.heal_amount:
				best = item
	return best


## The food to eat now for `missing` points of hunger (Increment 21): the
## most filling one that wastes no more than a little, else the least
## filling one there is. Null with nothing to eat.
func find_best_food(missing: float) -> ItemDefinition:
	var foods: Array[ItemDefinition] = []
	for item in _carried():
		if item.food_value > 0.0 and not foods.has(item):
			foods.append(item)
	if foods.is_empty():
		return null
	foods.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.food_value > b.food_value)
	for f in foods:
		if f.food_value <= missing + 8.0:
			return f
	return foods.back()


## How many things to eat you carry.
func count_food() -> int:
	var total := 0
	for inv: InventoryComponent in [self, bar]:
		if inv == null:
			continue
		for i in inv.slot_count:
			var item := inv.get_slot_item(i)
			if item != null and item.food_value > 0.0:
				total += inv.get_slot_quantity(i)
	return total


func count_medical() -> int:
	var total := 0
	for inv: InventoryComponent in [self, bar]:
		if inv == null:
			continue
		for i in inv.slot_count:
			var item := inv.get_slot_item(i)
			if item != null and item.category == ItemDefinition.Category.MEDICAL:
				total += inv.get_slot_quantity(i)
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
