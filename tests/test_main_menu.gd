extends "res://tests/test_case.gd"
## Increment 33.1: the main menu. The game opens on it: Continue, New game,
## Load game (each game its own folder of saves, with its name, your name,
## where you were and how long you've played; rename and delete), the
## achievements (listed; counted from Increment 34), Settings (also in the
## pause menu) and About (credits and every licence the game must carry).
## Saves from before become a first game.

const ROOT := "user://test_menu_games"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var saves: Node
var _old := []


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old = [saves.save_dir, saves.root_dir, saves.current_game, saves.play_seconds]
		saves.root_dir = ROOT
		saves.save_dir = ROOT
		saves.current_game = ""
		_wipe(ROOT))
	tree_exiting.connect(func() -> void:
		_wipe(ROOT)
		saves.autosave_enabled = false
		saves.save_dir = _old[0]
		saves.root_dir = _old[1]
		saves.current_game = _old[2]
		saves.play_seconds = _old[3])


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	if dir != ROOT:
		DirAccess.remove_absolute(dir)


func _player() -> PlayerController:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.name = "Player"
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


# ---------------------------------------------------------------- games

func test_games_each_with_their_own_saves() -> void:
	check(saves.list_games().is_empty() and saves.latest_game() == "", "no games yet")
	var a: String = saves.create_game("Coastal run", "Gabe")
	check(saves.current_game == a and saves.save_dir == saves.game_dir(a), "a new game is picked")
	var p := _player()
	var previous := get_tree().current_scene
	get_tree().current_scene = self
	await wait_physics(3)
	p.set_player_name("Gabe")
	saves.play_seconds = 125.0 * 60.0
	check(saves.save_game(saves.AUTO_SLOT) == OK, "saved into it")
	var info: Dictionary = saves.game_info(a)
	check(info["name"] == "Coastal run" and info["player_name"] == "Gabe" and info["has_save"], "its card: %s" % [info])
	check(is_equal_approx(float(info["play_seconds"]), 7500.0) and float(info["last_played"]) > 0.0, "how long and when")
	check(String(info["place"]) != "", "where: %s" % info["place"])
	# A second game doesn't touch the first
	var b: String = saves.create_game("Hard mode")
	check(saves.save_dir == saves.game_dir(b) and not saves.has_save(saves.AUTO_SLOT), "the second starts empty")
	p.health.apply_damage(DamageInfo.create(40.0, DamageInfo.Type.FALL))
	saves.save_game(saves.QUICK_SLOT)
	check(saves.list_games().size() == 2, "two games")
	saves.use_game(a)
	check(saves.has_save(saves.AUTO_SLOT) and not saves.has_save(saves.QUICK_SLOT), "the first has only its own save")
	check(saves.latest_game() != "", "Continue has a game")
	saves.rename_game(b, "  Iron man  ")
	check(saves.game_info(b)["name"] == "Iron man", "renamed")
	saves.delete_game(b)
	check(saves.game_info(b).is_empty() and not DirAccess.dir_exists_absolute(saves.game_dir(b)), "deleted, saves and all")
	check(saves.list_games().size() == 1 and saves.latest_game() == a, "the other kept")
	get_tree().current_scene = previous


func test_saves_from_before_become_a_first_game() -> void:
	var f := FileAccess.open(ROOT.path_join("autosave.json"), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://tests/fixtures/save_27.json"))
	f.close()
	var id: String = saves.migrate_legacy()
	check(id != "", "moved into a game")
	check(not FileAccess.file_exists(ROOT.path_join("autosave.json")), "out of the old place")
	var info: Dictionary = saves.game_info(id)
	check(info["name"] == "Your first game" and info["has_save"], "\"Your first game\", with its save")
	check(saves.latest_game() == id, "and Continue carries it on")
	check(saves.migrate_legacy() == "", "once")
	check(saves.current_game == "", "nothing picked until you play")


# ---------------------------------------------------------------- the menu

func _menu() -> MainMenu:
	var m := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(m)
	await get_tree().process_frame
	return m


func test_the_menu() -> void:
	var m := await _menu()
	for id in ["Continue", "NewGame", "LoadGame", "Achievements", "SettingsButton", "About", "Quit"]:
		check(m.buttons.has(id), "%s" % id)
	check((m.buttons["Continue"] as Button).disabled, "Continue greyed with no game")
	check(m.find_child("Art", true, false) != null, "a picture of the game behind it")
	m.show_page("new")
	check(m.find_child("GameName", true, false) is LineEdit and m.find_child("PlayerName", true, false) is LineEdit, "New game: a name for the game and for you")
	m.show_page("achievements")
	await get_tree().process_frame
	var rows := m.find_children("Ach_*", "HBoxContainer", true, false)
	check(rows.size() == Achievements.count() and Achievements.count() == 33, "the 33 achievements (%d)" % rows.size())
	m.show_page("settings")
	check(m.find_child("UiSize", true, false) is HSlider and m.find_child("Mouse", true, false) is HSlider and m.find_child("Volume", true, false) is HSlider \
		and m.find_child("Fullscreen", true, false) is CheckButton, "Settings: interface size, mouse speed, volume, full screen")
	m.show_page("about")
	var about := MainMenu.about_text()
	check(about.contains("Copyright (c) 2014-present Godot Engine contributors"), "About carries Godot's licence")
	check(about.contains("SIL OPEN FONT LICENSE") and about.contains("Apache License"), "and the fonts'")
	check(about.contains("Quaternius"), "and thanks Quaternius")
	m.show_page("")
	check(not (m.find_child("Page", true, false) as Control).visible, "Esc or back: just the menu")
	# With a game: Continue, and the Load page's cards
	saves.create_game("Coastal run", "Gabe")
	FileAccess.open(saves.slot_path(saves.AUTO_SLOT), FileAccess.WRITE).store_string("{}")
	saves.current_game = ""
	m._refresh_continue()
	check(not (m.buttons["Continue"] as Button).disabled and m._continue_sub.text.begins_with("Coastal run"), "Continue: %s" % m._continue_sub.text)
	m.show_page("load")
	var cards := m.find_children("Game_*", "PanelContainer", true, false)
	check(cards.size() == 1, "one game card")
	var del := cards[0].find_child("Delete", true, false) as Button
	del.pressed.emit()
	check(saves.list_games().size() == 1 and del.text.begins_with("Sure"), "Delete asks first")
	del.pressed.emit()
	check(saves.list_games().is_empty(), "then deletes")
	m.queue_free()


func test_settings_are_kept() -> void:
	GameSettings.ensure_loaded()
	var was := [GameSettings.mouse_scale, GameSettings.volume]
	GameSettings.set_mouse(1.7)
	GameSettings.set_volume(0.4)
	GameSettings.mouse_scale = 1.0
	GameSettings.volume = 1.0
	GameSettings.load_all()
	check(is_equal_approx(GameSettings.mouse_scale, 1.7) and is_equal_approx(GameSettings.volume, 0.4), "kept in settings.cfg")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))), 0.4), "the volume applied")
	GameSettings.set_mouse(9.0)
	check(GameSettings.mouse_scale == GameSettings.MOUSE_MAX, "within limits")
	GameSettings.set_mouse(was[0])
	GameSettings.set_volume(was[1])


func test_the_game_opens_on_the_menu() -> void:
	var boot: GDScript = load("res://scripts/core/boot.gd")
	check(boot.MENU == "res://scenes/ui/main_menu.tscn" and ResourceLoader.exists(boot.MENU), "Run opens the main menu")
	check(boot.NEW_GAME_ARG == "--new-game" and boot.CONTINUE_ARG == "--continue", "or straight into a game, for testing")
