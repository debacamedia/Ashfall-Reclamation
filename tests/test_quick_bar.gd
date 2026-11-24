extends "res://tests/test_case.gd"
## Increment 32: the quick bar. Eight slots (keys 1-8, the wheel skips empty
## ones) that you fill yourself with anything you can hold: guns and blades,
## each with its own rounds and attachments (two pistols side by side if you
## like), medkits and food (held, fire uses them). Drag between the backpack
## and the bar; it's saved, it migrates old loadouts, and dying drops all of
## it but your blade into your gear.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DT := 1.0 / 60.0
const W := "res://resources/items/weapons/"

var RIFLE: WeaponDefinition = load(W + "service_rifle.tres")
var PISTOL: WeaponDefinition = load(W + "pistol.tres")
var SHOTGUN: WeaponDefinition = load(W + "shotgun.tres")
var MACHETE: WeaponDefinition = load(W + "machete.tres")
var RIFLE_ITEM: ItemDefinition = load(W + "service_rifle_item.tres")
var PISTOL_ITEM: ItemDefinition = load(W + "pistol_item.tres")
var SHOTGUN_ITEM: ItemDefinition = load(W + "shotgun_item.tres")
var MACHETE_ITEM: ItemDefinition = load(W + "machete_item.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")
var BEANS: ItemDefinition = load("res://resources/items/canned_beans.tres")
var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var RIFLE_AMMO: ItemDefinition = load("res://resources/items/rifle_ammo.tres")


## A fresh player as a new game makes one: a machete on slot 1.
func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	return p


func _run(p: PlayerController, f: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _slot_frame(slot: int) -> InputFrame:
	var f := InputFrame.new()
	f.slot = slot
	return f


func _index_of(p: PlayerController, item: ItemDefinition) -> int:
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == item:
			return i
	return -1


# ---------------------------------------------------------------- the bar

func test_a_new_game_starts_with_a_machete_on_slot_1() -> void:
	var p := await _player()
	check(p.quick_bar != null and p.quick_bar.slot_count == 8, "an eight-slot quick bar")
	check(p.quick_bar.get_parent() == p.inventory and InventoryComponent.find_on(p) == p.inventory, "under the backpack, which is still what find_on finds")
	check(p.quick_bar.get_slot_item(0) == MACHETE_ITEM, "the machete on slot 1 (%s)" % p.quick_bar.get_slot_item(0))
	check(p.weapon != null and p.weapon.definition == MACHETE and p.weapon_slots.current_slot == 1, "and in your hands")
	PlayerInput.ensure_bar_keys()
	for i in range(1, 9):
		check(InputMap.has_action("weapon_%d" % i), "key %d picks slot %d" % [i, i])
	var back := InputFrame.from_dict(_slot_frame(8).to_dict())
	check(back.slot == 8, "slot 8 survives the network")


func test_what_you_can_hold() -> void:
	for item: ItemDefinition in [PISTOL_ITEM, MACHETE_ITEM, MEDKIT, BEANS]:
		check(QuickBar.holdable(item), "%s can go on the bar" % item.id)
	check(QuickBar.refusal_reason(RIFLE_AMMO) == "Rounds stay in your backpack", "not rounds: %s" % QuickBar.refusal_reason(RIFLE_AMMO))
	check(QuickBar.refusal_reason(WOOD).begins_with("You can't hold"), "not wood: %s" % QuickBar.refusal_reason(WOOD))
	var p := await _player()
	p.inventory.add_item(WOOD, 3)
	var refused := []
	p.gun_refused.connect(func(r: String) -> void: refused.append(r))
	check(not p.request_move_to_bar(_index_of(p, WOOD), 3), "wood refused")
	check(refused.size() == 1 and p.quick_bar.is_slot_empty(3), "with a reason, nothing moved")


func test_two_pistols_side_by_side() -> void:
	var p := await _player()
	check(p.receive_gun(PISTOL) == PlayerController.GUN_TO_SLOT, "a pistol onto the bar")
	check(p.receive_gun(PISTOL) == PlayerController.GUN_TO_SLOT, "and another")
	var a := p.weapon_slots.get_weapon(2)
	var b := p.weapon_slots.get_weapon(3)
	check(a != null and b != null and a != b and a.base_definition == PISTOL and b.base_definition == PISTOL, "two pistols, slots 2 and 3")
	check(p.weapon_slots.pending_slot == 2, "the first comes straight out (only a blade was in hand)")
	await _run(p, InputFrame.new(), 60)
	check(p.weapon == a, "it's out")
	var fire := InputFrame.new()
	fire.fire = true
	await _run(p, fire, 1)
	await _run(p, InputFrame.new(), 2)
	check(a.ammo_in_magazine == PISTOL.magazine_size - 1 and b.ammo_in_magazine == PISTOL.magazine_size, "each keeps its own rounds (%d, %d)" % [a.ammo_in_magazine, b.ammo_in_magazine])
	await _run(p, _slot_frame(3), 1)
	await _run(p, InputFrame.new(), 40)
	check(p.weapon == b and p.weapon_slots.current_slot == 3, "key 3: the second pistol")
	check(p.quick_bar.get_slot_state(1)["magazine"] == PISTOL.magazine_size - 1, "the bar's entry follows the gun's rounds")


func test_the_wheel_skips_empty_slots() -> void:
	var p := await _player()
	p.inventory.add_item(PISTOL_ITEM, 1)
	p.request_move_to_bar(_index_of(p, PISTOL_ITEM), 5)
	check(p.weapon_slots.get_item(6) == PISTOL_ITEM, "a pistol dragged onto slot 6")
	var f := InputFrame.new()
	f.cycle = 1
	await _run(p, f, 1)
	check(p.weapon_slots.pending_slot == 6, "the wheel goes from 1 straight to 6 (%d)" % p.weapon_slots.pending_slot)
	await _run(p, InputFrame.new(), 40)
	await _run(p, f, 1)
	check(p.weapon_slots.pending_slot == 1, "and round to 1")
	await _run(p, _slot_frame(4), 1)
	check(p.weapon_slots.pending_slot == 1, "an empty slot's key does nothing")


func test_guns_on_the_bar_weigh_nothing_medkits_do() -> void:
	var p := await _player()
	p.inventory.clear()
	check_near(p.inventory.get_total_weight(), 0.0, 0.001, "a machete on the bar weighs nothing")
	p.receive_gun(SHOTGUN)
	check_near(p.inventory.get_total_weight(), 0.0, 0.001, "nor a shotgun")
	p.inventory.add_item(MEDKIT, 2)
	p.request_move_to_bar(_index_of(p, MEDKIT), 4)
	check(p.quick_bar.get_slot_quantity(4) == 2 and _index_of(p, MEDKIT) == -1, "both medkits went up")
	check_near(p.inventory.get_total_weight(), MEDKIT.weight * 2.0, 0.001, "medkits on the bar still weigh")
	check(p.inventory.count_of(MEDKIT.id) == 2 and p.inventory.find_best_medical() == MEDKIT, "and H finds them")
	# Off the bar into the backpack: a gun weighs again
	p.request_move_to_backpack(p.weapon_slots.find_slot(&"shotgun") - 1)
	check_near(p.inventory.get_total_weight(), MEDKIT.weight * 2.0 + SHOTGUN_ITEM.weight, 0.001, "a shotgun in the backpack weighs")


func test_drag_guns_between_backpack_and_bar_as_they_are() -> void:
	var p := await _player()
	p.receive_gun(RIFLE)
	var rifle := p.weapon_slots.get_weapon(2)
	rifle.fit_attachment(ItemDatabase.get_attachment(&"red_dot"))
	rifle.ammo_in_magazine = 7
	check(p.request_move_to_backpack(1), "rifle off the bar")
	var idx := _index_of(p, RIFLE_ITEM)
	check(idx >= 0 and p.weapon_slots.get_weapon(2) == null, "into the backpack")
	check(not is_instance_valid(rifle) or rifle.is_queued_for_deletion(), "its live gun freed")
	var st := p.inventory.get_slot_state(idx)
	check(st["magazine"] == 7 and st["attachments"] == ["red_dot"], "with its rounds and red dot (%s)" % [st])
	check(p.weapon != null and p.weapon.definition == MACHETE, "the machete's in hand again")
	# And back onto slot 8
	check(p.request_move_to_bar(idx, 7), "rifle onto slot 8")
	var back := p.weapon_slots.get_weapon(8)
	check(back != null and back.ammo_in_magazine == 7 and back.attachments.size() == 1, "just as it was")
	# Swap: a pistol in the backpack dragged onto the rifle's slot
	p.inventory.add_item(PISTOL_ITEM, 1)
	check(p.request_move_to_bar(_index_of(p, PISTOL_ITEM), 7), "pistol onto slot 8")
	check(p.weapon_slots.get_item(8) == PISTOL_ITEM and _index_of(p, RIFLE_ITEM) >= 0, "the rifle swapped into the backpack")
	check(p.inventory.get_slot_state(_index_of(p, RIFLE_ITEM))["magazine"] == 7, "still with 7 rounds")
	# Rearranging the bar
	check(p.request_move_in_bar(7, 2) and p.weapon_slots.get_item(3) == PISTOL_ITEM, "pistol moved to slot 3")
	# Dropped on the ground, picked up again: as it was
	p.request_move_to_bar(_index_of(p, RIFLE_ITEM), 4)
	var pk := p.request_drop_bar_slot(4)
	check(pk != null and pk.state["magazine"] == 7, "a dropped rifle keeps its rounds")
	check(p.receive_gun(RIFLE, true, pk.state) == PlayerController.GUN_TO_SLOT, "picked up")
	check(p.weapon_slots.get_weapon(p.weapon_slots.find_slot(&"service_rifle")).ammo_in_magazine == 7, "still 7")


func test_a_held_medkit_or_food_is_used_with_fire() -> void:
	var p := await _player()
	p.inventory.clear()
	p.inventory.add_item(MEDKIT, 2)
	p.request_move_to_bar(_index_of(p, MEDKIT), 1)
	p.health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.FALL))
	var hp := p.health.current_health
	await _run(p, _slot_frame(2), 1)
	await _run(p, InputFrame.new(), 30)
	check(p.weapon_slots.held_item() == MEDKIT and p.weapon == null, "a medkit in hand, no gun")
	var fire := InputFrame.new()
	fire.fire = true
	await _run(p, fire, 1)
	check(p.is_using_item() and p.get_item_in_use() == MEDKIT, "fire starts using it")
	# Holding fire doesn't cancel it (it would for H)
	await _run(p, fire, int(MEDKIT.use_time / DT) + 10)
	check(not p.is_using_item() and p.health.current_health > hp, "healed (%.0f → %.0f)" % [hp, p.health.current_health])
	check(p.quick_bar.get_slot_quantity(1) == 1, "one medkit used off the bar")
	await _run(p, fire, 5)
	check(not p.is_using_item(), "holding fire doesn't use another")


# ---------------------------------------------------------------- saves

func test_the_bar_is_saved_and_loaded() -> void:
	var p := await _player()
	p.receive_gun(PISTOL)
	p.receive_gun(PISTOL)
	p.weapon_slots.get_weapon(3).ammo_in_magazine = 4
	p.inventory.add_item(MEDKIT, 1)
	p.request_move_to_bar(_index_of(p, MEDKIT), 5)
	p.weapon_slots.equip_immediately(3)
	var data := JSON.parse_string(JSON.stringify(p.save_state())) as Dictionary
	check(data.get("quick_bar") is Array and (data["quick_bar"] as Array).size() == 4, "four things on the bar saved")
	var p2 := PLAYER_SCENE.instantiate() as PlayerController
	p2.controlled_locally = false
	p2.position = Vector3(4, 0.05, 0)
	add_child(p2)
	await wait_physics(3)
	p2.load_state(data)
	check(p2.weapon_slots.get_item(1) == MACHETE_ITEM and p2.weapon_slots.get_item(2) == PISTOL_ITEM and p2.weapon_slots.get_item(3) == PISTOL_ITEM, "machete, pistol, pistol")
	check(p2.weapon_slots.get_item(6) == MEDKIT, "the medkit on slot 6")
	check(p2.weapon_slots.current_slot == 3 and p2.weapon.ammo_in_magazine == 4, "the second pistol in hand, 4 rounds")
	check(p2.weapon_slots.get_weapon(2).ammo_in_magazine == PISTOL.magazine_size, "the first full")
	check(p2.weapon_slots.owned().size() == 3, "three live weapons, no leftovers")
	check(p2.camera.get_node("WeaponMount").get_children().filter(func(c: Node) -> bool: return c is HitscanWeapon and not c.is_queued_for_deletion()).size() == 3, "three on the mount")


func test_an_old_loadout_moves_onto_the_bar() -> void:
	var p := await _player()
	p.load_state({
		"inventory": [{"id": "pistol", "qty": 1, "slot": 0}],
		"loadout": {"weapons": [
			{"id": "service_rifle", "magazine": 7, "attachments": ["red_dot"]},
			{"id": "shotgun", "magazine": 2, "attachments": []},
			{"id": "machete", "magazine": 0, "attachments": []}],
			"equipped": 3},
	})
	check(p.weapon_slots.get_item(1) == RIFLE_ITEM and p.weapon_slots.get_item(3) == SHOTGUN_ITEM and p.weapon_slots.get_item(5) == MACHETE_ITEM,
		"each gun on the slot it had: rifle 1, shotgun 3, machete 5")
	check(p.weapon_slots.get_weapon(1).ammo_in_magazine == 7 and p.weapon_slots.get_weapon(1).attachments.size() == 1, "the rifle as it was")
	check(p.weapon_slots.current_slot == 3 and p.weapon.definition == SHOTGUN and p.weapon.ammo_in_magazine == 2, "the shotgun in hand, 2 shells")
	check(p.inventory.get_slot_item(0) == PISTOL_ITEM and p.inventory.get_slot_state(0)["magazine"] == PISTOL.magazine_size, "an old spare pistol in the backpack, as found")
	var refs := p.weapon_slots.owned()
	check(refs.size() == 3, "three live weapons")


# ---------------------------------------------------------------- dying

func test_dying_drops_the_bar_but_your_blade() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.inventory.clear()
	p.receive_gun(SHOTGUN)
	p.receive_gun(SHOTGUN)
	p.weapon_slots.get_weapon(p.weapon_slots.find_slot(&"shotgun")).ammo_in_magazine = 3
	p.inventory.add_item(MEDKIT, 1)
	p.request_move_to_bar(_index_of(p, MEDKIT), 6)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	var c := (zone.get_node("GameMode") as GameMode).get_dropped_gear(p)
	check(c != null and c.inventory.count_of(SHOTGUN_ITEM.id) == 2 and c.inventory.count_of(MEDKIT.id) == 1, "both shotguns and the medkit in your dropped gear")
	var bar_left := []
	for i in 8:
		if p.quick_bar.get_slot_item(i) != null:
			bar_left.append(p.quick_bar.get_slot_item(i).id)
	check(bar_left == [&"machete"], "only the machete left on the bar (%s)" % [bar_left])
	var mags := []
	for i in c.inventory.slot_count:
		if c.inventory.get_slot_item(i) == SHOTGUN_ITEM:
			mags.append(int(c.inventory.get_slot_state(i)["magazine"]))
	mags.sort()
	check(mags == [3, SHOTGUN.magazine_size], "each shotgun with its own shells (%s)" % [mags])
	remove_child(zone)
	zone.free()


func test_an_old_cache_gives_guns_back_as_they_were() -> void:
	var cache := (load(DeathCache.SCENE) as PackedScene).instantiate() as DeathCache
	add_child(cache)
	cache.load_state({"slots": 4, "items": [{"id": "service_rifle", "qty": 1, "slot": 0}],
		"guns": {"service_rifle": {"magazine": 5, "attachments": ["red_dot"]}}, "position": [0, 0, 0]})
	check(cache.inventory.get_slot_item(0) == RIFLE_ITEM, "a cache from before Increment 32 loads")
	var st := cache.legacy_state(&"service_rifle")
	check(st.get("magazine") == 5.0 or st.get("magazine") == 5, "its gun's state kept apart (%s)" % [st])
	check(cache.legacy_state(&"service_rifle").is_empty(), "once")
	cache.free()


# ---------------------------------------------------------------- the inventory screen

func _hud_with(p: PlayerController) -> HUD:
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(3)
	return hud


func test_the_quick_bar_in_the_inventory_screen() -> void:
	var p := await _player()
	var hud := await _hud_with(p)
	var screen := hud.inventory_screen
	check(screen.bar_slots.size() == 8, "eight quick bar cells")
	p.inventory.clear()
	p.inventory.add_item(PISTOL_ITEM, 1)
	p.inventory.add_item(MEDKIT, 1)
	screen.open()
	await wait_physics(2)
	var cells := screen.bar_slots
	check(cells[0].inventory == p.quick_bar, "bound to the bar")
	check((cells[0].get_node("%Icon") as TextureRect).texture == MACHETE_ITEM.icon, "the machete's picture on slot 1")
	# A gun in the backpack: To quick bar
	screen._select(_index_of(p, PISTOL_ITEM), -1)
	screen._refresh()
	var use := hud.find_child("UseButton", true, false) as Button
	check(use.text == "To quick bar" and not screen.bar_button.disabled, "a gun's button says To quick bar")
	check((hud.find_child("DetailInfo", true, false) as Label).text.contains("Loaded: %d / %d" % [PISTOL.magazine_size, PISTOL.magazine_size]), "its rounds in the details")
	# Drag the pistol onto slot 4
	screen.handle_slot_drop({"inventory_slot": _index_of(p, PISTOL_ITEM), "inventory": p.inventory}, cells[3])
	check(p.weapon_slots.get_item(4) == PISTOL_ITEM and _index_of(p, PISTOL_ITEM) == -1, "dragged onto slot 4")
	await wait_physics(2)
	check(screen._rounds_note(3) == "%d/%d" % [PISTOL.magazine_size, PISTOL.magazine_size], "the cell shows its rounds")
	# Right-click uses a medkit; the Quick bar button puts it on the bar
	screen._select(_index_of(p, MEDKIT), -1)
	screen._on_bar_pressed()
	check(p.quick_bar.count_of(MEDKIT.id) == 1 and _index_of(p, MEDKIT) == -1, "Quick bar button: the medkit went up")
	# Right-click a bar cell: off the bar
	screen._on_bar_clicked(3, MOUSE_BUTTON_RIGHT)
	check(p.weapon_slots.get_item(4) == null and _index_of(p, PISTOL_ITEM) >= 0, "right-click took the pistol off")
	# Drag from the bar onto a backpack cell
	var med_at := -1
	for i in 8:
		if p.quick_bar.get_slot_item(i) == MEDKIT:
			med_at = i
	screen.handle_slot_drop({"inventory_slot": med_at, "inventory": p.quick_bar}, screen._slots[10])
	check(p.inventory.get_slot_item(10) == MEDKIT, "dragged off onto backpack slot 11")
	# Double-click a bar cell: hold it
	screen.request_hold(0)
	check(p.weapon_slots.current_slot == 1 or p.weapon_slots.pending_slot == 1, "slot 1 in hand")
	screen.close()
	hud.queue_free()


# ---------------------------------------------------------------- interface size (16.7)

func test_interface_scales_and_is_bigger() -> void:
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "the interface stretches with the window (Retina, full screen)")
	check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "and keeps its proportions")
	check(UiScale.DEFAULT > 1.0, "drawn bigger than before by default (%d%%)" % roundi(UiScale.DEFAULT * 100))
	for size: Vector2 in [Vector2(1600, 900), Vector2(2880, 1800), Vector2(1280, 720), Vector2(3840, 2160), Vector2(1440, 900)]:
		var top := UiScale.largest_for(size)
		var stretch := minf(size.x / UiScale.BASE.x, size.y / UiScale.BASE.y)
		var room: Vector2 = size / (stretch * top)
		check(room.x >= UiScale.MIN_SPACE.x - 0.5 and room.y >= UiScale.MIN_SPACE.y - 0.5, "%s: the biggest size still fits the windows (%s)" % [size, room])
		check(top >= UiScale.DEFAULT - 0.001, "%s: the default size fits" % size)
	var p := await _player()
	var hud := await _hud_with(p)
	var old := UiScale.saved()
	hud.set_ui_scale(1.0)
	check_near(hud.ui_scale, 1.0, 0.001, "can be made smaller")
	check_near(UiScale.saved(), 1.0, 0.001, "and remembered")
	hud.set_ui_scale(5.0)
	check(hud.ui_scale <= UiScale.largest_for(Vector2(get_window().size)) + 0.001, "never bigger than fits")
	hud.set_ui_scale(old)
	check(CompassBar.CARDINAL_SIZE >= 20 and CompassBar.NAME_SIZE >= 17 and CompassBar.WIDTH >= 600.0, "a bigger compass with bigger letters")
	# The inventory window, quick bar and all, fits the smallest space
	hud.inventory_screen.open()
	await wait_physics(2)
	var win := hud.inventory_screen.get_node("%Window") as Control
	check(win.size.y <= UiScale.MIN_SPACE.y and win.size.x <= UiScale.MIN_SPACE.x, "the inventory window fits %s (%s)" % [UiScale.MIN_SPACE, win.size])
	hud.inventory_screen.close()
	hud.queue_free()
