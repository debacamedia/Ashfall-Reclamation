extends SceneTree
## Resource Pack 1.0 integration into Outpost 17 (kept for review and re-runs).
## Run headless from the project root:
##   godot --headless --path . -s res://tools/integrate_resource_pack_v1.gd
## Re-running is safe (signs and sounds are rebuilt). Only the level scene
## changes: per-instance material overrides (the shared scenes and the
## original materials are untouched), sign quads and sound nodes.

const LEVEL := "res://levels/outpost_17/outpost_17.tscn"
const PACK := "res://assets/ashfall_pack_v1/"
const OLD := "res://assets/materials/"

## [level groups searched, original material, pack material]
const SWAPS := [
	[["Terrain"], "ground_dirt", "dirt_dry"],
	[["Perimeter", "MainGate", "Buildings"], "concrete", "concrete_weathered"],
	[["Perimeter", "MainGate", "Buildings"], "concrete_stained", "concrete_cracked"],
	[["Buildings", "GuardTowers", "MainGate"], "corrugated_metal", "corrugated_metal"],
	[["GuardTowers", "Props", "FiringRange"], "sandbag", "sandbag_canvas"],
	[["GuardTowers"], "wood", "wood_weathered"],
	[["Props"], "wood", "wood_weathered"],
	[["Props"], "concrete", "concrete_weathered"],  # jersey barriers, flag pole base
]
## Surfaces are plain level meshes: node -> pack material
const SURFACES := {"MainRoad": "asphalt_worn", "Yard": "gravel_mixed", "MotorPool": "concrete_cracked"}
## Props whose metal_dark parts become rusted steel
const RUSTY_PROPS := ["fuel_drums.tscn", "burning_barrel.tscn"]

var _level: Node3D
var _changed := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_level = (load(LEVEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	(_level.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	_materials()
	root.add_child(_level)
	await physics_frame
	await physics_frame
	_signs()
	_sounds()
	root.remove_child(_level)
	(_level.get_node("RaiderSpawner") as EnemySpawner).enabled = true
	var ps := PackedScene.new()
	assert(ps.pack(_level) == OK)
	assert(ResourceSaver.save(ps, LEVEL) == OK)
	_level.free()
	for k in _changed:
		print("  ", k, ": ", _changed[k])
	print("INTEGRATE OK")
	quit()


# ---------------------------------------------------------------- materials

func _set_material(mesh: MeshInstance3D, mat: Material, label: String) -> void:
	# Meshes inside instanced scenes need their instances marked editable so
	# the override is stored in the level, not in the shared scene.
	var o := mesh.owner
	while o != null and o != _level:
		_level.set_editable_instance(o, true)
		o = o.owner
	mesh.material_override = mat
	_changed[label] = _changed.get(label, 0) + 1


func _materials() -> void:
	for swap in SWAPS:
		var from: String = OLD + swap[1] + ".tres"
		var to := load(PACK + "materials/" + swap[2] + ".tres") as Material
		for group: String in swap[0]:
			var g := _level.get_node(group)
			for m in g.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if mi.material_override != null and mi.material_override.resource_path == from:
					# Props: only sandbags, barriers, crates (not containers or vehicles)
					if group == "Props" and swap[1] == "concrete" and not _in_scene(mi, ["jersey_barrier.tscn", "flag_pole.tscn"]):
						continue
					_set_material(mi, to, "%s %s → %s" % [group, swap[1], swap[2]])
	var steel := load(PACK + "materials/rusted_steel.tres") as Material
	for m in _level.get_node("Props").find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.material_override != null and mi.material_override.resource_path == OLD + "metal_dark.tres" and _in_scene(mi, RUSTY_PROPS):
			_set_material(mi, steel, "Props drums/barrels metal_dark → rusted_steel")
	for node_name in SURFACES:
		var mi := _level.get_node("Surfaces/" + node_name) as MeshInstance3D
		_set_material(mi, load(PACK + "materials/" + SURFACES[node_name] + ".tres"), "Surfaces " + node_name)


## True if `n` belongs to an instance of one of these scene files.
func _in_scene(n: Node, files: Array) -> bool:
	var o := n.owner
	while o != null and o != _level:
		if o.scene_file_path.get_file() in files:
			return true
		o = o.owner
	return false


# ---------------------------------------------------------------- signs

func _sign_material(decal: String) -> Material:
	var path := "res://assets/materials/signs/sign_%s.tres" % decal
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceLoader.exists(path):
		return load(path)
	var m := StandardMaterial3D.new()
	m.resource_name = "Sign " + decal
	m.albedo_texture = load(PACK + "decals/%s.png" % decal)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ResourceSaver.save(m, path)
	return load(path)


## Casts a ray at a wall and hangs a sign a few millimetres in front of it.
func _sign(parent: Node3D, name: String, decal: String, from: Vector3, dir: Vector3, width: float) -> void:
	var space := _level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 30.0, PhysicsLayers.WORLD_SOLID)
	var hit := space.intersect_ray(q)
	assert(not hit.is_empty(), "sign %s: no wall" % name)
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	var mi := MeshInstance3D.new()
	mi.name = name
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width / 2.0)
	mi.mesh = quad
	mi.material_override = _sign_material(decal)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = _level
	# QuadMesh faces +Z: point +Z along the wall's normal
	mi.global_transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), (hit["position"] as Vector3) + normal * 0.006)
	print("  sign %s on %s at %s" % [name, (hit["collider"] as Node).name, mi.global_position.snappedf(0.01)])


func _signs() -> void:
	if _level.get_node_or_null("Signage") != null:
		_level.get_node("Signage").free()
	var signs := Node3D.new()
	signs.name = "Signage"
	_level.add_child(signs)
	signs.owner = _level
	# Either side of the main gate, facing the road in
	_sign(signs, "GateOutpost17", "outpost_17", Vector3(-6.0, 2.3, 34.0), Vector3(0, 0, -1), 2.2)
	_sign(signs, "GateRestricted", "restricted", Vector3(6.0, 2.3, 34.0), Vector3(0, 0, -1), 2.2)
	# Warehouse (salvage and the workbench), on its yard-facing wall beside the door
	_sign(signs, "WarehouseSalvage", "salvage", Vector3(-6.0, 2.5, 2.6), Vector3(-1, 0, 0), 3.2)
	# Drainage culvert: don't drink the runoff
	_sign(signs, "CulvertWarning", "warning", Vector3(-22.4, 1.0, -14.0), Vector3(0, 0, 1), 1.2)


# ---------------------------------------------------------------- sounds

func _sounds() -> void:
	if _level.get_node_or_null("Soundscape") != null:
		_level.get_node("Soundscape").free()
	var s := Node3D.new()
	s.name = "Soundscape"
	_level.add_child(s)
	s.owner = _level
	var gen := AudioStreamPlayer3D.new()
	gen.name = "GeneratorHum"
	gen.stream = load("res://assets/audio/loops/generator_idle_loop.wav")
	gen.position = Vector3(28.4, 0.8, 16.0)  # behind the motor pool fuel drums
	gen.unit_size = 3.0
	gen.max_distance = 35.0
	gen.volume_db = -6.0
	gen.autoplay = true
	gen.bus = &"SFX"
	s.add_child(gen)
	gen.owner = _level
	var radio := AudioStreamPlayer3D.new()
	radio.name = "RadioStatic"
	radio.stream = load("res://assets/audio/loops/radio_static_loop.wav")
	radio.position = Vector3(-12.0, 1.2, -16.0)  # inside the command post
	radio.unit_size = 1.5
	radio.max_distance = 14.0
	radio.volume_db = -10.0
	radio.autoplay = true
	radio.bus = &"SFX"
	s.add_child(radio)
	radio.owner = _level
	var clank := RandomSoundEmitter.new()
	clank.name = "MotorPoolClank"
	clank.stream = load(PACK + "audio/metal_clank.wav")
	clank.position = Vector3(21.5, 1.0, 8.0)  # between the trucks
	clank.unit_size = 4.0
	clank.max_distance = 45.0
	clank.volume_db = -8.0
	clank.bus = &"SFX"
	s.add_child(clank)
	clank.owner = _level
	var wind := AudioStreamPlayer.new()
	wind.name = "DistantWind"
	wind.stream = load("res://assets/audio/loops/distant_wind_loop.wav")
	wind.volume_db = -14.0
	wind.autoplay = true
	wind.bus = &"Ambience"
	s.add_child(wind)
	wind.owner = _level
