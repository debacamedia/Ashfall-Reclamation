extends "res://tests/test_case.gd"
## Increment 19: Ash Creek Farms, the first settlement. Claiming it, the
## pump, water and food, newcomers and survivors, jobs, guards and their
## guns, meals and leaving, the settlement screen, saving.

const RAIDER_SCENE := preload("res://scenes/enemies/raider.tscn")
const FARM := Vector3(340, 0, -90)

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PIPE: ItemDefinition = load("res://resources/items/metal_pipe.tres")
var SPRING: ItemDefinition = load("res://resources/items/spring.tres")
var PISTOL: ItemDefinition = load("res://resources/items/weapons/pistol_item.tres")
var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


## Puts the player at the farm's notice board.
func _to_board(zone: Node3D) -> PlayerController:
	var p := _player(zone)
	var st := _farm(zone)
	p.global_position = st.claim_point.global_position + Vector3(0, -1.35, 1.6)
	p.rotation.y = 0.0
	await wait_physics(5)
	return p


## A settled newcomer, arrived (the player stepped away while they walked in).
func _newcomer(zone: Node3D, role := Settler.Role.NONE) -> Settler:
	var st := _farm(zone)
	var p := _player(zone)
	var back := p.global_position
	p.global_position = FARM + Vector3(0, 0.1, 400)
	var s := st.spawn_newcomer()
	await wait_physics(70)
	p.global_position = back
	if role != Settler.Role.NONE:
		st.request_set_role(p, s, role)
	return s


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := await _to_board(zone)
	st.request_claim(p)
	return st


# ---------------------------------------------------------------- the farm

func test_ash_creek_is_a_settlement_waiting_to_be_claimed() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	check(st != null and st.is_in_group("settlements") and st.settlement_name == "Ash Creek Farms", "Ash Creek Farms has a Settlement")
	check(not st.is_claimed, "not yours yet")
	for part in ["ClaimPoint", "WaterPump", "FarmStore", "Armory", "FarmSpots", "GuardPosts", "ArrivalPoint", "Hangout", "Settlers"]:
		check(st.get_node_or_null(part) != null, "it has its %s" % part)
	check(st.store.is_searched and st.armory.is_searched, "the Farm Store and Armory Locker open with no search")
	var beds := zone.get_node("AshCreekFarms").find_children("SettlerBed*", "", true, false).size() + 1
	check(beds == st.beds and st.beds == 4, "beds for four in the farmhouse")
	check(not st.pump_working, "the pump is broken")
	var survivors := zone.get_node("Survivors").get_children()
	check(survivors.size() == 3, "three survivors waiting elsewhere")
	for sv: Settler in survivors:
		check(sv.settlement == null and sv.recruitable and sv.greeting != "" and sv.state == Settler.State.WAIT, "%s waits to be asked" % sv.settler_name)
		var on_mesh := NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, sv.global_position)
		check(on_mesh.distance_to(sv.global_position) < 0.8, "%s stands somewhere walkable" % sv.settler_name)
	var mark := zone.get_node("Landmarks/AshCreekFarms") as Landmark
	check(mark.marker_color != Settlement.CLAIMED_COLOR, "amber on the compass, like any place")


func test_claim_once_the_raiders_are_gone() -> void:
	var zone := await load_zone(["AshCreekFarms"])
	var st := _farm(zone)
	var p := await _to_board(zone)
	await wait_physics(30)
	var n := st.raiders_here()
	check(n > 0, "raiders hold the farm (%d)" % n)
	var refused := []
	st.refused.connect(func(r: String) -> void: refused.append(r))
	check(not st.request_claim(p) and st.claim_refusal_reason(p).contains("Raiders are still here"), "can't claim it yet: %s" % st.claim_refusal_reason(p))
	check(st.claim_point.get_block_reason(p) != "", "the board says why")
	for e in get_tree().get_nodes_in_group("enemies"):
		var r := e as Raider
		if r != null and r.global_position.distance_to(st.global_position) < st.claim_radius:
			r.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.BALLISTIC, p))
	await wait_physics(3)
	check(st.raiders_here() == 0, "cleared")
	var notices := []
	st.notice.connect(func(t: String) -> void: notices.append(t))
	check(st.claim_point.hold_time > 0.0, "claiming is a hold")
	check(st.claim_point.try_interact(p, p.head.global_position), "hold E at the board")
	check(st.is_claimed, "Ash Creek Farms is yours")
	check(notices.size() >= 1 and notices[0].contains("is yours"), "told: %s" % str(notices))
	var spawner := zone.get_node("AshCreekFarms").find_children("*", "EnemySpawner", true, false)[0] as EnemySpawner
	check(not spawner.enabled, "its raiders stop coming")
	check(st.food() == st.starting_food and is_equal_approx(st.water, st.starting_water), "a little food and water to start")
	check((zone.get_node("Landmarks/AshCreekFarms") as Landmark).marker_color == Settlement.CLAIMED_COLOR, "green on the compass")
	check(not st.request_claim(p) and refused.back().contains("already yours"), "only once")
	await wait_physics(5)
	check(st.claim_point.hold_time == 0.0, "the board now opens the settlement (a tap)")


func test_repair_the_pump() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	var p := _player(zone)
	check(st.pump_refusal_reason(p) == "Claim the farm first", "not before it's yours")
	await _claimed(zone)
	p.inventory.clear()
	var reason := st.pump_refusal_reason(p)
	check(reason.begins_with("Needs") and reason.contains("Scrap Metal"), "it needs parts: %s" % reason)
	var before: float = st.rates()["water"]
	p.inventory.add_item(SCRAP, 3)
	p.inventory.add_item(PIPE, 2)
	p.inventory.add_item(SPRING, 1)
	p.global_position = st.pump.global_position + Vector3(-1.3, -0.85, 0)
	p.rotation.y = -PI / 2.0  # facing east, at the tank
	await wait_physics(3)
	check(st.pump.get_prompt(p).begins_with("Repair the pump"), "prompt: %s" % st.pump.get_prompt(p))
	check(p.request_repair_pump(st) and st.pump_working, "fixed")
	check(p.inventory.count_of(&"scrap_metal") == 0 and p.inventory.count_of(&"metal_pipe") == 0 and p.inventory.count_of(&"spring") == 0, "the parts are used")
	check(st.rates()["water"] > before + 5.0, "water flows: %.1f → %.1f L an hour" % [before, st.rates()["water"]])
	st.simulate(10.0)
	check(st.water > st.starting_water + 50.0, "the tank fills (%.0f L)" % st.water)
	st.simulate(100.0)
	check(is_equal_approx(st.water, st.water_capacity), "up to %d L" % st.water_capacity)


func test_newcomers_farm_and_eat() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var arrived := []
	st.settler_arrived.connect(func(s: Settler) -> void: arrived.append(s))
	# The first newcomer comes about an hour after you claim it
	p.global_position = FARM + Vector3(0, 0.1, 400)
	st.simulate(st.first_arrival_hours + 0.01)
	var people := st.members()
	check(people.size() == 1, "a newcomer turns up")
	await wait_physics(70)
	check(arrived.size() == 1 and people[0].has_arrived(), "and settles in: %s" % people[0].settler_name)
	var s: Settler = people[0]
	check(s.get_parent() == st.settlers_root and s.spawned and s.is_save_removable(), "one of the farm's people")
	check(s.role == Settler.Role.NONE and not s.is_working(), "no job to start with")
	# A farmer turns water into vegetables
	check(st.request_set_role(p, s, Settler.Role.FARMER) and s.role == Settler.Role.FARMER, "made a farmer")
	st.water = 50.0
	var food := st.food()
	st.simulate(4.0)
	check(st.food() >= food + 5 - 1, "4 hours: about 6 grown, 1 eaten (%d → %d)" % [food, st.food()])
	check(st.rates()["food"] > 0.0, "more food than they eat (%.2f an hour)" % st.rates()["food"])
	# No water: no crops
	st.water = 0.0
	st.pump_working = false
	food = st.food()
	st.simulate(0.5)
	check(s.short_of_water and st.food() <= food, "no water, no crops")
	check(s.status_text() == "No water to farm", "status: %s" % s.status_text())


func test_hungry_settlers_stop_then_leave() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var s := await _newcomer(zone, Settler.Role.FARMER)
	st.water = 100.0
	st.store.inventory.remove_item(&"vegetables", 999)
	var lost := []
	st.settler_lost.connect(func(n: String, why: String) -> void: lost.append([n, why]))
	s.next_meal = 0.0
	# (no water either, so nothing grows)
	st.water = 0.0
	for i in 12:
		st.store.inventory.remove_item(&"vegetables", 999)
		st.simulate((st.hungry_after_hours + 0.1) / 12.0)
	check(s.is_hungry() and not s.is_working(), "nothing to eat: hungry, not working")
	check(s.status_text().begins_with("Hungry"), "status: %s" % s.status_text())
	check(st.rates()["farmers"] == 0, "a hungry farmer grows nothing")
	# Food and water arrive: they eat and get back to work
	st.store.inventory.add_item(VEG, 3)
	st.water = 50.0
	st.simulate(0.05)
	check(not s.is_hungry() and s.is_working(), "fed again, back to work")
	# Starved for good: they leave
	st.store.inventory.remove_item(&"vegetables", 999)
	s.role = Settler.Role.NONE  # (so nothing grows)
	s.next_meal = 0.0
	st.simulate(st.leave_after_hours + 0.1)
	check(lost.size() == 1 and lost[0][1] == "nothing to eat", "after %d hours, they leave: %s" % [st.leave_after_hours, str(lost)])
	check(s.settlement == null and s.state == Settler.State.LEAVING and st.members().is_empty(), "and walk away")
	check(p != null, "")


func test_newcomers_need_a_bed_and_food() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	_player(zone).global_position = FARM + Vector3(0, 0.1, 400)
	st.store.inventory.remove_item(&"vegetables", 999)
	st.simulate(st.arrival_every_hours * 2.0)
	check(st.members().is_empty(), "no food in store, no newcomers")
	st.store.inventory.add_item(VEG, 20)
	for i in 4:
		st.spawn_newcomer()
	check(st.free_beds() == 0, "four beds, four people")
	st.arrival_in = 0.0
	st.simulate(0.01)
	check(st.members().size() == 4, "a full house takes nobody else")
	var names := {}
	for s in st.members():
		names[s.settler_name] = true
	check(names.size() == 4, "everyone has their own name")


func test_survivors_come_when_asked() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	var p := _player(zone)
	var maya := zone.get_node("Survivors/Maya") as Settler
	var refused := []
	st.refused.connect(func(r: String) -> void: refused.append(r))
	p.global_position = maya.global_position + Vector3(0, 0, 1.6)
	await wait_physics(5)
	p.talk_to(maya)
	check(maya.settlement == null and refused.size() == 1 and refused[0].contains("Claim a settlement first") and refused[0].contains(maya.greeting),
		"before you've a settlement she says her piece: %s" % str(refused))
	await _claimed(zone)
	p.global_position = maya.global_position + Vector3(0, 0, 1.6)
	await wait_physics(5)
	var notices := []
	st.notice.connect(func(t: String) -> void: notices.append(t))
	p.talk_to(maya)
	check(maya.settlement == st and not maya.recruitable, "Maya agrees to come")
	check(notices.any(func(t: String) -> bool: return t.contains("on the way")), "she's on the way")
	check(maya.state == Settler.State.TRAVEL and not maya.has_arrived(), "walking there with you")
	await wait_physics(60)
	check(maya.velocity.length() > 0.5, "she sets off (%.1f m/s)" % maya.velocity.length())
	# Leave her to it: out of sight, she gets there
	p.global_position = Vector3(0, 0.1, 14)
	await wait_physics(80)
	check(maya.has_arrived() and maya.global_position.distance_to(st.get_node("Hangout").global_position) < 3.0, "she arrives at Ash Creek Farms")
	# No room: the others wait
	for i in st.free_beds():
		st.spawn_newcomer()
	var jeb := zone.get_node("Survivors/Jeb") as Settler
	p.talk_to(jeb)
	check(jeb.settlement == null and refused.back().contains("no bed"), "with every bed taken, Old Jeb waits: %s" % refused.back())


func test_arming_guards() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var g := await _newcomer(zone, Settler.Role.GUARD)
	check(g.role == Settler.Role.GUARD and g.gun == null and g.status_text() == "Guarding (machete)", "a guard with only a machete")
	# Your spare pistol and its rounds
	p.inventory.clear()
	p.inventory.add_item(PISTOL, 1)
	p.inventory.add_item(ItemDatabase.find_ammo_item(PISTOL.weapon.ammo_type), 40)
	var idx := -1
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == PISTOL:
			idx = i
	check(st.request_give_gun(p, g, idx), "give a guard your spare pistol")
	check(g.gun == PISTOL and g.ammo == 40 and p.inventory.count_of(PISTOL.id) == 0, "they have it, and your 40 rounds (%d)" % g.ammo)
	check(g.gun_text().contains("Pistol") and g.gun_text().contains("40"), "shown: %s" % g.gun_text())
	check(not st.request_give_ammo(p, g), "no more rounds to give")
	check(st.request_take_gun(p, g) and g.gun == null and p.inventory.count_of(PISTOL.id) == 1, "take it back")
	check(p.inventory.count_of(ItemDatabase.find_ammo_item(PISTOL.weapon.ammo_type).id) == 40, "with its rounds")
	var refused := []
	st.refused.connect(func(r: String) -> void: refused.append(r))
	p.inventory.add_item(SCRAP, 1)
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) == SCRAP:
			idx = i
	check(not st.request_give_gun(p, g, idx) and refused.back() == "That's not a gun", "only guns")
	# The armory: an unarmed guard helps themselves
	st.armory.inventory.add_item(RIFLE, 1)
	st.armory.inventory.add_item(ItemDatabase.find_ammo_item(RIFLE.weapon.ammo_type), 90)
	await wait_physics(150)
	check(g.gun == RIFLE and g.ammo >= 30, "a guard takes the armory's rifle and rounds (%s)" % g.gun_text())
	check(st.armory.inventory.count_of(RIFLE.id) == 0, "it's gone from the locker")


func test_guards_defend_the_farm() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var g := await _newcomer(zone, Settler.Role.GUARD)
	g.arm(RIFLE, 60)
	g.global_position = st.get_node("Hangout").global_position
	p.global_position = FARM + Vector3(0, 0.1, 200)
	# A raider wanders into the yard
	var r := RAIDER_SCENE.instantiate() as Raider
	r.position = g.global_position + Vector3(14, 0.1, 6)
	zone.add_child(r)
	var hurt := []
	r.health.damaged.connect(func(_a: float, info: DamageInfo) -> void: hurt.append(info))
	var n := 0
	while not r.is_dead() and n < 900:
		await wait_physics(1)
		n += 1
	check(not hurt.is_empty() and (hurt[0] as DamageInfo).source == g, "the guard shoots at it")
	check(r.is_dead(), "and kills it (%.1f s)" % (n / 60.0))
	check(g.ammo + g.magazine < 60, "using rounds (%d left)" % (g.ammo + g.magazine))
	# Unarmed, it's the machete
	g.disarm()
	var r2 := RAIDER_SCENE.instantiate() as Raider
	r2.position = g.global_position + Vector3(6, 0.1, 0)
	zone.add_child(r2)
	var hurt2 := []
	r2.health.damaged.connect(func(_a: float, info: DamageInfo) -> void: hurt2.append(info))
	n = 0
	while hurt2.is_empty() and n < 900:
		await wait_physics(1)
		n += 1
	check(not hurt2.is_empty() and (hurt2[0] as DamageInfo).type == DamageInfo.Type.MELEE, "without a gun, the machete")
	# Farmers don't fight
	var f := await _newcomer(zone, Settler.Role.FARMER)
	await wait_physics(30)
	check(f.state != Settler.State.FIGHT, "farmers keep farming")


func test_settled_life_is_saved() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	st.pump_working = true
	st.water = 77.0
	var a := await _newcomer(zone, Settler.Role.FARMER)
	var b := await _newcomer(zone, Settler.Role.GUARD)
	b.arm(PISTOL, 33)
	var maya := zone.get_node("Survivors/Maya") as Settler
	maya.join(st)
	var data := JSON.parse_string(JSON.stringify(SaveManager.build_save_data(zone))) as Dictionary
	var a_name := a.settler_name
	var b_name := b.settler_name
	# Undo it all
	st.load_state({})
	a.queue_free()
	b.queue_free()
	maya.load_state({"recruitable": true})
	await wait_physics(3)
	check(not st.is_claimed and st.members().is_empty(), "(back to an empty farm)")
	check((zone.get_node("Landmarks/AshCreekFarms") as Landmark).marker_color != Settlement.CLAIMED_COLOR, "(and amber again)")
	SaveManager.apply_save_data(data, zone)
	await wait_physics(3)
	check(st.is_claimed and st.pump_working and absf(st.water - 77.0) < 0.5, "claimed, pump fixed, 77 L of water (%.2f)" % st.water)
	var by_name := {}
	for s in st.members():
		by_name[s.settler_name] = s
	check(by_name.has(a_name) and (by_name[a_name] as Settler).role == Settler.Role.FARMER and (by_name[a_name] as Settler).has_arrived(), "%s the farmer is back" % a_name)
	check(by_name.has(b_name) and (by_name[b_name] as Settler).gun == PISTOL and (by_name[b_name] as Settler).ammo == 33, "%s the guard, with the pistol and 33 rounds" % b_name)
	check(by_name.has("Maya") and not (by_name["Maya"] as Settler).recruitable, "Maya still lives there")
	check((zone.get_node("Landmarks/AshCreekFarms") as Landmark).marker_color == Settlement.CLAIMED_COLOR, "green again")
	check(p != null, "")


func test_settlement_screen() -> void:
	var zone := await load_zone()
	var hud := zone.get_node("HUD") as HUD
	var screen := hud.settlement_screen
	var p := _player(zone)
	check(screen != null and not screen.visible, "the HUD has a settlement screen")
	screen.open()
	check(screen.visible and p.player_input.ui_open and hud.is_window_open(), "L opens it")
	check(screen._empty.visible and screen._empty.text.contains("notice board"), "not claimed: how to claim it")
	screen.close()
	var st := await _claimed(zone)
	var s := await _newcomer(zone)
	p.inventory.clear()
	p.inventory.add_item(PISTOL, 1)
	p.talk_to(s)
	check(screen.visible and screen.focus == s, "talking to a settler opens it at them")
	check(not screen._empty.visible and screen._stocks.text.contains("Fresh Vegetables"), "stocks: %s" % screen._stocks.text.replace("\n", " | "))
	check(screen._pump.text.contains("broken"), "the pump: %s" % screen._pump.text)
	check(screen._rows.size() == 1, "one settler listed")
	var row := screen._list.get_child(0)
	(row.find_child("Job_Guard", true, false) as Button).pressed.emit()
	check(s.role == Settler.Role.GUARD, "the Guard button makes them a guard")
	var give := screen._list.get_child(0).find_child("GiveGun", true, false) as MenuButton
	check(not give.disabled and give.get_popup().item_count == 1, "your spare pistol is offered")
	give.get_popup().id_pressed.emit(give.get_popup().get_item_id(0))
	check(s.gun == PISTOL, "and given")
	screen.close()
	check(not p.player_input.ui_open, "closed")
	# The board opens it too
	p.global_position = st.claim_point.global_position + Vector3(0, -1.35, 1.6)
	p.rotation.y = 0.0
	await wait_physics(5)
	check(st.claim_point.try_interact(p, p.head.global_position) and screen.visible, "so does the notice board")
	screen.close()
	check(InputMap.has_action("settlement"), "an L action")


func test_on_the_map() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	await _newcomer(zone, Settler.Role.FARMER)
	var hud := zone.get_node("HUD") as HUD
	var view := hud.map_screen.view
	view.player = _player(zone)
	var marks := view.markers()
	var farm: Array = marks.filter(func(m: Dictionary) -> bool: return str(m["name"]).begins_with("Ash Creek Farms"))
	check(farm.size() == 1 and farm[0]["yours"] and str(farm[0]["name"]).contains("yours"), "the farm shows as yours")
	check(marks.filter(func(m: Dictionary) -> bool: return m["kind"] == "settler").size() == 1, "and your settler")
	check(st != null, "")
