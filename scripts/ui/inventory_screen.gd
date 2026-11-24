class_name InventoryScreen
extends Control
## The inventory window (Tab / I). Shows the player's slots in a grid, the
## quick bar (keys 1-8, Increment 32) along the bottom, what you wear, carry
## weight and details of the selected item, with Use, Quick bar and Drop
## buttons. Left-click selects, right-click uses (or puts a gun on the bar,
## or takes a thing off it), drag to move or stack, between the backpack and
## the bar, or outside the window to drop it on the ground.
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
## The quick bar slot selected (0-based), -1 = none. Only one of `selected`
## and `selected_bar` is ever set.
var selected_bar := -1
var _slots: Array[InventorySlot] = []
## The quick bar's eight cells (Increment 32), keys 1-8.
var bar_slots: Array[InventorySlot] = []
var bar_button: Button
## The backpack slot under them (Increment 16.8).
var pack_row: PackSlotRow
var armour_row: ArmourSlotsRow
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
	# What you wear in the left column (guns moved to the quick bar, 32)
	var panel := _weapon_label.get_parent() as Control
	panel.visible = false
	var column := panel.get_parent() as VBoxContainer
	column.custom_minimum_size.x = 270
	column.add_theme_constant_override("separation", 6)
	var title := column.get_node_or_null("EquipTitle") as Label
	if title != null:
		title.text = "WEARING"
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	column.add_child(gap)
	pack_row = PackSlotRow.new()
	pack_row.take_off_requested.connect(request_take_off_pack)
	pack_row.pack_dropped.connect(request_use)
	column.add_child(pack_row)
	armour_row = ArmourSlotsRow.new()
	armour_row.take_off_requested.connect(func(slot: int) -> void:
		if player != null:
			player.request_take_off_armour(slot)
		_refresh())
	armour_row.repair_requested.connect(func() -> void:
		if player != null:
			player.request_repair_armour()
		_refresh())
	column.add_child(armour_row)
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
	_build_bar()
	# A button to put the selected thing on (or take it off) the quick bar
	bar_button = Button.new()
	bar_button.name = "BarButton"
	bar_button.custom_minimum_size = Vector2(120, 34)
	bar_button.focus_mode = Control.FOCUS_NONE
	bar_button.text = "To quick bar"
	bar_button.pressed.connect(_on_bar_pressed)
	_use_button.get_parent().add_child(bar_button)
	_use_button.get_parent().move_child(bar_button, _drop_button.get_index())
	_window.grow_vertical = Control.GROW_DIRECTION_BOTH


## The quick bar along the bottom of the window: eight cells, keys 1-8.
func _build_bar() -> void:
	var layout := _window.get_node("Layout") as VBoxContainer
	var box := VBoxContainer.new()
	box.name = "QuickBar"
	box.add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.text = "QUICK BAR   ·   keys 1-8 or the wheel   ·   drag guns, blades, medkits and food here"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	box.add_child(head)
	var row := HBoxContainer.new()
	row.name = "Slots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var slot_scene := load(SLOT_SCENE_PATH) as PackedScene
	for i in QuickBar.SIZE:
		var cell := slot_scene.instantiate() as InventorySlot
		cell.name = "Bar%d" % (i + 1)
		cell.index = i
		cell.screen = self
		row.add_child(cell)
		cell.set_corner(str(i + 1))
		cell.clicked.connect(_on_bar_clicked)
		cell.activated.connect(request_hold)
		bar_slots.append(cell)
	layout.add_child(box)
	layout.move_child(box, layout.get_child_count() - 2)  # above the footer


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
	if hud != null and hud.settlement_screen != null and hud.settlement_screen.visible:
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
	if armour_row != null:
		armour_row.player = player
		armour_row.refresh()
	_refresh_bar()


## The quick bar's cells: what's on each, a gun's rounds, what's in hand.
func _refresh_bar() -> void:
	var bar := player.quick_bar if player != null else null
	if bar == null:
		return
	if selected_bar >= 0 and bar.is_slot_empty(selected_bar):
		selected_bar = -1
	var ws := player.weapon_slots
	var hand := (ws.pending_slot if ws.pending_slot != 0 else ws.current_slot) if ws != null else 0
	for cell in bar_slots:
		cell.inventory = bar
		var item := bar.get_slot_item(cell.index)
		cell.set_in_hand(item != null and cell.index + 1 == hand)
		cell.set_note(_rounds_note(cell.index))
		cell.show_stack(item, bar.get_slot_quantity(cell.index), cell.index == selected_bar)


## "12/15" for a gun on the bar (live), "" for anything else.
func _rounds_note(bar_slot: int) -> String:
	var w := player.weapon_slots.get_weapon(bar_slot + 1) if player.weapon_slots != null else null
	if w == null or w.definition.melee:
		return ""
	return "%d/%d" % [w.ammo_in_magazine, w.definition.magazine_size]


# ---------------------------------------------------------------- requests

## Move/merge/swap between two slots (from drag and drop).
func request_move(from: int, to: int) -> void:
	var inv := get_inventory()
	if inv != null and inv.move_slot(from, to):
		_select(to, -1)


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
		_select(-1, -1)
		_refresh()
		return
	if item.is_armour():
		# Clothing and armour: put it on (Increment 22)
		player.request_wear_armour(index)
		_select(index if not inv.is_slot_empty(index) else -1, -1)
		_refresh()
		return
	if item.category != ItemDefinition.Category.MEDICAL and item.food_value <= 0.0 and QuickBar.holdable(item):
		# A gun or blade: onto the quick bar (Increment 32)
		request_to_bar(index)
		return
	player.request_use_item(item)


## Puts backpack slot `index` on the quick bar (`bar_slot`, or the first
## free one), whatever was there swapping into the backpack.
func request_to_bar(index: int, bar_slot := -1) -> void:
	var target := bar_slot if bar_slot >= 0 else -1
	if player != null and player.request_move_to_bar(index, target):
		var item_at := bar_slot
		if item_at < 0:
			item_at = _last_bar_change
		_select(-1, item_at)
	_refresh()


## Takes quick bar slot `bar_slot` off the bar, into the backpack (onto
## backpack slot `index` if given).
func request_off_bar(bar_slot: int, index := -1) -> void:
	if player != null and player.request_move_to_backpack(bar_slot, index):
		_select(-1, -1)
	_refresh()


## Takes quick bar slot `bar_slot` into your hands.
func request_hold(bar_slot: int) -> void:
	if player != null and player.weapon_slots != null and not player.is_dead():
		player.weapon_slots.request_slot(bar_slot + 1)
	_refresh()


## Takes the backpack off (back to the satchel).
func request_take_off_pack() -> void:
	if player != null and player.request_take_off_pack():
		_refresh()


func request_drop(index: int) -> void:
	if player != null and player.request_drop_slot(index) != null and selected == index:
		_select(-1, -1)
		_refresh()


func request_drop_bar(bar_slot: int) -> void:
	if player != null and player.request_drop_bar_slot(bar_slot) != null:
		_select(-1, -1)
	_refresh()


## A slot was dropped onto another slot of this screen: move/merge/swap
## within the backpack or the bar, or between them.
func handle_slot_drop(data: Dictionary, target: InventorySlot) -> void:
	var bar := player.quick_bar if player != null else null
	if data.has("pack_slot"):
		request_take_off_pack()
		return
	var from := int(data.get("inventory_slot", -1))
	var src: Variant = data.get("inventory")
	if src == get_inventory() and target.inventory == get_inventory():
		request_move(from, target.index)
	elif src == get_inventory() and target.inventory == bar:
		request_to_bar(from, target.index)
	elif src == bar and target.inventory == bar:
		if player.request_move_in_bar(from, target.index):
			_select(-1, target.index)
		_refresh()
	elif src == bar and target.inventory == get_inventory():
		request_off_bar(from, target.index)


func _select(backpack: int, bar_slot: int) -> void:
	selected = backpack
	selected_bar = bar_slot


# ---------------------------------------------------------------- dropping onto the background

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# Anywhere outside the window counts as "drop on the ground"
	return data is Dictionary and data.has("inventory_slot") \
		and (data.get("inventory") == get_inventory() or (player != null and data.get("inventory") == player.quick_bar)) \
		and not _window.get_global_rect().has_point(get_global_transform() * at_position)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player != null and data.get("inventory") == player.quick_bar:
		request_drop_bar(int(data["inventory_slot"]))
	else:
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
	if player.quick_bar != null:
		player.quick_bar.contents_changed.connect(_on_bar_changed)
		for cell in bar_slots:
			cell.inventory = player.quick_bar
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
	if player != null and player.quick_bar != null and player.quick_bar.contents_changed.is_connected(_on_bar_changed):
		player.quick_bar.contents_changed.disconnect(_on_bar_changed)


func _on_contents_changed(_changed: PackedInt32Array) -> void:
	if visible:
		_refresh()


## The last bar slot that changed (where request_to_bar put something).
var _last_bar_change := -1


func _on_bar_changed(changed: PackedInt32Array) -> void:
	for i in changed:
		if player != null and player.quick_bar != null and not player.quick_bar.is_slot_empty(i):
			_last_bar_change = i
	if visible:
		_refresh()


func _on_slot_clicked(index: int, button: MouseButton) -> void:
	_select(index, -1)
	if button == MOUSE_BUTTON_RIGHT:
		request_use(index)
	_refresh()


func _on_bar_clicked(index: int, button: MouseButton) -> void:
	_select(-1, index)
	if button == MOUSE_BUTTON_RIGHT:
		request_off_bar(index)
	_refresh()


func _on_use_pressed() -> void:
	if selected >= 0:
		request_use(selected)
	elif selected_bar >= 0:
		var item := player.quick_bar.get_slot_item(selected_bar)
		if item != null and (item.category == ItemDefinition.Category.MEDICAL or item.food_value > 0.0):
			player.request_use_item(item)
		else:
			request_hold(selected_bar)


func _on_bar_pressed() -> void:
	if selected >= 0:
		request_to_bar(selected)
	elif selected_bar >= 0:
		request_off_bar(selected_bar)


func _on_drop_pressed() -> void:
	if selected >= 0:
		request_drop(selected)
	elif selected_bar >= 0:
		request_drop_bar(selected_bar)


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

	var bar := player.quick_bar
	var on_bar := selected_bar >= 0 and bar != null
	var from: InventoryComponent = bar if on_bar else inv
	var at := selected_bar if on_bar else selected
	var item := from.get_slot_item(at) if at >= 0 else null
	var usable := item != null and (item.category == ItemDefinition.Category.MEDICAL or item.food_value > 0.0)
	if on_bar:
		_use_button.disabled = item == null
		_use_button.text = ("Eat" if item.food_value > 0.0 else "Use") if usable else "Hold"
		bar_button.text = "Off quick bar"
		bar_button.disabled = item == null
	else:
		_use_button.disabled = item == null or (not usable and not QuickBar.holdable(item) and not item.is_pack() and not item.is_armour())
		_use_button.text = "To quick bar" if item != null and not usable and QuickBar.holdable(item) else ("Wear" if item != null and (item.is_pack() or item.is_armour()) else ("Eat" if item != null and item.food_value > 0.0 else "Use"))
		bar_button.text = "To quick bar"
		bar_button.disabled = item == null or not QuickBar.holdable(item)
		bar_button.tooltip_text = "" if item == null else QuickBar.refusal_reason(item)
	_drop_button.disabled = item == null
	if item == null:
		_detail_name.text = "Select an item"
		_detail_info.text = ""
		_detail_desc.text = "Left-click: select   ·   Right-click: use\nDrag: move or stack   ·   Drag outside: drop\nDrag guns, blades, medkits and food onto the quick bar"
		return
	var qty := from.get_slot_quantity(at)
	_detail_name.text = item.get_label(qty)
	var category: String = ItemDefinition.Category.keys()[item.category].capitalize()
	var lines := ["%s  ·  %.2f kg each  ·  %d Marks" % [category, item.weight, item.base_value]]
	if on_bar and item.weapon != null:
		lines.append("On your quick bar, key %d: slung, it weighs nothing" % (at + 1))
	else:
		lines.append("Stack %d / %d  ·  %.1f kg total" % [qty, item.max_stack, item.weight * qty])
		if on_bar:
			lines.append("On your quick bar: key %d" % (at + 1))
	if item.heal_amount > 0.0:
		lines.append("Restores %d health (%.0f s)" % [roundi(item.heal_amount), item.use_time])
	if item.is_armour():
		lines.append("%s armour: takes %d%% off hits  ·  %d wear%s" % [ArmourSet.SLOT_NAMES[item.armour_slot], roundi(item.armour_protection * 100.0),
			roundi(item.armour_durability), "" if item.armour_speed >= 1.0 else "  ·  %d%% slower" % roundi((1.0 - item.armour_speed) * 100.0)])
		lines.append("Right-click or Wear to put it on  ·  repairs: %s at a workbench" % SettlementPlans.cost_text(item.armour_repair))
	if item.food_value > 0.0:
		var h := player.hunger
		lines.append("Food: fills you %d of 100 (%.1f s to eat)  ·  you're at %d%s" % [roundi(item.food_value), item.use_time,
			roundi(h.food), "" if h.stage == PlayerHunger.Stage.FED else " (%s)" % PlayerHunger.stage_name(h.stage).to_lower()])
		lines.append("Right-click or Eat to eat one  ·  J eats the best thing you carry")
	if usable and not on_bar:
		lines.append("Put it on the quick bar to hold it: fire uses it")
	if item.is_pack():
		var now := inv as PlayerInventory
		lines.append("Backpack: %.0f kg, %d slots (you carry %.0f kg, %d slots now)" % [item.pack_carry_weight, item.pack_slots,
			PlayerInventory.weight_for(now.pack if now != null else null), PlayerInventory.slots_for(now.pack if now != null else null)])
		lines.append("Right-click, Wear or drag it to the backpack slot to put it on")
		if item.pack_rattle_radius > 0.0:
			lines.append("Rattles as you move: raiders within %.0f m hear you (crouch to move quietly)" % item.pack_rattle_radius)
	if item.weapon != null:
		lines.append_array(_gun_lines(item, from, at, on_bar))
	_detail_info.text = "\n".join(lines)
	_detail_desc.text = item.description


## A gun's rounds and attachments, and what you can do with it.
func _gun_lines(item: ItemDefinition, from: InventoryComponent, at: int, on_bar: bool) -> Array:
	var out := []
	if item.weapon.melee:
		out.append("A blade: never runs dry")
	else:
		var w := player.weapon_slots.get_weapon(at + 1) if on_bar and player.weapon_slots != null else null
		var state := WeaponSlots.state_of(w) if w != null else from.get_slot_state(at)
		out.append("Loaded: %d / %d rounds" % [int(state.get("magazine", 0)), item.weapon.magazine_size])
		var names := []
		for id in state.get("attachments", []):
			var att := ItemDatabase.get_attachment(StringName(str(id)))
			if att != null:
				names.append(att.display_name)
		out.append("Fitted: " + (", ".join(names) if not names.is_empty() else "nothing"))
	if on_bar:
		out.append("Double-click or Hold to take it out  ·  right-click to take it off the bar")
	else:
		out.append("Right-click or drag it onto the quick bar to carry it in hand")
	return out
