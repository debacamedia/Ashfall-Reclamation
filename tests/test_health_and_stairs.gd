extends "res://tests/test_case.gd"
## Increment 22.1, from the user's playtest of 22: each settler's health on
## the settlement screen; Bandages and Medkits left in the stores used by the
## hurt (and to help up the wounded); holding E helps build every kind of
## site, not just the small ones; settlers and raiders get up stairs, so
## guards reach their towers.

const AWAY := Vector3(520, 0.1, -180)
const DT := 1.0 / 60.0

var BANDAGE: ItemDefinition = load("res://resources/items/bandage.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")


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
	st.next_raid_in = 9999.0
	return st


func _newcomer(zone: Node3D, st: Settlement, role: Settler.Role) -> Settler:
	var p := _player(zone)
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


## A site for `plan` at `local` in the farm, with its materials.
func _supplied_site(zone: Node3D, plan: StringName, local: Vector3, yaw_deg := 0.0) -> ConstructionSite:
	var p := _player(zone)
	var root := zone.get_node("AshCreekFarms") as Node3D
	var xf := root.global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), local)
	p.global_position = xf.origin + root.global_basis * Vector3(0, 0.1, 9)
	await wait_physics(3)
	var site := p.request_place_site(plan, xf)
	check(site != null, "planned a %s (%s)" % [plan, p.site_refusal_reason(plan, xf)])
	if site == null:
		return null
	var inv := InventoryComponent.new()
	inv.slot_count = 40
	inv.max_weight = 0.0
	add_child(inv)
	for id: StringName in site.missing():
		inv.add_item(ItemDatabase.get_item(id), site.missing()[id])
	site.take_from(inv)
	inv.queue_free()
	await wait_physics(2)
	return site


func _aim(p: PlayerController, target: Vector3) -> void:
	var d := target - p.camera.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


## Holds E (through the player's own interaction ray) for `frames`.
func _hold_e(p: PlayerController, frames: int) -> void:
	p.simulate(InputFrame.new(), DT)
	var f := InputFrame.new()
	f.interact = true
	for i in frames:
		p.simulate(f, DT)
		await wait_physics(1)
	p.simulate(InputFrame.new(), DT)


# ---------------------------------------------------------------- helping build

func test_holding_e_helps_build_everything() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	for plan in SettlementPlans.placeable():
		for old in st.sites():
			old.queue_free()
		await wait_physics(2)
		var site := await _supplied_site(zone, plan, Vector3(30, 0, 30))
		if site == null:
			continue
		var def := SettlementPlans.structure(plan)
		var front := site.global_transform * Vector3(0, 0.1, def.footprint.z * 0.5 + 1.0)
		p.global_position = front
		await wait_physics(4)
		_aim(p, site.global_transform * Vector3(0, 1.0, def.footprint.z * 0.5 - 0.3))
		await wait_physics(2)
		await _hold_e(p, 100)
		check(p.interactor.focused == site, "%s: looking at it from its edge" % plan)
		check(site.work > 0.1, "%s: a hold of E helps, standing at its edge (%.2f h)" % [plan, site.work])
	# Holding on keeps helping (a bunkhouse, 6 hours' work)
	for old in st.sites():
		old.queue_free()
	await wait_physics(2)
	var bunk := await _supplied_site(zone, &"bunkhouse", Vector3(30, 0, 30))
	p.global_position = bunk.global_transform * Vector3(0, 0.1, 4.1)
	await wait_physics(4)
	_aim(p, bunk.global_transform * Vector3(0, 1.0, 2.8))
	await wait_physics(2)
	await _hold_e(p, 280)
	check(bunk.work > 0.4 and bunk.work < 0.5, "held for 4.6 s: three helps in a row (%.2f h)" % bunk.work)
	check(bunk.get_prompt(p).contains("%"), "the prompt shows how far along it is: %s" % bunk.get_prompt(p))
	await _free(zone)


func test_reach_is_to_the_nearest_edge() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	for old in st.sites():
		old.queue_free()
	await wait_physics(2)
	var site := await _supplied_site(zone, &"cow_pasture", Vector3(30, 0, 30))
	var near := site.global_transform * Vector3(0, 1.6, 6.15 + 1.5)
	var far := site.global_transform * Vector3(0, 1.6, 6.15 + 5.0)
	check(near.distance_to(site.centre()) > 5.0, "the middle of a cow pasture is out of reach from its edge (%.1f m)" % near.distance_to(site.centre()))
	check(site.is_within_reach(near), "but its edge is in reach")
	check(not site.is_within_reach(far), "5 m off, it isn't")
	await _free(zone)


# ---------------------------------------------------------------- stairs

func test_guards_climb_to_their_towers() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var spots_at := [[Vector3(30, 0, 26), 0.0], [Vector3(30, 0, 10), 180.0], [Vector3(14, 0, 26), 90.0]]
	for t in spots_at:
		var site := await _supplied_site(zone, &"guard_tower", t[0], t[1])
		site.add_work(site.total_hours())
	await wait_physics(30)
	check(st.guard_posts().size() == 3, "three towers")
	var guards: Array[Settler] = []
	for i in 3:
		guards.append(await _newcomer(zone, st, Settler.Role.GUARD))
	var up := 0
	for i in 75:
		await wait_physics(60)
		up = guards.filter(func(g: Settler) -> bool:
			return g.global_position.y > 2.4 and st.guard_posts().any(func(s: Node3D) -> bool: return s.global_position.distance_to(g.global_position) < 1.5)).size()
		if up == 3:
			break
	check(up == 3, "all three guards walked up to their decks (%d did)" % up)
	# Nobody stands under a deck: it's boarded in
	var tower := st.buildings().filter(func(b: SettlementBuilding) -> bool: return b.definition.id == &"guard_tower")[0] as SettlementBuilding
	var under := tower.global_transform * Vector3(0, 0.1, -1.7)
	var map := zone.get_world_3d().navigation_map
	check(NavigationServer3D.map_get_closest_point(map, under).distance_to(under) > 1.0, "nowhere to stand under the deck")
	await _free(zone)


## A body walking into a step a hand high gets up it; a knee-high box stops it.
func _walk_into(step_height: float) -> float:
	var floor_body := make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var step := make_static_box(Vector3(4, step_height, 4), Vector3(0, step_height / 2.0, -3.0))
	var body := CharacterBody3D.new()
	body.collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES
	body.floor_max_angle = deg_to_rad(46.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.45
	cs.shape = cap
	cs.position.y = 0.725
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(0, 0.02, 0)
	await wait_physics(2)
	for i in 120:
		body.velocity = Vector3(0, body.velocity.y - 9.8 * DT, -2.0)
		body.move_and_slide()
		NpcStep.step_up(body)
		await wait_physics(1)
	var y := body.global_position.y
	body.queue_free()
	floor_body.queue_free()
	step.queue_free()
	await wait_physics(2)
	return y


func test_npcs_step_up_low_steps() -> void:
	var y := await _walk_into(0.3)
	check(y > 0.25, "a 30 cm step: up it (feet at %.2f m)" % y)
	y = await _walk_into(0.75)
	check(y < 0.1, "a 75 cm box: not climbed (feet at %.2f m)" % y)


func test_wooden_stairs_are_solid_underneath() -> void:
	var stairs := (load("res://scenes/structures/wooden_stairs.tscn") as PackedScene).instantiate() as Node3D
	var ramp := stairs.get_node("Body/Ramp") as CollisionShape3D
	check(ramp.shape is ConvexPolygonShape3D, "the stair's collision is a solid wedge")
	var pts := (ramp.shape as ConvexPolygonShape3D).points
	var top := -INF
	for v in pts:
		top = maxf(top, v.y)
	check(is_equal_approx(top, 2.6), "2.6 m up, level with a platform")
	stairs.free()
	var tower := (load("res://scenes/settlement/guard_tower.tscn") as PackedScene).instantiate() as Node3D
	check(tower.get_node("Body/Ramp").get("shape") is ConvexPolygonShape3D, "so is a guard tower's")
	check(tower.find_child("Newel*", true, false) != null and tower.find_child("HandrailCol*", true, false) != null, "with handrails and newel posts: on from the front only")
	check(tower.find_child("UnderDeck", true, false) != null, "and boarded in under the deck")
	tower.free()


# ---------------------------------------------------------------- health and first aid

func test_settler_health_on_the_screen() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var hud := zone.get_node("HUD") as HUD
	var screen := hud.settlement_screen
	var s := await _newcomer(zone, st, Settler.Role.FARMER)
	s.health.current_health = 74.0
	screen.open(st, s)
	await wait_physics(2)
	screen.refresh()
	var bar := screen._list.get_child(0).find_child("Health", true, false) as ProgressBar
	check(bar != null, "each settler's row has a health bar")
	check(is_equal_approx(bar.value, 74.0) and (bar.get_node("Text") as Label).text == "74 / 100", "74 / 100: %s" % (bar.get_node("Text") as Label).text)
	s.knock_down()
	screen.refresh()
	check((bar.get_node("Text") as Label).text == "Down" and bar.value == 0.0, "down: Down")
	check(screen._stocks.text.contains("First aid:  0 Bandages, 0 Medkits"), "and the stores' first aid in the stocks")
	screen.close()
	await _free(zone)


func test_first_aid_from_the_stores() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	var a := await _newcomer(zone, st, Settler.Role.FARMER)
	var b := await _newcomer(zone, st, Settler.Role.FARMER)
	# Nothing in the stores: nothing to be done
	a.health.current_health = 50.0
	st.simulate(1.0)
	check(is_equal_approx(a.health.current_health, 50.0), "with nothing in the stores, a hurt settler stays hurt")
	# A Medkit and two Bandages on the Farm Store's shelves
	st.store.inventory.add_item(MEDKIT, 1)
	st.store.inventory.add_item(BANDAGE, 2)
	check(st.first_aid_stock() == [2, 1], "two bandages and a medkit in the stores")
	st.simulate(0.1)
	check(is_equal_approx(a.health.current_health, 90.0), "50 short: a Medkit (+40) gets them to 90 (%.0f)" % a.health.current_health)
	check(st.first_aid_stock() == [2, 0], "the Medkit's used; a scrape of 10 isn't worth a bandage")
	check(said.any(func(t: String) -> bool: return t.contains(a.settler_name) and t.contains("Medkit")), "a notice: %s" % [said])
	# The wounded: helped up once the raid's over, not during it
	b.knock_down()
	st.raid_phase = Settlement.RaidPhase.ACTIVE
	st._simulate_first_aid(st.members())
	check(b.is_down(), "not while raiders are still here")
	st.raid_phase = Settlement.RaidPhase.NONE
	st.simulate(0.1)
	check(not b.is_down(), "after: helped up with a Bandage")
	check(said.any(func(t: String) -> bool: return t.contains("helped %s up" % b.settler_name)), "by someone standing: %s" % [said])
	check(is_equal_approx(b.health.current_health, 70.0) and st.first_aid_stock() == [0, 0], "then patched up with the last one: 50 + 20 (%.0f)" % b.health.current_health)
	await _free(zone)
