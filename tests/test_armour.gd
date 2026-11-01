extends "res://tests/test_case.gd"
## Increment 22: clothing and armour from hides. Head, body and legs pieces
## of leather or plate that take a share off hits and wear down as they do;
## repaired at a workbench; Raw Hides tanned into Leather on a Tanning Rack;
## guards can wear it too.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WORKBENCH := preload("res://scenes/world/stations/workbench.tscn")
const AWAY := Vector3(520, 0.1, -180)
const DT := 1.0 / 60.0

var LEATHER: ItemDefinition = load("res://resources/items/leather.tres")
var HIDE: ItemDefinition = load("res://resources/items/raw_hide.tres")
var CAP: ItemDefinition = load("res://resources/items/leather_cap.tres")
var JACKET: ItemDefinition = load("res://resources/items/leather_jacket.tres")
var TROUSERS: ItemDefinition = load("res://resources/items/leather_trousers.tres")
var HELMET: ItemDefinition = load("res://resources/items/scrap_helmet.tres")
var VEST: ItemDefinition = load("res://resources/items/plated_vest.tres")
var PLATED_LEGS: ItemDefinition = load("res://resources/items/plated_trousers.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")


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


func _slot_of(p: PlayerController, item: ItemDefinition) -> int:
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == item:
			return i
	return -1


func _hit(p: PlayerController, amount: float, type := DamageInfo.Type.MELEE) -> float:
	var before := p.health.current_health
	p.health.apply_damage(DamageInfo.create(amount, type))
	return before - p.health.current_health


# ---------------------------------------------------------------- the pieces

func test_the_pieces() -> void:
	var by_slot := {1: [], 2: [], 3: []}
	for it in [CAP, JACKET, TROUSERS, HELMET, VEST, PLATED_LEGS]:
		check(it.is_armour() and it.max_stack == 1 and it.icon != null and it.world_model != null, "%s: something to wear, with an icon" % it.display_name)
		by_slot[it.armour_slot].append(it)
		var r := RecipeDatabase.get_recipe(it.id)
		check(r != null and r.station == RecipeDefinition.Station.WORKBENCH and r.inputs.has(LEATHER), "%s: made from leather at a workbench" % it.display_name)
	check(by_slot[1].size() == 2 and by_slot[2].size() == 2 and by_slot[3].size() == 2, "two for each of head, body and legs")
	check(VEST.armour_protection > JACKET.armour_protection and VEST.armour_speed < 1.0 and JACKET.armour_speed == 1.0, "plate protects more, and slows you")
	check(HELMET.armour_protection + VEST.armour_protection + PLATED_LEGS.armour_protection <= ArmourSet.MAX_PROTECTION, "a full set of plate: %d%%" % roundi((HELMET.armour_protection + VEST.armour_protection + PLATED_LEGS.armour_protection) * 100))
	check(JACKET.armour_repair == {&"leather": 1} and VEST.armour_repair == {&"scrap_metal": 2}, "leather mends leather, scrap mends plate")
	var tables := 0
	for f in DirAccess.get_files_at("res://resources/loot"):
		if f.ends_with(".tres") and (load("res://resources/loot/" + f) as LootTable).entries.any(func(e: LootEntry) -> bool: return e.item == LEATHER):
			tables += 1
	check(tables >= 4, "leather to find in %d loot tables" % tables)
	check(SettlementPlans.placeable().has(&"tanning_rack"), "a Tanning Rack to plan in build mode")


# ---------------------------------------------------------------- wearing

func test_armour_cuts_hits_and_wears_down() -> void:
	var p := _player()
	await _run(p, 2)
	check(is_equal_approx(_hit(p, 20.0), 20.0), "nothing on: the whole hit")
	p.health.revive(1.0)
	p.inventory.add_item(JACKET, 1)
	p.inventory.add_item(HELMET, 1)
	check(p.request_wear_armour(_slot_of(p, JACKET)) and p.request_wear_armour(_slot_of(p, HELMET)), "put on a jacket and a helmet")
	check(p.inventory.count_of(&"leather_jacket") == 0 and p.armour.worn(ArmourSet.BODY) == JACKET, "off the grid and worn")
	check_near(p.armour.protection(), 0.26, 0.001, "26% off hits")
	check_near(_hit(p, 20.0), 20.0 * 0.74, 0.01, "a machete: 14.8 gets through")
	check_near(_hit(p, 20.0, DamageInfo.Type.BALLISTIC), 20.0 * 0.74, 0.01, "a bullet too")
	check(is_equal_approx(_hit(p, 10.0, DamageInfo.Type.FALL), 10.0), "not a fall")
	check(p.armour.condition(ArmourSet.BODY) < 1.0, "the jacket's wearing (%.0f%% left)" % (p.armour.condition(ArmourSet.BODY) * 100))
	# Wear it right out
	var worn := []
	p.armour_worn_out.connect(func(it: ItemDefinition) -> void: worn.append(it))
	for i in 60:
		p.health.revive(1.0)
		_hit(p, 30.0)
	check(p.armour.is_worn_out(ArmourSet.BODY) and worn.has(JACKET), "the jacket's worn out, and you're told")
	p.health.revive(1.0)
	var gets := _hit(p, 20.0)
	check(p.armour.is_worn_out(ArmourSet.HEAD) or is_equal_approx(gets, 20.0 * (1.0 - HELMET.armour_protection)), "only what's not worn out protects (%.1f)" % gets)


func test_plate_slows_you() -> void:
	var p := _player()
	await _run(p, 2)
	var walk := InputFrame.new()
	walk.move = Vector2(0, -1)
	await _run(p, 40, walk)
	var free := Vector2(p.velocity.x, p.velocity.z).length()
	p.inventory.add_item(VEST, 1)
	p.inventory.add_item(PLATED_LEGS, 1)
	p.request_wear_armour(_slot_of(p, VEST))
	p.request_wear_armour(_slot_of(p, PLATED_LEGS))
	await _run(p, 40, walk)
	var plated := Vector2(p.velocity.x, p.velocity.z).length()
	check_near(plated / free, 0.94 * 0.97, 0.02, "plated: %.0f%% of your speed" % (plated / free * 100))


func test_swapping_and_taking_off_keep_the_wear() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(JACKET, 1)
	p.inventory.add_item(VEST, 1)
	p.request_wear_armour(_slot_of(p, JACKET))
	_hit(p, 40.0)
	var left := p.armour.wear_left(ArmourSet.BODY)
	check(left < JACKET.armour_durability, "a worn jacket (%.1f)" % left)
	p.request_wear_armour(_slot_of(p, VEST))
	check(p.armour.worn(ArmourSet.BODY) == VEST and p.inventory.count_of(&"leather_jacket") == 1, "the vest on, the jacket back in the grid")
	p.request_wear_armour(_slot_of(p, JACKET))
	check_near(p.armour.wear_left(ArmourSet.BODY), left, 0.001, "the jacket back on, as worn as it was")
	check(p.request_take_off_armour(ArmourSet.BODY) and p.armour.worn(ArmourSet.BODY) == null and p.inventory.count_of(&"leather_jacket") == 1, "taken off")
	var said := []
	p.armour_refused.connect(func(r: String) -> void: said.append(r))
	check(not p.request_take_off_armour(ArmourSet.HEAD) and said.back() == "Nothing worn there", "nothing on your head: %s" % [said])
	# Data in, data out
	p.request_wear_armour(_slot_of(p, JACKET))
	var data := p.save_state()
	p.armour.clear()
	p.armour_wear_kept.clear()
	p.load_state(data)
	check(p.armour.worn(ArmourSet.BODY) == JACKET and is_equal_approx(p.armour.wear_left(ArmourSet.BODY), left), "saved and loaded, wear and all")
	check(p.inventory.count_of(&"plated_vest") == 1, "the vest still in the backpack")
	data.erase("armour")
	p.load_state(data)
	check(p.armour.is_empty(), "an older save: nothing worn")


func test_repair_at_a_workbench() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(JACKET, 1)
	p.inventory.add_item(HELMET, 1)
	p.request_wear_armour(_slot_of(p, JACKET))
	p.request_wear_armour(_slot_of(p, HELMET))
	var said := []
	p.armour_refused.connect(func(r: String) -> void: said.append(r))
	check(not p.request_repair_armour() and said.back() == "Nothing you wear needs repairing", "nothing to mend yet")
	for i in 5:
		_hit(p, 15.0)
		p.health.revive(1.0)
	check(p.armour_repair_cost() == {&"leather": 1, &"scrap_metal": 2}, "mending costs %s" % p.armour_repair_cost())
	check(not p.request_repair_armour() and said.back() == "Repair it at a workbench", "away from a bench: %s" % said.back())
	var bench := WORKBENCH.instantiate() as CraftingStation
	bench.position = Vector3(0, 0, -1.6)
	add_child(bench)
	await _run(p, 3)
	check(p.near_workbench(), "at a workbench")
	check(not p.request_repair_armour() and said.back().begins_with("Needs "), "without the leather: %s" % said.back())
	p.inventory.add_item(LEATHER, 1)
	p.inventory.add_item(SCRAP, 3)
	check(p.request_repair_armour(), "repaired")
	check(p.armour.condition(ArmourSet.BODY) == 1.0 and p.armour.condition(ArmourSet.HEAD) == 1.0, "both as good as new")
	check(p.inventory.count_of(&"leather") == 0 and p.inventory.count_of(&"scrap_metal") == 1, "a leather and 2 scrap used")


func test_dying_drops_what_you_wear() -> void:
	var p := _player()
	await _run(p, 2)
	p.inventory.add_item(JACKET, 1)
	p.request_wear_armour(_slot_of(p, JACKET))
	_hit(p, 50.0)
	var left := p.armour.wear_left(ArmourSet.BODY)
	var world := Node3D.new()
	add_child(world)
	var cache := DeathCache.drop_for(p, world, p.global_position)
	check(cache != null and (cache.get_node("%Inventory") as InventoryComponent).count_of(&"leather_jacket") == 1, "the jacket's in your gear")
	check(p.armour.is_empty(), "and off you")
	var inv := cache.get_node("%Inventory") as InventoryComponent
	p.inventory.add_item(JACKET, 1)
	inv.remove_item(&"leather_jacket", 1)
	p.request_wear_armour(_slot_of(p, JACKET))
	check_near(p.armour.wear_left(ArmourSet.BODY), left, 0.001, "picked back up, as worn as it was")
	world.queue_free()


# ---------------------------------------------------------------- at the farm

func _claimed(zone: Node3D) -> Settlement:
	var st := zone.get_node("AshCreekFarms/Settlement") as Settlement
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	st.next_raid_in = 9999.0
	return st


func _newcomer(zone: Node3D, st: Settlement, role: Settler.Role) -> Settler:
	var p := zone.get_node("Player") as PlayerController
	var back := p.global_position
	p.global_position = AWAY
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	st.request_set_role(p, s, role)
	return s


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func test_the_tanning_rack() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_armour"
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := zone.get_node("Player") as PlayerController
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var xf := site_root.global_transform * Transform3D(Basis(), Vector3(20, 0, 24))
	p.global_position = xf.origin + site_root.global_basis * Vector3(0, 0.1, 6)
	await wait_physics(3)
	var site := p.request_place_site(&"tanning_rack", xf)
	check(site != null, "planned (%s)" % p.site_refusal_reason(&"tanning_rack", xf))
	var inv := InventoryComponent.new()
	inv.slot_count = 20
	inv.max_weight = 0.0
	add_child(inv)
	for id: StringName in site.missing():
		inv.add_item(ItemDatabase.get_item(id), site.missing()[id])
	site.take_from(inv)
	site.add_work(site.total_hours())
	inv.queue_free()
	await wait_physics(3)
	check(st.tanning_racks().size() == 1, "a Tanning Rack built")
	var rack := st.tanning_racks()[0]
	var tub := rack.rack.inventory
	check(tub.slot_count == 6 and rack.rack.get_prompt(p).length() > 0, "with a tub to put hides in")
	tub.add_item(HIDE, 2)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	st.simulate(3.9)
	check(tub.count_of(&"raw_hide") == 2 and tub.count_of(&"leather") == 0, "not yet, at 3.9 hours")
	st.simulate(0.2)
	check(tub.count_of(&"raw_hide") == 1 and tub.count_of(&"leather") == 3, "4 hours: a hide is 3 Leather")
	check(said.has("A hide is tanned: 3 Leather in the tanning tub"), "a notice: %s" % [said])
	st.simulate(1.0)
	check(saves.save_game("armour", zone) == OK, "saved, a quarter of the way through the next")
	await _free(zone)
	var zone2 := await load_zone()
	saves.load_game("armour", zone2)
	await wait_physics(4)
	var st2 := zone2.get_node("AshCreekFarms/Settlement") as Settlement
	var rack2 := st2.tanning_racks()[0]
	check(absf(rack2.tan_progress - 0.25) < 0.05 and rack2.rack.inventory.count_of(&"leather") == 3, "the tub and the hide's progress came back (%.2f)" % rack2.tan_progress)
	st2.simulate(3.0)
	check(rack2.rack.inventory.count_of(&"leather") == 6 and rack2.rack.inventory.count_of(&"raw_hide") == 0, "the second hide done: 6 Leather")
	await _free(zone2)


func test_guards_wear_armour() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := zone.get_node("Player") as PlayerController
	var g := await _newcomer(zone, st, Settler.Role.GUARD)
	p.inventory.add_item(VEST, 1)
	p.inventory.add_item(CAP, 1)
	check(st.request_give_armour(p, g, _player_slot(p, VEST)), "a vest for the guard")
	check(g.armour.worn(ArmourSet.BODY) == VEST and p.inventory.count_of(&"plated_vest") == 0, "worn, out of your backpack")
	check((g.visual.get_node("ArmourBody") as Node3D).visible and not (g.visual.get_node("Vest") as Node3D).visible, "you can see it on them")
	var before := g.health.current_health
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	zone.add_child(r)
	r.global_position = AWAY
	g.health.apply_damage(DamageInfo.create(20.0, DamageInfo.Type.MELEE, r))
	check_near(before - g.health.current_health, 20.0 * (1.0 - VEST.armour_protection), 0.01, "it takes a share off a raider's hit")
	r.queue_free()
	# On paper too
	var stopped_before := g.armour.wear_left(ArmourSet.BODY)
	st.warn_raid(0.0)
	st.raid_size = 2
	st.settle_raid_on_paper(3)
	check(g.armour.wear_left(ArmourSet.BODY) < stopped_before, "a raid settled on paper wears it too: the unarmed guard fought hand to hand (%.0f → %.0f)" % [stopped_before, g.armour.wear_left(ArmourSet.BODY)])
	if g.is_down():
		g.help_up(1.0)
	# Taken back; the armory dresses guards with nothing on
	check(st.request_take_armour(p, g) and g.armour.is_empty() and p.inventory.count_of(&"plated_vest") == 1, "taken back")
	st.armory.inventory.add_item(TROUSERS, 1)
	st.armory.inventory.add_item(PLATED_LEGS, 1)
	st._supply_guards()
	check(g.armour.worn(ArmourSet.LEGS) == PLATED_LEGS and st.armory.inventory.count_of(&"leather_trousers") == 1, "the guard takes the best legs from the armory")
	await _free(zone)


func _player_slot(p: PlayerController, item: ItemDefinition) -> int:
	return _slot_of(p, item)
