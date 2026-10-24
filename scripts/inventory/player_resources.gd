class_name PlayerResources
extends Node
## What the player is carrying, until the full inventory arrives in
## Increment 6. Decides what picking up an item means:
##   AMMO     → added to the equipped weapon's reserve (up to its maximum)
##   MEDICAL  → used immediately to heal (refused at full health)
##   others   → counted per item (scrap, cloth, fuel, electronics…)
##
## Increment 6 replaces the counting with an InventoryComponent; receive()
## and get_refusal_reason() keep the same meaning so pickups don't change.
##
## AUTHORITY: receive() changes game state — host only in co-op.

signal item_received(item: ItemDefinition, quantity: int)
signal counts_changed

## item id -> quantity
var counts := {}
## item id -> ItemDefinition (for names in the HUD)
var definitions := {}


func get_count(id: StringName) -> int:
	return counts.get(id, 0)


## "" if the player can accept at least one of these, otherwise why not.
func get_refusal_reason(item: ItemDefinition, _quantity: int) -> String:
	var player := get_parent() as PlayerController
	match item.category:
		ItemDefinition.Category.AMMO:
			var weapon := player.weapon if player != null else null
			if weapon == null or weapon.definition.ammo_type != item.ammo_type:
				return "No weapon uses this ammo"
			if weapon.reserve_ammo >= weapon.definition.max_reserve:
				return "Ammo full"
		ItemDefinition.Category.MEDICAL:
			if player != null and player.health.current_health >= player.health.max_health:
				return "Already at full health"
	return ""


## Accepts up to `quantity` of `item`. Returns how many were taken.
func receive(item: ItemDefinition, quantity: int) -> int:
	if quantity <= 0 or get_refusal_reason(item, quantity) != "":
		return 0
	var player := get_parent() as PlayerController
	var taken := quantity
	match item.category:
		ItemDefinition.Category.AMMO:
			var weapon := player.weapon
			taken = mini(quantity, weapon.definition.max_reserve - weapon.reserve_ammo)
			weapon.add_reserve_ammo(taken)
		ItemDefinition.Category.MEDICAL:
			taken = 1
			player.health.heal(item.heal_amount)
		_:
			counts[item.id] = get_count(item.id) + quantity
			definitions[item.id] = item
			counts_changed.emit()
	item_received.emit(item, taken)
	return taken


## Finds the PlayerResources belonging to `node` (a player).
static func find_on(node: Node) -> PlayerResources:
	if node == null:
		return null
	for child in node.get_children():
		if child is PlayerResources:
			return child
	return null
