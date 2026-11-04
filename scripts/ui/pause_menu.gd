class_name PauseMenu
extends Control
## The Esc menu (Increment 24.1): Resume, Save game, Load last save, New
## game and Quit. The game pauses while it's open. Quit saves first (to the
## autosave slot), so the next launch carries on from here.
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
	_new_button = _button(box, "NewGame", "New game", _new_game)
	_button(box, "Quit", "Save and quit", _quit)
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
	_new_button.text = "New game"
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


func _new_game() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_button.text = "Start over? Click again"
		_status.text = "Your saves are kept until the game saves over them"
		return
	close()
	var world := get_node_or_null("/root/WorldManager")
	if world != null:
		world.reset()
	var saves := _saves()
	if saves != null and saves.autosave_enabled:
		saves.autosave_enabled = true  # the next autosave is a full interval away
	get_tree().change_scene_to_file(GAME_LEVEL)


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
