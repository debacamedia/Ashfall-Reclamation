class_name FarmAnimal
extends Interactable
## A chicken, pig or cow in one of a settlement's pens (Increment 21.5).
## Made by its pen (SettlementBuilding with an `animal_kind`), which keeps
## the count; the animal only wanders about inside the pen's AnimalArea,
## stops to graze or peck, and can be butchered: hold E (3 s).
##
## Built from boxes in code (no scene): small enough for a dozen of them.

const KINDS := {
	&"chicken": {"name": "Chicken", "speed": 0.9, "size": 0.45},
	&"pig": {"name": "Pig", "speed": 0.7, "size": 1.1},
	&"cow": {"name": "Cow", "speed": 0.6, "size": 2.0},
}

var kind: StringName = &"chicken"
var pen: SettlementBuilding
var _goal := Vector3.INF
var _rest := 0.0
var _bob := 0.0
var _visual: Node3D
var _rng := RandomNumberGenerator.new()


static func make(animal_kind: StringName, home: SettlementBuilding, seed_value: int) -> FarmAnimal:
	var a := FarmAnimal.new()
	a.kind = animal_kind
	a.pen = home
	a._rng.seed = seed_value
	a.name = "%s%d" % [String(KINDS[animal_kind]["name"]), seed_value % 100000]
	return a


func _ready() -> void:
	add_to_group("farm_animals")
	action_name = "Butcher"
	object_name = "the " + String(KINDS[kind]["name"]).to_lower()
	hold_time = 3.0
	max_distance = 2.5
	var size: float = KINDS[kind]["size"]
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(size * 0.5, size * 0.6, size) if kind != &"chicken" else Vector3(0.35, 0.45, 0.4)
	shape.shape = box
	shape.position.y = box.size.y / 2.0
	add_child(shape)
	focus_offset = Vector3(0, box.size.y * 0.6, 0)
	_visual = _build_visual()
	add_child(_visual)
	_rest = _rng.randf_range(0.0, 3.0)


func get_block_reason(interactor: Node3D) -> String:
	var pc := interactor as PlayerController
	if pc == null or pc.is_dead():
		return "Can't do that now"
	if pen == null or pen.settlement() == null or not pen.settlement().is_claimed:
		return "Not yours"
	return ""


func _perform(interactor: Node3D) -> void:
	if pen != null:
		pen.settlement().request_butcher(interactor as PlayerController, self)


func _physics_process(delta: float) -> void:
	if pen == null or not is_instance_valid(pen):
		return
	var speed: float = KINDS[kind]["speed"]
	if _rest > 0.0:
		_rest -= delta
		# Grazing or pecking: the head dips now and then
		_bob += delta * (6.0 if kind == &"chicken" else 1.5)
		var head := _visual.get_node_or_null("Head") as Node3D
		if head != null:
			head.rotation.x = (0.5 + 0.5 * sin(_bob)) * (0.7 if kind == &"chicken" else 0.35)
		return
	if _goal == Vector3.INF:
		_goal = pen.random_animal_spot(_rng)
	var to := _goal - global_position
	to.y = 0.0
	if to.length() < 0.15:
		_goal = Vector3.INF
		_rest = _rng.randf_range(2.0, 7.0)
		return
	var step := to.normalized() * minf(speed * delta, to.length())
	global_position += step
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
	# A little bounce as they walk
	_bob += delta * speed * 9.0
	_visual.position.y = absf(sin(_bob)) * (0.04 if kind == &"chicken" else 0.02)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _box(parent: Node3D, n: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## Facing -z, feet on y = 0.
func _build_visual() -> Node3D:
	var v := Node3D.new()
	v.name = "Visual"
	match kind:
		&"chicken":
			var hue := _rng.randf()
			var feather := _mat(Color(0.95, 0.93, 0.88) if hue < 0.5 else Color(0.62, 0.38, 0.2))
			var leg := _mat(Color(0.9, 0.65, 0.2))
			_box(v, "Body", Vector3(0.22, 0.2, 0.3), Vector3(0, 0.24, 0), feather)
			_box(v, "Tail", Vector3(0.14, 0.14, 0.08), Vector3(0, 0.33, 0.16), feather)
			for x in [-0.05, 0.05]:
				_box(v, "Leg%s" % ("L" if x < 0 else "R"), Vector3(0.025, 0.14, 0.025), Vector3(x, 0.07, 0), leg)
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0, 0.34, -0.12)
			v.add_child(head)
			_box(head, "Skull", Vector3(0.11, 0.12, 0.11), Vector3(0, 0.05, -0.04), feather)
			_box(head, "Beak", Vector3(0.04, 0.03, 0.05), Vector3(0, 0.04, -0.12), leg)
			_box(head, "Comb", Vector3(0.025, 0.05, 0.07), Vector3(0, 0.13, -0.04), _mat(Color(0.85, 0.15, 0.12)))
		&"pig":
			var skin := _mat(Color(0.92, 0.66, 0.62) if _rng.randf() < 0.7 else Color(0.35, 0.28, 0.26))
			_box(v, "Body", Vector3(0.55, 0.5, 1.0), Vector3(0, 0.5, 0), skin)
			for c in [Vector2(-0.18, -0.32), Vector2(0.18, -0.32), Vector2(-0.18, 0.32), Vector2(0.18, 0.32)]:
				_box(v, "Leg%d%d" % [int(c.x > 0), int(c.y > 0)], Vector3(0.13, 0.28, 0.13), Vector3(c.x, 0.14, c.y), skin)
			_box(v, "Tail", Vector3(0.05, 0.12, 0.05), Vector3(0, 0.66, 0.52), skin)
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0, 0.55, -0.5)
			v.add_child(head)
			_box(head, "Skull", Vector3(0.4, 0.36, 0.3), Vector3(0, 0.0, -0.12), skin)
			_box(head, "Snout", Vector3(0.2, 0.15, 0.1), Vector3(0, -0.05, -0.31), _mat(Color(0.85, 0.5, 0.5)))
			for x in [-0.13, 0.13]:
				_box(head, "Ear%s" % ("L" if x < 0 else "R"), Vector3(0.1, 0.12, 0.04), Vector3(x, 0.2, -0.05), skin)
		&"cow":
			var white := _mat(Color(0.92, 0.9, 0.86))
			var patch := _mat(Color(0.18, 0.15, 0.14) if _rng.randf() < 0.6 else Color(0.5, 0.3, 0.18))
			_box(v, "Body", Vector3(0.75, 0.75, 1.6), Vector3(0, 1.05, 0), white)
			_box(v, "Patch", Vector3(0.77, 0.45, 0.55), Vector3(0, 1.15, 0.25), patch)
			_box(v, "Patch2", Vector3(0.77, 0.35, 0.35), Vector3(0, 1.0, -0.45), patch)
			for c in [Vector2(-0.26, -0.6), Vector2(0.26, -0.6), Vector2(-0.26, 0.6), Vector2(0.26, 0.6)]:
				_box(v, "Leg%d%d" % [int(c.x > 0), int(c.y > 0)], Vector3(0.16, 0.7, 0.16), Vector3(c.x, 0.35, c.y), white)
			_box(v, "Udder", Vector3(0.3, 0.15, 0.3), Vector3(0, 0.62, 0.45), _mat(Color(0.9, 0.65, 0.62)))
			_box(v, "Tail", Vector3(0.06, 0.6, 0.06), Vector3(0, 0.95, 0.82), white)
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0, 1.3, -0.8)
			v.add_child(head)
			_box(head, "Skull", Vector3(0.42, 0.45, 0.5), Vector3(0, -0.05, -0.22), white)
			_box(head, "Muzzle", Vector3(0.36, 0.22, 0.12), Vector3(0, -0.2, -0.5), _mat(Color(0.85, 0.65, 0.6)))
			for x in [-0.24, 0.24]:
				_box(head, "Horn%s" % ("L" if x < 0 else "R"), Vector3(0.14, 0.06, 0.06), Vector3(x, 0.2, -0.15), _mat(Color(0.85, 0.82, 0.72)))
	return v
