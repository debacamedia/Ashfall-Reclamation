extends "res://tests/test_case.gd"
## Increment 34: the 33 achievements, earned per game. Each shows as a toast
## (top right) once; story ones only count in Story. The game's card keeps
## what it's earned and how it's played, and the main menu shows everything
## earned across your games. New game asks Story or Free Play.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const ROOT := "user://test_achievement_games"

var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")
var saves: Node
var _old := []


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old = [saves.save_dir, saves.root_dir, saves.current_game]
		saves.root_dir = ROOT
		saves.save_dir = ROOT
		saves.current_game = ""
		_wipe(ROOT))
	tree_exiting.connect(func() -> void:
		_wipe(ROOT)
		saves.autosave_enabled = false
		saves.save_dir = _old[0]
		saves.root_dir = _old[1]
		saves.current_game = _old[2])


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
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.name = "Player"
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	return p


func _raider(at: Vector3, kind := "Raider") -> Node3D:
	var r := Node3D.new()
	r.set_meta("kind", kind)
	add_child(r)
	r.global_position = at
	return r


func _kill(p: PlayerController, at: Vector3, type := DamageInfo.Type.BALLISTIC) -> void:
	var info := DamageInfo.create(50.0, type)
	info.source = p
	StoryProgress.on_raider_killed(_raider(at), info)


# ---------------------------------------------------------------- the list

func test_the_33() -> void:
	check(Achievements.count() == 33, "33 achievements")
	var per := {}
	for a: Dictionary in Achievements.LIST:
		per[a["category"]] = int(per.get(a["category"], 0)) + 1
		check(Achievements.CATEGORIES.has(a["category"]), "%s: a known category" % a["name"])
		check(Achievements.find(a["id"]) == a, "%s: found by its id" % a["name"])
	check(per[&"story"] == 6, "six story ones: %s" % [per])
	check(Achievements.initials(Achievements.find(&"first_light")) == "FL", "medal initials")


# ---------------------------------------------------------------- earning

func test_earned_once_with_a_toast() -> void:
	var p := await _player()
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(3)
	await get_tree().process_frame
	var heard := []
	p.story.achievement_earned.connect(func(id: StringName) -> void: heard.append(id))
	_kill(p, Vector3(5, 0, 5))
	_kill(p, Vector3(6, 0, 5))
	check(heard == [&"first_blood"], "First Blood, once: %s" % [heard])
	await get_tree().process_frame
	await get_tree().process_frame
	var toast := hud.achievement_toast
	check(toast.visible and toast.shown == [&"first_blood"], "a toast, top right")
	check((toast.find_child("Name", true, false) as Label).text == "First Blood", "with its name")
	check(toast.global_position.x > toast.get_viewport_rect().size.x / 2.0, "on the right (%s)" % toast.global_position)
	p.story.got_gear_back()
	await get_tree().create_timer(AchievementToast.SHOW_TIME + 0.3).timeout
	await get_tree().process_frame
	check(toast.shown == [&"first_blood", &"back_for_it"], "the next waits its turn: %s" % [toast.shown])


func test_what_you_do() -> void:
	var p := await _player()
	var st := p.story
	_kill(p, Vector3(200, 0, 0))
	check(st.has_earned(&"long_shot"), "Long Shot: more than 150 m")
	_kill(p, Vector3(5, 0, 0), DamageInfo.Type.VEHICLE)
	check(st.has_earned(&"roadkill"), "Roadkill: with the truck")
	# A medkit in a fight (hurt just now), not out of one
	var p2 := await _player()
	p2.item_use_finished.emit(MEDKIT)
	check(not p2.story.has_earned(&"patched_up"), "a medkit at rest: no")
	p2.health.apply_damage(DamageInfo.create(20.0, DamageInfo.Type.BALLISTIC))
	p2.item_use_finished.emit(MEDKIT)
	check(p2.story.has_earned(&"patched_up"), "Patched Up: in the middle of a fight")
	# Held the Line: a raid beaten with nobody wounded
	st.raid_over(&"ash_creek", {"killed": 3, "wounded": ["Tomas"], "stolen": {}})
	check(not st.has_earned(&"held_the_line"), "someone wounded: no")
	st.raid_over(&"ash_creek", {"killed": 3, "wounded": [], "stolen": {}})
	check(st.has_earned(&"held_the_line"), "Held the Line")
	check(int(st.stats["raids_over"]["ash_creek"]) == 2, "and the farm's raids counted (for its order)")


func test_free_play_has_no_story_ones() -> void:
	var p := await _player()
	p.story.begin(StoryProgress.Mode.FREE_PLAY)
	for a: Dictionary in Achievements.LIST:
		check(p.story.can_earn(a["id"]) == (a["category"] != &"story"), "%s: %s" % [a["name"], "no" if a["category"] == &"story" else "yes"])
	check(not p.story.earn(&"roots") and p.story.earn(&"first_blood"), "earning follows")


# ---------------------------------------------------------------- the menu

func test_the_games_card_and_the_menu() -> void:
	var id: String = saves.create_game("Coastal run", "Gabe")
	var p := await _player()
	var previous := get_tree().current_scene
	get_tree().current_scene = self
	p.story.earn(&"first_blood")
	p.story.earn(&"pipe_dream")
	check(saves.save_game(saves.AUTO_SLOT) == OK, "saved")
	var info: Dictionary = saves.game_info(id)
	check(info["mode"] == "story", "the card says Story")
	check(info["achievements"].size() == 2 and info["achievements"].has("first_blood"), "and what it's earned: %s" % [info["achievements"]])
	var b: String = saves.create_game("Sandbox")
	p.story.begin(StoryProgress.Mode.FREE_PLAY)
	p.story.earn(&"long_shot")
	saves.save_game(saves.AUTO_SLOT)
	check(saves.game_info(b)["mode"] == "free_play", "Free Play on its card")
	get_tree().current_scene = previous
	var all := MainMenu.earned_everywhere(saves)
	check(all.size() == 3 and all.has("long_shot") and all.has("pipe_dream"), "the menu counts every game's: %s" % [all.keys()])
	var m := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(m)
	await get_tree().process_frame
	m.show_page("achievements")
	await get_tree().process_frame
	var note := m.find_child("Earned", true, false) as Label
	check(note != null and note.text.begins_with("3 of 33 earned"), "3 of 33 earned: %s" % (note.text if note != null else "?"))
	var got := 0
	for row in m.find_children("Ach_*", "HBoxContainer", true, false):
		if row.has_meta("earned"):
			got += 1
	check(got == 3, "three medals lit (%d)" % got)
	m.show_page("load")
	await get_tree().process_frame
	var lines := []
	for l in m.find_children("*", "Label", true, false):
		lines.append((l as Label).text)
	check(lines.any(func(t: String) -> bool: return t.begins_with("Free Play  ·  ")) and lines.any(func(t: String) -> bool: return t.begins_with("Story  ·  as Gabe")),
		"each card says how it's played")
	# New game: Story or Free Play, Story picked
	m.show_page("new")
	await get_tree().process_frame
	var story := m.find_child("Story", true, false) as Button
	var free := m.find_child("FreePlay", true, false) as Button
	check(story != null and free != null and story.button_pressed and not free.button_pressed, "New game: Story or Free Play, Story picked")
	free.button_pressed = true
	check(not story.button_pressed, "one or the other")
	var all_text := ""
	for l in m.find_children("*", "Label", true, false):
		all_text += (l as Label).text + "\n"
	check(not all_text.contains("next update"), "no \"next update\" lines left")
	m.queue_free()
