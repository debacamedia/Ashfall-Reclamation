class_name ArmourSlotsRow
extends PanelContainer
## Your clothing and armour in the inventory screen (Increment 22): head,
## body and legs, each with what it's worth and how worn it is. Right-click a
## piece in the grid (or Wear) to put it on; right-click it here to take it
## off. Near a workbench, Repair mends everything you wear.

signal take_off_requested(slot: int)
signal repair_requested

## Set by InventoryScreen.
var player: PlayerController

var _cells := {}
var _summary := Label.new()
var _title := Label.new()
var _repair := Button.new()


func _init() -> void:
	name = "ArmourSlots"
	custom_minimum_size = Vector2(270, 62)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.09, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.33, 0.3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for slot in ArmourSet.SLOTS:
		var cell := Panel.new()
		cell.name = "Cell" + ArmourSet.SLOT_NAMES[slot]
		cell.custom_minimum_size = Vector2(50, 50)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.06, 0.06, 0.055)
		cs.set_border_width_all(1)
		cs.border_color = Color(0.3, 0.28, 0.25)
		cs.set_corner_radius_all(3)
		cell.add_theme_stylebox_override("panel", cs)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 8
		icon.offset_right = -3
		icon.offset_bottom = -6
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var tag := Label.new()
		tag.name = "Tag"
		tag.text = ArmourSet.SLOT_NAMES[slot].to_upper()
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
		tag.position = Vector2(4, 0)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(tag)
		var bar := ColorRect.new()
		bar.name = "Wear"
		bar.position = Vector2(4, 44)
		bar.size = Vector2(42, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bar)
		cell.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				take_off_requested.emit(slot)
				cell.accept_event())
		row.add_child(cell)
		_cells[slot] = cell
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	var title := _title
	title.name = "Title"
	title.text = "ARMOUR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	side.add_child(title)
	_summary.name = "Summary"
	_summary.add_theme_font_size_override("font_size", 11)
	_summary.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_summary.clip_text = true
	side.add_child(_summary)
	_repair.name = "Repair"
	_repair.text = "Repair"
	_repair.focus_mode = Control.FOCUS_NONE
	_repair.add_theme_font_size_override("font_size", 11)
	_repair.clip_text = true
	_repair.pressed.connect(func() -> void: repair_requested.emit())
	side.add_child(_repair)


func refresh() -> void:
	if player == null:
		return
	var a := player.armour
	for slot in ArmourSet.SLOTS:
		var cell: Panel = _cells[slot]
		var it := a.worn(slot)
		(cell.get_node("Icon") as TextureRect).texture = it.icon if it != null else null
		var bar := cell.get_node("Wear") as ColorRect
		bar.visible = it != null
		var c := a.condition(slot)
		bar.size.x = 42.0 * c
		bar.color = Color(0.9, 0.25, 0.2) if c <= 0.0 else (Color(0.95, 0.7, 0.25) if c < 0.35 else Color(0.6, 0.9, 0.55))
		if it == null:
			cell.tooltip_text = "%s: nothing. Right-click a piece in your backpack (or Wear) to put it on" % ArmourSet.SLOT_NAMES[slot]
		else:
			cell.tooltip_text = "%s: takes %d%% off hits, %d%% wear left%s\nRight-click to take it off" % [it.display_name,
				roundi(it.armour_protection * 100.0), roundi(c * 100.0), " (worn out: repair it)" if c <= 0.0 else ""]
	var p := a.protection()
	var slow := 1.0 - a.speed()
	_title.text = "ARMOUR" if a.is_empty() else "ARMOUR  %d%%" % roundi(p * 100.0)
	if a.is_empty():
		_summary.text = "Nothing worn"
	elif slow > 0.005:
		_summary.text = "%d%% slower" % roundi(slow * 100.0)
	else:
		_summary.text = "off every hit"
	tooltip_text = "Takes %d%% off hits%s" % [roundi(p * 100.0), "" if slow <= 0.005 else "; plate slows you %d%%" % roundi(slow * 100.0)]
	var cost := player.armour_repair_cost()
	_repair.visible = not cost.is_empty()
	var why := player.repair_armour_refusal_reason()
	_repair.disabled = why != ""
	_repair.text = "Repair"
	_repair.tooltip_text = ("Mend everything you wear: " + SettlementPlans.cost_text(cost)) + ("\n" + why if why != "" else "")
