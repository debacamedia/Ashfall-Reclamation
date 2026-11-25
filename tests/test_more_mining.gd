extends "res://tests/test_case.gd"
## Increment 33.3: more room to mine. The mine's tunnel has four rock faces,
## so four Miners; a Rock Face (build mode, B), put with its back against
## rock inside a place you hold, is timbered workings for two more.

const AWAY := Vector3(120, 0.1, 40)

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")


func _mine(zone: Node3D) -> Settlement:
	return zone.get_node("BlackRidgeMine/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	await wait_physics(3)
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
	check(st.request_set_role(p, s, role), "%s: %s (%s)" % [s.settler_name, Settler.ROLE_NAMES[role], st.role_refusal_reason(role)])
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


## Looks along the yard at the ridge for a spot a Rock Face fits (the way
## build mode puts one when you look at rock). Returns [xform, where the
## player stands], or [] if none.
func _spot_on_the_ridge(zone: Node3D, st: Settlement) -> Array:
	var site := zone.get_node("BlackRidgeMine") as Node3D
	var p := _player(zone)
	var space := zone.get_world_3d().direct_space_state
	var def := SettlementPlans.structure(&"rock_face")
	for z in range(-30, 34, 2):
		var from := site.to_global(Vector3(-10, 1.2, z))
		var to := site.to_global(Vector3(-46, 1.2, z))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD_SOLID))
		if hit.is_empty() or not SettlementPlans.is_rock(hit["collider"]):
			continue
		var xf := SettlementPlans.against_rock_xform(hit["position"], hit["normal"], from - to, def)
		xf.origin.y = site.global_position.y
		p.global_position = xf * Vector3(0, 0.05, 4.0)
		await wait_physics(3)
		if st.site_refusal_reason(p, &"rock_face", xf) == "":
			return [xf, p.global_position]
	return []


# ---------------------------------------------------------------- the plan

func test_the_rock_face() -> void:
	check(SettlementPlans.has(&"rock_face") and SettlementPlans.PLANS[&"rock_face"]["placeable"], "a Rock Face you plan in build mode")
	check(SettlementPlans.against_rock(&"rock_face") and not SettlementPlans.against_rock(&"bunkhouse"), "its back against rock")
	var scene := load("res://scenes/settlement/rock_face.tscn") as PackedScene
	var b := scene.instantiate() as SettlementBuilding
	add_child(b)
	await wait_physics(1)
	check(b.mine_spots().size() == 2, "room for two Miners")
	check(b.mine_spots().all(func(m: Node3D) -> bool: return m.global_basis.z.z > 0.9), "facing the rock (its back)")
	check(b.definition.id == &"rock_face" and b.definition.footprint.x >= 4.0, "a structure of its own")
	b.queue_free()
	var rock := StaticBody3D.new()
	rock.set_meta("rock", true)
	add_child(rock)
	check(SettlementPlans.is_rock(rock) and not SettlementPlans.is_rock(StaticBody3D.new()), "rock is told from anything else")
	rock.queue_free()


func test_more_miners_at_the_mine() -> void:
	var zone := await load_zone()
	var st := _mine(zone)
	await _claim(zone, st)
	var p := _player(zone)
	check(st.mine_spots().size() == 4, "the tunnel: four rock faces")
	# Against the ridge
	var found := await _spot_on_the_ridge(zone, st)
	check(not found.is_empty(), "a place against the ridge, inside the walls")
	if found.is_empty():
		await _free(zone)
		return
	var xf: Transform3D = found[0]
	# A few metres out from it, on open ground: not without rock behind it
	var reasons := []
	for out in [4.0, 6.0, 8.0, 10.0, 12.0]:
		var open := xf.translated_local(Vector3(0, 0, out))
		p.global_position = open * Vector3(0, 0.05, 4)
		await wait_physics(3)
		reasons.append(st.site_refusal_reason(p, &"rock_face", open))
	check(reasons.has("Put its back against rock") and not reasons.has(""), "open ground: %s" % [reasons])
	p.global_position = found[1]
	await wait_physics(3)
	var site := p.request_place_site(&"rock_face", xf)
	check(site != null, "planned")
	if site == null:
		await _free(zone)
		return
	await _finish(site)
	check(st.mine_spots().size() == 6, "built: six places to dig (%d)" % st.mine_spots().size())
	# Six Miners at work
	st.store.inventory.add_item(VEG, 40)
	var miners: Array[Settler] = []
	for i in 6:
		miners.append(await _newcomer(zone, st, Settler.Role.MINER))
	check(st.rates()["miners"] == 6, "six Miners at work (%d)" % st.rates()["miners"])
	# The new ones walk to the Rock Face and dig there
	var face := st.mine_spots()[5]
	check(face.get_parent().get_parent() is SettlementBuilding, "the last places are the Rock Face's")
	check(_on_navmesh(zone, face.global_position), "its places are on the navmesh")
	var last := miners[5]
	var there := false
	for i in 40:
		await wait_physics(60)
		if last.global_position.distance_to(face.global_position) < 1.3:
			there = true
			break
	check(there, "the sixth walked to the Rock Face (%.1f m off)" % last.global_position.distance_to(face.global_position))
	await _free(zone)


func _on_navmesh(zone: Node3D, at: Vector3) -> bool:
	var map := zone.get_world_3d().navigation_map
	var on := NavigationServer3D.map_get_closest_point(map, at)
	return Vector2(on.x - at.x, on.z - at.z).length() < 0.8 and absf(on.y - at.y) < 1.2


func test_no_rock_no_miners() -> void:
	var zone := await load_zone()
	var farm := zone.get_node("AshCreekFarms/Settlement") as Settlement
	check(farm.role_refusal_reason(Settler.Role.MINER) == "No rock to mine here: plan a Rock Face against rock in build mode (B)",
		"the farm: %s" % farm.role_refusal_reason(Settler.Role.MINER))
	await _free(zone)
