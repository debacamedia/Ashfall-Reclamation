extends "res://tests/test_case.gd"
## Increment 11: the machete + pipe pistol start, gun parts, crafting guns
## at the weapons bench, attachments (fit/remove at a bench, effects,
## models, saving), the Modify Weapons tab and the first-minutes hint.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WEAPONS_BENCH := preload("res://scenes/world/stations/weapons_bench.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DT := 1.0 / 60.0
const W := "res://resources/items/weapons/"

var RIFLE: WeaponDefinition = load(W + "service_rifle.tres")
var PISTOL: WeaponDefinition = load(W + "pistol.tres")
var PIPE: WeaponDefinition = load(W + "pipe_pistol.tres")
var MACHETE: WeaponDefinition = load(W + "machete.tres")
var MARKSMAN: WeaponDefinition = load(W + "scoped_rifle.tres")
var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var PIPE_R: RecipeDefinition = load("res://resources/recipes/craft_pipe_pistol.tres")
var PISTOL_R: RecipeDefinition = load("res://resources/recipes/craft_pistol.tres")

const PARTS := ["gun_barrel", "gun_receiver", "gun_stock", "trigger_group", "gun_magazine"]
const ATTACHMENTS := ["red_dot", "scope_4x", "suppressor", "extended_mag", "foregrip"]


## A player with the real (Increment 11) start: machete + scrap.
func _player(at := Vector3(0, 0.05, 0)) -> PlayerController:
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
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


func _item(id: String) -> ItemDefinition:
	return ItemDatabase.get_item(StringName(id))


func _look_at(p: PlayerController, point: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


## Player using a weapons bench 1.6 m in front (opened with E).
func _at_bench(p: PlayerController) -> CraftingStation:
	var bench := WEAPONS_BENCH.instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.6)
	add_child(bench)
	await _run(p, 3)
	_look_at(p, bench.get_focus_point())
	await _run(p, 2)
	var e := InputFrame.new()
	e.interact = true
	await _run(p, 1, e)
	await _run(p, 1)
	return bench


func _target(distance: float, hp := 1000.0) -> HealthComponent:
	var root := Node3D.new()
	add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.NPCS
	body.position = Vector3(0, 1.4, -distance)
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.4)
	shape.shape = box
	body.add_child(shape)
	var h := HealthComponent.new()
	h.max_health = hp
	root.add_child(h)
	return h


# ---------------------------------------------------------------- data

func test_parts_attachments_and_recipes_are_valid() -> void:
	for id in PARTS:
		var item := _item(id)
		check(item != null and item.category == ItemDefinition.Category.PART, "%s is a part" % id)
		if item != null:
			check(item.icon != null and item.world_model != null, "%s has an icon and model" % id)
			check(not RecipeDatabase.recipes_for(item).is_empty(), "%s can be crafted" % id)
	for id in ATTACHMENTS:
		var item := _item(id)
		check(item != null and item.category == ItemDefinition.Category.ATTACHMENT and item.attachment != null, "%s is an attachment" % id)
		if item == null or item.attachment == null:
			continue
		var a := item.attachment
		check(ItemDatabase.get_attachment(a.id) == a and ItemDatabase.find_attachment_item(a.id) == item, "%s registered" % id)
		check(item.icon != null and item.world_model != null, "%s has an icon and model" % id)
		check(not a.compatible.is_empty(), "%s fits something" % id)
		check(not RecipeDatabase.recipes_for(item).is_empty(), "%s can be crafted" % id)
		if a.model_path != "":
			var m := (load(a.model_path) as PackedScene).instantiate()
			check(a.slot != AttachmentDefinition.Slot.OPTIC or m.get_node_or_null("Sight") != null, "%s optic has a Sight marker" % id)
			m.free()
		# Every gun it fits has a mount for it
		for gun_id in a.compatible:
			var def := ItemDatabase.get_weapon(gun_id)
			check(def != null, "%s: %s is a gun" % [id, gun_id])
			if def == null or a.slot == AttachmentDefinition.Slot.MAGAZINE:
				continue
			var w := def.instantiate_weapon()
			var mount := ["%OpticMount", "%MuzzleMount", "", "%UnderMount"][a.slot] as String
			check(w.get_node_or_null(mount) != null, "%s has a %s for the %s" % [gun_id, mount, id])
			w.free()
	for path in ["pipe_pistol_item", "pistol_item", "shotgun_item", "service_rifle_item", "scoped_rifle_item"]:
		var gun := load(W + path + ".tres") as ItemDefinition
		var recipes := RecipeDatabase.recipes_for(gun)
		check(recipes.size() == 1, "%s: one recipe" % gun.id)
		if recipes.size() == 1:
			var r := recipes[0]
			check(r.station == (RecipeDefinition.Station.HAND if gun.id == &"pipe_pistol" else RecipeDefinition.Station.WEAPONS_BENCH),
				"%s made at the right place" % gun.id)
	check(MACHETE.melee and MACHETE.slot == 5 and MACHETE.tier == 0, "machete: melee, slot 5")
	check(PIPE.slot == 2 and PIPE.tier < PISTOL.tier and RIFLE.tier > PISTOL.tier, "tiers: pipe < pistol < rifle")


# ---------------------------------------------------------------- start

func test_new_start_is_a_machete_and_scrap() -> void:
	var p := _player()
	await _run(p, 3)
	var owned := p.weapon_slots.owned()
	check(owned.size() == 1 and owned[0].definition == MACHETE, "only a machete")
	check(p.weapon == owned[0] and p.weapon_slots.current_slot == 5, "machete in hand (slot 5)")
	check(p.inventory.count_of(&"scrap_metal") == 4 and p.inventory.count_of(&"cloth") == 2, "4 scrap, 2 cloth")
	check(p.inventory.count_of(&"pistol_ammo") == 12 and p.inventory.count_of(&"medkit") == 1, "12 pistol rounds and a medkit")
	check(p.craft_refusal_reason(PIPE_R) == "Missing 1 Wood", "pipe pistol just needs wood: '%s'" % p.craft_refusal_reason(PIPE_R))
	var aim := InputFrame.new()
	aim.aim = true
	await _run(p, 20, aim)
	check(p.aim_amount == 0.0, "no aiming down a machete")
	var r := InputFrame.new()
	r.reload = true
	await _run(p, 1, r)
	check(not p.weapon.is_reloading, "nothing to reload")


func test_machete_hits_up_close_only() -> void:
	var p := _player()
	await _run(p, 3)
	var near := _target(1.3)
	var swing := InputFrame.new()
	swing.fire = true
	var hits := []
	p.weapon.hit_confirmed.connect(func(_t: Node, dmg: float, _k: bool, _z: float) -> void: hits.append(dmg))
	await _run(p, 1, swing)
	check_near(near.max_health - near.current_health, 40.0, 0.01, "40 damage up close")
	check(hits.size() == 1, "one hit marker")
	await _run(p, 50, swing)  # held: swings again at 85 per minute (0.7 s)
	check(near.max_health - near.current_health >= 80.0, "holding the button keeps swinging")
	near.get_parent().queue_free()
	await _run(p, 50)
	var far := _target(3.0)
	await _run(p, 1, swing)
	check(far.current_health == far.max_health, "out of reach at 3 m")
	check(p.weapon.ammo_in_magazine == 0 and p.weapon.reserve_ammo == 0, "uses no ammo")


func test_pipe_pistol_crafted_by_hand() -> void:
	var p := _player()
	await _run(p, 3)
	p.inventory.add_item(WOOD, 1)
	var got := []
	p.weapon_picked_up.connect(func(d: WeaponDefinition) -> void: got.append(d.id))
	check(p.request_craft(PIPE_R), "craft started anywhere (by hand)")
	await _run(p, int(PIPE_R.craft_time * 60.0) + 5)
	check(got == [&"pipe_pistol"], "pipe pistol made")
	check(p.inventory.count_of(&"scrap_metal") == 0 and p.inventory.count_of(&"wood") == 0, "scrap and wood used")
	check(p.weapon_slots.get_weapon(2) != null and p.weapon_slots.get_weapon(2).definition == PIPE, "in slot 2")
	await _run(p, 60)
	check(p.weapon.definition == PIPE, "drawn straight away (you only had a machete)")
	check(p.weapon.ammo_in_magazine == 1 and p.weapon.reserve_ammo == 12, "1 in the pipe, 12 in the pack")
	var h := _target(8.0)
	var fire := InputFrame.new()
	fire.fire = true
	await _run(p, 1, fire)
	check_near(h.max_health - h.current_health, 35.0, 0.01, "35 damage")
	check(p.weapon.ammo_in_magazine == 0, "single shot")
	check(p.request_craft(PIPE_R) == false, "can't make a second one")


func test_parts_make_a_pistol_at_the_weapons_bench() -> void:
	var p := _player()
	await _run(p, 3)
	p.give_weapon(PIPE)
	for id in ["gun_receiver", "gun_barrel", "trigger_group", "gun_magazine"]:
		p.inventory.add_item(_item(id), 1)
	check(p.craft_refusal_reason(PISTOL_R) == "Needs a Weapons Bench", "not by hand")
	await _at_bench(p)
	check(p.get_crafting_station() == RecipeDefinition.Station.WEAPONS_BENCH, "at the weapons bench")
	check(p.request_craft(PISTOL_R), "pistol craft started")
	await _run(p, int(PISTOL_R.craft_time * 60.0) + 5)
	check(p.weapon_slots.get_weapon(2).definition == PISTOL, "pistol replaces the pipe pistol in slot 2")
	for id in ["gun_receiver", "gun_barrel", "trigger_group", "gun_magazine"]:
		check(p.inventory.count_of(StringName(id)) == 0, "%s used" % id)
	p.inventory.add_item(_item("scrap_metal"), 4)
	p.inventory.add_item(WOOD, 1)
	check(p.craft_refusal_reason(PIPE_R) == "Your Sidearm Pistol is better", "no downgrading: '%s'" % p.craft_refusal_reason(PIPE_R))


func test_part_recipes_turn_materials_into_parts() -> void:
	var p := _player()
	await _run(p, 3)
	p.inventory.add_item(_item("metal_pipe"), 2)
	await _at_bench(p)
	var r := RecipeDatabase.get_recipe(&"gun_barrel")
	check(p.request_craft(r), "barrel craft started")
	await _run(p, int(r.craft_time * 60.0) + 5)
	check(p.inventory.count_of(&"gun_barrel") == 1 and p.inventory.count_of(&"metal_pipe") == 0, "2 pipes → 1 barrel")


# ---------------------------------------------------------------- attachments

func test_attachment_effects_and_shared_definition_untouched() -> void:
	var w := RIFLE.instantiate_weapon()
	add_child(w)
	check(w.definition == RIFLE, "no attachments: the shared definition")
	w.fit_attachment(ItemDatabase.get_attachment(&"suppressor"))
	check(w.definition != RIFLE, "attachments: an effective copy")
	check_near(w.definition.noise_radius, RIFLE.noise_radius * 0.3, 0.01, "suppressor: heard at 30%")
	check_near(w.definition.damage, RIFLE.damage * 0.92, 0.01, "suppressor: 8% less damage")
	w.fit_attachment(ItemDatabase.get_attachment(&"foregrip"))
	check_near(w.definition.recoil_pitch, RIFLE.recoil_pitch * 0.9 * 0.7, 0.001, "foregrip + suppressor recoil")
	w.fit_attachment(ItemDatabase.get_attachment(&"red_dot"))
	check_near(w.definition.ads_zoom, RIFLE.ads_zoom * 1.15, 0.001, "red dot: a little more zoom")
	var old := w.fit_attachment(ItemDatabase.get_attachment(&"scope_4x"))
	check(old != null and old.id == &"red_dot", "scope replaces the red dot")
	check_near(w.definition.ads_zoom, 4.0, 0.001, "scope: 4×")
	check(w.definition.scope_overlay, "scope overlay")
	w.reserve_ammo = 10
	w.fit_attachment(ItemDatabase.get_attachment(&"extended_mag"))
	check(w.definition.magazine_size == 45, "extended magazine: 45 rounds")
	w.ammo_in_magazine = 45
	w.remove_attachment(AttachmentDefinition.Slot.MAGAZINE)
	check(w.ammo_in_magazine == 30 and w.reserve_ammo == 25, "removing it puts 15 rounds back in the pack")
	check(RIFLE.noise_radius > 50.0 and RIFLE.magazine_size == 30 and RIFLE.ads_zoom == 1.2 and not RIFLE.scope_overlay,
		"the shared rifle definition is unchanged")
	for slot in [AttachmentDefinition.Slot.OPTIC, AttachmentDefinition.Slot.MUZZLE, AttachmentDefinition.Slot.UNDERBARREL]:
		w.remove_attachment(slot)
	check(w.definition == RIFLE, "back to the shared definition when bare")


func test_attachment_models_and_iron_sights() -> void:
	var w := RIFLE.instantiate_weapon()
	add_child(w)
	var irons := w.get_node("%IronSights") as Node3D
	check(irons.visible and w.get_node("%OpticMount").get_child_count() == 0, "bare rifle: iron sights")
	w.fit_attachment(ItemDatabase.get_attachment(&"red_dot"))
	w.fit_attachment(ItemDatabase.get_attachment(&"suppressor"))
	w.fit_attachment(ItemDatabase.get_attachment(&"foregrip"))
	await get_tree().process_frame
	check(not irons.visible, "irons hidden under an optic")
	check(w.get_node("%OpticMount").get_child_count() == 1 and w.get_node("%MuzzleMount").get_child_count() == 1
		and w.get_node("%UnderMount").get_child_count() == 1, "optic, suppressor and grip models shown")
	check(w.get_sight_node().get_parent() == w.get_node("%OpticMount").get_child(0), "aiming uses the optic's sight")
	w.remove_attachment(AttachmentDefinition.Slot.OPTIC)
	await get_tree().process_frame
	check(irons.visible and w.get_node("%OpticMount").get_child_count() == 0, "irons back when the optic comes off")


func test_fit_and_remove_only_at_a_weapons_bench() -> void:
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await _run(p, 3)
	var red := _item("red_dot")
	var scope := _item("scope_4x")
	p.inventory.add_item(red, 1)
	p.inventory.add_item(scope, 1)
	var refused := []
	p.attachment_refused.connect(func(r: String) -> void: refused.append(r))
	check(not p.request_fit_attachment(1, red) and refused.back() == "Needs a Weapons Bench", "not in the field")
	await _at_bench(p)
	check(p.request_fit_attachment(1, red), "red dot fitted to the rifle")
	check(p.inventory.count_of(&"red_dot") == 0 and p.weapon_slots.get_weapon(1).get_attachment(AttachmentDefinition.Slot.OPTIC).id == &"red_dot", "item used")
	check(not p.request_fit_attachment(2, scope) and refused.back() == "Doesn't fit the Sidearm Pistol", "no scope on a pistol: %s" % refused.back())
	check(p.request_fit_attachment(1, scope), "scope swapped in")
	check(p.inventory.count_of(&"red_dot") == 1 and p.inventory.count_of(&"scope_4x") == 0, "red dot back in the bag")
	check(not p.request_fit_attachment(1, scope) and refused.back() == "You don't have a 4× Scope", "can't fit what you don't carry")
	check(p.request_remove_attachment(1, AttachmentDefinition.Slot.OPTIC), "scope removed")
	check(p.inventory.count_of(&"scope_4x") == 1 and p.weapon_slots.get_weapon(1).get_attachment(AttachmentDefinition.Slot.OPTIC) == null, "scope back in the bag")
	check(not p.request_remove_attachment(1, AttachmentDefinition.Slot.OPTIC) and refused.back() == "Nothing fitted there", "nothing to remove")


func test_attachments_saved_and_loaded() -> void:
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await _run(p, 3)
	var rifle := p.weapon_slots.get_weapon(1)
	rifle.fit_attachment(ItemDatabase.get_attachment(&"extended_mag"))
	rifle.fit_attachment(ItemDatabase.get_attachment(&"suppressor"))
	rifle.ammo_in_magazine = 40
	var json := JSON.new()
	check(json.parse(JSON.stringify(p.save_state())) == OK, "save is valid JSON")
	var data := json.data as Dictionary
	var p2 := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p2.controlled_locally = false
	p2.position = Vector3(4, 0.05, 0)
	add_child(p2)
	await _run(p2, 3)
	p2.load_state(data)
	var r2 := p2.weapon_slots.get_weapon(1)
	check(r2.get_attachment(AttachmentDefinition.Slot.MAGAZINE) != null and r2.get_attachment(AttachmentDefinition.Slot.MUZZLE) != null, "attachments restored")
	check(r2.definition.magazine_size == 45 and r2.ammo_in_magazine == 40, "40 of 45 in the extended magazine")
	# Nonsense attachment ids are ignored
	var bad := data.duplicate(true)
	bad["loadout"]["weapons"][0]["attachments"] = ["nonsense", "scope_4x", 7]
	p2.load_state(bad)
	r2 = p2.weapon_slots.get_weapon(1)
	check(r2.get_attachment(AttachmentDefinition.Slot.OPTIC) != null and r2.get_attachment(AttachmentDefinition.Slot.OPTIC).id == &"scope_4x",
		"valid ids kept, bad ones skipped")
	check(r2.get_attachment(AttachmentDefinition.Slot.MAGAZINE) == null, "load replaces what was fitted")


# ---------------------------------------------------------------- UI

func test_modify_weapons_tab() -> void:
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	p.inventory.add_item(_item("red_dot"), 1)
	await _at_bench(p)
	await get_tree().process_frame
	var cs := hud.crafting_screen
	check(cs.visible and (cs.get_node("%CraftTabs") as Control).visible, "bench screen open with tabs")
	(cs.get_node("%ModifyTab") as Button).pressed.emit()
	await get_tree().process_frame
	var gs := cs.get_node("%GunsmithPanel") as GunsmithPanel
	check(gs.visible and not (cs.get_node("%CraftBody") as Control).visible, "Modify Weapons tab shown")
	check((gs.get_node("%GunList") as Container).get_child_count() == 2, "rifle and pistol listed")
	check((gs.get_node("%GunTitle") as Label).text == "Service Rifle", "rifle selected")
	var fit: Button = null
	for row in gs.get_node("%AttachmentSlots").get_children():
		for c in row.get_children():
			if c is Button and (c as Button).text == "Fit Red Dot Sight":
				fit = c
	check(fit != null, "a Fit Red Dot Sight button")
	if fit != null:
		fit.pressed.emit()
		await get_tree().process_frame
		check(p.weapon_slots.get_weapon(1).get_attachment(AttachmentDefinition.Slot.OPTIC) != null, "fitted from the UI")
	(cs.get_node("%CraftTab") as Button).pressed.emit()
	check(not gs.visible and (cs.get_node("%CraftBody") as Control).visible, "back to recipes")


func test_first_minutes_hint() -> void:
	var p := _player()
	var hud := HUD_SCENE.instantiate() as HUD
	hud.player = p
	add_child(hud)
	await _run(p, 3)
	await get_tree().process_frame
	var hint := hud.get_node("%HintLabel") as Label
	check(hint.visible and hint.text.contains("pallet"), "hint: find wood (%s)" % hint.text)
	check((hud.get_node("%AmmoLabel") as Label).text == "—", "no ammo count for a machete")
	p.inventory.add_item(WOOD, 1)
	await get_tree().process_frame
	check(hint.text.contains("Press K"), "hint: craft it (%s)" % hint.text)
	p.give_weapon(PIPE)
	await get_tree().process_frame
	check(not hint.visible, "hint gone once you have a gun")
