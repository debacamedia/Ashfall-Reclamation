class_name InventorySlot
extends PanelContainer
## One cell of an inventory grid: icon, quantity, selection border.
## Used by the InventoryScreen and both sides of the ContainerScreen.
## Drag and drop: the owning screen decides what a drop means (move within
## one inventory, transfer between two, drop on the ground) in
## handle_slot_drop(data, target_slot).
##
## Scene: res://scenes/ui/inventory_slot.tscn (created by the screens).

signal clicked(index: int, button: MouseButton)
## Double-click (left button).
signal activated(index: int)

var index := -1
## The inventory this cell shows.
var inventory: InventoryComponent
## The screen that owns this cell; must have handle_slot_drop(data, slot).
var screen: Control

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat

@onready var _icon: TextureRect = %Icon
@onready var _qty: Label = %Quantity
@onready var _short_name: Label = %ShortName


func _ready() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.1, 0.1, 0.09, 0.85)
	_style_normal.border_color = Color(0.35, 0.33, 0.28, 0.9)
	_style_normal.set_border_width_all(1)
	_style_normal.set_corner_radius_all(3)
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(0.95, 0.75, 0.3)
	_style_selected.set_border_width_all(2)
	_style_selected.bg_color = Color(0.2, 0.17, 0.1, 0.9)
	add_theme_stylebox_override("panel", _style_normal)


func show_stack(item: ItemDefinition, quantity: int, selected: bool) -> void:
	add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)
	if item == null:
		_icon.texture = null
		_qty.text = ""
		_short_name.text = ""
		tooltip_text = ""
		return
	_icon.texture = item.icon
	_short_name.text = "" if item.icon != null else item.display_name
	_qty.text = str(quantity) if quantity > 1 else ""
	tooltip_text = item.get_label(quantity)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(index)
		else:
			clicked.emit(index, mb.button_index)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory == null or inventory.is_slot_empty(index):
		return null
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(56, 56)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	return {"inventory_slot": index, "inventory": inventory}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# A backpack slot, or a gun dragged off a weapon slot (Increment 16.7)
	return data is Dictionary and (data.has("inventory_slot") or data.has("weapon_slot") or data.has("pack_slot"))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if screen != null and screen.has_method("handle_slot_drop"):
		screen.call("handle_slot_drop", data, self)
