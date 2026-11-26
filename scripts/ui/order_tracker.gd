class_name OrderTracker
extends PanelContainer
## Top left (Increment 34): the order you're on, in Story. The chapter, the
## order, how far along it is ("1 / 3"), and what's next in the chapter.
## Flashes green as an order's done. Hidden in Free Play and once Act 1 is
## done (a line says so for a while).

const AMBER := Color(0.91, 0.71, 0.29)
const TEXT := Color(0.91, 0.89, 0.85)
const DIM := Color(0.61, 0.59, 0.54)
const GREEN := Color(0.56, 0.82, 0.54)

var player: PlayerController:
	set(v):
		player = v
		_bind()

var _chapter: Label
var _order: Label
var _rest: Label
var _flash := 0.0
var _done_line := ""
var _done_left := 0.0
var _bound: StoryProgress


func _init() -> void:
	name = "OrderTracker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 18
	offset_top = 64
	custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.066, 0.058, 0.82)
	style.border_color = AMBER
	style.border_width_left = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_chapter = _label(13, AMBER)
	_chapter.name = "Chapter"
	box.add_child(_chapter)
	_order = _label(19, TEXT)
	_order.name = "Order"
	_order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order.custom_minimum_size.x = 352
	box.add_child(_order)
	_rest = _label(14, DIM)
	_rest.name = "Rest"
	_rest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rest.custom_minimum_size.x = 352
	box.add_child(_rest)
	visible = false


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Listens to the player's story (each time it changes).
func _bind() -> void:
	var s := player.story if player != null and is_instance_valid(player) else null
	if s == _bound:
		return
	if _bound != null and is_instance_valid(_bound):
		_bound.order_done.disconnect(_on_order_done)
		_bound.act_done.disconnect(_on_act_done)
	_bound = s
	if s != null:
		s.order_done.connect(_on_order_done)
		s.act_done.connect(_on_act_done)


func _on_order_done(_id: StringName) -> void:
	_flash = 1.2


func _on_act_done() -> void:
	_done_line = "Act 1 is done. Act 2 comes with a later update."
	_done_left = 20.0


func _process(delta: float) -> void:
	_bind()
	var s := _bound
	_flash = maxf(_flash - delta, 0.0)
	_done_left = maxf(_done_left - delta, 0.0)
	if s == null or not s.is_story() or player.is_dead():
		visible = false
		return
	var c := s.current_chapter()
	if c.is_empty():
		visible = _done_left > 0.0
		_chapter.text = Orders.ACT_TITLE.to_upper()
		_order.text = _done_line
		_rest.text = ""
		return
	visible = true
	var o := s.tracked_order()
	_chapter.text = ("%s · %s" % [c["label"], c["title"]]).to_upper()
	var line: String = o.get("text", "")
	var pr := s.progress_of(o)
	if int(pr[1]) > 0:
		line += "   %d / %d" % [pr[0], pr[1]]
	_order.text = line
	_order.add_theme_color_override("font_color", TEXT.lerp(GREEN, clampf(_flash, 0.0, 1.0)))
	var left := 0
	for x: Dictionary in c["orders"]:
		if not s.is_done(x["id"]):
			left += 1
	var total: int = (c["orders"] as Array).size()
	_rest.text = "%d of %d done in this chapter  ·  N for your orders" % [total - left, total]
