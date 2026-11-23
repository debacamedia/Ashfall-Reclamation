extends "res://tests/fortify_helpers.gd"
## Increment 28: sheep, wool, the Tailor, everyone dressed, and Ash Creek's
## palisade.
##
## Sheep come in a Sheep Pen (build mode), fed by a Rancher like the other
## animals; a fed sheep grows a fleece each day, and a Farmer shears it for
## Wool into the stores. A Tailor at a Tailor's Table (build mode) spins Wool
## into Wool Clothes until the stores hold six, then makes padded armour from
## clothes beyond those, Leather and Scrap Metal. Settlers with nothing on
## their back put on clothes from the stores; armour goes to guards first,
## then everyone else. And once everything else at Ash Creek is built, its
## fences become a palisade with palisade gates, then that's reinforced.

const FARM_AWAY := Vector3(520, 0.1, -180)

var WOOL: ItemDefinition = load("res://resources/items/wool.tres")
var CLOTHES: ItemDefinition = load("res://resources/items/wool_clothes.tres")
var LEATHER: ItemDefinition = load("res://resources/items/leather.tres")
var COAT: ItemDefinition = load("res://resources/items/padded_coat.tres")
var HOOD: ItemDefinition = load("res://resources/items/padded_hood.tres")
var VEST: ItemDefinition = load("res://resources/items/plated_vest.tres")


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _hand_over(site: ConstructionSite) -> void:
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


## Plans `plan` at `local` in the farm, as you would in build mode, and builds it.
func _put_up(zone: Node3D, plan: StringName, local: Vector3) -> SettlementBuilding:
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
	await _hand_over(site)
	p.global_position = back
	await wait_physics(2)
	var found: SettlementBuilding = null
	for n in zone.get_node("Structures").get_children():
		if n is SettlementBuilding and (n as SettlementBuilding).definition.id == SettlementPlans.PLANS[plan]["structure"] and not n.is_queued_for_deletion():
			found = n
	return found


func _farm_settler(st: Settlement, role: Settler.Role) -> Settler:
	var s := st.spawn_newcomer()
	await wait_physics(70)
	var p := _player(st.get_parent().get_parent() as Node3D)
	if role != Settler.Role.NONE:
		check(st.request_set_role(p, s, role), "%s: %s (%s)" % [s.settler_name, Settler.ROLE_NAMES[role], st.role_refusal_reason(role)])
	return s


## Claims the farm with its plan put aside (its fences would take the
## materials these tests hand over).
func _farm_claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	await _claim(zone, st)
	for site in st.sites():
		site.free()
	st.defence_stage = 9
	st.hour_seconds = 100000.0  # (the clock's run by hand here)
	_player(zone).global_position = FARM_AWAY
	st.store.inventory.add_item(load("res://resources/items/vegetables.tres"), 200)
	return st


func test_wool_clothes_and_padded_armour() -> void:
	check(WOOL != null and WOOL.max_stack >= 20 and not WOOL.is_armour(), "Wool: a material that stacks")
	check(CLOTHES.is_armour() and CLOTHES.armour_slot == ArmourSet.BODY and is_equal_approx(CLOTHES.armour_protection, 0.05),
		"Wool Clothes: worn on the body, 5% off hits")
	var leather_jacket: ItemDefinition = load("res://resources/items/leather_jacket.tres")
	check(COAT.armour_protection > leather_jacket.armour_protection and COAT.armour_protection < VEST.armour_protection,
		"the Padded Coat sits between a leather jacket and a plated vest (%.2f)" % COAT.armour_protection)
	for id: StringName in [&"wool_clothes", &"padded_hood", &"padded_coat", &"padded_trousers"]:
		var r := load("res://resources/recipes/%s.tres" % id) as RecipeDefinition
		check(r != null and r.station == RecipeDefinition.Station.WORKBENCH, "%s: made at a workbench (by you or a Tailor)" % id)
		if id != &"wool_clothes":
			var ins := {}
			for it: ItemDefinition in r.inputs:
				ins[it.id] = r.inputs[it]
			check(ins.has(&"wool_clothes") and ins.has(&"leather") and ins.has(&"scrap_metal"), "%s: from clothes, leather and scrap (%s)" % [id, ins])
	check(SettlementPlans.PLANS[&"sheep_pen"]["placeable"] and SettlementPlans.PLANS[&"tailors_table"]["placeable"], "a Sheep Pen and a Tailor's Table to plan in build mode")
	var pen := (load("res://scenes/settlement/sheep_pen.tscn") as PackedScene).instantiate() as SettlementBuilding
	check(pen.animal_kind == &"sheep" and pen.animal_capacity == 6 and pen.shear_spots().size() == 1, "the Sheep Pen: 6 sheep, a shearing stand")
	pen.free()
	var table := (load("res://scenes/settlement/tailors_table.tscn") as PackedScene).instantiate() as SettlementBuilding
	check(table.is_tailors_table() and table.tailor_spots().size() == 1, "the Tailor's Table: a place to work")
	table.free()
	check(Settler.ROLE_NAMES.has(Settler.Role.TAILOR) and Settler.Role.TAILOR == 9, "the Tailor job (added last, so saved jobs keep their numbers)")


func test_sheep_grow_wool_and_farmers_shear_it() -> void:
	var zone := await load_zone()
	var st := await _farm_claimed(zone)
	var pen := await _put_up(zone, &"sheep_pen", Vector3(30, 0, 20))
	check(pen != null and pen.is_pen(), "a Sheep Pen built")
	if pen == null:
		await _free(zone)
		return
	st.simulate(0.1)
	check(pen.count() == 2 and pen.animals().all(func(a: FarmAnimal) -> bool: return a.kind == &"sheep"), "a pair of sheep arrives")
	check(st.role_refusal_reason(Settler.Role.RANCHER) == "", "a Rancher can tend them")
	await _farm_settler(st, Settler.Role.RANCHER)
	st.simulate(12.0)
	check(st._stores_count(&"wool") == 0 and pen.egg_progress >= 0.99, "fed for half a day: their fleece is grown, but nobody's shearing (%.2f)" % pen.egg_progress)
	st.simulate(48.0)
	check(pen.egg_progress <= float(pen.count()) + 0.001, "a fleece a sheep at most, waiting (%.1f for %d)" % [pen.egg_progress, pen.count()])
	var f := await _farm_settler(st, Settler.Role.FARMER)
	await wait_physics(10)
	check(f._shearing() and f.status_text() == "Shearing the sheep", "a Farmer: off to shear (%s)" % f.status_text())
	var spot := pen.shear_spots()[0].global_position
	for i in 3000:
		await wait_physics(1)
		if f.global_position.distance_to(spot) < 1.5:
			break
	check(f.global_position.distance_to(spot) < 1.5, "at the shearing stand (%.1f m off)" % f.global_position.distance_to(spot))
	var fleeces := floori(minf(pen.egg_progress + pen.count() / 24.0, float(pen.count())))
	var said: Array[String] = []
	st.notice.connect(func(t: String) -> void: said.append(t))
	st.simulate(1.0)
	check(fleeces >= 1 and st._stores_count(&"wool") == fleeces * 2 and pen.egg_progress < 1.0, "sheared: %d Wool into the stores, 2 a fleece (%d fleeces)" % [st._stores_count(&"wool"), fleeces])
	check(said.any(func(t: String) -> bool: return t.contains("sheared") and t.contains("Wool")), "a notice: %s" % [said])
	await wait_physics(10)
	check(not f._shearing() and f.status_text() != "Shearing the sheep", "then back to the fields")
	check(Settlement.butcher_yield(&"sheep") == {&"raw_meat": 3, &"wool": 2}, "butchered, a sheep gives 3 meat and its fleece")
	await _free(zone)


func test_the_tailor_keeps_six_clothes_then_makes_armour() -> void:
	var zone := await load_zone()
	var st := await _farm_claimed(zone)
	check(st.role_refusal_reason(Settler.Role.TAILOR).contains("Tailor's Table"), "no Tailor without a Tailor's Table")
	var table := await _put_up(zone, &"tailors_table", Vector3(24, 0, 28))
	check(table != null and st.tailors_tables().size() == 1, "a Tailor's Table built")
	var t := await _farm_settler(st, Settler.Role.TAILOR)
	st.simulate(1.0)
	check(st.tailor_status().contains("Needs Wool"), "no wool: %s" % st.tailor_status())
	st.store.inventory.add_item(WOOL, 30)
	st.simulate(0.5)
	check(st.tailor_status().begins_with("Making Wool Clothes"), "wool: %s" % st.tailor_status())
	st.simulate(5.5)
	check(st.clothes() == 6 and st._stores_count(&"wool") == 12, "six hours: 6 Wool Clothes in the stores, 18 Wool used (%d, %d left)" % [st.clothes(), st._stores_count(&"wool")])
	st.simulate(2.0)
	check(st.clothes() == 6 and st.tailor_status().contains("needs Leather"), "six in the stores: no more clothes, and no leather for armour: %s" % st.tailor_status())
	st.store.inventory.add_item(LEATHER, 10)
	st.store.inventory.add_item(load("res://resources/items/scrap_metal.tres"), 30)
	var low := 99
	var said: Array[String] = []
	for i in 48:
		st.simulate(0.5)
		low = mini(low, st.clothes())
		said.append(st.tailor_status())
	check(said.any(func(x: String) -> bool: return x.begins_with("Making Padded Coat")), "then armour, the coat first, from clothes beyond the six")
	var lock := st.armory.inventory
	check(lock.count_of(&"padded_coat") >= 1 and lock.count_of(&"padded_hood") >= 1 and lock.count_of(&"padded_trousers") >= 1,
		"a day on: padded pieces in the Armory Locker (%d coats, %d hoods, %d trousers)" % [lock.count_of(&"padded_coat"), lock.count_of(&"padded_hood"), lock.count_of(&"padded_trousers")])
	check(low >= 6, "and never fewer than six clothes left in the stores (fewest %d)" % low)
	check(st._stores_count(&"wool") < 3 and st.tailor_status().contains("Wool"), "the wool used up: %s" % st.tailor_status())
	check(st.save_state().has("tailor_job"), "what they're making is saved")
	var _t := t
	await _free(zone)


func test_everyone_dressed_guards_first() -> void:
	var zone := await load_zone()
	var st := await _farm_claimed(zone)
	var g := await _farm_settler(st, Settler.Role.GUARD)
	var a := await _farm_settler(st, Settler.Role.FARMER)
	var b := await _farm_settler(st, Settler.Role.NONE)
	for s in [g, a, b]:
		st._return_armour(s, null)
	st.armory.inventory.clear()
	st.store.inventory.add_item(CLOTHES, 4)
	st.armory.inventory.add_item(COAT, 1)
	st.armory.inventory.add_item(HOOD, 2)
	st._supply_guards()
	check(g.armour.worn(ArmourSet.BODY) == COAT and g.armour.worn(ArmourSet.HEAD) == HOOD, "the guard first: the coat and a hood")
	var others := [a, b]
	check(others.filter(func(s: Settler) -> bool: return s.armour.worn(ArmourSet.HEAD) == HOOD).size() == 1, "the other hood to one of the others")
	check(others.all(func(s: Settler) -> bool: return s.armour.worn(ArmourSet.BODY) == CLOTHES), "the others put on Wool Clothes from the stores")
	check(st.clothes() == 2, "two sets left in the stores")
	# A plated vest comes in: the guard takes it, the coat goes on to another
	st.armory.inventory.add_item(VEST, 1)
	st._supply_guards()
	st._supply_guards()
	check(g.armour.worn(ArmourSet.BODY) == VEST, "a plated vest for the guard")
	check(others.filter(func(s: Settler) -> bool: return s.armour.worn(ArmourSet.BODY) == COAT).size() == 1, "the coat to someone in clothes")
	check(st.clothes() == 3, "whose clothes go back on the shelf")
	# Guards first: a guard with only clothes on keeps a coat from the others
	var g2 := await _farm_settler(st, Settler.Role.GUARD)
	st._return_armour(g2, null)
	st.store.inventory.clear()
	st.store.inventory.add_item(CLOTHES, 1)
	st._supply_guards()
	check(g2.armour.worn(ArmourSet.BODY) == CLOTHES, "a new guard, no armour about: clothes for now")
	st._supply_guards()
	var spare: ItemDefinition = load("res://resources/items/padded_coat.tres")
	st.armory.inventory.add_item(spare, 1)
	# (the farmer in clothes would like it too, but the guard comes first)
	st._supply_guards()
	check(g2.armour.worn(ArmourSet.BODY) == COAT, "the next coat goes to the guard")
	# It counts: a blow on someone in clothes is a little softer
	var hit := DamageInfo.create(20.0, DamageInfo.Type.MELEE, null)
	var dressed := (others.filter(func(s: Settler) -> bool: return s.armour.worn(ArmourSet.BODY) == CLOTHES)[0]) as Settler if others.any(func(s: Settler) -> bool: return s.armour.worn(ArmourSet.BODY) == CLOTHES) else b
	var before := dressed.health.current_health
	dressed.health.apply_damage(hit)
	check(before - dressed.health.current_health < 20.0, "a settler in clothes takes less from a blow (%.1f of 20)" % (before - dressed.health.current_health))
	await _free(zone)


func test_ash_creek_palisade_after_everything() -> void:
	var zone := await load_zone()
	var farm := _farm(zone)
	# Every run of palisade to come is clear of anything solid, as thick as a
	# reinforced length
	var space := zone.get_world_3d().direct_space_state
	for m in farm.get_node("Plans").get_children():
		if int(m.get_meta("stage", 1)) < 3 or not m.has_meta("to"):
			continue
		var a := farm.to_global((m as Node3D).position)
		var b := farm.to_global(m.get_meta("to"))
		var blocked := []
		var n := int(a.distance_to(b) / 1.0)
		for j in range(1, n):
			var q := PhysicsShapeQueryParameters3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.55, 1.0, 0.55)
			q.shape = box
			q.transform = Transform3D(Basis.IDENTITY, a.lerp(b, float(j) / n) + Vector3.UP * 0.8)
			q.collision_mask = PhysicsLayers.STRUCTURES
			for h in space.intersect_shape(q, 4):
				blocked.append(str((h["collider"] as Node).name))
		check(blocked.is_empty(), "%s: clear all along (%s)" % [m.name, blocked])
	await _claim(zone, farm)
	# The gates built, but the fences still to do: no watchtowers yet
	await _finish_these(farm, ["GateFront", "GateBack", "GateField"])
	check(farm.defence_stage == 1, "the gates built, the fences not: the next stage waits for everything")
	await _finish_these(farm, [])
	check(farm.defence_stage == 2 and _keys(farm).has("TowerFrontLeft"), "everything built: watchtowers")
	await _finish_these(farm, [])
	var keys := _keys(farm)
	check(farm.defence_stage == 3, "the watchtowers up: the third stage")
	check(keys.filter(func(k: String) -> bool: return k.begins_with("PalisadeFence") or k.begins_with("PalisadeField")).size() == 11
		and keys.has("PalisadeGateFront") and keys.has("PalisadeGateBack") and keys.has("PalisadeGateField"),
		"the yard's and the fields' fences to become a palisade, and the gates palisade gates (%d sites)" % keys.size())
	var fences := _built(farm, &"farm_fence").size()
	check(fences == 132, "132 lengths of fence standing till then (%d)" % fences)
	await _finish_these(farm, [])
	check(_built(farm, &"farm_fence").is_empty() and _built(farm, &"palisade").size() == 132, "built: a palisade all round, no fence left")
	check(_built(farm, &"settlement_gate").is_empty() and _built(farm, &"palisade_gate").size() == 3, "and three palisade gates")
	check(farm.defence_stage == 4 and _keys(farm).any(func(k: String) -> bool: return k.begins_with("Reinforce")), "then the reinforcing")
	await _wait_nav(zone)
	var goal := farm.raid_goal()
	var gates := _built(farm, &"palisade_gate")
	for rp in farm.get_node("RaidPoints").get_children():
		var path := _path(zone, (rp as Node3D).global_position, goal)
		var through := gates.any(func(g: Node) -> bool: return _closest_to_gate(path, g as SettlementGate) < 1.0)
		check(path.size() > 1 and path[-1].distance_to(goal) < 1.0 and through, "from %s: into the yard only through a gate" % rp.get_meta("label"))
	await _finish_these(farm, [])
	check(_built(farm, &"reinforced_palisade").size() == 132 and _built(farm, &"palisade").is_empty(), "and reinforced, all 132 lengths")
	await _free(zone)


func _built(st: Settlement, id: StringName) -> Array:
	return get_tree().get_nodes_in_group("settlement_buildings").filter(
		func(b: Node) -> bool: return not b.is_queued_for_deletion() and (b as SettlementBuilding).settlement() == st and (b as Structure).definition.id == id)


func _finish_these(st: Settlement, keys: Array) -> void:
	for site in st.sites():
		if keys.is_empty() or keys.has(site.key):
			site.delivered = site.total_cost().duplicate()
			site.add_work(site.total_hours())
	await wait_physics(5)
