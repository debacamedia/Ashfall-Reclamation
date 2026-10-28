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
## The five weapon slots (Increment 16.7), 1–5.
var weapon_rows: Array[WeaponSlotRow] = []
## The backpack slot under them (Increment 16.8).
var pack_row: PackSlotRow
## The grid scrolls when a big backpack has more slots than fit.
var grid_scroll: ScrollContainer
var _refresh_left := 0.0

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
	# Weapon slots replace the old text list of equipped guns
	var panel := _weapon_label.get_parent() as Control
	panel.visible = false
	var column := panel.get_parent() as VBoxContainer
	column.custom_minimum_size.x = 270
	column.add_theme_constant_override("separation", 6)
	for s in range(1, WeaponSlots.SLOT_COUNT + 1):
		var row := WeaponSlotRow.new(s)
		row.pressed.connect(_on_weapon_row_pressed)
		row.stow_requested.connect(request_stow)
		row.spare_dropped.connect(request_use)
		column.add_child(row)
		weapon_rows.append(row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	column.add_child(gap)
	pack_row = PackSlotRow.new()
	pack_row.take_off_requested.connect(request_take_off_pack)
	pack_row.pack_dropped.connect(request_use)
	column.add_child(pack_row)
	# The backpack grid scrolls (5 rows show) when a big pack has more
	var body := _grid.get_parent()
	var at := _grid.get_index()
	grid_scroll = ScrollContainer.new()
	grid_scroll.name = "GridScroll"
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.custom_minimum_size = Vector2(6 * 72 + 5 * 6 + 14, 5 * 72 + 4 * 6)
	var owner_of_grid := _grid.owner
	body.remove_child(_grid)
	body.add_child(grid_scroll)
	body.move_child(grid_scroll, at)
	grid_scroll.add_child(_grid)
	# Moving it loses its %Name: give it back
	_grid.owner = owner_of_grid
	_grid.unique_name_in_owner = true


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
	var hud := get_parent().get_parent() as HUD if get_parent() != null else null
	if hud != null and hud.crafting_screen != null and hud.crafting_screen.visible:
		return
	if hud != null and hud.map_screen != null and hud.map_screen.visible:
		return
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible and player != null and player.is_dead():
		close()
	# Ammo counts change as you reload while it's open
	_refresh_left -= delta
	if visible and _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh_weapons()


func _refresh_weapons() -> void:
	if player == null:
		return
	if pack_row != null:
		pack_row.refresh()
	var pending := player.weapon_slots.pending_slot if player.weapon_slots != null else 0
	for row in weapon_rows:
		var w := player.weapon_slots.get_weapon(row.slot) if player.weapon_slots != null else null
		var in_hand := w != null and (row.slot == pending if pending != 0 else w == player.weapon)
		row.show_weapon(w, in_hand)


## Clicking a weapon slot takes that gun out (validated by WeaponSlots).
func _on_weapon_row_pressed(slot: int) -> void:
	if player != null and player.weapon_slots != null and not player.is_dead():
		player.weapon_slots.request_slot(slot)
		_refresh_weapons()


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
	if item == null:
		return
	if item.is_pack():
		# A backpack: put it on (Increment 16.8)
		player.request_wear_pack(index)
		selected = -1
		_refresh()
		return
	if item.weapon != null:
		# A spare gun: swap it into its weapon slot (Increment 16.7)
		if player.request_equip_spare(index):
			selected = index if not inv.is_slot_empty(index) else -1
		_refresh()
		return
	player.request_use_item(item)


## Takes the backpack off (back to the satchel).
func request_take_off_pack() -> void:
	if player != null and player.request_take_off_pack():
		_refresh()


## Puts the gun in weapon slot `slot` into the backpack.
func request_stow(slot: int) -> void:
	if player != null and player.request_stow_gun(slot):
		_refresh()


func request_drop(index: int) -> void:
	if player != null and player.request_drop_slot(index) != null and selected == index:
		selected = -1
		_refresh()


## A slot was dropped onto another slot of this screen: move/merge/swap.
## A gun dragged off a weapon slot goes into the backpack.
func handle_slot_drop(data: Dictionary, target: InventorySlot) -> void:
	if data.has("weapon_slot"):
		request_stow(int(data["weapon_slot"]))
	elif data.has("pack_slot"):
		request_take_off_pack()
	elif data.get("inventory") == get_inventory():
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
	if not inv.capacity_changed.is_connected(_rebuild_grid):
		inv.capacity_changed.connect(_rebuild_grid)
	for row in weapon_rows:
		row.inventory = inv
	pack_row.inventory = inv as PlayerInventory
	_rebuild_grid()


## One slot widget per backpack slot (again when you change backpacks).
func _rebuild_grid() -> void:
	var inv := get_inventory()
	if inv == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
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
	if inv != null and inv.capacity_changed.is_connected(_rebuild_grid):
		inv.capacity_changed.disconnect(_rebuild_grid)


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

	_refresh_weapons()

	var item := inv.get_slot_item(selected) if selected >= 0 else null
	_use_button.disabled = item == null or (item.category != ItemDefinition.Category.MEDICAL and item.weapon == null and not item.is_pack())
	_use_button.text = "Equip" if item != null and item.weapon != null else ("Wear" if item != null and item.is_pack() else "Use")
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
	if item.is_pack():
		var now := inv as PlayerInventory
		lines.append("Backpack: %.0f kg, %d slots (you carry %.0f kg, %d slots now)" % [item.pack_carry_weight, item.pack_slots,
			PlayerInventory.weight_for(now.pack if now != null else null), PlayerInventory.slots_for(now.pack if now != null else null)])
		lines.append("Right-click, Wear or drag it to the backpack slot to put it on")
		if item.pack_rattle_radius > 0.0:
			lines.append("Rattles as you move: raiders within %.0f m hear you (crouch to move quietly)" % item.pack_rattle_radius)
	if item.weapon != null:
		var kind: String = WeaponSlotRow.KINDS.get(item.weapon.slot, "")
		var there := player.weapon_slots.get_weapon(item.weapon.slot) if player.weapon_slots != null else null
		lines.append("Spare gun for slot %d (%s), unloaded" % [item.weapon.slot, kind.to_lower()])
		lines.append("Right-click, Equip or drag it to slot %d to swap it in%s" % [item.weapon.slot,
			"" if there == null else " (your %s goes into the backpack)" % there.base_definition.display_name])
	_detail_info.text = "\n".join(lines)
	_detail_desc.text = item.description
