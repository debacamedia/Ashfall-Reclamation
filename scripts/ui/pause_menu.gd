class_name PauseMenu
extends Control
## The Esc menu (Increment 24.1): Resume, Save game, Load last save,
## Settings, Main menu and Quit. The game pauses while it's open. Main menu
## and Quit save first (to the autosave slot), so Continue carries on from
## here. (New game moved to the main menu in Increment 33.1.)
##
## Built in code by the HUD. Esc only opens it when no other window is open
## (Esc closes those first).

const GAME_LEVEL := "res://levels/early_zone/early_zone.tscn"
const TITLE_COLOR := Color(0.95, 0.72, 0.38)
const TEXT := Color(0.86, 0.84, 0.78)

var player: PlayerController
var _info: Label
var _status: Label
var _new_button: Button
## New game needs a second click.
var _confirm_new := false
var _settings_box: VBoxContainer
var _buttons_box: VBoxContainer


func _init() -> void:
	name = "PauseMenu"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var window := PanelContainer.new()
	window.name = "Window"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.065, 0.97)
	style.set_border_width_all(1)
	style.border_color = Color(0.45, 0.4, 0.3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(20)
	window.add_theme_stylebox_override("panel", style)
	center.add_child(window)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	box.add_theme_constant_override("separation", 10)
	window.add_child(box)
	var title := _label("PAUSED", 28, TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_button(box, "Resume", "Resume  (Esc)", close)
	_button(box, "Save", "Save game  (F5)", _save)
	_button(box, "Load", "Load last save  (F9)", _load)
	_button(box, "SettingsButton", "Settings", _show_settings)
	_new_button = _button(box, "MainMenu", "Save and go to the main menu", _to_menu)
	_button(box, "Quit", "Save and quit", _quit)
	# Settings, in place of the buttons while they're shown
	_settings_box = VBoxContainer.new()
	_settings_box.name = "SettingsBox"
	_settings_box.visible = false
	_settings_box.add_theme_constant_override("separation", 12)
	_settings_box.add_child(SettingsPanel.new())
	_button(_settings_box, "SettingsBack", "Back", _hide_settings)
	box.add_child(_settings_box)
	_buttons_box = box
	_info = _label("", 14, TEXT)
	_info.name = "Info"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_status = _label("", 15, Color(0.7, 0.95, 0.7))
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func is_open() -> bool:
	return visible


func open() -> void:
	if player == null or player.is_dead():
		return
	visible = true
	_confirm_new = false
	_hide_settings()
	_status.text = ""
	_refresh_info()
	player.player_input.set_ui_open(true)
	get_tree().paused = true


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if player != null:
		player.player_input.set_ui_open(false)


func _input(event: InputEvent) -> void:
	# Typing in a text box (your name in the Field Manual, 33.1): keys are letters
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if player == null or not player.controlled_locally:
		return
	if not event.is_action_pressed("pause"):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
	elif not player.player_input.ui_open and player.current_container == null and not player.is_dead():
		open()
		get_viewport().set_input_as_handled()


func _saves() -> Node:
	return get_node_or_null("/root/SaveManager")


func _refresh_info() -> void:
	var saves := _saves()
	if saves == null:
		_info.text = ""
		return
	var when: String = saves.latest_save_time()
	_info.text = "Your game saves itself every %d minutes and when you quit.\n%s" % [
		int(saves.autosave_minutes), "Last saved " + when if when != "" else "Not saved yet"]


func _save() -> void:
	var saves := _saves()
	if saves != null and saves.save_game(saves.QUICK_SLOT) == OK:
		_status.text = "Saved"
		_refresh_info()


func _load() -> void:
	var saves := _saves()
	if saves == null or saves.latest_slot() == "":
		_status.text = "No save yet"
		return
	close()
	saves.continue_game()


func _show_settings() -> void:
	for c in _buttons_box.get_children():
		if c is Button:
			(c as Button).visible = false
	_settings_box.visible = true


func _hide_settings() -> void:
	if _settings_box == null:
		return
	for c in _buttons_box.get_children():
		if c is Button:
			(c as Button).visible = true
	_settings_box.visible = false


func _to_menu() -> void:
	close()
	var saves := _saves()
	if saves != null and saves.has_method("quit_to_menu"):
		saves.quit_to_menu()


func _quit() -> void:
	var saves := _saves()
	if saves != null:
		saves.autosave()
	get_tree().paused = false
	get_tree().quit()


func _button(parent: Control, id: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
