extends SceneTree
## Builds Increment 28's tailoring: Wool (sheared from sheep), Wool Clothes
## (worn on the body, a little protection) and three padded pieces made from
## clothes, leather and scrap. Their models, items and recipes (at a
## workbench, the same ones a settlement's Tailor follows).
##
##   godot --headless --path . -s res://tools/build_tailoring.gd
## Then render the icons (needs a window):
##   godot --path . -s res://tools/render_item_icons.gd -- wool,wool_clothes,padded_hood,padded_coat,padded_trousers

const MODELS := "res://scenes/items/models/"
const ITEMS := "res://resources/items/"
const RECIPES := "res://resources/recipes/"

## id: [name, slot (1 head, 2 body, 3 legs), protection, durability, speed,
##      weight, value, repair {id: n}, recipe inputs {id: n}, craft s, description]
const PIECES := {
	&"wool_clothes": ["Wool Clothes", 2, 0.05, 100.0, 1.0, 0.8, 8, {&"wool": 1}, {&"wool": 3}, 5.0,
		"A thick wool shirt and jerkin, spun and stitched from Ash Creek fleece. Warm, and takes a little off a blow."],
	&"padded_hood": ["Padded Hood", 1, 0.09, 180.0, 1.0, 0.6, 14, {&"wool": 1}, {&"wool_clothes": 1, &"leather": 1, &"scrap_metal": 1}, 6.0,
		"A quilted wool hood with a leather crown and a scrap-metal brow band."],
	&"padded_coat": ["Padded Coat", 2, 0.2, 320.0, 0.98, 3.2, 35, {&"wool": 1, &"scrap_metal": 1}, {&"wool_clothes": 2, &"leather": 2, &"scrap_metal": 3}, 10.0,
		"Layers of quilted wool over leather, with scrap plates sewn into the chest. Between a leather jacket and a plated vest."],
	&"padded_trousers": ["Padded Trousers", 3, 0.11, 240.0, 1.0, 1.6, 20, {&"wool": 1}, {&"wool_clothes": 1, &"leather": 1, &"scrap_metal": 2}, 7.0,
		"Quilted trousers with leather knees and scrap shin guards."],
}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var wool := _item(&"wool", "Wool", "Fleece sheared from your sheep, cleaned and carded. A Tailor spins it into clothes; so can you, at a workbench.",
		ItemDefinition.Category.RESOURCE, 0.3, 30, 4, "wool")
	ResourceSaver.save(wool, ITEMS + "wool.tres")
	print("item wool")
	for id: StringName in PIECES:
		var s: Array = PIECES[id]
		var it := _item(id, s[0], s[10], ItemDefinition.Category.EQUIPMENT, s[5], 1, s[6], String(id))
		it.armour_slot = s[1]
		it.armour_protection = s[2]
		it.armour_durability = s[3]
		it.armour_speed = s[4]
		it.armour_repair = s[7]
		ResourceSaver.save(it, ITEMS + String(id) + ".tres")
	# Recipes after every item exists (the padded ones take Wool Clothes)
	for id: StringName in PIECES:
		var s: Array = PIECES[id]
		var r := RecipeDefinition.new()
		r.id = id
		r.category = RecipeDefinition.Category.GEAR
		r.station = RecipeDefinition.Station.WORKBENCH
		var inputs: Dictionary[ItemDefinition, int] = {}
		for iid: StringName in s[8]:
			inputs[load(ITEMS + String(iid) + ".tres") as ItemDefinition] = s[8][iid]
		r.inputs = inputs
		r.output = load(ITEMS + String(id) + ".tres")
		r.output_quantity = 1
		r.craft_time = s[9]
		ResourceSaver.save(r, RECIPES + String(id) + ".tres")
		print("piece ", id)
	quit()


func _item(id: StringName, display: String, about: String, cat: ItemDefinition.Category, weight: float, stack: int, value: int, model_kind: String) -> ItemDefinition:
	var model := _model(model_kind)
	var packed := PackedScene.new()
	packed.pack(model)
	var model_path := MODELS + String(id) + ".tscn"
	ResourceSaver.save(packed, model_path)
	model.free()
	var path := ITEMS + String(id) + ".tres"
	var item: ItemDefinition = load(path) if ResourceLoader.exists(path) else ItemDefinition.new()
	item.id = id
	item.display_name = display
	item.description = about
	item.category = cat
	item.weight = weight
	item.max_stack = stack
	item.base_value = value
	item.pickup_sound = load("res://assets/ashfall_pack_v3/sets/pickup_soft.tres")
	item.world_model = load(model_path)
	var icon := "res://assets/icons/%s.png" % String(id)
	if ResourceLoader.exists(icon):
		item.icon = load(icon)
	return item


# ---------------------------------------------------------------- models

func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
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
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _ball(parent: Node3D, n: String, r: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 1.6
	m.radial_segments = 10
	m.rings = 5
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


## Laid flat (as they'd lie on the ground), about 0.4 m across.
func _model(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var wool := _mat(Color(0.86, 0.82, 0.72))
	var oat := _mat(Color(0.72, 0.64, 0.5))
	var quilt := _mat(Color(0.44, 0.42, 0.3))
	var hide := _mat(Color(0.48, 0.3, 0.17), 0.85)
	var rust := _mat(Color(0.45, 0.3, 0.22), 0.7, 0.4)
	match kind:
		"wool":
			# A bundle of carded fleece, tied
			for i in 4:
				_ball(root, "Fleece%d" % i, 0.09 - i * 0.008, Vector3(-0.08 + i * 0.055, 0.06, (i % 2) * 0.04 - 0.02), wool)
			_box(root, "Twine", Vector3(0.012, 0.13, 0.17), Vector3(0.0, 0.06, 0), _mat(Color(0.55, 0.45, 0.3)))
		"wool_clothes":
			_box(root, "Shirt", Vector3(0.3, 0.04, 0.34), Vector3(0, 0.02, 0), wool)
			for x in [-0.21, 0.21]:
				var sl := _box(root, "Sleeve%s" % ("L" if x < 0 else "R"), Vector3(0.1, 0.035, 0.28), Vector3(x, 0.02, 0.05), wool)
				sl.rotation_degrees.y = -18.0 if x < 0 else 18.0
			_box(root, "Jerkin", Vector3(0.24, 0.02, 0.26), Vector3(0, 0.05, 0.02), oat)
			_box(root, "Collar", Vector3(0.14, 0.05, 0.05), Vector3(0, 0.04, -0.16), oat)
		"padded_hood":
			_ball(root, "Hood", 0.12, Vector3(0, 0.05, 0), quilt)
			_box(root, "Crown", Vector3(0.12, 0.03, 0.14), Vector3(0, 0.12, 0), hide)
			_box(root, "Brow", Vector3(0.2, 0.025, 0.03), Vector3(0, 0.08, -0.11), rust)
		"padded_coat":
			_box(root, "Torso", Vector3(0.34, 0.06, 0.38), Vector3(0, 0.03, 0), quilt)
			for i in 4:
				_box(root, "Quilt%d" % i, Vector3(0.33, 0.012, 0.012), Vector3(0, 0.066, -0.14 + i * 0.09), oat)
			for x in [-0.23, 0.23]:
				var sl := _box(root, "Sleeve%s" % ("L" if x < 0 else "R"), Vector3(0.11, 0.05, 0.32), Vector3(x, 0.025, 0.06), quilt)
				sl.rotation_degrees.y = -20.0 if x < 0 else 20.0
			_box(root, "Leather", Vector3(0.2, 0.02, 0.12), Vector3(0, 0.07, -0.1), hide)
			_box(root, "Plate", Vector3(0.12, 0.02, 0.1), Vector3(0, 0.08, 0.04), rust)
		"padded_trousers":
			for x in [-0.07, 0.07]:
				_box(root, "Leg%s" % ("L" if x < 0 else "R"), Vector3(0.12, 0.045, 0.42), Vector3(x, 0.022, 0.05), quilt)
				_box(root, "Knee%s" % ("L" if x < 0 else "R"), Vector3(0.09, 0.02, 0.07), Vector3(x, 0.05, 0.08), hide)
				_box(root, "Shin%s" % ("L" if x < 0 else "R"), Vector3(0.08, 0.02, 0.1), Vector3(x, 0.05, 0.19), rust)
			_box(root, "Waist", Vector3(0.28, 0.05, 0.08), Vector3(0, 0.025, -0.18), oat)
	return root
