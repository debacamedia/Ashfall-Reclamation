extends SceneTree
## Builds the settler (Increment 19): scenes/npcs/settler.tscn. Since 29 a
## real person (HumanBody: a Quaternius body, dressed and animated), looks
## picked per settler (Settler._apply_look), with each job's gear on their
## bones: a straw hat for farmers, a vest and helmet for guards, a gun or
## machete in hand…
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

	var straw := _mat("straw", Color(0.78, 0.66, 0.38))
	var olive := _mat("olive", Color(0.3, 0.33, 0.2))
	var steel := _mat("steel", Color(0.2, 0.2, 0.21), 0.5)
	var blade := _mat("blade", Color(0.72, 0.72, 0.72), 0.35)
	var wood := _mat("wood", Color(0.38, 0.25, 0.14))
	var leather := _mat("leather", Color(0.42, 0.28, 0.16))
	var whites := _mat("whites", Color(0.93, 0.92, 0.88))
	var hat_leather := _mat("hat_leather", Color(0.45, 0.3, 0.17))
	var hard_hat := _mat("hard_hat", Color(0.92, 0.72, 0.12), 0.5)
	var plate := _mat("armour", Color(0.45, 0.46, 0.48), 0.6)

	var v := Node3D.new()
	v.name = "Visual"
	_add(s, v)
	v.unique_name_in_owner = true
	# The person (Increment 29): a Quaternius body, dressed and animated;
	# their looks are picked from their name when they're made
	# (Settler._apply_look). Gear hangs on its bones: each node below says
	# which with a "slot" meta, laid out in that bone's space (+Y up the
	# bone, +Z the way the face looks; in the hand +Y runs to the
	# fingertips and a handle lies along +X through the fist).
	var person := HumanBody.new()
	person.name = "Body"
	_add(v, person)
	# Farmer's straw hat
	var hat := _slot(person, "Hat", "Head", Vector3(0, 0.19, 0.025))
	_cyl(hat, "Brim", 0.24, 0.24, 0.02, Vector3.ZERO, straw)
	_cyl(hat, "Crown", 0.095, 0.11, 0.11, Vector3(0, 0.055, 0), straw)
	# Guard's vest and helmet
	var vest := _slot(person, "Vest", "UpperChest", Vector3(0, 0.1, 0.0))
	_box(vest, "Front", Vector3(0.34, 0.36, 0.04), Vector3(0, 0, 0.14), olive)
	_box(vest, "Back", Vector3(0.34, 0.36, 0.04), Vector3(0, 0, -0.12), olive)
	_box(vest, "Pouch", Vector3(0.12, 0.08, 0.05), Vector3(0.09, -0.13, 0.17), olive)
	var helmet := _slot(person, "Helmet", "Head", Vector3(0, 0.135, 0.02))
	_dome(helmet, "Shell", 0.13, olive)
	# Builder's (and Miner's) hard hat, Miner's lamp, Armorer's goggles
	var hard := _slot(person, "HardHat", "Head", Vector3(0, 0.14, 0.02))
	_dome(hard, "Shell", 0.125, hard_hat)
	_box(hard, "Brim", Vector3(0.25, 0.015, 0.29), Vector3(0, 0.004, 0.025), hard_hat)
	var lamp := _slot(person, "HeadLamp", "Head", Vector3(0, 0.2, 0.135))
	_box(lamp, "Lamp", Vector3(0.06, 0.045, 0.035), Vector3.ZERO, _mat("lamp_glass", Color(1.0, 0.95, 0.7), 0.2))
	var gog := _slot(person, "Goggles", "Head", Vector3(0, 0.165, 0.025))
	_box(gog, "Strap", Vector3(0.15, 0.025, 0.02), Vector3(0, 0, 0.085), leather)
	_box(gog, "LensL", Vector3(0.055, 0.04, 0.03), Vector3(-0.038, 0.0, 0.095), _mat("goggle_glass", Color(0.35, 0.55, 0.5), 0.2))
	_box(gog, "LensR", Vector3(0.055, 0.04, 0.03), Vector3(0.038, 0.0, 0.095), _mat("goggle_glass", Color(0.35, 0.55, 0.5), 0.2))
	# Builder's and Armorer's tool belt
	var belt := _slot(person, "ToolBelt", "Hips", Vector3(0, 0.06, 0))
	_box(belt, "Belt", Vector3(0.36, 0.07, 0.25), Vector3.ZERO, leather)
	_box(belt, "Pouch", Vector3(0.1, 0.13, 0.07), Vector3(-0.16, -0.07, 0.07), leather)
	# Cook's and Tailor's apron, Cook's chef's hat, Rancher's hat
	var apron := _slot(person, "Apron", "UpperChest", Vector3(0, 0.06, 0.15))
	_box(apron, "Bib", Vector3(0.26, 0.26, 0.02), Vector3.ZERO, whites)
	var skirt := _slot(person, "ApronSkirt", "Hips", Vector3(0, -0.14, 0.15))
	skirt.set_meta("part", "Apron")
	_box(skirt, "Skirt", Vector3(0.34, 0.4, 0.02), Vector3.ZERO, whites)
	var chef := _slot(person, "ChefHat", "Head", Vector3(0, 0.175, 0.015))
	_cyl(chef, "Band", 0.105, 0.105, 0.06, Vector3(0, 0.0, 0), whites)
	_cyl(chef, "Puff", 0.12, 0.095, 0.11, Vector3(0, 0.085, 0), whites)
	var cowboy := _slot(person, "CowboyHat", "Head", Vector3(0, 0.19, 0.025))
	_cyl(cowboy, "Brim", 0.25, 0.25, 0.02, Vector3.ZERO, hat_leather)
	_cyl(cowboy, "Crown", 0.09, 0.105, 0.12, Vector3(0, 0.065, 0), hat_leather)
	_cyl(cowboy, "Band", 0.107, 0.107, 0.025, Vector3(0, 0.02, 0), _mat("hat_band", Color(0.15, 0.1, 0.08)))
	# Armour (22): the coat and trousers recolour the clothes
	# (Settler._update_visuals); a helmet, and plates for plated pieces
	var ah := _slot(person, "ArmourHead", "Head", Vector3(0, 0.135, 0.02))
	_dome(ah, "Shell", 0.135, plate)
	var ab := _slot(person, "ArmourBody", "UpperChest", Vector3(0, 0.1, 0))
	_box(ab, "ChestPlate", Vector3(0.32, 0.3, 0.035), Vector3(0, 0, 0.15), plate)
	_box(ab, "BackPlate", Vector3(0.32, 0.3, 0.035), Vector3(0, 0, -0.13), plate)
	for side in ["Left", "Right"]:
		var knee := _slot(person, "ArmourLegs" + side, side + "LowerLeg", Vector3(0, 0.02, 0.07))
		knee.set_meta("part", "ArmourLegs")
		_box(knee, "KneePlate", Vector3(0.1, 0.14, 0.035), Vector3.ZERO, plate)
	# In the right hand (laid out in the hand's frame): the gun (pointed
	# where they face by Settler._process), a hammer, an axe, a pickaxe or a
	# machete
	var gun := _slot(person, "Gun", "RightHand", Vector3(0, 0.08, 0))
	gun.set_meta("space", "bone")
	_box(gun, "Body", Vector3(0.05, 0.09, 0.42), Vector3(0, 0.03, -0.16), steel)
	_box(gun, "Stock", Vector3(0.045, 0.09, 0.18), Vector3(0, 0.0, 0.1), wood)
	_box(gun, "Grip", Vector3(0.035, 0.11, 0.045), Vector3(0, -0.04, -0.02), steel)
	var hammer := _slot(person, "Hammer", "RightHand", Vector3(0, 0.08, 0))
	_box(hammer, "Handle", Vector3(0.34, 0.035, 0.035), Vector3(0.12, 0, 0), wood)
	_box(hammer, "Head", Vector3(0.06, 0.05, 0.15), Vector3(0.29, 0, 0), steel)
	var axe := _slot(person, "Axe", "RightHand", Vector3(0, 0.08, 0))
	_box(axe, "Haft", Vector3(0.55, 0.035, 0.035), Vector3(0.18, 0, 0), wood)
	_box(axe, "Head", Vector3(0.12, 0.025, 0.16), Vector3(0.42, 0, 0.05), steel)
	var pick := _slot(person, "Pickaxe", "RightHand", Vector3(0, 0.08, 0))
	_box(pick, "Haft", Vector3(0.6, 0.035, 0.035), Vector3(0.2, 0, 0), wood)
	_box(pick, "Head", Vector3(0.05, 0.03, 0.34), Vector3(0.47, 0, 0), steel)
	var mach := _slot(person, "Machete", "RightHand", Vector3(0, 0.08, 0))
	_box(mach, "Handle", Vector3(0.13, 0.04, 0.04), Vector3(0.0, 0, 0), wood)
	_box(mach, "Blade", Vector3(0.5, 0.015, 0.07), Vector3(0.3, 0, 0.02), blade)
	for n in [hammer, axe, pick, mach]:
		n.set_meta("space", "bone")

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


## A gear node hung on a bone of the body (HumanBody moves it there).
func _slot(body: Node3D, name: String, bone: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = at
	n.set_meta("slot", bone)
	_add(body, n)
	return n


func _dome(parent: Node, name: String, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 1.15
	m.is_hemisphere = true
	m.radial_segments = 16
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat
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
