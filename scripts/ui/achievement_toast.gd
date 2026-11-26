class_name AchievementToast
extends PanelContainer
## Top right (Increment 34): an achievement as you earn it, a gold medal with
## its initials, its name and what it was for. One at a time, each for a few
## seconds; more wait their turn.

const SHOW_TIME := 5.0
const AMBER := Color(0.91, 0.71, 0.29)

var player: PlayerController:
	set(v):
		player = v
		_bind()
## Shown so far (read by tests)
var shown: Array[StringName] = []

var _medal: Label
var _title: Label
var _name: Label
var _text: Label
var _queue: Array[StringName] = []
var _left := 0.0
var _bound: StoryProgress


func _init() -> void:
	name = "AchievementToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	offset_right = -18
	offset_left = -418
	offset_top = 150
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.075, 0.06, 0.94)
	style.border_color = AMBER
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var medal := PanelContainer.new()
	medal.custom_minimum_size = Vector2(58, 58)
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(0.84, 0.64, 0.26)
	disc.border_color = Color(0.96, 0.84, 0.5)
	disc.set_border_width_all(3)
	disc.set_corner_radius_all(29)
	medal.add_theme_stylebox_override("panel", disc)
	_medal = Label.new()
	_medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_medal.add_theme_font_size_override("font_size", 22)
	_medal.add_theme_color_override("font_color", Color(0.23, 0.16, 0.03))
	medal.add_child(_medal)
	row.add_child(medal)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_title = _label("ACHIEVEMENT", 12, AMBER)
	box.add_child(_title)
	_name = _label("", 22, Color(0.95, 0.92, 0.86))
	_name.name = "Name"
	box.add_child(_name)
	_text = _label("", 14, Color(0.65, 0.62, 0.56))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 300
	box.add_child(_text)
	modulate.a = 0.0
	visible = false


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Listens to the player's story (each time it changes).
func _bind() -> void:
	var s := player.story if player != null and is_instance_valid(player) else null
	if s == _bound:
		return
	if _bound != null and is_instance_valid(_bound) and _bound.achievement_earned.is_connected(show_achievement):
		_bound.achievement_earned.disconnect(show_achievement)
	_bound = s
	if s != null:
		s.achievement_earned.connect(show_achievement)


func show_achievement(id: StringName) -> void:
	_queue.append(id)


func _process(delta: float) -> void:
	_bind()
	if _left > 0.0:
		_left -= delta
		modulate.a = clampf(minf(_left, SHOW_TIME - _left) * 3.0, 0.0, 1.0)
		if _left <= 0.0:
			visible = false
		return
	if _queue.is_empty():
		return
	var id: StringName = _queue.pop_front()
	var a := Achievements.find(id)
	if a.is_empty():
		return
	_medal.text = Achievements.initials(a)
	_name.text = a["name"]
	_text.text = a["text"]
	shown.append(id)
	_left = SHOW_TIME
	visible = true
