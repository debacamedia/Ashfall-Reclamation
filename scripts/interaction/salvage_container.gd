class_name SalvageContainer
extends Interactable
## A crate, footlocker or locker you can search and loot.
##
## The first interaction is a hold-E "Search": the LootTable is rolled once
## into the container's own InventoryComponent. After that, a tap opens it.
## Opening hands the container to the player (PlayerController.open_container)
## and the HUD shows the transfer screen. Items move only through validated
## PlayerController.request_take / request_store calls.
##
## Searched state and contents are saved by SaveManager (Increment 8) through
## save_state() / load_state(); containers are in the "persist" group.
##
## Scenes: res://scenes/world/containers/*.tscn
## Root (this Area3D, layer 5) → Shape, Body (StaticBody3D, layer 2), %Lid
## (optional pivot), %Inventory (InventoryComponent), %OpenSound, %SearchSound.

signal searched(container: SalvageContainer)
signal opened(by: Node3D)
signal closed(by: Node3D)

## Name in prompts and on the transfer screen.
@export var container_name := "Supply Crate"
@export var loot_table: LootTable
## Seconds of holding E for the first search.
@export var search_time := 1.2
## 0 = different loot every game; otherwise always the same roll (tests,
## hand-placed story loot).
@export var loot_seed := 0
## Stable id for saves. Empty = the node path inside the level.
@export var container_id: StringName = &""

@export_group("Lid animation")
## Rotation (degrees, local) of %Lid when open.
@export var lid_open_rotation := Vector3(-105, 0, 0)

var is_searched := false
## Who has it open right now (players; several in co-op).
var users: Array[Node3D] = []

var _lid_closed_rotation := Vector3.ZERO
var _lid_tween: Tween

@onready var inventory: InventoryComponent = %Inventory
@onready var _body: CollisionObject3D = get_node_or_null("Body")
@onready var _lid: Node3D = get_node_or_null("%Lid")
@onready var _open_sound: AudioStreamPlayer3D = get_node_or_null("%OpenSound")
@onready var _search_sound: AudioStreamPlayer3D = get_node_or_null("%SearchSound")


func _ready() -> void:
	add_to_group("salvage_containers")
	add_to_group("persist")
	if _lid != null:
		_lid_closed_rotation = _lid.rotation_degrees
	_update_prompt()


func get_id() -> StringName:
	if container_id != &"":
		return container_id
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and scene.is_ancestor_of(self):
		return StringName(str(scene.get_path_to(self)))
	return StringName(str(get_path()))


func get_prompt(_interactor: Node3D) -> String:
	if not is_searched:
		return "Search %s" % container_name
	if inventory.get_free_slot_count() == inventory.slot_count:
		return "Open %s (empty)" % container_name
	return "Open %s" % container_name


## Rolls the loot table into the inventory, once. Returns false if it had
## already been searched.
func search() -> bool:
	if is_searched:
		return false
	is_searched = true
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		if loot_seed != 0:
			rng.seed = loot_seed
		else:
			rng.randomize()
		inventory.max_weight = 0.0
		for stack in loot_table.roll(rng):
			inventory.add_item(stack["item"], stack["qty"])
	_update_prompt()
	searched.emit(self)
	return true


func is_open() -> bool:
	return not users.is_empty()


## Called by PlayerController when it closes the screen or walks away.
func release(by: Node3D) -> void:
	if not users.has(by):
		return
	users.erase(by)
	closed.emit(by)
	if users.is_empty():
		_animate_lid(false)
	_update_prompt()


func _perform(interactor: Node3D) -> void:
	if not is_searched:
		search()
	var player := interactor as PlayerController
	if player != null:
		player.open_container(self)
	if not users.has(interactor):
		users.append(interactor)
	if users.size() == 1:
		_animate_lid(true)
		if _open_sound != null:
			_open_sound.play()
	opened.emit(interactor)


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if _body != null:
		out.append(_body.get_rid())
	return out


func _update_prompt() -> void:
	action_name = "Open" if is_searched else "Search"
	object_name = container_name
	hold_time = 0.0 if is_searched else search_time


func _process(_delta: float) -> void:
	# Rummaging sound while someone holds E to search
	if _search_sound == null or is_searched:
		return
	var searching := false
	for p in get_tree().get_nodes_in_group("players"):
		var pc := p as PlayerController
		if pc != null and pc.interactor != null and pc.interactor.focused == self and pc.interactor.hold_progress >= 0.0:
			searching = true
	if searching and not _search_sound.playing:
		_search_sound.play()
	elif not searching and _search_sound.playing:
		_search_sound.stop()


func _animate_lid(open: bool) -> void:
	if _lid == null or not is_inside_tree():
		return
	if _lid_tween != null:
		_lid_tween.kill()
	_lid_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lid_tween.tween_property(_lid, "rotation_degrees",
		_lid_closed_rotation + lid_open_rotation if open else _lid_closed_rotation, 0.35)


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	return {"id": String(get_id()), "searched": is_searched, "items": inventory.to_data()}


func load_state(data: Dictionary) -> void:
	var searched_value: Variant = data.get("searched", false)
	is_searched = searched_value is bool and searched_value
	inventory.clear()
	var items: Variant = data.get("items", [])
	if items is Array:
		inventory.max_weight = 0.0
		inventory.from_data(items)
	_update_prompt()
