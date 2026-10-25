class_name InventoryScreen
extends Control
## The inventory window (Tab / I). Shows the player's slots in a grid, the
## equipped weapon, carry weight and details of the selected item, with Use
## and Drop buttons. Left-click selects, right-click uses, drag to move or
## merge stacks, drag outside the window to drop on the ground.
##
## While open, the mouse is free and gameplay input is ignored, but the world
## keeps running — raiders don't wait.
##
## Lives under the HUD: res://scenes/ui/hud.tscn → Root/%InventoryScreen.
## UI requests go through PlayerController / InventoryComponent methods, which
## validate them (and will become host requests in co-op).

const SLOT_SCENE_PATH := "res://scenes/ui/inventory_slot.tscn"

## Set by the HUD.
var player: PlayerController:
	set(value):
		if player == value:
			return
		_unbind()
		player = value
		_bind()

var selected := -1
var _slots: Array[InventorySlot] = []

@onready var _grid: GridContainer = %Grid
@onready var _weight_label: Label = %WeightLabel
@onready var _weight_bar: ProgressBar = %WeightBar
@onready var _weapon_label: Label = %EquippedLabel
@onready var _detail_name: Label = %DetailName
@onready var _detail_info: Label = %DetailInfo
@onready var _detail_desc: Label = %DetailDescription
@onready var _use_button: Button = %UseButton
@onready var _drop_button: Button = %DropButton
@onready var _window: Control = %Window


func _ready() -> void:
	visible = false
	_use_button.pressed.connect(_on_use_pressed)
	_drop_button.pressed.connect(_on_drop_pressed)


func get_inventory() -> PlayerInventory:
	return player.inventory if player != null else null


func is_open() -> bool:
	return visible


func open() -> void:
	if player == null or player.is_dead() or get_inventory() == null:
		return
	visible = true
	player.player_input.set_ui_open(true)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.player_input.set_ui_open(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if player == null or not player.controlled_locally or player.current_container != null:
		return
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and player != null and player.is_dead():
		close()


# ---------------------------------------------------------------- requests

## Move/merge/swap between two slots (from drag and drop).
func request_move(from: int, to: int) -> void:
	var inv := get_inventory()
	if inv != null and inv.move_slot(from, to):
		selected = to


func request_use(index: int) -> void:
	var inv := get_inventory()
	if inv == null:
		return
	var item := inv.get_slot_item(index)
	if item != null:
		player.request_use_item(item)


func request_drop(index: int) -> void:
	if player != null and player.request_drop_slot(index) != null and selected == index:
		selected = -1
		_refresh()


## A slot was dropped onto another slot of this screen: move/merge/swap.
func handle_slot_drop(data: Dictionary, target: InventorySlot) -> void:
	if data.get("inventory") == get_inventory():
		request_move(int(data["inventory_slot"]), target.index)


# ---------------------------------------------------------------- dropping onto the background

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# Anywhere outside the window counts as "drop on the ground"
	return data is Dictionary and data.has("inventory_slot") and data.get("inventory") == get_inventory() \
		and not _window.get_global_rect().has_point(get_global_transform() * at_position)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	request_drop(int(data["inventory_slot"]))


# ---------------------------------------------------------------- display

func _bind() -> void:
	if player == null or not is_node_ready():
		return
	var inv := get_inventory()
	if inv == null:
		return
	inv.contents_changed.connect(_on_contents_changed)
	for child in _grid.get_children():
		child.queue_free()
	_slots.clear()
	var slot_scene := load(SLOT_SCENE_PATH) as PackedScene
	for i in inv.slot_count:
		var slot := slot_scene.instantiate() as InventorySlot
		slot.index = i
		slot.screen = self
		slot.inventory = inv
		slot.clicked.connect(_on_slot_clicked)
		slot.activated.connect(request_use)
		_grid.add_child(slot)
		_slots.append(slot)
	_refresh()


func _unbind() -> void:
	var inv := get_inventory()
	if inv != null and inv.contents_changed.is_connected(_on_contents_changed):
		inv.contents_changed.disconnect(_on_contents_changed)


func _on_contents_changed(_changed: PackedInt32Array) -> void:
	if visible:
		_refresh()


func _on_slot_clicked(index: int, button: MouseButton) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		request_use(index)
	selected = index
	_refresh()


func _on_use_pressed() -> void:
	if selected >= 0:
		request_use(selected)


func _on_drop_pressed() -> void:
	if selected >= 0:
		request_drop(selected)


func _refresh() -> void:
	var inv := get_inventory()
	if inv == null:
		return
	if selected >= 0 and inv.is_slot_empty(selected):
		selected = -1
	for slot in _slots:
		slot.show_stack(inv.get_slot_item(slot.index), inv.get_slot_quantity(slot.index), slot.index == selected)

	var weight := inv.get_total_weight()
	_weight_label.text = "%.1f / %.0f kg" % [weight, inv.max_weight]
	_weight_bar.value = 100.0 * weight / maxf(inv.max_weight, 0.001)

	var weapon := player.weapon
	if weapon != null:
		_weapon_label.text = "%s\n%d / %d  rounds" % [weapon.definition.display_name, weapon.ammo_in_magazine, weapon.reserve_ammo]
	else:
		_weapon_label.text = "Nothing equipped"

	var item := inv.get_slot_item(selected) if selected >= 0 else null
	_use_button.disabled = item == null or item.category != ItemDefinition.Category.MEDICAL
	_drop_button.disabled = item == null
	if item == null:
		_detail_name.text = "Select an item"
		_detail_info.text = ""
		_detail_desc.text = "Left-click: select   ·   Right-click: use\nDrag: move or stack   ·   Drag outside: drop"
		return
	var qty := inv.get_slot_quantity(selected)
	_detail_name.text = item.get_label(qty)
	var category: String = ItemDefinition.Category.keys()[item.category].capitalize()
	var lines := ["%s  ·  %.2f kg each  ·  %d Marks" % [category, item.weight, item.base_value],
		"Stack %d / %d  ·  %.1f kg total" % [qty, item.max_stack, item.weight * qty]]
	if item.heal_amount > 0.0:
		lines.append("Restores %d health (%.0f s)" % [roundi(item.heal_amount), item.use_time])
	_detail_info.text = "\n".join(lines)
	_detail_desc.text = item.description
