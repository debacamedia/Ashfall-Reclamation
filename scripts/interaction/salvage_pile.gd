class_name SalvagePile
extends Interactable
## Junk you break down for materials: wooden pallets, broken furniture.
## Hold E to tear it apart; the materials go straight into your inventory and
## the pile disappears. If your bags can't take everything, what's left
## stays in the pile.
##
## Saved like pickups (persist group; removable once used up).
##
## Scenes: res://scenes/world/salvage/*.tscn — Area3D root + Shape + model.

## What it breaks down into.
@export var yields: Dictionary[ItemDefinition, int] = {}
@export var pile_name := "Pallet"
@export var salvage_time := 1.5

## What's still in it (starts as a copy of yields).
var remaining: Dictionary = {}


func _ready() -> void:
	add_to_group("salvage_piles")
	add_to_group("persist")
	if remaining.is_empty():
		for item in yields:
			remaining[item] = yields[item]
	action_name = "Break down"
	object_name = pile_name
	hold_time = salvage_time


func get_prompt(_interactor: Node3D) -> String:
	var parts := []
	for item: ItemDefinition in remaining:
		parts.append("%s ×%d" % [item.display_name, remaining[item]])
	return "Break down %s  (%s)" % [pile_name, ", ".join(parts)]


func get_block_reason(interactor: Node3D) -> String:
	var inv := InventoryComponent.find_on(interactor)
	if inv == null:
		return "Can't carry that"
	for item: ItemDefinition in remaining:
		if inv.can_add(item, 1) > 0:
			return ""
	var first: ItemDefinition = remaining.keys()[0] if not remaining.is_empty() else null
	return inv.get_refusal_reason(first, 1) if first != null else "Empty"


const SOUND_WOOD := preload("res://assets/ashfall_pack_v3/sets/salvage_wood.tres")
const SOUND_METAL := preload("res://assets/ashfall_pack_v3/sets/salvage_metal.tres")

var _break_sound_left := 0.0


## Wood or metal, by what it breaks down into (Resource Pack 3 sounds).
func get_break_sound() -> AudioStream:
	for item: ItemDefinition in yields:
		if String(item.id).begins_with("wood"):
			return SOUND_WOOD
	return SOUND_METAL


## Tearing sounds while someone holds E on it.
func _process(delta: float) -> void:
	_break_sound_left -= delta
	if _break_sound_left > 0.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		var it := (p as PlayerController).interactor
		if it != null and it.focused == self and it.hold_progress > 0.0:
			_break_sound()
			_break_sound_left = randf_range(0.4, 0.6)
			return


func _break_sound() -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = get_break_sound()
	s.bus = &"SFX"
	s.unit_size = 3.0
	s.volume_db = -4.0
	get_parent().add_child(s)  # outlives the pile when it's used up
	s.global_position = global_position + Vector3.UP * 0.4
	s.finished.connect(s.queue_free)
	s.play()


func _perform(interactor: Node3D) -> void:
	var inv := InventoryComponent.find_on(interactor)
	if inv == null:
		return
	for item: ItemDefinition in remaining.keys():
		var got := inv.receive(item, remaining[item])
		remaining[item] -= got
		if remaining[item] <= 0:
			remaining.erase(item)
	_break_sound()
	if remaining.is_empty():
		queue_free()


func save_state() -> Dictionary:
	var left := {}
	for item: ItemDefinition in remaining:
		left[String(item.id)] = remaining[item]
	return {"remaining": left}


func load_state(data: Dictionary) -> void:
	var left: Variant = data.get("remaining")
	if not left is Dictionary:
		return
	remaining.clear()
	for id in left:
		var item := ItemDatabase.get_item(StringName(str(id)))
		var qty: Variant = left[id]
		if item != null and (qty is float or qty is int) and int(qty) > 0:
			remaining[item] = int(qty)
	if remaining.is_empty():
		queue_free()


func is_save_removable() -> bool:
	return true
