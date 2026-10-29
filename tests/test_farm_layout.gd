extends "res://tests/test_case.gd"
## Increment 19.5: Ash Creek Farms laid out again. The railway runs past the
## farm instead of through it, with a level crossing where the lane comes in;
## the buildings face a yard; the food goes on shelves at the back of the barn.

const TRUCK_SCENE := preload("res://scenes/vehicles/cargo_truck.tscn")
const ZONE_TOOL := "res://tools/build_early_zone.gd"
const DT := 1.0 / 60.0

var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")


func _site(zone: Node3D) -> Node3D:
	return zone.get_node("AshCreekFarms") as Node3D


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


## The farm as built, before its plain meshes are merged at load.
func _plan() -> Node3D:
	return (load("res://levels/ash_creek_farms/ash_creek_farms.tscn") as PackedScene).instantiate() as Node3D


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _rail_points(step := 1.0) -> PackedVector3Array:
	var rail: Array = (load(ZONE_TOOL) as GDScript).get_script_constant_map()["RAIL"]
	var out := PackedVector3Array()
	for i in rail.size() - 1:
		var a: Vector2 = rail[i]
		var b: Vector2 = rail[i + 1]
		var n := ceili(a.distance_to(b) / step)
		for j in n:
			var q := a.lerp(b, float(j) / n)
			out.append(Vector3(q.x, 0, q.y))
	return out


func _ticks(p: PlayerController, f: InputFrame, n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		p.simulate(f, DT)


# ---------------------------------------------------------------- the railway

func test_the_railway_runs_past_the_farm() -> void:
	var zone := await load_zone()
	var site := _site(zone)
	var near := 0
	for q in _rail_points():
		var local := site.to_local(q)
		if absf(local.x) < 60.0 and local.z > -80.0:
			near += 1
			check(local.z > 44.0, "the tracks pass in front of the farm, past its gateway (at %s)" % local.snappedf(0.1))
	check(near > 50, "the tracks run along the farm's front (%d samples)" % near)
	# Nothing solid stands on the tracks anywhere: no fences, beams or walls
	var space := zone.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.6, 0.6)
	q.shape = box
	q.collision_mask = PhysicsLayers.STRUCTURES
	var pts := _rail_points(1.0)
	var blocked := []
	for i in range(1, pts.size()):
		var dir := (pts[i] - pts[i - 1]).normalized()
		q.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI / 2.0), pts[i] + Vector3.UP * 1.0)
		for hit in space.intersect_shape(q, 8):
			var who := hit["collider"] as Node
			var path := str(zone.get_path_to(who)) if who != null else ""
			# (the buffer stop at the end of the line; the storm's wall where it leaves the zone)
			if who != null and not path.contains("BufferStop") and not path.begins_with("Boundary"):
				blocked.append("%s at %s" % [zone.get_path_to(who), pts[i].snappedf(1)])
	check(blocked.is_empty(), "nothing solid across the tracks %s" % [blocked.slice(0, 4)])
	await _free(zone)


func test_a_level_crossing_where_the_lane_meets_the_tracks() -> void:
	var zone := await load_zone()
	var site := _site(zone)
	var crossings := zone.find_children("Crossing*", "Node3D", true, false).filter(func(n: Node) -> bool: return n.get_parent().name == "LevelCrossings")
	check(crossings.size() >= 2, "level crossings where roads meet the railway (%d)" % crossings.size())
	var lane_at := site.to_global(Vector3(0, 0, 50))
	var ours: Node3D = null
	for c: Node3D in crossings:
		if Vector2(c.global_position.x - lane_at.x, c.global_position.z - lane_at.z).length() < 4.0:
			ours = c
	check(ours != null, "one on the farm lane (%s)" % lane_at.snappedf(0.1))
	if ours != null:
		var planks := ours.find_children("Planks*", "MeshInstance3D", false, false)
		check(planks.size() == 3, "planks between and beside the rails")
		for pl: MeshInstance3D in planks:
			var top := pl.position.y + (pl.mesh as BoxMesh).size.y / 2.0
			check(top > 0.42 and top < 0.5, "level with the rail tops (%.2f m)" % top)
		check(ours.find_children("Crossbuck*", "StaticBody3D", false, false).size() == 2, "a crossing sign each side")
	await _free(zone)


func test_drive_off_the_road_over_the_tracks_into_the_yard() -> void:
	var zone := await load_zone()
	var site := _site(zone)
	# The gateway is high enough
	var plan := _plan()
	var beam := plan.get_node("Props/Gateway/Beam") as MeshInstance3D
	check(beam.position.y - 0.15 > 4.2, "the gateway's beam is high over the lane (%.1f m)" % (beam.position.y - 0.15))
	plan.free()
	var t := TRUCK_SCENE.instantiate() as Truck
	zone.add_child(t)
	t.global_transform = Transform3D(Basis(Vector3.UP, site.rotation.y + PI), site.to_global(Vector3(0, 0.15, 92)))
	t.fuel = 20.0
	await wait_physics(30)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = t.global_transform * Vector3(2.3, 0.05, 1.2)
	await wait_physics(3)
	check(t.door.try_interact(p, p.head.global_position), "get in on the main road")
	var stuck := 0
	for target in [Vector3(0, 0, 66), Vector3(0, 0, 50), Vector3(0, 0, 36), Vector3(0, 0, 14)]:
		var goal := site.to_global(target)
		var n := 0
		while Vector2(t.global_position.x - goal.x, t.global_position.z - goal.z).length() > 3.0 and n < 900:
			var f := t.global_basis.z
			var to := Vector2(goal.x - t.global_position.x, goal.z - t.global_position.z)
			var err := wrapf(atan2(to.x, to.y) - atan2(f.x, f.z), -PI, PI)
			var fr := InputFrame.new()
			fr.move = Vector2(clampf(-err * 2.0, -1.0, 1.0), -0.55)
			await _ticks(p, fr, 1)
			n += 1
			if n > 60 and t.forward_speed() < 0.5:
				stuck += 1
		check(Vector2(t.global_position.x - goal.x, t.global_position.z - goal.z).length() <= 3.0, "reached %s" % target)
	check(stuck < 30, "nothing in the way: it never stalls (%d frames slow)" % stuck)
	check(t.global_basis.y.y > 0.95, "upright, in the yard")
	await _free(zone)


# ---------------------------------------------------------------- the layout

func test_the_buildings_face_a_yard() -> void:
	var zone := await load_zone()
	var site := _site(zone)
	var yard := Vector3(0, 0, 6)
	for b_name in ["Farmhouse", "Barn", "ToolShed", "PumpHouse", "ChickenCoop"]:
		var b := site.get_node("Buildings/" + b_name) as StaticBody3D
		var best := -1.0
		for d: Array in b.get_meta("doors"):
			var door: Vector3 = d[0]
			var out: Vector3 = d[1]
			best = maxf(best, out.dot((yard - door).normalized()))
		check(best > 0.3, "%s's door opens toward the yard (%.2f)" % [b_name, best])
	# The fields in a row behind the farmhouse
	var plan := _plan()
	var house_z := (site.get_node("Buildings/Farmhouse") as Node3D).position.z
	var soils := plan.get_node("Fields").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Soil"))
	check(soils.size() == 4, "four fields")
	for s: Node3D in soils:
		check(s.position.z < house_z - 20.0 and is_equal_approx(s.position.z, (soils[0] as Node3D).position.z), "%s in the row behind the farmhouse" % s.name)
	# Farmers work in the fields
	for m: Node3D in _farm(zone).get_node("FarmSpots").get_children():
		var inside := soils.any(func(s: Node3D) -> bool:
			var sz: Vector2 = ((s as MeshInstance3D).mesh as PlaneMesh).size
			return absf(m.position.x - s.position.x) < sz.x / 2.0 and absf(m.position.z - s.position.z) < sz.y / 2.0)
		check(inside, "%s is in a field" % m.name)
	# No perimeter fence or guard posts yet: settlers build those (19.6)
	check(plan.get_node_or_null("Props/LaneFence") == null, "no old lane fence")
	plan.free()
	await _free(zone)


# ---------------------------------------------------------------- food shelves

func test_food_shelves_at_the_back_of_the_barn() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	var store := st.store
	check(store != null and store.scene_file_path.ends_with("food_shelves.tscn"), "the Farm Store is the food shelves")
	check(store.inventory.slot_count == 60, "60 slots")
	check(st.food_capacity() == 1200, "holds 1,200 vegetables (%d)" % st.food_capacity())
	var barn := zone.get_node("AshCreekFarms/Buildings/Barn") as StaticBody3D
	var local := barn.global_transform.affine_inverse() * store.global_position
	var size: Vector2 = barn.get_meta("size")
	check(absf(local.x) < size.x / 2.0 and local.z < -size.y / 2.0 + 1.0, "against the barn's back wall (%s)" % local.snappedf(0.01))
	check(store.global_basis.z.dot(barn.global_basis.z) > 0.99, "facing into the barn")
	# Crates appear as it fills
	var fill := store.get_node("Fill") as ShelfFill
	await wait_physics(2)
	check(fill.multimesh.visible_instance_count == 0, "empty shelves to start")
	store.inventory.add_item(VEG, 300)
	await wait_physics(1)
	var some := fill.multimesh.visible_instance_count
	check(some > 0 and some < fill.multimesh.instance_count, "some crates of produce (%d)" % some)
	store.inventory.add_item(VEG, 900)
	await wait_physics(1)
	check(fill.multimesh.visible_instance_count == fill.multimesh.instance_count, "full shelves")
	check(st.food() == 1200 and store.inventory.add_item(VEG, 1) == 0, "and no more")
	await _free(zone)


func test_farmers_fill_the_shelves_past_the_old_crate() -> void:
	var zone := await load_zone()
	var st := _farm(zone)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed")
	st.store.inventory.add_item(VEG, 300 - st.food())
	st.water = st.water_capacity
	st.pump_working = true
	p.global_position = st.global_position + Vector3(0, 0.1, 400)
	var s := st.spawn_newcomer()
	await wait_physics(70)
	st.request_set_role(p, s, Settler.Role.FARMER)
	s.global_position = (st.get_node("FarmSpots").get_child(0) as Node3D).global_position + Vector3.UP * 0.1
	var before := st.food()
	st.simulate(10.0)
	check(st.food() > before and st.food() > 240, "farmers keep filling it past 240 (%d → %d)" % [before, st.food()])
	# The settlement screen shows how full it is
	var hud := zone.get_node("HUD") as HUD
	hud.settlement_screen.open(st)
	await wait_physics(2)
	var text := ""
	for l in hud.settlement_screen.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	check(text.contains("%d / 1200" % st.food()), "the screen shows food / capacity")
	hud.settlement_screen.close()
	# Saved and loaded
	var saves := get_node("/root/SaveManager")
	saves.save_dir = "user://test_saves_farm_layout"
	var had := st.food()
	check(saves.save_game("farm_layout", zone) == OK, "saved")
	await _free(zone)
	var zone2 := await load_zone()
	check(saves.load_game("farm_layout", zone2) == OK, "loaded")
	await wait_physics(3)
	check(_farm(zone2).food() == had, "the shelves still hold %d" % had)
	check((_farm(zone2).store.get_node("Fill") as ShelfFill).multimesh.visible_instance_count > 0, "crates on the shelves after loading")
	await _free(zone2)


func test_a_save_from_the_old_layout() -> void:
	# Settlers saved standing round the old farm come to the new yard
	var zone := await load_zone()
	var st := _farm(zone)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	p.global_position = st.global_position + Vector3(0, 0.1, 400)
	var s := st.spawn_newcomer()
	await wait_physics(70)
	check(s.has_arrived(), "a settler living there")
	var data := SaveManager.build_save_data(zone)
	var marked := false
	# Make it an Increment 19 save: no layout, the settler where the old farmhouse stood
	for e: Dictionary in data["nodes"]:
		var d: Dictionary = e["data"]
		if d.has("layout"):
			marked = d["layout"] == Settlement.LAYOUT
			d.erase("layout")
		if d.has("settlement") and str(d["settlement"]) == "ash_creek":
			d["position"] = [332.0, 0.1, -82.0]
	check(marked, "saves note the layout")
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	await _free(zone)
	var zone2 := await load_zone()
	SaveManager.apply_save_data(old, zone2)
	await wait_physics(3)
	var back := zone2.get_tree().get_nodes_in_group("settlers").filter(func(n: Node) -> bool: return (n as Settler).settlement != null)
	check(back.size() == 1, "the settler loaded")
	if back.size() == 1:
		var h := (_farm(zone2).get_node("Hangout") as Node3D).global_position
		check((back[0] as Node3D).global_position.distance_to(h) < 3.0, "and is in the new yard, at the hangout")
	await _free(zone2)
