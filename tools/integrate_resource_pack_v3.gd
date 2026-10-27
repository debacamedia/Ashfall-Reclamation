extends SceneTree
## Resource Pack 3.0 integration (kept for review and re-runs). Run headless
## from the project root:
##   godot --headless --path . -s res://tools/integrate_resource_pack_v3.gd
##
## Creates, all under res://assets/ashfall_pack_v3/ (the pack's own files are
## never changed):
##   sets/          AudioStreamRandomizer sets from the pack's numbered WAVs
##   materials/     world-triplanar PBR materials from the texture sets, plus
##                  sign and decal materials
##   environments/  copies of each level's Environment with the pack's sky
## and, for each level, a dressing scene levels/<level>/pack3_dressing.tscn
## (signs, graffiti, decals, ambient sound) placed by raycasting into a
## loaded copy of the level. The level itself is NOT re-saved here: the level
## files only gain one instance line and a few resource paths, applied by
## tools/apply_resource_pack_v3.py.

const PACK := "res://assets/ashfall_pack_v3/"
const SETS := PACK + "sets/"
const MATS := PACK + "materials/"
const ENVS := PACK + "environments/"

var _level: Node3D
var _dress: Node3D
var _space: PhysicsDirectSpaceState3D
var _failed := false
var _made := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for d in [SETS, MATS, ENVS]:
		DirAccess.make_dir_recursive_absolute(d)
	_sets()
	_materials()
	_environments()
	await _dress_level("res://levels/haldens_crossing/haldens_crossing.tscn", _haldens)
	await _dress_level("res://levels/outpost_17/outpost_17.tscn", _outpost)
	if _failed:
		push_error("Pack 3 integration failed (see errors above)")
		quit(1)
		return
	print("INTEGRATE PACK3 OK")
	quit()


# ---------------------------------------------------------------- sound sets

## name → [file prefix, count, pitch variation, volume variation dB]
const SET_SPECS := {
	"impact_concrete": ["impact_concrete_", 3, 1.1, 1.0],
	"impact_dirt": ["impact_dirt_", 3, 1.1, 1.0],
	"impact_flesh": ["impact_flesh_", 3, 1.08, 1.0],
	"impact_metal": ["impact_metal_", 3, 1.1, 1.0],
	"ladder_step": ["ladder_step_", 4, 1.06, 1.0],
	"land": ["land_jump_", 3, 1.05, 1.0],
	"machete_swing": ["machete_swing_", 3, 1.08, 1.0],
	"machete_hit": ["machete_hit_", 3, 1.08, 1.0],
	"weapon_draw": ["weapon_draw_", 3, 1.05, 1.0],
	"aim_in": ["aim_in_", 3, 1.04, 1.0],
	"dry_fire": ["dry_fire_click_", 3, 1.05, 1.0],
	"pickup_ammo": ["pickup_ammo_", 3, 1.05, 1.0],
	"pickup_metal": ["pickup_metal_", 3, 1.05, 1.0],
	"pickup_soft": ["pickup_soft_", 3, 1.05, 1.0],
	"pickup_weapon": ["pickup_weapon_", 3, 1.04, 1.0],
	"rummage": ["rummage_", 3, 1.05, 1.0],
	"salvage_metal": ["salvage_metal_", 3, 1.08, 1.0],
	"salvage_wood": ["salvage_wood_break_", 3, 1.08, 1.0],
	"craft_saw": ["craft_saw_", 3, 1.06, 1.0],
	"craft_hammer": ["craft_hammer_", 3, 1.08, 1.0],
	"craft_file": ["craft_file_", 3, 1.06, 1.0],
	"shell_insert": ["shotgun_shell_insert_", 3, 1.05, 1.0],
}


func _sets() -> void:
	for set_name in SET_SPECS:
		var spec: Array = SET_SPECS[set_name]
		var r := AudioStreamRandomizer.new()
		r.random_pitch = spec[2]
		r.random_volume_offset_db = spec[3]
		r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		for i in int(spec[1]):
			r.add_stream(i, load(PACK + "audio/%s%d.wav" % [spec[0], i + 1]))
		_save(r, SETS + set_name + ".tres")


# ---------------------------------------------------------------- materials

## texture set → [tile size m, roughness scale, normal strength, (tint)]
## Brick and asphalt are tinted down to the brightness of the materials they
## replace in Halden's Crossing (the pack's are ~2.5× and ~1.4× brighter).
const MAT_SPECS := {
	"brick_weathered": [2.0, 1.0, 1.0, 0.55],
	"asphalt_cracked": [3.0, 1.0, 0.8, 0.72],
	"canvas_tent": [2.0, 1.0, 0.8],
	"wood_charred": [2.0, 1.0, 1.0],
	"desert_sand": [3.0, 1.0, 0.6],
	"dirt_road": [3.0, 1.0, 0.7],
	"roofing_tarpaper": [2.0, 1.0, 0.8],
	"container_paint_red": [2.0, 1.0, 0.6],
	"container_paint_blue": [2.0, 1.0, 0.6],
	"container_paint_olive": [2.0, 1.0, 0.6],
	# Imported for completeness; not applied (see INTEGRATION.md)
	"plaster_peeling": [2.0, 1.0, 1.0],
	"floor_linoleum": [2.0, 1.0, 0.6],
	"corrugated_rusty": [2.0, 1.0, 1.0],
}


func _materials() -> void:
	for tex in MAT_SPECS:
		var spec: Array = MAT_SPECS[tex]
		var m := StandardMaterial3D.new()
		m.resource_name = "AF3_" + tex
		m.albedo_texture = load(PACK + "textures/%s/albedo.png" % tex)
		if spec.size() > 3:
			var t: float = spec[3]
			m.albedo_color = Color(t, t, t)
		m.roughness = spec[1]
		m.roughness_texture = load(PACK + "textures/%s/roughness.png" % tex)
		m.normal_enabled = true
		m.normal_scale = spec[2]
		m.normal_texture = load(PACK + "textures/%s/normal.png" % tex)
		var s := 1.0 / float(spec[0])
		m.uv1_scale = Vector3(s, s, s)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_save(m, MATS + tex + ".tres")


## A sign: just the painted panel (the images have a grey board round it),
## cut out where transparent.
func _sign_material(file: String, region: Rect2) -> StandardMaterial3D:
	var path := MATS + "sign_" + file.get_file().get_basename() + ".tres"
	var m := StandardMaterial3D.new()
	m.resource_name = "AF3 sign " + file.get_file().get_basename()
	m.albedo_texture = load(PACK + file)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.85
	m.uv1_scale = Vector3(region.size.x, region.size.y, 1.0)
	m.uv1_offset = Vector3(region.position.x, region.position.y, 0.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_save(m, path)
	return load(path)


## Spray paint: soft edges, blended.
func _graffiti_material(file: String) -> StandardMaterial3D:
	var path := MATS + "graffiti_" + file.get_file().get_basename() + ".tres"
	var m := StandardMaterial3D.new()
	m.resource_name = "AF3 graffiti " + file.get_file().get_basename()
	m.albedo_texture = load(PACK + file)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_save(m, path)
	return load(path)


# ---------------------------------------------------------------- skies

func _environments() -> void:
	var sky_tex := load(PACK + "derived/sky_dusty_afternoon_nosun.png") as Texture2D
	for spec in [["res://levels/outpost_17/outpost_17_environment.tres", "outpost_17_dusty.tres"],
			["res://levels/haldens_crossing/haldens_crossing_environment.tres", "haldens_crossing_dusty.tres"]]:
		var env := (load(spec[0]) as Environment).duplicate(true) as Environment
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = sky_tex
		pano.filter = true
		pano.energy_multiplier = 1.0
		var sky := Sky.new()
		sky.sky_material = pano
		env.sky = sky
		env.resource_name = "Pack 3 sky: " + spec[1]
		_save(env, ENVS + spec[1])


# ---------------------------------------------------------------- dressing

func _dress_level(level_path: String, fill: Callable) -> void:
	_level = (load(level_path) as PackedScene).instantiate() as Node3D
	for sp in _level.get_children():
		if sp is EnemySpawner:
			(sp as EnemySpawner).enabled = false
	var old := _level.get_node_or_null("Pack3Dressing")
	if old != null:
		old.free()
	root.add_child(_level)
	for i in 3:
		await physics_frame
	_space = _level.get_world_3d().direct_space_state
	_dress = Node3D.new()
	_dress.name = "Pack3Dressing"
	root.add_child(_dress)  # at the origin, like the level: global = level space
	await fill.call()
	root.remove_child(_dress)
	var out := level_path.get_base_dir() + "/pack3_dressing.tscn"
	for c in _dress.get_children():
		_own(c)
	var ps := PackedScene.new()
	assert(ps.pack(_dress) == OK)
	assert(ResourceSaver.save(ps, out) == OK)
	print("  saved ", out, " (", _count(_dress), " nodes)")
	_dress.free()
	root.remove_child(_level)
	_level.free()


func _own(n: Node) -> void:
	n.owner = _dress
	for c in n.get_children():
		_own(c)


func _count(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count(c)
	return k


func _group(name: String) -> Node3D:
	var g := _dress.get_node_or_null(name) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = name
		_dress.add_child(g)
	return g


## The panel inside each sign image (fractions of the image).
const BOARD := Rect2(0.045, 0.145, 0.911, 0.713)
const WOOD_BOARD := Rect2(0.078, 0.195, 0.845, 0.6)
const WHOLE := Rect2(0, 0, 1, 1)


## Finds a spot on a wall for a width × height panel: casts from `from`
## along `dir` (the wall must be within `reach`), then keeps the panel where
## aimed if it lies on solid wall all over, else tries it a little smaller,
## then nudged up/down or along the wall (doorways, windows, broken tops).
## Returns {"centre", "normal", "basis", "scale", "wall"} or {} (and fails
## the run).
func _wall_spot(name: String, from: Vector3, dir: Vector3, width: float, height: float, reach := 12.0) -> Dictionary:
	var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * reach, PhysicsLayers.WORLD_SOLID))
	if hit.is_empty():
		push_error("%s: no wall within %.0f m of %s" % [name, reach, from])
		_failed = true
		return {}
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	var basis := Basis.looking_at(-normal, Vector3.UP)
	var aimed: Vector3 = hit["position"]
	for dx: float in [0.0, 0.4, -0.4, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
		for scale: float in [1.0, 0.9, 0.8, 0.7]:
			for dy: float in [0.0, 0.08, -0.08, 0.16, -0.16, 0.3, -0.3]:
				var c := aimed + basis.x * dx + Vector3.UP * dy
				if _fits(c, basis, normal, width * scale, height * scale, hit["collider"]):
					if scale != 1.0 or dx != 0.0 or dy != 0.0:
						print("    (%s: %.1f m along, %.2f m up, size ×%.2f to fit)" % [name, dx, dy, scale])
					return {"centre": c, "normal": normal, "basis": basis, "scale": scale, "wall": hit["collider"]}
	push_error("%s: doesn't fit on %s near %s" % [name, (hit["collider"] as Node).name, aimed])
	_failed = true
	return {}


## Mounts a sign (or spray-painted graffiti) on a wall: see _wall_spot.
func _sign(name: String, file: String, from: Vector3, dir: Vector3, width: float, region := BOARD, graffiti := false) -> void:
	var height := width * 0.5 * region.size.y / region.size.x  # images are 1024 × 512
	var spot := _wall_spot(name, from, dir, width, height)
	if spot.is_empty():
		return
	var scale: float = spot["scale"]
	var mi := MeshInstance3D.new()
	mi.name = name
	var quad := QuadMesh.new()
	quad.size = Vector2(width * scale, height * scale)
	mi.mesh = quad
	mi.material_override = _graffiti_material(file) if graffiti else _sign_material(file, region)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_group("Signs" if not graffiti else "Graffiti").add_child(mi)
	mi.global_transform = Transform3D(spot["basis"], (spot["centre"] as Vector3) + (spot["normal"] as Vector3) * (0.004 if graffiti else 0.008))
	print("  %s %s on %s at %s" % ["graffiti" if graffiti else "sign", name, (spot["wall"] as Node).name, mi.global_position.snappedf(0.01)])


## True if a width × height panel centred at `c` lies on `wall` all over:
## its corners and edge midpoints, with nothing in front of it.
func _fits(c: Vector3, basis: Basis, normal: Vector3, width: float, height: float, wall: Object) -> bool:
	for k: Vector2 in [Vector2(-0.48, -0.48), Vector2(0.48, -0.48), Vector2(-0.48, 0.48), Vector2(0.48, 0.48),
			Vector2(0, -0.48), Vector2(0, 0.48), Vector2(-0.48, 0), Vector2(0.48, 0), Vector2.ZERO]:
		var p := c + basis.x * k.x * width + Vector3.UP * k.y * height + normal * 0.3
		var h := _space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - normal * 0.6, PhysicsLayers.WORLD_SOLID))
		if h.is_empty() or h["collider"] != wall or absf((h["position"] as Vector3).distance_to(p) - 0.3) > 0.03:
			return false
	return true


## A decal: a flat, alpha-blended quad lying on the ground (default) or
## mounted on a wall (`wall` = the direction from `at` into the wall). Quads
## rather than Decal nodes, so they show with every renderer (Decal nodes
## don't draw in the Compatibility renderer).
func _decal(name: String, file: String, at: Vector3, size: float, yaw := 0.0, wall := Vector3.ZERO, alpha := 1.0, reach := 8.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.material_override = _decal_material(file, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_group("Decals").add_child(mi)
	if wall == Vector3.ZERO:
		# From just above the ground: starting inside a barrel or under a truck
		# skips it, so the decal lands on the floor beneath
		var gy := _space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 3.0, PhysicsLayers.WORLD_SOLID))
		if gy.is_empty():
			push_error("%s: no ground at %s" % [name, at])
			_failed = true
			return
		# Lie flat (the quad faces +Z: tip it to face up), then turn
		var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, -PI / 2.0)
		# 4 cm up: streets and yards are thin slabs ~2 cm above the ground's
		# collision, and the decal must sit on top of them
		mi.global_transform = Transform3D(basis, (gy["position"] as Vector3) + Vector3.UP * 0.04)
	else:
		var spot := _wall_spot(name, at, wall, size * 0.8, size * 0.8, reach)
		if spot.is_empty():
			return
		mi.global_transform = Transform3D(spot["basis"], (spot["centre"] as Vector3) + (spot["normal"] as Vector3) * 0.005)
	print("  decal %s at %s" % [name, mi.global_position.snappedf(0.01)])


func _decal_material(file: String, alpha: float) -> StandardMaterial3D:
	var path := MATS + "decal_" + file.get_basename() + ("" if alpha >= 1.0 else "_%d" % roundi(alpha * 100)) + ".tres"
	if ResourceLoader.exists(path) and _made.has(path):
		return load(path)
	var m := StandardMaterial3D.new()
	m.resource_name = "AF3 decal " + file.get_basename()
	m.albedo_texture = load(PACK + "decals/" + file)
	m.albedo_color = Color(1, 1, 1, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_save(m, path)
	_made[path] = true
	return load(path)


func _ambience(name: String, stream_path: String, at: Vector3, volume_db: float, unit: float, max_dist: float, bus := &"Ambience") -> void:
	var p := AudioStreamPlayer3D.new()
	p.name = name
	p.stream = load(stream_path)  # looping is set in the WAV's import settings
	assert((p.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, stream_path + " must import as a loop")
	p.volume_db = volume_db
	p.unit_size = unit
	p.max_distance = max_dist
	p.autoplay = true
	p.bus = bus
	_group("Sounds").add_child(p)
	p.global_position = at


# ---------------------------------------------------------------- Halden's Crossing

func _haldens() -> void:
	# Shop signs above the doors (each building's door side faces the street)
	# Doors and windows reach ~2.35 m and walls are 3.3 m: signs go between
	_sign("SignGeneralStore", "signs/sign_general_store.png", Vector3(-3.0, 2.86, -60.0), Vector3.LEFT, 2.15)
	_sign("SignHotel", "signs/sign_hotel.png", Vector3(-3.0, 2.86, -22.0), Vector3.LEFT, 2.15)
	_sign("SignClinic", "signs/sign_clinic.png", Vector3(-40.0, 2.86, -4.0), Vector3.FORWARD, 2.0)
	# The diner and feed store are ruined at the top: lower, smaller signs
	_sign("SignDiner", "signs/sign_diner.png", Vector3(3.0, 2.66, -40.0), Vector3.RIGHT, 1.6)
	_sign("SignBank", "signs/sign_bank.png", Vector3(3.0, 2.86, -21.0), Vector3.RIGHT, 2.15)
	_sign("SignFeedSupply", "signs/sign_feed_supply.png", Vector3(40.0, 2.66, -4.0), Vector3.FORWARD, 1.8)
	_sign("SignGas", "signs/sign_gas.png", Vector3(5.0, 2.86, 27.0), Vector3.RIGHT, 2.0)
	# Raider camp: warnings on the containers either side of the gates
	_sign("SignKeepOutNorth", "signs/sign_keep_out.png", Vector3(31.0, 1.4, 5.0), Vector3.BACK, 2.0, WOOD_BOARD)
	_sign("SignTurnBackNorth", "signs/sign_turn_back.png", Vector3(46.5, 1.4, 5.0), Vector3.BACK, 2.0, WOOD_BOARD)
	_sign("SignKeepOutWest", "signs/sign_keep_out.png", Vector3(19.0, 1.4, 35.0), Vector3.RIGHT, 2.0, WOOD_BOARD)
	_sign("GraffitiSkull", "signs/graffiti_raider_1.png", Vector3(53.3, 1.3, 5.0), Vector3.BACK, 2.2, WHOLE, true)
	_sign("GraffitiCross", "signs/graffiti_raider_2.png", Vector3(19.0, 1.3, 42.0), Vector3.RIGHT, 2.2, WHOLE, true)
	# "RAID →" on the bank's south wall: the arrow points east, at the camp
	_sign("GraffitiRaid", "signs/graffiti_raider_3.png", Vector3(14.0, 2.8, -10.0), Vector3.FORWARD, 1.8, WHOLE, true)

	# Decals
	_decal("OilGarage", "decal_oil_stain_1.png", Vector3(9.5, 0, -58.0), 2.4, 20.0)
	_decal("OilGarageStreet", "decal_oil_stain_2.png", Vector3(6.0, 0, -56.0), 2.0, 70.0)
	_decal("OilPumps", "decal_oil_stain_3.png", Vector3(14.0, 0, 17.5), 2.2, 0.0)
	_decal("TracksWestGate", "decal_tyre_tracks.png", Vector3(21.0, 0, 28.5), 4.0, 90.0)
	_decal("TracksNorthGate", "decal_tyre_tracks.png", Vector3(40.5, 0, 9.0), 4.0, 0.0)
	_decal("ScorchBarrelA", "decal_scorch_1.png", Vector3(44.0, 0, 30.0), 3.0)
	_decal("ScorchBarrelB", "decal_scorch_2.png", Vector3(31.0, 0, 31.5), 3.0, 40.0)
	_decal("ScorchChurch", "decal_scorch_1.png", Vector3(-17.0, 0, 20.0), 4.0, 15.0)
	_decal("BloodCamp", "decal_blood_1.png", Vector3(37.0, 0, 25.0), 1.6, 30.0)
	_decal("BloodClinic", "decal_blood_2.png", Vector3(-41.0, 0, -16.5), 1.4)
	_decal("CracksMain", "decal_cracks.png", Vector3(0.5, 0, -30.0), 3.5, 10.0)
	_decal("CracksCross", "decal_cracks.png", Vector3(22.0, 0, 0.5), 3.5, 80.0)
	_decal("PosterWanted", "decal_poster_1.png", Vector3(-3.0, 1.6, -63.8), 1.1, 0.0, Vector3.LEFT)
	_decal("PosterCitizens", "decal_poster_2.png", Vector3(3.0, 1.6, -37.4), 1.1, 0.0, Vector3.RIGHT)
	_decal("WaterStainHotel", "decal_water_stain.png", Vector3(-3.0, 4.6, -26.0), 2.2, 0.0, Vector3.LEFT, 0.8)

	# Ambience: the empty town, and gunfire far off
	_ambience("TownRuins", PACK + "audio/amb_town_ruins.wav", Vector3(0, 6, -20), 2.0, 40.0, 400.0)
	_ambience("DistantGunfire", PACK + "audio/amb_distant_gunfire.wav", Vector3(-120, 10, 110), 6.0, 80.0, 600.0)
	_ambience("Insects", PACK + "derived/amb_insects_loop.wav", Vector3(-68, 1, -62), -8.0, 6.0, 40.0)


# ---------------------------------------------------------------- Outpost 17

func _pos(path: String) -> Vector3:
	var n := _level.get_node_or_null(path) as Node3D
	assert(n != null, "no " + path)
	return n.global_position


func _outpost() -> void:
	# Motor pool: oil under the trucks, tracks to the gate
	var trucks := _level.get_node("Vehicles").get_children()
	for i in trucks.size():
		var t := trucks[i] as Node3D
		_decal("OilTruck%d" % i, "decal_oil_stain_%d.png" % (i % 3 + 1), t.global_position + t.global_basis.x * 2.0 + t.global_basis.z * 1.5, 2.2, 30.0 * i)
	var gate := _pos("MainGate")
	_decal("TracksGate", "decal_tyre_tracks.png", gate + Vector3(0, 0, -6.0), 4.0, 0.0)
	_decal("TracksYard", "decal_tyre_tracks.png", gate + Vector3(0, 0, -11.0), 4.0, 8.0)
	_decal("ScorchYard", "decal_scorch_1.png", _pos("Props/BurningBarrelYard"), 3.0)
	_decal("ScorchMotorPool", "decal_scorch_2.png", _pos("Props/BurningBarrelMotorPool"), 3.0, 60.0)
	_decal("CracksYard", "decal_cracks.png", Vector3(-4.0, 0, 6.0), 3.0, 25.0)
	# Notices on the command post and the barracks fronts
	_decal("PosterCommandPost", "decal_poster_2.png", Vector3(-11.0, 1.5, -6.0), 1.0, 0.0, Vector3.FORWARD)
	_decal("PosterBarracks", "decal_poster_1.png", Vector3(12.0, 1.5, -6.0), 1.0, 0.0, Vector3.FORWARD, 1.0, 16.0)
	# (The burning barrels' fire loop itself is swapped for the pack's, in the
	# barrel scene: tools/apply_resource_pack_v3_audio.py)


# ---------------------------------------------------------------- helpers

func _save(res: Resource, path: String) -> void:
	assert(ResourceSaver.save(res, path) == OK, "save " + path)
