extends "res://tests/test_case.gd"
## Increment 21: the player gets hungry. About 20 minutes of play between
## meals (full to empty in 40), sprinting three times as fast; hungry, no
## sprinting; starving, slower and losing health down to 25, never dying of
## it. Fresh Vegetables, canned food from loot, and stew cooked on a stove
## (or a workbench). J eats the best thing you carry.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WORKBENCH := preload("res://scenes/world/stations/workbench.tscn")
const STOVE := preload("res://scenes/world/stations/cooking_stove.tscn")
const DT := 1.0 / 60.0

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var BEANS: ItemDefinition = load("res://resources/items/canned_beans.tres")
var PEACHES: ItemDefinition = load("res://resources/items/canned_peaches.tres")
var STEW: ItemDefinition = load("res://resources/items/vegetable_stew.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var STEW_R: RecipeDefinition = load("res://resources/recipes/vegetable_stew.tres")


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


# ---------------------------------------------------------------- hunger

func test_hunger_drains_faster_when_you_sprint() -> void:
	var p := _player()
	await _run(p, 2)
	var h := p.hunger
	check(h != null and is_equal_approx(h.food, 100.0) and h.stage == PlayerHunger.Stage.FED, "you start full")
	h.tick(600.0, false, p.health)
	check_near(h.food, 75.0, 0.01, "10 min of play, walking: a quarter gone")
	h.tick(200.0, true, p.health)
	check_near(h.food, 50.0, 0.01, "200 s sprinting burns as much as 600 s walking")
	h.set_food(100.0)
	h.tick(1200.0, false, p.health)
	check_near(h.food, 50.0, 0.01, "20 min: half gone (time to eat)")
	check(h.stage == PlayerHunger.Stage.PECKISH or is_equal_approx(h.food, 50.0), "about now you're peckish")
	h.tick(1300.0, false, p.health)
	check(h.food == 0.0 and h.stage == PlayerHunger.Stage.STARVING, "40 min without eating: starving")


func test_hungry_you_cant_sprint_starving_youre_slower() -> void:
	var p := _player()
	await _run(p, 2)
	var said := []
	p.hunger.stage_changed.connect(func(s: PlayerHunger.Stage) -> void: said.append(s))
	var sprint := InputFrame.new()
	sprint.move = Vector2(0, -1)
	sprint.sprint = true
	await _run(p, 40, sprint)
	check(p.movement_state == PlayerController.MovementState.SPRINTING, "fed: you sprint")
	p.hunger.set_food(40.0)
	check(said == [PlayerHunger.Stage.PECKISH], "peckish at under half")
	await _run(p, 10, sprint)
	check(p.movement_state == PlayerController.MovementState.SPRINTING, "peckish: you still sprint")
	p.hunger.set_food(20.0)
	await _run(p, 30, sprint)
	check(p.movement_state != PlayerController.MovementState.SPRINTING, "hungry: too weak to sprint")
	var walk := Vector2(p.velocity.x, p.velocity.z).length()
	check_near(walk, p.walk_speed, 0.3, "you walk instead (%.2f m/s)" % walk)
	p.hunger.set_food(0.0)
	await _run(p, 30, sprint)
	var slow := Vector2(p.velocity.x, p.velocity.z).length()
	check_near(slow, p.walk_speed * 0.75, 0.3, "starving: slower (%.2f m/s)" % slow)
	check(said == [PlayerHunger.Stage.PECKISH, PlayerHunger.Stage.HUNGRY, PlayerHunger.Stage.STARVING], "each stage told: %s" % [said])


func test_starving_hurts_but_never_kills() -> void:
	var p := _player()
	await _run(p, 2)
	var flashes := []
	p.health.damaged.connect(func(a: float, _i: DamageInfo) -> void: flashes.append(a))
	p.hunger.set_food(0.0)
	p.hunger.tick(40.0, false, p.health)
	check_near(p.health.current_health, 90.0, 0.01, "a quarter of a point a second (%.1f)" % p.health.current_health)
	for i in 60:
		p.hunger.tick(10.0, false, p.health)
	check_near(p.health.current_health, 25.0, 0.01, "down to 25 and no further (%.1f)" % p.health.current_health)
	check(not p.is_dead(), "starving never kills you")
	check(flashes.is_empty(), "quietly: no hurt flash or sound")
	# Already below 25 (a raider got you): hunger takes nothing more
	p.health.current_health = 15.0
	p.hunger.tick(100.0, false, p.health)
	check_near(p.health.current_health, 15.0, 0.01, "below the floor, it takes nothing")


# ---------------------------------------------------------------- eating

func test_eating() -> void:
	var p := _player()
	await _run(p, 2)
	var refused := []
	p.item_use_refused.connect(func(r: String) -> void: refused.append(r))
	var j := InputFrame.new()
	j.eat = true
	await _run(p, 1, j)
	check(refused.back() == "Nothing to eat", "J with nothing to eat: %s" % [refused])
	p.inventory.add_item(VEG, 5)
	await _run(p, 1, j)
	check(refused.back() == "You're full", "J when full: %s" % [refused])
	p.hunger.set_food(50.0)
	await _run(p, 1, j)
	check(p.is_using_item() and p.get_item_in_use() == VEG, "J: eating a vegetable")
	await _run(p, 95)
	check(not p.is_using_item() and p.inventory.count_of(&"vegetables") == 4, "one eaten after 1.5 s")
	check_near(p.hunger.food, 62.0, 0.3, "+12 (%.1f)" % p.hunger.food)
	# Right-click in the inventory does the same
	check(p.request_use_item(VEG), "eat from the inventory")
	await _run(p, 95)
	check_near(p.hunger.food, 74.0, 0.3, "+12 again (%.1f)" % p.hunger.food)
	# Sprinting off cancels it, and nothing is eaten
	p.request_use_item(VEG)
	var run := InputFrame.new()
	run.move = Vector2(0, -1)
	run.sprint = true
	await _run(p, 5, run)
	check(not p.is_using_item() and p.inventory.count_of(&"vegetables") == 3, "sprinting off stops you eating")


func test_j_picks_what_to_eat() -> void:
	var p := _player()
	await _run(p, 2)
	var inv := p.inventory
	for it in [VEG, BEANS, PEACHES, STEW]:
		inv.add_item(it, 2)
	check(inv.find_best_food(70.0) == STEW, "very hungry: the stew (60)")
	check(inv.find_best_food(36.0) == BEANS, "half empty: beans (30)")
	check(inv.find_best_food(24.0) == BEANS, "a quarter empty: beans still (wasting a little is fine)")
	check(inv.find_best_food(18.0) == PEACHES, "a bit hungry: peaches (20)")
	check(inv.find_best_food(10.0) == VEG, "peckish: a vegetable (12)")
	check(inv.find_best_food(2.0) == VEG, "barely: the least filling there is")
	check(inv.count_food() == 8, "8 things to eat")
	check(STEW.food_value > BEANS.food_value and BEANS.food_value > PEACHES.food_value and PEACHES.food_value > VEG.food_value, "stew > beans > peaches > vegetables")
	check(STEW.category == ItemDefinition.Category.FOOD and BEANS.icon != null and STEW.world_model != null and BEANS.use_sound != null, "real items, with icons, models and a sound")


# ---------------------------------------------------------------- cooking

func test_stew_cooks_on_a_stove_or_a_workbench() -> void:
	check(STEW_R.output == STEW and STEW_R.inputs.get(VEG) == 3 and STEW_R.inputs.get(PLANK) == 1, "3 vegetables and a plank for the fire (a plank since 21.5)")
	check(STEW_R.can_make_at(RecipeDefinition.Station.STOVE) and STEW_R.can_make_at(RecipeDefinition.Station.WORKBENCH), "on a stove or a workbench")
	check(not STEW_R.can_make_at(RecipeDefinition.Station.HAND) and not STEW_R.can_make_at(RecipeDefinition.Station.WEAPONS_BENCH), "not by hand, not at the gun bench")
	var p := _player()
	var refused := []
	p.craft_refused.connect(func(r: String) -> void: refused.append(r))
	p.inventory.add_item(VEG, 6)
	p.inventory.add_item(PLANK, 2)
	check(not p.request_craft(STEW_R) and refused.back() == "Needs a Cooking Stove or a Workbench", "by hand: %s" % [refused])
	var stove := STOVE.instantiate() as CraftingStation
	stove.position = Vector3(0, 0, -1.4)
	add_child(stove)
	await _run(p, 3)
	_look_at(p, stove.get_focus_point())
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 2)
	await _run(p, 1, e)
	await _run(p, 1)
	check(p.current_station == stove and p.get_crafting_station() == RecipeDefinition.Station.STOVE, "E opens the stove")
	check(p.request_craft(STEW_R, 2), "cooking two")
	await _run(p, 60 * 9)
	check(p.inventory.count_of(&"vegetable_stew") == 2 and p.inventory.count_of(&"vegetables") == 0 and p.inventory.count_of(&"wood_plank") == 0, "two stews (4 s each)")
	# And on a workbench
	p.close_station()
	stove.queue_free()
	p.inventory.add_item(VEG, 3)
	p.inventory.add_item(PLANK, 1)
	var bench := WORKBENCH.instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.6)
	add_child(bench)
	await _run(p, 3)
	_look_at(p, bench.get_focus_point())
	await _run(p, 2)
	await _run(p, 1, e)
	await _run(p, 1)
	check(p.current_station == bench and p.request_craft(STEW_R), "a workbench cooks too")
	await _run(p, 60 * 5)
	check(p.inventory.count_of(&"vegetable_stew") == 3, "a third stew")


func test_the_farm_has_a_stove_and_loot_has_cans() -> void:
	var zone := await load_zone()
	var stove := zone.get_node("AshCreekFarms/CraftingStations/FarmStove") as CraftingStation
	check(stove != null and stove.station == RecipeDefinition.Station.STOVE, "a cooking stove at Ash Creek")
	var house := zone.get_node("AshCreekFarms/Buildings/Farmhouse") as Node3D
	var local := house.global_transform.affine_inverse() * stove.global_position
	check(local.x > 0.0 and local.x < 5.0 and absf(local.z) < 4.0, "in the farmhouse kitchen (%s)" % local)
	var tables := 0
	for f in DirAccess.get_files_at("res://resources/loot"):
		if not f.ends_with(".tres"):
			continue
		var lt := load("res://resources/loot/" + f) as LootTable
		if lt.entries.any(func(e: LootEntry) -> bool: return e.item == BEANS or e.item == PEACHES):
			tables += 1
	check(tables >= 8, "canned food in %d loot tables" % tables)
	var raider := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	check(raider.drop_items.has(BEANS), "raiders sometimes carry beans")
	raider.free()
	remove_child(zone)
	zone.free()
	await wait_physics(2)


# ---------------------------------------------------------------- kept

func test_hunger_is_saved_and_respawn_feeds_you() -> void:
	var p := _player()
	await _run(p, 2)
	p.hunger.set_food(37.0)
	var data := p.save_state()
	check(is_equal_approx(float(data["food"]), 37.0), "saved")
	p.hunger.set_food(100.0)
	p.load_state(data)
	check_near(p.hunger.food, 37.0, 0.01, "loaded")
	data.erase("food")
	p.load_state(data)
	check_near(p.hunger.food, 100.0, 0.01, "an older save starts you full")
	data["food"] = "lots"
	p.load_state(data)
	check_near(p.hunger.food, 100.0, 0.01, "nonsense is treated as full")
	p.hunger.set_food(10.0)
	p.respawn_at(Transform3D.IDENTITY.translated(Vector3(0, 0.05, 0)))
	check_near(p.hunger.food, 60.0, 0.01, "respawned with a meal in you")


func test_hud_shows_hunger() -> void:
	var zone := await load_zone()
	var hud := zone.get_node("HUD") as HUD
	var p := zone.get_node("Player") as PlayerController
	await wait_physics(3)
	var fill := hud.find_child("FoodFill", true, false) as ColorRect
	var title := hud.find_child("FoodTitle", true, false) as Label
	var eat := hud.find_child("EatSlotLabel", true, false) as Label
	check(fill != null and title != null and eat != null, "a food bar and a [J] slot")
	var full := fill.size.x
	p.hunger.set_food(50.0)
	await wait_physics(2)
	check_near(fill.size.x, full * 0.5, 1.0, "half full, half the bar")
	p.hunger.set_food(10.0)
	await wait_physics(2)
	check(title.text == "HUNGRY", "says HUNGRY: %s" % title.text)
	p.inventory.add_item(BEANS, 2)
	await wait_physics(2)
	check(eat.text == "[J]  FOOD ×2", "the [J] slot counts food: %s" % eat.text)
	var notices := []
	for n in hud.find_child("Notices", true, false).get_children():
		notices.append((n as Label).text if n is Label else "")
	check(notices.any(func(t: String) -> bool: return t.begins_with("You're hungry: too weak to sprint")), "a notice: %s" % [notices])
	remove_child(zone)
	zone.free()
	await wait_physics(2)
