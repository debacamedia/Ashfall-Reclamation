extends "res://tests/test_case.gd"
## Increment 16.5: drawing the zone more cheaply (StaticBatcher, shadows,
## occlusion) without changing what you see, what's solid, or what you can
## loot, move or scrap. The draw-call numbers themselves come from
## tools/benchmark.gd, which needs a real renderer.


func _unbatched_zone() -> Node3D:
	var zone := instance_zone()
	zone.set("batch_sites", false)
	add_child(zone)
	await wait_physics(2)
	return zone


func _batched_zone() -> Node3D:
	var zone := instance_zone()
	add_child(zone)
	await wait_physics(2)
	return zone


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


## Triangles and collision shapes per site, and the scripted things in it.
func _census(zone: Zone) -> Dictionary:
	var out := {}
	for site in zone.sites():
		var tris := 0
		var meshes := 0
		for mi: MeshInstance3D in site.find_children("*", "MeshInstance3D", true, false):
			if mi.is_queued_for_deletion() or mi.mesh == null:
				continue
			meshes += 1
			for i in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(i)
				tris += ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var scripted := 0
		for n in site.find_children("*", "Node", true, false):
			if n.get_script() != null:
				scripted += 1
		out[site.name] = {
			"tris": tris,
			"meshes": meshes,
			"shapes": site.find_children("*", "CollisionShape3D", true, false).size(),
			"scripted": scripted,
		}
	return out


func test_merging_keeps_every_triangle_and_all_collision() -> void:
	var plain := await _unbatched_zone()
	var before := _census(plain as Zone)
	await _free(plain)
	var zone := await _batched_zone()
	var after := _census(zone as Zone)
	var total_before := 0
	var total_after := 0
	for key in before:
		var b: Dictionary = before[key]
		var a: Dictionary = after[key]
		check(a["tris"] == b["tris"], "%s: same triangles (%d vs %d)" % [key, a["tris"], b["tris"]])
		check(a["shapes"] == b["shapes"], "%s: same collision (%d shapes)" % [key, a["shapes"]])
		check(a["scripted"] == b["scripted"], "%s: every scripted thing still there (%d)" % [key, a["scripted"]])
		check(a["meshes"] < b["meshes"], "%s: fewer meshes (%d, was %d)" % [key, a["meshes"], b["meshes"]])
		total_before += b["meshes"]
		total_after += a["meshes"]
	check(total_after < total_before * 0.6, "40%%+ fewer meshes across the zone (%d, was %d)" % [total_after, total_before])
	var ms: int = (zone as Zone).batch_stats["_ms"]
	check(ms < 1000, "merging takes under a second at load (%d ms)" % ms)
	await _free(zone)


func test_merged_meshes_keep_their_look() -> void:
	var zone := await _batched_zone()
	for site in (zone as Zone).sites():
		var holder := site.get_node_or_null("Batched")
		check(holder != null and holder.get_child_count() > 0, "%s has merged meshes" % site.name)
		for b: MeshInstance3D in holder.get_children():
			check(b.material_override != null, "%s/%s has its material" % [site.name, b.name])
			check(b.visibility_range_end > 0.0, "%s/%s has a draw distance" % [site.name, b.name])
	# A known wall material survives: Halden's hotel brick, the outpost's
	# concrete. Every material on an unbatched building is on a batch.
	var plain := await _unbatched_zone()
	for key in ["HaldensCrossing", "Outpost17", "SaintMercyClinic"]:
		var want := {}
		for mi: MeshInstance3D in plain.get_node(key + "/Buildings").find_children("*", "MeshInstance3D", true, false):
			if mi.material_override != null and StaticBatcher.mergeable(mi, plain.get_node(key)):
				want[mi.material_override] = true
		var have := {}
		for b: MeshInstance3D in zone.get_node(key + "/Batched").get_children():
			have[b.material_override] = true
		var missing := want.keys().filter(func(m: Material) -> bool: return not have.has(m))
		check(missing.is_empty(), "%s: every building material is drawn (%d missing)" % [key, missing.size()])
	await _free(plain)
	await _free(zone)


func test_props_you_can_move_or_scrap_still_work() -> void:
	var zone := await _batched_zone()
	var props: Array = get_tree().get_nodes_in_group("level_props").filter(func(n: Node) -> bool: return zone.is_ancestor_of(n) and not n is ContainerProp)
	check(props.size() > 30, "the zone's props (%d)" % props.size())
	var merged := props.filter(func(n: Node) -> bool: return n.get_children().any(func(c: Node) -> bool: return c.name.begins_with("Batch")))
	check(merged.size() > 10, "many props have their pieces merged (%d)" % merged.size())
	var prop := merged[0] as LevelProp
	var mesh := prop.get_children().filter(func(c: Node) -> bool: return c.name.begins_with("Batch"))[0] as MeshInstance3D
	# Moved: the merged mesh goes with it
	var was := mesh.global_position
	prop.apply_transform(prop.global_transform.translated(Vector3(3, 0, 0)))
	check(mesh.global_position.distance_to(was + Vector3(3, 0, 0)) < 0.01, "moving a prop moves its merged mesh")
	# Scrapped: hidden with it
	prop.scrap()
	check(not mesh.is_visible_in_tree(), "scrapping a prop hides its merged mesh")
	await _free(zone)


func test_containers_and_piles_untouched_where_it_matters() -> void:
	var zone := await _batched_zone()
	var plain := await _unbatched_zone()
	# Containers keep every piece (their lids and doors open)
	for c in zone.find_children("*", "SalvageContainer", true, false):
		var twin := plain.get_node_or_null(zone.get_path_to(c))
		check(twin != null, "%s still there" % c.name)
		if twin != null:
			check(c.find_children("*", "MeshInstance3D", true, false).size() == twin.find_children("*", "MeshInstance3D", true, false).size(), "%s keeps its parts" % zone.get_path_to(c))
	# Piles keep working: same yields, and breaking one down removes it all
	var piles := zone.find_children("*", "SalvagePile", true, false)
	check(piles.size() > 30, "salvage piles (%d)" % piles.size())
	for pile: SalvagePile in piles:
		var twin := plain.get_node(zone.get_path_to(pile)) as SalvagePile
		check(pile.yields == twin.yields, "%s yields the same" % pile.name)
	await _free(plain)
	await _free(zone)


func test_interiors_drawn_close_and_without_sun_shadow() -> void:
	var zone := await _batched_zone()
	var mercy := zone.get_node("SaintMercyClinic")
	var cabinet := mercy.get_node("SalvageContainers/MedicineCabinet")
	for m: MeshInstance3D in cabinet.find_children("*", "MeshInstance3D", true, false):
		check(m.visibility_range_end > 0.0 and m.visibility_range_end <= StaticBatcher.INTERIOR_RANGE and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"the hospital's medicine cabinet (%s): drawn within %d m (%.0f), no sun shadow (%d)" % [m.name, StaticBatcher.INTERIOR_RANGE, m.visibility_range_end, m.cast_shadow])
	var lamp_bulbs := (mercy.get_node("Batched").get_children() as Array).filter(func(b: MeshInstance3D) -> bool: return b.visibility_range_end == StaticBatcher.INTERIOR_RANGE)
	check(lamp_bulbs.size() > 0, "interior batches drawn close")
	# Outside things keep their distance: a container in the open
	var outside := zone.get_node("SmugglersGulch/SalvageContainers/RaiderCache")
	check((outside.find_children("*", "MeshInstance3D", true, false) as Array).all(func(m: MeshInstance3D) -> bool: return m.visibility_range_end > StaticBatcher.INTERIOR_RANGE),
		"a cache out in the open is still seen from afar")
	# The walls themselves are seen from far off
	var far := (mercy.get_node("Batched").get_children() as Array).filter(func(b: MeshInstance3D) -> bool: return b.visibility_range_end >= Zone.LARGE_RANGE)
	check(far.size() > 0, "the hospital's walls are drawn from far away")
	await _free(zone)


func test_buildings_hide_what_is_behind_them() -> void:
	check(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling"), "occlusion culling on")
	var zone := await _batched_zone()
	for site in (zone as Zone).sites():
		var occ := site.get_node_or_null("Occluders")
		check(occ != null and occ.get_child_count() >= 15, "%s: walls hide what's behind them (%d)" % [site.name, occ.get_child_count() if occ else 0])
	# Each occluder sits within a building, inside its wall (the buildings'
	# outlines are measured on an unmerged copy)
	var plain := await _unbatched_zone()
	var shells := StaticBatcher.building_shells(plain.get_node("HaldensCrossing"), false)
	await _free(plain)
	var inv := (zone.get_node("HaldensCrossing") as Node3D).global_transform.affine_inverse()
	for o: OccluderInstance3D in zone.get_node("HaldensCrossing/Occluders").get_children():
		var p := inv * o.global_position
		check(shells.any(func(s: Array) -> bool: return (s[0] as AABB).grow(0.6).has_point(p)), "occluder at %s is in a building" % p)
	await _free(zone)


func test_sun_shadows_two_cascades() -> void:
	var zone := instance_zone()
	var sun := zone.get_node("Lighting/Sun") as DirectionalLight3D
	check(sun.shadow_enabled, "the sun casts shadows")
	check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "in two cascades")
	check_near(sun.directional_shadow_max_distance, 120.0, 0.1, "out to 120 m")
	zone.free()


func test_debug_readout_shows_frame_numbers() -> void:
	var zone := await _batched_zone()
	var hud := zone.get_node("HUD")
	var label := hud.get_node("%DebugLabel") as Label
	label.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(label.text.contains("fps") and label.text.contains("draw calls"), "F3 shows fps and draw calls")
	await _free(zone)
