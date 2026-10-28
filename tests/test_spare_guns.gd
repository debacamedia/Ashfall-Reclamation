extends "res://tests/test_case.gd"
## Increment 16.7: spare guns in the backpack, weapon slots in the inventory
## screen, a bigger interface and compass.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DT := 1.0 / 60.0
const W := "res://resources/items/weapons/"

var RIFLE: WeaponDefinition = load(W + "service_rifle.tres")
var PISTOL: WeaponDefinition = load(W + "pistol.tres")
var PIPE: WeaponDefinition = load(W + "pipe_pistol.tres")
var SHOTGUN: WeaponDefinition = load(W + "shotgun.tres")
var RIFLE_ITEM: ItemDefinition = load(W + "service_rifle_item.tres")
var PISTOL_ITEM: ItemDefinition = load(W + "pistol_item.tres")
var PIPE_ITEM: ItemDefinition = load(W + "pipe_pistol_item.tres")
var SHOTGUN_ITEM: ItemDefinition = load(W + "shotgun_item.tres")
var RED_DOT: ItemDefinition = load("res://resources/items/red_dot.tres")


func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	p.inventory.clear()
	return p


func _ammo_total(p: PlayerController, def: WeaponDefinition) -> int:
	var total := p.inventory.count_ammo(def.ammo_type)
	var w := p.weapon_slots.get_weapon(def.slot)
	if w != null and w.base_definition.ammo_type == def.ammo_type:
		total += w.ammo_in_magazine
	return total


func _index_of(p: PlayerController, item: ItemDefinition) -> int:
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == item:
			return i
	return -1


# ---------------------------------------------------------------- spares

func test_guns_have_weight_as_spares() -> void:
	for item: ItemDefinition in [PIPE_ITEM, PISTOL_ITEM, SHOTGUN_ITEM, RIFLE_ITEM, load(W + "scoped_rifle_item.tres")]:
		check(item.weight >= 1.0 and item.weight <= 5.0, "%s weighs %.1f kg as a spare" % [item.id, item.weight])
	check(SHOTGUN_ITEM.weight > PISTOL_ITEM.weight and RIFLE_ITEM.weight > PISTOL_ITEM.weight, "long guns weigh more than pistols")


func test_a_second_gun_becomes_a_spare() -> void:
	var p := await _player()
	check(p.receive_gun(SHOTGUN) == PlayerController.GUN_TO_SLOT, "first shotgun into slot 3")
	check(p.weapon_slots.get_weapon(3) != null, "in slot 3")
	var before := p.inventory.get_total_weight()
	check(p.receive_gun(SHOTGUN) == PlayerController.GUN_TO_BACKPACK, "second one into the backpack")
	check(p.inventory.count_of(SHOTGUN_ITEM.id) == 1, "a spare shotgun in the backpack")
	check_near(p.inventory.get_total_weight() - before, SHOTGUN_ITEM.weight, 0.01, "and it weighs what a shotgun weighs")
	# Better guns in hand stay: a worse one is a spare
	p.receive_gun(PISTOL)
	check(p.receive_gun(PIPE) == PlayerController.GUN_TO_BACKPACK and p.weapon_slots.get_weapon(2).base_definition == PISTOL, "a pipe pistol is a spare when you have a pistol")


func test_a_better_gun_swaps_the_old_one_into_the_backpack() -> void:
	var p := await _player()
	p.receive_gun(PIPE)
	check(p.receive_gun(PISTOL) == PlayerController.GUN_TO_SLOT, "the pistol goes into slot 2")
	check(p.weapon_slots.get_weapon(2).base_definition == PISTOL, "pistol in slot 2")
	check(p.inventory.count_of(PIPE_ITEM.id) == 1, "the pipe pistol it replaced is in the backpack, not thrown away")


func test_no_room_no_gun() -> void:
	var p := await _player()
	p.receive_gun(SHOTGUN)
	# Fill the backpack to its weight limit with scrap
	var scrap := ItemDatabase.get_item(&"scrap_metal")
	p.inventory.add_item(scrap, 999)
	check(p.gun_destination(SHOTGUN) == "", "nowhere for a second shotgun")
	check(p.gun_refusal_reason(SHOTGUN).begins_with("No room for a spare Pump Shotgun"), "says why: %s" % p.gun_refusal_reason(SHOTGUN))
	var pk := Pickup.spawn(self, SHOTGUN_ITEM, 1, Vector3(0, 0, -1))
	await wait_physics(2)
	check(pk.get_block_reason(p) != "", "a shotgun on the ground can't be picked up")
	check(p.receive_gun(SHOTGUN) == "" and p.inventory.count_of(SHOTGUN_ITEM.id) == 0, "and nothing changes")


func test_equip_a_spare_swaps_without_free_ammo() -> void:
	var p := await _player()
	var ammo := ItemDatabase.find_ammo_item(PIPE.ammo_type)
	p.receive_gun(PIPE)
	p.weapon_slots.get_weapon(2).ammo_in_magazine = 5
	p.inventory.add_item(ammo, 20)
	p.inventory.add_item(PISTOL_ITEM, 1)
	var total := _ammo_total(p, PIPE)
	var idx := _index_of(p, PISTOL_ITEM)
	check(p.request_equip_spare(idx), "equipped the spare pistol")
	check(p.weapon_slots.get_weapon(2).base_definition == PISTOL, "pistol in slot 2")
	check(p.weapon_slots.get_weapon(2).ammo_in_magazine == 0, "spares come out unloaded")
	check(p.inventory.get_slot_item(idx) == PIPE_ITEM, "the pipe pistol took its place in the backpack")
	check(_ammo_total(p, PIPE) == total, "the pipe pistol's 5 rounds went back with your ammo (%d of %d)" % [_ammo_total(p, PIPE), total])
	# Back and forth makes no ammo
	for i in 3:
		p.request_equip_spare(_index_of(p, PIPE_ITEM) if p.weapon_slots.get_weapon(2).base_definition == PISTOL else _index_of(p, PISTOL_ITEM))
	check(_ammo_total(p, PIPE) == total, "swapping back and forth makes no ammo")
	# Same gun in hand: refused
	p.inventory.add_item(PISTOL_ITEM if p.weapon_slots.get_weapon(2).base_definition == PISTOL else PIPE_ITEM, 1)
	var reasons := []
	p.gun_refused.connect(func(r: String) -> void: reasons.append(r))
	var same := p.weapon_slots.get_weapon(2).base_definition
	check(not p.request_equip_spare(_index_of(p, ItemDatabase.find_weapon_item(same.id))), "can't equip the gun you're holding")
	check(not reasons.is_empty() and reasons[0].contains("already have"), "says why: %s" % [reasons])


func test_put_a_gun_away_with_its_attachments() -> void:
	var p := await _player()
	var ammo := ItemDatabase.find_ammo_item(RIFLE.ammo_type)
	p.receive_gun(RIFLE)
	var w := p.weapon_slots.get_weapon(1)
	check(RED_DOT.attachment.fits(RIFLE.id), "the red dot fits the rifle")
	w.fit_attachment(RED_DOT.attachment)
	w.ammo_in_magazine = 17
	p.weapon_slots.equip_immediately(1)
	check(p.request_stow_gun(1), "put the rifle away")
	check(p.weapon_slots.get_weapon(1) == null, "slot 1 is empty")
	check(p.inventory.count_of(RIFLE_ITEM.id) == 1, "the rifle is in the backpack")
	check(p.inventory.count_of(RED_DOT.id) == 1, "its red dot came off into the backpack")
	check(p.inventory.count_ammo(RIFLE.ammo_type) == 17, "its 17 rounds went back with your ammo")
	check(p.weapon != null and p.weapon.definition.melee, "the machete comes out")
	check(not p.request_stow_gun(5), "the blade stays on your belt")


func test_spares_drop_with_your_gear_and_come_back() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.inventory.clear()
	p.receive_gun(SHOTGUN)
	p.receive_gun(SHOTGUN)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	var c := (zone.get_node("GameMode") as GameMode).get_dropped_gear(p)
	check(c != null and c.inventory.count_of(SHOTGUN_ITEM.id) == 2, "both shotguns in your dropped gear")
	remove_child(zone)
	zone.free()


# ---------------------------------------------------------------- inventory screen

func _hud_with(p: PlayerController) -> HUD:
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await wait_physics(3)
	return hud


func test_weapon_slots_in_the_inventory_screen() -> void:
	var p := await _player()
	var hud := await _hud_with(p)
	var screen := hud.inventory_screen
	check(screen.weapon_rows.size() == 5, "five weapon slots")
	p.receive_gun(PISTOL)
	p.receive_gun(SHOTGUN)
	p.weapon_slots.equip_immediately(2)
	screen.open()
	await wait_physics(2)
	var rows := screen.weapon_rows
	check(rows[0].weapon == null, "slot 1 (rifle) empty")
	check(rows[1].weapon != null and rows[1].weapon.base_definition == PISTOL, "slot 2 shows the pistol")
	check(rows[2].weapon != null and rows[2].weapon.base_definition == SHOTGUN, "slot 3 shows the shotgun")
	check(rows[4].weapon != null and rows[4].weapon.definition.melee, "slot 5 shows the machete")
	check((rows[1].find_child("WeaponName", true, false) as Label).text == "Sidearm Pistol", "with its name")
	check((rows[1].find_child("Icon", true, false) as TextureRect).texture != null, "and its picture")
	check((rows[0].find_child("WeaponName", true, false) as Label).text == "Empty", "empty slots say so")
	# Clicking a slot takes that gun out
	rows[2].pressed.emit(3)
	check(p.weapon_slots.pending_slot == 3, "clicking slot 3 starts taking out the shotgun")
	for i in 40:
		await get_tree().physics_frame
		p.simulate(InputFrame.new(), DT)
	check(p.weapon_slots.current_slot == 3, "and it's in your hands")
	# A spare: Equip button, and right-click equips it
	p.inventory.add_item(PIPE_ITEM, 1)
	screen.selected = _index_of(p, PIPE_ITEM)
	screen._refresh()
	var use := hud.find_child("UseButton", true, false) as Button
	check(not use.disabled and use.text == "Equip", "a spare gun's button says Equip")
	screen.request_use(_index_of(p, PIPE_ITEM))
	check(p.weapon_slots.get_weapon(2).base_definition == PIPE and p.inventory.count_of(PISTOL_ITEM.id) == 1, "equipped from the inventory screen; the pistol went into the backpack")
	# Dragging a gun off its slot onto the backpack puts it away
	screen.handle_slot_drop({"weapon_slot": 3}, screen._slots[0])
	check(p.weapon_slots.get_weapon(3) == null and p.inventory.count_of(SHOTGUN_ITEM.id) == 1, "dragged the shotgun into the backpack")
	# A spare can be dropped onto its own kind of slot only
	var idx := _index_of(p, SHOTGUN_ITEM)
	var data := {"inventory_slot": idx, "inventory": p.inventory}
	check(rows[2]._can_drop_data(Vector2.ZERO, data) and not rows[1]._can_drop_data(Vector2.ZERO, data), "a shotgun drops onto slot 3, not slot 2")
	rows[2]._drop_data(Vector2.ZERO, data)
	check(p.weapon_slots.get_weapon(3) != null and p.inventory.count_of(SHOTGUN_ITEM.id) == 0, "and dropping it there equips it")
	screen.close()
	hud.queue_free()


# ---------------------------------------------------------------- interface size

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
	hud.queue_free()
