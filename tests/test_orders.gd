extends "res://tests/test_case.gd"
## Increment 34: the story's orders (The Last Order, Act 1). Short tasks in
## chapters, one chapter at a time, each ticked off when the game sees it
## done (anything already done counts). The order you track is on screen
## and on the compass. Story or Free Play at New game; a game from before
## carries on in Story with Act 1 done as far as it's got. The radio at
## Northwatch is the act's last order.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

var PIPE_PISTOL: RecipeDefinition = load("res://resources/recipes/craft_pipe_pistol.tres")
var ROUNDS: RecipeDefinition = load("res://resources/recipes/pistol_ammo.tres")
var BANDAGE: ItemDefinition = load("res://resources/items/bandage.tres")
var MACHETE: ItemDefinition = load("res://resources/items/weapons/machete_item.tres")


func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	return p


## Lets the story look (it checks twice a second).
func _tick() -> void:
	await get_tree().create_timer(StoryProgress.CHECK_EVERY + 0.15).timeout
	await get_tree().process_frame


func _container(n: int) -> SalvageContainer:
	var c := (load("res://scenes/world/containers/supply_crate.tscn") as PackedScene).instantiate() as SalvageContainer
	c.name = "Crate%d" % n
	add_child(c)
	c.position = Vector3(10 + n * 2, 0, 10)
	return c


func _raider() -> Node3D:
	var r := Node3D.new()
	add_child(r)
	return r


func _shot(p: PlayerController) -> DamageInfo:
	var info := DamageInfo.create(50.0, DamageInfo.Type.BALLISTIC)
	info.source = p
	return info


# ---------------------------------------------------------------- the orders

func test_the_orders_from_the_proofs() -> void:
	check(Orders.ACT_TITLE == "Act 1 · The Last Order", "Act 1 · The Last Order")
	var sizes := []
	for c: Dictionary in Orders.CHAPTERS:
		sizes.append((c["orders"] as Array).size())
		check(String(c["note"]).ends_with("— A.V."), "%s: Vance's note in the margin" % c["title"])
	check(sizes == [4, 4, 4, 6, 5, 5], "a prologue and five chapters: %s" % [sizes])
	var ids := Orders.all_ids()
	var unique := {}
	for id in ids:
		unique[id] = true
	check(ids.size() == 28 and unique.size() == 28, "28 orders, each its own (%d)" % ids.size())
	check(Orders.chapter_of(&"radio")["id"] == &"northwatch" and Orders.order(&"radio")["where"] == "NorthwatchOutpost/StoryRadio", "the radio's the last")
	for c: Dictionary in Orders.CHAPTERS:
		for o: Dictionary in c["orders"]:
			var text := String(o["text"])
			check(not text.contains("reward"), "no item rewards: %s" % text)


func test_orders_tick_off_one_chapter_at_a_time() -> void:
	var p := await _player()
	var st := p.story
	check(st != null and st.is_story(), "a player's in Story unless it's Free Play")
	# A player starts with the manual and a machete: those count straight away
	check(st.is_done(&"take_manual") and st.is_done(&"armed") and not st.is_done(&"wake"), "anything already done counts")
	var done := []
	var chapters := []
	st.order_done.connect(func(id: StringName) -> void: done.append(id))
	st.chapter_done.connect(func(id: StringName) -> void: chapters.append(id))
	check(st.current_chapter()["id"] == &"prologue", "the Prologue first")
	# Chapter 1's work done early waits its turn, then counts
	p.crafting_finished.emit(PIPE_PISTOL)
	await _tick()
	check(not st.is_done(&"pipe_pistol"), "Chapter 1's order not ticked while in the Prologue")
	st._flag(&"in_barracks")
	await _tick()
	check(st.is_done(&"wake"), "woke")
	check(st.tracked_order()["id"] == &"search", "on to: %s" % st.tracked_order().get("text", ""))
	for i in 3:
		p.container_opened.emit(_container(i))
		await get_tree().process_frame
		if i == 1:
			check(st.progress_of(Orders.order(&"search")) == [2, 3], "two of three searched")
	await _tick()
	check(chapters == [&"prologue"], "the Prologue's done: %s" % [chapters])
	check(st.current_chapter()["id"] == &"first_light", "Chapter 1 · First Light")
	check(st.is_done(&"pipe_pistol"), "the pipe pistol made earlier counts now")
	p.crafting_finished.emit(ROUNDS)
	StoryProgress.on_raider_killed(_raider(), _shot(p))
	p.item_use_finished.emit(BANDAGE)
	await _tick()
	check(chapters == [&"prologue", &"first_light"], "First Light done: %s" % [chapters])
	check(st.has_earned(&"first_light") and st.has_earned(&"first_blood") and st.has_earned(&"pipe_dream"), "and its achievements: %s" % [st.earned.keys()])
	check(st.current_chapter()["id"] == &"crossing_over", "Chapter 2 · Crossing Over")
	check(done == [&"wake", &"search", &"pipe_pistol", &"rounds", &"first_kill", &"bandage"], "each said once: %s" % [done])


func test_tracking_an_order() -> void:
	var p := await _player()
	var st := p.story
	await _tick()
	var changed := [0]
	st.tracked_changed.connect(func() -> void: changed[0] += 1)
	check(st.tracked_order()["id"] == &"wake", "the first left, unless you pick one")
	st.track(&"search")
	check(st.tracked_order()["id"] == &"search" and changed[0] == 1, "track one from the manual")
	st.track(&"radio")
	check(st.tracked_order()["id"] == &"search", "not one from a later chapter")
	st.track(&"take_manual")
	check(st.tracked_order()["id"] == &"search", "nor one that's done")
	for i in 3:
		p.container_opened.emit(_container(i))
	await _tick()
	check(st.is_done(&"search") and st.tracked_order()["id"] == &"wake", "done: back to the first left")


# ---------------------------------------------------------------- on screen

func test_the_tracker_and_the_manual_page() -> void:
	var p := await _player()
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(2)
	await _tick()
	var t := hud.order_tracker
	check(t != null and t.visible, "top left: the order you're on")
	var chapter := (t.find_child("Chapter", true, false) as Label).text
	var order := (t.find_child("Order", true, false) as Label).text
	check(chapter == "PROLOGUE · HOLD AND WAIT", "its chapter: %s" % chapter)
	check(order == "Wake in Outpost 17's barracks", "its order: %s" % order)
	p.story.track(&"search")
	await get_tree().process_frame
	await get_tree().process_frame
	order = (t.find_child("Order", true, false) as Label).text
	check(order.ends_with("0 / 3"), "with how far along: %s" % order)
	var rest := (t.find_child("Rest", true, false) as Label).text
	check(rest.contains("of 4 done in this chapter") and rest.contains("N for your orders"), "and the rest: %s" % rest)
	# The manual's Orders page
	var text := FieldManualScreen.orders_text(p.story)
	check(text.contains("Command says hold") and text.contains("[url=track:wake]") and text.contains("[s]Take the Field Manual"), "the manual lists this chapter's orders, done ones struck out, the rest to track")
	check(not text.contains("Answer the radio"), "not the chapters to come")
	hud.field_manual_screen._on_link("track:wake")
	check(p.story.tracked_order()["id"] == &"wake", "click one to track it")
	# Hidden with a window open, and in Free Play
	p.story.mode = StoryProgress.Mode.FREE_PLAY
	await get_tree().process_frame
	await get_tree().process_frame
	check(not t.visible, "no orders in Free Play")


# ---------------------------------------------------------------- in the zone

func test_a_new_story_game() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var bar_had := p.quick_bar.count_of(&"field_manual")
	p.story.begin(StoryProgress.Mode.STORY)
	await wait_physics(5)
	var barracks := zone.get_node("Outpost17/Buildings/Barracks") as Node3D
	var local := barracks.to_local(p.global_position)
	check(absf(local.x) < 5.5 and absf(local.z) < 4.0, "you wake in Outpost 17's barracks (%s)" % local)
	var locker := zone.get_node("Outpost17/SalvageContainers/VanceFootlocker") as SalvageContainer
	check(bar_had == 1 and p.quick_bar.count_of(&"field_manual") == 0 and p.inventory.count_of(&"field_manual") == 0, "the manual's not on you")
	check(locker.inventory.count_of(&"field_manual") == 1, "it's in Sgt. Vance's footlocker")
	await _tick()
	check(p.story.is_done(&"wake"), "Wake: done")
	check(p.story.tracked_order()["id"] == &"take_manual", "next: the manual")
	var mark := p.story.get_node_or_null("OrderMarker") as Landmark
	check(mark != null and mark.global_position.distance_to(locker.global_position) < 0.1, "a compass marker on the footlocker")
	check(mark != null and mark.get_compass_name() == "Order: Take the Field Manual from Sgt. Vance's footlocker" and mark.radius == 0.0, "named for the order, and not a place")
	check(Landmark.at(get_tree(), locker.global_position) == null or Landmark.at(get_tree(), locker.global_position).radius > 0.0, "it doesn't count as a place")
	# Take it
	var slot := -1
	for i in locker.inventory.slot_count:
		if locker.inventory.get_slot_item(i) != null and locker.inventory.get_slot_item(i).id == &"field_manual":
			slot = i
	locker.inventory.take_from_slot(slot, 1)
	p.quick_bar.add_item(ItemDatabase.get_item(&"field_manual"), 1)
	await _tick()
	check(p.story.is_done(&"take_manual"), "taken: done")
	await _tick()
	check(p.story.tracked_order()["id"] != &"take_manual" and (p.story.get_node_or_null("OrderMarker") == null or p.story.tracked_order().has("where")),
		"the marker goes with an order that has nowhere to point")


func test_free_play() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var at := p.global_position
	p.story.begin(StoryProgress.Mode.FREE_PLAY)
	await _tick()
	check(not p.story.is_story() and p.story.current_chapter().is_empty(), "no orders")
	check(p.global_position.distance_to(at) < 0.5, "you start where the zone puts you")
	for id in FieldManualText.ids():
		check(p.field_manual.is_open(id), "%s open" % id)
	check(p.quick_bar.count_of(&"field_manual") == 1, "the manual's on you")
	check(p.story.get_node_or_null("OrderMarker") == null, "no order marker")
	check(not p.story.can_earn(&"roots") and p.story.can_earn(&"first_blood"), "no story achievements; the rest count")
	var radio := zone.get_node("NorthwatchOutpost/StoryRadio") as StoryRadio
	check(not radio.can_interact(p) and radio.get_block_reason(p) == "Only static on every channel", "the radio's just static")


func test_a_game_from_before_carries_on() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var earned := []
	p.story.achievement_earned.connect(func(id: StringName) -> void: earned.append(id))
	var said := []
	p.story.order_done.connect(func(id: StringName) -> void: said.append(id))
	# Ash Creek held, its pump fixed: Chapter 3 under way
	var farm := zone.get_node("AshCreekFarms/Settlement") as Settlement
	farm.is_claimed = true
	farm.pump_level = 1
	p.load_state({"loadout": {"weapons": [{"id": "service_rifle", "magazine": 7, "attachments": []}], "equipped": 1}})
	check(p.story.is_story(), "in Story")
	await _tick()
	for id: StringName in [&"wake", &"take_manual", &"search", &"pipe_pistol", &"first_kill", &"reach_haldens", &"tomas", &"clear_haldens",
			&"clear_ash", &"claim_ash", &"pump"]:
		check(p.story.is_done(id), "%s counted done" % id)
	check(p.story.current_chapter()["id"] == &"roots" and not p.story.is_done(&"farmer"), "on Chapter 3 · Roots, as far as it's got")
	check(p.story.has_earned(&"roots") and p.story.has_earned(&"running_water"), "achievements it shows: %s" % [p.story.earned.keys()])
	check(earned.is_empty() and said.is_empty(), "caught up quietly (no toasts, no ticks): %s %s" % [earned, said])
	# A game from before with nothing claimed starts at the beginning (but awake)
	var p2 := PLAYER_SCENE.instantiate() as PlayerController
	p2.controlled_locally = false
	farm.is_claimed = false
	farm.pump_level = 0
	zone.add_child(p2)
	p2.global_position = p.global_position + Vector3(4, 0, 0)
	p2.load_state({})
	await _tick()
	check(p2.story.is_done(&"wake") and p2.story.current_chapter()["id"] == &"prologue", "nothing held: the Prologue, awake (%s, %s)" % [p2.story.done.keys(), p2.story.current_chapter().get("id")])


func test_the_radio() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var radio := zone.get_node_or_null("NorthwatchOutpost/StoryRadio") as StoryRadio
	check(radio != null, "a radio in Northwatch's command post")
	if radio == null:
		return
	var comms := zone.get_node("NorthwatchOutpost/Props/CommsRadio") as Node3D
	check(radio.global_position.distance_to(comms.global_position) < 1.5, "on the comms radio")
	check(radio.get_block_reason(p) == "Only static. Hold Northwatch, and all three places, first", "static until the rest of Chapter 5's done")
	for id in Orders.all_ids():
		if id != &"radio":
			p.story.done[id] = true
	check(radio.can_interact(p) and radio.get_prompt(p) == "Answer the radio", "then: Answer the radio")
	var heard := []
	p.story.message.connect(func(t: String) -> void: heard.append(t))
	var finished := [false]
	p.story.act_done.connect(func() -> void: finished[0] = true)
	p.set_player_name("Gabe")
	radio._perform(p)
	check(heard.size() == 1 and heard[0].contains("Gabe, is that you?") and heard[0].contains("Report to Scorch"), "Command answers: %s" % [heard])
	await _tick()
	check(p.story.is_done(&"radio") and finished[0] and p.story.act_finished(), "Act 1 done")
	check(p.story.has_earned(&"northwatch_stands"), "Northwatch Stands")
	check(radio.get_block_reason(p) == "Only static now", "after that, static")


# ---------------------------------------------------------------- saves

func test_saved_and_loaded() -> void:
	var p := await _player()
	p.story._flag(&"in_barracks")
	p.story.earn(&"first_blood")
	await _tick()
	p.story.track(&"search")
	var data := p.save_state()
	check(data.has("story"), "saved with the game")
	var copy: Variant = JSON.parse_string(JSON.stringify(data))
	var p2 := await _player()
	p2.load_state(copy)
	check(p2.story.is_story() and p2.story.is_done(&"wake") and p2.story.is_done(&"take_manual"), "orders done")
	check(p2.story.tracked_order()["id"] == &"search", "the one you track")
	check(p2.story.has_earned(&"first_blood"), "achievements")
	check(not p2.story._catch_up, "not taken for a game from before")
	p.story.begin(StoryProgress.Mode.FREE_PLAY)
	var p3 := await _player()
	p3.load_state(JSON.parse_string(JSON.stringify(p.save_state())))
	check(not p3.story.is_story(), "Free Play stays Free Play")
