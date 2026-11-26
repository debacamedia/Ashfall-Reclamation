class_name FieldManualScreen
extends Control
## The Field Manual (Increment 33): N, or hold it on the quick bar and fire.
## A booklet open on two pages: the contents and Sgt. Vance's note on the
## left, a chapter on the right. Chapters you haven't reached yet are greyed
## in the contents. Click a chapter, or turn pages with the arrow keys (or A
## and D); N or Esc closes it.
##
## Built in code by the HUD. Orders, achievements and a journal join it as
## tabs later.

const ACTION := "field_manual"
const PAPER := Color(0.89, 0.84, 0.71)
const PAPER_EDGE := Color(0.62, 0.55, 0.4)
const INK := Color(0.17, 0.14, 0.09)
const FADED := Color(0.17, 0.14, 0.09, 0.38)
const PEN := Color(0.64, 0.15, 0.11)
const LEATHER := Color(0.16, 0.13, 0.09)
const PAGE_SIZE := Vector2(530, 640)
## The two pages that aren't chapters (34)
const ORDERS := &"orders"
const ACHIEVEMENTS := &"achievements"

var player: PlayerController
## The chapter on the right-hand page.
var chapter_id: StringName = &"staying_alive"

var _contents: VBoxContainer
var _chapter_buttons := {}
var _sub: Label
var _title: Label
var _body: RichTextLabel
var _prev: Button
var _next: Button
var _hand_font: Font
var _type_font: Font
## Your name, written on the cover page (Increment 33.1).
var name_field: LineEdit
const BLUE_INK := Color(0.13, 0.22, 0.48)


func _init() -> void:
	name = "FieldManualScreen"
	PlayerInput.ensure_bar_keys()  # N
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hand_font = load(FieldManualText.HAND_FONT)
	_type_font = load(FieldManualText.TYPE_FONT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	center.add_child(column)
	# The tab along the top (more join it later)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	var tab := Label.new()
	tab.name = "Tab"
	tab.text = "  HOW TO PLAY  "
	tab.add_theme_font_override("font", _type_font)
	tab.add_theme_font_size_override("font_size", 17)
	tab.add_theme_color_override("font_color", INK)
	var tab_style := _paper_style(PAPER.darkened(0.06))
	tab_style.corner_radius_bottom_left = 0
	tab_style.corner_radius_bottom_right = 0
	tab_style.set_content_margin_all(6)
	tab.add_theme_stylebox_override("normal", tab_style)
	var tab_gap := Control.new()
	tab_gap.custom_minimum_size.x = 28
	tabs.add_child(tab_gap)
	tabs.add_child(tab)
	column.add_child(tabs)
	var book := PanelContainer.new()
	book.name = "Book"
	var cover := StyleBoxFlat.new()
	cover.bg_color = LEATHER
	cover.set_corner_radius_all(6)
	cover.set_content_margin_all(12)
	cover.shadow_color = Color(0, 0, 0, 0.5)
	cover.shadow_size = 14
	book.add_theme_stylebox_override("panel", cover)
	column.add_child(book)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	book.add_child(pages)
	pages.add_child(_left_page())
	pages.add_child(_right_page())


func _paper_style(c := PAPER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = PAPER_EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 34
	s.content_margin_right = 34
	s.content_margin_top = 26
	s.content_margin_bottom = 20
	return s


func _label(text: String, size: int, colour: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


func _left_page() -> Control:
	var page := PanelContainer.new()
	page.name = "LeftPage"
	page.custom_minimum_size = PAGE_SIZE
	page.add_theme_stylebox_override("panel", _paper_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	page.add_child(box)
	box.add_child(_label(FieldManualText.COVER_SUB, 14, FADED.lerp(INK, 0.4), _type_font))
	var title := _label(FieldManualText.COVER_TITLE, 40, INK, _type_font)
	title.name = "CoverTitle"
	box.add_child(title)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	# "Issued to": where you write your name
	var issued := HBoxContainer.new()
	issued.name = "IssuedTo"
	issued.add_theme_constant_override("separation", 10)
	var lab := _label("Issued to:", 16, FADED.lerp(INK, 0.5), _type_font)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	issued.add_child(lab)
	name_field = LineEdit.new()
	name_field.name = "NameField"
	name_field.placeholder_text = "write your name here"
	name_field.max_length = PlayerController.NAME_MAX
	name_field.flat = true
	name_field.custom_minimum_size = Vector2(300, 40)
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.add_theme_font_override("font", _hand_font)
	name_field.add_theme_font_size_override("font_size", 30)
	name_field.add_theme_color_override("font_color", BLUE_INK)
	name_field.add_theme_color_override("font_placeholder_color", Color(BLUE_INK, 0.35))
	name_field.add_theme_color_override("caret_color", BLUE_INK)
	name_field.add_theme_color_override("selection_color", Color(BLUE_INK, 0.2))
	var under := StyleBoxFlat.new()
	under.bg_color = Color(0, 0, 0, 0)
	under.border_color = FADED
	under.border_width_bottom = 1
	under.content_margin_left = 2
	name_field.add_theme_stylebox_override("normal", under)
	var under_focus := under.duplicate() as StyleBoxFlat
	under_focus.border_color = BLUE_INK
	under_focus.border_width_bottom = 2
	name_field.add_theme_stylebox_override("focus", under_focus)
	name_field.text_submitted.connect(func(_t: String) -> void: _commit_name(); name_field.release_focus())
	name_field.focus_exited.connect(_commit_name)
	issued.add_child(name_field)
	box.add_child(issued)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	_contents = VBoxContainer.new()
	_contents.name = "Contents"
	_contents.add_theme_constant_override("separation", 2)
	box.add_child(_contents)
	for c: Dictionary in FieldManualText.CHAPTERS:
		var b := _contents_button("Chapter%d" % c["n"])
		var id: StringName = c["id"]
		b.pressed.connect(func() -> void: show_chapter(id))
		_contents.add_child(b)
		_chapter_buttons[id] = b
	# Your orders and achievements (34)
	var rule2 := ColorRect.new()
	rule2.color = FADED
	rule2.custom_minimum_size = Vector2(0, 1)
	_contents.add_child(rule2)
	for extra: Array in [[ORDERS, "Orders"], [ACHIEVEMENTS, "Achievements"]]:
		var b := _contents_button(String(extra[0]).capitalize().replace(" ", ""))
		b.name = String(extra[1])
		var page_id: StringName = extra[0]
		b.pressed.connect(func() -> void: show_chapter(page_id))
		_contents.add_child(b)
		_chapter_buttons[page_id] = b
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	var note := _label(FieldManualText.COVER_NOTE, 27, PEN, _hand_font)
	note.name = "VanceNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PAGE_SIZE.x - 90
	note.rotation_degrees = -2.0
	box.add_child(note)
	return page


## A line in the contents.
func _contents_button(node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 34
	b.add_theme_font_override("font", _type_font)
	b.add_theme_font_size_override("font_size", 19)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_disabled_color", FADED)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.17, 0.14, 0.09, 0.08)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var num := _label("", 19, INK, _type_font)
	num.name = "Page"
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	num.offset_right = -6
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(num)
	return b


func _right_page() -> Control:
	var page := PanelContainer.new()
	page.name = "RightPage"
	page.custom_minimum_size = PAGE_SIZE
	page.add_theme_stylebox_override("panel", _paper_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	page.add_child(box)
	_sub = _label("", 14, FADED.lerp(INK, 0.4), _type_font)
	_sub.name = "Sub"
	box.add_child(_sub)
	_title = _label("", 30, INK, _type_font)
	_title.name = "ChapterTitle"
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.name = "Body"
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_color_override("default_color", INK)
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.add_theme_constant_override("line_separation", 3)
	_body.add_theme_constant_override("paragraph_separation", 12)
	# Keycaps' backgrounds stop at their own text (they covered commas)
	_body.add_theme_constant_override("text_highlight_h_padding", 0)
	_body.add_theme_constant_override("text_highlight_v_padding", 1)
	_body.meta_underlined = true
	_body.meta_clicked.connect(_on_link)
	box.add_child(_body)
	var foot := HBoxContainer.new()
	_prev = _turn_button("‹  Back", -1)
	foot.add_child(_prev)
	var hint := _label("N or Esc to close  ·  ← → to turn", 13, FADED.lerp(INK, 0.3))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	_next = _turn_button("Next  ›", 1)
	foot.add_child(_next)
	box.add_child(foot)
	return page


func _turn_button(text: String, step: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _type_font)
	b.add_theme_font_size_override("font_size", 16)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	b.pressed.connect(func() -> void: turn(step))
	return b


func _progress() -> FieldManualProgress:
	return player.field_manual if player != null else null


## Writes what's in the name field in as your name (cleaned up).
func _commit_name() -> void:
	if player == null or name_field == null:
		return
	var kept := player.set_player_name(name_field.text)
	if name_field.text != kept:
		name_field.text = kept


func is_open() -> bool:
	return visible


func open(at: StringName = &"") -> void:
	if player == null or player.is_dead() or _progress() == null:
		return
	var m := _progress()
	if at == &"":
		at = m.page_to_open()
	m.used_tip()
	name_field.text = player.player_name
	visible = true
	player.player_input.set_ui_open(true)
	_refresh_contents()
	if at == ORDERS or at == ACHIEVEMENTS:
		show_chapter(at)
	else:
		show_chapter(at if m.is_open(at) else (m.page if m.is_open(m.page) or m.page in [ORDERS, ACHIEVEMENTS] else &"staying_alive"))


func close() -> void:
	if not visible:
		return
	if name_field.has_focus():
		name_field.release_focus()  # (keeps what's written)
	visible = false
	if player != null:
		player.player_input.set_ui_open(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## The chapters you can read, in order.
func readable() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in FieldManualText.ids():
		if _progress() != null and _progress().is_open(id):
			out.append(id)
	return out


func show_chapter(id: StringName) -> void:
	if id == ORDERS or id == ACHIEVEMENTS:
		_show_extra(id)
		return
	var c := FieldManualText.chapter(id)
	if c.is_empty() or _progress() == null or not _progress().is_open(id):
		return
	chapter_id = id
	_progress().page = id
	_sub.text = "Chapter %d  ·  p. %d" % [c["n"], c["page"]]
	_title.text = c["title"]
	_body.text = FieldManualText.render(c["text"])
	_body.scroll_to_line(0)
	var list := readable()
	var at := list.find(id)
	_prev.disabled = at <= 0
	_next.disabled = at < 0 or at >= list.size() - 1
	_refresh_contents()


## Your orders or your achievements (34), on the right-hand page.
func _show_extra(id: StringName) -> void:
	var st := player.story if player != null else null
	if st == null:
		return
	chapter_id = id
	_progress().page = id
	_prev.disabled = true
	_next.disabled = true
	if id == ORDERS:
		_sub.text = "Orders  ·  %s" % Orders.ACT_TITLE
		_body.text = orders_text(st)
		var c := st.current_chapter()
		_title.text = "Free Play: no orders" if not st.is_story() else ("Act 1 done" if c.is_empty() else "%s · %s" % [c["label"], c["title"]])
	else:
		_sub.text = "Achievements  ·  %d of %d" % [st.earned.size(), Achievements.count()]
		_title.text = "Achievements"
		_body.text = achievements_text(st)
	_body.scroll_to_line(0)
	_refresh_contents()


## The orders page: the chapters done, this chapter's orders (click one to
## track it), and the ones to come.
static func orders_text(st: StoryProgress) -> String:
	if not st.is_story():
		return "This game is Free Play: no orders, every chapter of this manual open. Start a new game in Story to follow Sgt. Vance's last order."
	var out := []
	var current := st.current_chapter()
	var tracked := st.tracked_order()
	var reached := true
	for c: Dictionary in Orders.CHAPTERS:
		if c == current:
			# (the page's heading names this chapter)
			for o: Dictionary in c["orders"]:
				var line: String = o["text"]
				var pr := st.progress_of(o)
				if int(pr[1]) > 0:
					line += "  (%d / %d)" % [pr[0], pr[1]]
				if st.is_done(o["id"]):
					out.append("[color=#6a6150]✓  [s]%s[/s][/color]" % line)
				elif o == tracked:
					out.append("☐  [b]%s[/b]  [color=#8a6d1f]◂ on your compass[/color]" % line)
				else:
					out.append("☐  [url=track:%s]%s[/url]" % [o["id"], line])
			out.append("[font=%s][font_size=24][color=#a3261c]%s[/color][/font_size][/font]" % [FieldManualText.HAND_FONT, c["note"]])
			reached = false
		elif reached and not current.is_empty() or current.is_empty():
			out.append("[color=#6a6150]✓  %s · %s[/color]" % [c["label"], c["title"]])
		else:
			out.append("[color=#a59a83]%s · %s[/color]" % [c["label"], c["title"]])
	if current.is_empty():
		out.append("")
		out.append("Act 1 is done. Act 2 comes with a later update.")
	else:
		out.append("")
		out.append("[color=#6a6150]Click an order to track it on your compass.[/color]")
	return "\n".join(out)


## The achievements page: the ones earned, then the rest (the hidden ones
## as "Hidden").
static func achievements_text(st: StoryProgress) -> String:
	var got := []
	var rest := []
	for a: Dictionary in Achievements.LIST:
		if st.has_earned(a["id"]):
			got.append("[color=#8a6d1f]●[/color]  [b]%s[/b]  ·  %s" % [a["name"], a["text"]])
		elif not st.can_earn(a["id"]):
			rest.append("[color=#a59a83]○  %s  ·  in Story only[/color]" % a["name"])
		elif a["hidden"]:
			rest.append("[color=#a59a83]○  Hidden  ·  keep playing[/color]")
		else:
			rest.append("[color=#6a6150]○  %s  ·  %s[/color]" % [a["name"], a["text"]])
	var out := []
	if got.is_empty():
		out.append("[color=#6a6150]None yet.[/color]")
	out.append_array(got)
	out.append("")
	out.append_array(rest)
	return "\n".join(out)


func _on_link(meta: Variant) -> void:
	var m := str(meta)
	if m.begins_with("track:") and player != null and player.story != null:
		player.story.track(StringName(m.trim_prefix("track:")))
		_show_extra(ORDERS)


## Turns a chapter on (+1) or back (-1), skipping those not reached yet.
func turn(step: int) -> void:
	var list := readable()
	var at := list.find(chapter_id)
	if at >= 0 and at + step >= 0 and at + step < list.size():
		show_chapter(list[at + step])


func _refresh_contents() -> void:
	var st := player.story if player != null else null
	for extra: Array in [[ORDERS, "Orders"], [ACHIEVEMENTS, "Achievements"]]:
		var b := _chapter_buttons.get(extra[0]) as Button
		if b == null:
			continue
		b.text = "%s%s" % ["▸ " if chapter_id == extra[0] else "   ", extra[1]]
		var num := b.get_node("Page") as Label
		num.text = ""
		if st != null and extra[0] == ORDERS and st.is_story():
			var done := 0
			for o in Orders.all_ids():
				if st.is_done(o):
					done += 1
			num.text = "%d / %d" % [done, Orders.count()]
		elif st != null and extra[0] == ACHIEVEMENTS:
			num.text = "%d / %d" % [st.earned.size(), Achievements.count()]
	for c: Dictionary in FieldManualText.CHAPTERS:
		var b := _chapter_buttons[c["id"]] as Button
		var ok := _progress() != null and _progress().is_open(c["id"])
		b.disabled = not ok
		var here := "▸ " if c["id"] == chapter_id and ok else "   "
		b.text = "%s%d · %s" % [here, c["n"], c["title"]]
		var num := b.get_node("Page") as Label
		num.text = str(c["page"]) if ok else "— —"
		num.add_theme_color_override("font_color", INK if ok else FADED)
		b.tooltip_text = "" if ok else "You'll get to this one"


func _input(event: InputEvent) -> void:
	if player == null or not player.controlled_locally:
		return
	if not visible:
		if event.is_action_pressed(ACTION) and not event.is_echo() and not player.player_input.ui_open \
				and player.current_container == null and not player.is_dead() and not player.is_driving():
			open()
			get_viewport().set_input_as_handled()
		return
	if name_field.has_focus():
		# Writing your name: every key's a letter, but Esc puts the pen down
		if event.is_action_pressed("pause") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and not name_field.get_global_rect().has_point((event as InputEventMouseButton).position)):
			_commit_name()
			name_field.release_focus()
			if event.is_action_pressed("pause"):
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION) or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") or event.is_action_pressed("map") or event.is_action_pressed("crafting"):
		close()  # and let that window open
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		turn(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		turn(1)
		get_viewport().set_input_as_handled()
