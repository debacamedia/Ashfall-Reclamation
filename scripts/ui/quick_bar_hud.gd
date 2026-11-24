class_name QuickBarHud
extends Control
## The quick bar along the bottom of the screen (Increment 32): eight cells,
## keys 1-8, with each thing's icon, a gun's rounds or a stack's count, and
## the one in your hands raised with a gold edge. When what's in hand
## changes, its name shows above the bar for a moment.
##
## Made by the HUD; reads the player's QuickBar and WeaponSlots each frame.

const CELL := 54.0
const GAP := 4.0
const RAISE := 8.0
const NAME_TIME := 2.2

var player: PlayerController

var cells: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _keys: Array[Label] = []
var _notes: Array[Label] = []
var _name: Label
var _name_left := 0.0
var _shown_slot := -1
var _shown_item: ItemDefinition = null
var _style: StyleBoxFlat
var _style_hand: StyleBoxFlat
var _style_empty: StyleBoxFlat


func _init() -> void:
	name = "QuickBarHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := QuickBar.SIZE * CELL + (QuickBar.SIZE - 1) * GAP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -width / 2.0
	offset_right = width / 2.0
	offset_top = -14.0 - CELL - RAISE - 26.0
	offset_bottom = -14.0
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.08, 0.08, 0.07, 0.72)
	_style.border_color = Color(0.4, 0.38, 0.32, 0.85)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(4)
	_style_empty = _style.duplicate()
	_style_empty.bg_color = Color(0.06, 0.06, 0.05, 0.4)
	_style_empty.border_color = Color(0.35, 0.33, 0.28, 0.4)
	_style_hand = _style.duplicate()
	_style_hand.bg_color = Color(0.2, 0.16, 0.08, 0.85)
	_style_hand.border_color = Color(0.98, 0.78, 0.32)
	_style_hand.set_border_width_all(2)
	_name = Label.new()
	_name.name = "HeldName"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.position = Vector2(-100, 0)
	_name.size = Vector2(width + 200, 24)
	_name.add_theme_font_size_override("font_size", 17)
	_name.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name.add_theme_constant_override("outline_size", 4)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.modulate.a = 0.0
	add_child(_name)
	for i in QuickBar.SIZE:
		var p := Panel.new()
		p.name = "Cell%d" % (i + 1)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size = Vector2(CELL, CELL)
		p.position = Vector2(i * (CELL + GAP), 26.0 + RAISE)
		p.add_theme_stylebox_override("panel", _style_empty)
		add_child(p)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(5, 5)
		icon.size = Vector2(CELL - 10, CELL - 10)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		var key := _small(str(i + 1), Vector2(4, 1), HORIZONTAL_ALIGNMENT_LEFT, Color(0.9, 0.85, 0.7))
		p.add_child(key)
		var note := _small("", Vector2(0, CELL - 17), HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE)
		note.size.x = CELL - 4
		p.add_child(note)
		cells.append(p)
		_icons.append(icon)
		_keys.append(key)
		_notes.append(note)


func _small(text: String, at: Vector2, align: HorizontalAlignment, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.size = Vector2(CELL - 6, 16)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The slot (1-8) shown as in your hands (the one being drawn, mid-switch).
func hand_slot() -> int:
	var ws := player.weapon_slots if player != null else null
	if ws == null:
		return 0
	return ws.pending_slot if ws.pending_slot != 0 else ws.current_slot


func _process(delta: float) -> void:
	var bar := player.quick_bar if player != null else null
	visible = bar != null and not player.is_dead()
	if not visible:
		return
	var hand := hand_slot()
	for i in QuickBar.SIZE:
		var item := bar.get_slot_item(i)
		var held := item != null and i + 1 == hand
		var p := cells[i]
		p.add_theme_stylebox_override("panel", _style_hand if held else (_style if item != null else _style_empty))
		p.position.y = 26.0 + (0.0 if held else RAISE)
		_icons[i].texture = item.icon if item != null else null
		_icons[i].modulate = Color.WHITE if item != null else Color(1, 1, 1, 0)
		_keys[i].modulate.a = 1.0 if item != null else 0.45
		_notes[i].text = _note(i, item, bar.get_slot_quantity(i))
		_notes[i].add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if _notes[i].text.begins_with("0/") else Color.WHITE)
	# The name of what's in hand, for a moment after it changes
	var in_hand := bar.get_slot_item(hand - 1) if hand > 0 else null
	if hand != _shown_slot or in_hand != _shown_item:
		_shown_slot = hand
		_shown_item = in_hand
		_name.text = in_hand.display_name if in_hand != null else ""
		if in_hand != null and (in_hand.category == ItemDefinition.Category.MEDICAL or in_hand.food_value > 0.0):
			_name.text += "   ·   fire to " + ("eat" if in_hand.food_value > 0.0 else "use")
		_name_left = NAME_TIME if in_hand != null else 0.0
	_name_left = maxf(_name_left - delta, 0.0)
	_name.modulate.a = clampf(_name_left / 0.4, 0.0, 1.0)


## A gun's rounds ("12/30"), a stack's count, or "".
func _note(i: int, item: ItemDefinition, qty: int) -> String:
	if item == null:
		return ""
	if item.weapon != null:
		var w := player.weapon_slots.get_weapon(i + 1) if player.weapon_slots != null else null
		if w == null or w.definition.melee:
			return ""
		return "%d/%d" % [w.ammo_in_magazine, w.definition.magazine_size]
	return "×%d" % qty if qty > 1 else ""
