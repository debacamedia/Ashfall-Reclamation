extends "res://tests/test_case.gd"
## Milestone 2 weapons: loadout slots and switching, pistol, pump shotgun
## (pellets, shell-by-shell reload), marksman rifle (4x scope), weapon
## pickups, saving the loadout.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PICKUP := preload("res://scenes/items/pickup.tscn")
const DT := 1.0 / 60.0

var RIFLE: WeaponDefinition = load("res://resources/items/weapons/service_rifle.tres")
var PISTOL: WeaponDefinition = load("res://resources/items/weapons/pistol.tres")
var SHOTGUN: WeaponDefinition = load("res://resources/items/weapons/shotgun.tres")
var MARKSMAN: WeaponDefinition = load("res://resources/items/weapons/scoped_rifle.tres")
var SHOTGUN_ITEM: ItemDefinition = load("res://resources/items/weapons/shotgun_item.tres")
var SHELLS: ItemDefinition = load("res://resources/items/shotgun_shells.tres")
var MARKSMAN_AMMO: ItemDefinition = load("res://resources/items/rifle_308.tres")


func _player() -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


func _frame() -> InputFrame:
	return InputFrame.new()


func _run(p: PlayerController, f: InputFrame, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _switch(p: PlayerController, slot: int) -> void:
	var f := _frame()
	f.slot = slot
	await _run(p, f, 1)
	await _run(p, _frame(), 75)


## A big target `distance` m in front of the player's eyes.
func _target(distance: float, hp := 1000.0) -> HealthComponent:
	var root := Node3D.new()
	add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.NPCS
	body.position = Vector3(0, 1.67, -distance)
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	shape.shape = box
	body.add_child(shape)
	var h := HealthComponent.new()
	h.max_health = hp
	root.add_child(h)
	return h


# ---------------------------------------------------------------- loadout

func test_definitions_and_scenes_are_valid() -> void:
	for def: WeaponDefinition in [RIFLE, PISTOL, SHOTGUN, MARKSMAN]:
		check(def.slot >= 1 and def.slot <= 5, "%s has a slot" % def.id)
		var w := def.instantiate_weapon()
		check(w != null and w.definition == def, "%s scene instantiates" % def.id)
		if w == null:
			continue
		add_child(w)
		check(w.get_node_or_null("%SightAnchor") != null and w.get_node_or_null("%Muzzle") != null, "%s has sights and a muzzle" % def.id)
		check(ItemDatabase.find_ammo_item(def.ammo_type) != null, "%s has an ammo item" % def.id)
		check(ItemDatabase.get_weapon(def.id) == def, "%s found by id" % def.id)
	var slots := {}
	for def in [RIFLE, PISTOL, SHOTGUN, MARKSMAN]:
		check(not slots.has(def.slot), "one gun per slot")
		slots[def.slot] = true


func test_start_with_rifle_and_pistol() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	var slots := p.weapon_slots
	check(slots.get_weapon(1).definition == RIFLE and slots.get_weapon(2).definition == PISTOL, "rifle in 1, pistol in 2")
	check(slots.get_weapon(3) == null and slots.get_weapon(4) == null, "slots 3 and 4 empty")
	check(p.weapon == slots.get_weapon(1) and slots.current_slot == 1, "rifle in hand")
	check(slots.get_weapon(1).visible and not slots.get_weapon(2).visible, "only the gun in hand is shown")
	check(slots.get_weapon(2).reserve_ammo == 36, "36 pistol rounds in the pack (%d)" % slots.get_weapon(2).reserve_ammo)
	check(slots.get_weapon(1).reserve_ammo == 120, "120 rifle rounds")


func test_switching_takes_time_and_blocks_firing() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	var rifle := p.weapon
	var started := []
	var equipped := []
	p.weapon_slots.switch_started.connect(func(s: int) -> void: started.append(s))
	p.weapon_slots.weapon_equipped.connect(func(w: HitscanWeapon) -> void: equipped.append(w.definition.id))
	var f := _frame()
	f.slot = 2
	await _run(p, f, 1)
	check(p.is_switching_weapon() and started == [2], "switch started")
	var fire := _frame()
	fire.fire = true
	await _run(p, fire, 10)
	check(rifle.ammo_in_magazine == rifle.definition.magazine_size, "no shots while putting the rifle away")
	await _run(p, _frame(), 30)
	check(not p.is_switching_weapon() and p.weapon.definition == PISTOL, "pistol up after holster + draw (~0.5 s)")
	check(equipped == [&"pistol"], "weapon_equipped once")
	check(p.weapon.visible and not rifle.visible, "pistol shown, rifle hidden")
	await _run(p, fire, 1)
	check(p.weapon.ammo_in_magazine == 11, "pistol fires once it's up")


func test_number_keys_wheel_and_unowned_slots() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	var f := _frame()
	f.slot = 3
	await _run(p, f, 1)
	check(not p.is_switching_weapon(), "an empty slot does nothing")
	f = _frame()
	f.slot = 1
	await _run(p, f, 1)
	check(not p.is_switching_weapon(), "the slot in hand does nothing")
	var wheel := _frame()
	wheel.cycle = 1
	await _run(p, wheel, 1)
	await _run(p, _frame(), 60)
	check(p.weapon.definition == PISTOL, "wheel down → next gun")
	await _run(p, wheel, 1)
	await _run(p, _frame(), 60)
	check(p.weapon.definition == RIFLE, "wraps around to the rifle")
	wheel.cycle = -1
	await _run(p, wheel, 1)
	await _run(p, _frame(), 60)
	check(p.weapon.definition == PISTOL, "wheel up → previous gun")


func test_wheel_is_rate_limited() -> void:
	var p := _player()
	await _run(p, _frame(), 2)
	var input := p.player_input
	input.queue_cycle(1)
	input.queue_cycle(1)
	input.queue_cycle(1)
	check(input._pending_cycle == 1, "a burst of wheel events (Magic Mouse swipe) is one step")


func test_switching_cancels_reload_and_toggled_aim() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	var rifle := p.weapon
	rifle.ammo_in_magazine = 5
	var r := _frame()
	r.reload = true
	await _run(p, r, 1)
	check(rifle.is_reloading, "rifle reloading")
	p.player_input.update_aim(true, false)
	await _switch(p, 2)
	check(not rifle.is_reloading and rifle.ammo_in_magazine == 5, "reload abandoned, magazine kept")
	check(not p.player_input.is_aiming_toggled(), "toggled sights lowered by the switch")


func test_pistol_uses_its_own_ammo() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	await _switch(p, 2)
	var pistol := p.weapon
	var h := _target(10.0)
	var fire := _frame()
	fire.fire = true
	await _run(p, fire, 20)
	check(pistol.ammo_in_magazine == 11, "semi-auto: holding the trigger fires once")
	check_near(h.max_health - h.current_health, 24.0, 0.01, "24 damage")
	pistol.ammo_in_magazine = 0
	var r := _frame()
	r.reload = true
	await _run(p, r, 1)
	await _run(p, _frame(), 100)
	check(pistol.ammo_in_magazine == 12 and pistol.reserve_ammo == 24, "reloaded 12 from 36 pistol rounds")
	check(p.inventory.count_ammo(&"rifle_556") == 120, "rifle ammo untouched")


# ---------------------------------------------------------------- pickups

func _pickup_in_front(p: PlayerController, item: ItemDefinition, qty := 1) -> Pickup:
	var pk := PICKUP.instantiate() as Pickup
	pk.item = item
	pk.quantity = qty
	pk.position = Vector3(0, 0, -1.6)
	add_child(pk)
	var eye := p.head.global_position
	var t := pk.global_position + Vector3(0, 0.1, 0)
	p.head.rotation.x = atan2(t.y - eye.y, eye.z - t.z)
	return pk


func _hold_e(p: PlayerController, ticks: int) -> void:
	var f := _frame()
	f.interact = true
	await _run(p, f, ticks)
	await _run(p, _frame(), 1)


func test_weapon_pickup_fills_its_slot() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	var pk := _pickup_in_front(p, SHOTGUN_ITEM)
	await _run(p, _frame(), 2)
	check(pk.get_prompt(p) == "Pick up Pump Shotgun", "prompt: %s" % pk.get_prompt(p))
	var got := []
	p.weapon_picked_up.connect(func(d: WeaponDefinition) -> void: got.append(d.id))
	await _hold_e(p, 40)
	check(p.weapon_slots.get_weapon(3) != null and p.weapon_slots.get_weapon(3).definition == SHOTGUN, "shotgun in slot 3")
	check(got == [&"shotgun"] and not is_instance_valid(pk), "weapon_picked_up, pickup gone")
	check(p.weapon.definition == RIFLE, "still holding the rifle")
	check(p.inventory.count_of(&"shotgun") == 0, "guns don't go into the inventory grid")
	var again := _pickup_in_front(p, SHOTGUN_ITEM)
	await _run(p, _frame(), 2)
	check(again.get_prompt(p) == "Take ammo from Pump Shotgun", "second one: %s" % again.get_prompt(p))
	await _hold_e(p, 40)
	check(p.inventory.count_of(&"shotgun_shells") == 6 and not is_instance_valid(again), "a duplicate gun gives its 6 shells")


# ---------------------------------------------------------------- shotgun

func test_shotgun_pellets_and_one_hit_marker() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.give_weapon(SHOTGUN)
	await _switch(p, 3)
	var shotgun := p.weapon
	check(shotgun.definition == SHOTGUN and shotgun.ammo_in_magazine == 6, "shotgun up with 6 loaded")
	var h := _target(3.0)
	var markers := []
	shotgun.hit_confirmed.connect(func(_t: Node, dmg: float, _k: bool, _z: float) -> void: markers.append(dmg))
	var fire := _frame()
	fire.fire = true
	await _run(p, fire, 1)
	check(markers.size() == 1, "one hit marker for the whole blast (%d)" % markers.size())
	check_near(h.max_health - h.current_health, 9.0 * 13.0, 0.01, "all 9 pellets hit at 3 m: 117 damage")
	await _run(p, _frame(), 70)  # pump cycle (70 rpm)
	check(shotgun.ammo_in_magazine == 5, "pump: one shell per shot")


func test_shotgun_loads_shell_by_shell_and_can_interrupt() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.give_weapon(SHOTGUN)
	p.inventory.add_item(SHELLS, 3)
	await _switch(p, 3)
	var sg := p.weapon
	sg.ammo_in_magazine = 2
	var r := _frame()
	r.reload = true
	await _run(p, r, 1)
	await _run(p, _frame(), 36)  # ~0.6 s
	check(sg.ammo_in_magazine == 3 and sg.is_reloading, "one shell loaded after 0.55 s, still loading")
	await _run(p, _frame(), 33)
	check(sg.ammo_in_magazine == 4, "second shell")
	var fire := _frame()
	fire.fire = true
	await _run(p, fire, 1)
	check(not sg.is_reloading and sg.ammo_in_magazine == 3, "trigger pull stops loading and fires")
	check(p.inventory.count_of(&"shotgun_shells") == 1, "1 shell left in the pack")


func test_shotgun_falloff() -> void:
	check_near(SHOTGUN.damage_at_distance(5.0), 13.0, 0.01, "full damage up close")
	check(SHOTGUN.damage_at_distance(25.0) < 2.5, "almost nothing at 25 m")


# ---------------------------------------------------------------- marksman

func test_marksman_scope() -> void:
	var p := _player()
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	await _run(p, _frame(), 3)
	p.give_weapon(MARKSMAN)
	p.inventory.add_item(MARKSMAN_AMMO, 10)
	await _switch(p, 4)
	var mr := p.weapon
	check(mr.definition == MARKSMAN and mr.ammo_in_magazine == 5, "marksman rifle up, 5 loaded")
	var hip := mr.get_current_spread_degrees()
	var aim := _frame()
	aim.aim = true
	# Iron sights until a 4× Scope is fitted at a weapons bench
	await _run(p, aim, 30)
	for i in 4:
		await get_tree().process_frame
	check_near(p.camera.fov, 75.0 / 1.3, 0.1, "irons: 1.3× (FOV %.1f)" % p.camera.fov)
	check(not (hud.get_node("%ScopeOverlay") as Control).visible, "no scope overlay on irons")
	await _run(p, _frame(), 30)
	mr.fit_attachment(ItemDatabase.get_attachment(&"scope_4x"))
	await _run(p, aim, 40)
	for i in 4:
		await get_tree().process_frame
	check_near(p.camera.fov, 75.0 / 4.0, 0.1, "4× zoom (FOV %.1f)" % p.camera.fov)
	check(mr.get_current_spread_degrees() < hip * 0.05, "scoped spread %.3f° vs hip %.2f°" % [mr.get_current_spread_degrees(), hip])
	check((hud.get_node("%ScopeOverlay") as Control).visible, "scope overlay shown")
	check(not (mr.get_node("%Model") as Node3D).visible, "gun model hidden behind the scope")
	await _run(p, _frame(), 30)
	await get_tree().process_frame
	check(not (hud.get_node("%ScopeOverlay") as Control).visible, "overlay gone when lowered")


func test_marksman_one_shots_a_raider_body() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.give_weapon(MARKSMAN)
	await _switch(p, 4)
	var h := _target(60.0, 80.0)
	var aim := _frame()
	aim.aim = true
	await _run(p, aim, 30)
	aim.fire = true
	await _run(p, aim, 1)
	check(h.is_dead(), "one .308 round kills an 80 HP raider at 60 m")


# ---------------------------------------------------------------- HUD, saves, input

func test_hud_weapon_strip() -> void:
	var p := _player()
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	await _run(p, _frame(), 3)
	await get_tree().process_frame
	var strip := hud.get_node("%WeaponStrip") as Label
	check(strip.text == "[1 RIFLE]   2 PISTOL   3 —   4 —   5 —", "strip: '%s'" % strip.text)
	p.give_weapon(SHOTGUN)
	await _switch(p, 3)
	await get_tree().process_frame
	check(strip.text == "1 RIFLE   2 PISTOL   [3 SHOTGUN]   4 —   5 —", "strip: '%s'" % strip.text)
	check((hud.get_node("%WeaponLabel") as Label).text == "PUMP SHOTGUN", "weapon name follows the switch")


func test_loadout_saved_and_loaded() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.give_weapon(SHOTGUN)
	await _switch(p, 3)
	p.weapon.ammo_in_magazine = 2
	p.weapon_slots.get_weapon(2).ammo_in_magazine = 7
	var data := JSON.parse_string(JSON.stringify(p.save_state())) as Dictionary
	var p2 := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p2.controlled_locally = false
	p2.position = Vector3(4, 0.05, 0)
	add_child(p2)
	await _run(p2, _frame(), 3)
	p2.load_state(data)
	check(p2.weapon_slots.get_weapon(3) != null and p2.weapon_slots.get_weapon(3).definition == SHOTGUN, "shotgun restored")
	check(p2.weapon.definition == SHOTGUN and p2.weapon_slots.current_slot == 3, "shotgun in hand")
	check(p2.weapon.ammo_in_magazine == 2 and p2.weapon_slots.get_weapon(2).ammo_in_magazine == 7, "magazines restored")
	# A save from before weapon slots: just the rifle's magazine
	var old := data.duplicate()
	old.erase("loadout")
	old["magazine"] = 9
	var p3 := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p3.controlled_locally = false
	p3.position = Vector3(-4, 0.05, 0)
	add_child(p3)
	await _run(p3, _frame(), 3)
	p3.load_state(old)
	check(p3.weapon.definition == RIFLE and p3.weapon.ammo_in_magazine == 9, "old saves still load (rifle magazine 9)")
	p3.load_state({"loadout": {"weapons": [{"id": "nonsense"}], "equipped": 99}})
	check(p3.weapon != null and p3.weapon_slots.owned().size() == 2, "a bad loadout never leaves you unarmed")


func test_respawn_restocks_every_gun() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.inventory.take_ammo(&"pistol_9mm", 36)
	p.weapon_slots.get_weapon(2).ammo_in_magazine = 0
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	check(p.inventory.count_ammo(&"pistol_9mm") == PISTOL.starting_reserve and p.weapon_slots.get_weapon(2).ammo_in_magazine == 12, "pistol topped up on respawn")
	check(p.weapon.visible, "gun in hand after respawn")


func test_input_frame_slot_validation() -> void:
	var f := InputFrame.new()
	f.slot = 3
	f.cycle = -1
	var back := InputFrame.from_dict(f.to_dict())
	check(back.slot == 3 and back.cycle == -1, "slot and cycle survive the round trip")
	for bad in [{"w": 9}, {"w": -2}, {"w": 2.5}, {"w": "4"}, {"y": 5}, {"y": NAN}]:
		var g := InputFrame.from_dict(bad)
		check(g.slot == 0 and g.cycle == 0, "rejected: %s" % [bad])
	for i in range(1, 5):
		var e := InputEventKey.new()
		e.physical_keycode = KEY_1 + i - 1
		e.pressed = true
		check(InputMap.event_is_action(e, "weapon_%d" % i), "key %d selects slot %d" % [i, i])


func test_iron_sights_line_up() -> void:
	var p := _player()
	await _run(p, _frame(), 3)
	p.give_weapon(SHOTGUN)
	for slot in [2, 3]:
		await _switch(p, slot)
		var aim := _frame()
		aim.aim = true
		await _run(p, aim, 30)
		for i in 90:
			await get_tree().process_frame
			await get_tree().physics_frame
		var to_cam := p.camera.global_transform.affine_inverse()
		var anchor := to_cam * (p.weapon.get_node("%SightAnchor") as Node3D).global_position
		check(absf(anchor.x) < 0.002 and absf(anchor.y) < 0.002, "%s: rear sight on the centre line (%s)" % [p.weapon.definition.id, anchor])
		var front_name := "FrontDot" if slot == 2 else "Bead"
		var front := to_cam * (p.weapon.get_node(("%IronSights/" if slot == 2 else "Model/") + front_name) as Node3D).global_position
		check(absf(front.x) < 0.003 and absf(front.y) < 0.006, "%s: front sight lines up too (%s)" % [p.weapon.definition.id, front])
		await _run(p, _frame(), 20)
