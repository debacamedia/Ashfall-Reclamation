class_name WeaponSlotRow
extends PanelContainer
## One weapon slot in the inventory screen (Increment 16.7): the slot's
## number and kind (1 RIFLE, 2 SIDEARM…), and when you have a gun there its
## picture, name, ammo and attachments. The gun in your hands is outlined.
## Click to take that gun out. Built in code by InventoryScreen.

signal pressed(slot: int)
## Right-click: put this gun into the backpack.
signal stow_requested(slot: int)
## A spare gun from backpack slot `index` was dropped here.
signal spare_dropped(index: int)

## Set by InventoryScreen: the backpack spare guns come from.
var inventory: InventoryComponent

const KINDS := {1: "RIFLE", 2: "SIDEARM", 3: "SHOTGUN", 4: "MARKSMAN", 5: "BLADE"}
const BORDER := Color(0.35, 0.33, 0.3)
const BORDER_EQUIPPED := Color(0.95, 0.75, 0.35)

var slot := 1
var weapon: HitscanWeapon

var _style := StyleBoxFlat.new()
var _icon := TextureRect.new()
var _kind := Label.new()
var _name := Label.new()
var _info := Label.new()


func _init(slot_number := 1) -> void:
	slot = slot_number
	name = "WeaponSlot%d" % slot
	custom_minimum_size = Vector2(270, 74)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.bg_color = Color(0.1, 0.1, 0.09, 0.92)
	_style.set_border_width_all(2)
	_style.border_color = BORDER
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 8
	_style.content_margin_right = 8
	_style.content_margin_top = 5
	_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2(76, 58)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	for pair in [[_kind, "Kind", 13, Color(0.75, 0.7, 0.6)], [_name, "WeaponName", 18, Color(0.95, 0.93, 0.87)], [_info, "Info", 14, Color(0.8, 0.78, 0.72)]]:
		var l: Label = pair[0]
		l.name = pair[1]
		l.add_theme_font_size_override("font_size", pair[2])
		l.add_theme_color_override("font_color", pair[3])
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(l)


## Shows `w` (null = empty) in this slot; `equipped` outlines it.
func show_weapon(w: HitscanWeapon, equipped: bool) -> void:
	weapon = w
	_kind.text = "%d  ·  %s" % [slot, KINDS.get(slot, "")]
	if w == null:
		_icon.texture = null
		_name.text = "Empty"
		_name.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
		_info.text = ""
		_style.border_color = BORDER
		_style.bg_color = Color(0.08, 0.08, 0.07, 0.85)
		tooltip_text = ""
		return
	var item := ItemDatabase.find_weapon_item(w.base_definition.id)
	_icon.texture = item.icon if item != null else null
	_name.text = w.base_definition.display_name
	_name.add_theme_color_override("font_color", Color(0.95, 0.93, 0.87))
	var parts := []
	if not w.definition.melee:
		parts.append("%d / %d" % [w.ammo_in_magazine, w.reserve_ammo])
	for att_slot in w.attachments:
		parts.append((w.attachments[att_slot] as AttachmentDefinition).display_name)
	_info.text = "  ·  ".join(parts)
	_style.border_color = BORDER_EQUIPPED if equipped else BORDER
	_style.bg_color = Color(0.16, 0.14, 0.1, 0.95) if equipped else Color(0.1, 0.1, 0.09, 0.92)
	tooltip_text = ("In your hands" if equipped else "Click to take it out") + ("" if w.definition.melee else "\nRight-click or drag to the backpack to put it away")


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not mb.double_click:
		pressed.emit(slot)
		accept_event()
	elif mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		stow_requested.emit(slot)
		accept_event()


## Drag a gun off its slot onto the backpack grid to put it away.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if weapon == null or weapon.definition.melee:
		return null
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(76, 58)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	return {"weapon_slot": slot}


## A spare gun from the backpack can be dropped on its own kind of slot.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("inventory_slot") and data.get("inventory") == inventory and inventory != null):
		return false
	var item := inventory.get_slot_item(int(data["inventory_slot"]))
	return item != null and item.weapon != null and item.weapon.slot == slot


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	spare_dropped.emit(int(data["inventory_slot"]))
