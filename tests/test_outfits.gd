extends "res://tests/test_case.gd"
## Increment 29.1: real clothes. People are dressed in Quaternius's Modular
## Character Outfits (Fantasy, Standard: the Peasant and the Ranger, CC0),
## piece by piece over the base body's head, tinted per person; armour is
## drawn as the outfits' pieces.

const DIR := "res://assets/characters/quaternius/outfits/"


func _person(cfg := {}) -> HumanBody:
	var hb := HumanBody.new()
	for k: String in cfg:
		hb.set(k, cfg[k])
	add_child(hb)
	hb.build()
	await wait_physics(1)
	return hb


func test_the_pack() -> void:
	var text := FileAccess.get_file_as_string(DIR + "LICENSE_Modular_Character_Outfits_Fantasy.txt")
	check(text.contains("CC0"), "the outfits' licence: CC0 (free in a game that's sold)")
	var missing := []
	for female in [false, true]:
		var hb := HumanBody.new()
		hb.female = female
		for outfit: StringName in [&"peasant", &"ranger"]:
			for piece: StringName in HumanBody.PIECES:
				if outfit == &"peasant" and piece in [&"hood", &"pauldrons"]:
					continue
				var path := hb._piece_file(piece, outfit)
				if not ResourceLoader.exists(path):
					missing.append(path.get_file())
		hb.free()
	check(missing.is_empty(), "every piece of both outfits, for a man and a woman (missing %s)" % [missing])
	var big := []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".png"):
			var img := Image.load_from_file(DIR + f)
			if img.get_width() > 1024:
				big.append(f)
	check(big.is_empty(), "textures scaled down to 1024 px at most (too big: %s)" % [big])


func test_pieces_drawn_right() -> void:
	var hb := await _person({"top": &"ranger", "top_way": 1, "bottoms": &"peasant", "footwear": &"ranger", "skin_tone": 4})
	check(hb.outfit_of(&"body") == &"ranger" and hb.outfit_of(&"arms") == &"ranger" and hb.outfit_of(&"legs") == &"peasant"
		and hb.outfit_of(&"feet") == &"ranger", "a ranger's shirt and sleeves, a peasant's trousers, ranger's boots")
	# Cloth in the outfit shader with its colourway; bare skin (the ranger's
	# forearms and hands) in the body's, with their skin tone
	var cloth_ok := true
	var skin_seen := false
	for piece: StringName in [&"body", &"arms", &"legs", &"feet"]:
		for mi: MeshInstance3D in hb.piece_meshes(piece):
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i) as ShaderMaterial
				if m == null:
					cloth_ok = false
				elif m.shader.resource_path.ends_with("human_body.gdshader"):
					skin_seen = skin_seen or piece == &"arms"
					cloth_ok = cloth_ok and m.get_shader_parameter(&"bare") == true
				else:
					cloth_ok = cloth_ok and m.shader.resource_path.ends_with("outfit.gdshader")
	check(cloth_ok, "cloth drawn by shaders/outfit, skin by the body's (all skin)")
	check(skin_seen, "the ranger's bare forearms and hands in the body's skin")
	var arms := hb.piece_meshes(&"arms")[0] as MeshInstance3D
	var tone: Color = HumanBody.SKIN_TONES[4][1]
	check((arms.get_instance_shader_parameter(&"skin_tint") as Color).is_equal_approx(tone), "the hands their own skin tone")
	var tex := (hb.piece_meshes(&"body")[0] as MeshInstance3D).get_surface_override_material(0).get_shader_parameter(&"albedo_texture") as Texture2D
	check(tex.resource_path.get_file() == "T_Ranger_3_BaseColor.png", "the shirt in its colourway (%s)" % tex.resource_path.get_file())
	# Animated with the body: the pieces are skinned to its skeleton
	var before := (hb.piece_meshes(&"legs")[0] as MeshInstance3D).get_aabb()
	hb.play(&"Crouch_Idle", 1.0, 0.0, true)
	await wait_physics(10)
	var foot := hb.skeleton.get_bone_global_pose(hb.skeleton.find_bone("LeftFoot"))
	check(hb.piece_meshes(&"legs")[0].skeleton == NodePath("..") and before.size.y > 0.5, "the trousers move with the legs")
	check(foot.origin.y < 0.3, "crouching, the body under them crouches too")
	hb.queue_free()


func test_wearing_swaps_pieces() -> void:
	var hb := await _person({"top": &"peasant", "bottoms": &"peasant", "hair": &"Hair_Long"})
	var shirt := hb.piece_meshes(&"body")[0] as MeshInstance3D
	hb.wear(&"legs", "")
	check(hb.piece_meshes(&"body")[0] == shirt, "nothing changed: the same shirt kept, not built again")
	hb.wear(&"body", "leather")
	check(hb.outfit_of(&"body") == &"ranger" and not is_instance_valid(shirt), "a leather coat: the Ranger's, the shirt gone")
	hb.wear(&"body", "wool")
	check(hb.outfit_of(&"body") == &"peasant" and hb.outfit_of(&"pauldrons") == &"", "Wool Clothes: the Peasant's")
	hb.wear(&"body", "plated")
	check(hb.outfit_of(&"pauldrons") == &"ranger", "plate: with pauldrons")
	hb.wear(&"head", "leather")
	check(hb.outfit_of(&"hood") == &"ranger" and not hb._hair[0].visible, "a leather cap: the hood, the long hair under it")
	hb.wear(&"head", "")
	hb.wear(&"body", "")
	check(hb.outfit_of(&"hood") == &"" and hb._hair[0].visible and hb.outfit_of(&"body") == &"peasant" and hb.outfit_of(&"pauldrons") == &"",
		"taken off: their own shirt and hair again")
	# Rebuilt (a new look): what's worn stays on
	hb.wear(&"legs", "padded")
	hb.female = true
	hb.rebuild()
	await wait_physics(1)
	check(hb.outfit_of(&"legs") == &"ranger" and hb.worn(&"legs") == "padded", "rebuilt as someone else: the padded trousers still on")
	hb.queue_free()


func test_who_wears_what() -> void:
	# Settlers: washed-out clothes, mostly the Peasant's; raiders: darker,
	# mostly the Ranger's; Marauders soot-black with rusty pauldrons
	var peasant := 0
	for i in 30:
		var h := HumanBody.new()
		h.pick_looks(i * 31 + 7)
		peasant += 1 if h.top == &"peasant" else 0
		check(h.tint.get_luminance() > 0.75, "a settler's clothes not darkened (%s)" % h.tint)
		h.free()
	check_between(peasant, 14, 28, "settlers mostly in the Peasant's shirt (%d of 30)" % peasant)
	var lum := {}
	for kind in ["raider", "raider_veteran", "raider_marauder"]:
		var r := (load("res://scenes/enemies/%s.tscn" % kind) as PackedScene).instantiate() as Raider
		add_child(r)
		r.set_physics_process(false)
		await wait_physics(1)
		lum[kind] = r.body.tint.get_luminance()
		if kind == "raider_marauder":
			var p := r.body.piece_meshes(&"pauldrons")[0] as MeshInstance3D
			var t: Color = p.get_instance_shader_parameter(&"tint")
			check(t.r > t.g * 1.5, "a Marauder's pauldrons rust-red")
		r.queue_free()
	check(lum["raider"] < 0.8 and lum["raider_marauder"] < lum["raider_veteran"] and lum["raider_veteran"] < lum["raider"] + 0.05,
		"raiders darker than settlers, Marauders darkest (%s)" % [lum])
