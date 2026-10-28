extends SceneTree
## Builds the backpacks (Increment 16.8): their world models, item
## definitions and recipes, from the data below.
##
##   godot --headless --path . -s res://tools/build_backpacks.gd
##   godot --path . -s res://tools/render_item_icons.gd -- satchel,rucksack,military_pack,frame_pack
##   godot --headless --path . -s res://tools/build_backpacks.gd     (again, to pick up the icons)
##
## Where the military pack and frame pack turn up as loot is in
## tools/build_sites.gd (LOOT).

const MODELS := "res://scenes/items/models/"
const ITEMS := "res://resources/items/"
const RECIPES := "res://resources/recipes/"
const MAT := "res://assets/materials/"

## id: [name, slots, carry kg, own weight, value, rattle m, body material, size, description]
const PACKS := {
	"satchel": ["Satchel", 24, 30.0, 0.5, 10, 0.0, "tent_canvas", Vector3(0.36, 0.3, 0.14),
		"The shoulder bag you started with. 24 slots, 30 kg. You never lose it."],
	"rucksack": ["Rucksack", 30, 40.0, 1.2, 80, 0.0, "tent_canvas", Vector3(0.38, 0.46, 0.2),
		"A patched canvas rucksack on a stick frame. 30 slots, 40 kg. Put it on from your backpack (right-click or Wear)."],
	"military_pack": ["Military Pack", 36, 50.0, 1.8, 220, 0.0, "olive_drab", Vector3(0.42, 0.56, 0.24),
		"An army field pack with side pouches. 36 slots, 50 kg. Garrisons and smugglers keep these."],
	"frame_pack": ["Frame Pack", 42, 60.0, 2.6, 300, 14.0, "olive_drab", Vector3(0.46, 0.66, 0.26),
		"A welded pipe frame with a load bag: 42 slots, 60 kg. It rattles when you walk: raiders nearby will hear you (crouch to move quietly)."],
}

## id: [station (0 hand, 1 workbench), seconds, {input id: count}]
const CRAFT := {
	"rucksack": [0, 8.0, {"cloth": 6, "wood_plank": 2, "scrap_metal": 2}],
	"frame_pack": [1, 14.0, {"metal_pipe": 3, "spring": 2, "metal_plate": 1, "cloth": 8}],
}


func _initialize() -> void:
	for id in PACKS:
		_model(id)
		_item(id)
	for id in CRAFT:
		_recipe(id)
	print("backpacks built")
	quit()


func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = load(MAT + mat + ".tres")
	mi.position = pos
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner


func _model(id: String) -> void:
	var spec: Array = PACKS[id]
	var s: Vector3 = spec[7]
	var body_mat: String = spec[6]
	var root := Node3D.new()
	root.name = String(spec[0]).to_pascal_case()
	# Lying on its back, straps up, as it would on the ground
	_box(root, "Bag", Vector3(s.x, s.z, s.y), Vector3(0, s.z / 2.0, 0), body_mat)
	_box(root, "Flap", Vector3(s.x * 1.02, 0.03, s.y * 0.35), Vector3(0, s.z + 0.015, -s.y * 0.33), body_mat if id != "satchel" else "raider_leather")
	_box(root, "StrapL", Vector3(0.05, 0.02, s.y * 0.85), Vector3(-s.x * 0.25, s.z + 0.01, 0.02), "raider_leather")
	_box(root, "StrapR", Vector3(0.05, 0.02, s.y * 0.85), Vector3(s.x * 0.25, s.z + 0.01, 0.02), "raider_leather")
	if id in ["military_pack", "frame_pack"]:
		_box(root, "PouchL", Vector3(0.08, s.z * 0.7, s.y * 0.4), Vector3(-s.x / 2.0 - 0.04, s.z * 0.35, 0.05), "olive_drab")
		_box(root, "PouchR", Vector3(0.08, s.z * 0.7, s.y * 0.4), Vector3(s.x / 2.0 + 0.04, s.z * 0.35, 0.05), "olive_drab")
	if id == "rucksack":
		_box(root, "StickL", Vector3(0.03, 0.03, s.y * 1.05), Vector3(-s.x / 2.0 + 0.03, s.z + 0.03, 0), "wood")
		_box(root, "StickR", Vector3(0.03, 0.03, s.y * 1.05), Vector3(s.x / 2.0 - 0.03, s.z + 0.03, 0), "wood")
	if id == "frame_pack":
		for x in [-1.0, 1.0]:
			_box(root, "Rail%s" % ("L" if x < 0 else "R"), Vector3(0.035, 0.035, s.y * 1.25), Vector3(x * (s.x / 2.0 + 0.02), s.z + 0.04, 0.0), "metal_dark")
		for z in [-0.45, 0.0, 0.45]:
			_box(root, "Bar%d" % roundi(z * 10), Vector3(s.x + 0.08, 0.03, 0.03), Vector3(0, s.z + 0.04, z * s.y), "metal_dark")
	if id == "satchel":
		_box(root, "Buckle", Vector3(0.06, 0.02, 0.05), Vector3(0, s.z + 0.035, s.y * 0.0), "metal_dark")
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, MODELS + id + ".tscn")
	root.free()


func _item(id: String) -> void:
	var spec: Array = PACKS[id]
	var path := ITEMS + id + ".tres"
	var item: ItemDefinition = load(path) if ResourceLoader.exists(path) else ItemDefinition.new()
	item.id = StringName(id)
	item.display_name = spec[0]
	item.description = spec[8]
	item.category = ItemDefinition.Category.EQUIPMENT
	item.max_stack = 1
	item.weight = spec[3]
	item.base_value = spec[4]
	item.pack_slots = spec[1]
	item.pack_carry_weight = spec[2]
	item.pack_rattle_radius = spec[5]
	item.world_model = load(MODELS + id + ".tscn")
	item.pickup_hold_time = 0.3
	if ResourceLoader.exists("res://assets/ashfall_pack_v3/sets/pickup_soft.tres"):
		item.pickup_sound = load("res://assets/ashfall_pack_v3/sets/pickup_soft.tres")
	var icon := "res://assets/icons/%s.png" % id
	if ResourceLoader.exists(icon):
		item.icon = load(icon)
	ResourceSaver.save(item, path)


func _recipe(id: String) -> void:
	var spec: Array = CRAFT[id]
	var r := RecipeDefinition.new()
	r.id = StringName("craft_" + id)
	r.category = RecipeDefinition.Category.GEAR
	r.station = RecipeDefinition.Station.HAND if spec[0] == 0 else RecipeDefinition.Station.WORKBENCH
	r.craft_time = spec[1]
	var inputs: Dictionary[ItemDefinition, int] = {}
	for input_id in spec[2]:
		var input := load(ITEMS + input_id + ".tres") as ItemDefinition
		assert(input != null, input_id)
		inputs[input] = spec[2][input_id]
	r.inputs = inputs
	r.output = load(ITEMS + id + ".tres")
	r.output_quantity = 1
	ResourceSaver.save(r, RECIPES + "craft_" + id + ".tres")
