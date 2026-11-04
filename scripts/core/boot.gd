extends Control
## The first scene (Increment 24.1): gets the game ready, then starts it.
##
## 1. AFTER AN UPDATE. Godot keeps lists of the game's scripts and imported
##    files in the hidden .godot folder, and only the editor rebuilds them.
##    Pressing Run in the Project Manager after a pull used to start the game
##    with the old lists: new scripts didn't load and the game froze. Now,
##    when this is the editor's Godot (Run, or F5 in the editor) and the lists
##    are out of date, the boot screen rebuilds them (godot --headless
##    --import, the same as opening the editor) and starts the game again.
## 2. CONTINUE. Loads your latest save (the autosave or the quick save,
##    whichever is newer) and turns autosaving on. With no save, or with
##    `-- --new-game` on the command line, a new game starts.
##
## No class_name, and only engine types here and in the boot scene: it has
## to run while the lists are out of date.

const GAME_LEVEL := "res://levels/early_zone/early_zone.tscn"
## Given to the game when it restarts after rebuilding, so it never loops.
const AFTER_UPDATE_ARG := "--after-update"
const NEW_GAME_ARG := "--new-game"
## Give up waiting for the rebuild after this long and start anyway.
const REBUILD_TIMEOUT := 900.0

var _title: Label
var _status: Label
var _rebuild_pid := -1
var _rebuild_time := 0.0


func _ready() -> void:
	_build_ui()
	var after_update := OS.get_cmdline_user_args().has(AFTER_UPDATE_ARG)
	var stale := stale_reasons() if OS.has_feature("editor") else PackedStringArray()
	if not stale.is_empty():
		print("Boot: Godot's lists are out of date (%d): %s" % [stale.size(), ", ".join(stale.slice(0, 8))])
		if not after_update and _start_rebuild():
			return
		push_warning("Boot: starting with out-of-date lists; open the project with Edit if the game won't start")
	_status.text = "Loading…"
	_start_game.call_deferred()


func _process(delta: float) -> void:
	if _rebuild_pid < 0:
		return
	_rebuild_time += delta
	var dots := ".".repeat(int(_rebuild_time * 2.0) % 4)
	_status.text = "This happens once after each update and takes a minute or two.\nThe game starts by itself when it's ready%s\n\n%d s" % [dots, int(_rebuild_time)]
	if OS.is_process_running(_rebuild_pid) and _rebuild_time < REBUILD_TIMEOUT:
		return
	_rebuild_pid = -1
	_restart()


# ---------------------------------------------------------------- the lists

## What's out of date: script classes Godot doesn't know about yet (or knows
## at another path) and files that haven't been imported. Empty when the
## game can start.
static func stale_reasons() -> PackedStringArray:
	var out := PackedStringArray()
	for c in missing_classes():
		out.append("class " + c)
	for f in unimported_files():
		out.append("import " + f)
	return out


## Every `class_name` in the project's scripts that Godot's class list
## doesn't have at that script's path.
static func missing_classes() -> PackedStringArray:
	var known := {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		known[str(c["class"])] = str(c["path"])
	var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var out := PackedStringArray()
	for path in project_files("gd"):
		var m := re.search(FileAccess.get_file_as_string(path))
		if m != null and known.get(m.get_string(1), "") != path:
			out.append(m.get_string(1))
	return out


## Source files whose imported copy isn't in .godot/imported yet.
static func unimported_files() -> PackedStringArray:
	var out := PackedStringArray()
	for path in project_files("import"):
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		if str(cfg.get_value("remap", "importer", "")) in ["keep", "skip", ""]:
			continue
		if cfg.get_value("remap", "valid", true) == false:
			continue
		for dest: Variant in cfg.get_value("deps", "dest_files", []):
			if not FileAccess.file_exists(str(dest)):
				out.append(path.trim_suffix(".import"))
				break
	return out


## Every file in the project with this extension (not in hidden folders).
static func project_files(extension: String, dir := "res://") -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.include_hidden = false
	for f in d.get_files():
		if f.get_extension() == extension:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(project_files(extension, dir.path_join(sub)))
	return out


# ---------------------------------------------------------------- rebuilding

## Runs the editor's import in the background. False if it couldn't start.
func _start_rebuild() -> bool:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"])
	_rebuild_pid = OS.create_process(OS.get_executable_path(), args)
	if _rebuild_pid <= 0:
		_rebuild_pid = -1
		return false
	_title.text = "Getting the update ready"
	return true


## Starts the game again with the new lists, and closes this one.
func _restart() -> void:
	_status.text = "Starting…"
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--", AFTER_UPDATE_ARG])
	if OS.get_cmdline_user_args().has(NEW_GAME_ARG):
		args.append(NEW_GAME_ARG)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


# ---------------------------------------------------------------- starting

func _start_game() -> void:
	var saves := get_node_or_null("/root/SaveManager")
	if saves != null and saves.has_method("continue_game"):
		saves.set("autosave_enabled", true)
		if not OS.get_cmdline_user_args().has(NEW_GAME_ARG) and saves.call("continue_game") == OK:
			return
	get_tree().change_scene_to_file(GAME_LEVEL)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	var name_label := Label.new()
	name_label.text = "ASHFALL: RECLAMATION"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.38))
	box.add_child(name_label)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	box.add_child(_status)
