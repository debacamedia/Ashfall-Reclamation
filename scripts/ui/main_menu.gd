class_name MainMenu
extends Control
## The main menu (Increment 33.1): what the game opens on. Continue your last
## game, start a new one, load any of your games (rename or delete them),
## see the achievements, change the settings, read about the game and its
## credits, or quit.
##
## Each game is its own folder of saves (SaveManager's games). Built in code;
## the scene is just this script on a Control.

## The rebuilt Outpost 17, where you start (33.3; 33.1 had Halden's Crossing)
const ART := "res://assets/ui/menu_background_outpost.jpg"
const AMBER := Color(0.95, 0.72, 0.38)
const TEXT := Color(0.88, 0.86, 0.8)
const DIM := Color(0.6, 0.58, 0.53)
const RED := Color(0.9, 0.42, 0.33)
const PANEL := Color(0.07, 0.068, 0.06, 0.93)
## Shown at the bottom left.
const VERSION := "Increment 34"

var saves: Node
var buttons := {}
var page: Control
var page_name := ""
var _continue_sub: Label
var _pages_host: Control
var _type_font: Font


func _ready() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	saves = get_node_or_null("/root/SaveManager")
	get_tree().paused = false
	GameSettings.apply_all(get_window())
	UiScale.apply(get_window(), UiScale.saved())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if saves != null:
		saves.set("autosave_enabled", false)
		saves.call("migrate_legacy")
	_type_font = load(FieldManualText.TYPE_FONT)
	_build()
	_refresh_continue()


# ---------------------------------------------------------------- building

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.048, 0.042)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(ART):
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = load(ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(art)
	# Darker on the left, where the menu is
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.03, 0.025, 0.94))
	grad.set_color(1, Color(0.03, 0.03, 0.025, 0.25))
	grad.add_point(0.42, Color(0.03, 0.03, 0.025, 0.72))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# The menu
	var col := VBoxContainer.new()
	col.name = "Menu"
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 72
	col.offset_right = 500
	col.offset_top = 64
	col.offset_bottom = -60
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := _label("ASHFALL", 76, AMBER)
	title.add_theme_font_override("font", _type_font)
	title.name = "Title"
	col.add_child(title)
	var sub := _label("R E C L A M A T I O N", 26, TEXT)
	sub.add_theme_font_override("font", _type_font)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	col.add_child(gap)
	_menu_button(col, "Continue", "Continue", _continue)
	_continue_sub = _label("", 16, DIM)
	_continue_sub.name = "ContinueInfo"
	_continue_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_continue_sub.custom_minimum_size.x = 380
	col.add_child(_continue_sub)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 8
	col.add_child(gap2)
	_menu_button(col, "NewGame", "New game", func() -> void: show_page("new"))
	_menu_button(col, "LoadGame", "Load game", func() -> void: show_page("load"))
	_menu_button(col, "Achievements", "Achievements", func() -> void: show_page("achievements"))
	_menu_button(col, "SettingsButton", "Settings", func() -> void: show_page("settings"))
	_menu_button(col, "About", "About", func() -> void: show_page("about"))
	_menu_button(col, "Quit", "Quit", func() -> void: get_tree().quit())
	var ver := _label(VERSION + "  ·  made with Godot", 13, DIM)
	ver.name = "Version"
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.offset_left = -360
	ver.offset_right = -24
	ver.offset_top = -34
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	# The page on the right
	_pages_host = PanelContainer.new()
	_pages_host.name = "Page"
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color(0.4, 0.37, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(28)
	_pages_host.add_theme_stylebox_override("panel", style)
	_pages_host.anchor_left = 0.42
	_pages_host.anchor_right = 0.97
	_pages_host.anchor_top = 0.07
	_pages_host.anchor_bottom = 0.92
	_pages_host.visible = false
	add_child(_pages_host)


func _menu_button(parent: Control, id: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 46
	b.add_theme_font_override("font", _type_font)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_focus_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))
	b.pressed.connect(action)
	parent.add_child(b)
	buttons[id] = b
	return b


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _button(text: String, id := "") -> Button:
	var b := Button.new()
	b.text = text
	if id != "":
		b.name = id
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(92, 38)
	b.add_theme_font_size_override("font_size", 17)
	return b


func _line(placeholder: String, id: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.name = id
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(380, 42)
	e.add_theme_font_size_override("font_size", 19)
	return e


# ---------------------------------------------------------------- continue

func _refresh_continue() -> void:
	var id: String = saves.call("latest_game") if saves != null else ""
	var b := buttons["Continue"] as Button
	b.disabled = id == ""
	if id == "":
		_continue_sub.text = "No game yet: start a new one"
		return
	var g: Dictionary = saves.call("game_info", id)
	_continue_sub.text = "%s  ·  %s  ·  %s" % [g["name"], g["place"], play_time(float(g["play_seconds"]))]


func _continue() -> void:
	var id: String = saves.call("latest_game") if saves != null else ""
	if id != "":
		saves.call("play_game", id)


## "2 h 14 min", "35 min", "under a minute".
static func play_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 1:
		return "under a minute played"
	if m < 60:
		return "%d min played" % m
	return "%d h %02d min played" % [m / 60, m % 60]


## "Today, 8:40 pm", "Yesterday", "26 Oct".
static func when(unix: float) -> String:
	if unix <= 0.0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(int(unix) + bias)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var hour := int(t["hour"])
	var clock := "%d:%02d %s" % [12 if hour % 12 == 0 else hour % 12, int(t["minute"]), "am" if hour < 12 else "pm"]
	if t["year"] == now["year"] and t["month"] == now["month"] and t["day"] == now["day"]:
		return "today, " + clock
	return "%d %s" % [int(t["day"]), MONTHS[int(t["month"]) - 1]]


# ---------------------------------------------------------------- pages

func show_page(which: String) -> void:
	if page != null:
		page.queue_free()
		page = null
	page_name = which
	_pages_host.visible = which != ""
	match which:
		"new":
			page = _new_game_page()
		"load":
			page = _load_page()
		"achievements":
			page = _achievements_page()
		"settings":
			page = _settings_page()
		"about":
			page = _about_page()
	if page != null:
		_pages_host.add_child(page)


func _page_box(heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var h := _label(heading, 40, AMBER)
	h.add_theme_font_override("font", _type_font)
	box.add_child(h)
	return box


func _new_game_page() -> Control:
	var box := _page_box("New game")
	box.name = "NewGamePage"
	var count: int = (saves.call("list_games") as Array).size() if saves != null else 0
	box.add_child(_label("Name this game", 17, DIM))
	var game_name := _line("Game %d" % (count + 1), "GameName", "Game %d" % (count + 1))
	box.add_child(game_name)
	box.add_child(_label("Your name: what people will call you (you can change it in the Field Manual)", 17, DIM))
	var you := _line("Survivor", "PlayerName")
	you.max_length = PlayerController.NAME_MAX
	box.add_child(you)
	box.add_child(_label("How do you want to play?", 17, DIM))
	var modes := HBoxContainer.new()
	modes.name = "Modes"
	modes.add_theme_constant_override("separation", 12)
	box.add_child(modes)
	var group := ButtonGroup.new()
	var story := _mode_card(modes, group, "Story", "Story · The Last Order",
		"Wake in Outpost 17's barracks. Sgt. Vance's Field Manual is in his footlocker; his orders lead the way.")
	_mode_card(modes, group, "FreePlay", "Free Play",
		"No orders: the whole manual's open and the map is yours. Story achievements are off.")
	story.button_pressed = true
	var start := _button("Start", "Start")
	start.custom_minimum_size = Vector2(180, 46)
	start.pressed.connect(func() -> void:
		if saves != null:
			var picked := group.get_pressed_button()
			saves.call("start_new_game", game_name.text, you.text,
				"free_play" if picked != null and picked.name == "FreePlay" else "story"))
	box.add_child(start)
	you.text_submitted.connect(func(_t: String) -> void: start.pressed.emit())
	game_name.text_submitted.connect(func(_t: String) -> void: you.grab_focus())
	game_name.call_deferred("grab_focus")
	game_name.call_deferred("select_all")
	return box


## A Story / Free Play choice: a toggle card with its name and a line on it.
func _mode_card(parent: Control, group: ButtonGroup, id: String, title: String, text: String) -> Button:
	var b := Button.new()
	b.name = id
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(300, 140)
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0.03)
	off.border_color = Color(0.32, 0.3, 0.25)
	off.set_border_width_all(1)
	off.set_corner_radius_all(3)
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color(0.91, 0.71, 0.29, 0.1)
	on.border_color = AMBER
	on.set_border_width_all(2)
	for state: String in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(state, off)
	for state: String in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, on)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var t := _label(title, 22, TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	var d := _label(text, 14, DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 270
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(d)
	b.add_child(box)
	parent.add_child(b)
	return b


func _load_page() -> Control:
	var box := _page_box("Load game")
	box.name = "LoadPage"
	var games: Array = saves.call("list_games") if saves != null else []
	if games.is_empty():
		box.add_child(_label("No games yet. Start a new one.", 18, DIM))
		return box
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "Games"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	box.add_child(scroll)
	for g: Dictionary in games:
		list.add_child(_game_card(g))
	return box


func _game_card(g: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Game_" + String(g["id"])
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.035)
	st.border_color = Color(0.32, 0.3, 0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var title := _label(String(g["name"]), 24, TEXT)
	title.name = "GameTitle"
	info.add_child(title)
	var who := String(g["player_name"])
	var mode_name := "Free Play" if g.get("mode", "story") == "free_play" else "Story"
	var line := "%s  ·  %s%s  ·  %s" % [mode_name, "as " + who + "  ·  " if who != "" else "", g["place"], play_time(float(g["play_seconds"]))]
	info.add_child(_label(line, 15, DIM))
	var last := when(float(g["last_played"]))
	info.add_child(_label(("Last played " + last) if last != "" else "Never played", 14, DIM))
	for l in info.get_children():
		if l is Label:
			(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(l as Label).custom_minimum_size.x = 120
	var rename_box := HBoxContainer.new()
	rename_box.visible = false
	var rename_edit := _line("Game name", "RenameField", String(g["name"]))
	rename_edit.custom_minimum_size.x = 260
	rename_box.add_child(rename_edit)
	var ok := _button("Keep", "KeepName")
	rename_box.add_child(ok)
	info.add_child(rename_box)
	var id := String(g["id"])
	var play := _button("Play", "Play")
	play.pressed.connect(func() -> void: saves.call("play_game", id))
	row.add_child(play)
	var rename := _button("Rename", "Rename")
	rename.pressed.connect(func() -> void:
		rename_box.visible = not rename_box.visible
		if rename_box.visible:
			rename_edit.grab_focus()
			rename_edit.select_all())
	var keep := func() -> void:
		saves.call("rename_game", id, rename_edit.text)
		show_page("load")
		_refresh_continue()
	ok.pressed.connect(keep)
	rename_edit.text_submitted.connect(func(_t: String) -> void: keep.call())
	row.add_child(rename)
	var del := _button("Delete", "Delete")
	del.add_theme_color_override("font_color", RED)
	del.pressed.connect(func() -> void:
		if del.text == "Delete":
			del.text = "Sure? Click again"
			return
		saves.call("delete_game", id)
		show_page("load")
		_refresh_continue())
	row.add_child(del)
	return card


func _achievements_page() -> Control:
	var box := _page_box("Achievements")
	box.name = "AchievementsPage"
	var have := earned_everywhere(saves)
	var note := _label("%d of %d earned, across all your games. Story ones only count in Story." % [have.size(), Achievements.count()], 16, DIM)
	note.name = "Earned"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	box.add_child(scroll)
	for cat: StringName in Achievements.CATEGORIES:
		var head := _label(Achievements.CATEGORIES[cat].to_upper(), 15, AMBER)
		head.add_theme_font_override("font", _type_font)
		list.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for a: Dictionary in Achievements.LIST:
			if a["category"] == cat:
				grid.add_child(_achievement_row(a, have.has(String(a["id"]))))
	return box


## Every achievement any game has earned (each game keeps its own).
static func earned_everywhere(save_manager: Node) -> Dictionary:
	var out := {}
	if save_manager == null:
		return out
	for g: Dictionary in save_manager.call("list_games"):
		for id: String in g.get("achievements", []):
			out[id] = true
	return out


func _achievement_row(a: Dictionary, got := false) -> Control:
	var row := HBoxContainer.new()
	row.name = "Ach_" + String(a["id"])
	row.custom_minimum_size.x = 340
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	var medal := PanelContainer.new()
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.84, 0.64, 0.26) if got else Color(0.2, 0.19, 0.16)
	ms.border_color = Color(0.96, 0.84, 0.5) if got else Color(0.36, 0.34, 0.28)
	ms.set_border_width_all(2)
	ms.set_corner_radius_all(22)
	medal.add_theme_stylebox_override("panel", ms)
	medal.custom_minimum_size = Vector2(44, 44)
	var secret: bool = a["hidden"] and not got
	var ml := _label("?" if secret else Achievements.initials(a), 17, Color(0.23, 0.16, 0.03) if got else DIM)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	medal.add_child(ml)
	row.add_child(medal)
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_constant_override("separation", 0)
	t.add_child(_label("Hidden" if secret else String(a["name"]), 18, AMBER if got else TEXT))
	var d := _label("Keep playing" if secret else String(a["text"]), 14, DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_child(d)
	row.add_child(t)
	if got:
		row.set_meta("earned", true)
	return row


func _settings_page() -> Control:
	var box := _page_box("Settings")
	box.name = "SettingsPage"
	var panel := SettingsPanel.new()
	panel.custom_minimum_size.x = 420
	box.add_child(panel)
	return box


func _about_page() -> Control:
	var box := _page_box("About")
	box.name = "AboutPage"
	var text := RichTextLabel.new()
	text.name = "AboutText"
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.add_theme_color_override("default_color", TEXT)
	text.text = about_text()
	text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	box.add_child(text)
	return box


## The About page: the game, then the credits and every licence the game
## has to carry (Godot's and the fonts').
static func about_text() -> String:
	var t := ""
	t += "[b]ASHFALL: Reclamation[/b] is a survival game set on a coast burned grey by the ash. You start at Outpost 17, an army post its garrison was ordered to hold and never left, with a machete and the Field Manual of the sergeant who held it last. Scavenge, fight raiders, claim the places around you and build them into settlements that feed, arm and defend themselves.\n\n"
	t += "In the game, press [b]N[/b] for the Field Manual: it explains everything as you need it.\n\n"
	t += "[color=#f2b860][b]CREDITS[/b][/color]\n"
	t += "A DeBaca Video Game Studios game.\n\n"
	t += "[b]Characters, animations, clothes, guns, farm buildings and Halden's Crossing's city kit[/b] by Quaternius (quaternius.com), CC0: thank you.\n"
	t += "[b]Fonts:[/b] Special Elite by Astigmatic (Apache License 2.0) and Caveat by the Caveat Project Authors (SIL Open Font License 1.1), via Google Fonts.\n"
	t += "[b]Made with the Godot Engine[/b] (godotengine.org), MIT licence.\n\n"
	t += "[color=#f2b860][b]LICENCES[/b][/color]\n\n"
	t += "[b]Godot Engine[/b]\n" + Engine.get_license_text().replace("[", "[lb]") + "\n\n"
	for f: Array in [["Caveat", "res://assets/fonts/LICENSE_Caveat_OFL.txt"], ["Special Elite", "res://assets/fonts/LICENSE_SpecialElite_Apache.txt"]]:
		var body := FileAccess.get_file_as_string(f[1])
		t += "[b]%s[/b]\n%s\n\n" % [f[0], body.replace("[", "[lb]")]
	return t


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if page_name != "":
			show_page("")
			get_viewport().set_input_as_handled()
