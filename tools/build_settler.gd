extends SceneTree
## Builds the settler (Increment 19): scenes/npcs/settler.tscn. A person in
## the raiders' proportions but dressed as a civilian: work trousers, a shirt
## and skin tinted per settler (Settler._apply_look), a straw hat for
## farmers, a vest and helmet for guards, a gun or machete in hand.
##
##   godot --headless --path . -s res://tools/build_settler.gd

const OUT := "res://scenes/npcs/settler.tscn"

var s: Settler
var _mats := {}


func _initialize() -> void:
	_run.call_deferred()


func _mat(key: String, color: Color, rough := 0.9) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


func _run() -> void:
	s = Settler.new()
	s.name = "Settler"
	s.collision_layer = PhysicsLayers.NPCS
	s.collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES | PhysicsLayers.PLAYER | PhysicsLayers.NPCS
	s.floor_max_angle = deg_to_rad(46.0)
	var body := CollisionShape3D.new()
	body.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2  # inside the navmesh's agent radius (0.25), so they fit its doorways and corners (20.1)
	cap.height = 1.45
	body.shape = cap
	body.position.y = 0.725
	_add(s, body)
	var head_shape := CollisionShape3D.new()
	head_shape.name = "HeadShape"
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	head_shape.shape = sph
	head_shape.position.y = 1.6
	head_shape.set_meta("damage_multiplier", 2.0)
	_add(s, head_shape)

	var trousers := _mat("trousers", Color(0.28, 0.27, 0.24))
	var boots := _mat("boots", Color(0.22, 0.16, 0.11))
	var shirt := _mat("shirt", Color(0.5, 0.4, 0.3))
	var skin := _mat("skin", Color(0.8, 0.62, 0.5), 0.8)
	var hair := _mat("hair", Color(0.18, 0.13, 0.09))
	var straw := _mat("straw", Color(0.78, 0.66, 0.38))
	var olive := _mat("olive", Color(0.3, 0.33, 0.2))
	var steel := _mat("steel", Color(0.2, 0.2, 0.21), 0.5)
	var blade := _mat("blade", Color(0.72, 0.72, 0.72), 0.35)
	var wood := _mat("wood", Color(0.38, 0.25, 0.14))

	var v := Node3D.new()
	v.name = "Visual"
	_add(s, v)
	v.unique_name_in_owner = true
	for x in [-0.12, 0.12]:
		var tag := "L" if x < 0 else "R"
		_box(v, "Leg" + tag, Vector3(0.17, 0.8, 0.2), Vector3(x, 0.42, 0), trousers)
		_box(v, "Boot" + tag, Vector3(0.19, 0.13, 0.29), Vector3(x, 0.065, -0.04), boots)
	_box(v, "Belt", Vector3(0.46, 0.08, 0.27), Vector3(0, 0.84, 0), boots)
	var torso := _box(v, "Torso", Vector3(0.46, 0.55, 0.27), Vector3(0, 1.13, 0), shirt)
	torso.set_meta("tint", "shirt")
	var neck := _box(v, "Neck", Vector3(0.11, 0.09, 0.11), Vector3(0, 1.44, 0), skin)
	neck.set_meta("tint", "skin")
	var head := MeshInstance3D.new()
	head.name = "Head"
	var hm := SphereMesh.new()
	hm.radius = 0.14
	hm.height = 0.3
	head.mesh = hm
	head.material_override = skin
	head.position.y = 1.6
	head.set_meta("tint", "skin")
	_add(v, head)
	_box(v, "Hair", Vector3(0.27, 0.08, 0.26), Vector3(0, 1.72, 0.02), hair)
	# Farmer's straw hat
	var hat := Node3D.new()
	hat.name = "Hat"
	hat.position.y = 1.73
	_add(v, hat)
	_cyl(hat, "Brim", 0.3, 0.3, 0.025, Vector3.ZERO, straw)
	_cyl(hat, "Crown", 0.14, 0.16, 0.13, Vector3(0, 0.07, 0), straw)
	# Guard's vest and helmet
	var vest := Node3D.new()
	vest.name = "Vest"
	_add(v, vest)
	_box(vest, "Front", Vector3(0.48, 0.42, 0.06), Vector3(0, 1.15, -0.15), olive)
	_box(vest, "Back", Vector3(0.48, 0.42, 0.06), Vector3(0, 1.15, 0.15), olive)
	_box(vest, "Pouch", Vector3(0.16, 0.1, 0.05), Vector3(-0.12, 1.0, -0.19), olive)
	# Builder's hard hat and tool belt
	var hard := Node3D.new()
	hard.name = "HardHat"
	hard.position.y = 1.69
	_add(v, hard)
	var hh := MeshInstance3D.new()
	hh.name = "Shell"
	var hm2 := SphereMesh.new()
	hm2.radius = 0.165
	hm2.height = 0.19
	hm2.is_hemisphere = true
	hh.mesh = hm2
	hh.material_override = _mat("hard_hat", Color(0.92, 0.72, 0.12), 0.5)
	_add(hard, hh)
	_box(hard, "Brim", Vector3(0.36, 0.02, 0.4), Vector3(0, 0.005, -0.02), _mat("hard_hat", Color(0.92, 0.72, 0.12), 0.5))
	# A Miner's lamp on the front of the hard hat (23)
	var lamp := Node3D.new()
	lamp.name = "HeadLamp"
	lamp.position.y = 1.69
	_add(v, lamp)
	_box(lamp, "Lamp", Vector3(0.08, 0.06, 0.04), Vector3(0, 0.06, -0.16), _mat("lamp_glass", Color(1.0, 0.95, 0.7), 0.2))
	var belt := Node3D.new()
	belt.name = "ToolBelt"
	_add(v, belt)
	_box(belt, "Belt", Vector3(0.5, 0.1, 0.3), Vector3(0, 0.86, 0), _mat("leather", Color(0.42, 0.28, 0.16)))
	_box(belt, "Pouch", Vector3(0.14, 0.16, 0.08), Vector3(0.17, 0.78, -0.16), _mat("leather", Color(0.42, 0.28, 0.16)))
	# Cook's apron and chef's hat (21.5)
	var whites := _mat("whites", Color(0.93, 0.92, 0.88))
	var apron := Node3D.new()
	apron.name = "Apron"
	_add(v, apron)
	_box(apron, "Bib", Vector3(0.36, 0.3, 0.03), Vector3(0, 1.12, -0.15), whites)
	_box(apron, "Skirt", Vector3(0.42, 0.42, 0.03), Vector3(0, 0.66, -0.15), whites)
	var chef := Node3D.new()
	chef.name = "ChefHat"
	chef.position.y = 1.7
	_add(v, chef)
	_cyl(chef, "Band", 0.15, 0.15, 0.08, Vector3(0, 0.02, 0), whites)
	_cyl(chef, "Puff", 0.17, 0.14, 0.14, Vector3(0, 0.12, 0), whites)
	# Rancher's wide-brimmed hat (21.5)
	var leather := _mat("hat_leather", Color(0.45, 0.3, 0.17))
	var cowboy := Node3D.new()
	cowboy.name = "CowboyHat"
	cowboy.position.y = 1.72
	_add(v, cowboy)
	_cyl(cowboy, "Brim", 0.32, 0.32, 0.02, Vector3.ZERO, leather)
	_cyl(cowboy, "Crown", 0.12, 0.15, 0.15, Vector3(0, 0.08, 0), leather)
	_cyl(cowboy, "Band", 0.152, 0.152, 0.03, Vector3(0, 0.025, 0), _mat("hat_band", Color(0.15, 0.1, 0.08)))
	# Armour a guard's given (22): coloured by the settler for leather or plate
	var hide := _mat("armour", Color(0.42, 0.27, 0.15))
	var ah := Node3D.new()
	ah.name = "ArmourHead"
	ah.position.y = 1.68
	_add(v, ah)
	var ahm := MeshInstance3D.new()
	ahm.name = "Shell"
	var ahs := SphereMesh.new()
	ahs.radius = 0.172
	ahs.height = 0.2
	ahs.is_hemisphere = true
	ahm.mesh = ahs
	ahm.material_override = hide
	_add(ah, ahm)
	var ab := Node3D.new()
	ab.name = "ArmourBody"
	_add(v, ab)
	_box(ab, "Coat", Vector3(0.5, 0.58, 0.31), Vector3(0, 1.13, 0), hide)
	_box(ab, "Collar", Vector3(0.3, 0.06, 0.3), Vector3(0, 1.43, 0), hide)
	var al := Node3D.new()
	al.name = "ArmourLegs"
	_add(v, al)
	for x in [-0.12, 0.12]:
		_box(al, "Leg" + ("L" if x < 0 else "R"), Vector3(0.19, 0.6, 0.22), Vector3(x, 0.5, 0), hide)
	var helmet := Node3D.new()
	helmet.name = "Helmet"
	helmet.position.y = 1.68
	_add(v, helmet)
	var hel := MeshInstance3D.new()
	hel.name = "Shell"
	var hs := SphereMesh.new()
	hs.radius = 0.17
	hs.height = 0.2
	hs.is_hemisphere = true
	hel.mesh = hs
	hel.material_override = olive
	_add(helmet, hel)
	# Arms: the right one holds the gun (or the machete)
	for spec in [["LeftArm", -0.31, 0.17], ["RightArm", 0.31, 0.26]]:
		var arm := Node3D.new()
		arm.name = spec[0]
		arm.position = Vector3(spec[1], 1.36, 0)
		arm.rotation.x = spec[2]
		_add(v, arm)
		var upper := _box(arm, "UpperArm", Vector3(0.13, 0.62, 0.14), Vector3(0, -0.3, 0), shirt)
		upper.set_meta("tint", "shirt")
		var hand := _box(arm, "Hand", Vector3(0.1, 0.1, 0.1), Vector3(0, -0.64, 0), skin)
		hand.set_meta("tint", "skin")
	var right := v.get_node("RightArm")
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, -0.64, -0.1)
	_add(right, gun)
	_box(gun, "Body", Vector3(0.06, 0.1, 0.42), Vector3(0, 0.02, -0.12), steel)
	_box(gun, "Stock", Vector3(0.05, 0.1, 0.18), Vector3(0, -0.01, 0.15), wood)
	_box(gun, "Grip", Vector3(0.04, 0.12, 0.05), Vector3(0, -0.07, 0.02), steel)
	var hammer := Node3D.new()
	hammer.name = "Hammer"
	hammer.position = Vector3(0, -0.64, -0.04)
	_add(right, hammer)
	_box(hammer, "Handle", Vector3(0.035, 0.035, 0.34), Vector3(0, 0, -0.12), wood)
	_box(hammer, "Head", Vector3(0.05, 0.15, 0.06), Vector3(0, 0.03, -0.3), steel)
	var axe := Node3D.new()
	axe.name = "Axe"
	axe.position = Vector3(0, -0.64, -0.04)
	_add(right, axe)
	_box(axe, "Haft", Vector3(0.035, 0.035, 0.55), Vector3(0, 0, -0.2), wood)
	_box(axe, "Head", Vector3(0.025, 0.16, 0.12), Vector3(0, 0.05, -0.45), steel)
	# A Miner's pickaxe (23)
	var pick := Node3D.new()
	pick.name = "Pickaxe"
	pick.position = Vector3(0, -0.64, -0.04)
	_add(right, pick)
	_box(pick, "Haft", Vector3(0.035, 0.035, 0.6), Vector3(0, 0, -0.22), wood)
	_box(pick, "Head", Vector3(0.03, 0.34, 0.05), Vector3(0, 0.0, -0.5), steel)
	var mach := Node3D.new()
	mach.name = "Machete"
	mach.position = Vector3(0, -0.64, -0.06)
	_add(right, mach)
	_box(mach, "Handle", Vector3(0.04, 0.04, 0.14), Vector3.ZERO, wood)
	_box(mach, "Blade", Vector3(0.015, 0.07, 0.5), Vector3(0, 0.02, -0.32), blade)

	var eyes := Marker3D.new()
	eyes.name = "Eyes"
	eyes.position = Vector3(0, 1.62, -0.1)
	_add(s, eyes)
	eyes.unique_name_in_owner = true
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = 0.8
	agent.path_height_offset = 0.5
	agent.path_max_distance = 3.0
	agent.height = 1.75
	agent.radius = 0.4
	_add(s, agent)
	agent.unique_name_in_owner = true
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100.0
	_add(s, health)
	health.unique_name_in_owner = true
	var label := Label3D.new()
	label.name = "NameLabel"
	label.position.y = 2.15
	label.pixel_size = 0.0007
	label.fixed_size = true  # the same size on screen near or far
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.text = "Settler"
	_add(s, label)
	label.unique_name_in_owner = true
	var talk := SettlerTalk.new()
	talk.name = "Talk"
	_add(s, talk)
	talk.unique_name_in_owner = true
	var ts := CollisionShape3D.new()
	ts.name = "Shape"
	var tc := CapsuleShape3D.new()
	tc.radius = 0.45
	tc.height = 1.8
	ts.shape = tc
	ts.position.y = 0.9
	_add(talk, ts)
	for spec in [["ShotSound", "res://assets/audio/pistol_shot_1.wav", 12.0], ["HitSound", "res://assets/audio/impact_flesh_1.wav", 4.0]]:
		var a := AudioStreamPlayer3D.new()
		a.name = spec[0]
		a.stream = load(spec[1])
		a.unit_size = spec[2]
		a.position.y = 1.2
		_add(s, a)
		a.unique_name_in_owner = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(s)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("wrote ", OUT, " (", error_string(err), ")")
	s.free()
	quit()


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = s


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_add(parent, mi)
	return mi


func _cyl(parent: Node, name: String, top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 14
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_add(parent, mi)
	return mi
