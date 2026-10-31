class_name Timber
extends Interactable
## Wood you can chop (Increment 19.7): a dead tree or a fallen log. Hold E
## to cut it up; the wood goes into your backpack (craft it into planks, K).
## A tree leaves a stump, a log nothing; either grows back after
## `regrow_hours` (a few days: a settlement hour is a minute of play).
##
## Saved with the game (persist): how much is left, whether it's been cut,
## and how long until it grows back.
##
## Scenes: res://scenes/world/timber/*.tscn (tools/build_timber.gd).
## Root (this Area3D, the bit you look at) → Shape, %Standing (the tree or
## log, with its StaticBody), %Stump (optional, shown once it's cut).

const WOOD := &"wood"
const SOUND := preload("res://assets/ashfall_pack_v3/sets/salvage_wood.tres")

@export var timber_name := "Dead Tree"
@export var wood := 8
@export var chop_time := 3.0
## In settlement hours (a minute of play each).
@export var regrow_hours := 72.0
@export var hour_seconds := 60.0

## Wood still in it.
var remaining := -1
var cut := false
## Seconds until it grows back (while cut).
var regrow_left := 0.0

var _sound_left := 0.0

@onready var standing: Node3D = %Standing
@onready var stump: Node3D = get_node_or_null("%Stump")


func _ready() -> void:
	add_to_group("timber")
	add_to_group("persist")
	if remaining < 0:
		remaining = wood
	action_name = "Chop"
	object_name = timber_name
	hold_time = chop_time
	_apply()


func get_prompt(_interactor: Node3D) -> String:
	return "Chop %s  (Wood ×%d)" % [timber_name, remaining]


func get_block_reason(interactor: Node3D) -> String:
	if cut:
		return "Cut down: it'll grow back"
	var inv := InventoryComponent.find_on(interactor)
	if inv == null:
		return "Can't carry that"
	var item := ItemDatabase.get_item(WOOD)
	return "" if inv.can_add(item, 1) > 0 else inv.get_refusal_reason(item, 1)


func _perform(interactor: Node3D) -> void:
	var inv := InventoryComponent.find_on(interactor)
	if inv == null or cut:
		return
	remaining -= inv.receive(ItemDatabase.get_item(WOOD), remaining)
	_sound()
	if remaining <= 0:
		cut_down()


## Felled: a stump (or nothing) until it grows back.
func cut_down() -> void:
	cut = true
	remaining = 0
	regrow_left = regrow_hours * hour_seconds
	_apply()


func regrow() -> void:
	cut = false
	remaining = wood
	regrow_left = 0.0
	_apply()


func _apply() -> void:
	if standing == null:
		return
	standing.visible = not cut
	for cs in standing.find_children("*", "CollisionShape3D", true, false):
		(cs as CollisionShape3D).set_deferred("disabled", cut)
	if stump != null:
		stump.visible = cut
	enabled = not cut
	set_physics_process(cut)


func _physics_process(delta: float) -> void:
	if not cut:
		return
	regrow_left -= delta
	if regrow_left <= 0.0:
		regrow()


## Chopping sounds while someone holds E on it.
func _process(delta: float) -> void:
	if cut:
		return
	_sound_left -= delta
	if _sound_left > 0.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		var it := (p as PlayerController).interactor
		if it != null and it.focused == self and it.hold_progress > 0.0:
			_sound()
			_sound_left = randf_range(0.45, 0.65)
			return


func _sound() -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = SOUND
	s.bus = &"SFX"
	s.unit_size = 4.0
	s.volume_db = -3.0
	get_parent().add_child(s)
	s.global_position = global_position + Vector3.UP * 1.0
	s.finished.connect(s.queue_free)
	s.play()


func save_state() -> Dictionary:
	return {"remaining": remaining, "cut": cut, "regrow_left": regrow_left}


func load_state(data: Dictionary) -> void:
	var r: Variant = data.get("remaining")
	if (r is int or r is float) and is_finite(float(r)):
		remaining = clampi(int(r), 0, wood)
	cut = data.get("cut") is bool and data["cut"]
	var g: Variant = data.get("regrow_left")
	regrow_left = clampf(float(g), 0.0, regrow_hours * hour_seconds) if (g is int or g is float) and is_finite(float(g)) else 0.0
	if not cut and remaining <= 0:
		remaining = wood
	if cut and regrow_left <= 0.0:
		regrow_left = regrow_hours * hour_seconds
	_apply()


func is_save_removable() -> bool:
	return false
