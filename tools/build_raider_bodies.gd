extends SceneTree
## Increment 29: raiders in real bodies. Rewrites the Visual of the Raider
## and the Raider Veteran (scenes/enemies/) as a HumanBody in raider
## colours (each one a bit different, Raider._ready picks the body), with
## their gear on its bones: a red bandana over the mouth, goggles on the
## forehead, a leather strap and a tyre pad, a machete in hand; the Veteran
## adds a scrap chest plate and knee pads. Then run build_marauder.gd for the
## Scorch Marauder (from the Veteran).
##
##   godot --headless --path . -s res://tools/build_raider_bodies.gd
##   godot --headless --path . -s res://tools/build_marauder.gd

const SCENES := {
	"res://scenes/enemies/raider.tscn": false,
	"res://scenes/enemies/raider_veteran.tscn": true,
}

var _mats := {}
var _root: Node


func _initialize() -> void:
	for path: String in SCENES:
		var r := (load(path) as PackedScene).instantiate()
		_root = r
		var v := r.get_node("Visual")
		for c in v.get_children():
			v.remove_child(c)
			c.free()
		_dress(v, SCENES[path])
		var packed := PackedScene.new()
		assert(packed.pack(r) == OK)
		assert(ResourceSaver.save(packed, path) == OK)
		print("wrote ", path)
		r.free()
	quit()


func _mat(key: String, c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


func _dress(v: Node, veteran: bool) -> void:
	var body := HumanBody.new()
	body.name = "Body"
	body.shirt = Color(0.3, 0.22, 0.15) if not veteran else Color(0.24, 0.2, 0.17)
	body.trousers = Color(0.2, 0.19, 0.17)
	body.boots = Color(0.1, 0.09, 0.08)
	body.colour_jitter = 0.25
	_add(v, body)
	var red := _mat("bandana", Color(0.55, 0.1, 0.07))
	var leather := _mat("leather", Color(0.3, 0.2, 0.12))
	var rubber := _mat("rubber", Color(0.08, 0.08, 0.08), 0.95)
	var rust := _mat("rust", Color(0.42, 0.28, 0.2), 0.7, 0.4)
	var blade := _mat("blade", Color(0.6, 0.6, 0.58), 0.4, 0.3)
	var wood := _mat("wood", Color(0.35, 0.22, 0.13))
	# A red bandana over the mouth and nose, tied behind
	var band := _slot(body, "Bandana", "Head", Vector3(0, 0.005, 0.03))
	_box(band, "Mask", Vector3(0.15, 0.075, 0.02), Vector3(0, 0, 0.085), red)
	_box(band, "Wrap", Vector3(0.16, 0.035, 0.15), Vector3(0, 0.02, 0.0), red)
	_box(band, "Knot", Vector3(0.04, 0.07, 0.03), Vector3(0, 0.0, -0.085), red)
	# Goggles pushed up on the forehead
	var gog := _slot(body, "Goggles", "Head", Vector3(0, 0.165, 0.025))
	_box(gog, "Strap", Vector3(0.15, 0.025, 0.02), Vector3(0, 0, 0.085), rubber)
	_box(gog, "Lens", Vector3(0.055, 0.04, 0.03), Vector3(-0.038, 0, 0.095), _mat("lens", Color(0.15, 0.12, 0.1), 0.2))
	_box(gog, "Lens2", Vector3(0.055, 0.04, 0.03), Vector3(0.038, 0, 0.095), _mat("lens", Color(0.15, 0.12, 0.1), 0.2))
	# A leather strap across the chest, a tyre pad on the left shoulder
	var strap := _slot(body, "ChestStrap", "UpperChest", Vector3(0, 0.05, 0.0))
	var s1 := _box(strap, "Front", Vector3(0.06, 0.48, 0.02), Vector3(0, 0, 0.145), leather)
	s1.rotation.z = 0.7
	var s2 := _box(strap, "Back", Vector3(0.06, 0.48, 0.02), Vector3(0, 0, -0.13), leather)
	s2.rotation.z = -0.7
	var tire := _slot(body, "TirePad", "UpperChest", Vector3(0.19, 0.2, -0.01))
	_box(tire, "Pad", Vector3(0.15, 0.045, 0.19), Vector3.ZERO, rubber)
	_box(tire, "Spike", Vector3(0.03, 0.08, 0.03), Vector3(0, 0.05, 0), rust)
	if veteran:
		var plate := _slot(body, "ChestPlate", "UpperChest", Vector3(0, 0.09, 0.0))
		_box(plate, "Front", Vector3(0.32, 0.3, 0.03), Vector3(0, 0, 0.155), rust)
		for side in ["Left", "Right"]:
			var knee := _slot(body, "KneePad" + side, side + "LowerLeg", Vector3(0, 0.02, 0.07))
			knee.set_meta("part", "KneePad")
			_box(knee, "Pad", Vector3(0.11, 0.13, 0.04), Vector3.ZERO, rust)
	# The machete (in the hand's frame: the handle along +X)
	var mach := _slot(body, "Machete", "RightHand", Vector3(0, 0.08, 0))
	mach.set_meta("space", "bone")
	_box(mach, "Handle", Vector3(0.13, 0.04, 0.04), Vector3.ZERO, wood)
	_box(mach, "Blade", Vector3(0.5, 0.015, 0.07), Vector3(0.3, 0, 0.02), blade)


func _slot(body: Node3D, n: String, bone: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = at
	node.set_meta("slot", bone)
	_add(body, node)
	return node


func _box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_add(parent, mi)
	return mi


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root
