class_name PackSlotRow
extends PanelContainer
## The backpack slot in the inventory screen (Increment 16.8): the pack you
## wear, what it carries and how many slots it gives. Drop a backpack from
## the grid here (or right-click it there) to put it on; right-click here, or
## drag it onto the grid, to take it off and go back to your satchel.

signal take_off_requested
## A backpack from backpack slot `index` was dropped here.
signal pack_dropped(index: int)

## Set by InventoryScreen.
var inventory: PlayerInventory

var _style := StyleBoxFlat.new()
var _icon := TextureRect.new()
var _kind := Label.new()
var _name := Label.new()
var _info := Label.new()


func _init() -> void:
	name = "PackSlot"
	custom_minimum_size = Vector2(270, 68)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.bg_color = Color(0.1, 0.1, 0.09, 0.92)
	_style.set_border_width_all(2)
	_style.border_color = Color(0.35, 0.33, 0.3)
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 8
	_style.content_margin_right = 8
	_style.content_margin_top = 3
	_style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2(72, 52)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	for pair in [[_kind, "Kind", 13, Color(0.75, 0.7, 0.6)], [_name, "PackName", 18, Color(0.95, 0.93, 0.87)], [_info, "Info", 14, Color(0.8, 0.78, 0.72)]]:
		var l: Label = pair[0]
		l.name = pair[1]
		l.add_theme_font_size_override("font_size", pair[2])
		l.add_theme_color_override("font_color", pair[3])
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(l)
	_kind.text = "BACKPACK"


func refresh() -> void:
	var pack := inventory.pack if inventory != null else null
	var shown := pack if pack != null else ItemDatabase.get_item(&"satchel")
	_icon.texture = shown.icon if shown != null else null
	_name.text = pack.display_name if pack != null else "Satchel"
	var info := "%.0f kg  ·  %d slots" % [PlayerInventory.weight_for(pack), PlayerInventory.slots_for(pack)]
	if pack != null and pack.pack_rattle_radius > 0.0:
		info += "  ·  rattles"
	_info.text = info
	_style.border_color = Color(0.95, 0.75, 0.35) if pack != null else Color(0.35, 0.33, 0.3)
	tooltip_text = ("Right-click or drag to the backpack grid to take it off" if pack != null
		else "Your satchel. Put on a better pack: drop it here, or right-click it in the grid")


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		take_off_requested.emit()
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory == null or inventory.pack == null:
		return null
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	return {"pack_slot": true}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("inventory_slot") and data.get("inventory") == inventory and inventory != null):
		return false
	var item := inventory.get_slot_item(int(data["inventory_slot"]))
	return item != null and item.is_pack()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	pack_dropped.emit(int(data["inventory_slot"]))
