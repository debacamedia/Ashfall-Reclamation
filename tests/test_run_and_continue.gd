extends "res://tests/test_case.gd"
## Increment 24.1: playing with Run, autosave and continue. The game starts
## at a boot screen that rebuilds Godot's lists after an update and then
## continues your latest save; the game autosaves every few minutes and when
## you quit; Esc opens a pause menu; saves from earlier updates still load.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOOT := "res://scripts/core/boot.gd"
const ZONE := "res://levels/early_zone/early_zone.tscn"
const TEST_DIR := "user://test_saves_continue"
const DT := 1.0 / 60.0

var saves: Node
var _old_dir := ""


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old_dir = saves.save_dir
		saves.save_dir = TEST_DIR
		_clean())
	tree_exiting.connect(func() -> void:
		_clean()
		saves.autosave_enabled = false
		saves.save_dir = _old_dir)


func _clean() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)


func _player() -> PlayerController:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.name = "Player"
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


func _hud(p: PlayerController) -> HUD:
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	return hud


func _notices(hud: HUD) -> Array:
	var box := hud.get_node("%Notices") as VBoxContainer
	return box.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).map(func(n: Label) -> String: return n.text)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


# ---------------------------------------------------------------- boot

func test_the_game_starts_at_the_boot_screen() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot/boot.tscn", "Run starts at the boot screen")
	var boot: GDScript = load(BOOT)
	check(boot.GAME_LEVEL == ZONE and PauseMenu.GAME_LEVEL == ZONE, "which opens the early zone")
	check(not RegEx.create_from_string("(?m)^class_name").search(boot.source_code), "the boot script has no class_name (it has to run while the lists are old)")
	check(boot.stale_reasons().is_empty(), "nothing out of date here: %s" % [boot.stale_reasons()])
	check(boot.project_files("gd").has("res://scripts/core/boot.gd") and boot.project_files("import").size() > 100, "it looks at every script and imported file")


func test_boot_spots_an_update() -> void:
	var boot: GDScript = load(BOOT)
	var dir := "res://tests/_update_check"
	DirAccess.make_dir_recursive_absolute(dir)
	var gd := FileAccess.open(dir + "/new_thing.gd", FileAccess.WRITE)
	gd.store_string("class_name UpdateCheckNewThing\nextends Node\n")
	gd.close()
	var imp := FileAccess.open(dir + "/new_art.png.import", FileAccess.WRITE)
	imp.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\npath=\"res://.godot/imported/new_art.png-0.ctex\"\n\n[deps]\n\nsource_file=\"%s/new_art.png\"\ndest_files=[\"res://.godot/imported/new_art.png-0.ctex\"]\n" % dir)
	imp.close()
	var classes: PackedStringArray = boot.missing_classes()
	var files: PackedStringArray = boot.unimported_files()
	var reasons: PackedStringArray = boot.stale_reasons()
	DirAccess.remove_absolute(dir + "/new_thing.gd")
	DirAccess.remove_absolute(dir + "/new_art.png.import")
	DirAccess.remove_absolute(dir)
	check(classes == PackedStringArray(["UpdateCheckNewThing"]), "a new script's class isn't in Godot's list yet: %s" % [classes])
	check(files == PackedStringArray([dir + "/new_art.png"]), "new art isn't imported yet: %s" % [files])
	check(reasons.size() == 2, "so the boot screen rebuilds before starting: %s" % [reasons])
	check(boot.stale_reasons().is_empty(), "and nothing once they're gone")
	check(boot.AFTER_UPDATE_ARG == "--after-update", "the restart is marked, so it never rebuilds twice")


# ---------------------------------------------------------------- autosave

func test_autosave_and_continue() -> void:
	var p := _player()
	var hud := _hud(p)
	var previous := get_tree().current_scene
	get_tree().current_scene = self
	await wait_physics(3)
	check(not saves.autosave_enabled, "off unless the boot screen started the game (tests never autosave)")
	check(saves.latest_slot() == "" and saves.continue_game() == ERR_FILE_NOT_FOUND, "no save: nothing to continue (a new game)")
	saves.autosave_enabled = true
	check(is_equal_approx(saves.autosave_left, saves.autosave_minutes * 60.0) and saves.autosave_minutes == 5.0, "every 5 minutes")
	p.health.apply_damage(DamageInfo.create(30.0, DamageInfo.Type.FALL))
	saves.autosave_left = 0.05
	await wait_physics(8)
	check(saves.has_save(saves.AUTO_SLOT), "autosaved")
	check(_notices(hud).has("Autosaved"), "with a quiet notice: %s" % [_notices(hud)])
	check(saves.autosave_left > 290.0, "and the next one in 5 minutes")
	check(saves.latest_slot() == saves.AUTO_SLOT, "the autosave is the latest")
	# Continue picks the newest of the autosave and the quick save
	await get_tree().create_timer(1.1).timeout
	p.health.heal(10.0)
	saves.save_game(saves.QUICK_SLOT)
	check(saves.latest_slot() == saves.QUICK_SLOT, "a newer quick save is the latest")
	p.health.heal(100.0)
	check(saves.continue_game() == OK, "continue")
	await wait_physics(2)
	check_near(p.health.current_health, 80.0, 0.01, "carried on from the quick save (80)")
	check(saves.latest_save_time().begins_with("at ") and saves.latest_save_time().contains(":") and (saves.latest_save_time().ends_with("am") or saves.latest_save_time().ends_with("pm")), "when: %s" % saves.latest_save_time())
	# Dead: no autosave, no complaint, try again soon
	_clean()
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	var said := _notices(hud).size()
	saves.autosave_left = 0.05
	await wait_physics(8)
	check(not saves.has_save(saves.AUTO_SLOT) and saves.autosave_left <= 30.0, "not while dead; tries again in half a minute")
	check(not _notices(hud).has("Can't save while dead") or _notices(hud).size() == said, "and says nothing")
	saves.autosave_enabled = false
	get_tree().current_scene = previous


# ---------------------------------------------------------------- pause menu

func test_the_pause_menu() -> void:
	var p := _player()
	var hud := _hud(p)
	var previous := get_tree().current_scene
	get_tree().current_scene = self
	await wait_physics(3)
	var menu := hud.pause_menu
	check(menu != null and not menu.visible and menu.process_mode == Node.PROCESS_MODE_ALWAYS, "a pause menu, closed")
	p.controlled_locally = true
	_press("pause")
	await wait_physics(2)
	check(menu.visible and get_tree().paused and p.player_input.ui_open, "Esc opens it and pauses the game")
	_press("pause")
	await wait_physics(2)
	check(not menu.visible and not get_tree().paused and not p.player_input.ui_open, "Esc again resumes")
	p.player_input.set_ui_open(true)  # another window is open: Esc is that window's
	_press("pause")
	await wait_physics(2)
	check(not menu.visible, "not over another window")
	p.player_input.set_ui_open(false)
	p.controlled_locally = false
	menu.open()
	check((menu.find_child("Info", true, false) as Label).text.contains("Not saved yet"), "says it isn't saved yet")
	p.health.apply_damage(DamageInfo.create(25.0, DamageInfo.Type.FALL))
	(menu.find_child("Save", true, false) as Button).pressed.emit()
	check(saves.has_save(saves.QUICK_SLOT), "Save game writes the quick save")
	check((menu.find_child("Status", true, false) as Label).text == "Saved", "Saved")
	check((menu.find_child("Info", true, false) as Label).text.contains("Last saved at"), "and when: %s" % (menu.find_child("Info", true, false) as Label).text)
	p.health.heal(25.0)
	(menu.find_child("Load", true, false) as Button).pressed.emit()
	await wait_physics(2)
	check(not menu.visible and not get_tree().paused, "Load last save closes the menu")
	check_near(p.health.current_health, 75.0, 0.01, "and loads it")
	menu.open()
	var new_game := menu.find_child("NewGame", true, false) as Button
	new_game.pressed.emit()
	check(new_game.text == "Start over? Click again" and menu.visible, "New game asks first")
	(menu.find_child("Resume", true, false) as Button).pressed.emit()
	check(not menu.visible and not get_tree().paused, "Resume")
	menu.open()
	check(new_game.text == "New game", "and asks again next time")
	menu.close()
	check(menu.find_child("Quit", true, false) != null, "Save and quit")
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	menu.open()
	check(not menu.visible, "not while dead")
	get_tree().paused = false
	get_tree().current_scene = previous


# ---------------------------------------------------------------- old saves

## Loads a fixture save into the zone. `right_after` runs before the world
## has moved on (the settlers start using the stores at once).
func _load_fixture(fixture: String, zone: Node3D, right_after := Callable()) -> Error:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	DirAccess.copy_absolute(fixture, TEST_DIR + "/fixture.json")
	var err: Error = saves.load_game("fixture", zone)
	if right_after.is_valid():
		right_after.call()
	await wait_physics(10)
	return err


func test_a_save_from_increment_24_still_loads() -> void:
	var zone := await load_zone()
	var stores := func() -> void:
		var farm_planks := Settlement.find(get_tree(), &"ash_creek").store.inventory.count_of(&"wood_plank")
		var mine_scrap := Settlement.find(get_tree(), &"black_ridge").store.inventory.count_of(&"scrap_metal")
		check(farm_planks == 9 and mine_scrap == 13, "the stores (%d planks, %d scrap)" % [farm_planks, mine_scrap])
	check(await _load_fixture("res://tests/fixtures/save_24_1.json", zone, stores) == OK, "loaded the 24 save")
	var p := zone.get_node("Player") as PlayerController
	check_near(p.health.current_health, 65.0, 0.01, "health 65")
	check(p.inventory.count_of(&"scrap_metal") == 11 and p.inventory.count_of(&"medkit") == 3, "the backpack (%d scrap, %d medkits)" % [p.inventory.count_of(&"scrap_metal"), p.inventory.count_of(&"medkit")])
	var farm := Settlement.find(get_tree(), &"ash_creek")
	var mine := Settlement.find(get_tree(), &"black_ridge")
	var nw := Settlement.find(get_tree(), &"northwatch")
	check(p.global_position.distance_to(farm.global_transform * Vector3(4, 0.2, 18)) < 1.0, "standing at the farm")
	check(farm.is_claimed and mine.is_claimed and not nw.is_claimed, "the farm and the mine are yours")
	var names := farm.members().map(func(s: Settler) -> String: return "%s %s" % [s.settler_name, s.role_name()])
	check(names.has("Dale Farmer") and names.has("Zeke Guard") and names.size() == 2, "the farm's settlers: %s" % [names])
	check(mine.members().size() == 1 and mine.members()[0].settler_name == "Edie" and mine.members()[0].role == Settler.Role.MINER, "the mine's Miner")
	check(is_equal_approx(farm.food_share, 67.0) and is_equal_approx(mine.food_share, 30.0), "the food shares")
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func test_a_save_from_october_still_loads() -> void:
	var zone := await load_zone()
	check(await _load_fixture("res://tests/fixtures/save_v3_oct26.json", zone) == OK, "loaded a version 3 save from 26 Oct (before settlements)")
	var p := zone.get_node("Player") as PlayerController
	check(p.global_position.distance_to(Vector3(440, 0, -265)) < 1.0, "where it was saved (%s)" % p.global_position)
	check(not Settlement.find(get_tree(), &"ash_creek").is_claimed, "nothing claimed yet, and the settlements are all there")
	remove_child(zone)
	zone.free()
	await wait_physics(2)
