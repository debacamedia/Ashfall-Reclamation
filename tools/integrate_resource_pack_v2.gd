extends SceneTree
## Resource Pack 2.0 integration into Outpost 17 (kept for review and re-runs).
## Run headless from the project root:
##   godot --headless --path . -s res://tools/integrate_resource_pack_v2.gd
## Re-running is safe: the Pack2 node is rebuilt. Only the level scene and its
## navmesh change. Everything Pack 2 adds lives under the level's "Pack2" node:
##   Signs     6 m-clear sign quads raycast onto walls (alpha scissor)
##   Overlays  weathering decals (alpha blend), same placement rule
##   Props     the pack's prop scenes (StaticBody3D), in navigation_geometry
##   Sounds    3D ambient sources (AudioStreamPlayer3D / RandomSoundEmitter)
## Props are checked against existing geometry; the build fails if one
## overlaps anything. The navmesh is rebaked so raiders path around them.

const LEVEL := "res://levels/outpost_17/outpost_17.tscn"
const NAVMESH := "res://levels/outpost_17/outpost_17_navmesh.tres"
const PACK := "res://assets/ashfall_pack_v2/"

var _level: Node3D
var _space: PhysicsDirectSpaceState3D
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_level = (load(LEVEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	(_level.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	if _level.get_node_or_null("Pack2") != null:
		_level.get_node("Pack2").free()
	root.add_child(_level)
	await physics_frame
	await physics_frame
	_space = _level.get_world_3d().direct_space_state
	var pack := _node(_level, "Pack2")
	var signs := _node(pack, "Signs")
	var overlays := _node(pack, "Overlays")
	var props := _node(pack, "Props")
	props.add_to_group("navigation_geometry", true)
	var sounds := _node(pack, "Sounds")

	# ---------------------------------------------------------------- props
	# Water point against the west wall, between the NW tower and the culvert
	var tank := _prop(props, "water_storage_tank", "WaterTank", Vector3(-30.45, 0, -14.6), 0.0)
	var gen := _prop(props, "portable_generator", "WaterPumpGenerator", Vector3(-30.5, 0, -12.2), 90.0)
	# Field radio against the command post's east wall, facing into the room
	# (the back wall has loot on the floor)
	var radio := _prop(props, "field_radio", "FieldRadio", Vector3(-7.6, 0, -15.6), 90.0)
	# Toolbox on the warehouse floor beside the workbench
	_prop(props, "salvage_toolbox", "SalvageToolbox", Vector3(-19.2, 0, 0.62), 0.0)
	await physics_frame
	await physics_frame
	for p in props.get_children():
		_check_clear(p as StaticBody3D)
	if _failed:
		push_error("A prop overlaps existing geometry or loot: nothing saved.")
		quit(1)
		return

	# ---------------------------------------------------------------- signs
	_quad(signs, "WaterPoint", "water_purification", Vector3(-28.0, 2.55, -14.6), Vector3.LEFT, 2.2, false)
	# Building fronts are solid from 2.25 m to the roofline: signs go up there,
	# over the right-hand window, clear of the door awning
	_quad(signs, "RadioRelay", "radio_signal", Vector3(-9.6, 2.65, -8.0), Vector3.FORWARD, 1.6, false)
	# The gatehouse side facing the road is 1.75 m wide (z 26.0 to 27.75)
	_quad(signs, "Checkpoint17", "checkpoint_17", Vector3(2.0, 1.75, 26.9), Vector3.RIGHT, 1.6, false)
	_quad(signs, "MedicalTriage", "medical_triage", Vector3(14.4, 2.65, -8.0), Vector3.FORWARD, 1.6, false)
	_quad(signs, "UnstableGround", "danger_mines", Vector3(-22.4, 1.05, -0.5), Vector3.FORWARD, 1.2, false)

	# ---------------------------------------------------------------- overlays
	_quad(overlays, "GateBulletHoles", "bullet_holes", Vector3(-10.0, 1.5, 34.0), Vector3.FORWARD, 2.4, true)
	# Rust running down the light east wall from its metal caps (motor pool):
	# fine lines, so it goes on light concrete where it shows.
	_quad(overlays, "MotorPoolRust", "rust_streaks", Vector3(27.0, 2.0, 12.0), Vector3.RIGHT, 2.4, true)
	# soot_marks (max 14% opacity) and scratches (0.4% of the image visible)
	# were tried here and couldn't be seen even from 1.5 m: imported only.

	# ---------------------------------------------------------------- sounds
	var hum := AudioStreamPlayer3D.new()
	hum.name = "WaterPumpHum"
	hum.stream = load(PACK + "audio/power_generator_loop.wav")
	hum.unit_size = 2.5
	hum.max_distance = 25.0
	hum.volume_db = -6.0
	hum.autoplay = true
	hum.bus = &"SFX"
	_add(sounds, hum, gen.global_position + Vector3(0, 0.6, 0))
	var chatter := RandomSoundEmitter.new()
	chatter.name = "RadioChatter"
	chatter.stream = load(PACK + "audio/radio_chatter_static.wav")
	chatter.min_interval = 6.0
	chatter.max_interval = 16.0
	chatter.pitch_variation = 0.05
	chatter.unit_size = 1.5
	chatter.max_distance = 16.0
	chatter.volume_db = -6.0
	chatter.bus = &"SFX"
	_add(sounds, chatter, radio.global_position + Vector3(0, 0.8, 0))
	var rattle := RandomSoundEmitter.new()
	rattle.name = "GateRattle"
	rattle.stream = load(PACK + "audio/metal_gate_rattle.wav")
	rattle.min_interval = 14.0
	rattle.max_interval = 38.0
	rattle.pitch_variation = 0.1
	rattle.unit_size = 3.0
	rattle.max_distance = 32.0
	rattle.volume_db = -6.0
	rattle.bus = &"SFX"
	_add(sounds, rattle, Vector3(4.2, 1.2, 24.5))
	var industry := AudioStreamPlayer3D.new()
	industry.name = "DistantIndustry"
	industry.stream = load(PACK + "audio/distant_industry.wav")
	industry.unit_size = 25.0
	industry.max_distance = 220.0
	industry.volume_db = -4.0
	industry.autoplay = true
	industry.bus = &"Ambience"
	_add(sounds, industry, Vector3(12.0, 6.0, -95.0))  # far beyond the north wall

	# ---------------------------------------------------------------- navmesh
	var nav := _level.get_node("Navigation") as NavigationRegion3D
	nav.bake_navigation_mesh(false)
	assert(ResourceSaver.save(nav.navigation_mesh, NAVMESH) == OK)

	root.remove_child(_level)
	(_level.get_node("RaiderSpawner") as EnemySpawner).enabled = true
	# The fire barrels' FlickerLight changes light_energy every frame while the
	# level runs; put the saved values back so they don't show up as changes.
	for barrel in ["Props/BurningBarrelYard", "Props/BurningBarrelMotorPool"]:
		var light := _level.get_node_or_null(barrel + "/FireLight") as Light3D
		var original := (load(LEVEL) as PackedScene).instantiate()
		var saved := original.get_node_or_null(barrel + "/FireLight") as Light3D
		if light != null and saved != null:
			light.light_energy = saved.light_energy
		original.free()
	var ps := PackedScene.new()
	assert(ps.pack(_level) == OK)
	assert(ResourceSaver.save(ps, LEVEL) == OK)
	_level.free()
	print("INTEGRATE PACK2 OK")
	quit()


func _node(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	n.owner = _level
	return n


func _add(parent: Node, n: Node3D, at: Vector3) -> void:
	parent.add_child(n)
	n.owner = _level
	n.global_position = at


func _prop(parent: Node, scene: String, name: String, at: Vector3, yaw: float) -> Node3D:
	var p := (load(PACK + "scenes/%s.tscn" % scene) as PackedScene).instantiate() as Node3D
	p.name = name
	parent.add_child(p)
	p.owner = _level
	p.global_position = at
	p.rotation.y = deg_to_rad(yaw)
	return p


## Fails the build if a prop's collider overlaps anything solid or any
## interactable (containers, benches, pickups).
func _check_clear(body: StaticBody3D) -> void:
	var cs := body.get_node("Collider") as CollisionShape3D
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
	shape.size -= Vector3(0.04, 0.04, 0.04)
	q.shape = shape
	q.transform = cs.global_transform.translated(Vector3(0, 0.03, 0))  # just off the floor
	q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.INTERACTABLES
	q.collide_with_areas = true
	q.exclude = [body.get_rid()]
	var hits := _space.intersect_shape(q, 8).filter(func(h: Dictionary) -> bool: return (h["collider"] as Node).name != "Terrain")
	var names := hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))
	if not hits.is_empty():
		push_error("%s overlaps %s" % [body.name, names])
		_failed = true
		return
	print("  prop %s clear at %s" % [body.name, body.global_position.snappedf(0.01)])


func _material(decal: String, overlay: bool) -> Material:
	var path := "res://assets/materials/signs/pack2_%s.tres" % decal
	if ResourceLoader.exists(path):
		return load(path)
	var m := StandardMaterial3D.new()
	m.resource_name = ("Overlay " if overlay else "Sign ") + decal
	m.albedo_texture = load(PACK + "decals/%s.png" % decal)
	if overlay:
		# Soft, partly transparent stains: blend, don't cut out
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ResourceSaver.save(m, path)
	return load(path)


## Casts a ray at a wall and puts a quad just in front of it. Signs are 2:1,
## overlays square; overlays sit a little closer so a sign always wins.
func _quad(parent: Node3D, name: String, decal: String, from: Vector3, dir: Vector3, width: float, overlay: bool) -> void:
	var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 30.0, PhysicsLayers.WORLD_SOLID))
	assert(not hit.is_empty(), "%s: no wall" % name)
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	var mi := MeshInstance3D.new()
	mi.name = name
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width if overlay else width / 2.0)
	mi.mesh = quad
	mi.material_override = _material(decal, overlay)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = _level
	var gap := 0.004 if overlay else 0.006
	mi.global_transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), (hit["position"] as Vector3) + normal * gap)
	print("  %s %s on %s at %s" % ["overlay" if overlay else "sign", name, (hit["collider"] as Node).name, mi.global_position.snappedf(0.01)])
