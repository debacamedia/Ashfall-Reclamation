extends "res://tests/test_case.gd"
## Increment 20.5: the farm while you're away. A raid that arrives with no
## player within 200 m is settled on paper (RaidOnPaper), at the same odds as
## a real fight, with a notice and a log; coming back tells you what happened.

const AWAY := Vector3(560, 0.1, -330)

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")
var RIFLE_W: WeaponDefinition = load("res://resources/items/weapons/service_rifle.tres")


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	p.global_position = AWAY
	await wait_physics(2)
	return st


func _newcomer(zone: Node3D, role: Settler.Role) -> Settler:
	var st := _farm(zone)
	var s := st.spawn_newcomer()
	await wait_physics(70)
	st.request_set_role(_player(zone), s, role)
	return s


func _raid_settlers() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(n: Node) -> bool: return n is Raider and (n as Raider).raid != null)


# ---------------------------------------------------------------- the model

func test_on_paper_the_odds_follow_the_guards() -> void:
	# Two raiders against four rifles: the guards win, nearly always
	var wins := 0
	for i in 20:
		var paper := RaidOnPaper.new(100 + i)
		for r in 2:
			paper.add_raider("Raider", 80.0, 20.0, 1.25)
		for g in 4:
			paper.add_guard("G%d" % g, 100.0, RIFLE_W, 0, 120)
		paper.stores = {&"vegetables": 60, &"wood_plank": 20}
		paper.carry = {&"vegetables": 15, &"wood_plank": 8}
		var res := paper.run()
		if int(res["escaped"]) == 0:
			wins += 1
		check(int(res["rounds"]) > 0 and int(res["rounds"]) <= 480, "rounds counted (%d)" % res["rounds"])
	check(wins >= 17, "four rifles hold off two raiders (%d / 20)" % wins)
	# Nobody to stop three: they all get away with what they can carry
	var bare := RaidOnPaper.new(7)
	for r in 3:
		bare.add_raider("Raider", 80.0, 20.0, 1.25)
	bare.add_sheltering("Finn", 100.0)
	bare.stores = {&"vegetables": 40, &"wood_plank": 20}
	bare.carry = {&"vegetables": 15, &"wood_plank": 8}
	var res := bare.run()
	check(int(res["escaped"]) == 3 and int(res["killed"]) == 0, "no guards: all three get away")
	check(int((res["stolen"] as Dictionary)[&"vegetables"]) == 40 and int((res["stolen"] as Dictionary)[&"wood_plank"]) == 20, "with everything they could carry: %s" % res["stolen"])
	check(bare.stores[&"vegetables"] == 0 and bare.stores[&"wood_plank"] == 0, "the stores are empty")
	# One guard with a machete against three: usually beaten
	var beaten := 0
	for i in 20:
		var paper := RaidOnPaper.new(300 + i)
		for r in 3:
			paper.add_raider("Raider", 80.0, 20.0, 1.25)
		paper.add_guard("Otis", 100.0, null, 0, 0)
		var out := paper.run()
		if (out["wounded"] as Array).has("Otis"):
			beaten += 1
	check(beaten >= 12, "a guard with a machete is beaten by three raiders more often than not (%d / 20)" % beaten)
	# The same seed, the same fight
	var a := RaidOnPaper.new(42)
	var b := RaidOnPaper.new(42)
	for p in [a, b]:
		for r in 3:
			p.add_raider("Raider", 80.0, 20.0, 1.25)
		p.add_guard("Quinn", 100.0, RIFLE_W, 30, 60)
		p.add_guard("Otis", 100.0, null, 0, 0)
	check(str(a.run()) == str(b.run()), "repeatable with a seed")


# ---------------------------------------------------------------- away

func test_a_raid_while_youre_away_is_settled_on_paper() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var g1 := await _newcomer(zone, Settler.Role.GUARD)
	var g2 := await _newcomer(zone, Settler.Role.GUARD)
	var f := await _newcomer(zone, Settler.Role.FARMER)
	g1.arm(RIFLE, 120)
	g2.arm(RIFLE, 120)
	st.store.inventory.add_item(VEG, 40)
	st.store.inventory.add_item(PLANK, 12)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	check(not st.player_near() and st.player_distance() > 200.0, "you're %d m away" % roundi(st.player_distance()))
	st.next_raid_in = 2.2
	st.simulate(0.5)
	check(st.raid_phase == Settlement.RaidPhase.WARNED, "warned")
	check(said.any(func(t: String) -> bool: return t.contains("You're ") and t.contains("be back within 200 m")), "the warning says you're far off: %s" % [said])
	var food := st.food()
	var planks := st.planks()
	var raided := []
	var after := []
	st.raid_ended.connect(func(rep: Dictionary) -> void:
		raided.append(rep)
		after.append_array([st.food(), st.planks()]))
	st.simulate(2.0)
	check(raided.size() == 1 and st.raid_phase == Settlement.RaidPhase.NONE, "the raid came and was settled at once")
	check(_raid_settlers().is_empty(), "no raiders were put in the world")
	check(st.next_raid_in > 30.0, "the next raid is days off (%.0f h)" % st.next_raid_in)
	var rep: Dictionary = raided[0]
	check(rep.get("on_paper") == true and int(rep["killed"]) + int(rep["escaped"]) == int(rep["size"]), "every raider killed or gone: %s" % rep)
	var stolen: Dictionary = rep["stolen"]
	check(after[0] == food - int(stolen.get(&"vegetables", 0)) and after[1] == planks - int(stolen.get(&"wood_plank", 0)), "what they took left the stores (%d → %d food)" % [food, after[0]])
	var spent := 240 - (g1.ammo + g1.magazine + g2.ammo + g2.magazine)
	check(spent == int(rep["rounds"]) and spent > 0, "the guards' rounds went down by what they fired (%d)" % spent)
	var down := st.members().filter(func(m: Settler) -> bool: return m.is_down()).map(func(m: Settler) -> String: return m.settler_name)
	check(str(down) == str(rep["wounded"]), "who's down is who the report says: %s" % [down])
	var line := said.filter(func(t: String) -> bool: return t.begins_with("While you were away, %d raiders hit Ash Creek Farms" % int(rep["size"])))
	check(line.size() == 1, "a notice: %s" % [said.back()])
	check(st.log_entries.any(func(e: Dictionary) -> bool: return e["away"] and str(e["text"]).begins_with("While you were away")), "and it's in the log")
	await _free(zone)


func test_losing_while_away_costs_the_same() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var f1 := await _newcomer(zone, Settler.Role.FARMER)
	var f2 := await _newcomer(zone, Settler.Role.FARMER)
	st.store.inventory.add_item(VEG, 60)
	st.store.inventory.add_item(PLANK, 20)
	var food := st.food()
	st.warn_raid(0.0)
	st.raid_size = 3
	var rep := st.settle_raid_on_paper(11)
	check(int(rep["escaped"]) == 3, "no guards: all three got away")
	check(st.food() == food - 45 and st.planks() == 20 - 20, "with 45 vegetables and every plank (%d left)" % st.food())
	# A sheltering settler found and beaten is down, and bleeds out like any other
	f1.knock_down()
	check(f1.is_down() and st.members().has(f1), "down, still one of them")
	st.simulate(11.0)
	check(f1.is_down(), "still holding on after 11 hours")
	st.simulate(1.5)
	check(f1.is_dead() and not st.members().has(f1), "left 12 hours, they die: the same as when you're there")
	await _free(zone)


func test_with_you_there_its_a_real_fight() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	p.global_position = st.global_position + Vector3(0, 0.1, 0) + st.global_basis * Vector3(0, 0, 20)
	await wait_physics(3)
	check(st.player_near(), "you're at the farm")
	st.warn_raid(0.0)
	st.start_raid()
	check(st.raid_active() and st.raiders.size() == st.raid_size, "raiders come in for real")
	check(_raid_settlers().size() == st.raid_size, "in the world")
	for r in st.raiders:
		r.queue_free()
	await wait_physics(3)
	await _free(zone)


# ---------------------------------------------------------------- the log

func test_coming_back_tells_you_what_happened() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var g := await _newcomer(zone, Settler.Role.GUARD)
	g.arm(RIFLE, 60)
	# You leave (the farm notices within a second)
	await wait_physics(70)
	check(st.left_at_hour >= 0.0, "it knows when you left (%s)" % Settlement.clock_text(st.left_at_hour))
	st.warn_raid(0.0)
	st.settle_raid_on_paper(5)
	st.spawn_newcomer()
	var away := st.away_entries()
	check(away.size() >= 2, "things happened while you were away: %s" % [away.map(func(e: Dictionary) -> String: return e["text"])])
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 2.0)
	await wait_physics(70)
	check(said.any(func(t: String) -> bool: return t.begins_with("Back at Ash Creek Farms: ") and t.contains("things happened while you were away (L for the log)")), "back: a notice: %s" % [said])
	# The settlement screen's log shows them first
	var hud := zone.get_node("HUD") as HUD
	hud.settlement_screen.open(st)
	await wait_physics(2)
	var lines: Array[String] = []
	for l in hud.settlement_screen.find_child("Log", true, false).get_children():
		lines.append((l as Label).text)
	check(lines.size() >= 3 and lines[0].begins_with("While you were away (since Day 1"), "headed While you were away: %s" % [lines.slice(0, 2)])
	check(lines.any(func(t: String) -> bool: return t.contains("raiders hit Ash Creek Farms")), "the raid's there")
	check(lines[1].begins_with("Day "), "each with the time: %s" % lines[1])
	hud.settlement_screen.close()
	await _free(zone)


func test_the_log_is_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_away"
	var zone := await load_zone()
	var st := await _claimed(zone)
	await wait_physics(70)
	st.simulate(5.0)
	st.warn_raid(0.0)
	st.settle_raid_on_paper(9)
	var n := st.log_entries.size()
	var clock := st.clock_hours
	var left := st.left_at_hour
	var saved_texts := st.log_entries.map(func(e: Dictionary) -> String: return str(e["text"]))
	check(n >= 3, "a few things in the log (%d)" % n)
	check(saves.save_game("away", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	saves.load_game("away", zone2)
	await wait_physics(3)
	var st2 := _farm(zone2)
	var texts := st2.log_entries.slice(0, n).map(func(e: Dictionary) -> String: return str(e["text"]))
	check(str(texts) == str(saved_texts) and st2.clock_hours >= clock and is_equal_approx(st2.left_at_hour, left), "the log, its clock and when you left come back: %s" % [texts])
	check(st2.log_entries.any(func(e: Dictionary) -> bool: return str(e["text"]).begins_with("While you were away") and e["away"]), "the raid's there, marked as while you were away")
	check(st2.away_entries().size() >= 1, "still marked as while you were away")
	await _free(zone2)
