extends SceneTree
## Builds the wood you can chop (Increment 19.7): scenes/world/timber/
##   dead_tree.tscn     a bare dead tree: 8 wood, leaves a stump, grows back
##   fallen_log.tscn    a fallen trunk: 6 wood, grows back
##   lumber_stack.tscn  a stack of old planks (a SalvagePile): 10 Wood Planks, once
##
##   godot --headless --path . -s res://tools/build_timber.gd

const OUT := "res://scenes/world/timber/"

var top: Node3D
var bark: StandardMaterial3D
var heart: StandardMaterial3D
var plank: Material


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var base := load("res://assets/ashfall_pack_v1/materials/wood_weathered.tres") as StandardMaterial3D
	bark = base.duplicate() as StandardMaterial3D
	bark.albedo_color = Color(0.5, 0.42, 0.36)
	heart = StandardMaterial3D.new()
	heart.albedo_color = Color(0.72, 0.58, 0.4)
	heart.roughness = 0.9
	plank = load("res://assets/materials/wood.tres")
	_tree()
	_log()
	_lumber()
	quit()


func _tree() -> void:
	top = _timber("DeadTree", "Dead Tree", 8, 3.0)
	_area_shape(CylinderShape3D.new(), 0.75, 2.2)
	var standing := _node(top, "Standing")
	var body := _body(standing)
	_cyl(standing, "Trunk", 0.1, 0.27, 5.6, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(3)), Vector3(0, 2.8, 0)), bark)
	var trunk := CollisionShape3D.new()
	trunk.name = "TrunkShape"
	var cs := CylinderShape3D.new()
	cs.radius = 0.24
	cs.height = 5.4
	trunk.shape = cs
	trunk.position.y = 2.7
	_add(body, trunk)
	# Bare branches reaching up and out
	for b: Array in [[2.9, 0.0, 50.0, 2.2], [3.6, 2.1, 42.0, 1.9], [4.3, 4.0, 55.0, 1.6], [3.2, 3.3, 38.0, 1.4], [4.9, 1.2, 30.0, 1.2]]:
		var yaw: float = b[1]
		var tilt := deg_to_rad(b[2])
		var length: float = b[3]
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, tilt)
		var at := Vector3(0, b[0], 0) + basis * Vector3(0, length / 2.0, 0)
		_cyl(standing, "Branch", 0.025, 0.08, length, Transform3D(basis, at), bark)
	var stump := _node(top, "Stump")
	_cyl(stump, "Stub", 0.25, 0.28, 0.45, Transform3D(Basis.IDENTITY, Vector3(0, 0.225, 0)), bark)
	_cyl(stump, "Cut", 0.235, 0.235, 0.02, Transform3D(Basis.IDENTITY, Vector3(0, 0.455, 0)), heart)
	_save("dead_tree")


func _log() -> void:
	top = _timber("FallenLog", "Fallen Log", 6, 2.5)
	var box := BoxShape3D.new()
	box.size = Vector3(4.4, 0.9, 1.1)
	var a := CollisionShape3D.new()
	a.name = "Shape"
	a.shape = box
	a.position.y = 0.45
	_add(top, a)
	var standing := _node(top, "Standing")
	var body := _body(standing)
	var lying := Basis(Vector3.BACK, deg_to_rad(90))
	_cyl(standing, "Trunk", 0.26, 0.32, 4.2, Transform3D(lying, Vector3(0, 0.3, 0)), bark)
	for x in [-2.1, 2.1]:
		_cyl(standing, "End", 0.27 if x < 0 else 0.31, 0.27 if x < 0 else 0.31, 0.02, Transform3D(lying, Vector3(x, 0.3, 0)), heart)
	_cyl(standing, "Stub", 0.03, 0.08, 1.1, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60)), Vector3(0.6, 0.65, 0.35)), bark)
	var shape := CollisionShape3D.new()
	shape.name = "LogShape"
	var lb := BoxShape3D.new()
	lb.size = Vector3(4.2, 0.6, 0.6)
	shape.shape = lb
	shape.position.y = 0.3
	_add(body, shape)
	_save("fallen_log")


func _lumber() -> void:
	top = SalvagePile.new()
	top.name = "LumberStack"
	top.collision_layer = PhysicsLayers.INTERACTABLES
	top.collision_mask = 0
	top.monitoring = false
	top.set("pile_name", "Lumber Stack")
	top.set("salvage_time", 2.0)
	var yields: Dictionary[ItemDefinition, int] = {load("res://resources/items/wood_plank.tres"): 10}
	top.set("yields", yields)
	top.set("focus_offset", Vector3(0, 0.4, 0))
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 0.9, 1.3)
	var a := CollisionShape3D.new()
	a.name = "Shape"
	a.shape = box
	a.position.y = 0.45
	_add(top, a)
	var model := _node(top, "Model")
	for i in 4:
		_cyl_free(model, "Bearer%d" % i, Vector3(0.12, 0.1, 1.2), Vector3(-1.1 + i * 0.73, 0.05, 0))
	var n := 0
	for layer in 4:
		for j in 5 - (layer % 2):
			_cyl_free(model, "Plank%d" % n, Vector3(2.5, 0.06, 0.2), Vector3((layer % 2) * 0.05, 0.13 + layer * 0.07, -0.46 + j * 0.23 + (layer % 2) * 0.1))
			n += 1
	_save("lumber_stack")


# ---------------------------------------------------------------- helpers

func _timber(node_name: String, display: String, wood: int, chop: float) -> Node3D:
	var t := Timber.new()
	t.name = node_name
	t.collision_layer = PhysicsLayers.INTERACTABLES
	t.collision_mask = 0
	t.monitoring = false
	t.timber_name = display
	t.wood = wood
	t.chop_time = chop
	t.focus_offset = Vector3(0, 1.0, 0)
	return t


func _area_shape(shape: CylinderShape3D, radius: float, height: float) -> void:
	shape.radius = radius
	shape.height = height
	var a := CollisionShape3D.new()
	a.name = "Shape"
	a.shape = shape
	a.position.y = height / 2.0
	_add(top, a)


func _node(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	_add(parent, n)
	n.unique_name_in_owner = true
	return n


func _body(parent: Node) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = "Body"
	b.collision_layer = PhysicsLayers.STRUCTURES
	b.collision_mask = 0
	_add(parent, b)
	return b


func _cyl(parent: Node, name: String, top_r: float, bottom_r: float, h: float, xf: Transform3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.transform = xf
	_add(parent, mi)


func _cyl_free(parent: Node, name: String, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = plank
	mi.position = pos
	_add(parent, mi)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	child.owner = top


func _save(id: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(top)
	if err == OK:
		err = ResourceSaver.save(packed, OUT + id + ".tscn")
	print("wrote %s (%s)" % [id, error_string(err)])
	top.free()
