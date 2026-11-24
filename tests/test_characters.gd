extends "res://tests/test_case.gd"
## Increment 29: real characters. Settlers and raiders are Quaternius bodies
## (Universal Base Characters, CC0), playing the Universal Animation Library
## (CC0) through Godot's humanoid retarget, with their gear on their bones.
## 29.1: dressed in Modular Character Outfits (CC0), the Peasant's and the
## Ranger's pieces, armour drawn as their pieces.

const LIB := "res://assets/characters/quaternius/animations/AnimationLibrary_Godot_Standard.glb"
var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")


func _settler(role: Settler.Role, name := "Maya") -> Settler:
	var s := (load("res://scenes/npcs/settler.tscn") as PackedScene).instantiate() as Settler
	s.settler_name = name
	add_child(s)
	s.role = role
	s._update_visuals()
	s.set_physics_process(false)
	await wait_physics(1)
	return s


func test_the_packs_and_the_bodies() -> void:
	for f in ["LICENSE_animation_library.txt", "LICENSE_base_characters.txt", "outfits/LICENSE_Modular_Character_Outfits_Fantasy.txt"]:
		var text := FileAccess.get_file_as_string("res://assets/characters/quaternius/" + f)
		check(text.contains("CC0"), "%s: CC0 (free to use in a game that's sold)" % f)
	var lib := HumanBody._animations()
	var want := [&"Idle", &"Walk", &"Jog_Fwd", &"Sprint", &"Death01", &"Hit_Chest", &"Sword_Attack", &"Sword_Idle",
		&"Pistol_Idle", &"Pistol_Shoot", &"Fixing_Kneeling", &"Interact", &"Crouch_Idle", &"PickUp_Table"]
	var missing := want.filter(func(a: StringName) -> bool: return not lib.has_animation(a))
	check(missing.is_empty(), "the library has every animation used (missing %s)" % [missing])
	check(lib.get_animation(&"Walk").loop_mode != Animation.LOOP_NONE and lib.get_animation(&"Death01").loop_mode == Animation.LOOP_NONE,
		"walking loops; a death plays once and holds")
	check(String(lib.get_animation(&"Walk").track_get_path(1)).begins_with("%GeneralSkeleton:"), "its tracks are on the humanoid profile's bones")
	for female in [false, true]:
		var hb := HumanBody.new()
		hb.female = female
		add_child(hb)
		hb.build()
		await wait_physics(2)
		check(hb.skeleton != null and hb.skeleton.name == "GeneralSkeleton" and hb.skeleton.find_bone("Head") >= 0,
			"%s body: retargeted onto the humanoid profile" % ("female" if female else "male"))
		# 29.1: just the base body's head, the outfit for the rest
		var aabb := hb.body_mesh.mesh.get_aabb()
		check(aabb.position.y > 1.3, "%s: only the head drawn of the base body (from %.2f m up)" % ["female" if female else "male", aabb.position.y])
		var dressed := true
		for piece: StringName in [&"body", &"arms", &"legs", &"feet"]:
			var meshes := hb.piece_meshes(piece)
			dressed = dressed and not meshes.is_empty() and meshes.all(func(m: MeshInstance3D) -> bool:
				return m.get_parent() == hb.skeleton and m.skin != null and m.get_surface_override_material(0) != null)
		check(dressed, "dressed: a shirt with its sleeves, trousers and boots, skinned to the body's skeleton")
		check(hb.piece_meshes(&"hood").is_empty() and hb.piece_meshes(&"pauldrons").is_empty(), "no hood or pauldrons unless worn")
		var head := hb.skeleton.get_bone_global_pose(hb.skeleton.find_bone("Head")).origin.y
		check_between(head, 1.45, 1.7, "the head where the settler's head collision is (%.2f m)" % head)
		check(hb.anim.current_animation == &"Idle", "standing idle to start")
		hb.queue_free()


func test_looks_follow_the_seed() -> void:
	var a := HumanBody.new()
	var b := HumanBody.new()
	a.pick_looks(12345)
	b.pick_looks(12345)
	check(a.female == b.female and a.hair == b.hair and a.skin_tone == b.skin_tone and a.hair_colour == b.hair_colour
		and a.top == b.top and a.top_way == b.top_way and a.bottoms == b.bottoms and a.footwear == b.footwear and a.tint == b.tint,
		"the same seed, the same person, in the same clothes")
	var sexes := {}
	var hairs := {}
	var tones := {}
	var clothes := {}
	for i in 40:
		var h := HumanBody.new()
		h.pick_looks(i * 7919 + 3)
		sexes[h.female] = true
		hairs[h.hair] = true
		tones[h.skin_tone] = true
		clothes["%s%d %s%d %s" % [h.top, h.top_way, h.bottoms, h.bottoms_way, h.footwear]] = true
		h.free()
	check(sexes.size() == 2 and hairs.size() >= 4 and tones.size() >= 4 and clothes.size() >= 12,
		"forty settlers: men and women, %d hairstyles, %d skin tones, %d sets of clothes" % [hairs.size(), tones.size(), clothes.size()])
	a.free()
	b.free()
	# A settler's face is kept: from their look seed, saved with them
	var s := await _settler(Settler.Role.FARMER, "Hank")
	s.look_seed = 777
	s._apply_look()
	var was := [s.body.female, s.body.hair, s.body.shirt, s.body.top, s.body.top_way, s.body.bottoms]
	var data := s.save_state()
	var t := await _settler(Settler.Role.NONE, "Someone")
	t.load_state(data)
	check([t.body.female, t.body.hair, t.body.shirt, t.body.top, t.body.top_way, t.body.bottoms] == was, "loaded from a save: the same person (%s)" % [was])
	s.queue_free()
	t.queue_free()


func test_settlers_wear_their_jobs() -> void:
	var expect := {
		Settler.Role.FARMER: ["Hat"], Settler.Role.GUARD: ["Helmet", "Machete"],
		Settler.Role.BUILDER: ["HardHat", "ToolBelt", "Hammer"], Settler.Role.MINER: ["HardHat", "HeadLamp", "Pickaxe"],
		Settler.Role.COOK: ["ChefHat", "Apron"], Settler.Role.RANCHER: ["CowboyHat"], Settler.Role.ARMORER: ["Goggles", "ToolBelt", "Hammer"],
		Settler.Role.TAILOR: ["Apron"], Settler.Role.WOODCUTTER: ["Axe"],
	}
	var all := ["Hat", "Helmet", "HardHat", "HeadLamp", "Goggles", "ToolBelt", "ChefHat", "Apron", "CowboyHat",
		"Gun", "Machete", "Hammer", "Axe", "Pickaxe"]
	for role: Settler.Role in expect:
		var s := await _settler(role)
		var wrong := all.filter(func(n: String) -> bool: return s.part(n) == null or s.part(n).visible != (n in expect[role]))
		check(wrong.is_empty(), "%s: wears %s and nothing else (wrong: %s)" % [Settler.ROLE_NAMES[role], expect[role], wrong])
		check((s.body.outfit_of(&"pauldrons") != &"") == (role == Settler.Role.GUARD), "%s: pauldrons only for a guard" % Settler.ROLE_NAMES[role])
		s.queue_free()
	# Gear hangs on the bones and moves with them
	var f := await _settler(Settler.Role.FARMER)
	var hat := f.part("Hat")
	check(hat.get_parent() is BoneAttachment3D and (hat.get_parent() as BoneAttachment3D).bone_name == "Head", "the farmer's hat is on their head bone")
	f.body.play(&"Idle")
	await wait_physics(3)
	var standing := hat.global_position
	f.body.play(&"Fixing_Kneeling", 1.0, 0.0, true)
	f.body.anim.seek(1.5, true)
	await wait_physics(3)
	check(hat.global_position.y < standing.y - 0.4, "kneeling, the hat goes down with the head (%.2f → %.2f m)" % [standing.y, hat.global_position.y])
	var hat_head := hat.global_position.distance_to(f.body.slot("Head").global_position)
	check(hat_head < 0.3, "and stays on it (%.2f m from the head bone)" % hat_head)
	f.queue_free()
	# Armour (29.1): drawn as the outfits' pieces
	var g := await _settler(Settler.Role.GUARD)
	g.arm(RIFLE, 30)
	g.body.top = &"peasant"
	g.body.bottoms = &"peasant"
	g.body.rebuild()
	g._update_visuals()
	for id in ["plated_vest", "scrap_helmet", "leather_trousers"]:
		g.armour.put_on(load("res://resources/items/%s.tres" % id))
	await wait_physics(2)
	check(g.body.outfit_of(&"body") == &"ranger" and g.body.outfit_of(&"arms") == &"ranger" and g.body.outfit_of(&"pauldrons") == &"ranger",
		"a plated vest: the Ranger's coat, greyed, with pauldrons (over a peasant's shirt)")
	check(g.body.outfit_of(&"legs") == &"ranger" and not g.part("ArmourLegs").visible, "leather trousers: the Ranger's, no knee plates")
	check(g.part("ArmourHead").visible and g.body.outfit_of(&"hood") == &"", "a scrap helmet: a helmet, no hood")
	check(g.part("Gun").visible and not g.part("Machete").visible, "a rifle in hand, the machete put away")
	g.armour.take_off(ArmourSet.HEAD)
	g.armour.take_off(ArmourSet.BODY)
	g.armour.put_on(load("res://resources/items/padded_hood.tres"))
	g.armour.put_on(load("res://resources/items/plated_trousers.tres"))
	await wait_physics(2)
	var hair_off := g.body._hair.all(func(h: MeshInstance3D) -> bool: return not h.visible or h.get_meta("hair") == &"Hair_Beard")
	check(g.body.outfit_of(&"hood") == &"ranger" and not g.part("ArmourHead").visible and hair_off, "a padded hood: the Ranger's hood, the hair under it")
	check(g.body.outfit_of(&"body") == &"peasant" and g.body.outfit_of(&"pauldrons") == &"ranger", "the vest off: their own shirt, a guard's pauldrons")
	check(g.part("ArmourLegs").visible, "plated trousers: knee plates")
	g.queue_free()


func test_settlers_move_and_work() -> void:
	var s := await _settler(Settler.Role.MINER)
	s.state = Settler.State.WORK
	s.velocity = Vector3(1.4, 0, 0)
	s._animate(0.016)
	check(s.body.current() == &"Walk", "walking: Walk")
	s.velocity = Vector3(4.0, 0, 0)
	s._animate(0.016)
	check(s.body.current() == &"Jog_Fwd", "running: Jog_Fwd")
	s.velocity = Vector3.ZERO
	s._working = true
	s._animate(0.016)
	check(s.body.current() == &"Sword_Attack", "a Miner at the rock face swings the pick")
	s.role = Settler.Role.BUILDER
	s._animate(0.016)
	check(s.body.current() == &"Fixing_Kneeling", "a Builder kneels to the work")
	s.role = Settler.Role.COOK
	s._animate(0.016)
	check(s.body.current() == &"Interact", "a Cook at the stove")
	s._working = false
	s._animate(0.016)
	check(s.body.current() == &"Idle", "nothing to do: Idle")
	# A guard: aiming, shooting, struck, down
	var g := await _settler(Settler.Role.GUARD)
	g.arm(RIFLE, 30)
	g.state = Settler.State.FIGHT
	g._animate(0.016)
	check(g.body.current() == &"Pistol_Idle", "fighting with a gun: aiming")
	var target := Node3D.new()
	add_child(target)
	target.global_position = g.global_position + Vector3(0, 0, -10)
	g._shoot(target)
	g._animate(0.016)
	check(g.body.current() == &"Pistol_Shoot", "a shot: the recoil")
	await wait_physics(30)
	g._animate(0.5)
	check(g.body.current() == &"Pistol_Idle", "then back to aiming")
	g.state = Settler.State.DOWN
	g._animate(0.016)
	check(g.body.current() == &"Death01", "down: on the ground")
	# The gun points where they face, whatever the hand's doing
	g.state = Settler.State.IDLE
	g.rotation.y = 0.7
	g._update_gun()
	check(g.part("Gun").global_basis.z.dot(g.visual.global_basis.z) > 0.99, "the gun points where they face")
	target.queue_free()
	s.queue_free()
	g.queue_free()


func test_raiders_dressed_and_animated() -> void:
	for spec in [["raider", ["Bandana", "Goggles", "ChestStrap", "TirePad", "Machete"]],
			["raider_veteran", ["Bandana", "KneePadLeft", "Machete"]],
			["raider_marauder", ["Bandana", "KneePadLeft", "ScrapHelmet", "Machete"]]]:
		var r := (load("res://scenes/enemies/%s.tscn" % spec[0]) as PackedScene).instantiate() as Raider
		add_child(r)
		r.set_physics_process(false)
		await wait_physics(2)
		check(r.body != null and r.body.skeleton != null, "%s: a real body" % spec[0])
		var gear: Array = spec[1]
		var off := gear.filter(func(n: String) -> bool:
			var node := r.body.skeleton.find_child(n, true, false)
			return node == null or not (node.get_parent() is BoneAttachment3D))
		check(off.is_empty(), "%s: %s on its bones (missing %s)" % [spec[0], gear, off])
		check(not r.body.piece_meshes(&"body").is_empty() and (r.body.outfit_of(&"pauldrons") != &"") == (spec[0] != "raider"),
			"%s: dressed%s" % [spec[0], ", with pauldrons" if spec[0] != "raider" else ""])
		r.queue_free()
	var r2 := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	add_child(r2)
	r2.set_physics_process(false)
	await wait_physics(2)
	r2.velocity = Vector3(5.0, 0, 0)
	r2._animate(0.016)
	check(r2.body.current() == &"Sprint", "a raider charging: Sprint")
	r2.velocity = Vector3(1.5, 0, 0)
	r2._animate(0.016)
	check(r2.body.current() == &"Walk", "wandering: Walk")
	r2.velocity = Vector3.ZERO
	r2._play_windup()
	r2._animate(0.016)
	check(r2.body.current() == &"Sword_Attack", "a swing: Sword_Attack, over its windup and recovery")
	r2.health.apply_damage(DamageInfo.create(10000.0, DamageInfo.Type.BALLISTIC, null))
	await wait_physics(2)
	r2._act = 0.0
	r2._animate(0.016)
	check(r2.body.current() == &"Death01", "killed: falls")
	r2.queue_free()
	# Raiders vary
	var looks := {}
	for i in 6:
		var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
		add_child(r)
		r.set_physics_process(false)
		await wait_physics(1)
		looks["%s %s %s%d %s%d" % [r.body.female, r.body.hair, r.body.top, r.body.top_way, r.body.bottoms, r.body.bottoms_way]] = true
		r.queue_free()
	check(looks.size() >= 4, "six raiders, %d different looks" % looks.size())
