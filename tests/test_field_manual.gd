extends "res://tests/test_case.gd"
## Increment 33: the Field Manual. Outpost 17's issue booklet, annotated by
## Sgt. Ada Vance: on slot 8 in a new game, opened with N (or its key, or
## fire with it held), chapters 1-4 open from the start and 5-7 the first
## time you need them, a tip the first time you do something it covers.
## Saved; kept when you die; a game from before it gets it all.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DT := 1.0 / 60.0

var BOOK: ItemDefinition = load("res://resources/items/field_manual.tres")


func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	return p


func _hud(p: PlayerController) -> HUD:
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(2)
	await get_tree().process_frame
	await get_tree().process_frame
	return hud


func _run(p: PlayerController, f: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _press(action: String) -> void:
	for down: bool in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()


# ---------------------------------------------------------------- the book

func test_a_new_game_has_the_manual_on_slot_8() -> void:
	var p := await _player()
	check(p.quick_bar.get_slot_item(7) == BOOK, "the Field Manual on slot 8")
	check(BOOK.holdable and BOOK.keep_on_death and BOOK.weight == 0.0, "holdable, kept when you die, weighs nothing")
	check(BOOK.icon != null and BOOK.world_model != null, "a picture and a model")
	var m := p.field_manual
	for id: StringName in [&"staying_alive", &"scavenging", &"making_things", &"guns_and_fighting"]:
		check(m.is_open(id), "%s open from the start" % id)
	for id: StringName in [&"building", &"settlements", &"getting_around"]:
		check(not m.is_open(id), "%s not yet" % id)


func test_the_text_names_real_keys() -> void:
	PlayerInput.ensure_bar_keys()
	check(InputMap.has_action(FieldManualScreen.ACTION) and FieldManualText.key_name(FieldManualScreen.ACTION) == "N", "N opens it")
	var named := FieldManualText.actions_named()
	check(named.size() >= 20, "the manual names %d keys" % named.size())
	for a in named:
		check(InputMap.has_action(a), "{%s} is a real action" % a)
		check(FieldManualText.key_name(a) != "?", "{%s} is bound (%s)" % [a, FieldManualText.key_name(a)])
	check(FieldManualText.key_name("fire") == "Left click", "fire is the left click")
	var last := 0
	for c: Dictionary in FieldManualText.CHAPTERS:
		var out := FieldManualText.render(c["text"])
		check(not out.contains("{") and not out.contains("(("), "chapter %d: every key and note drawn" % c["n"])
		check(out.contains(FieldManualText.PEN), "chapter %d: one of Vance's notes" % c["n"])
		check(int(c["page"]) > last, "chapter %d starts after the last (p. %d)" % [c["n"], c["page"]])
		last = c["page"]


# ---------------------------------------------------------------- reading it

func test_n_opens_it_at_a_chapter_and_closes_it() -> void:
	var p := await _player()
	var hud := await _hud(p)
	var screen := hud.field_manual_screen
	p.controlled_locally = true
	_press(FieldManualScreen.ACTION)
	await get_tree().process_frame
	check(screen.visible and p.player_input.ui_open, "N opens the manual")
	check(screen.chapter_id == &"staying_alive", "at chapter 1")
	var body := screen.find_child("Body", true, false) as RichTextLabel
	check(body.get_parsed_text().contains("Bandage"), "its text")
	var locked := screen.find_child("Chapter5", true, false) as Button
	check(locked.disabled and (locked.get_node("Page") as Label).text == "— —", "chapter 5 greyed in the contents")
	screen.turn(1)
	check(screen.chapter_id == &"scavenging", "turned to chapter 2")
	screen.show_chapter(&"guns_and_fighting")
	screen.turn(1)
	check(screen.chapter_id == &"guns_and_fighting", "no turning on to a chapter not reached yet")
	screen.show_chapter(&"building")
	check(screen.chapter_id == &"guns_and_fighting", "nor opening it from the contents")
	_press(FieldManualScreen.ACTION)
	await get_tree().process_frame
	check(not screen.visible and not p.player_input.ui_open, "N again closes it")
	check(p.field_manual.page == &"guns_and_fighting", "it remembers the page")
	p.controlled_locally = false
	hud.queue_free()


func test_its_key_or_fire_with_it_held_opens_it() -> void:
	var p := await _player()
	var hud := await _hud(p)
	var screen := hud.field_manual_screen
	var f := InputFrame.new()
	f.slot = 8
	await _run(p, f, 1)
	await _run(p, InputFrame.new(), 40)
	await get_tree().process_frame
	check(p.weapon_slots.held_item() == BOOK, "the manual in hand")
	check(screen.visible, "taking it in hand opens it")
	screen.close()
	var fire := InputFrame.new()
	fire.fire = true
	await _run(p, fire, 1)
	await get_tree().process_frame
	check(screen.visible, "fire with it held opens it again")
	screen.close()
	await _run(p, fire, 10)
	await get_tree().process_frame
	check(not screen.visible, "holding fire doesn't keep opening it")
	# The wheel passes over it
	await _run(p, InputFrame.new(), 2)
	var wheel := InputFrame.new()
	wheel.cycle = -1
	p.weapon_slots.equip_immediately(1)
	await _run(p, wheel, 1)
	check(p.weapon_slots.pending_slot != 8, "the wheel skips the manual")
	hud.queue_free()


# ---------------------------------------------------------------- chapters and tips

func test_chapters_open_when_you_first_need_them() -> void:
	var p := await _player()
	var hud := await _hud(p)
	var m := p.field_manual
	var tips := []
	m.tip.connect(func(id: StringName) -> void: tips.append(id))
	p.player_input.build_mode = true
	await wait_physics(20)
	p.player_input.build_mode = false
	check(m.is_open(&"building"), "build mode opens Building")
	check(tips.has(&"building"), "with a tip")
	await get_tree().process_frame
	check(hud.manual_tip.visible and hud.manual_tip.text() == "5 · Building, p. 18", "the tip card: %s" % hud.manual_tip.text())
	check(m.page_to_open() == &"building", "N opens it there for a while")
	m.saw(&"map")
	check(m.is_open(&"getting_around"), "the map opens Getting around")
	# Claiming a place opens Settlements
	var s := Settlement.new()
	s.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(s)
	s.is_claimed = true
	await wait_physics(20)
	check(m.is_open(&"settlements"), "a place you hold opens Settlements")
	s.free()
	hud.queue_free()


func test_a_tip_comes_once() -> void:
	var p := await _player()
	var m := p.field_manual
	var tips := []
	m.tip.connect(func(id: StringName) -> void: tips.append(id))
	p.health.apply_damage(DamageInfo.create(40.0, DamageInfo.Type.FALL))
	await wait_physics(20)
	check(tips == [&"staying_alive"], "hurt: Staying alive (%s)" % [tips])
	p.health.apply_damage(DamageInfo.create(10.0, DamageInfo.Type.FALL))
	await wait_physics(20)
	check(tips.size() == 1, "only once")
	m.saw(&"crafting")
	m.saw(&"crafting")
	check(tips == [&"staying_alive", &"making_things"], "the crafting screen: Making things, once")


# ---------------------------------------------------------------- kept

func test_saved_and_loaded() -> void:
	var p := await _player()
	var m := p.field_manual
	m.open_chapter(&"building")
	m.page = &"building"
	var data := JSON.parse_string(JSON.stringify(p.save_state())) as Dictionary
	check(data.get("manual") is Dictionary, "saved")
	var p2 := PLAYER_SCENE.instantiate() as PlayerController
	p2.controlled_locally = false
	p2.position = Vector3(4, 0.05, 0)
	add_child(p2)
	await wait_physics(3)
	p2.load_state(data)
	check(p2.field_manual.is_open(&"building") and not p2.field_manual.is_open(&"settlements"), "Building still open, Settlements not")
	check(p2.field_manual.page == &"building" and p2.field_manual.tipped.has(&"building"), "its page and tips")
	check(p2.quick_bar.count_of(BOOK.id) == 1, "one manual, not two")


func test_a_game_from_before_gets_the_manual_and_every_chapter() -> void:
	var p := await _player()
	p.load_state({"loadout": {"weapons": [{"id": "service_rifle", "magazine": 7, "attachments": []}], "equipped": 1}})
	check(p.quick_bar.get_slot_item(7) == BOOK, "the manual on slot 8")
	check(p.quick_bar.count_of(BOOK.id) == 1, "just the one")
	for id in FieldManualText.ids():
		check(p.field_manual.is_open(id), "%s open" % id)
	check(p.field_manual.tipped.size() == FieldManualText.ids().size(), "no tips for things you've done before")
	# Slot 8 taken: it goes on the first free slot
	var p2 := await _player()
	var bar: Array = []
	for i in 8:
		bar.append({"id": "pistol", "qty": 1, "slot": i})
	p2.load_state({"quick_bar": bar})
	check(p2.quick_bar.count_of(BOOK.id) == 0 and p2.inventory.count_of(BOOK.id) == 1, "a full bar: into the backpack")


func test_you_keep_it_when_you_die() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.request_move_to_backpack(7)
	check(p.inventory.count_of(BOOK.id) == 1 and p.quick_bar.count_of(BOOK.id) == 0, "the manual in the backpack")
	p.inventory.add_item(load("res://resources/items/wood.tres"), 5)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	var c := (zone.get_node("GameMode") as GameMode).get_dropped_gear(p)
	check(c != null and c.inventory.count_of(&"wood") == 5 and c.inventory.count_of(BOOK.id) == 0, "your wood in your gear, not the manual")
	check(p.inventory.count_of(BOOK.id) == 1, "you still have it")
	remove_child(zone)
	zone.free()


func test_it_fits_the_smallest_window() -> void:
	var p := await _player()
	var hud := await _hud(p)
	hud.field_manual_screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var book := hud.field_manual_screen.find_child("Book", true, false) as Control
	var size: Vector2 = (book.get_parent() as Control).size
	check(size.x <= UiScale.MIN_SPACE.x and size.y <= UiScale.MIN_SPACE.y, "the open book fits %s (%s)" % [UiScale.MIN_SPACE, size])
	hud.field_manual_screen.close()
	hud.queue_free()
