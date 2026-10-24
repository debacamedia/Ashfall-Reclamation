extends SceneTree
## Renders an inventory icon for every ItemDefinition from its world_model
## and saves it to assets/icons/<id>.png (128×128, transparent background).
##
## Needs a real renderer (not --headless):
##   godot --path . -s res://tools/render_item_icons.gd
## Then assign the PNGs to each item's `icon` (the Increment 6 build did this).

const SIZE := 128
const OUT := "res://assets/icons/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, 35, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)

	for item in ItemDatabase.all_items():
		if item.world_model == null:
			continue
		var model := item.world_model.instantiate() as Node3D
		vp.add_child(model)
		var bounds := _bounds(model)
		var centre := bounds.get_center()
		# Three-quarter view from the front-right, slightly above
		var dir := Vector3(0.9, 0.75, 1.0).normalized()
		cam.size = bounds.size.length() * 1.05
		cam.position = centre + dir * 5.0
		cam.look_at(centre, Vector3.UP)
		for i in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(OUT + String(item.id) + ".png")
		print("icon: ", item.id)
		model.free()
	quit()


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
