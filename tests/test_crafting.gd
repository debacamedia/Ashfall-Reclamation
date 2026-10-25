extends "res://tests/test_case.gd"
## Increment 10: recipes, hand crafting, benches, the crafting screen,
## salvage piles and new materials.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WORKBENCH := preload("res://scenes/world/stations/workbench.tscn")
const PALLET := preload("res://scenes/world/salvage/wood_pallet.tscn")
const DT := 1.0 / 60.0

var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")
var BANDAGE_R: RecipeDefinition = load("res://resources/recipes/bandage.tres")
var PLATE_R: RecipeDefinition = load("res://resources/recipes/metal_plate.tres")
var PLANK_R: RecipeDefinition = load("res://resources/recipes/wood_plank.tres")


func _player(at := Vector3(0, 0.05, 0)) -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = at
	add_child(p)
	return p


func _run(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _look_at(p: PlayerController, point: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


## Player facing a workbench 1.5 m away, bench opened with E.
func _at_bench() -> Array:
	var p := _player()
	var bench := WORKBENCH.instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.6)
	add_child(bench)
	await _run(p, 3)
	_look_at(p, bench.get_focus_point())
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 2)
	await _run(p, 1, e)
	await _run(p, 1)
	return [p, bench]


# ---------------------------------------------------------------- data

func test_recipes_are_valid() -> void:
	var recipes := RecipeDatabase.all_recipes()
	check(recipes.size() >= 13, "13+ recipes (%d)" % recipes.size())
	var stations := {}
	for r in recipes:
		check(r.output != null and ItemDatabase.get_item(r.output.id) == r.output, "%s: registered output" % r.id)
		check(not r.inputs.is_empty() and r.output_quantity > 0 and r.craft_time > 0.0, "%s: inputs, quantity, time" % r.id)
		for item: ItemDefinition in r.inputs:
			check(ItemDatabase.get_item(item.id) == item and r.inputs[item] > 0, "%s: input %s" % [r.id, item.id])
			check(item != r.output, "%s: doesn't consume its own output" % r.id)
		check(RecipeDatabase.get_recipe(r.id) == r, "%s found by id" % r.id)
		stations[r.station] = true
	check(stations.size() == 3, "recipes for hand, workbench and weapons bench")
	for id in ["wood", "chemicals", "wood_plank", "metal_plate", "metal_pipe", "spring", "gunpowder", "bandage"]:
		var item := ItemDatabase.get_item(StringName(id))
		check(item != null and item.icon != null and item.world_model != null, "%s: item with icon and model" % id)
	for id in ["pistol_ammo", "shotgun_shells", "rifle_ammo", "rifle_308", "medkit", "gunpowder"]:
		check(not RecipeDatabase.recipes_for(ItemDatabase.get_item(StringName(id))).is_empty(), "%s can be crafted" % id)


func test_can_exchange_changes_nothing() -> void:
	var p := _player()
	await _run(p, 2)
	var inv := p.inventory
	inv.add_item(CLOTH, 2)
	var before := str(inv.to_data())
	var signals := [0]
	inv.contents_changed.connect(func(_s: PackedInt32Array) -> void: signals[0] += 1)
	var bandage := ItemDatabase.get_item(&"bandage")
	var remove: Dictionary[ItemDefinition, int] = {CLOTH: 2}
	check(inv.can_exchange(remove, bandage, 1), "2 cloth → bandage fits")
	check(str(inv.to_data()) == before and signals[0] == 0, "no change, no signals")
	inv.max_weight = 2.4
	check(not inv.can_exchange({}, FUEL, 1), "a 9 kg fuel can doesn't fit under 2.4 kg")


# ---------------------------------------------------------------- hand crafting

func test_hand_crafting_bandages() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(CLOTH, 5)
	var done := []
	p.crafting_finished.connect(func(r: RecipeDefinition) -> void: done.append(r.id))
	var received := []
	p.inventory.item_received.connect(func(i: ItemDefinition, q: int) -> void: received.append([i.id, q]))
	check(p.request_craft(BANDAGE_R, 2), "crafting started")
	check(p.is_crafting() and p.get_crafting_count() == 2, "2 queued")
	await _run(p, 60)
	check(p.inventory.count_of(&"bandage") == 0, "not done before 2 s")
	await _run(p, 65)
	check(p.inventory.count_of(&"bandage") == 1 and p.inventory.count_of(&"cloth") == 3, "first bandage, 2 cloth used")
	await _run(p, 125)
	check(p.inventory.count_of(&"bandage") == 2 and p.inventory.count_of(&"cloth") == 1, "second bandage")
	check(not p.is_crafting() and done == [&"bandage", &"bandage"], "queue finished")
	check(received.has([&"bandage", 1]), "item_received for the HUD notice")


func test_refusal_reasons() -> void:
	var p := _player()
	await _run(p, 2)
	var reasons := []
	p.craft_refused.connect(func(r: String) -> void: reasons.append(r))
	check(not p.request_craft(BANDAGE_R) and reasons.back() == "Missing 2 Cloth", "missing: %s" % reasons.back())
	p.inventory.add_item(SCRAP, 5)
	check(not p.request_craft(PLATE_R) and reasons.back() == "Needs a Workbench", "bench: %s" % reasons.back())
	p.inventory.add_item(WOOD, 1)
	p.inventory.max_weight = 0.0
	p.inventory.add_item(CLOTH, CLOTH.max_stack * p.inventory.get_free_slot_count())
	check(p.inventory.get_free_slot_count() == 0, "bags full")
	check(p.craft_refusal_reason(PLANK_R) == "", "planks fit: using up the wood frees its slot")
	p.inventory.add_item(WOOD, 1)
	var wood_left := p.inventory.count_of(&"wood")
	check(wood_left == 2, "2 wood")
	check(p.craft_refusal_reason(PLANK_R) == "Inventory full", "no free slot for planks: %s" % p.craft_refusal_reason(PLANK_R))
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	check(p.craft_refusal_reason(BANDAGE_R) == "Can't do that now", "dead")


func test_queue_stops_when_materials_run_out_and_cancel() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(CLOTH, 3)
	p.request_craft(BANDAGE_R, 5)
	await _run(p, 140)
	check(p.inventory.count_of(&"bandage") == 1 and not p.is_crafting(), "made 1, stopped when only 1 cloth left")
	p.inventory.add_item(CLOTH, 3)
	p.request_craft(BANDAGE_R, 1)
	await _run(p, 30)
	p.cancel_crafting()
	await _run(p, 120)
	check(p.inventory.count_of(&"cloth") == 4 and p.inventory.count_of(&"bandage") == 1, "cancel consumes nothing")


func test_materials_checked_again_when_done() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(CLOTH, 2)
	var reasons := []
	p.craft_refused.connect(func(r: String) -> void: reasons.append(r))
	p.request_craft(BANDAGE_R)
	await _run(p, 30)
	p.inventory.remove_item(&"cloth", 1)  # dropped / used elsewhere mid-craft
	await _run(p, 100)
	check(p.inventory.count_of(&"bandage") == 0 and reasons == ["Missing 1 Cloth"], "nothing made, refusal: %s" % [reasons])


# ---------------------------------------------------------------- benches

func test_bench_crafting_and_walking_away() -> void:
	var r: Array = await _at_bench()
	var p: PlayerController = r[0]
	check(p.current_station == r[1], "E opened the workbench")
	check(p.get_crafting_station() == RecipeDefinition.Station.WORKBENCH, "crafting at a workbench")
	p.inventory.add_item(SCRAP, 6)
	check(p.request_craft(PLATE_R, 2), "metal plate allowed here")
	await _run(p, 160)
	check(p.inventory.count_of(&"metal_plate") == 1, "one plate after 2.5 s")
	p.global_position = Vector3(0, 0.05, 8)
	await _run(p, 2)
	check(p.current_station == null and not p.is_crafting(), "walking away closes the bench and stops bench work")
	check(p.inventory.count_of(&"scrap_metal") == 3, "only the finished plate used scrap")
	p.inventory.add_item(CLOTH, 2)
	p.request_craft(BANDAGE_R)
	await _run(p, 130)
	check(p.inventory.count_of(&"bandage") == 1, "hand recipes work away from benches")


func test_weapons_bench_recipes_need_the_weapons_bench() -> void:
	var r: Array = await _at_bench()
	var p: PlayerController = r[0]
	var rifle_ammo: RecipeDefinition = load("res://resources/recipes/rifle_ammo.tres")
	p.inventory.add_item(SCRAP, 4)
	p.inventory.add_item(ItemDatabase.get_item(&"gunpowder"), 4)
	check(p.craft_refusal_reason(rifle_ammo) == "Needs a Weapons Bench", "not at a workbench")
	check(p.craft_refusal_reason(BANDAGE_R).begins_with("Missing"), "hand recipes are offered at benches too")


# ---------------------------------------------------------------- screen

func _hud(p: PlayerController) -> HUD:
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	return hud


func test_screen_by_hand() -> void:
	var p := _player()
	var hud := _hud(p)
	await _run(p, 3)
	p.inventory.add_item(CLOTH, 4)
	var screen := hud.crafting_screen
	screen.open()
	await get_tree().process_frame
	check(screen.visible and p.player_input.ui_open, "open, gameplay paused")
	check((screen.get_node("%CraftTitle") as Label).text == "CRAFTING", "title")
	var texts := (screen.get_node("%RecipeList") as VBoxContainer).get_children().map(func(n: Node) -> String: return n.text if n is Label else "")
	check(texts.has("AT OTHER BENCHES"), "bench recipes listed for discovery")
	screen.select(BANDAGE_R)
	await get_tree().process_frame
	check((screen.get_node("%RecipeIngredients") as Label).text.begins_with("Cloth  4 / 2"), "ingredients: %s" % (screen.get_node("%RecipeIngredients") as Label).text)
	check(not (screen.get_node("%CraftButton") as Button).disabled, "Craft enabled")
	(screen.get_node("%CraftButton") as Button).pressed.emit()
	check(p.is_crafting(), "Craft queued it")
	await _run(p, 30)
	await get_tree().process_frame
	check((screen.get_node("%CraftProgress") as ProgressBar).visible and (screen.get_node("%CraftQueue") as Label).text.begins_with("Crafting Bandage"), "progress shown")
	screen.select(PLATE_R)
	await get_tree().process_frame
	check((screen.get_node("%RecipeStatus") as Label).text == "Needs a Workbench" and (screen.get_node("%CraftButton") as Button).disabled, "bench recipe explained and disabled")
	screen.close()
	await _run(p, 2)
	await get_tree().process_frame
	check(not screen.visible and not p.player_input.ui_open, "closed")
	check((hud.get_node("%UseLabel") as Label).visible and (hud.get_node("%UseLabel") as Label).text.begins_with("Crafting Bandage"), "HUD shows hand crafting with the screen closed")


func test_screen_at_bench_and_close_keys() -> void:
	var p := _player()
	var hud := _hud(p)
	var bench := WORKBENCH.instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.6)
	add_child(bench)
	await _run(p, 3)
	_look_at(p, bench.get_focus_point())
	await _run(p, 2)
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 1, e)
	await get_tree().process_frame
	var screen := hud.crafting_screen
	check(screen.visible and (screen.get_node("%CraftTitle") as Label).text == "WORKBENCH", "bench opens the screen")
	for action in ["interact", "inventory", "pause"]:
		if not screen.visible:
			bench._perform(p)
			await get_tree().process_frame
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)
		await wait_physics(2)
		check(not screen.visible and p.current_station == null, "%s closes it" % action)
		check(not hud.inventory_screen.visible, "and doesn't open the inventory")
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
		await wait_physics(1)


# ---------------------------------------------------------------- salvage, medical

func test_breaking_down_a_pallet() -> void:
	var p := _player()
	var pallet := PALLET.instantiate() as SalvagePile
	pallet.position = Vector3(0, 0, -1.5)
	add_child(pallet)
	await _run(p, 3)
	_look_at(p, pallet.get_focus_point())
	await _run(p, 2)
	check(p.interactor.focused == pallet, "pallet focused")
	check(pallet.get_prompt(p) == "Break down Pallet  (Wood ×3)", "prompt: %s" % pallet.get_prompt(p))
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 30, e)
	check(p.inventory.count_of(&"wood") == 0, "a short hold does nothing")
	await _run(p, 70, e)
	await _run(p, 2)
	check(p.inventory.count_of(&"wood") == 3 and not is_instance_valid(pallet), "3 wood, pallet gone")


func test_pallet_keeps_what_doesnt_fit_and_saves() -> void:
	var p := _player()
	await _run(p, 2)
	var pallet := PALLET.instantiate() as SalvagePile
	pallet.position = Vector3(0, 0, -1.5)
	add_child(pallet)
	await _run(p, 2)
	# Leave room for exactly 1 kg (one wood)
	p.inventory.max_weight = p.inventory.get_total_weight() + 1.0
	pallet._perform(p)
	check(p.inventory.count_of(&"wood") == 1 and is_instance_valid(pallet) and pallet.remaining.values() == [2], "1 taken, 2 left in the pallet")
	var data := JSON.parse_string(JSON.stringify(pallet.save_state())) as Dictionary
	var copy := PALLET.instantiate() as SalvagePile
	add_child(copy)
	copy.load_state(data)
	check(copy.remaining.values() == [2], "remaining saved")
	check(copy.is_save_removable(), "removable when used up")


func test_bandage_heals_20() -> void:
	var p := _player()
	await _run(p, 2)
	var bandage := ItemDatabase.get_item(&"bandage")
	p.inventory.add_item(bandage, 1)
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	check(p.request_use_item(bandage), "bandage used")
	await _run(p, 70)
	check_near(p.health.current_health, 70.0, 0.01, "healed 20 in 1 s")
