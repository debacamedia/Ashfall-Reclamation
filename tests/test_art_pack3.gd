extends "res://tests/test_case.gd"
## Resource Pack 3.0: installed as shipped, sound sets and materials built,
## signs/graffiti/decals placed on real surfaces in both levels, no new
## collision or save data, surface-aware footsteps and impacts, crafting and
## salvage sounds, weathered container paint, seamless derived loops and sky.

const PACK := "res://assets/ashfall_pack_v3/"
const HALDENS := "res://levels/haldens_crossing/haldens_crossing.tscn"
const OUTPOST := "res://levels/outpost_17/outpost_17.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0


func _level(path: String) -> Node3D:
	var lvl := (load(path) as PackedScene).instantiate() as Node3D
	for sp in lvl.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = false
	(lvl.get_node("Player") as PlayerController).controlled_locally = false
	add_child(lvl)
	await wait_physics(6)
	return lvl


func _audio(p: PlayerController) -> PlayerAudio:
	for c in p.get_children():
		if c is PlayerAudio:
			return c
	return null


func _free(lvl: Node3D) -> void:
	remove_child(lvl)
	lvl.free()
	await wait_physics(2)


# ---------------------------------------------------------------- files

func test_pack_installed_as_shipped() -> void:
	var f := FileAccess.open(PACK + "manifest.json", FileAccess.READ)
	var manifest: Array = JSON.parse_string(f.get_as_text())
	check(manifest.size() == 253, "253 files in the manifest")
	var bad := 0
	for e: Dictionary in manifest:
		var path := "res://" + str(e["path"])
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or (not path.ends_with("manifest.json") and file.get_length() != int(e["size_bytes"])):
			bad += 1
	check(bad == 0, "every file present at its shipped size (%d differ)" % bad)
	check(not DirAccess.dir_exists_absolute(PACK + "scenes"), "no models in this pack (as its README says)")


func test_sound_sets_and_materials() -> void:
	for f in DirAccess.get_files_at(PACK + "sets"):
		if not f.ends_with(".tres"):
			continue
		var r := load(PACK + "sets/" + f) as AudioStreamRandomizer
		check(r != null and r.streams_count >= 3, "%s: a set of 3+" % f)
		if r != null:
			for i in r.streams_count:
				check(r.get_stream(i) != null, "%s: stream %d loads" % [f, i])
	for m in ["brick_weathered", "asphalt_cracked", "canvas_tent", "roofing_tarpaper", "container_paint_red", "container_paint_blue", "container_paint_olive"]:
		var mat := load(PACK + "materials/%s.tres" % m) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null and mat.normal_texture != null and mat.roughness_texture != null, "%s: albedo, normal, roughness" % m)
		check(mat != null and mat.uv1_world_triplanar, "%s: world-triplanar (no UVs needed)" % m)
	check((load(PACK + "materials/brick_weathered.tres") as StandardMaterial3D).albedo_color.r < 0.6, "brick tinted down to the old brick's brightness")


# ---------------------------------------------------------------- placement

func _check_dressing(lvl: Node3D, signs: int, decals: int) -> void:
	var dress := lvl.get_node_or_null("Pack3Dressing")
	check(dress != null, "%s: Pack 3 dressing instanced" % lvl.name)
	if dress == null:
		return
	check(dress.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s: dressing adds no collision" % lvl.name)
	var space := lvl.get_world_3d().direct_space_state
	var wall_items: Array[Node] = []
	for g in ["Signs", "Graffiti"]:
		var n := dress.get_node_or_null(g)
		if n != null:
			wall_items.append_array(n.get_children())
	check(wall_items.size() == signs, "%s: %d signs and graffiti (%d)" % [lvl.name, signs, wall_items.size()])
	for s in wall_items:
		var mi := s as MeshInstance3D
		var normal := mi.global_basis.z.normalized()
		var size := (mi.mesh as QuadMesh).size
		# Every corner sits a few millimetres in front of solid wall
		for k: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
			var p := mi.global_position + mi.global_basis.x * k.x * size.x + mi.global_basis.y * k.y * size.y + normal * 0.2
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - normal * 0.4, PhysicsLayers.WORLD_SOLID))
			check(not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) < 0.22, "%s: corner %s on the wall" % [mi.name, k])
	var ds := dress.get_node_or_null("Decals")
	var n_decals := ds.get_child_count() if ds != null else 0
	check(n_decals == decals, "%s: %d decals (%d)" % [lvl.name, decals, n_decals])
	if ds != null:
		for d in ds.get_children():
			var mi := d as MeshInstance3D
			var normal := mi.global_basis.z.normalized()
			var p := mi.global_position + normal * 0.2
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - normal * 0.5, PhysicsLayers.WORLD_SOLID))
			check(not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) < 0.26, "%s lies on a surface" % mi.name)


func test_haldens_crossing_dressed() -> void:
	var lvl := await _level(HALDENS)
	await _check_dressing(lvl, 13, 15)
	# Signs by name over the right buildings
	var signs := lvl.get_node("Pack3Dressing/Signs")
	for pair in [["SignGeneralStore", "GeneralStore"], ["SignHotel", "Hotel"], ["SignClinic", "Clinic"], ["SignDiner", "Diner"],
			["SignBank", "Bank"], ["SignFeedSupply", "FeedStore"], ["SignGas", "GasKiosk"]]:
		var s := signs.get_node_or_null(pair[0]) as Node3D
		var b := lvl.get_node("Buildings/" + pair[1]) as Node3D
		check(s != null and Vector2(s.global_position.x - b.global_position.x, s.global_position.z - b.global_position.z).length() < 8.0, "%s on the %s" % pair)
		check(s != null and s.global_position.y > 2.3, "%s above the door" % pair[0])
	# Materials: brick buildings, streets, tents and roofs use the pack's
	var store := lvl.get_node("Buildings/GeneralStore")
	var uses := {}
	for mi in lvl.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m != null and m.resource_path.begins_with(PACK):
			uses[m.resource_path.get_file()] = true
	for f in ["brick_weathered.tres", "asphalt_cracked.tres", "canvas_tent.tres", "roofing_tarpaper.tres"]:
		check(uses.has(f), "Halden's uses %s" % f)
	check(store != null, "")
	# Ambient sound loops
	for name in ["TownRuins", "DistantGunfire", "Insects"]:
		var a := lvl.get_node_or_null("Pack3Dressing/Sounds/" + name) as AudioStreamPlayer3D
		check(a != null and a.autoplay and (a.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s: plays and loops" % name)
	# Nothing new in a save
	var data: Dictionary = get_node("/root/SaveManager").build_save_data(lvl)
	check((data["nodes"] as Array).all(func(e: Dictionary) -> bool: return not str(e["path"]).begins_with("Pack3")), "dressing isn't saved")
	await _free(lvl)


func test_outpost_dressed_and_old_saves_load() -> void:
	var lvl := await _level(OUTPOST)
	await _check_dressing(lvl, 0, 9)
	var saves := get_node("/root/SaveManager")
	var f := FileAccess.open("res://tests/fixtures/outpost_save_before_pack2.json", FileAccess.READ)
	var old: Dictionary = JSON.parse_string(f.get_as_text())
	check(saves.validate(old) == "", "a save from before Packs 2 and 3 still validates")
	saves.apply_save_data(old, lvl)
	await wait_physics(2)
	check((lvl.get_node("Player") as Node3D).global_position.distance_to(Vector3(-24.0, 0.05, -15.0)) < 0.3, "and loads")
	check(lvl.get_node_or_null("Pack3Dressing/Decals") != null, "dressing untouched by loading")
	await _free(lvl)


# ---------------------------------------------------------------- sounds

func test_surfaces() -> void:
	var floor_body := make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	check(SurfaceSounds.of(floor_body) == &"gravel", "the ground: gravel")
	var building := make_static_box(Vector3(2, 2, 2), Vector3(5, 1, 0))
	check(SurfaceSounds.of(building) == &"concrete", "buildings: concrete")
	var cases := {
		"res://scenes/structures/metal_wall.tscn": &"metal",
		"res://scenes/structures/wooden_platform.tscn": &"wood",
		"res://scenes/structures/wooden_stairs.tscn": &"wood",
		"res://scenes/structures/sandbag_barricade.tscn": &"gravel",
		"res://scenes/structures/chain_link_fence.tscn": &"metal",
		"res://scenes/vehicles/military_truck.tscn": &"metal",
		"res://scenes/world/props/jersey_barrier.tscn": &"concrete",
		"res://scenes/world/props/wood_crate.tscn": &"wood",
		"res://scenes/world/containers/footlocker.tscn": &"wood",
		"res://scenes/world/containers/weapons_locker.tscn": &"metal",
		"res://scenes/world/props/shipping_container.tscn": &"metal",
	}
	var x := -8.0
	for path in cases:
		var n := (load(path) as PackedScene).instantiate() as Node3D
		n.position = Vector3(x, 0, -8)
		x += 4.0
		add_child(n)
		var body: Node = n if n is CollisionObject3D else n.find_children("*", "StaticBody3D", true, false)[0]
		check(SurfaceSounds.of(body) == cases[path], "%s: %s (got %s)" % [path.get_file(), cases[path], SurfaceSounds.of(body)])
	var tagged := make_static_box(Vector3(1, 1, 1), Vector3(0, 0.5, 8))
	tagged.set_meta("surface", "metal")
	check(SurfaceSounds.of(tagged) == &"metal", "a node can tag itself")


func test_footsteps_follow_the_floor() -> void:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var deck := (load("res://scenes/structures/wooden_platform.tscn") as PackedScene).instantiate() as Node3D
	deck.position = Vector3(6, 0, 0)
	add_child(deck)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	var audio := _audio(p)
	var f := InputFrame.new()
	f.move = Vector2(0, -1)
	for i in 90:
		await get_tree().physics_frame
		p.simulate(f, DT)
	check(audio.footstep_count > 0 and audio.last_surface == &"gravel", "walking on the ground: gravel (%s)" % audio.last_surface)
	check((p.get_node("%Footsteps") as AudioStreamPlayer3D).stream == SurfaceSounds.footstep(&"gravel"), "gravel footstep set")
	p.global_position = Vector3(6, 2.7, 0)
	var n0 := audio.footstep_count
	for i in 90:
		await get_tree().physics_frame
		p.simulate(f, DT)
		if p.global_position.z < -0.9:
			p.global_position.z = 0.9
	check(audio.footstep_count > n0 and audio.last_surface == &"wood", "on a wooden deck: wood (%s)" % audio.last_surface)


func test_bullets_sound_like_what_they_hit() -> void:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var wall := (load("res://scenes/structures/metal_wall.tscn") as PackedScene).instantiate() as Node3D
	wall.position = Vector3(0, 0, -6)
	add_child(wall)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(30)
	p.head.rotation.x = 0.0
	p.rotation.y = 0.0
	var f := InputFrame.new()
	f.fire = true
	for i in 3:
		await get_tree().physics_frame
		p.simulate(f, DT)
	f.fire = false
	await wait_physics(2)
	var impacts := get_tree().get_nodes_in_group("bullet_impacts")
	check(not impacts.is_empty(), "the shot left an impact")
	if not impacts.is_empty():
		var imp := impacts[impacts.size() - 1] as BulletImpact
		check(imp.surface == &"metal", "it knows it hit metal (%s)" % imp.surface)
		check((imp.get_node("%HardSound") as AudioStreamPlayer3D).stream == SurfaceSounds.impact(&"metal"), "metal impact sound")
	for i in impacts:
		i.queue_free()


func test_crafting_and_salvage_sounds() -> void:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	var audio := _audio(p)
	var r: RecipeDefinition = load("res://resources/recipes/kit_wooden_barricade.tres")
	check(PlayerAudio.tools_for(r).has(PlayerAudio.CRAFT_SAW), "woodwork: the saw")
	check(PlayerAudio.tools_for(load("res://resources/recipes/kit_ladder.tres")).has(PlayerAudio.CRAFT_HAMMER), "and the hammer")
	p.inventory.add_item(ItemDatabase.get_item(&"wood_plank"), 3)
	p.inventory.add_item(ItemDatabase.get_item(&"scrap_metal"), 1)
	check(p.request_craft(r), "crafting")
	var f := InputFrame.new()
	for i in int(r.craft_time / DT) + 10:
		await get_tree().physics_frame
		p.simulate(f, DT)
	check(audio.craft_sound_count >= 4, "tools heard while crafting (%d)" % audio.craft_sound_count)
	var n := audio.craft_sound_count
	await wait_physics(40)
	check(audio.craft_sound_count == n, "and they stop when it's done")
	var pallet := (load("res://scenes/world/salvage/wood_pallet.tscn") as PackedScene).instantiate() as SalvagePile
	var heap := (load("res://scenes/world/salvage/scrap_heap.tscn") as PackedScene).instantiate() as SalvagePile
	check(pallet.get_break_sound() == SalvagePile.SOUND_WOOD, "pallets break with wood sounds")
	check(heap.get_break_sound() == SalvagePile.SOUND_METAL, "scrap heaps with metal")
	pallet.free()
	heap.free()


func test_containers_keep_their_paint() -> void:
	var lvl := await _level(OUTPOST)
	for c in ["Props/ContainerA", "Props/ContainerB", "Props/ContainerC", "Props/ContainerD"]:
		var n := lvl.get_node(c)
		var mat := (n.get_node("Body") as MeshInstance3D).material_override as StandardMaterial3D
		check(mat.albedo_texture != null and mat.resource_name.begins_with("AF3_container_paint"), "%s: weathered paint" % c)
		var paint: Color = n.get("paint")
		# Texture average × tint = the paint picked in the level
		var best := ""
		for p: Array in n.get("PAINTS"):
			if mat.albedo_texture == (load(p[0]) as StandardMaterial3D).albedo_texture:
				var avg: Color = p[1]
				check(absf(avg.r * mat.albedo_color.r - paint.r) < 0.01 and absf(avg.b * mat.albedo_color.b - paint.b) < 0.01, "%s keeps its colour" % c)
				best = p[0]
		check(best != "", "%s: one of the pack paints" % c)
	await _free(lvl)


func test_loops_and_sky_are_seamless() -> void:
	for name in ["amb_fire_barrel_loop", "amb_insects_loop"]:
		var w := load(PACK + "derived/%s.wav" % name) as AudioStreamWAV
		check(w != null and w.loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s loops" % name)
		# The source WAV (imported audio is compressed): 16-bit mono PCM after
		# a 44-byte header. The last sample must lead smoothly into the first.
		var raw := FileAccess.get_file_as_bytes(PACK + "derived/%s.wav" % name)
		var first := raw.decode_s16(44)
		var last := raw.decode_s16(raw.size() - 2)
		var step := raw.decode_s16(46) - first
		check(absi(first - last - step) < 2500, "%s: no click at the join (%d → %d)" % [name, last, first])
	var shipped := FileAccess.get_file_as_bytes(PACK + "audio/amb_fire_barrel.wav")
	check(absi(shipped.decode_s16(44) - shipped.decode_s16(shipped.size() - 2)) > 2000, "(the shipped fire loop does click: why the copy exists)")
	var img := Image.load_from_file(ProjectSettings.globalize_path(PACK + "derived/sky_dusty_afternoon_nosun.png"))
	var worst := 0.0
	for y in range(0, img.get_height(), 64):
		for x in range(2900, 3700, 2):
			worst = maxf(worst, absf(img.get_pixel(x, y).get_luminance() - img.get_pixel(x + 1, y).get_luminance()))
	check(worst < 0.04, "the fixed sky has no seam (%.3f)" % worst)
