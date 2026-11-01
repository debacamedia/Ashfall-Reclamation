extends "res://tests/test_case.gd"
## Increment 21.5: a Kitchen and a Cook, pens and a Rancher. The Cook turns
## wood into planks for the stove and the farm's vegetables, meat and eggs
## into dishes in the fridge, which settlers eat first; the Rancher feeds the
## animals, collects eggs and butchers the spares; you can cook in the
## kitchen and butcher an animal yourself.

const AWAY := Vector3(520, 0.1, -180)

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var MEAT: ItemDefinition = load("res://resources/items/raw_meat.tres")
var EGG: ItemDefinition = load("res://resources/items/egg.tres")
var HIDE: ItemDefinition = load("res://resources/items/raw_hide.tres")
var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var VSTEW: ItemDefinition = load("res://resources/items/vegetable_stew.tres")
var MSTEW: ItemDefinition = load("res://resources/items/meat_stew.tres")


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	st.next_raid_in = 9999.0
	return st


func _newcomer(zone: Node3D, role: Settler.Role) -> Settler:
	var st := _farm(zone)
	var p := _player(zone)
	var back := p.global_position
	p.global_position = AWAY
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	st.request_set_role(p, s, role)
	return s


func _finish(site: ConstructionSite) -> void:
	var inv := InventoryComponent.new()
	inv.slot_count = 40
	inv.max_weight = 0.0
	add_child(inv)
	for id: StringName in site.missing():
		inv.add_item(ItemDatabase.get_item(id), site.missing()[id])
	site.take_from(inv)
	site.add_work(site.total_hours())
	inv.queue_free()
	await wait_physics(3)


## Plans `plan` at `local` in the farm and builds it.
func _build(zone: Node3D, plan: StringName, local: Vector3) -> SettlementBuilding:
	var st := _farm(zone)
	var p := _player(zone)
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var xf := site_root.global_transform * Transform3D(Basis(), local)
	var back := p.global_position
	p.global_position = xf.origin + site_root.global_basis * Vector3(0, 0.1, 10)
	await wait_physics(3)
	var site := p.request_place_site(plan, xf)
	check(site != null, "planned a %s (%s)" % [plan, p.site_refusal_reason(plan, xf)])
	if site == null:
		return null
	await wait_physics(2)
	await _finish(site)
	p.global_position = back
	await wait_physics(2)
	var found: SettlementBuilding = null
	for n in zone.get_node("Structures").get_children():
		if n is SettlementBuilding and (n as SettlementBuilding).definition.id == SettlementPlans.PLANS[plan]["structure"] and not n.is_queued_for_deletion():
			found = n
	return found


func _clear_stores(st: Settlement) -> void:
	for s in st.stores():
		s.inventory.clear()


# ---------------------------------------------------------------- what there is

func test_the_new_buildings_and_food() -> void:
	for id: StringName in [&"kitchen", &"chicken_coop", &"pig_pen", &"cow_pasture"]:
		check(SettlementPlans.placeable().has(id), "%s can be planned in build mode" % id)
		var def := SettlementPlans.structure(id)
		check(def != null and ResourceLoader.exists(def.scene_path), "%s: a scene" % id)
	var k := (load(SettlementPlans.structure(&"kitchen").scene_path) as PackedScene).instantiate() as SettlementBuilding
	add_child(k)
	await wait_physics(2)
	check(k.is_kitchen() and k.fridge.inventory.slot_count == 30 and k.cook_spots().size() == 1, "the kitchen: a 30-slot fridge and a place to cook")
	var stove := k.get_node("Stove") as CraftingStation
	check(stove != null and stove.station == RecipeDefinition.Station.STOVE, "with a stove you can cook at")
	k.queue_free()
	for spec in [[&"chicken_coop", &"chicken", 8], [&"pig_pen", &"pig", 6], [&"cow_pasture", &"cow", 4]]:
		var pen := (load(SettlementPlans.structure(spec[0]).scene_path) as PackedScene).instantiate() as SettlementBuilding
		check(pen.animal_kind == spec[1] and pen.animal_capacity == spec[2] and pen.has_node("AnimalArea") and pen.has_node("TendSpots"), "%s: room for %d %ss" % [spec[0], spec[2], spec[1]])
		pen.free()
	check(Settlement.butcher_yield(&"chicken") == {&"raw_meat": 2}, "a chicken: 2 meat")
	check(Settlement.butcher_yield(&"pig") == {&"raw_meat": 5}, "a pig: 5 meat")
	check(Settlement.butcher_yield(&"cow") == {&"raw_meat": 8, &"raw_hide": 1}, "a cow: 8 meat and a hide")
	# Cooking: every recipe on a stove (or workbench) burns a plank
	for rid in [&"vegetable_stew", &"meat_stew", &"cooked_meat", &"fried_eggs"]:
		var r := RecipeDatabase.get_recipe(rid)
		check(r != null and r.station == RecipeDefinition.Station.STOVE and r.inputs.get(PLANK) == 1 and r.output.settler_meals > 0.0, "%s: cooked over a plank" % rid)
	check(MSTEW.settler_meals == 5.0 and VSTEW.settler_meals == 4.0, "a meat stew feeds five, a vegetable stew four")
	check(MEAT.food_value == 0.0 and EGG.food_value == 0.0 and HIDE.category == ItemDefinition.Category.RESOURCE, "raw meat and eggs need cooking; the hide's for later")
	check(Settlement.cook_recipes()[0].output == MSTEW, "the Cook's first choice: meat stew")


# ---------------------------------------------------------------- jobs

func test_cook_and_rancher_need_their_buildings() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var s := await _newcomer(zone, Settler.Role.FARMER)
	var said := []
	st.refused.connect(func(r: String) -> void: said.append(r))
	var p := _player(zone)
	check(not st.request_set_role(p, s, Settler.Role.COOK) and said.back().begins_with("Build a Kitchen first"), "no kitchen, no cook: %s" % [said])
	check(not st.request_set_role(p, s, Settler.Role.RANCHER) and said.back().begins_with("Build a Chicken Coop, Pig Pen or Cow Pasture first"), "no pen, no rancher")
	await _build(zone, &"kitchen", Vector3(20, 0, 24))
	check(st.kitchens().size() == 1, "a kitchen built")
	check(st.request_set_role(p, s, Settler.Role.COOK) and s.role == Settler.Role.COOK and s.role_name() == "Cook", "now a cook")
	await _free(zone)


func test_the_cook_fills_the_fridge() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var kitchen := await _build(zone, &"kitchen", Vector3(20, 0, 24))
	var cook := await _newcomer(zone, Settler.Role.COOK)
	check(cook.role == Settler.Role.COOK, "hired")
	_clear_stores(st)
	st.store.inventory.add_item(VEG, 16)
	st.store.inventory.add_item(MEAT, 2)
	st.store.inventory.add_item(WOOD, 2)  # no planks: they cut them
	st.simulate(1.0)
	var f := kitchen.fridge.inventory
	check(f.count_of(&"meat_stew") == 2, "an hour: two meat stews in the fridge (%d)" % f.count_of(&"meat_stew"))
	check(st.store.inventory.count_of(&"raw_meat") == 0 and st.store.inventory.count_of(&"vegetables") == 12, "the meat and 4 vegetables went in")
	check(st.store.inventory.count_of(&"wood") == 1 and st.store.inventory.count_of(&"wood_plank") == 0, "a piece of wood cut into 2 planks, both burned")
	st.store.inventory.add_item(WOOD, 4)
	st.simulate(1.0)
	check(f.count_of(&"vegetable_stew") == 0 and cook.status_text().begins_with("Nothing to cook"), "10 vegetables are left for the animals: %s" % cook.status_text())
	st.store.inventory.add_item(VEG, 6)
	st.store.inventory.add_item(EGG, 4)
	st.simulate(1.0)
	check(f.count_of(&"vegetable_stew") == 2, "then vegetable stews (%d)" % f.count_of(&"vegetable_stew"))
	st.simulate(1.0)
	check(f.count_of(&"fried_eggs") == 2, "and fried eggs (%d)" % f.count_of(&"fried_eggs"))
	check(st.fridge_meals() >= 2 * 5 + 2 * 4 + 2 * 2 - 2, "%.0f meals waiting (the cook eats too)" % st.fridge_meals())
	# No fuel at all
	for sto in st.stores():
		sto.inventory.remove_item(&"wood", 99)
		sto.inventory.remove_item(&"wood_plank", 99)
	st.store.inventory.add_item(VEG, 20)
	st.simulate(1.0)
	check(cook.status_text() == "No planks or wood for the stove", "nothing to burn: %s" % cook.status_text())
	await _free(zone)


func test_settlers_eat_cooked_food_first() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var kitchen := await _build(zone, &"kitchen", Vector3(20, 0, 24))
	var a := await _newcomer(zone, Settler.Role.FARMER)
	var b := await _newcomer(zone, Settler.Role.FARMER)
	_clear_stores(st)
	st.store.inventory.add_item(VEG, 10)
	st.water = 100.0
	kitchen.fridge.inventory.add_item(VSTEW, 1)
	for s in [a, b]:
		s.next_meal = 0.01
	st.simulate(0.05)
	check(kitchen.fridge.inventory.count_of(&"vegetable_stew") == 0 and st.food() == 10, "two meals from one stew: no vegetables eaten")
	check_near(st.fridge_meals(), 2.0, 0.01, "and two more meals of it left (%.1f)" % st.fridge_meals())
	for s in [a, b]:
		s.next_meal = 0.01
	st.simulate(0.05)
	check(st.food() == 10 and st.fridge_meals() < 0.01, "the rest of the stew")
	for s in [a, b]:
		s.next_meal = 0.01
	st.simulate(0.05)
	check(st.food() == 8, "then vegetables again")
	await _free(zone)


# ---------------------------------------------------------------- animals

func test_a_coop_its_chickens_and_the_rancher() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	var coop := await _build(zone, &"chicken_coop", Vector3(22, 0, 24))
	st.simulate(0.1)
	await wait_physics(3)
	check(coop.count() == 2 and coop.animals().size() == 2, "a pair of chickens arrives")
	check(said.any(func(t: String) -> bool: return t == "A pair of chickens has arrived at the chicken coop"), "a notice: %s" % [said])
	var hen := coop.animals()[0]
	var area := coop.get_node("AnimalArea") as Node3D
	var local := area.global_transform.affine_inverse() * hen.global_position
	check(absf(local.x) <= 3.5 and absf(local.z) <= 2.5, "inside the coop (%s)" % local)
	_clear_stores(st)
	st.store.inventory.add_item(VEG, 30)
	# Nobody to feed them: nothing happens
	st.simulate(24.0)
	check(coop.count() == 2 and st.store.inventory.count_of(&"egg") == 0 and st.food() == 30, "no rancher: no eggs, no chicks, no feed used")
	var r := await _newcomer(zone, Settler.Role.RANCHER)
	check(r.role == Settler.Role.RANCHER, "a rancher")
	st.simulate(12.0)
	await wait_physics(3)
	check(coop.count() == 3 and coop.animals().size() == 3, "12 hours: a chick (%d)" % coop.count())
	check(st.store.inventory.count_of(&"egg") >= 2, "eggs in the stores (%d)" % st.store.inventory.count_of(&"egg"))
	check(st.food() < 30, "fed from the stores (%d left)" % st.food())
	check(r.status_text() == "Tending the animals", r.status_text())
	# Until it's full: then the spares are butchered
	st.store.inventory.add_item(VEG, 30)
	for i in 6:
		st.simulate(12.0)
	await wait_physics(3)
	check(coop.count() < 8 and coop.count() >= 4, "full, then butchered back to half (%d)" % coop.count())
	check(st.store.inventory.count_of(&"raw_meat") >= 8, "meat in the stores (%d)" % st.store.inventory.count_of(&"raw_meat"))
	check(said.any(func(t: String) -> bool: return t.begins_with(r.settler_name + " butchered 4 chickens: 8 Raw Meat")), "a notice: %s" % [said.back()])
	await _free(zone)


func test_cows_give_hides_and_you_can_butcher() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var pasture := await _build(zone, &"cow_pasture", Vector3(26, 0, 22))
	st.simulate(0.1)
	await wait_physics(3)
	check(pasture.count() == 2, "a pair of cows")
	var p := _player(zone)
	p.inventory.clear()
	var cow := pasture.animals()[0]
	p.global_position = cow.global_position + Vector3(1.0, 0.1, 0)
	await wait_physics(3)
	check(cow.get_prompt(p) == "Butcher the cow" and is_equal_approx(cow.hold_time, 3.0), "hold E: %s" % cow.get_prompt(p))
	check(st.request_butcher(p, cow), "butchered")
	await wait_physics(3)
	check(pasture.count() == 1 and pasture.animals().size() == 1, "one cow left")
	check(p.inventory.count_of(&"raw_meat") == 8 and p.inventory.count_of(&"raw_hide") == 1, "8 meat and a hide in your backpack")
	# Raw meat has to be cooked
	var refused := []
	p.item_use_refused.connect(func(t: String) -> void: refused.append(t))
	p.hunger.set_food(30.0)
	check(not p.request_use_item(MEAT) and refused.back() == "Cook it first", "raw: %s" % [refused])
	await _free(zone)


func test_pens_kitchens_and_jobs_are_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_kitchen"
	var zone := await load_zone()
	var st := await _claimed(zone)
	var kitchen := await _build(zone, &"kitchen", Vector3(20, 0, 24))
	var pen := await _build(zone, &"pig_pen", Vector3(33, 0, 22))
	st.simulate(0.1)
	await wait_physics(3)
	var cook := await _newcomer(zone, Settler.Role.COOK)
	var rancher := await _newcomer(zone, Settler.Role.RANCHER)
	pen.set_count(5)
	pen.breed_progress = 0.4
	kitchen.fridge.inventory.add_item(MSTEW, 3)
	var names := [cook.settler_name, rancher.settler_name]
	check(saves.save_game("kitchen", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	saves.load_game("kitchen", zone2)
	await wait_physics(5)
	var st2 := _farm(zone2)
	check(st2.pens().size() == 1 and st2.pens()[0].count() == 5 and st2.pens()[0].animals().size() == 5, "five pigs back in their pen")
	check(absf(st2.pens()[0].breed_progress - 0.4) < 0.05, "and the next piglet as close (%.2f)" % st2.pens()[0].breed_progress)
	check(st2.kitchens().size() == 1 and st2.kitchens()[0].fridge.inventory.count_of(&"meat_stew") == 3, "the fridge's stews")
	var roles := {}
	for s in st2.members():
		roles[s.settler_name] = s.role
	check(roles.get(names[0]) == Settler.Role.COOK and roles.get(names[1]) == Settler.Role.RANCHER, "the cook and the rancher: %s" % roles)
	await _free(zone2)
