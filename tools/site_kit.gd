extends RefCounted
## Builds a place (a site) out of simple parts, the way Halden's Crossing is
## built: buildings whose walls are split round door and window openings,
## floors, upper storeys reached by ladders, fixtures (counters, shelves,
## beds), searchable containers, salvage piles, pickups, reusable props and
## raider spawners. Used by tools/build_sites.gd.
##
## Coordinates are the site's own (x east, -z north), metres. A building
## has its own frame: its centre and a yaw. Its sides are N (-z), S (+z),
## W (-x) and E (+x) in that frame, and anything placed "in" a building
## takes a position and yaw in the building's frame.
##
## Everything solid is on the structures layer and in the
## "navigation_geometry" group, so the zone's navmesh sees it.

const WALL_T := 0.3          ## wall thickness
const STOREY := 3.3          ## floor to floor
const DOOR := Vector2(1.6, 2.4)    ## width, height
const WIDE := Vector2(4.0, 4.0)    ## barn / workshop doors
const WINDOW := Vector2(1.2, 1.2)  ## width, height (sill at 1.0)
const SILL := 1.0

const SCENES := {
	"crate": "res://scenes/world/containers/supply_crate.tscn",
	"footlocker": "res://scenes/world/containers/footlocker.tscn",
	"locker": "res://scenes/world/containers/weapons_locker.tscn",
	"pallet": "res://scenes/world/salvage/wood_pallet.tscn",
	"furniture": "res://scenes/world/salvage/broken_furniture.tscn",
	"scrap": "res://scenes/world/salvage/scrap_heap.tscn",
	"appliance": "res://scenes/world/salvage/appliance_pile.tscn",
	"pickup": "res://scenes/items/pickup.tscn",
	"ladder": "res://scenes/world/structures/ladder.tscn",
	"guard_tower": "res://scenes/world/structures/guard_tower.tscn",
	"shipping_container": "res://scenes/world/props/shipping_container.tscn",
	"fuel_drums": "res://scenes/world/props/fuel_drums.tscn",
	"wood_crate": "res://scenes/world/props/wood_crate.tscn",
	"sandbags": "res://scenes/world/props/sandbag_wall.tscn",
	"jersey": "res://scenes/world/props/jersey_barrier.tscn",
	"chain_link": "res://scenes/world/props/chain_link_fence.tscn",
	"burning_barrel": "res://scenes/world/props/burning_barrel.tscn",
	"truck": "res://scenes/vehicles/military_truck.tscn",
	"generator": "res://assets/ashfall_pack_v2/scenes/portable_generator.tscn",
	"radio": "res://assets/ashfall_pack_v2/scenes/field_radio.tscn",
	"toolbox": "res://assets/ashfall_pack_v2/scenes/salvage_toolbox.tscn",
	"water_tank": "res://assets/ashfall_pack_v2/scenes/water_storage_tank.tscn",
	"workbench": "res://scenes/world/stations/workbench.tscn",
	"weapons_bench": "res://scenes/world/stations/weapons_bench.tscn",
	"raider": "res://scenes/enemies/raider.tscn",
	"veteran": "res://scenes/enemies/raider_veteran.tscn",
}

const MATERIALS := {
	"concrete": "res://assets/ashfall_pack_v1/materials/concrete_weathered.tres",
	"concrete_cracked": "res://assets/ashfall_pack_v1/materials/concrete_cracked.tres",
	"concrete_plain": "res://assets/materials/concrete.tres",
	"concrete_stained": "res://assets/materials/concrete_stained.tres",
	"plaster": "res://assets/materials/plaster.tres",
	"brick": "res://assets/ashfall_pack_v3/materials/brick_weathered.tres",
	"wood": "res://assets/ashfall_pack_v1/materials/wood_weathered.tres",
	"wood_plain": "res://assets/materials/wood.tres",
	"corrugated": "res://assets/ashfall_pack_v1/materials/corrugated_metal.tres",
	"rust": "res://assets/ashfall_pack_v1/materials/rusted_steel.tres",
	"metal_dark": "res://assets/materials/metal_dark.tres",
	"olive": "res://assets/materials/olive_drab.tres",
	"hazard": "res://assets/materials/hazard_yellow.tres",
	"roofing": "res://assets/ashfall_pack_v3/materials/roofing_tarpaper.tres",
	"canvas": "res://assets/ashfall_pack_v3/materials/canvas_tent.tres",
	"sandbag": "res://assets/materials/sandbag.tres",
	"soot": "res://assets/materials/soot.tres",
	"glass": "res://assets/materials/glass_dirty.tres",
	"paint_white": "res://levels/early_zone/materials/paint_white.tres",
	"barn_red": "res://levels/early_zone/materials/barn_red.tres",
	"red_cross": "res://levels/early_zone/materials/red_cross.tres",
	"field_soil": "res://levels/early_zone/materials/field_soil.tres",
	"crop": "res://levels/early_zone/materials/crop_dry.tres",
	"crop_green": "res://levels/early_zone/materials/crop_green.tres",
	"rock_red": "res://levels/early_zone/materials/rock_red.tres",
	"rock_dark": "res://levels/early_zone/materials/rock_dark.tres",
	"opening": "res://levels/early_zone/materials/opening.tres",
	"container_red": "res://assets/ashfall_pack_v3/materials/container_paint_red.tres",
	"container_blue": "res://assets/ashfall_pack_v3/materials/container_paint_blue.tres",
	"container_olive": "res://assets/ashfall_pack_v3/materials/container_paint_olive.tres",
}

var root: Node3D
var groups := {}   # name -> Node3D
var rng := RandomNumberGenerator.new()
## For tests and the guide: what was placed
var counts := {"buildings": 0, "containers": 0, "piles": 0, "pickups": 0, "ladders": 0}

var _mats := {}
var _scenes := {}
var _mesh_cache := {}
var _shape_cache := {}


func _init(node_name: String, display_name: String, seed_value: int) -> void:
	root = Node3D.new()
	root.name = node_name
	root.set_meta("region_name", display_name)
	rng.seed = seed_value
	for g in ["Buildings", "Furniture", "Props", "SalvageContainers", "CraftingStations", "Towers"]:
		group(g, true)
	for g in ["SalvagePiles", "Loot", "Signage", "Soundscape"]:
		group(g, false)


func group(name: String, solid: bool) -> Node3D:
	if groups.has(name):
		return groups[name]
	var n := Node3D.new()
	n.name = name
	if solid:
		n.add_to_group("navigation_geometry", true)
	root.add_child(n)
	groups[name] = n
	return n


func mat(key: String) -> Material:
	if not _mats.has(key):
		_mats[key] = load(MATERIALS[key])
	return _mats[key]


func scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		_scenes[key] = load(SCENES[key])
	return _scenes[key]


func box_mesh(size: Vector3) -> BoxMesh:
	var k := str(size.snappedf(0.001))
	if not _mesh_cache.has(k):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[k] = m
	return _mesh_cache[k]


func box_shape(size: Vector3) -> BoxShape3D:
	var k := str(size.snappedf(0.001))
	if not _shape_cache.has(k):
		var s := BoxShape3D.new()
		s.size = size
		_shape_cache[k] = s
	return _shape_cache[k]


## A box under `body` (a StaticBody3D, or any Node3D for visual-only).
func box(body: Node3D, name: String, size: Vector3, pos: Vector3, mat_key: String, yaw_deg := 0.0, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = box_mesh(size)
	mi.material_override = mat(mat_key)
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	body.add_child(mi)
	if solid and body is CollisionObject3D:
		var cs := CollisionShape3D.new()
		cs.name = name + "Col"
		cs.shape = box_shape(size)
		cs.transform = mi.transform
		body.add_child(cs)
	return mi


func solid_body(parent: Node3D, name: String, xform := Transform3D.IDENTITY) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.collision_layer = PhysicsLayers.STRUCTURES
	b.collision_mask = 0
	b.transform = xform
	parent.add_child(b)
	return b


# ================================================================ buildings

## A building, `size` (x, z) metres, centred at `at` and turned `yaw_deg`.
## opts:
##   wall: material key (walls)          floor: material key ("" = none)
##   storeys: 1 or 2                     height: storey height (STOREY)
##   roof: "flat" | "pitched" | "none"   roof_mat: material key
##   parapet: true for a walkable flat roof (with a gap where `roof_ladder` is)
##   openings: [[side, offset, kind, storey?]]  kind "door" | "window" | "wide"
##   ruin: {side: height}  ground-storey walls broken down to that height
##   hole: Rect2 in the building frame, the hole in the upper floor
##   inner: [[from Vector2, to Vector2, [door offsets along it]]]  inner walls
## Returns the building's StaticBody3D; its meta "doors" lists each door as
## [centre in the site, outward direction] for tests.
func building(name: String, at: Vector2, yaw_deg: float, size: Vector2, opts: Dictionary) -> StaticBody3D:
	var b := solid_body(groups["Buildings"], name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(at.x, 0, at.y)))
	var wall: String = opts.get("wall", "concrete")
	var storeys: int = opts.get("storeys", 1)
	var h: float = opts.get("height", STOREY)
	var openings: Array = opts.get("openings", [])
	var ruin: Dictionary = opts.get("ruin", {})
	var doors := []
	for side in ["N", "S", "W", "E"]:
		var along := size.x if side in ["N", "S"] else size.y - 2.0 * WALL_T
		for s in storeys:
			var ops := openings.filter(func(o: Array) -> bool: return o[0] == side and (o[3] if o.size() > 3 else 0) == s)
			var top := h if s < storeys - 1 or not ruin.has(side) else maxf(float(ruin[side]), _tallest(ops) + 0.2)
			_wall(b, "Wall%s%d" % [side, s], side, size, along, s * h, top, ops, wall)
			for o: Array in ops:
				if o[2] != "window" and s == 0:
					var c := _side_point(side, size, float(o[1]))
					var out := _side_normal(side)
					doors.append([b.transform * Vector3(c.x, 0, c.y), (b.basis * Vector3(out.x, 0, out.y)).normalized()])
	if opts.get("floor", "concrete") != "":
		var fm := MeshInstance3D.new()
		fm.name = "Floor"
		fm.mesh = box_mesh(Vector3(size.x - 0.1, 0.04, size.y - 0.1))
		fm.material_override = mat(opts.get("floor", "concrete"))
		fm.position = Vector3(0, 0.02, 0)
		b.add_child(fm)
	# Upper floors, with a hole for the ladder
	for s in range(1, storeys):
		_slab(b, "Slab%d" % s, size, s * h, opts.get("hole", Rect2()), opts.get("floor2", "wood"))
	# Roof
	var top_y := storeys * h
	match opts.get("roof", "flat"):
		"flat":
			box(b, "Roof", Vector3(size.x + 0.2, 0.3, size.y + 0.2), Vector3(0, top_y + 0.15, 0), opts.get("roof_mat", "roofing"))
			if opts.get("parapet", false):
				_parapet(b, size, top_y + 0.3, opts.get("roof_ladder", Vector3.INF), wall)
		"pitched":
			box(b, "Ceiling", Vector3(size.x, 0.12, size.y), Vector3(0, top_y + 0.06, 0), opts.get("floor2", "wood"))
			var pm := PrismMesh.new()
			var ridge_z: bool = size.y >= size.x
			pm.size = Vector3((size.x if ridge_z else size.y) + 0.6, opts.get("pitch", 2.2), (size.y if ridge_z else size.x) + 0.6)
			var roof := MeshInstance3D.new()
			roof.name = "Roof"
			roof.mesh = pm
			roof.material_override = mat(opts.get("roof_mat", "roofing"))
			roof.transform = Transform3D(Basis(Vector3.UP, 0.0 if ridge_z else PI / 2.0), Vector3(0, top_y + 0.12 + pm.size.y / 2.0, 0))
			b.add_child(roof)
		"none":
			pass
	# Inner walls
	for iw: Array in opts.get("inner", []):
		_inner_wall(b, iw[0], iw[1], iw[2] if iw.size() > 2 else [], h, opts.get("inner_mat", "plaster"))
	# Interior lights, so rooms read inside (the sun never reaches them)
	if opts.get("roof", "flat") != "none" and opts.get("lights", true):
		_interior_lights(b, size, storeys, h)
	b.set_meta("doors", doors)
	b.set_meta("size", size)
	b.set_meta("storeys", storeys)
	counts["buildings"] += 1
	return b


var _lamp_mat: StandardMaterial3D


## A dim, warm lamp every ~9 m along the long axis, one row per storey.
## No shadows, faded out past 60 m so the zone never draws many at once.
func _interior_lights(b: StaticBody3D, size: Vector2, storeys: int, h: float) -> void:
	var long_z := size.y >= size.x
	var length := size.y if long_z else size.x
	var n := maxi(1, int(round(length / 9.0)))
	for s in storeys:
		for i in n:
			var t := (float(i) + 0.5) / float(n) - 0.5
			var p := Vector3(0, s * h + h - 0.35, 0)
			if long_z:
				p.z = t * length
			else:
				p.x = t * length
			lamp(b, "%d_%d" % [s, i], p, 1.1, clampf(maxf(size.x, size.y) * 0.75, 6.0, 11.0))


## A ceiling lamp: a dim warm OmniLight plus a small glowing fitting just above it.
func lamp(parent: Node3D, suffix: String, p: Vector3, energy: float, light_range: float, flicker := false) -> OmniLight3D:
	if _lamp_mat == null:
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.albedo_color = Color(1.0, 0.86, 0.6)
		_lamp_mat.emission_enabled = true
		_lamp_mat.emission = Color(1.0, 0.8, 0.5)
		_lamp_mat.emission_energy_multiplier = 2.0
	var l := OmniLight3D.new()
	if flicker:
		l.set_script(load("res://scripts/world/flicker_light.gd"))
		l.set("base_energy", energy)
		l.set("flicker_amount", energy * 0.15)
		l.set("speed", 3.0)
	l.name = "Lamp" + suffix
	l.position = p
	l.light_color = Color(1.0, 0.85, 0.65)
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 0.8
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 45.0
	l.distance_fade_length = 15.0
	parent.add_child(l)
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb" + suffix
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.08, 0.5)
	bulb.mesh = bm
	bulb.material_override = _lamp_mat
	bulb.position = p + Vector3(0, 0.29, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bulb)
	counts["lights"] = counts.get("lights", 0) + 1
	return l


func _tallest(ops: Array) -> float:
	var t := 0.0
	for o: Array in ops:
		t = maxf(t, _opening(o[2]).y + (SILL if o[2] == "window" else 0.0))
	return t


func _opening(kind: String) -> Vector2:
	return DOOR if kind == "door" else (WIDE if kind == "wide" else WINDOW)


## Centre of side `side` at `offset` along it (building frame, x/z).
func _side_point(side: String, size: Vector2, offset: float) -> Vector2:
	match side:
		"N": return Vector2(offset, -size.y / 2.0 + WALL_T / 2.0)
		"S": return Vector2(offset, size.y / 2.0 - WALL_T / 2.0)
		"W": return Vector2(-size.x / 2.0 + WALL_T / 2.0, offset)
		_: return Vector2(size.x / 2.0 - WALL_T / 2.0, offset)


func _side_normal(side: String) -> Vector2:
	match side:
		"N": return Vector2(0, -1)
		"S": return Vector2(0, 1)
		"W": return Vector2(-1, 0)
		_: return Vector2(1, 0)


## One storey of one wall, split round its openings.
func _wall(b: StaticBody3D, name: String, side: String, size: Vector2, length: float, y0: float, top: float, ops: Array, wall: String) -> void:
	var along_x := side in ["N", "S"]
	var c := _side_point(side, size, 0.0)
	var h := top
	# Spans along the wall: [from, to, kind]
	var cuts := []
	for o: Array in ops:
		var w := _opening(o[2]).x
		cuts.append([float(o[1]) - w / 2.0, float(o[1]) + w / 2.0, o[2]])
	cuts.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] < bb[0])
	var pos := -length / 2.0
	var k := [0]  # (lambdas capture locals by value: count in an array)
	var piece := func(from: float, to: float, lo: float, hi: float) -> void:
		if to - from < 0.02 or hi - lo < 0.02:
			return
		var mid := (from + to) / 2.0
		var size3 := Vector3(to - from, hi - lo, WALL_T) if along_x else Vector3(WALL_T, hi - lo, to - from)
		var p := Vector3(mid if along_x else c.x, y0 + (lo + hi) / 2.0, c.y if along_x else mid)
		box(b, "%s_%d" % [name, k[0]], size3, p, wall)
		k[0] += 1
	for cut: Array in cuts:
		piece.call(pos, cut[0], 0.0, h)
		var o := _opening(cut[2])
		if cut[2] == "window":
			piece.call(cut[0], cut[1], 0.0, SILL)
			piece.call(cut[0], cut[1], SILL + o.y, h)
		else:
			piece.call(cut[0], cut[1], o.y, h)
		pos = cut[1]
	piece.call(pos, length / 2.0, 0.0, h)


## An upper floor slab with a rectangular hole (building frame).
func _slab(b: StaticBody3D, name: String, size: Vector2, y: float, hole: Rect2, mat_key: String) -> void:
	var inner := Rect2(-size.x / 2.0 + WALL_T, -size.y / 2.0 + WALL_T, size.x - 2.0 * WALL_T, size.y - 2.0 * WALL_T)
	var parts: Array[Rect2] = []
	if hole.size == Vector2.ZERO:
		parts.append(inner)
	else:
		# Four slabs round the hole: north, south (full width), west, east
		parts.append(Rect2(inner.position.x, inner.position.y, inner.size.x, hole.position.y - inner.position.y))
		parts.append(Rect2(inner.position.x, hole.end.y, inner.size.x, inner.end.y - hole.end.y))
		parts.append(Rect2(inner.position.x, hole.position.y, hole.position.x - inner.position.x, hole.size.y))
		parts.append(Rect2(hole.end.x, hole.position.y, inner.end.x - hole.end.x, hole.size.y))
	var i := 0
	for r in parts:
		if r.size.x < 0.05 or r.size.y < 0.05:
			continue
		box(b, "%s%s" % [name, "ABCD"[i]], Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, y - 0.15, r.get_center().y), mat_key)
		i += 1


func _parapet(b: StaticBody3D, size: Vector2, y: float, gap_at: Vector3, wall: String) -> void:
	var h := 0.9
	for side in ["N", "S", "W", "E"]:
		var along := size.x + 0.2 if side in ["N", "S"] else size.y
		var c := _side_point(side, size + Vector2(0.2, 0.2), 0.0)
		var pieces := [[-along / 2.0, along / 2.0]]
		if gap_at != Vector3.INF:
			var g: float = gap_at.x if side in ["N", "S"] else gap_at.z
			var on_side: bool = absf((gap_at.z if side in ["N", "S"] else gap_at.x) - (c.y if side in ["N", "S"] else c.x)) < 0.6
			if on_side:
				pieces = [[-along / 2.0, g - 0.6], [g + 0.6, along / 2.0]]
		var k := 0
		for pc: Array in pieces:
			var len: float = pc[1] - pc[0]
			if len < 0.05:
				continue
			var mid: float = (pc[0] + pc[1]) / 2.0
			var s3 := Vector3(len, h, 0.25) if side in ["N", "S"] else Vector3(0.25, h, len)
			var p := Vector3(mid, y + h / 2.0, c.y) if side in ["N", "S"] else Vector3(c.x, y + h / 2.0, mid)
			box(b, "Parapet%s_%d" % [side, k], s3, p, wall)
			k += 1


func _inner_wall(b: StaticBody3D, from: Vector2, to: Vector2, door_offsets: Array, h: float, mat_key: String) -> void:
	var d := to - from
	var length := d.length()
	var dir := d / length
	var yaw := -atan2(dir.y, dir.x)
	var cuts := []
	for off in door_offsets:
		cuts.append([float(off) - DOOR.x / 2.0, float(off) + DOOR.x / 2.0])
	cuts.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] < bb[0])
	var pos := 0.0
	var k := 0
	var spans := []
	for cut: Array in cuts:
		spans.append([pos, cut[0], 0.0, h])
		spans.append([cut[0], cut[1], DOOR.y, h])
		pos = cut[1]
	spans.append([pos, length, 0.0, h])
	for s: Array in spans:
		if s[1] - s[0] < 0.02:
			continue
		var mid: float = (s[0] + s[1]) / 2.0
		var p2 := from + dir * mid
		box(b, "Inner_%d_%d_%d" % [int(from.x * 10), int(from.y * 10), k], Vector3(s[1] - s[0], s[3] - s[2], 0.15), Vector3(p2.x, (s[2] + s[3]) / 2.0, p2.y), mat_key, rad_to_deg(yaw))
		k += 1


# ================================================================ things in and around buildings

## A point in `b`'s frame (or the site's if b is null), in site space.
func at(b: Node3D, local: Vector3) -> Vector3:
	return b.transform * local if b != null else local


func yaw_in(b: Node3D, local_yaw_deg: float) -> float:
	return (b.rotation.y if b != null else 0.0) + deg_to_rad(local_yaw_deg)


## Inside face of a building's wall, `inset` metres in (building frame).
func against(b: StaticBody3D, side: String, offset: float, inset: float) -> Vector3:
	var size: Vector2 = b.get_meta("size")
	match side:
		"N": return Vector3(offset, 0, -size.y / 2.0 + WALL_T + inset)
		"S": return Vector3(offset, 0, size.y / 2.0 - WALL_T - inset)
		"W": return Vector3(-size.x / 2.0 + WALL_T + inset, 0, offset)
		_: return Vector3(size.x / 2.0 - WALL_T - inset, 0, offset)


## The yaw (degrees) that turns a thing's front (+Z) away from `side`'s wall.
static func facing_from(side: String) -> float:
	match side:
		"N": return 0.0
		"S": return 180.0
		"W": return 90.0
		_: return -90.0


## Counters, shelves, beds, desks: solid boxes in Furniture/Fixtures.
func fixture(name: String, b: Node3D, local: Vector3, size: Vector3, mat_key: String, local_yaw := 0.0) -> MeshInstance3D:
	var fx := groups["Furniture"].get_node_or_null("Fixtures") as StaticBody3D
	if fx == null:
		fx = solid_body(groups["Furniture"], "Fixtures")
	var p := at(b, local + Vector3(0, size.y / 2.0, 0))
	return box(fx, name, size, p, mat_key, rad_to_deg(yaw_in(b, local_yaw)))


## A searchable container (front = +Z at local_yaw 0).
func container(kind: String, name: String, b: Node3D, local: Vector3, local_yaw: float, table: String, label: String) -> Node3D:
	var c := scene(kind).instantiate() as Node3D
	c.name = name
	c.position = at(b, local)
	c.rotation.y = yaw_in(b, local_yaw)
	if table != "":
		c.set("loot_table", load("res://resources/loot/%s.tres" % table))
	if label != "":
		c.set("container_name", label)
		c.set("object_name", label)
	groups["SalvageContainers"].add_child(c)
	counts["containers"] += 1
	return c


## A container standing against an inside wall, facing into the room.
func container_at_wall(kind: String, name: String, b: StaticBody3D, side: String, offset: float, table: String, label: String, y := 0.0) -> Node3D:
	var depth := 0.72 if kind == "crate" else (0.62 if kind == "locker" else 0.57)
	var p := against(b, side, offset, depth / 2.0 + 0.08)
	p.y = y
	return container(kind, name, b, p, facing_from(side), table, label)


func pile(kind: String, name: String, b: Node3D, local: Vector3, local_yaw := 0.0) -> Node3D:
	var p := scene(kind).instantiate() as Node3D
	p.name = name
	p.position = at(b, local)
	p.rotation.y = yaw_in(b, local_yaw)
	groups["SalvagePiles"].add_child(p)
	counts["piles"] += 1
	return p


func pickup(item_id: String, qty: int, name: String, b: Node3D, local: Vector3, local_yaw := 0.0) -> Node3D:
	var p := scene("pickup").instantiate() as Node3D
	p.name = name
	var item := load("res://resources/items/%s.tres" % item_id) as Resource
	if item == null:
		item = load("res://resources/items/weapons/%s.tres" % item_id)
	assert(item != null, "no item " + item_id)
	p.set("item", item)
	p.set("quantity", qty)
	p.position = at(b, local)
	p.rotation.y = yaw_in(b, local_yaw + rng.randf_range(-40, 40))
	groups["Loot"].add_child(p)
	counts["pickups"] += 1
	return p


## A ladder: origin at the bottom, its +Z toward the climber, top at `height`.
func ladder(name: String, b: Node3D, local: Vector3, local_yaw: float, height: float) -> Node3D:
	var l := scene("ladder").instantiate() as Node3D
	l.name = name
	l.set("height", height)
	l.set("width", 0.5)
	# In a building it's part of the building (its frame); otherwise the site's
	l.position = local
	l.rotation.y = deg_to_rad(local_yaw)
	(b if b != null else groups["Buildings"]).add_child(l)
	counts["ladders"] += 1
	return l


## A reusable prop scene (movable/scrappable where the scene allows).
func prop(kind: String, name: String, pos: Vector3, yaw_deg := 0.0, parent_group := "Props") -> Node3D:
	var p := scene(kind).instantiate() as Node3D
	p.name = name
	p.position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	groups[parent_group].add_child(p)
	return p


func spawner(name: String, enemy: String, max_alive: int, respawn: float, points: Array, active_radius := 230.0) -> EnemySpawner:
	var s := EnemySpawner.new()
	s.name = name
	s.enemy_scene = scene(enemy)
	s.max_alive = max_alive
	s.respawn_delay = respawn
	s.active_radius = active_radius
	root.add_child(s)
	var i := 0
	for pt in points:
		var m := Marker3D.new()
		m.name = "Point%d" % i
		var v: Vector2 = pt
		m.position = Vector3(v.x, 0.1, v.y)
		s.add_child(m)
		i += 1
	return s


## A Pack 3 sign (or graffiti) on a wall: an alpha quad just off the face.
func sign(name: String, material_path: String, b: Node3D, local: Vector3, local_yaw: float, size: Vector2, region := Rect2(0, 0, 1, 1)) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = q
	var m := (load(material_path) as Material).duplicate() as StandardMaterial3D
	if region != Rect2(0, 0, 1, 1):
		m.uv1_scale = Vector3(region.size.x, region.size.y, 1)
		m.uv1_offset = Vector3(region.position.x, region.position.y, 0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at(b, local)
	mi.rotation.y = yaw_in(b, local_yaw)
	groups["Signage"].add_child(mi)
	return mi


func sound(name: String, stream_path: String, pos: Vector3, volume_db: float, max_distance: float, bus := &"SFX") -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = name
	a.stream = load(stream_path)
	a.position = pos
	a.volume_db = volume_db
	a.unit_size = 3.0
	a.max_distance = max_distance
	a.autoplay = true
	a.bus = bus
	groups["Soundscape"].add_child(a)
	return a


## A tent: canvas prism over a low solid base (you can't go in).
func tent(name: String, pos: Vector3, yaw_deg: float, size := Vector3(3.6, 2.2, 4.6)) -> void:
	var b := solid_body(groups["Props"], name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	var pm := PrismMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Canvas"
	mi.mesh = pm
	mi.material_override = mat("canvas")
	mi.position.y = size.y / 2.0
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "CanvasCol"
	cs.shape = box_shape(Vector3(size.x * 0.7, size.y * 0.6, size.z))
	cs.position.y = size.y * 0.3
	b.add_child(cs)


## A lumpy flat-shaded rock of radius ~1 (bottom at -0.3, top clipped).
func rock_mesh(variant: int, top := 0.42, amount := 0.14, freq := 2.2, sides := 10) -> Array:
	var key := "rock:%d:%.2f" % [variant, top]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var n := FastNoiseLite.new()
	n.seed = 400 + variant * 31
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
		var v := d * (1.0 + amount * n.get_noise_3dv(d * 1.5))
		v.y = clampf(v.y, -0.3, top)
		out[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := out[idx[t]]
		var bb := out[idx[t + 1]]
		var c := out[idx[t + 2]]
		var nrm := (c - a).cross(bb - a).normalized()
		if nrm.length() < 0.5:
			continue
		for v in [a, bb, c]:
			st.set_normal(nrm)
			st.add_vertex(v)
	_mesh_cache[key] = [st.commit(), out]
	return _mesh_cache[key]


## A solid rock: `scale` is (half width, height scale, half depth).
func rock(parent: Node3D, name: String, pos: Vector3, yaw_deg: float, scale: Vector3, mat_key: String, variant: int, top := 0.42) -> StaticBody3D:
	var b := solid_body(parent, name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	var shape: Array = rock_mesh(variant, top)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = shape[0]
	mi.material_override = mat(mat_key)
	mi.scale = scale
	mi.set_meta("no_draw_distance", true)
	mi.visibility_range_end = 750.0
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var convex := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for v: Vector3 in shape[1]:
		pts.append(v * scale)
	convex.points = pts
	cs.shape = convex
	b.add_child(cs)
	return b


## Many copies of `mesh` merged into one (MultiMesh data isn't kept headless).
func merged(parent: Node3D, name: String, mesh: Mesh, xforms: Array[Transform3D], mat_key: String, draw_range: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in xforms:
		st.append_from(mesh, 0, x)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat(mat_key)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = draw_range
	mi.set_meta("no_draw_distance", true)
	parent.add_child(mi)
	return mi


# ================================================================ saving

func save(path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	assert(err == OK, "pack " + path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	err = ResourceSaver.save(packed, path)
	assert(err == OK, "save " + path)
	print("  wrote %s: %s" % [path, counts])
	root.free()


func _own(node: Node, owner_root: Node) -> void:
	for c in node.get_children():
		c.owner = owner_root
		if c.scene_file_path == "":
			_own(c, owner_root)
