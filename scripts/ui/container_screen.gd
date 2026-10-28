class_name ContainerScreen
extends Control
## Transfer screen for a SalvageContainer: your gear on the left, the
## container's contents on the right.
##
##   Click            select (details shown underneath)
##   Double-click /   move the whole stack to the other side
##   right-click
##   Drag             move to the other side, or rearrange within one side
##   Take / Store     move the selected stack
##   Take All (R)     take everything that fits
##   E / Tab / Esc    close
##
## Opens when the player's container_opened signal fires and closes on
## container_closed (also sent when the player walks away or dies). Every
## transfer goes through PlayerController.request_take / request_store, which
## validate it (host-side in co-op).
##
## Lives under the HUD: res://scenes/ui/hud.tscn → Root/%ContainerScreen.

const SLOT_SCENE_PATH := "res://scenes/ui/inventory_slot.tscn"
const SIDE_PLAYER := &"player"
const SIDE_CONTAINER := &"container"

## Set by the HUD.
var player: PlayerController:
	set(value):
		if player == value:
			return
		_unbind()
		player = value
		_bind()

var container: SalvageContainer
var selected_side: StringName = &""
var selected := -1

var _player_slots: Array[InventorySlot] = []
var _container_slots: Array[InventorySlot] = []
var _message_left := 0.0

@onready var _title: Label = %Title
@onready var _weight_label: Label = %CarryLabel
@onready var _weight_bar: ProgressBar = %CarryBar
@onready var _player_grid: GridContainer = %PlayerGrid
@onready var _container_grid: GridContainer = %ContainerGrid
@onready var _empty_label: Label = %EmptyLabel
@onready var _detail: Label = %DetailLabel
@onready var _message: Label = %MessageLabel
@onready var _take_button: Button = %TakeButton
@onready var _store_button: Button = %StoreButton
@onready var _take_all_button: Button = %TakeAllButton


func _ready() -> void:
	visible = false
	_take_button.pressed.connect(func() -> void:
		if selected_side == SIDE_CONTAINER:
			request_take(selected))
	_store_button.pressed.connect(func() -> void:
		if selected_side == SIDE_PLAYER:
			request_store(selected))
	_take_all_button.pressed.connect(request_take_all)
	# Your side scrolls when a big backpack has more slots than fit (16.8)
	var side := _player_grid.get_parent()
	var at := _player_grid.get_index()
	var scroll := ScrollContainer.new()
	scroll.name = "PlayerGridScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(6 * 72 + 5 * 6 + 14, 4 * 72 + 3 * 6)
	var owner_of_grid := _player_grid.owner
	side.remove_child(_player_grid)
	side.add_child(scroll)
	side.move_child(scroll, at)
	scroll.add_child(_player_grid)
	# Moving it loses its %Name: give it back
	_player_grid.owner = owner_of_grid
	_player_grid.unique_name_in_owner = true


func is_open() -> bool:
	return visible


# ---------------------------------------------------------------- requests

func request_take(index: int) -> void:
	if player != null and index >= 0:
		player.request_take(index)
		_refresh()


func request_store(index: int) -> void:
	if player != null and index >= 0:
		player.request_store(index)
		_refresh()


func request_take_all() -> void:
	if player != null:
		player.request_take_all()
		_refresh()


## A slot was dropped on another slot of this screen.
func handle_slot_drop(data: Dictionary, target: InventorySlot) -> void:
	if player == null or container == null:
		return
	var source: InventoryComponent = data.get("inventory")
	var from := int(data.get("inventory_slot", -1))
	if source == target.inventory:
		# Rearranging one side
		source.move_slot(from, target.index)
	elif source == player.inventory:
		player.request_store(from)
	elif source == container.inventory:
		player.request_take(from)
	_refresh()


# ---------------------------------------------------------------- open / close

func _input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		player.close_container()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("take_all"):
		request_take_all()
		get_viewport().set_input_as_handled()


func _on_container_opened(c: SalvageContainer) -> void:
	# The HUD only ever binds its own (local) player
	container = c
	selected = -1
	selected_side = &""
	_title.text = c.container_name.to_upper()
	# Big ones (your dropped gear) get wider rows so they fit the window
	_container_grid.columns = 4 if c.inventory.slot_count <= 12 else 6
	_build_slots(_container_grid, _container_slots, c.inventory, SIDE_CONTAINER)
	if not c.inventory.contents_changed.is_connected(_on_contents_changed):
		c.inventory.contents_changed.connect(_on_contents_changed)
	visible = true
	player.player_input.set_ui_open(true)
	_message.text = ""
	_refresh()


func _on_container_closed(c: SalvageContainer) -> void:
	if is_instance_valid(c) and c.inventory.contents_changed.is_connected(_on_contents_changed):
		c.inventory.contents_changed.disconnect(_on_contents_changed)
	container = null
	if visible:
		visible = false
		if player != null:
			player.player_input.set_ui_open(false)


func _on_transfer_refused(reason: String) -> void:
	_message.text = reason
	_message_left = 2.0


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.text = ""


# ---------------------------------------------------------------- display

func _bind() -> void:
	if player == null or not is_node_ready():
		return
	player.container_opened.connect(_on_container_opened)
	player.container_closed.connect(_on_container_closed)
	player.transfer_refused.connect(_on_transfer_refused)
	if player.inventory != null:
		player.inventory.contents_changed.connect(_on_contents_changed)
		player.inventory.capacity_changed.connect(_on_capacity_changed)
		_build_slots(_player_grid, _player_slots, player.inventory, SIDE_PLAYER)


func _on_capacity_changed() -> void:
	if player != null and player.inventory != null:
		_build_slots(_player_grid, _player_slots, player.inventory, SIDE_PLAYER)
		if visible:
			_refresh()


func _unbind() -> void:
	if player == null:
		return
	for pair in [[player.container_opened, _on_container_opened], [player.container_closed, _on_container_closed],
			[player.transfer_refused, _on_transfer_refused]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if player.inventory != null and player.inventory.contents_changed.is_connected(_on_contents_changed):
		player.inventory.contents_changed.disconnect(_on_contents_changed)
	if player.inventory != null and player.inventory.capacity_changed.is_connected(_on_capacity_changed):
		player.inventory.capacity_changed.disconnect(_on_capacity_changed)


func _build_slots(grid: GridContainer, list: Array[InventorySlot], inv: InventoryComponent, side: StringName) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	list.clear()
	var slot_scene := load(SLOT_SCENE_PATH) as PackedScene
	for i in inv.slot_count:
		var slot := slot_scene.instantiate() as InventorySlot
		slot.index = i
		slot.inventory = inv
		slot.screen = self
		slot.clicked.connect(_on_slot_clicked.bind(side))
		slot.activated.connect(_on_slot_activated.bind(side))
		grid.add_child(slot)
		list.append(slot)


func _on_slot_clicked(index: int, button: MouseButton, side: StringName) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_on_slot_activated(index, side)
		return
	selected = index
	selected_side = side
	_refresh()


func _on_slot_activated(index: int, side: StringName) -> void:
	if side == SIDE_CONTAINER:
		request_take(index)
	else:
		request_store(index)


func _on_contents_changed(_changed: PackedInt32Array) -> void:
	if visible:
		_refresh()


func _selected_inventory() -> InventoryComponent:
	if selected_side == SIDE_PLAYER and player != null:
		return player.inventory
	if selected_side == SIDE_CONTAINER and container != null:
		return container.inventory
	return null


func _refresh() -> void:
	if player == null or container == null:
		return
	var sel_inv := _selected_inventory()
	if sel_inv != null and (selected < 0 or sel_inv.is_slot_empty(selected)):
		selected = -1
		selected_side = &""
		sel_inv = null
	for slot in _player_slots:
		slot.show_stack(player.inventory.get_slot_item(slot.index), player.inventory.get_slot_quantity(slot.index),
			selected_side == SIDE_PLAYER and slot.index == selected)
	for slot in _container_slots:
		slot.show_stack(container.inventory.get_slot_item(slot.index), container.inventory.get_slot_quantity(slot.index),
			selected_side == SIDE_CONTAINER and slot.index == selected)
	var weight := player.inventory.get_total_weight()
	_weight_label.text = "%.1f / %.0f kg" % [weight, player.inventory.max_weight]
	_weight_bar.value = 100.0 * weight / maxf(player.inventory.max_weight, 0.001)
	var empty := container.inventory.get_free_slot_count() == container.inventory.slot_count
	_empty_label.visible = empty
	_take_all_button.disabled = empty
	_take_button.disabled = selected_side != SIDE_CONTAINER
	_store_button.disabled = selected_side != SIDE_PLAYER
	if sel_inv == null:
		_detail.text = "Double-click or right-click to move a stack  ·  Drag to move  ·  R: take all"
		return
	var item := sel_inv.get_slot_item(selected)
	var qty := sel_inv.get_slot_quantity(selected)
	_detail.text = "%s  ·  %.2f kg each  ·  %.1f kg total  ·  %d Marks each" % [item.get_label(qty), item.weight, item.weight * qty, item.base_value]
