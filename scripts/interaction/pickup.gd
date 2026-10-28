class_name Pickup
extends Interactable
## An item lying in the world. Interacting puts it into the interactor's
## inventory (InventoryComponent). If only part fits (slots or weight), the
## remainder stays on the ground.
##
## Scene: res://scenes/items/pickup.tscn — set `item` and `quantity`; the
## item's world_model is shown automatically.

signal picked_up(item: ItemDefinition, quantity: int, by: Node3D)

@export var item: ItemDefinition:
	set(value):
		item = value
		if is_inside_tree():
			_refresh()
@export var quantity := 1:
	set(value):
		quantity = maxi(value, 0)
		if is_inside_tree():
			_refresh()
## Gentle bob and spin so loot is easy to spot.
@export var animate := false

var _model: Node3D
var _highlight := false
var _time := 0.0
var _highlight_material: StandardMaterial3D


func _ready() -> void:
	action_name = "Pick up"
	add_to_group("pickups")
	add_to_group("persist")
	_refresh()


func _process(delta: float) -> void:
	if animate and _model != null:
		_time += delta
		_model.rotation.y += delta * 0.8
		_model.position.y = 0.05 + sin(_time * 2.0) * 0.04


func _refresh() -> void:
	if item == null:
		return
	object_name = item.get_label(quantity)
	hold_time = item.pickup_hold_time
	if _model != null:
		_model.queue_free()
		_model = null
	if item.world_model != null:
		_model = item.world_model.instantiate() as Node3D
		add_child(_model)
	set_highlighted(_highlight)


func get_block_reason(interactor: Node3D) -> String:
	if item == null or quantity <= 0:
		return "Empty"
	if item.category == ItemDefinition.Category.WEAPON:
		var pc := interactor as PlayerController
		return pc.gun_refusal_reason(item.weapon) if pc != null and item.weapon != null else "Can't carry that"
	var inventory := InventoryComponent.find_on(interactor)
	if inventory == null:
		return "Can't carry this"
	return inventory.get_refusal_reason(item, quantity)


func get_prompt(interactor: Node3D) -> String:
	var player := interactor as PlayerController
	if item != null and item.weapon != null and player != null \
			and player.gun_destination(item.weapon) == PlayerController.GUN_TO_BACKPACK:
		return "%s %s (spare, into your backpack)" % [action_name, object_name]
	return "%s %s" % [action_name, object_name]


func set_highlighted(on: bool) -> void:
	_highlight = on
	if _model == null:
		return
	if _highlight_material == null:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_highlight_material.albedo_color = Color(1.0, 0.85, 0.5, 0.18)
	for mesh in _model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = _highlight_material if on else null


func _perform(interactor: Node3D) -> void:
	if item.category == ItemDefinition.Category.WEAPON and item.weapon != null:
		_take_weapon(interactor)
		return
	var inventory := InventoryComponent.find_on(interactor)
	var taken := inventory.receive(item, quantity)
	if taken <= 0:
		return
	picked_up.emit(item, taken, interactor)
	quantity -= taken
	if quantity <= 0:
		queue_free()


## Spawns a pickup into the world at `position` (world space; used for loot
## drops). The parent may be a site that isn't at the origin.
static func spawn(parent: Node, definition: ItemDefinition, amount: int, position: Vector3) -> Pickup:
	var scene := load("res://scenes/items/pickup.tscn") as PackedScene
	var pickup := scene.instantiate() as Pickup
	pickup.item = definition
	pickup.quantity = amount
	var parent3d := parent as Node3D
	pickup.position = parent3d.to_local(position) if parent3d != null and parent3d.is_inside_tree() else position
	parent.add_child(pickup)
	return pickup


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var p := global_position
	return {"item": String(item.id) if item != null else "", "quantity": quantity,
		"position": [p.x, p.y, p.z], "yaw": rotation.y}


func load_state(data: Dictionary) -> void:
	var def := ItemDatabase.get_item(StringName(str(data.get("item", ""))))
	var qty: Variant = data.get("quantity")
	if def == null or not (qty is float or qty is int) or int(qty) <= 0:
		queue_free()  # nothing valid to show
		return
	item = def
	quantity = int(qty)
	var raw: Variant = data.get("position")
	if raw is Array and raw.size() == 3 and raw.all(func(v: Variant) -> bool: return v is float or v is int):
		global_position = Vector3(raw[0], raw[1], raw[2])
	var yaw: Variant = data.get("yaw")
	if yaw is float or yaw is int:
		rotation.y = float(yaw)


## Pickups can disappear (taken), so a save that doesn't list one removes it.
func is_save_removable() -> bool:
	return true


## Guns go into their weapon slot, or your backpack as a spare if you
## already have that gun or a better one (Increment 16.7).
func _take_weapon(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player == null:
		return
	if player.receive_gun(item.weapon) != "":
		picked_up.emit(item, 1, interactor)
		queue_free()
