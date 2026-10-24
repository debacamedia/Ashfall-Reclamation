extends "res://tests/test_case.gd"
## InventoryComponent (stacks, slots, weight, moving, transfers, saving),
## the player's inventory (loadout, ammo, medkits, quick heal, dropping) and
## the inventory screen.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")   # stack 100, 0.5 kg
var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")           # stack 10, 9 kg
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")         # stack 50, 0.2 kg
var AMMO: ItemDefinition = load("res://resources/items/rifle_ammo.tres")     # stack 120
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")


func _inv(slots := 6, max_weight := 0.0) -> InventoryComponent:
	var inv := InventoryComponent.new()
	inv.slot_count = slots
	inv.max_weight = max_weight
	add_child(inv)
	return inv


func _player() -> PlayerController:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


func _tick(p: PlayerController, ticks: int, f: InputFrame = null) -> void:
	if f == null:
		f = InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


# ---------------------------------------------------------------- core

func test_stacks_fill_existing_then_new_slots() -> void:
	var inv := _inv()
	check(inv.add_item(SCRAP, 70) == 70, "added 70")
	check(inv.add_item(SCRAP, 50) == 50, "added 50 more")
	check(inv.get_slot_quantity(0) == 100 and inv.get_slot_quantity(1) == 20, "first stack topped to 100, rest in slot 2")
	check(inv.count_of(&"scrap_metal") == 120, "count 120")


func test_full_slots_returns_partial() -> void:
	var inv := _inv(2)
	check(inv.add_item(FUEL, 25) == 20, "only 2 stacks of 10 fit")
	check(inv.get_refusal_reason(FUEL, 1) == "Inventory full", "refusal reason")
	check(inv.add_item(CLOTH, 5) == 0, "no slot for a different item")


func test_weight_limit() -> void:
	var inv := _inv(10, 30.0)
	check(inv.add_item(FUEL, 5) == 3, "3 fuel cans (27 kg) fit under 30 kg")
	check_near(inv.get_total_weight(), 27.0, 0.001, "weight 27 kg")
	check(inv.get_refusal_reason(FUEL, 1) == "Too heavy", "refused: too heavy")
	check(inv.add_item(SCRAP, 100) == 6, "6 scrap (3 kg) fills the rest")


func test_remove_across_stacks() -> void:
	var inv := _inv()
	inv.add_item(SCRAP, 150)
	check(inv.remove_item(&"scrap_metal", 120) == 120, "removed 120")
	check(inv.count_of(&"scrap_metal") == 30, "30 left")
	check(inv.remove_item(&"scrap_metal", 100) == 30, "can't remove more than there is")
	check(inv.get_free_slot_count() == 6, "slots freed")


func test_move_merge_swap_split() -> void:
	var inv := _inv()
	inv.add_item(SCRAP, 100)
	inv.add_item(CLOTH, 10)
	check(inv.move_slot(0, 4), "move to an empty slot")
	check(inv.get_slot_item(4) == SCRAP and inv.is_slot_empty(0), "moved")
	check(inv.move_slot(1, 4), "swap different items")
	check(inv.get_slot_item(4) == CLOTH and inv.get_slot_item(1) == SCRAP, "swapped")
	check(inv.move_slot(1, 2, 40), "split 40 into an empty slot")
	check(inv.get_slot_quantity(1) == 60 and inv.get_slot_quantity(2) == 40, "split 60/40")
	check(inv.move_slot(2, 1), "merge back")
	check(inv.get_slot_quantity(1) == 100 and inv.is_slot_empty(2), "merged to 100")
	check(not inv.move_slot(1, 4, 10), "can't split onto a different item")


func test_merge_respects_stack_limit() -> void:
	var inv := _inv()
	inv.add_item(SCRAP, 100)
	inv.move_slot(0, 1, 30)            # 70 | 30
	inv.add_item(SCRAP, 30)            # tops slot 0 to 100 → 100 | 30
	check(inv.get_slot_quantity(0) == 100 and inv.get_slot_quantity(1) == 30, "setup 100/30")
	check(not inv.move_slot(1, 0), "nothing moves onto a full stack")


func test_transfer_between_inventories() -> void:
	var a := _inv()
	var b := _inv(1, 20.0)
	a.add_item(FUEL, 5)
	var received := []
	b.item_received.connect(func(i: ItemDefinition, q: int) -> void: received.append(q))
	check(a.transfer_slot_to(0, b) == 2, "only 2 cans fit the 20 kg container")
	check(a.count_of(&"fuel") == 3 and b.count_of(&"fuel") == 2, "3 stay, 2 moved")
	check(received == [2], "item_received fired on the target")


func test_save_and_restore() -> void:
	var inv := _inv()
	inv.add_item(SCRAP, 130)
	inv.add_item(MEDKIT, 2)
	inv.move_slot(2, 5)
	var data := inv.to_data()
	var copy := _inv()
	copy.from_data(data)
	check(copy.count_of(&"scrap_metal") == 130 and copy.count_of(&"medkit") == 2, "counts restored")
	check(copy.get_slot_item(5) == MEDKIT, "slot positions restored")
	copy.from_data([{"id": "no_such_item", "qty": 5, "slot": 0}, {"id": "scrap_metal", "qty": -3, "slot": 1}, "junk"])
	check(copy.count_of(&"scrap_metal") == 0 and copy.get_free_slot_count() == 6, "bad save entries ignored")


func test_item_database() -> void:
	check(ItemDatabase.get_item(&"fuel") == FUEL, "lookup by id")
	check(ItemDatabase.find_ammo_item(&"rifle_556") == AMMO, "ammo item for the rifle")
	check(ItemDatabase.all_items().size() >= 6, "all items found")
	for item in ItemDatabase.all_items():
		check(item.icon != null, "%s has an icon" % item.id)


# ---------------------------------------------------------------- player

func test_starting_loadout() -> void:
	var p := _player()
	await _tick(p, 2)
	check(p.inventory.count_of(&"rifle_ammo") == 120, "starts with 120 rounds")
	check(p.inventory.count_of(&"medkit") == 1, "starts with 1 medkit")
	check(p.weapon.reserve_ammo == 120, "weapon sees 120 in reserve")


func test_reload_takes_ammo_from_inventory() -> void:
	var p := _player()
	await _tick(p, 2)
	var f := InputFrame.new()
	f.fire = true
	await _tick(p, 40, f)
	var fired := 30 - p.weapon.ammo_in_magazine
	f.fire = false
	f.reload = true
	await _tick(p, 1, f)
	f.reload = false
	await _tick(p, 150, f)
	check(p.weapon.ammo_in_magazine == 30, "magazine full after reload")
	check(p.inventory.count_of(&"rifle_ammo") == 120 - fired, "inventory lost exactly the %d rounds loaded" % fired)


func test_no_ammo_in_inventory_no_reload() -> void:
	var p := _player()
	await _tick(p, 2)
	p.inventory.remove_item(&"rifle_ammo", 999)
	p.weapon.ammo_in_magazine = 10
	check(not p.weapon.start_reload(), "can't reload with no rounds in the inventory")


func test_quick_heal_takes_time_and_uses_one_medkit() -> void:
	var p := _player()
	await _tick(p, 2)
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	var f := InputFrame.new()
	f.use_heal = true
	await _tick(p, 1, f)
	check(p.is_using_item(), "quick heal started")
	f.use_heal = false
	await _tick(p, 60, f)  # 1 s of the 2 s
	check_near(p.health.current_health, 50.0, 0.01, "no heal half-way through")
	check(p.weapon.lowered, "weapon lowered while healing")
	await _tick(p, 70, f)
	check(not p.is_using_item(), "finished")
	check_near(p.health.current_health, 90.0, 0.01, "healed 40")
	check(p.inventory.count_of(&"medkit") == 0, "medkit used up")
	check(not p.weapon.lowered, "weapon raised again")


func test_quick_heal_refusals() -> void:
	var p := _player()
	await _tick(p, 2)
	var reasons := []
	p.item_use_refused.connect(func(r: String) -> void: reasons.append(r))
	var f := InputFrame.new()
	f.use_heal = true
	await _tick(p, 1, f)
	check(reasons == ["Already at full health"], "refused at full health: %s" % [reasons])
	p.health.apply_damage(DamageInfo.create(30.0, DamageInfo.Type.FALL))
	p.inventory.remove_item(&"medkit", 5)
	await _tick(p, 1, f)
	check(reasons.size() == 2 and reasons[1] == "No medkits", "refused without medkits: %s" % [reasons])


func test_firing_cancels_heal_and_no_shots_while_healing() -> void:
	var p := _player()
	await _tick(p, 2)
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	var f := InputFrame.new()
	f.use_heal = true
	await _tick(p, 1, f)
	f.use_heal = false
	await _tick(p, 30, f)
	f.fire = true
	await _tick(p, 1, f)
	check(not p.is_using_item(), "pulling the trigger cancels the heal")
	check(p.inventory.count_of(&"medkit") == 1, "medkit not used up when cancelled")
	check_near(p.health.current_health, 50.0, 0.01, "no health gained")


func test_moving_slower_while_healing() -> void:
	var p := _player()
	await _tick(p, 2)
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	var f := InputFrame.new()
	f.use_heal = true
	await _tick(p, 1, f)
	f.use_heal = false
	f.move = Vector2(0, -1)
	await _tick(p, 60, f)
	check_near(p.get_horizontal_speed(), p.walk_speed * p.use_move_multiplier, 0.3, "half speed while healing")


func test_drop_slot_spawns_pickup() -> void:
	var p := _player()
	await _tick(p, 2)
	var slot := -1
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == MEDKIT:
			slot = i
	var pickup := p.request_drop_slot(slot)
	await wait_physics(2)
	check(pickup != null and pickup.item == MEDKIT and pickup.quantity == 1, "medkit pickup on the ground")
	check(p.inventory.count_of(&"medkit") == 0, "removed from the inventory")
	check(pickup.global_position.distance_to(p.global_position) < 2.0, "dropped in front of the player")


func test_respawn_tops_up_ammo() -> void:
	var p := _player()
	await _tick(p, 2)
	p.inventory.remove_item(&"rifle_ammo", 999)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	check(p.weapon.reserve_ammo >= p.weapon.definition.starting_reserve, "never respawn without ammo")


# ---------------------------------------------------------------- screen

func _hud_with_player() -> Array:
	var p := _player()
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	await _tick(p, 3)
	return [p, hud]


func test_screen_opens_and_shows_slots() -> void:
	var r: Array = await _hud_with_player()
	var p: PlayerController = r[0]
	var screen: InventoryScreen = (r[1] as HUD).inventory_screen
	screen.open()
	await wait_physics(2)
	check(screen.visible, "screen open")
	check(p.player_input.ui_open, "gameplay input blocked while open")
	var grid := screen.get_node("%Grid") as GridContainer
	check(grid.get_child_count() == 24, "24 slots shown")
	var texts := []
	for slot in grid.get_children():
		var q := (slot.get_node("%Quantity") as Label).text
		if q != "":
			texts.append(q)
	check(texts.has("120"), "ammo stack shows 120 (%s)" % [texts])
	check((screen.get_node("%WeightLabel") as Label).text == "1.9 / 30 kg", "weight: %s" % (screen.get_node("%WeightLabel") as Label).text)
	screen.close()
	check(not screen.visible and not p.player_input.ui_open, "closed, input restored")


func test_screen_use_drop_and_drag_move() -> void:
	var r: Array = await _hud_with_player()
	var p: PlayerController = r[0]
	var screen: InventoryScreen = (r[1] as HUD).inventory_screen
	screen.open()
	await wait_physics(2)
	var med_slot := -1
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == MEDKIT:
			med_slot = i
	screen.request_move(med_slot, 20)
	check(p.inventory.get_slot_item(20) == MEDKIT, "drag-and-drop moved the medkit to slot 21")
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	screen.request_use(20)
	await _tick(p, 130)
	check_near(p.health.current_health, 90.0, 0.01, "Use from the screen healed (gameplay keeps running)")
	screen.request_drop(0)
	await wait_physics(2)
	check(p.inventory.count_of(&"rifle_ammo") == 0, "Drop put the ammo stack on the ground")
	check(get_tree().get_nodes_in_group("pickups").size() == 1, "one pickup in the world")
