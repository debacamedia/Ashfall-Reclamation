extends "res://tests/test_case.gd"
## Increment 7: loot tables, salvage containers (search once, open, lid),
## validated transfers between player and container, the transfer screen,
## and save state.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CRATE := preload("res://scenes/world/containers/supply_crate.tscn")
const DT := 1.0 / 60.0

var AMMO: ItemDefinition = load("res://resources/items/rifle_ammo.tres")
var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")


func _entry(item: ItemDefinition, weight: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item = item
	e.weight = weight
	e.min_quantity = lo
	e.max_quantity = hi
	return e


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Player at the origin facing -Z, with a crate 1.4 m in front of it.
func _setup(seed_value := 1234) -> Array:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	var c := CRATE.instantiate() as SalvageContainer
	c.loot_seed = seed_value
	c.position = Vector3(0, 0, -1.4)
	add_child(c)
	await _tick(p, 3)
	_look_at(p, c.get_focus_point())
	await _tick(p, 2)
	return [p, c]


func _look_at(p: PlayerController, point: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


func _tick(p: PlayerController, ticks: int, interact := false) -> void:
	var f := InputFrame.new()
	f.interact = interact
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _search(p: PlayerController, c: SalvageContainer) -> void:
	var ticks := ceili(c.search_time / DT) + 3
	await _tick(p, ticks, true)
	await _tick(p, 1, false)


# ---------------------------------------------------------------- loot tables

func test_loot_table_roll_rules() -> void:
	var t := LootTable.new()
	t.entries = [_entry(AMMO, 3, 10, 20), _entry(SCRAP, 1, 2, 4)]
	t.min_rolls = 2
	t.max_rolls = 4
	var a := t.roll(_rng(7))
	var b := t.roll(_rng(7))
	check(str(a) == str(b), "same seed, same loot")
	var different := false
	for s in 30:
		var r := t.roll(_rng(100 + s))
		var total_rolls_ok := true
		for stack: Dictionary in r:
			check(stack["item"] == AMMO or stack["item"] == SCRAP, "only items from the table")
			if stack["item"] == SCRAP:
				total_rolls_ok = total_rolls_ok and stack["qty"] >= 2 and stack["qty"] <= 16
			else:
				total_rolls_ok = total_rolls_ok and stack["qty"] >= 10 and stack["qty"] <= 80
		check(total_rolls_ok, "quantities within entry bounds × rolls (%s)" % [r])
		if str(r) != str(a):
			different = true
	check(different, "different seeds give different loot")
	var ids := {}
	for stack: Dictionary in t.roll(_rng(3)):
		check(not ids.has(stack["item"]), "repeats are merged into one stack")
		ids[stack["item"]] = true


func test_loot_table_weights_guaranteed_and_empty() -> void:
	var t := LootTable.new()
	t.entries = [_entry(AMMO, 9, 1, 1), _entry(SCRAP, 1, 1, 1)]
	t.min_rolls = 1
	t.max_rolls = 1
	var ammo := 0
	for s in 1000:
		if t.roll(_rng(s + 1))[0]["item"] == AMMO:
			ammo += 1
	check_between(ammo, 850, 950, "weight 9:1 gives ~90%% ammo (%d / 1000)" % ammo)
	t.guaranteed = [_entry(MEDKIT, 1, 2, 2)]
	var r := t.roll(_rng(5))
	check(r.any(func(s: Dictionary) -> bool: return s["item"] == MEDKIT and s["qty"] == 2), "guaranteed entry always present")
	t.empty_chance = 1.0
	check(t.roll(_rng(5)).is_empty(), "empty_chance 1 → nothing")


func test_shipped_loot_tables_are_valid() -> void:
	var dir := DirAccess.open("res://resources/loot")
	var count := 0
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var t := load("res://resources/loot/" + f) as LootTable
		check(t != null, "%s loads as a LootTable" % f)
		count += 1
		check(not t.possible_items().is_empty(), "%s has items" % f)
		for item in t.possible_items():
			check(ItemDatabase.get_item(item.id) == item, "%s: %s is a registered item" % [f, item.id])
		var any := false
		for s in 20:
			if not t.roll(_rng(s + 1)).is_empty():
				any = true
		check(any, "%s produces loot" % f)
	check(count >= 6, "6 loot tables (%d)" % count)


# ---------------------------------------------------------------- containers

func test_search_once_then_open() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	check(p.interactor.focused == c, "looking at the crate focuses it")
	check(c.get_prompt(p) == "Search Supply Crate" and c.hold_time > 1.0, "prompt: '%s' (hold %.1f s)" % [c.get_prompt(p), c.hold_time])
	var opened := []
	p.container_opened.connect(func(x: SalvageContainer) -> void: opened.append(x))
	await _tick(p, 30, true)
	check(not c.is_searched, "a short hold doesn't search")
	await _tick(p, 1, false)
	await _search(p, c)
	check(c.is_searched, "holding E for search_time searches it")
	check(p.current_container == c and opened == [c], "and opens it for the player")
	check(c.is_open() and c.users == [p], "container knows who has it open")
	var expected := c.loot_table.roll(_rng(1234))
	var total := 0
	for stack: Dictionary in expected:
		check(c.inventory.count_of(stack["item"].id) == stack["qty"], "%s ×%d rolled in" % [stack["item"].id, stack["qty"]])
		total += stack["qty"]
	check(total > 0, "crate has loot")
	var snapshot := str(c.inventory.to_data())
	p.close_container()
	check(p.current_container == null and not c.is_open(), "closed")
	check(c.get_prompt(p).begins_with("Open Supply Crate") and c.hold_time == 0.0, "now a tap to open: '%s'" % c.get_prompt(p))
	await _tick(p, 1, true)
	await _tick(p, 1, false)
	check(p.current_container == c, "tap E reopens")
	check(str(c.inventory.to_data()) == snapshot, "not rolled again")


func test_take_store_and_take_all() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	await _search(p, c)
	c.inventory.clear()
	c.inventory.add_item(SCRAP, 5)
	c.inventory.add_item(MEDKIT, 2)
	var received := []
	p.inventory.item_received.connect(func(i: ItemDefinition, q: int) -> void: received.append([i.id, q]))
	var scrap_slot := 0
	check(p.request_take(scrap_slot) == 5, "take a whole stack")
	check(p.inventory.count_of(&"scrap_metal") == 5 and c.inventory.count_of(&"scrap_metal") == 0, "scrap moved to the player")
	check(received.has([&"scrap_metal", 5]), "item_received fires (HUD notice + sound)")
	var ammo_slot := -1
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == AMMO:
			ammo_slot = i
	check(p.request_store(ammo_slot, 50) == 50, "store part of a stack")
	check(p.inventory.count_of(&"rifle_ammo") == 70 and c.inventory.count_of(&"rifle_ammo") == 50, "50 rounds stored, 70 kept")
	check(p.request_take_all() == 52, "take all: 2 medkits + 50 rounds")
	check(c.inventory.get_free_slot_count() == c.inventory.slot_count, "container emptied")
	check(c.get_prompt(p) == "Open Supply Crate (empty)", "prompt says empty")


func test_weight_limit_refuses_with_reason() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	await _search(p, c)
	c.inventory.clear()
	c.inventory.add_item(FUEL, 4)  # 36 kg
	var reasons := []
	p.transfer_refused.connect(func(why: String) -> void: reasons.append(why))
	var moved := p.request_take(0)
	check(moved == 3, "only 3 fuel cans fit under 30 kg (took %d)" % moved)
	check(reasons == ["Too heavy"], "refusal reason: %s" % [reasons])
	check(c.inventory.count_of(&"fuel") == 1, "the rest stays in the crate")
	reasons.clear()
	p.request_take_all()
	check(reasons == ["Too heavy"], "take all reports it too")


func test_transfers_are_validated() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	c.search()
	c.inventory.clear()
	c.inventory.add_item(SCRAP, 3)
	check(p.request_take(0) == 0, "can't take from a container you haven't opened")
	await _tick(p, 1, true)
	await _tick(p, 1, false)
	check(p.current_container == c, "opened")
	p.global_position = Vector3(0, 0.05, 8)
	await _tick(p, 2)
	check(p.current_container == null and not c.is_open(), "walking away closes it")
	check(p.request_take(0) == 0 and c.inventory.count_of(&"scrap_metal") == 3, "nothing taken from out of reach")
	p.global_position = Vector3(0, 0.05, 0)
	await _tick(p, 2)
	_look_at(p, c.get_focus_point())
	await _tick(p, 1, true)
	await _tick(p, 1, false)
	check(p.current_container == c, "reopened")
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	check(p.current_container == null, "dying closes it")
	check(p.request_take(0) == 0, "dead players take nothing")


func test_lid_opens_and_closes() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var lid := c.get_node("%Lid") as Node3D
	var closed := lid.rotation_degrees
	await _search(p, c)
	await wait_physics(40)
	check(lid.rotation_degrees.distance_to(closed + c.lid_open_rotation) < 1.0, "lid swung open")
	p.close_container()
	await wait_physics(40)
	check(lid.rotation_degrees.distance_to(closed) < 1.0, "lid closed again")


func test_save_state_round_trip() -> void:
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	await _search(p, c)
	p.request_take(0)
	var data := c.save_state()
	check(data["searched"] == true and data["items"] is Array, "save_state has searched + items")
	var copy := CRATE.instantiate() as SalvageContainer
	copy.position = Vector3(5, 0, 5)
	add_child(copy)
	copy.load_state(JSON.parse_string(JSON.stringify(data)))
	check(copy.is_searched and copy.hold_time == 0.0, "restored as searched (no re-roll)")
	check(str(copy.inventory.to_data()) == str(c.inventory.to_data()), "same contents after a JSON round trip")
	copy.load_state({"searched": "yes", "items": "junk"})
	check(not copy.is_searched and copy.inventory.get_free_slot_count() == copy.inventory.slot_count, "bad data is ignored safely")
	check(c.is_in_group("persist"), "in the persist group for SaveManager")


# ---------------------------------------------------------------- screen

func _hud_setup() -> Array:
	var r: Array = await _setup()
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = r[0]
	add_child(hud)
	await _tick(r[0], 3)
	return [r[0], r[1], hud.container_screen]


func test_screen_opens_with_both_inventories() -> void:
	var r: Array = await _hud_setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var screen: ContainerScreen = r[2]
	await _search(p, c)
	await wait_physics(2)
	check(screen.visible and p.player_input.ui_open, "screen open, gameplay input paused")
	check(screen.get_node("%PlayerGrid").get_child_count() == 24, "24 player slots")
	check(screen.get_node("%ContainerGrid").get_child_count() == c.inventory.slot_count, "%d container slots" % c.inventory.slot_count)
	check((screen.get_node("%Title") as Label).text == "SUPPLY CRATE", "title")
	check((screen.get_node("%CarryLabel") as Label).text == "2.2 / 30 kg", "carry weight: %s" % (screen.get_node("%CarryLabel") as Label).text)
	var shown := 0
	for slot: InventorySlot in screen.get_node("%ContainerGrid").get_children():
		if slot.tooltip_text != "":
			shown += 1
	check(shown == c.inventory.slot_count - c.inventory.get_free_slot_count(), "every stack drawn (%d)" % shown)
	p.close_container()
	await wait_physics(1)
	check(not screen.visible and not p.player_input.ui_open, "closing restores gameplay input")


func test_screen_moves_stacks() -> void:
	var r: Array = await _hud_setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var screen: ContainerScreen = r[2]
	await _search(p, c)
	c.inventory.clear()
	c.inventory.add_item(SCRAP, 4)
	c.inventory.add_item(MEDKIT, 1)
	# Right-click on a container slot takes it
	screen._on_slot_clicked(0, MOUSE_BUTTON_RIGHT, ContainerScreen.SIDE_CONTAINER)
	check(p.inventory.count_of(&"scrap_metal") == 4, "right-click took the scrap")
	# Double-click (activated) on a player slot stores it
	var scrap_slot := -1
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == SCRAP:
			scrap_slot = i
	screen._on_slot_activated(scrap_slot, ContainerScreen.SIDE_PLAYER)
	check(c.inventory.count_of(&"scrap_metal") == 4, "double-click stored it back")
	# Drag from the container onto a player slot
	var cslots := screen.get_node("%ContainerGrid").get_children()
	var pslots := screen.get_node("%PlayerGrid").get_children()
	var med_index := -1
	for i in c.inventory.slot_count:
		if c.inventory.get_slot_item(i) == MEDKIT:
			med_index = i
	screen.handle_slot_drop({"inventory_slot": med_index, "inventory": c.inventory}, pslots[10])
	check(p.inventory.count_of(&"medkit") == 2, "drag across took the medkit")
	# Drag within the container rearranges
	var from := -1
	for i in c.inventory.slot_count:
		if c.inventory.get_slot_item(i) == SCRAP:
			from = i
	screen.handle_slot_drop({"inventory_slot": from, "inventory": c.inventory}, cslots[11])
	check(c.inventory.get_slot_item(11) == SCRAP, "drag inside the crate moved the stack")
	# Select + Take button, then Take All button
	screen._on_slot_clicked(11, MOUSE_BUTTON_LEFT, ContainerScreen.SIDE_CONTAINER)
	check(screen.selected == 11 and not (screen.get_node("%TakeButton") as Button).disabled, "selected; Take enabled")
	check((screen.get_node("%DetailLabel") as Label).text.begins_with("Scrap Metal ×4"), "details: %s" % (screen.get_node("%DetailLabel") as Label).text)
	(screen.get_node("%TakeButton") as Button).pressed.emit()
	check(p.inventory.count_of(&"scrap_metal") == 4, "Take button")
	c.inventory.add_item(SCRAP, 2)
	(screen.get_node("%TakeAllButton") as Button).pressed.emit()
	check(p.inventory.count_of(&"scrap_metal") == 6 and c.inventory.get_free_slot_count() == c.inventory.slot_count, "Take All button")
	await wait_physics(1)
	check((screen.get_node("%EmptyLabel") as Label).visible, "shows Empty")


func test_screen_shows_refusal() -> void:
	var r: Array = await _hud_setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var screen: ContainerScreen = r[2]
	await _search(p, c)
	c.inventory.clear()
	c.inventory.add_item(FUEL, 4)
	screen.request_take_all()
	check((screen.get_node("%MessageLabel") as Label).text == "Too heavy", "message: '%s'" % (screen.get_node("%MessageLabel") as Label).text)


func test_close_keys() -> void:
	var r: Array = await _hud_setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var screen: ContainerScreen = r[2]
	for action in ["interact", "inventory", "pause"]:
		if p.current_container == null:
			c.search()
			c._perform(p)
			await wait_physics(1)
		check(screen.visible, "open before pressing %s" % action)
		var e := InputEventAction.new()
		e.action = action
		e.pressed = true
		Input.parse_input_event(e)
		await wait_physics(2)
		check(not screen.visible and p.current_container == null, "%s closes the screen" % action)
		var inv_screen := (screen.get_parent().get_node("%InventoryScreen") as InventoryScreen)
		check(not inv_screen.visible, "and doesn't open the inventory instead")
		var release := InputEventAction.new()
		release.action = action
		release.pressed = false
		Input.parse_input_event(release)
		await wait_physics(1)


func test_lockers_clang_shut() -> void:
	# Resource Pack 3: lockers clang shut, crates thud
	var clang := load("res://assets/ashfall_pack_v3/audio/locker_close.wav")
	for path in ["res://scenes/world/containers/weapons_locker.tscn", "res://scenes/world/containers/footlocker.tscn"]:
		var c := (load(path) as PackedScene).instantiate() as SalvageContainer
		c.position = Vector3(15, 0, 15)
		add_child(c)
		check((c.get_node("%CloseSound") as AudioStreamPlayer3D).stream == clang, "%s closes with a metal clang" % path.get_file())
	var crate := CRATE.instantiate() as SalvageContainer
	crate.position = Vector3(-15, 0, 15)
	add_child(crate)
	check((crate.get_node("%CloseSound") as AudioStreamPlayer3D).stream == load("res://assets/ashfall_pack_v3/audio/crate_close.wav"), "crates close with a wooden thud")
	var r: Array = await _setup()
	var p: PlayerController = r[0]
	var c: SalvageContainer = r[1]
	var shut := [0]
	c.lid_closed.connect(func() -> void: shut[0] += 1)
	await _search(p, c)
	await wait_physics(30)
	check(shut[0] == 0, "no close sound while open")
	p.close_container()
	await wait_physics(40)
	check(shut[0] == 1, "close sound once the lid has shut")
