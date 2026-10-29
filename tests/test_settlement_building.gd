extends "res://tests/test_case.gd"
## Increment 19.6: settlers build. Claiming Ash Creek lays out its fences
## and guard posts as sites; you bring the materials (or leave them in the
## stores) and Builders put them up. Bunkhouses, storehouses, guard towers,
## guard posts and farm plots are planned in build mode. What's built adds
## beds, shelves, guard spots and fields.

const FARM := Vector3(307, 0, -106)
## Far from the farm (newcomers arrive while you're away), inside the zone.
const AWAY := Vector3(520, 0.1, -180)
const DT := 1.0 / 60.0

var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")
var PIPE: ItemDefinition = load("res://resources/items/metal_pipe.tres")
var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")


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
	return st


## A newcomer who's arrived, with a job.
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


func _site(st: Settlement, key: String) -> ConstructionSite:
	return st.sites_root.get_node_or_null(key) as ConstructionSite


func _built(zone: Node3D, id: StringName) -> Array:
	return zone.get_node("Structures").get_children().filter(func(n: Node) -> bool:
		return n is SettlementBuilding and (n as SettlementBuilding).definition.id == id and not n.is_queued_for_deletion())


## Supplies `site` from a fresh inventory and finishes it.
func _finish(st: Settlement, site: ConstructionSite) -> void:
	var inv := InventoryComponent.new()
	inv.slot_count = 40
	inv.max_weight = 0.0
	add_child(inv)
	for id: StringName in site.missing():
		inv.add_item(ItemDatabase.get_item(id), site.missing()[id])
	site.take_from(inv)
	site.add_work(site.total_hours())
	inv.queue_free()
	await wait_physics(2)


## A site for `plan` placed at `local` in the farm (validated like build mode).
func _plan(zone: Node3D, plan: StringName, local: Vector3, yaw_deg := 0.0) -> ConstructionSite:
	var st := _farm(zone)
	var p := _player(zone)
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var xf := site_root.global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), local)
	p.global_position = xf.origin + site_root.global_basis * Vector3(0, 0.1, 9)
	await wait_physics(3)
	var site := p.request_place_site(plan, xf)
	check(site != null, "planned a %s (%s)" % [plan, p.site_refusal_reason(plan, xf)])
	await wait_physics(2)
	return site


# ---------------------------------------------------------------- what can be built

func test_what_settlers_can_build() -> void:
	for id: StringName in [&"farm_fence", &"guard_post", &"guard_tower", &"bunkhouse", &"storehouse", &"farm_plot"]:
		var def := load("res://resources/structures/settlement/%s.tres" % id) as StructureDefinition
		check(def != null and def.id == id and not def.movable and ResourceLoader.exists(def.scene_path), "%s: defined, with a scene" % id)
		var b := (load(def.scene_path) as PackedScene).instantiate() as SettlementBuilding
		check(b != null and b.definition == def, "%s is a SettlementBuilding" % id)
		match id:
			&"farm_fence":
				check(is_equal_approx(def.footprint.x, 4.0), "fences come in 4 m lengths")
			&"bunkhouse":
				check(b.beds == 4, "a bunkhouse has four beds")
			&"storehouse":
				var shelves := b.get_node("Storage") as SalvageContainer
				check(shelves != null and shelves.get_node("Inventory").get("slot_count") == 60, "a storehouse has 60 slots of shelving")
			&"guard_post":
				check(b.get_node("GuardSpots").get_child_count() == 1, "a guard post has a spot for a guard")
			&"guard_tower":
				var spot := b.get_node("GuardSpots").get_child(0) as Node3D
				check(spot.position.y > 2.4, "a guard tower's spot is up on its deck (%.1f m)" % spot.position.y)
			&"farm_plot":
				check(b.get_node("FarmSpots").get_child_count() == 2 and not def.blocks_navigation, "a farm plot: two farmers, walk across it")
		b.free()
	var pl := SettlementPlans.placeable()
	check(pl.size() == 5 and pl[0] == &"bunkhouse" and pl.has(&"farm_plot") and not pl.has(&"fence"), "five things to plan in build mode")
	check(SettlementPlans.cost(&"fence", 9) == {&"wood_plank": 9, &"scrap_metal": 3}, "a fence run: a plank a length, a scrap every four")
	check(is_equal_approx(SettlementPlans.hours(&"fence", 9), 2.25), "a quarter hour a length")


# ---------------------------------------------------------------- the plan

func test_claiming_lays_out_the_plan() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	check(st.sites().is_empty(), "nothing planned before you claim it")
	check(_built(zone, &"farm_fence").is_empty() and _built(zone, &"guard_post").is_empty(), "no fence or guard posts yet")
	await _claimed(zone)
	var sites := st.sites()
	var fences := sites.filter(func(s: ConstructionSite) -> bool: return s.plan_id == &"fence")
	var posts := sites.filter(func(s: ConstructionSite) -> bool: return s.plan_id == &"guard_post")
	check(fences.size() == 11 and posts.size() == 4, "fence runs (%d) and guard posts (%d) laid out" % [fences.size(), posts.size()])
	var lengths := 0
	for f: ConstructionSite in fences:
		lengths += f.pieces.size()
	check(lengths == 132, "528 m of fence: round the yard and round the fields (%d lengths)" % lengths)
	check(sites[0].key == "FenceFrontLeft", "the yard's fence first")
	# The yard fence leaves the gateway open
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var gate := site_root.to_global(Vector3(0, 0, 36))
	for f: ConstructionSite in fences:
		for p in f.pieces:
			var at := f.global_transform * p.origin
			check(Vector2(at.x - gate.x, at.z - gate.z).length() > 5.0, "%s leaves the gateway clear" % f.key)
	# Guard posts face out from the yard's corners
	for g: ConstructionSite in posts:
		var out := -(g.global_transform * g.pieces[0]).basis.z
		var from_middle := g.centre() - st.global_position
		check(out.dot(Vector3(from_middle.x, 0, from_middle.z).normalized()) > 0.9, "%s faces out" % g.key)
	# Claiming again (a load) doesn't lay it out twice
	st.lay_out_plans()
	check(st.sites().size() == 15, "laid out once")
	await _free(zone)


func test_hand_over_materials_and_a_builder_builds_it() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	p.inventory.clear()
	var post := _site(st, "GuardPostFrontLeft")
	check(post != null and not post.is_supplied(), "a guard post waiting for materials")
	check(post.get_block_reason(p) != "", "with nothing it needs, E says what it needs: %s" % post.get_block_reason(p))
	p.inventory.add_item(PLANK, 4)
	check(post.get_prompt(p).begins_with("Hand over"), "carrying planks: %s" % post.get_prompt(p))
	p.global_position = post.work_point() + Vector3.UP * 0.1
	await wait_physics(3)
	check(st.request_deliver(p, post) == 4 and p.inventory.count_of(&"wood_plank") == 0, "hand over the planks you have")
	check(post.missing() == {&"wood_plank": 2, &"cloth": 4, &"scrap_metal": 2}, "still needs %s" % SettlementPlans.cost_text(post.missing()))
	p.inventory.add_item(PLANK, 5)
	p.inventory.add_item(CLOTH, 4)
	p.inventory.add_item(SCRAP, 2)
	st.request_deliver(p, post)
	check(post.is_supplied() and p.inventory.count_of(&"wood_plank") == 3, "it takes only what it needs")
	check(post.get_prompt(p).begins_with("Help build"), "then E (held) helps build: %s" % post.get_prompt(p))
	# Nobody's building yet
	st.simulate(3.0)
	check(is_zero_approx(post.work), "no Builder, no progress")
	# A builder
	var b := await _newcomer(zone, Settler.Role.BUILDER)
	check(b.role == Settler.Role.BUILDER and b.role_name() == "Builder", "a Builder")
	check((b.visual.get_node("HardHat") as Node3D).visible and (b.visual.get_node("RightArm/Hammer") as Node3D).visible, "in a hard hat, with a hammer")
	check(b.status_text() == "Building the guard post", "status: %s" % b.status_text())
	var said := []
	st.notice.connect(func(t: String) -> void: said.append(t))
	st.simulate(1.0)
	check(post.progress() > 0.45 and post.progress() < 0.55, "an hour's work: half built (%.2f)" % post.progress())
	# You can lend a hand
	var before := post.work
	check(p.request_help_build(post) and post.work > before, "holding E helps")
	st.simulate(1.0)
	await wait_physics(2)
	check(not is_instance_valid(post) or post.is_queued_for_deletion(), "done: the site goes")
	var built := _built(zone, &"guard_post")
	check(built.size() == 1, "and a guard post stands there")
	check(said.any(func(t: String) -> bool: return t.contains("Guard Post")), "a notice: %s" % [said])
	check(st.guard_posts().size() == 1, "a spot for a guard")
	await _free(zone)


func test_builders_take_materials_from_the_stores_and_fences_go_up_a_length_at_a_time() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	await _newcomer(zone, Settler.Role.BUILDER)
	var run := _site(st, "FenceFrontLeft")
	check(run.pieces.size() == 9 and run.total_cost() == {&"wood_plank": 9, &"scrap_metal": 3}, "36 m of fence: 9 planks, 3 scrap")
	st.store.inventory.add_item(PLANK, 9)
	st.store.inventory.add_item(SCRAP, 3)
	st._supply_sites()
	check(run.is_supplied() and st.store.inventory.count_of(&"wood_plank") == 0, "it took them from the Farm Store")
	st.simulate(1.0)
	await wait_physics(2)
	check(_built(zone, &"farm_fence").size() == 4, "an hour in: four lengths up (%d)" % _built(zone, &"farm_fence").size())
	st.simulate(1.3)
	await wait_physics(2)
	check(_built(zone, &"farm_fence").size() == 9 and not is_instance_valid(run), "then all nine, and the site's gone")
	# Each length stands where the plan put it, in a line
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	for f: Node3D in _built(zone, &"farm_fence"):
		var local := site_root.to_local(f.global_position)
		check(absf(local.z - 36.0) < 0.1 and local.x > -40.0 and local.x < -4.0, "%s on the front line (%s)" % [f.name, local.snappedf(0.1)])
	await _free(zone)


func test_call_off_gives_the_materials_back() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var run := _site(st, "FieldFenceBack")
	p.inventory.clear()
	p.inventory.add_item(PLANK, 10)
	st.request_deliver(p, run)
	check(int(run.delivered.get(&"wood_plank", 0)) == 10 and p.inventory.count_of(&"wood_plank") == 0, "handed over 10 planks")
	check(st.request_cancel_site(p, run), "called it off")
	await wait_physics(2)
	check(p.inventory.count_of(&"wood_plank") == 10, "the planks come back to you")
	check(_site(st, "FieldFenceBack") == null and st.sites().size() == 14, "it's gone from the plan")
	await _free(zone)


# ---------------------------------------------------------------- planning in build mode

func test_plan_buildings_in_build_mode() -> void:
	var zone := await load_zone()
	var p := _player(zone)
	var bm := p.get_node("%BuildMode") as BuildMode
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	# Before it's yours: nothing to plan
	p.global_position = site_root.to_global(Vector3(20, 0.1, 30))
	await wait_physics(3)
	bm.refresh_kits()
	check(bm.plans.is_empty(), "nothing to plan before you hold the farm")
	var st := await _claimed(zone)
	p.inventory.clear()
	p.global_position = site_root.to_global(Vector3(22, 0.1, 30))
	p.rotation.y = site_root.rotation.y  # facing the farm's back (-z)
	p.head.rotation.x = deg_to_rad(-20)
	await wait_physics(3)
	check(bm.enter(), "B in the farm with no kits: there are buildings to plan")
	check(bm.plans.has(&"bunkhouse") and bm.current_plan() == &"bunkhouse", "the list has the bunkhouse")
	check(bm.title_text().begins_with("Plan: Bunkhouse"), "title: %s" % bm.title_text())
	bm.update_preview()
	check(bm.ghost_valid, "the yard's front right is clear for it (%s)" % bm.ghost_reason)
	var local := site_root.to_local(bm.ghost_transform.origin)
	check(local.z < 30.0 - 3.0, "its near side where you look (%s)" % local.snappedf(0.1))
	bm.place()
	await wait_physics(2)
	var planned := st.sites().filter(func(s: ConstructionSite) -> bool: return s.plan_id == &"bunkhouse")
	check(planned.size() == 1 and planned[0].key == "", "a bunkhouse site")
	bm.update_preview()
	check(not bm.ghost_valid and bm.ghost_reason.contains("planned"), "can't plan another on top: %s" % bm.ghost_reason)
	bm.exit()
	# Outside the farm it's refused
	var out := Transform3D(Basis.IDENTITY, site_root.to_global(Vector3(0, 0, 120)))
	check(p.site_refusal_reason(&"bunkhouse", out) != "", "not out past the farm")
	check(p.request_place_site(&"fence", Transform3D(Basis.IDENTITY, site_root.to_global(Vector3(20, 0, 20)))) == null, "fences aren't planned by hand")
	await _free(zone)


func test_a_bunkhouse_brings_more_people() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	check(st.total_beds() == 4, "four beds to start")
	var site := await _plan(zone, &"bunkhouse", Vector3(20, 0, 24))
	await _finish(st, site)
	var b := _built(zone, &"bunkhouse")
	check(b.size() == 1 and st.total_beds() == 8, "a bunkhouse: eight beds (%d)" % st.total_beds())
	check(b[0] is SettlementBuilding and (b[0] as SettlementBuilding).settlement() == st, "it belongs to the farm")
	await _free(zone)


func test_a_storehouse_holds_more_food() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var site := await _plan(zone, &"storehouse", Vector3(22, 0, 24))
	await _finish(st, site)
	check(st.stores().size() == 2 and st.food_capacity() == 2400, "two sets of shelves: room for 2,400 (%d)" % st.food_capacity())
	st.store.inventory.add_item(VEG, 1200 - st.food())
	st._add_food(30)
	check(st.food() == 1230, "food goes onto the storehouse shelves when the barn's full")
	st._eat(1210)
	check(st.food() == 20, "and is eaten from both")
	await _free(zone)


func test_farm_plots_make_room_for_more_farmers() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	st.water = st.water_capacity
	st.pump_working = true
	st.store.inventory.add_item(VEG, 200)
	check(st.farm_spots().size() == 8, "four fields: eight farmers")
	var farmers: Array[Settler] = []
	for i in 9:
		farmers.append(await _newcomer(zone, Settler.Role.FARMER))
	st.simulate(0.1)
	check(st.rates()["farmers"] == 8, "nine farmers, eight at work (%d)" % st.rates()["farmers"])
	check(farmers.filter(func(s: Settler) -> bool: return s.no_field).size() == 1, "one has no field")
	check(farmers.any(func(s: Settler) -> bool: return s.status_text() == "No field free"), "and says so")
	var site := await _plan(zone, &"farm_plot", Vector3(24, 0, 22))
	await _finish(st, site)
	st.simulate(0.1)
	check(st.farm_spots().size() == 10 and st.rates()["farmers"] == 9, "a farm plot: all nine at work")
	await _free(zone)


func test_guards_stand_at_the_posts() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var a := await _newcomer(zone, Settler.Role.GUARD)
	var b := await _newcomer(zone, Settler.Role.GUARD)
	await _finish(st, _site(st, "GuardPostFrontLeft"))
	var tower := await _plan(zone, &"guard_tower", Vector3(30, 0, 26))
	await _finish(st, tower)
	var spots := st.guard_posts()
	check(spots.size() == 2, "a guard post and a tower")
	for g in [a, b]:
		(g as Settler)._goal = Vector3.INF
		(g as Settler)._enter(Settler.State.IDLE)
	await wait_physics(3)
	var goals := [a._goal, b._goal]
	check(spots.any(func(s: Node3D) -> bool: return s.global_position.distance_to(goals[0]) < 0.5)
		and spots.any(func(s: Node3D) -> bool: return s.global_position.distance_to(goals[1]) < 0.5)
		and goals[0].distance_to(goals[1]) > 1.0, "each guard heads for a post of their own")
	# The tower's deck can be walked to (the navmesh goes up the stair)
	var up := (_built(zone, &"guard_tower")[0] as SettlementBuilding).guard_spots()[0].global_position
	var on := Vector3.INF
	for i in 600:
		await wait_physics(1)
		on = NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, up)
		if on.distance_to(up) < 0.6:
			break
	check(on.distance_to(up) < 0.6, "the navmesh reaches the tower's deck (%.2f m off)" % on.distance_to(up))
	await _free(zone)


# ---------------------------------------------------------------- saving

func test_sites_and_buildings_are_saved() -> void:
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_settlement_building"
	var zone := await load_zone()
	var st := await _claimed(zone)
	var p := _player(zone)
	var run := _site(st, "FenceFrontLeft")
	p.inventory.add_item(PLANK, 9)
	p.inventory.add_item(SCRAP, 3)
	st.request_deliver(p, run)
	run.add_work(1.0)  # four lengths
	var bunk := await _plan(zone, &"bunkhouse", Vector3(20, 0, 24))
	p.inventory.add_item(PLANK, 12)
	st.request_deliver(p, bunk)
	await _finish(st, _site(st, "GuardPostFrontRight"))
	await wait_physics(2)
	check(saves.save_game("building", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("building", zone2) == OK, "loaded")
	await wait_physics(5)
	var st2 := _farm(zone2)
	check(st2.sites().size() == 15, "the plan's sites (one built) plus the bunkhouse: %d" % st2.sites().size())
	var run2 := _site(st2, "FenceFrontLeft")
	check(run2 != null and run2.built == 4 and run2.is_supplied() and is_equal_approx(run2.work, 1.0), "the fence run, four lengths in")
	check(_built(zone2, &"farm_fence").size() == 4, "and those four lengths stand")
	var bunk2 := st2.sites().filter(func(s: ConstructionSite) -> bool: return s.plan_id == &"bunkhouse")
	check(bunk2.size() == 1 and int(bunk2[0].delivered.get(&"wood_plank", 0)) == 12, "the bunkhouse with its 12 planks")
	check(_built(zone2, &"guard_post").size() == 1 and _site(st2, "GuardPostFrontRight") == null, "the built guard post, not planned again")
	await _free(zone2)


func test_a_farm_claimed_before_builders_gets_its_plan() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var data := SaveManager.build_save_data(zone)
	# Make it an Increment 19 save: no sites, no plans_laid
	var kept := []
	for e: Dictionary in data["nodes"]:
		if str(e["scene"]).ends_with("construction_site.tscn"):
			continue
		(e["data"] as Dictionary).erase("plans_laid")
		kept.append(e)
	data["nodes"] = kept
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	await _free(zone)
	var zone2 := await load_zone()
	SaveManager.apply_save_data(old, zone2)
	await wait_physics(3)
	check(_farm(zone2).is_claimed and _farm(zone2).sites().size() == 15, "claimed, and the plan is laid out (%d)" % _farm(zone2).sites().size())
	await _free(zone2)
	var _st := st
