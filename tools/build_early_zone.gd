extends SceneTree
## Builds the early zone (Increment 15): one seamless level laid out from the
## Regional Buildout Map, with Outpost 17 on the west coast and Halden's
## Crossing to its north-east.
##
## Run from the project root (re-running rebuilds everything it makes):
##
##     godot --headless --path . -s res://tools/build_early_zone.gd
##
## Writes, under levels/early_zone/:
##   early_zone.tscn            the level (main scene)
##   early_zone_environment.tres
##   terrain.scn                ground (collision + 10 m mesh chunks), sea
##   roads.scn                  roads, the railway, signposts (visual only)
##   rocks.scn                  hills and outcrops (solid), scattered stones
##   navigation.scn             the navmesh in 100 m tiles
## (the big generated parts are binary .scn: smaller and quicker to load)
##   materials/*.tres
## The places are site scenes, placed as they are:
##   Outpost 17         levels/outpost_17/outpost_17.tscn at the origin
##   Halden's Crossing  levels/haldens_crossing/haldens_crossing.tscn
##   the other five     levels/<place>/<place>.tscn, built by tools/build_sites.gd
##
## SCALE: 1 px of the concept map = 1.1 m, with Outpost 17 at the origin.
## World x = east, -z = north.

const OUT := "res://levels/early_zone/"
const PX := 1.1  # metres per map pixel

const OUTPOST_SCENE := "res://levels/outpost_17/outpost_17.tscn"
const HALDENS_SCENE := "res://levels/haldens_crossing/haldens_crossing.tscn"
const HALDENS_AT := Vector3(450, 0, -275)

## Places: node name -> [display name, centre (x, z), radius, compass name]
const PLACES := {
	"Outpost17": ["Outpost 17", Vector2(0, 5), 85.0, "Outpost 17"],
	"HaldensCrossing": ["Halden's Crossing", Vector2(450, -275), 115.0, "Halden's"],
	"SaintMercyClinic": ["Saint Mercy Clinic", Vector2(245, -205), 50.0, "Saint Mercy"],
	"AshCreekFarms": ["Ash Creek Farms", Vector2(340, -90), 65.0, "Ash Creek"],
	"SmugglersGulch": ["Smuggler's Gulch", Vector2(150, -395), 60.0, "Smuggler's Gulch"],
	"BlackRidgeMine": ["Black Ridge Mine", Vector2(262, -552), 55.0, "Black Ridge"],
	"NorthwatchOutpost": ["Northwatch Outpost", Vector2(400, -680), 45.0, "Northwatch"],
}

## The playable area, round the edge (x, z). Edges 0–2 are the coast.
const EDGE := [
	Vector2(-135, 135), Vector2(-160, 40), Vector2(-150, -80), Vector2(-120, -185),
	Vector2(-60, -320), Vector2(40, -470), Vector2(120, -640), Vector2(250, -770),
	Vector2(420, -800), Vector2(540, -745), Vector2(610, -580), Vector2(650, -400),
	Vector2(660, -230), Vector2(610, -70), Vector2(480, 50), Vector2(300, 115),
	Vector2(120, 150), Vector2(-40, 160),
]
const SEA_EDGES := [0, 1, 2]

## Roads: [name, kind, width, points (x, z)]. Kinds: main (asphalt),
## gravel (dirt road), trail (narrow dirt road).
const ROADS := [
	["MainRoad", "main", 7.0, [Vector2(0, 69), Vector2(4, 88), Vector2(30, 103), Vector2(95, 100),
		Vector2(175, 66), Vector2(255, 16), Vector2(330, -22), Vector2(392, -62),
		Vector2(432, -112), Vector2(448, -150), Vector2(450, -176)]],  # runs on under Main Street
	["RoadToSaintMercy", "gravel", 5.5, [Vector2(361, -275), Vector2(330, -268), Vector2(298, -246),
		Vector2(272, -222)]],
	["TrailToGulch", "trail", 4.0, [Vector2(238, -224), Vector2(214, -262), Vector2(190, -305),
		Vector2(171, -348), Vector2(160, -372)]],
	["RoadNorth", "gravel", 5.5, [Vector2(450, -376), Vector2(447, -420), Vector2(438, -470),
		Vector2(425, -545), Vector2(410, -615), Vector2(402, -652)]],
	["RoadToBlackRidge", "gravel", 5.0, [Vector2(438, -470), Vector2(395, -492), Vector2(345, -520),
		Vector2(298, -540)]],
	["FarmLane", "trail", 4.0, [Vector2(318, -12), Vector2(326, -40), Vector2(334, -62)]],
	["RoadEast", "gravel", 6.0, [Vector2(539, -275), Vector2(580, -279), Vector2(640, -287),
		Vector2(700, -300), Vector2(760, -318)]],
]

## The railway: from a buffer stop east of Outpost 17, past Halden's, east
## out of the zone (toward the Iron Vein Rail Yard).
const RAIL := [Vector2(105, 58), Vector2(160, 40), Vector2(240, 0), Vector2(320, -52),
	Vector2(400, -118), Vector2(470, -160), Vector2(540, -195), Vector2(620, -228),
	Vector2(700, -258), Vector2(800, -290)]

## Signposts: [position (x, z), [destinations…]]
const SIGNPOSTS := [
	[Vector2(8, 80), ["HaldensCrossing", "AshCreekFarms"]],
	[Vector2(441, -162), ["Outpost17", "AshCreekFarms"]],
	[Vector2(366, -265), ["SaintMercyClinic", "SmugglersGulch"]],
	[Vector2(458, -385), ["NorthwatchOutpost", "BlackRidgeMine"]],
	[Vector2(446, -478), ["NorthwatchOutpost", "BlackRidgeMine", "HaldensCrossing"]],
	[Vector2(310, -6), ["AshCreekFarms", "Outpost17"]],
	[Vector2(231, -229), ["SmugglersGulch", "HaldensCrossing"]],  # at the trail head, clear of the staff house
]

# Materials used across the zone
var M := {}
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _boundary: ZoneBoundary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "materials"))
	_noise.seed = 1717
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 4
	_noise2.seed = 99
	_noise2.frequency = 0.011
	_boundary = ZoneBoundary.new()
	_boundary.polygon = PackedVector2Array(EDGE)
	var kinds := PackedByteArray()
	for i in EDGE.size():
		kinds.append(ZoneBoundary.Kind.SEA if SEA_EDGES.has(i) else ZoneBoundary.Kind.STORM)
	_boundary.edge_kinds = kinds
	_materials()
	_save(_terrain(), "terrain.scn")
	_save(_roads(), "roads.scn")
	_save(_rocks(), "rocks.scn")
	ResourceSaver.save(_environment(), OUT + "early_zone_environment.tres")
	await _zone()
	_boundary.free()
	print("early zone built")
	quit()


# ================================================================ helpers

func _save(root: Node, file: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	assert(err == OK, "pack " + file)
	err = ResourceSaver.save(packed, OUT + file)
	assert(err == OK, "save " + file)
	print("  wrote ", file)
	root.free()


## Sets the owner of everything made here (not the insides of instanced scenes).
func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		if c.scene_file_path == "":
			_own(c, root)


func _mat(path: String) -> Material:
	return load(path) as Material


func _materials() -> void:
	M["asphalt"] = _mat("res://assets/ashfall_pack_v3/materials/asphalt_cracked.tres")
	# Pack 3's dirt road, darkened to sit with the ground (untinted it glows)
	var road_tex := "res://assets/ashfall_pack_v3/textures/dirt_road/"
	M["dirt_road"] = _save_mat(_tex_mat(road_tex, Color(0.52, 0.47, 0.41), 0.333), "dirt_road_dark")
	M["gravel"] = _mat("res://assets/materials/gravel.tres")
	M["concrete"] = _mat("res://assets/materials/concrete.tres")
	M["concrete_stained"] = _mat("res://assets/materials/concrete_stained.tres")
	M["plaster"] = _mat("res://assets/materials/plaster.tres")
	M["corrugated"] = _mat("res://assets/materials/corrugated_metal.tres")
	M["wood"] = _mat("res://assets/materials/wood.tres")
	M["rust"] = _mat("res://assets/materials/rust.tres")
	M["metal_dark"] = _mat("res://assets/materials/metal_dark.tres")
	M["sandbag"] = _mat("res://assets/materials/sandbag.tres")
	M["olive"] = _mat("res://assets/materials/olive_drab.tres")
	M["hazard"] = _mat("res://assets/materials/hazard_yellow.tres")
	M["brick"] = _mat("res://assets/ashfall_pack_v3/materials/brick_weathered.tres")
	M["roofing"] = _mat("res://assets/ashfall_pack_v3/materials/roofing_tarpaper.tres")
	M["canvas"] = _mat("res://assets/ashfall_pack_v3/materials/canvas_tent.tres")
	M["container_red"] = _mat("res://assets/ashfall_pack_v3/materials/container_paint_red.tres")
	M["container_blue"] = _mat("res://assets/ashfall_pack_v3/materials/container_paint_blue.tres")
	M["container_olive"] = _mat("res://assets/ashfall_pack_v3/materials/container_paint_olive.tres")
	var concrete_tex := "res://assets/ashfall_pack_v1/textures/concrete_weathered/"
	M["rock_dark"] = _save_mat(_tex_mat(concrete_tex, Color(0.36, 0.34, 0.34), 0.12), "rock_dark")
	M["rock_red"] = _save_mat(_tex_mat(concrete_tex, Color(0.72, 0.42, 0.3), 0.12), "rock_red")
	M["rock_tan"] = _save_mat(_tex_mat(concrete_tex, Color(0.66, 0.57, 0.45), 0.12), "rock_tan")
	var dirt_tex := "res://assets/ashfall_pack_v1/textures/dirt_dry/"
	M["field_soil"] = _save_mat(_tex_mat(dirt_tex, Color(0.46, 0.39, 0.31), 0.25), "field_soil")
	M["barn_red"] = _save_mat(_tex_mat("res://assets/ashfall_pack_v1/textures/wood_weathered/", Color(0.62, 0.24, 0.18), 0.5), "barn_red")
	M["paint_white"] = _save_mat(_tex_mat(concrete_tex, Color(0.86, 0.85, 0.8), 0.3), "paint_white")
	var crop := StandardMaterial3D.new()
	crop.albedo_color = Color(0.27, 0.23, 0.13)
	crop.roughness = 0.95
	M["crop"] = _save_mat(crop, "crop_dry")
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.14, 0.18, 0.08)
	green.roughness = 0.95
	M["crop_green"] = _save_mat(green, "crop_green")
	var red_cross := StandardMaterial3D.new()
	red_cross.albedo_color = Color(0.7, 0.1, 0.08)
	red_cross.roughness = 0.8
	M["red_cross"] = _save_mat(red_cross, "red_cross")
	var scrub := StandardMaterial3D.new()
	scrub.albedo_color = Color(0.36, 0.3, 0.2)
	scrub.roughness = 1.0
	M["scrub"] = _save_mat(scrub, "scrub")
	var sign := StandardMaterial3D.new()
	sign.albedo_color = Color(0.32, 0.25, 0.17)
	sign.roughness = 0.9
	M["sign_wood"] = _save_mat(sign, "sign_wood")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	dark.roughness = 1.0
	M["opening"] = _save_mat(dark, "opening")
	# Ground and sea
	var ground := ShaderMaterial.new()
	ground.shader = load("res://assets/shaders/zone_terrain.gdshader")
	ground.set_shader_parameter("albedo_tex", load(dirt_tex + "albedo.png"))
	ground.set_shader_parameter("normal_tex", load(dirt_tex + "normal.png"))
	ground.set_shader_parameter("roughness_tex", load(dirt_tex + "roughness.png"))
	var pn := FastNoiseLite.new()
	pn.seed = 5
	pn.frequency = 0.012
	pn.fractal_octaves = 3
	var patches := NoiseTexture2D.new()
	patches.noise = pn
	patches.seamless = true
	patches.width = 256
	patches.height = 256
	ground.set_shader_parameter("patches", patches)
	M["ground"] = _save_mat(ground, "zone_ground")
	var sea := ShaderMaterial.new()
	sea.shader = load("res://assets/shaders/sea.gdshader")
	var wn := FastNoiseLite.new()
	wn.seed = 8
	wn.frequency = 0.03
	wn.fractal_octaves = 3
	var waves := NoiseTexture2D.new()
	waves.noise = wn
	waves.seamless = true
	waves.as_normal_map = true
	waves.bump_strength = 6.0
	waves.width = 256
	waves.height = 256
	sea.set_shader_parameter("waves", waves)
	M["sea"] = _save_mat(sea, "sea")


func _tex_mat(dir: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "albedo.png")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.png")
	m.roughness_texture = load(dir + "roughness.png")
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _save_mat(m: Material, name: String) -> Material:
	var path := OUT + "materials/" + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	return load(path)


## Many copies of `mesh` merged into one mesh per `cell` metres (one draw
## call each; MultiMesh data isn't kept when this runs headless).
func _merged(name: String, mesh: Mesh, xforms: Array[Transform3D], mat: Material, cell: float, draw_range: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = name
	var groups := {}
	for x in xforms:
		var key := Vector2i(floori(x.origin.x / cell), floori(x.origin.z / cell))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(x)
	for key: Vector2i in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x: Transform3D in groups[key]:
			st.append_from(mesh, 0, x)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d_%d" % [name, key.x, key.y]
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = draw_range
		mi.set_meta("no_draw_distance", true)
		holder.add_child(mi)
	return holder


## A small, very low-poly stone for scattering.
func _pebble() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.4
	sphere.radial_segments = 6
	sphere.rings = 3
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, idx.size(), 3):
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		var n := (c - a).cross(b - a).normalized()
		if n.length() < 0.5:
			continue
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(Vector3(v.x, maxf(v.y, -0.1), v.z))
	return st.commit()


## A solid box (mesh + collision) under `body`.
func _box(body: Node3D, name: String, size: Vector3, pos: Vector3, mat_key: String, yaw := 0.0, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = M[mat_key]
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		cs.name = name + "Col"
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = mi.transform
		body.add_child(cs)
	return mi


func _cylinder(body: Node3D, name: String, radius: float, height: float, pos: Vector3, mat_key: String, solid := true, sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = M[mat_key]
	mi.position = pos
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		cs.name = name + "Col"
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		cs.position = pos
		body.add_child(cs)
	return mi


## A pitched roof (visual; the walls under it are solid).
func _roof(body: Node3D, name: String, size: Vector3, pos: Vector3, mat_key: String, yaw := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = M[mat_key]
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	body.add_child(mi)


func _solid_body(name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.collision_layer = PhysicsLayers.STRUCTURES
	b.collision_mask = 0
	b.add_to_group("navigation_geometry", true)
	return b


## Distance from `p` to the nearest road or the railway (m).
func _road_distance(p: Vector2) -> float:
	var best := INF
	for r in ROADS:
		var pts: Array = r[3]
		for i in pts.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])) - float(r[2]) * 0.5)
	for i in RAIL.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, RAIL[i], RAIL[i + 1])) - 1.8)
	return best


## Distance from `p` to the edge of the nearest place (negative inside).
func _place_distance(p: Vector2) -> float:
	var best := INF
	for k in PLACES:
		var d: float = p.distance_to(PLACES[k][1]) - float(PLACES[k][2])
		best = minf(best, d)
	return best


func _inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _boundary.polygon)


## Flat distance to the nearest sea edge and the nearest storm edge.
func _edge_distances(p: Vector2) -> Vector2:
	var sea := INF
	var land := INF
	for i in EDGE.size():
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, EDGE[i], EDGE[(i + 1) % EDGE.size()]))
		if SEA_EDGES.has(i):
			sea = minf(sea, d)
		else:
			land = minf(land, d)
	return Vector2(sea, land)


# ================================================================ terrain

const T_MIN := Vector2(-900, -1500)
const T_MAX := Vector2(1400, 860)
const T_STEP := 10.0
const CHUNK := 24  # cells per mesh chunk side
## Collision covers the playable area and this far past its edge (m).
const COLLISION_MARGIN := 45.0

## The sea beyond the playable coast (x, z). Its edge is the coastline.
const SEA_AREA := [Vector2(-120, -185), Vector2(-150, -80), Vector2(-160, 40), Vector2(-135, 135),
	Vector2(-100, 250), Vector2(-60, 420), Vector2(-80, 1000), Vector2(-1200, 1000),
	Vector2(-1200, -330), Vector2(-400, -262), Vector2(-200, -232)]
const WATER_LEVEL := -0.35

## Area tints: [centre, radius, colour]
const TINTS := [
	[Vector2(230, -600), 340.0, Color(0.56, 0.54, 0.54)],   # Black Ridge: dark ash
	[Vector2(120, -390), 230.0, Color(1.08, 0.8, 0.68)],    # Smuggler's Gulch: red earth
	[Vector2(10, -240), 160.0, Color(1.05, 0.86, 0.74)],
	[Vector2(450, -275), 175.0, Color(0.82, 0.78, 0.72)],   # Halden's: darker, trodden
	[Vector2(340, -90), 110.0, Color(0.88, 0.86, 0.7)],     # Ash Creek: tilled
]


func _dist_to_outline(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])))
	return best


## Ground height at (x, z): flat inside the zone, sea bed off the coast,
## hills rising past the storm's edge (beyond the backstop).
func _height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if _inside(p):
		return 0.0
	var sea_poly := PackedVector2Array(SEA_AREA)
	var d_coast := _dist_to_outline(p, SEA_AREA)
	if Geometry2D.is_point_in_polygon(p, sea_poly):
		return -minf(smoothstep(0.0, 70.0, d_coast) * 7.0 + d_coast * 0.004, 9.0)
	var d_play := _dist_to_outline(p, EDGE)
	var r := maxf(d_play - 36.0, 0.0)
	var n := _noise.get_noise_2d(x, z)
	var ridge := 1.0 - absf(_noise2.get_noise_2d(x, z))
	var h := smoothstep(0.0, 170.0, r) * (16.0 + 14.0 * n + 12.0 * ridge) + maxf(r - 170.0, 0.0) * 0.05 * (1.2 + n)
	h *= smoothstep(0.0, 50.0, d_coast)  # land meets the sea at sea level
	return clampf(h, 0.0, 90.0)


func _tint(x: float, z: float, h: float) -> Color:
	var p := Vector2(x, z)
	var c := Color(1, 1, 1)
	for t in TINTS:
		var f := 1.0 - smoothstep(float(t[1]) * 0.45, float(t[1]), p.distance_to(t[0]))
		var tc: Color = t[2]
		c = Color(c.r * lerpf(1.0, tc.r, f), c.g * lerpf(1.0, tc.g, f), c.b * lerpf(1.0, tc.b, f))
	# Sand along the shore
	var shore := 1.0 - smoothstep(10.0, 70.0, _dist_to_outline(p, SEA_AREA))
	c = c.lerp(Color(1.12, 1.06, 0.95), shore * 0.8)
	# Hills past the edge: a little darker and greyer the higher they go
	c = c.lerp(c * Color(0.8, 0.78, 0.76), clampf(h / 60.0, 0.0, 1.0))
	return c


func _terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var nx := int((T_MAX.x - T_MIN.x) / T_STEP) + 1
	var nz := int((T_MAX.y - T_MIN.y) / T_STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = _height(T_MIN.x + i * T_STEP, T_MIN.y + j * T_STEP)
	var hat := func(i: int, j: int) -> float:
		return heights[clampi(j, 0, nz - 1) * nx + clampi(i, 0, nx - 1)]
	# Mesh chunks
	var mesh_root := Node3D.new()
	mesh_root.name = "Mesh"
	root.add_child(mesh_root)
	for cj in range(0, nz - 1, CHUNK):
		for ci in range(0, nx - 1, CHUNK):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var w := mini(CHUNK, nx - 1 - ci) + 1
			var d := mini(CHUNK, nz - 1 - cj) + 1
			for j in d:
				for i in w:
					var gi := ci + i
					var gj := cj + j
					var x := T_MIN.x + gi * T_STEP
					var z := T_MIN.y + gj * T_STEP
					var h: float = hat.call(gi, gj)
					var nrm := Vector3(hat.call(gi - 1, gj) - hat.call(gi + 1, gj), 2.0 * T_STEP, hat.call(gi, gj - 1) - hat.call(gi, gj + 1)).normalized()
					st.set_normal(nrm)
					st.set_color(_tint(x, z, h))
					st.add_vertex(Vector3(x, h, z))
			for j in d - 1:
				for i in w - 1:
					var a := j * w + i
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + w)
					st.add_index(a + 1)
					st.add_index(a + w + 1)
					st.add_index(a + w)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci / CHUNK, cj / CHUNK]
			mi.mesh = st.commit()
			mi.material_override = M["ground"]
			mi.set_meta("no_draw_distance", true)
			mesh_root.add_child(mi)
	# Collision: the playable area and a margin past the edge
	var reach := ZoneBoundary.grow(PackedVector2Array(EDGE), COLLISION_MARGIN)
	var faces := PackedVector3Array()
	for j in nz - 1:
		for i in nx - 1:
			var x0 := T_MIN.x + i * T_STEP
			var z0 := T_MIN.y + j * T_STEP
			if not Geometry2D.is_point_in_polygon(Vector2(x0 + T_STEP * 0.5, z0 + T_STEP * 0.5), reach):
				continue
			var a := Vector3(x0, hat.call(i, j), z0)
			var b := Vector3(x0 + T_STEP, hat.call(i + 1, j), z0)
			var c := Vector3(x0, hat.call(i, j + 1), z0 + T_STEP)
			var e := Vector3(x0 + T_STEP, hat.call(i + 1, j + 1), z0 + T_STEP)
			faces.append_array([a, b, c, b, e, c])
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = PhysicsLayers.TERRAIN
	ground.collision_mask = 0
	ground.add_to_group("navigation_geometry", true)
	var cs := CollisionShape3D.new()
	cs.name = "GroundCol"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	ground.add_child(cs)
	root.add_child(ground)
	# The sea
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1500, 1700)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	sea.mesh = pm
	sea.position = Vector3(-650, WATER_LEVEL, 330)
	sea.material_override = M["sea"]
	sea.set_meta("no_draw_distance", true)
	root.add_child(sea)
	print("  terrain: %d x %d points, %d collision triangles" % [nx, nz, faces.size() / 3])
	return root


# ================================================================ roads, rail, signs

## Evenly spaced points along a smoothed polyline (x, z).
func _smooth(points: Array, step := 2.0) -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.bake_interval = step
	for i in points.size():
		var p: Vector2 = points[i]
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var t := (next - prev) * 0.22
		curve.add_point(p, -t if i > 0 else Vector2.ZERO, t if i < points.size() - 1 else Vector2.ZERO)
	return curve.get_baked_points()


func _sides(pts: PackedVector2Array, k: int) -> Vector2:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	var dir := (b - a).normalized()
	return Vector2(-dir.y, dir.x)


## A flat strip along `pts`, `width` wide, `y` above the ground.
func _ribbon(pts: PackedVector2Array, width: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in pts.size():
		var side := _sides(pts, k) * width * 0.5
		var l := pts[k] + side
		var r := pts[k] - side
		st.add_vertex(Vector3(l.x, y, l.y))
		st.add_vertex(Vector3(r.x, y, r.y))
	for k in pts.size() - 1:
		var a := k * 2
		# Clockwise seen from above, so the top is the front face
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 3)
		st.add_index(a + 2)
	var mesh := st.commit()
	return mesh


## A raised strip with sloped sides (rail ballast, rails).
func _profile(pts: PackedVector2Array, bottom: float, top: float, height: float, offset := 0.0, base := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Cross-section, left to right: bottom-left, top-left, top-right, bottom-right
	var section := [Vector2(-bottom * 0.5, base), Vector2(-top * 0.5, base + height), Vector2(top * 0.5, base + height), Vector2(bottom * 0.5, base)]
	for k in pts.size():
		var side := _sides(pts, k)
		for s: Vector2 in section:
			var q := pts[k] + side * (s.x + offset)
			st.add_vertex(Vector3(q.x, s.y, q.y))
	for k in pts.size() - 1:
		for f in 3:
			var a := k * 4 + f
			var b := a + 1
			st.add_index(a)
			st.add_index(a + 4)
			st.add_index(b)
			st.add_index(b)
			st.add_index(a + 4)
			st.add_index(b + 4)
	st.generate_normals()
	return st.commit()


func _roads() -> Node3D:
	var root := Node3D.new()
	root.name = "Roads"
	var mats := {"main": "asphalt", "gravel": "dirt_road", "trail": "dirt_road"}
	for r in ROADS:
		var pts := _smooth(r[3])
		var mi := MeshInstance3D.new()
		mi.name = r[0]
		mi.mesh = _ribbon(pts, r[2], 0.006 if r[1] == "main" else 0.005)
		mi.material_override = M[mats[r[1]]]
		mi.set_meta("no_draw_distance", true)
		mi.visibility_range_end = 700.0
		root.add_child(mi)
		if r[1] == "main":
			var line := MeshInstance3D.new()
			line.name = r[0] + "Line"
			line.mesh = _ribbon(pts, 0.18, 0.009)
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color(0.72, 0.62, 0.32)
			paint.roughness = 0.9
			line.material_override = paint
			line.visibility_range_end = 160.0
			line.set_meta("no_draw_distance", true)
			root.add_child(line)
	# The railway: ballast, sleepers, rails
	var rail := Node3D.new()
	rail.name = "Railway"
	root.add_child(rail)
	var rpts := _smooth(RAIL, 1.0)
	var ballast := MeshInstance3D.new()
	ballast.name = "Ballast"
	ballast.mesh = _profile(rpts, 3.6, 2.6, 0.22)
	ballast.material_override = M["gravel"]
	ballast.set_meta("no_draw_distance", true)
	ballast.visibility_range_end = 700.0
	rail.add_child(ballast)
	for side in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		r.name = "Rail" + ("L" if side < 0 else "R")
		r.mesh = _profile(rpts, 0.14, 0.07, 0.13, side * 0.72, 0.3)
		r.material_override = M["rust"]
		r.set_meta("no_draw_distance", true)
		r.visibility_range_end = 260.0
		rail.add_child(r)
	var sleeper := BoxMesh.new()
	sleeper.size = Vector3(2.5, 0.1, 0.24)
	var xforms: Array[Transform3D] = []
	var acc := 0.0
	for k in range(1, rpts.size()):
		acc += rpts[k].distance_to(rpts[k - 1])
		if acc < 0.8:
			continue
		acc = 0.0
		var side := _sides(rpts, k)
		var basis := Basis(Vector3(side.x, 0, side.y), Vector3.UP, Vector3(-side.y, 0, side.x))
		xforms.append(Transform3D(basis, Vector3(rpts[k].x, 0.26, rpts[k].y)))
	rail.add_child(_merged("Sleepers", sleeper, xforms, M["sign_wood"], 200.0, 180.0))
	# Buffer stop at the Outpost 17 end
	var stop := _solid_body("BufferStop")
	stop.position = Vector3(RAIL[0].x, 0, RAIL[0].y)
	stop.rotation.y = atan2(-(RAIL[1] - RAIL[0]).x, -(RAIL[1] - RAIL[0]).y)
	_box(stop, "Frame", Vector3(2.8, 1.1, 0.5), Vector3(0, 0.75, 0), "hazard")
	rail.add_child(stop)
	# Signposts
	var signs := Node3D.new()
	signs.name = "Signposts"
	root.add_child(signs)
	for s in SIGNPOSTS:
		signs.add_child(_signpost(s[0], s[1]))
	print("  roads: %d, railway %.0f m, %d sleepers" % [ROADS.size(), _length(rpts), xforms.size()])
	return root


func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for k in range(1, pts.size()):
		l += pts[k].distance_to(pts[k - 1])
	return l


## A wooden post with an arm pointing to each destination, labelled both sides.
func _signpost(at: Vector2, destinations: Array) -> Node3D:
	var post := _solid_body("Signpost")
	post.position = Vector3(at.x, 0, at.y)
	_box(post, "Post", Vector3(0.16, 3.0, 0.16), Vector3(0, 1.5, 0), "sign_wood")
	var y := 2.6
	for dest: String in destinations:
		var place: Array = PLACES[dest]
		var to: Vector2 = place[1]
		var dir := (to - at).normalized()
		var arm := Node3D.new()
		arm.name = "To" + dest
		arm.position = Vector3(0, y, 0)
		arm.rotation.y = atan2(dir.y, -dir.x)  # the board runs along local -X, toward `dir`
		post.add_child(arm)
		var board := MeshInstance3D.new()
		board.name = "Board"
		var bm := BoxMesh.new()
		bm.size = Vector3(2.7, 0.3, 0.05)
		board.mesh = bm
		board.material_override = M["sign_wood"]
		board.position = Vector3(-1.45, 0, 0)
		arm.add_child(board)
		var km := at.distance_to(to) / 1000.0
		var text := "%s  %.1f km" % [place[0], km]
		for face in [1.0, -1.0]:
			var l := Label3D.new()
			l.name = "Text" + ("Front" if face > 0 else "Back")
			l.text = text
			l.font_size = 40
			l.pixel_size = 0.0036
			l.outline_size = 0
			l.modulate = Color(0.95, 0.9, 0.78)
			l.position = Vector3(-1.5, 0, 0.03 * face)
			l.rotation.y = 0.0 if face > 0 else PI
			l.double_sided = false
			arm.add_child(l)
		y -= 0.42
	return post


# ================================================================ rocks

## Rock shapes: [radial noise amount, noise frequency, top cut (y), sides]
const ROCK_STYLES := {
	"boulder": [0.32, 1.7, 1.0, 9],
	"hill": [0.22, 1.2, 0.85, 12],
	"mesa": [0.14, 2.2, 0.42, 10],
}

## Clusters: [style, material, centre, radius, count, width min, width max, height / width]
const ROCK_CLUSTERS := [
	["hill", "rock_dark", Vector2(215, -610), 170.0, 18, 26.0, 62.0, Vector2(0.32, 0.55)],
	["boulder", "rock_dark", Vector2(262, -560), 130.0, 22, 4.0, 11.0, Vector2(0.55, 0.85)],
	["hill", "rock_dark", Vector2(80, -520), 80.0, 5, 22.0, 40.0, Vector2(0.3, 0.5)],
	["boulder", "rock_dark", Vector2(340, -705), 70.0, 6, 5.0, 12.0, Vector2(0.5, 0.8)],
	["mesa", "rock_red", Vector2(30, -255), 80.0, 7, 12.0, 26.0, Vector2(0.45, 0.8)],
	["mesa", "rock_red", Vector2(-50, -150), 50.0, 4, 10.0, 20.0, Vector2(0.45, 0.8)],
	["boulder", "rock_red", Vector2(255, -325), 55.0, 5, 6.0, 14.0, Vector2(0.5, 0.8)],
	["mesa", "rock_red", Vector2(540, -470), 70.0, 5, 12.0, 24.0, Vector2(0.45, 0.75)],
	["boulder", "rock_dark", Vector2(70, 125), 55.0, 5, 5.0, 12.0, Vector2(0.5, 0.8)],
	["boulder", "rock_dark", Vector2(-90, 90), 40.0, 4, 4.0, 9.0, Vector2(0.5, 0.8)],
	["boulder", "rock_tan", Vector2(250, -150), 340.0, 45, 2.0, 6.0, Vector2(0.45, 0.8)],
]

var _rock_meshes := {}  # "style:n" -> [ArrayMesh, PackedVector3Array]


## A lumpy, flat-shaded rock of radius ~1 (bottom buried a little).
func _rock_mesh(style: String, variant: int) -> Array:
	var key := "%s:%d" % [style, variant]
	if _rock_meshes.has(key):
		return _rock_meshes[key]
	var spec: Array = ROCK_STYLES[style]
	var amount: float = spec[0]
	var freq: float = spec[1]
	var top: float = spec[2]
	var sides: int = spec[3]
	var n := FastNoiseLite.new()
	n.seed = 400 + variant * 31 + style.length() * 7
	n.frequency = freq
	n.fractal_octaves = 2
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = sides
	sphere.rings = maxi(sides / 2, 5)
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var d := verts[i].normalized() if verts[i].length() > 0.0001 else Vector3.UP
		var r := 1.0 + amount * n.get_noise_3dv(d * 1.5)
		var v := d * r
		v.y = clampf(v.y, -0.3, top)
		out[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := out[idx[t]]
		var b := out[idx[t + 1]]
		var c := out[idx[t + 2]]
		var nrm := (c - a).cross(b - a).normalized()
		if nrm.length() < 0.5:
			continue
		for v in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(v)
	var mesh := st.commit()
	_rock_meshes[key] = [mesh, out]
	return _rock_meshes[key]


func _rocks() -> Node3D:
	var root := Node3D.new()
	root.name = "Rocks"
	_rng.seed = 2024
	var placed: Array[Vector3] = []  # x, z, radius
	var count := 0
	for c in ROCK_CLUSTERS:
		var style: String = c[0]
		var centre: Vector2 = c[2]
		var tries := 0
		var made := 0
		while made < int(c[4]) and tries < int(c[4]) * 40:
			tries += 1
			var ang := _rng.randf() * TAU
			var dist := sqrt(_rng.randf()) * float(c[3])
			var p := centre + Vector2(cos(ang), sin(ang)) * dist
			var w := _rng.randf_range(c[5], c[6])
			var d := w * _rng.randf_range(0.6, 1.0)
			var hr: Vector2 = c[7]
			var h := w * _rng.randf_range(hr.x, hr.y)
			var r := maxf(w, d) * 0.5
			if not _rock_fits(p, r, style == "hill", placed):
				continue
			placed.append(Vector3(p.x, p.y, r))
			var body := _solid_body("Rock%d" % count)
			body.position = Vector3(p.x, 0, p.y)
			body.rotation.y = _rng.randf() * TAU
			var shape: Array = _rock_mesh(style, _rng.randi_range(0, 7))
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = shape[0]
			mi.material_override = M[c[1]]
			mi.scale = Vector3(w * 0.5, h, d * 0.5)
			mi.position.y = -0.05 * h
			mi.set_meta("no_draw_distance", true)
			mi.visibility_range_end = 750.0 if w > 15.0 else 300.0
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			var convex := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for v: Vector3 in shape[1]:
				pts.append(Vector3(v.x * w * 0.5, v.y * h - 0.05 * h, v.z * d * 0.5))
			convex.points = pts
			cs.shape = convex
			body.add_child(cs)
			root.add_child(body)
			made += 1
			count += 1
	root.add_child(_scatter())
	print("  rocks: %d" % count)
	return root


## Room for a rock of radius `r` at `p`: inside the zone, clear of places,
## roads, the railway and other rocks. Hills may run out past the edge.
func _rock_fits(p: Vector2, r: float, hill: bool, placed: Array[Vector3]) -> bool:
	var inside_by := -_boundary.signed_distance(Vector3(p.x, 0, p.y))
	if inside_by < (-r * 0.5 if hill else r + 2.0):
		return false
	if _place_distance(p) < r + 10.0 or _road_distance(p) < r + 5.0:
		return false
	for q in placed:
		if p.distance_to(Vector2(q.x, q.y)) < r + q.z + 2.0:
			return false
	return true


## Pebbles and dry scrub over the open ground (no collision).
func _scatter() -> Node3D:
	var root := Node3D.new()
	root.name = "Scatter"
	var kinds := [["Stones", 900, "rock_tan"], ["Scrub", 1100, "scrub"]]
	var stone := _pebble()
	var bush := CylinderMesh.new()
	bush.top_radius = 0.0
	bush.bottom_radius = 0.45
	bush.height = 0.55
	bush.radial_segments = 5
	bush.rings = 1
	var min_p := Vector2(-160, -800)
	var max_p := Vector2(660, 160)
	for k in kinds:
		var xf: Array[Transform3D] = []
		var tries := 0
		while xf.size() < int(k[1]) and tries < int(k[1]) * 6:
			tries += 1
			var p := Vector2(_rng.randf_range(min_p.x, max_p.x), _rng.randf_range(min_p.y, max_p.y))
			if not _inside(p) or _place_distance(p) < 4.0 or _road_distance(p) < 2.0:
				continue
			var s := _rng.randf_range(0.18, 0.55) if k[0] == "Stones" else _rng.randf_range(0.6, 1.5)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.5, 1.0), s))
			xf.append(Transform3D(b, Vector3(p.x, 0.0, p.y)))
		root.add_child(_merged(k[0], stone if k[0] == "Stones" else bush, xf, M[k[2]], 200.0, 240.0))
	return root


# ================================================================ the zone

const TILE := 100.0
const NAV_PATH := OUT + "navigation.scn"


func _environment() -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.45, 0.54)
	sky_mat.sky_horizon_color = Color(0.74, 0.68, 0.6)
	sky_mat.ground_bottom_color = Color(0.18, 0.16, 0.13)
	sky_mat.ground_horizon_color = Color(0.64, 0.59, 0.52)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.glow_enabled = true
	# Dust haze: clear close by, closing in to hide the zone's far edges
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.7, 0.64, 0.56)
	env.fog_density = 1.0
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 620.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.4
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	return env


func _zone() -> void:
	# An empty navigation scene first: the zone instances it, and it's filled below
	var empty := Node3D.new()
	empty.name = "Navigation"
	_save(empty, "navigation.scn")

	var zone := Node3D.new()
	zone.name = "EarlyZone"
	zone.set_script(load("res://scripts/world/zone.gd"))
	zone.set_meta("region_name", "Early Zone")
	# Light
	var lighting := Node3D.new()
	lighting.name = "Lighting"
	zone.add_child(lighting)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load(OUT + "early_zone_environment.tres")
	lighting.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = str_to_var("Transform3D(0.81915206, 0.35312894, -0.45198444, 0, 0.7880108, 0.6156615, 0.57357645, -0.5043204, 0.64550066, 0, 0, 0)")  # as Outpost 17's
	sun.light_color = Color(1, 0.93, 0.83)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	# Two cascades to 120 m: each cascade draws every shadow caster again, and
	# past 120 m the haze softens everything anyway (Increment 16.5)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 120.0
	lighting.add_child(sun)
	# Ground, roads, rocks
	for part in ["terrain", "roads", "rocks"]:
		zone.add_child((load(OUT + part + ".scn") as PackedScene).instantiate())
	# The places
	var outpost := (load(OUTPOST_SCENE) as PackedScene).instantiate() as Node3D
	outpost.name = "Outpost17"
	zone.add_child(outpost)
	var haldens := (load(HALDENS_SCENE) as PackedScene).instantiate() as Node3D
	haldens.name = "HaldensCrossing"
	haldens.position = HALDENS_AT
	zone.add_child(haldens)
	# The other five places (Increment 16: tools/build_sites.gd builds them)
	for pair in [["SaintMercyClinic", "saint_mercy_clinic"], ["AshCreekFarms", "ash_creek_farms"],
			["SmugglersGulch", "smugglers_gulch"], ["BlackRidgeMine", "black_ridge_mine"],
			["NorthwatchOutpost", "northwatch_outpost"]]:
		var site := (load("res://levels/%s/%s.tscn" % [pair[1], pair[1]]) as PackedScene).instantiate() as Node3D
		site.name = pair[0]
		var c: Vector2 = PLACES[pair[0]][1]
		site.position = Vector3(c.x, 0, c.y)
		zone.add_child(site)
	# Landmarks (compass, place names)
	var marks := Node3D.new()
	marks.name = "Landmarks"
	zone.add_child(marks)
	for key in PLACES:
		var l := Landmark.new()
		l.name = key
		l.display_name = PLACES[key][0]
		l.compass_name = PLACES[key][3]
		l.radius = PLACES[key][2]
		var c: Vector2 = PLACES[key][1]
		l.position = Vector3(c.x, 2.0, c.y)
		marks.add_child(l)
	# The edge: the ash storm and the coast, and the walls past it
	var edge := ZoneBoundary.new()
	edge.name = "Boundary"
	edge.polygon = _boundary.polygon
	edge.edge_kinds = _boundary.edge_kinds
	zone.add_child(edge)
	edge.add_child(_backstop())
	# Built things, the player and the game
	var structures := Node3D.new()
	structures.name = "Structures"
	structures.add_to_group("navigation_geometry", true)
	zone.add_child(structures)
	var nav := (load(NAV_PATH) as PackedScene).instantiate()
	nav.name = "Navigation"
	zone.add_child(nav)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0, 0.05, 14)
	zone.add_child(spawn)
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
	player.name = "Player"
	player.position = Vector3(0, 0, 14)
	zone.add_child(player)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	hud.name = "HUD"
	zone.add_child(hud)
	var gm := Node.new()
	gm.name = "GameMode"
	gm.set_script(load("res://scripts/core/game_mode.gd"))
	zone.add_child(gm)
	hud.set("player", player)
	hud.set("game_mode", gm)
	gm.set("spawn_point", spawn)
	var players: Array[PlayerController] = [player as PlayerController]
	gm.set("players", players)
	var storm := CanvasLayer.new()
	storm.name = "StormEffects"
	storm.set_script(load("res://scripts/world/storm_effects.gd"))
	zone.add_child(storm)
	var wind := AudioStreamPlayer.new()
	wind.name = "Ambience"
	wind.stream = load("res://assets/audio/wind_loop.wav")
	wind.volume_db = -2.0
	wind.autoplay = true
	wind.bus = &"Ambience"
	zone.add_child(wind)
	var far_wind := AudioStreamPlayer.new()
	far_wind.name = "DistantWind"
	far_wind.stream = load("res://assets/audio/loops/distant_wind_loop.wav")
	far_wind.volume_db = -14.0
	far_wind.autoplay = true
	far_wind.bus = &"Ambience"
	zone.add_child(far_wind)
	_own(zone, zone)
	wind.unique_name_in_owner = true
	_save(zone, "early_zone.tscn")
	await _bake_navigation()


## Invisible walls past the edge: storm edges `backstop_distance` out, the
## coast `sea_backstop_distance` out.
func _backstop() -> StaticBody3D:
	var body := _solid_body("Backstop")
	var n := EDGE.size()
	var outward: Array[Vector2] = []
	var dist: Array[float] = []
	for i in n:
		var a: Vector2 = EDGE[i]
		var b: Vector2 = EDGE[(i + 1) % n]
		var dir := (b - a).normalized()
		var nrm := Vector2(dir.y, -dir.x)
		if _inside((a + b) * 0.5 + nrm):
			nrm = -nrm
		outward.append(nrm)
		dist.append(_boundary.sea_backstop_distance if SEA_EDGES.has(i) else _boundary.backstop_distance)
	var corners: Array[Vector2] = []
	for i in n:
		var p := (i - 1 + n) % n
		var a0: Vector2 = EDGE[p] + outward[p] * dist[p]
		var a1: Vector2 = EDGE[i] + outward[p] * dist[p]
		var b0: Vector2 = EDGE[i] + outward[i] * dist[i]
		var b1: Vector2 = EDGE[(i + 1) % n] + outward[i] * dist[i]
		var hit: Variant = Geometry2D.line_intersects_line(a0, a1 - a0, b0, b1 - b0)
		corners.append(hit if hit != null else EDGE[i] + (outward[p] + outward[i]).normalized() * dist[i])
	for i in n:
		var a := corners[i]
		var b := corners[(i + 1) % n]
		var d := b - a
		var cs := CollisionShape3D.new()
		cs.name = "Wall%d" % i
		var bs := BoxShape3D.new()
		bs.size = Vector3(d.length() + 4.0, 90.0, 2.0)
		cs.shape = bs
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3((a.x + b.x) * 0.5, 35.0, (a.y + b.y) * 0.5))
		body.add_child(cs)
	return body


func _nav_template() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navigation_geometry"
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_height = 1.75
	nm.agent_radius = 0.25
	nm.agent_max_climb = 0.25
	nm.border_size = 1.0
	nm.edge_max_error = 1.0
	return nm


## Bakes the navmesh tile by tile from the saved zone (with its raiders off)
## and writes navigation.scn.
func _bake_navigation() -> void:
	var zone := (load(OUT + "early_zone.tscn") as PackedScene).instantiate() as Node3D
	for n in zone.find_children("*", "Node3D", true, false):
		if n is EnemySpawner:
			(n as EnemySpawner).enabled = false
	(zone.get_node("Player") as PlayerController).controlled_locally = false
	root.add_child(zone)
	for i in 3:
		await process_frame
	var t0 := Time.get_ticks_msec()
	var template := _nav_template()
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(template, source, zone)
	var t1 := Time.get_ticks_msec()
	var grown := ZoneBoundary.grow(PackedVector2Array(EDGE), 36.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in grown:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var nav := Node3D.new()
	nav.name = "Navigation"
	var tiles := 0
	var x := floorf(lo.x / TILE) * TILE
	while x < hi.x:
		var z := floorf(lo.y / TILE) * TILE
		while z < hi.y:
			var rect := PackedVector2Array([Vector2(x, z), Vector2(x + TILE, z), Vector2(x + TILE, z + TILE), Vector2(x, z + TILE)])
			if not Geometry2D.intersect_polygons(rect, grown).is_empty():
				var nm := _nav_template()
				# The border is cut off inside the baking box, so grow the box by it:
				# each tile's edges then lie exactly on the tile lines and join up.
				var bs := nm.border_size
				nm.filter_baking_aabb = AABB(Vector3(x - bs, -12.0, z - bs), Vector3(TILE + 2.0 * bs, 52.0, TILE + 2.0 * bs))
				NavigationServer3D.bake_from_source_geometry_data(nm, source)
				if nm.get_polygon_count() > 0:
					var region := NavigationRegion3D.new()
					region.name = "Tile_%d_%d" % [int(x / TILE), int(z / TILE)]
					region.navigation_mesh = nm
					nav.add_child(region)
					tiles += 1
			z += TILE
		x += TILE
	var t2 := Time.get_ticks_msec()
	print("  navigation: parsed in %.1f s, %d tiles baked in %.1f s" % [(t1 - t0) / 1000.0, tiles, (t2 - t1) / 1000.0])
	zone.queue_free()
	await process_frame
	_save(nav, "navigation.scn")
