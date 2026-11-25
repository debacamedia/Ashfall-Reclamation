class_name ManualTipCard
extends PanelContainer
## A slip of paper top left (Increment 33): the first time you do something
## the Field Manual covers, it says where to read about it, and that N opens
## it there. Fades after a while.

const SHOW_TIME := FieldManualProgress.TIP_WINDOW

var _title: Label
var _line: Label
var _hint: Label
var _left := 0.0


func _init() -> void:
	name = "ManualTipCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 18
	offset_top = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.89, 0.84, 0.71, 0.95)
	style.border_color = Color(0.62, 0.55, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	add_child(box)
	var type_font: Font = load(FieldManualText.TYPE_FONT)
	_title = Label.new()
	_title.add_theme_font_override("font", type_font)
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(0.17, 0.14, 0.09, 0.7))
	_title.text = "FIELD MANUAL"
	box.add_child(_title)
	_line = Label.new()
	_line.name = "Line"
	_line.add_theme_font_override("font", type_font)
	_line.add_theme_font_size_override("font_size", 19)
	_line.add_theme_color_override("font_color", Color(0.17, 0.14, 0.09))
	box.add_child(_line)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.64, 0.15, 0.11))
	box.add_child(_hint)
	modulate.a = 0.0
	visible = false


## Shows the tip for chapter `id` ("Building, p. 18 · N to read").
func show_tip(id: StringName) -> void:
	var c := FieldManualText.chapter(id)
	if c.is_empty():
		return
	_line.text = "%d · %s, p. %d" % [c["n"], c["title"], c["page"]]
	_hint.text = "Press %s to read it" % FieldManualText.key_name(FieldManualScreen.ACTION)
	_left = SHOW_TIME
	visible = true
	modulate.a = 1.0


func text() -> String:
	return _line.text


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	modulate.a = clampf(_left / 0.6, 0.0, 1.0)
	if _left <= 0.0:
		visible = false
