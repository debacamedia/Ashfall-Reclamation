extends SceneTree
## Increment 33: the Field Manual as an item: Outpost 17's issue booklet,
## olive card covers over yellowed pages, with a stencilled band. Builds its
## world model and its ItemDefinition. Run once:
##   godot --headless --path . -s res://tools/make_field_manual_item.gd
## then its icon: godot --path . -s res://tools/render_item_icons.gd -- field_manual
## Leaves existing files alone.

const MODEL := "res://scenes/items/models/field_manual_world.tscn"
const ITEM := "res://resources/items/field_manual.tres"


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(root: Node3D, name: String, size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	root.add_child(mi)
	mi.owner = root


func _initialize() -> void:
	if not ResourceLoader.exists(MODEL):
		var root := Node3D.new()
		root.name = "FieldManualWorld"
		var cover := _mat(Color(0.29, 0.31, 0.2))
		_box(root, "BackCover", Vector3(0.15, 0.004, 0.21), Vector3(0, 0.002, 0), cover)
		_box(root, "Pages", Vector3(0.142, 0.014, 0.202), Vector3(0.003, 0.011, 0), _mat(Color(0.86, 0.8, 0.63)))
		_box(root, "FrontCover", Vector3(0.15, 0.004, 0.21), Vector3(0, 0.02, 0), cover)
		_box(root, "Spine", Vector3(0.006, 0.022, 0.21), Vector3(-0.075, 0.011, 0), cover)
		_box(root, "Band", Vector3(0.11, 0.001, 0.03), Vector3(0.005, 0.0225, -0.05), _mat(Color(0.82, 0.76, 0.58)))
		_box(root, "Stencil", Vector3(0.07, 0.001, 0.008), Vector3(0.005, 0.0232, -0.05), _mat(Color(0.2, 0.18, 0.13)))
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, MODEL)
		root.free()
		print("wrote ", MODEL)
	if not ResourceLoader.exists(ITEM):
		var it := ItemDefinition.new()
		it.id = &"field_manual"
		it.display_name = "Field Manual"
		it.description = "Outpost 17's issue copy of the Reclamation Field Manual, annotated in red pen by Sgt. Ada Vance. Press N to read it, or hold it and fire."
		it.category = ItemDefinition.Category.MISC
		it.max_stack = 1
		it.weight = 0.0
		it.base_value = 0
		it.holdable = true
		it.keep_on_death = true
		it.world_model = load(MODEL)
		it.pickup_hold_time = 0.3
		ResourceSaver.save(it, ITEM)
		print("wrote ", ITEM)
	quit()
