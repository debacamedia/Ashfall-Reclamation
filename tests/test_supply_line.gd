extends "res://tests/test_case.gd"
## Increment 24: the supply line. Once you hold two places or more they're
## linked: settlers at any of them use materials (planks, scrap, cloth,
## bandages, gunpowder…) from all of their stores, and guards take guns and
## rounds from any Armory Locker. Food stays where it is but is shared out
## every settlement hour by each place's share, by headcount until you set
## the shares on the settlement screen.

const AWAY := Vector3(120, 0.1, 40)

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var STEW: ItemDefinition = load("res://resources/items/vegetable_stew.tres")
var BANDAGE: ItemDefinition = load("res://resources/items/bandage.tres")


func _st(zone: Node3D, id: StringName) -> Settlement:
	return Settlement.find(get_tree(), id)


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s (%s)" % [st.settlement_name, st.claim_refusal_reason(p)])
	st.next_raid_in = 9999.0
	st.arrival_in = 9999.0


func _newcomer(zone: Node3D, st: Settlement, role: Settler.Role) -> Settler:
	var p := _player(zone)
	var back := p.global_position
	p.global_position = AWAY
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	if role != Settler.Role.NONE:
		st.request_set_role(p, s, role)
	return s


## Empties a place's stores of food.
func _no_food(st: Settlement) -> void:
	for c in st.stores():
		c.inventory.remove_item(&"vegetables", c.inventory.count_of(&"vegetables"))
		c.inventory.remove_item(&"vegetable_stew", c.inventory.count_of(&"vegetable_stew"))


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


# ---------------------------------------------------------------- materials

func test_materials_are_shared() -> void:
	var zone := await load_zone()
	var farm := _st(zone, &"ash_creek")
	var mine := _st(zone, &"black_ridge")
	var nw := _st(zone, &"northwatch")
	check(farm.network() == [farm], "nothing claimed: no line")
	await _claim(zone, farm)
	check(farm.network() == [farm], "one place: no line")
	await _claim(zone, nw)
	check(farm.network().size() == 2 and nw.network()[0] == nw and nw.network().has(farm), "two places: linked, each first in its own list")
	check(not nw.network().has(mine), "an unclaimed place isn't on it")
	await _claim(zone, mine)
	# The Armorer at Northwatch uses the mine's scrap
	mine.store.inventory.add_item(SCRAP, 16)
	nw.store.inventory.add_item(VEG, 20)
	await _newcomer(zone, nw, Settler.Role.ARMORER)
	check(nw.scrap() == 16 and farm.scrap() == 16, "16 Scrap Metal in all your places")
	nw.simulate(4.0)
	check(nw.armory.inventory.count_of(&"pistol") == 1, "Northwatch's Armorer made a pistol from the mine's scrap")
	check(mine.store.inventory.count_of(&"scrap_metal") == 0, "the mine's stores are down 16")
	# Building at the mine with the farm's planks
	var p := _player(zone)
	var xf := mine.global_transform * Transform3D(Basis.IDENTITY, Vector3(24, 0, 15))
	p.global_position = xf.origin + Vector3(0, 0.1, 8)
	await wait_physics(3)
	var site := p.request_place_site(&"guard_post", xf)
	check(site != null and site.settlement() == mine, "a guard post planned at the mine (%s)" % p.site_refusal_reason(&"guard_post", xf))
	for id: StringName in site.missing():
		farm.store.inventory.add_item(ItemDatabase.get_item(id), site.missing()[id])
	mine._supply_sites()
	check(site.is_supplied(), "its materials came from the farm's stores")
	# First aid at the mine with the farm's bandages
	var hurt := await _newcomer(zone, mine, Settler.Role.MINER)
	hurt.health.current_health = 70.0
	farm.store.inventory.add_item(BANDAGE, 1)
	mine._simulate_first_aid(mine.members())
	check(is_equal_approx(hurt.health.current_health, 90.0) and farm.store.inventory.count_of(&"bandage") == 0, "a hurt Miner used a bandage from the farm")
	# Food isn't shared that way: the mine's Miner doesn't eat the farm's vegetables
	_no_food(mine)
	check(mine.food() == 0 and farm.food() > 0, "the farm's vegetables aren't the mine's food")
	await _free(zone)


func test_guards_arm_from_any_armory() -> void:
	var zone := await load_zone()
	var farm := _st(zone, &"ash_creek")
	var nw := _st(zone, &"northwatch")
	await _claim(zone, farm)
	await _claim(zone, nw)
	farm.store.inventory.add_item(VEG, 20)
	var g := await _newcomer(zone, farm, Settler.Role.GUARD)
	var said := []
	farm.notice.connect(func(t: String) -> void: said.append(t))
	nw.armory.inventory.add_item(load("res://resources/items/weapons/shotgun_item.tres"), 1)
	nw.armory.inventory.add_item(ItemDatabase.find_ammo_item(&"shotgun_12"), 24)
	farm._supply_guards()
	check(g.gun != null and g.gun.id == &"shotgun", "the farm's guard took the Shotgun from Northwatch's locker")
	check(g.ammo >= 24 and nw.armory.inventory.count_of(ItemDatabase.find_ammo_item(&"shotgun_12").id) == 0, "and its shells (%d)" % g.ammo)
	check(said.any(func(t: String) -> bool: return t.contains("Northwatch Outpost's armory")), "a notice: %s" % [said])
	await _free(zone)


# ---------------------------------------------------------------- food

func test_food_is_shared_by_headcount() -> void:
	var zone := await load_zone()
	var farm := _st(zone, &"ash_creek")
	var mine := _st(zone, &"black_ridge")
	await _claim(zone, farm)
	await _claim(zone, mine)
	_no_food(farm)
	_no_food(mine)
	farm.store.inventory.add_item(VEG, 40)
	for i in 3:
		await _newcomer(zone, farm, Settler.Role.FARMER)
	await _newcomer(zone, mine, Settler.Role.MINER)
	var shares := farm.food_shares()
	check(is_equal_approx(shares[farm], 0.75) and is_equal_approx(shares[mine], 0.25), "three at the farm, one at the mine: 75% and 25%")
	check(not farm.food_shares_set(), "split by headcount")
	farm.share_out_food()
	check(farm.food() == 30 and mine.food() == 10, "40 vegetables: 30 and 10 (%d, %d)" % [farm.food(), mine.food()])
	check(mine.supply_last == 10 and farm.supply_last == -10, "10 down the line")
	# Hourly, by itself
	farm.store.inventory.add_item(VEG, 8)
	var leader := farm._supply_leader()
	leader.simulate(1.05)
	check(mine.food() >= 11, "an hour later the farm's new vegetables are shared too (%d)" % mine.food())
	# A place with nobody yet still gets a little, so newcomers come
	var nw := _st(zone, &"northwatch")
	await _claim(zone, nw)
	check(is_equal_approx(float(farm.food_shares()[nw]), 1.0 / 5.0), "Northwatch, empty, counts as one of five")
	await _free(zone)


func test_food_shares_set_by_hand() -> void:
	var zone := await load_zone()
	var farm := _st(zone, &"ash_creek")
	var mine := _st(zone, &"black_ridge")
	await _claim(zone, farm)
	await _claim(zone, mine)
	_no_food(farm)
	_no_food(mine)
	for i in 3:
		await _newcomer(zone, farm, Settler.Role.FARMER)
	mine.set_food_share(25.0)
	check(farm.food_shares_set() and is_equal_approx(farm.food_share, 75.0), "the farm keeps its headcount share (75)")
	farm.set_food_share(25.0)
	check(is_equal_approx(farm.food_shares()[mine], 0.5), "25 and 25: half each")
	# Stews move whole: 4 at the farm (16 meals) and 8 vegetables -> 12 meals each
	farm.store.inventory.add_item(STEW, 4)
	farm.store.inventory.add_item(VEG, 8)
	farm.share_out_food()
	check(mine.food() == 8 and mine.stored_dishes()[0] == 1 and farm.stored_dishes()[0] == 3, "the 8 vegetables and a stew went to the mine (%d veg, %s)" % [mine.food(), mine.stored_dishes()])
	check(is_equal_approx(mine.food_meals(), 12.0) and is_equal_approx(farm.food_meals(), 12.0), "12 meals each")
	# A share of nothing: none goes there
	mine.set_food_share(0.0)
	farm.share_out_food()
	check(mine.food_meals() == 0.0 and farm.food_meals() == 24.0, "the mine at 0: it all comes back (%s)" % mine.food_meals())
	# Back to headcount
	mine.reset_food_shares()
	check(not farm.food_shares_set() and farm.food_share == -1.0 and mine.food_share == -1.0, "split by headcount again")
	await _free(zone)


func test_the_supply_line_on_the_screen() -> void:
	var zone := await load_zone()
	var hud := zone.get_node("HUD") as HUD
	var screen := hud.settlement_screen
	var farm := _st(zone, &"ash_creek")
	var mine := _st(zone, &"black_ridge")
	await _claim(zone, farm)
	screen.open(farm)
	check(not screen._supply_box.visible, "one place: no supply line")
	screen.close()
	await _claim(zone, mine)
	screen.open(farm)
	check(screen._supply_box.visible and screen._supply_list.get_child_count() == 2, "two places: a share for each")
	var row := screen._supply_list.get_node("Share_black_ridge")
	check((row.get_node("Percent") as Label).text == "50%", "both empty: 50%% each (%s)" % (row.get_node("Percent") as Label).text)
	(row.get_node("Slider") as HSlider).value = 25.0
	check(is_equal_approx(mine.food_share, 25.0) and is_equal_approx(farm.food_share, 50.0), "the mine's slider at 25: the farm keeps 50")
	check((row.get_node("Percent") as Label).text == "33%", "the mine gets a third (%s)" % (row.get_node("Percent") as Label).text)
	(screen._supply_box.get_node("ByHeadcount") as Button).pressed.emit()
	check(not farm.food_shares_set(), "Split by headcount resets them")
	check(screen._stocks.text.contains("in all your places"), "planks are counted across your places")
	screen.close()
	await _free(zone)


func test_shares_are_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_supply"
	var zone := await load_zone()
	await _claim(zone, _st(zone, &"ash_creek"))
	await _claim(zone, _st(zone, &"black_ridge"))
	_st(zone, &"black_ridge").set_food_share(20.0)
	check(saves.save_game("supply", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("supply", zone2) == OK, "loaded")
	await wait_physics(3)
	check(is_equal_approx(_st(zone2, &"black_ridge").food_share, 20.0) and is_equal_approx(_st(zone2, &"ash_creek").food_share, 50.0), "the shares came back")
	await _free(zone2)
