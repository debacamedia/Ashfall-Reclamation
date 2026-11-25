extends "res://tests/test_case.gd"
## Increment 33.1: names. Over a thousand first names for newcomers, so
## nobody turns up as "Drifter 7", with each newcomer's body suiting their
## name; old Drifters get a real name that suits how they look. And your own
## name, written in the Field Manual, kept in saves, for anything that will
## speak to you.

const SETTLER_SCENE := preload("res://scenes/npcs/settler.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func test_a_thousand_names() -> void:
	var all := SettlerNames.all()
	var unique := {}
	for n: String in all:
		unique[n] = true
	check(all.size() >= 1000, "%d names" % all.size())
	check(unique.size() == all.size(), "no name twice")
	for reserved in ["Ada", "Maya", "Tomas", "Jeb"]:
		check(not unique.has(reserved), "%s is kept for the story" % reserved)
	var bad := all.filter(func(n: String) -> bool: return n.length() < 2 or n.length() > 12 or n[0] != n[0].to_upper() or n.contains(" "))
	check(bad.is_empty(), "every one a single capitalised name (%s)" % [bad.slice(0, 5)])
	check(SettlerNames.FEMALE.size() > 400 and SettlerNames.MALE.size() > 400 and SettlerNames.EITHER.size() > 40, "women's, men's and anyone's")
	check(SettlerNames.sex_of("Rosemary") == 1 and SettlerNames.sex_of("Gideon") == 0 and SettlerNames.sex_of("Rowan") in [0, -1], "who a name usually belongs to")
	var used := {}
	for i in 20:
		used[SettlerNames.pick(used)] = true
	check(used.size() == 20 and not used.has(""), "twenty newcomers, twenty names")


func test_newcomers_have_real_names_and_bodies_that_suit_them() -> void:
	var zone := await load_zone()
	var st := zone.get_node("AshCreekFarms/Settlement") as Settlement
	var names := []
	var ok := true
	for i in 30:
		var s := st.spawn_newcomer()
		names.append(s.settler_name)
		var want := SettlerNames.sex_of(s.settler_name)
		if want >= 0 and s.sex != want:
			ok = false
	await wait_physics(2)
	check(names.all(func(n: String) -> bool: return not n.begins_with("Drifter")), "thirty newcomers, no Drifters (%s…)" % [names.slice(0, 4)])
	var unique := {}
	for n: String in names:
		unique[n] = true
	check(unique.size() == names.size(), "all different")
	check(ok, "each one's body follows their name")
	var woman: Settler = null
	for s in get_tree().get_nodes_in_group("settlers"):
		if (s as Settler).sex == 1 and (s as Settler).body != null:
			woman = s
			break
	check(woman != null and woman.body.female, "a woman's name, a woman's body")
	var data := woman.save_state()
	check(data.get("sex") == 1, "saved")
	remove_child(zone)
	zone.free()


func test_old_drifters_get_a_name_that_suits_them() -> void:
	var s := SETTLER_SCENE.instantiate() as Settler
	add_child(s)
	await wait_physics(1)
	var was_female := HumanBody.female_by_seed(hash("Drifter 7"))
	s.load_state({"name": "Drifter 7", "look": 0, "role": Settler.Role.TAILOR})
	check(not s.settler_name.begins_with("Drifter") and s.settler_name != "", "renamed: %s" % s.settler_name)
	check(s.look_seed == hash("Drifter 7"), "looking as they did")
	check(s.body == null or s.body.female == was_female, "the same body")
	var sex := SettlerNames.sex_of(s.settler_name)
	check(sex == -1 or sex == (1 if was_female else 0), "a name that suits it")
	check(s.role == Settler.Role.TAILOR, "a Tailor stays a Tailor when loaded (it used to be dropped)")
	s.load_state({"name": "Rosa", "look": 5})
	check(s.settler_name == "Rosa", "a real name stays as it is")
	s.queue_free()


# ---------------------------------------------------------------- your name

func test_your_name() -> void:
	check(PlayerController.clean_name("  Gabe   the [b]Bold[/b]  ") == "Gabe the bBold/b", "cleaned: %s" % PlayerController.clean_name("  Gabe   the [b]Bold[/b]  "))
	check(PlayerController.clean_name("x".repeat(40)).length() == PlayerController.NAME_MAX, "at most %d letters" % PlayerController.NAME_MAX)
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	check(p.player_name == "" and p.call_name() == "Survivor", "nameless, you're Survivor")
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(2)
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := hud.field_manual_screen
	screen.open()
	var field := screen.name_field
	check(field != null and field.is_visible_in_tree() and field.text == "" and field.placeholder_text != "", "a line on the cover to write it on")
	field.grab_focus()
	field.text = "Gabe DeBaca"
	field.text_submitted.emit(field.text)
	check(p.player_name == "Gabe DeBaca" and p.call_name() == "Gabe DeBaca", "written in")
	# Typing doesn't open other windows
	p.controlled_locally = true
	field.grab_focus()
	for code in [KEY_I, KEY_M, KEY_N]:
		var k := InputEventKey.new()
		k.physical_keycode = code
		k.keycode = code
		k.pressed = true
		Input.parse_input_event(k)
		Input.flush_buffered_events()
		k = k.duplicate()
		k.pressed = false
		Input.parse_input_event(k)
		Input.flush_buffered_events()
	await get_tree().process_frame
	check(screen.visible and not hud.inventory_screen.visible and not hud.map_screen.visible, "typing I, M or N writes letters: no window opens or closes")
	field.release_focus()
	screen.close()
	p.controlled_locally = false
	var data := JSON.parse_string(JSON.stringify(p.save_state())) as Dictionary
	var p2 := PLAYER_SCENE.instantiate() as PlayerController
	p2.controlled_locally = false
	p2.position = Vector3(4, 0.05, 0)
	add_child(p2)
	await wait_physics(3)
	p2.load_state(data)
	check(p2.player_name == p.player_name, "saved and loaded")
	p2.load_state({})
	check(p2.player_name == "", "a game from before: no name yet")
	hud.queue_free()
