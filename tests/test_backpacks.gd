extends "res://tests/test_case.gd"
## Increment 16.8: backpacks (wear one to carry more) and double-tap W to
## sprint.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DT := 1.0 / 60.0

var SATCHEL: ItemDefinition = load("res://resources/items/satchel.tres")
var RUCKSACK: ItemDefinition = load("res://resources/items/rucksack.tres")
var MILITARY: ItemDefinition = load("res://resources/items/military_pack.tres")
var FRAME: ItemDefinition = load("res://resources/items/frame_pack.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")


func _player() -> PlayerController:
	make_static_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	p.inventory.clear()
	return p


func _run(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _index_of(p: PlayerController, item: ItemDefinition) -> int:
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == item:
			return i
	return -1


## Fills `n` distinct slots (one-of-a-kind items so they don't stack).
func _fill_slots(p: PlayerController, n: int) -> void:
	var kinds := ItemDatabase.all_items().filter(func(i: ItemDefinition) -> bool: return i.max_stack == 1 and not i.is_pack() and i.weight <= 0.5)
	var filler: ItemDefinition = kinds[0] if not kinds.is_empty() else SCRAP
	for i in n:
		p.inventory._slots[p.inventory._slots.find(null)] = {"item": filler, "qty": 1}


# ---------------------------------------------------------------- the packs

func test_four_packs_each_carries_more() -> void:
	var packs := [SATCHEL, RUCKSACK, MILITARY, FRAME]
	for i in packs.size():
		var pk: ItemDefinition = packs[i]
		check(pk.is_pack() and pk.category == ItemDefinition.Category.EQUIPMENT and pk.icon != null and pk.world_model != null, "%s is a backpack with an icon and a model" % pk.id)
		if i > 0:
			check(pk.pack_slots > packs[i - 1].pack_slots and pk.pack_carry_weight > packs[i - 1].pack_carry_weight, "%s carries more than %s" % [pk.id, packs[i - 1].id])
	check(PlayerInventory.slots_for(null) == SATCHEL.pack_slots and is_equal_approx(PlayerInventory.weight_for(null), SATCHEL.pack_carry_weight), "no pack = the satchel: %d slots, %.0f kg" % [SATCHEL.pack_slots, SATCHEL.pack_carry_weight])
	check(FRAME.pack_carry_weight <= 60.0, "even the biggest stays well short of a truck (%.0f kg)" % FRAME.pack_carry_weight)
	check(FRAME.pack_rattle_radius > 0.0 and MILITARY.pack_rattle_radius == 0.0, "only the frame pack rattles")


func test_wear_a_pack_and_swap_up() -> void:
	var p := await _player()
	p.inventory.add_item(SCRAP, 10)
	check(p.inventory.slot_count == 24 and is_equal_approx(p.inventory.max_weight, 30.0), "start: satchel, 24 slots, 30 kg")
	p.inventory.add_item(RUCKSACK, 1)
	check(p.request_wear_pack(_index_of(p, RUCKSACK)), "put on the rucksack")
	check(p.inventory.pack == RUCKSACK and p.inventory.slot_count == 30 and is_equal_approx(p.inventory.max_weight, 40.0), "30 slots, 40 kg")
	check(p.inventory.count_of(RUCKSACK.id) == 0, "a worn pack isn't in the grid (and doesn't weigh anything)")
	check(p.inventory.count_of(SCRAP.id) == 10, "nothing lost")
	p.inventory.add_item(MILITARY, 1)
	var idx := _index_of(p, MILITARY)
	check(p.request_wear_pack(idx), "swapped up to the military pack")
	check(p.inventory.pack == MILITARY and p.inventory.slot_count == 36, "36 slots")
	check(p.inventory.get_slot_item(idx) == RUCKSACK, "the rucksack took its place in the grid")


func test_a_smaller_pack_only_if_it_all_fits() -> void:
	var p := await _player()
	p.inventory.add_item(FRAME, 1)
	p.request_wear_pack(_index_of(p, FRAME))
	_fill_slots(p, 30)
	# Things in the high slots, then try to go back down
	p.inventory.add_item(RUCKSACK, 1)
	var reasons := []
	p.pack_refused.connect(func(r: String) -> void: reasons.append(r))
	check(not p.request_wear_pack(_index_of(p, RUCKSACK)), "can't swap to the rucksack with 31 things to carry")
	check(not reasons.is_empty() and reasons[-1].contains("empty"), "says why: %s" % reasons)
	check(not p.request_take_off_pack(), "nor take the frame pack off")
	check(p.inventory.pack == FRAME and p.inventory.slot_count == 42, "nothing changed")
	# Heavy: under the slot count but over the weight
	p.inventory.clear()
	p.inventory.add_item(SCRAP, int(45.0 / SCRAP.weight))
	p.inventory.add_item(RUCKSACK, 1)
	check(not p.request_wear_pack(_index_of(p, RUCKSACK)) and reasons[-1].contains("kg"), "too heavy for the rucksack: %s" % reasons[-1])
	# Light enough: things from high slots move down
	p.inventory.clear()
	p.inventory.add_to_slot(40, CLOTH, 3)
	check(p.request_take_off_pack(), "took the frame pack off")
	check(p.inventory.slot_count == 24 and p.inventory.count_of(CLOTH.id) == 3 and p.inventory.count_of(FRAME.id) == 1, "back to 24 slots: the cloth moved down, the frame pack's in the grid")


func test_packs_to_craft_and_find() -> void:
	var r := RecipeDatabase.get_recipe(&"craft_rucksack")
	check(r != null and r.output == RUCKSACK and r.station == RecipeDefinition.Station.HAND, "a rucksack is made by hand")
	check(r != null and r.category == RecipeDefinition.Category.GEAR, "under Gear")
	var f := RecipeDatabase.get_recipe(&"craft_frame_pack")
	check(f != null and f.output == FRAME and f.station == RecipeDefinition.Station.WORKBENCH, "a frame pack at a workbench")
	check(RecipeDatabase.recipes_for(MILITARY).is_empty(), "the military pack can't be made, only found")
	var p := await _player()
	for item: ItemDefinition in r.inputs:
		p.inventory.add_item(item, r.inputs[item])
	check(p.request_craft(r), "crafting a rucksack")
	await _run(p, int(r.craft_time * 60.0) + 5)
	check(p.inventory.count_of(RUCKSACK.id) == 1, "made a rucksack")
	# Loot
	var qm := load("res://resources/loot/quartermaster.tres") as LootTable
	var rng := RandomNumberGenerator.new()
	rng.seed = 168
	for i in 5:
		check(qm.roll(rng).any(func(e: Dictionary) -> bool: return e["item"] == MILITARY), "Northwatch's quartermaster always has a military pack")
	for t in ["garrison_crate", "smuggler_stash"]:
		check((load("res://resources/loot/%s.tres" % t) as LootTable).possible_items().has(MILITARY), "%s may have one" % t)
	check((load("res://resources/loot/mine_supplies.tres") as LootTable).possible_items().has(FRAME), "the mine may have a frame pack")
	var zone := instance_zone()
	check((zone.get_node("NorthwatchOutpost/SalvageContainers/StoresCrate") as SalvageContainer).loot_table == qm, "the quartermaster's crate is in Northwatch's stores")
	zone.free()


func test_dying_drops_your_pack_and_you_keep_the_satchel() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.inventory.clear()
	p.inventory.add_item(MILITARY, 1)
	p.request_wear_pack(_index_of(p, MILITARY))
	p.inventory.add_to_slot(33, CLOTH, 4)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	var c := (zone.get_node("GameMode") as GameMode).get_dropped_gear(p)
	check(c != null and c.inventory.count_of(MILITARY.id) == 1 and c.inventory.count_of(CLOTH.id) == 4, "your pack and what was in it are in your dropped gear")
	check(p.inventory.pack == null and p.inventory.slot_count == 24 and is_equal_approx(p.inventory.max_weight, 30.0), "you're back to your satchel")
	remove_child(zone)
	zone.free()


func test_your_pack_is_saved() -> void:
	var p := await _player()
	p.inventory.add_item(FRAME, 1)
	p.request_wear_pack(_index_of(p, FRAME))
	p.inventory.add_to_slot(40, CLOTH, 5)
	var data := p.save_state()
	check(data.get("pack") == "frame_pack", "the save knows your pack")
	p.request_take_off_pack()
	p.inventory.clear()
	p.load_state(data)
	check(p.inventory.pack == FRAME and p.inventory.slot_count == 42, "loading puts it back on")
	check(p.inventory.get_slot_item(40) == CLOTH and p.inventory.get_slot_quantity(40) == 5, "with things in slot 41 still there")
	var old := data.duplicate()
	old.erase("pack")
	p.load_state(old)
	check(p.inventory.pack == null and p.inventory.slot_count == 24, "an older save (no pack) loads with the satchel")


func test_the_frame_pack_rattles() -> void:
	var p := await _player()
	var listener := GDScript.new()
	listener.source_code = "extends Node\nvar heard := []\nfunc hear_noise(_o: Vector3, r: float, _s: Node) -> void:\n\theard.append(r)\n"
	listener.reload()
	var ear := Node.new()
	ear.set_script(listener)
	ear.add_to_group("noise_listeners")
	add_child(ear)
	var walk := InputFrame.new()
	walk.move = Vector2(0, -1)
	p.inventory.add_item(MILITARY, 1)
	p.request_wear_pack(_index_of(p, MILITARY))
	await _run(p, 90, walk)
	check(ear.get("heard").is_empty(), "a military pack is quiet")
	p.inventory.add_item(FRAME, 1)
	p.request_wear_pack(_index_of(p, FRAME))
	await _run(p, 90, walk)
	var walking: Array = ear.get("heard").duplicate()
	check(not walking.is_empty() and is_equal_approx(walking[0], FRAME.pack_rattle_radius), "a frame pack rattles as you walk (%s)" % [walking])
	ear.get("heard").clear()
	var sneak := InputFrame.new()
	sneak.move = Vector2(0, -1)
	sneak.crouch = true
	await _run(p, 90, sneak)
	check(ear.get("heard").is_empty(), "crouching, it's quiet")
	ear.free()


func test_backpack_slot_in_the_inventory_screen() -> void:
	var p := await _player()
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(3)
	var screen := hud.inventory_screen
	screen.open()
	await wait_physics(2)
	var row := screen.pack_row
	check(row != null and (row.find_child("PackName", true, false) as Label).text == "Satchel", "the backpack slot shows your satchel")
	check(screen.grid_scroll != null and screen.grid_scroll.get_child(0) == hud.find_child("Grid", true, false), "the grid scrolls")
	check(hud.find_child("Grid", true, false).get_child_count() == 24, "24 slots")
	p.inventory.add_item(RUCKSACK, 1)
	screen.selected = _index_of(p, RUCKSACK)
	screen._refresh()
	var use := hud.find_child("UseButton", true, false) as Button
	check(use.text == "Wear" and not use.disabled, "a backpack's button says Wear")
	screen.request_use(_index_of(p, RUCKSACK))
	await wait_physics(2)
	check(p.inventory.pack == RUCKSACK, "wearing the rucksack")
	check((row.find_child("PackName", true, false) as Label).text == "Rucksack", "the slot shows it")
	check(hud.find_child("Grid", true, false).get_child_count() == 30, "and the grid grew to 30 slots")
	row.take_off_requested.emit()
	await wait_physics(2)
	check(p.inventory.pack == null and hud.find_child("Grid", true, false).get_child_count() == 24, "right-click took it off: back to 24")
	screen.close()
	hud.queue_free()


# ---------------------------------------------------------------- double-tap sprint

func test_double_tap_forward_to_sprint() -> void:
	var input := PlayerInput.new()
	add_child(input)
	check(input.double_tap_sprint, "on by default")
	check(not input.update_double_tap(true, true, false, 10.0), "one tap: walking")
	input.update_double_tap(false, false, false, 10.1)
	check(input.update_double_tap(true, true, false, 10.2), "a second tap within %.2f s: sprinting" % input.double_tap_window)
	for t in [10.5, 11.0, 14.0]:
		check(input.update_double_tap(false, true, false, t), "still sprinting while you keep moving forward (%.1f s)" % t)
	check(not input.update_double_tap(false, false, false, 14.1), "let go of forward: stops")
	input.update_double_tap(true, true, false, 20.0)
	input.update_double_tap(false, false, false, 20.2)
	check(not input.update_double_tap(true, true, false, 20.6), "two taps too far apart: walking")
	input.update_double_tap(true, true, false, 20.7)
	check(input.sprint_latched, "sprinting again")
	check(not input.update_double_tap(false, true, true, 20.8), "crouching stops it")
	input.double_tap_sprint = false
	input.update_double_tap(true, true, false, 30.0)
	check(not input.update_double_tap(true, true, false, 30.1), "can be turned off")
	input.free()


func test_sprinting_is_faster_and_widens_the_view() -> void:
	var p := await _player()
	var walk := InputFrame.new()
	walk.move = Vector2(0, -1)
	await _run(p, 60, walk)
	var walk_speed := p.get_horizontal_speed()
	var fov_walk := p.camera.fov
	var sprint := InputFrame.new()
	sprint.move = Vector2(0, -1)
	sprint.sprint = true
	await _run(p, 60, sprint)
	check(p.get_horizontal_speed() > walk_speed + 1.0, "sprinting is faster (%.1f vs %.1f m/s)" % [p.get_horizontal_speed(), walk_speed])
	check(p.camera.fov > fov_walk + 3.0, "and the view widens a little (%.1f°)" % p.camera.fov)
	check(p.sprint_seconds > 0.5, "time spent sprinting is counted, for hunger later (%.1f s)" % p.sprint_seconds)
	await _run(p, 60, walk)
	check(absf(p.camera.fov - fov_walk) < 0.5, "back to normal when you stop")
