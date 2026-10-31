extends "res://tests/test_case.gd"
## Increment 19.7: wood. Dead trees and fallen logs to chop round the farm
## and out in the zone, that grow back; a lumber stack; the farm's woodlot
## and the Woodcutter job that keeps the stores in planks.

const AWAY := Vector3(520, 0.1, -180)
const ZONE_TOOL := "res://tools/build_early_zone.gd"

var WOOD: ItemDefinition = load("res://resources/items/wood.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


## Stands the player beside `t`, looking at it, with an empty backpack.
func _beside(p: PlayerController, t: Node3D) -> void:
	p.inventory.clear()
	var away := Vector3(1.6, 0, 0.6)
	p.global_position = t.global_position + away + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	await wait_physics(3)


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
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


# ---------------------------------------------------------------- chopping

func test_chop_a_dead_tree_and_it_grows_back() -> void:
	var zone := await load_zone()
	var p := _player(zone)
	var tree := zone.get_node("AshCreekFarms/Timber/WoodlotTree0") as Timber
	check(tree != null and tree.timber_name == "Dead Tree" and tree.wood == 8, "a dead tree in the farm's woodlot")
	await _beside(p, tree)
	check(tree.get_prompt(p) == "Chop Dead Tree  (Wood ×8)" and is_equal_approx(tree.hold_time, 3.0), "hold E to chop: %s" % tree.get_prompt(p))
	check(tree.try_interact(p, p.head.global_position), "chopped")
	check(p.inventory.count_of(&"wood") == 8, "8 wood in the backpack (%d)" % p.inventory.count_of(&"wood"))
	check(tree.cut and not tree.standing.visible and tree.stump.visible, "a stump left")
	check(not tree.enabled, "nothing more to chop")
	var shape := tree.standing.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	await wait_physics(2)
	check(shape.disabled, "you can walk where it stood")
	check(is_equal_approx(tree.regrow_left, 72.0 * 60.0), "it grows back in 72 settlement hours (%.0f s)" % tree.regrow_left)
	tree.regrow_left = 0.05
	await wait_physics(6)
	check(not tree.cut and tree.standing.visible and tree.enabled and tree.remaining == 8, "and it's back")
	await wait_physics(2)
	check(not shape.disabled, "solid again")
	await _free(zone)


func test_a_full_backpack_leaves_the_rest() -> void:
	var zone := await load_zone()
	var p := _player(zone)
	var tree := zone.get_node("AshCreekFarms/Timber/WoodlotTree1") as Timber
	await _beside(p, tree)
	p.inventory.max_weight = 0.0
	# Fill every slot but one with planks, the last with 15 wood
	for i in p.inventory.slot_count - 1:
		p.inventory.add_item(PLANK, PLANK.max_stack)
	p.inventory.add_item(WOOD, 15)
	check(tree.try_interact(p, p.head.global_position), "chopped what fits")
	check(tree.remaining == 3 and not tree.cut, "the rest stays in the tree (%d)" % tree.remaining)
	p.inventory.add_item(WOOD, 20)
	check(tree.get_block_reason(p) != "", "full: %s" % tree.get_block_reason(p))
	await _free(zone)


func test_fallen_logs_and_the_lumber_stack() -> void:
	var zone := await load_zone()
	var p := _player(zone)
	var lg := zone.get_node("AshCreekFarms/Timber/WoodlotLog0") as Timber
	check(lg != null and lg.timber_name == "Fallen Log" and lg.wood == 6 and lg.stump == null, "a fallen log: 6 wood, no stump")
	await _beside(p, lg)
	check(lg.try_interact(p, p.head.global_position) and p.inventory.count_of(&"wood") == 6 and lg.cut and not lg.standing.visible, "chopped up")
	var stack := zone.get_node("AshCreekFarms/SalvagePiles/LumberStack") as SalvagePile
	check(stack != null, "a lumber stack by the tool shed")
	await _beside(p, stack)
	check(stack.try_interact(p, p.head.global_position) and p.inventory.count_of(&"wood_plank") == 10, "10 Wood Planks")
	await wait_physics(2)
	check(not is_instance_valid(stack) or stack.is_queued_for_deletion(), "and it's gone (it doesn't come back)")
	await _free(zone)


# ---------------------------------------------------------------- where it is

func test_wood_round_the_farm() -> void:
	var zone := await load_zone()
	var site := zone.get_node("AshCreekFarms") as Node3D
	var st := _farm(zone)
	var woodlot := site.get_node("Timber").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Woodlot"))
	check(woodlot.size() == 10, "a woodlot: 8 trees and 2 logs (%d)" % woodlot.size())
	for t: Node3D in woodlot:
		var local := site.to_local(t.global_position)
		check(local.x > 50.0 and Vector2(local.x, local.z).length() < st.claim_radius, "%s east of the yard's fence, inside the farm (%s)" % [t.name, local.snappedf(0.1)])
	check(st.wood_spots().size() == 4, "four spots for Woodcutters")
	var round := site.get_node("Timber").get_child_count() - woodlot.size()
	check(round == 9, "dead trees and logs round the farm (%d)" % round)
	# Nothing in the way of the fences the settlers will build
	for t: Node3D in site.get_node("Timber").get_children():
		var local := site.to_local(t.global_position)
		var inside_yard := local.x > -42.0 and local.x < 50.0 and local.z > -30.0 and local.z < 38.0
		var inside_fields := local.x > -50.0 and local.x < 50.0 and local.z > -66.0 and local.z < -34.0
		check(not inside_yard and not inside_fields, "%s clear of the yard and fields" % t.name)
	await _free(zone)


func test_wood_out_in_the_zone() -> void:
	var zone := instance_zone()
	var timber := zone.get_node("Timber")
	check(timber.get_child_count() >= 56, "clumps of dead trees and logs across the zone (%d)" % timber.get_child_count())
	var consts := (load(ZONE_TOOL) as GDScript).get_script_constant_map()
	var places: Dictionary = consts["PLACES"]
	var roads: Array = consts["ROADS"]
	for t: Node3D in timber.get_children():
		check(t is Timber, "%s is wood to chop" % t.name)
		var p := Vector2(t.position.x, t.position.z)
		for key in places:
			check(p.distance_to(places[key][1]) > float(places[key][2]), "%s outside %s" % [t.name, key])
		for r: Array in roads:
			var pts: Array = r[3]
			for i in pts.size() - 1:
				check(p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])) > float(r[2]) * 0.5 + 1.0, "%s off the %s" % [t.name, r[0]])
	zone.free()


# ---------------------------------------------------------------- saving

func test_cut_trees_are_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_wood"
	var zone := await load_zone()
	var p := _player(zone)
	var tree := zone.get_node("Timber").get_child(0) as Timber
	await _beside(p, tree)
	tree.try_interact(p, p.head.global_position)
	var left := tree.regrow_left
	check(tree.cut, "cut one out in the zone")
	check(saves.save_game("wood", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("wood", zone2) == OK, "loaded")
	await wait_physics(3)
	var again := zone2.get_node("Timber").get_child(0) as Timber
	check(again.cut and not again.standing.visible and absf(again.regrow_left - left) < 2.0, "still a stump, growing back (%.0f s left)" % again.regrow_left)
	check(not (zone2.get_node("Timber").get_child(1) as Timber).cut, "the others stand")
	await _free(zone2)


# ---------------------------------------------------------------- woodcutters

func test_a_woodcutter_keeps_the_stores_in_planks() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	st.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 100)
	var w := await _newcomer(zone, Settler.Role.WOODCUTTER)
	check(w.role_name() == "Woodcutter" and (w.visual.get_node("RightArm/Axe") as Node3D).visible, "a Woodcutter, with an axe")
	check(w.status_text() == "Cutting wood", "status: %s" % w.status_text())
	check(is_equal_approx(st.rates()["planks"], 3.0), "3 planks an hour")
	var before := st.planks()
	st.simulate(2.0)
	check(st.planks() == before + 6, "two hours: 6 Wood Planks in the stores (%d)" % (st.planks() - before))
	# They head for the woodlot
	w._goal = Vector3.INF
	w._enter(Settler.State.IDLE)
	await wait_physics(3)
	check(st.wood_spots().any(func(s: Node3D) -> bool: return s.global_position.distance_to(w._goal) < 3.0), "off to the woodlot")
	# Builders use what they cut
	await _newcomer(zone, Settler.Role.BUILDER)
	st.store.inventory.add_item(SCRAP, 3)
	st.simulate(1.0)  # 3 more planks: 9
	st._supply_sites()
	var run := st.sites_root.get_node("FenceFrontLeft") as ConstructionSite
	check(run.is_supplied(), "the front fence took its 9 planks from the woodcutter's stock")
	await _free(zone)


func test_no_woodlot_no_wood() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var w := await _newcomer(zone, Settler.Role.WOODCUTTER)
	st.get_node("WoodSpots").free()
	check(w.status_text() == "No woodlot here" and is_zero_approx(st.rates()["planks"]), "without a woodlot, nothing")
	var before := st.planks()
	st.simulate(3.0)
	check(st.planks() == before, "no planks")
	await _free(zone)
