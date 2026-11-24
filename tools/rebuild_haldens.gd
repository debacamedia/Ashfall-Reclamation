extends SceneTree
## Increment 31: Halden's Crossing rebuilt from Quaternius's Downtown City
## MegaKit (CC0, made ready by tools/build_city_kit.gd).
##
## Each of the town's twelve buildings keeps its footprint, doors, floors,
## upper floor, roof, ladders, furniture and everything inside it (loot,
## containers, raiders' spots: nothing that's saved changes). Only its walls
## are rebuilt: from the kit's brick, painted stone and steel wall pieces,
## shopfronts, doorways, corner columns and cornices, laid out along each
## wall. The windows are open (the glass long gone).
##
## The walls' solid parts are worked out from the pieces themselves: each
## wall is drawn onto a 10 cm grid as seen from outside, thin bits (window
## bars) are left out, and what's solid becomes boxes, 0.3 m thick like the
## walls they replace. So you can see, shoot and (where they're low enough)
## climb through exactly the windows and doorways you see.
##
## Ruined buildings have broken, jagged wall tops, cut from the kit's pieces
## (saved in levels/haldens_crossing/kit/).
##
##   godot --headless --path . -s res://tools/rebuild_haldens.gd
## then rebake the early zone's navigation:
##   godot --headless --path . -s res://tools/build_early_zone.gd -- zone-only bake

const LEVEL := "res://levels/haldens_crossing/haldens_crossing.tscn"
const KIT := "res://assets/models/quaternius/city/built/"
const RUINS := "res://levels/haldens_crossing/kit/"
const T := 0.3
const FLOOR_H := 3.3
## The grid the walls' solid parts are worked out on
const CELL := 0.1
## The kit's walls are 0.2 m thick: ours are 0.3
const THICK := 1.5
## Doors and bays: how high the opening is
const DOOR_TOP := 2.4
## Doorways with a band of wall above them (for the shop signs): how high
## the door piece reaches
const DOOR_FASCIA := 2.6
## Ground-floor windows lower than this are boarded up to it (as the old
## walls' windows were, you can't step through them)
const BOARD_TOP := 1.05
const WOOD := "res://assets/materials/wood.tres"
const WOOD_CHARRED := "res://assets/materials/wood_charred.tres"

## Wall styles: which kit piece for which part of a wall
const STYLES := {
	"brick": {
		"wall": "Brick_Plain_3", "window": "Brick_Window_Trim", "shop": "Trim_FirstFloor_Window_001",
		"door": "DoorFrame_Trim", "column": "Trim_Column_Center", "cornice": "Cornice_Brick_Center",
		"upper_wall": "Brick_TopTrim", "upper_window": "Brick_Window_Trim_Single", "parapet": "Brick_Plain_1",
		"lintel": "Brick_Plain_1",
	},
	"pale_brick": {
		"wall": "Brick_Inset", "window": "Brick_Inset_Window", "shop": "Brick_RedWhite_DoubleWindow",
		"door": "DoorFrame_Trim", "column": "Trim_Column_Center", "cornice": "Cornice_Brick_Center", "base": 4.0,
	},
	"church": {
		"wall": "Brick_Inset", "window": "Brick_Inset_Window_Curved", "door": "DoorFrame_Trim", "column": "Trim_Column_Center",
		"upper_wall": "Brick_Inset", "upper_window": "Brick_Inset", "base": 4.0,
	},
	"stone": {
		"wall": "Trim_Plain_3", "window": "Trim_Window", "shop": "Trim_Window", "door": "DoorFrame_Trim",
		"column": "Trim_Column_Center", "cornice": "Cornice_Trim_Center", "lintel": "Trim_Plain_3",
	},
	"house": {
		"wall": "Trim_Plain_3", "window": "Trim_Window", "door": "DoorFrame_Trim", "column": "Trim_Column_Center",
		"cornice": "Cornice_Trim_Center",
	},
	"metal": {
		"wall": "Metal_Plain_3", "window": "Metal_FirstFloor_Window", "shop": "Metal_FirstFloor_Window", "door": "DoorFrame_Metal_Single",
		"column": "Metal_Column_Center", "cornice": "Cornice_Metal_Center", "lintel": "Metal_FirstFloor_Wall_1",
	},
	"diner": {
		"wall": "Trim_FirstFloor_Wall", "window": "Trim_Window", "shop": "Trim_FirstFloor_Window_001", "door": "DoorFrame_Metal_Single",
		"column": "Metal_Column_Center", "cornice": "Cornice_Metal_Center", "lintel": "Trim_Plain_3",
	},
	"garage": {
		"wall": "Brick_Inset", "window": "Brick_Inset_Window", "door": "DoorFrame_Metal_Single", "column": "Metal_Column_Center",
		"cornice": "Cornice_Metal_Center", "lintel": "Metal_FirstFloor_Wall_1", "base": 4.0,
	},
}

## The town's buildings: as Increment 12 built them (footprint, doors,
## floors, roof, ruin), each with a style. front: the side facing the street
## gets shopfront windows. keep: where a ruin's wall stays whole (a sign
## hangs there), as offsets like the doors'.
const BUILDINGS := [
	{"name": "GeneralStore", "w": 12, "d": 10, "style": "brick", "doors": {"e": [[0.0, 1.6]]}, "front": "e"},
	{"name": "HouseNorthWest", "w": 10, "d": 9, "style": "house", "roof": "partial", "ruin": 1.3, "doors": {"e": [[1.5, 1.3]]}},
	{"name": "Hotel", "w": 14, "d": 12, "floors": 2, "style": "brick", "doors": {"e": [[0.0, 1.6]]}, "front": "e",
		"roof_access": true, "ladder_side": "w", "ladder_at": 2.0},
	{"name": "Clinic", "w": 12, "d": 10, "style": "stone", "doors": {"s": [[0.0, 1.5]]}},
	{"name": "Church", "w": 12, "d": 18, "height": 5.6, "roof": "none", "ruin": 2.2, "style": "church", "doors": {"e": [[0.0, 2.0]]}},
	{"name": "HouseSouthWest", "w": 10, "d": 9, "style": "house", "roof": "partial", "ruin": 1.0, "doors": {"e": [[-1.0, 1.3]]}},
	{"name": "HouseWest", "w": 10, "d": 9, "style": "pale_brick", "doors": {"n": [[0.0, 1.3]]}},
	{"name": "Garage", "w": 14, "d": 12, "style": "garage", "doors": {"w": [[0.0, 4.6]]}, "bays": true},
	{"name": "Diner", "w": 12, "d": 9, "style": "diner", "roof": "partial", "ruin": 0.9, "doors": {"w": [[0.0, 1.5]]}, "front": "w"},
	{"name": "Bank", "w": 12, "d": 10, "style": "stone", "doors": {"w": [[0.0, 1.6]]}, "front": "w"},
	{"name": "FeedStore", "w": 12, "d": 10, "style": "brick", "roof": "partial", "ruin": 1.0, "doors": {"s": [[2.0, 2.4]]}, "bays": true,
		"keep": {"s": [4.4]}},
	{"name": "GasKiosk", "w": 8, "d": 6, "style": "metal", "doors": {"w": [[0.0, 1.4]]}, "front": "w"},
]

var _rng := RandomNumberGenerator.new()
var _meshes := {}
var _tris := {}
var _holes := {}
var _level: Node3D
var _stats := {}


func _initialize() -> void:
	_rng.seed = 31
	DirAccess.make_dir_recursive_absolute(RUINS)
	if OS.get_cmdline_user_args().has("measure"):
		for n in ["Brick_Window_Trim", "Brick_Window_Trim_Single", "Brick_Inset_Window", "Brick_Inset_Window_Curved", "Trim_Window",
				"Metal_Window_Half", "Metal_FullWindow", "Metal_FirstFloor_Window", "Trim_FirstFloor_Window_001", "Brick_RedWhite_DoubleWindow",
				"DoorFrame_Trim", "DoorFrame_Metal_Single"]:
			print(n, " hole ", _hole(n))
			if OS.get_cmdline_user_args().has("ascii"):
				var box := _mesh(n).get_aabb()
				var g := _Grid.new(box.position.x, box.size.x, box.end.y)
				g.draw(_triangles(n), Transform3D.IDENTITY)
				g.clean()
				for j in range(g.ny - 1, -1, -1):
					var line := ""
					for i in g.nx:
						line += "#" if g.solid(i, j) else "."
					print(line)
		quit()
		return
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	for spec: Dictionary in BUILDINGS:
		_rebuild(spec)
	_street_dressing()
	var ps := PackedScene.new()
	var err := ps.pack(_level)
	assert(err == OK)
	err = ResourceSaver.save(ps, LEVEL)
	print("saved ", LEVEL, ": ", error_string(err))
	for k in _stats:
		print("  ", k, ": ", _stats[k])
	_level.free()
	quit()


# ------------------------------------------------------------------ pieces

func _mesh(n: String) -> ArrayMesh:
	if not _meshes.has(n):
		_meshes[n] = load(KIT + n.to_snake_case() + ".res") as ArrayMesh
	return _meshes[n]


## A piece's triangles: [surface material, PackedVector3Array of corners
## (3 per triangle), PackedVector3Array normals, PackedVector2Array uvs]
func _triangles(n: String) -> Array:
	if _tris.has(n):
		return _tris[n]
	var out := []
	var m := _mesh(n)
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pu := PackedVector2Array()
		for i in idx:
			pv.append(v[i])
			pn.append(nn[i] if not nn.is_empty() else Vector3.BACK)
			pu.append(uv[i] if not uv.is_empty() else Vector2.ZERO)
		out.append([m.surface_get_material(s), pv, pn, pu])
	_tris[n] = out
	return out


## Where a piece's opening is (unscaled, piece space): [x0, x1, y0, y1],
## or [] if it's solid.
func _hole(n: String) -> Array:
	if _holes.has(n):
		return _holes[n]
	var box := _mesh(n).get_aabb()
	var g := _Grid.new(box.position.x, box.size.x, box.end.y)
	g.draw(_triangles(n), Transform3D.IDENTITY)
	g.clean()
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	for j in g.ny:
		for i in g.nx:
			var x := g.x0 + (i + 0.5) * CELL
			if g.solid(i, j) or x < box.position.x + 0.2 or x > box.end.x - 0.2:
				continue
			x0 = minf(x0, x - CELL / 2)
			x1 = maxf(x1, x + CELL / 2)
			y0 = minf(y0, j * CELL)
			y1 = maxf(y1, (j + 1) * CELL)
	_holes[n] = [] if x0 == INF else [x0, x1, y0, y1]
	return _holes[n]


# ------------------------------------------------------------- the grid

## A wall seen from outside, on a 10 cm grid: which cells are solid.
class _Grid:
	var x0: float
	var nx: int
	var ny: int
	var cells: PackedByteArray

	func _init(from: float, length: float, height: float) -> void:
		x0 = from
		nx = ceili(length / CELL - 0.001)
		ny = ceili(height / CELL - 0.001)
		cells = PackedByteArray()
		cells.resize(nx * ny)

	func solid(i: int, j: int) -> bool:
		return cells[clampi(j, 0, ny - 1) * nx + clampi(i, 0, nx - 1)] != 0

	## Draws triangles (piece space, moved by xf into wall space: x along
	## the wall, y up from the wall's foot) onto the grid
	func draw(tris: Array, xf: Transform3D) -> void:
		for surf: Array in tris:
			var pv: PackedVector3Array = surf[1]
			for t in range(0, pv.size(), 3):
				var a := xf * pv[t]
				var b := xf * pv[t + 1]
				var c := xf * pv[t + 2]
				var area := (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
				if absf(area) < 1e-6:
					continue
				var i0 := maxi(0, floori((minf(a.x, minf(b.x, c.x)) - x0) / CELL))
				var i1 := mini(nx - 1, floori((maxf(a.x, maxf(b.x, c.x)) - x0) / CELL))
				var j0 := maxi(0, floori(minf(a.y, minf(b.y, c.y)) / CELL))
				var j1 := mini(ny - 1, floori(maxf(a.y, maxf(b.y, c.y)) / CELL))
				for j in range(j0, j1 + 1):
					var py := (j + 0.5) * CELL
					for i in range(i0, i1 + 1):
						var px := x0 + (i + 0.5) * CELL
						var w0 := (b.x - px) * (c.y - py) - (c.x - px) * (b.y - py)
						var w1 := (c.x - px) * (a.y - py) - (a.x - px) * (c.y - py)
						var w2 := (a.x - px) * (b.y - py) - (b.x - px) * (a.y - py)
						if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
							cells[j * nx + i] = 1

	## Fills hairline cracks between pieces, then leaves out thin bits
	## (window bars, glazing strips): nothing under 0.3 m is solid
	func clean() -> void:
		cells = _erode(_dilate(cells))
		cells = _dilate(_erode(cells))

	func _dilate(src: PackedByteArray) -> PackedByteArray:
		var out := src.duplicate()
		for j in ny:
			for i in nx:
				if src[j * nx + i] != 0:
					continue
				for dj: int in [-1, 0, 1]:
					for di: int in [-1, 0, 1]:
						var ii := i + di
						var jj := j + dj
						if ii >= 0 and ii < nx and jj >= 0 and jj < ny and src[jj * nx + ii] != 0:
							out[j * nx + i] = 1
		return out

	func _erode(src: PackedByteArray) -> PackedByteArray:
		var out := src.duplicate()
		for j in ny:
			for i in nx:
				if src[j * nx + i] == 0:
					continue
				for dj: int in [-1, 0, 1]:
					for di: int in [-1, 0, 1]:
						# Off the grid counts as more of the same: the wall's
						# own edges aren't eaten away
						var ii := clampi(i + di, 0, nx - 1)
						var jj := clampi(j + dj, 0, ny - 1)
						if src[jj * nx + ii] == 0:
							out[j * nx + i] = 0
		return out

	func fill(fx0: float, fx1: float, fy0: float, fy1: float) -> void:
		for j in range(maxi(0, floori(fy0 / CELL)), mini(ny, ceili(fy1 / CELL - 0.001))):
			for i in range(maxi(0, floori((fx0 - x0) / CELL)), mini(nx, ceili((fx1 - x0) / CELL - 0.001))):
				cells[j * nx + i] = 1

	## Solid cells as rectangles [x0, x1, y0, y1] (wall space). Below row
	## `split`, rows of cells are merged; above it (a broken top), columns
	## `chunk` cells wide, each only as high as its lowest cell.
	func boxes(split := -1, chunk := 1) -> Array:
		if split < 0:
			split = ny
		var out := []
		var open := {}  # "i0,i1" -> index in out, for runs continuing up
		for j in split:
			var now := {}
			var i := 0
			while i < nx:
				if cells[j * nx + i] == 0:
					i += 1
					continue
				var s := i
				while i < nx and cells[j * nx + i] != 0:
					i += 1
				var key := "%d,%d" % [s, i]
				if open.has(key):
					var r: Array = out[open[key]]
					r[3] = (j + 1) * CELL
					now[key] = open[key]
				else:
					out.append([x0 + s * CELL, x0 + i * CELL, j * CELL, (j + 1) * CELL])
					now[key] = out.size() - 1
			open = now
		if split >= ny:
			return out
		# The broken top, chunk by chunk
		var runs_of := []
		for c0 in range(0, nx, chunk):
			var c1 := mini(nx, c0 + chunk)
			var runs := []
			var j := split
			while j < ny:
				var all := true
				for i in range(c0, c1):
					all = all and cells[j * nx + i] != 0
				if not all:
					j += 1
					continue
				var s := j
				while j < ny:
					var more := true
					for i in range(c0, c1):
						more = more and cells[j * nx + i] != 0
					if not more:
						break
					j += 1
				runs.append([s, j])
			runs_of.append([c0, c1, runs])
		# Neighbouring chunks the same height: one box
		var k := 0
		while k < runs_of.size():
			var e := k
			while e + 1 < runs_of.size() and str(runs_of[e + 1][2]) == str(runs_of[k][2]):
				e += 1
			for r: Array in runs_of[k][2]:
				out.append([x0 + runs_of[k][0] * CELL, x0 + runs_of[e][1] * CELL, r[0] * CELL, r[1] * CELL])
			k = e + 1
		return out


# ---------------------------------------------------------- a building

## One wall of a building: where it is and which way it faces.
## frame: wall space (x along the wall from its left end as seen from
## outside, y up, z out) -> building space.
func _side_frame(side: String, w: float, d: float) -> Transform3D:
	var o: Vector3 = {"n": Vector3.FORWARD, "s": Vector3.BACK, "w": Vector3.LEFT, "e": Vector3.RIGHT}[side]
	var x := Vector3.UP.cross(o)
	var half := (d if side in ["n", "s"] else w) / 2.0
	var length := w if side in ["n", "s"] else d
	return Transform3D(Basis(x, Vector3.UP, o), o * half - x * length / 2.0)


## A door's offset (Increment 12: from the wall's middle, along +x for n/s
## and +z for w/e) as a distance from the wall's left end
func _door_at(side: String, offset: float, length: float) -> float:
	return length / 2.0 + (offset if side in ["s", "w"] else -offset)


## The wall's pieces along its length: [[from, to, kind]], kind "wall",
## "door" or "bay"
func _layout(length: float, doors: Array, base: float, door_piece: String, bays: bool) -> Array:
	var cuts := []
	for dd: Array in doors:
		var c: float = dd[0]
		var width: float = dd[1]
		var kind := "bay" if bays else "door"
		var span := width
		if not bays:
			# The door piece scaled so its opening is at least the door's width
			var h := _hole(door_piece)
			var opening: float = h[1] - h[0]
			span = 2.0 * maxf(1.0, (width + 0.1) / opening)
		cuts.append([c - span / 2.0, c + span / 2.0, kind])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	var cursor := 0.0
	for c: Array in cuts:
		# Too little room for a piece between: the door's piece takes it
		if c[0] - cursor < 0.8 and c[0] > cursor:
			c[0] = cursor
		_fill(out, cursor, c[0], base)
		out.append(c)
		cursor = c[1]
	if length - cursor < 0.8 and not out.is_empty() and cursor < length:
		(out[-1] as Array)[1] = length
	else:
		_fill(out, cursor, length, base)
	return out


func _fill(out: Array, from: float, to: float, base: float) -> void:
	if to - from < 0.05:
		return
	var n := maxi(1, roundi((to - from) / base))
	var step := (to - from) / n
	for k in n:
		out.append([from + k * step, from + (k + 1) * step, "wall"])


func _rebuild(spec: Dictionary) -> void:
	var b := _level.get_node("Buildings/" + spec["name"]) as StaticBody3D
	var w: float = spec["w"]
	var d: float = spec["d"]
	var floors: int = spec.get("floors", 1)
	var h: float = spec.get("height", floors * FLOOR_H)
	var style: Dictionary = STYLES[spec["style"]]
	var base: float = style.get("base", 2.0)
	var ruin: float = spec.get("ruin", 0.0)
	var roof: String = spec.get("roof", "full")
	# The footprint is the one Increment 12 built: check
	var old := AABB()
	var first := true
	for c in b.get_children():
		if c is CollisionShape3D and (c.name.begins_with("Wall")):
			var bx := ((c as CollisionShape3D).shape as BoxShape3D).size
			var a := (c as CollisionShape3D).transform * AABB(-bx / 2.0, bx)
			old = a if first else old.merge(a)
			first = false
	assert(not first, spec["name"] + ": no walls found")
	assert(absf(old.size.x - w) < 0.05 and absf(old.size.z - d) < 0.05, "%s: footprint %s isn't %s x %s" % [spec["name"], old.size, w, d])
	assert(old.end.y < h + 0.05 and old.end.y > h - maxf(ruin, 0.05), "%s: height %.2f isn't %.2f" % [spec["name"], old.end.y, h])
	# Out with the old walls and parapets (meshes and solid parts)
	for c in b.get_children():
		if c.name.begins_with("Wall") or c.name.begins_with("Parapet") or c.name.begins_with("Kit") or c.name.begins_with("Corner") or c.name == "Ruins":
			b.remove_child(c)
			c.free()
	var kit := Node3D.new()
	kit.name = "Kit"
	# The building's walls: never hidden or shadowless as if they were
	# things inside it (StaticBatcher)
	kit.set_meta("shell", true)
	b.add_child(kit)
	kit.owner = _level
	# Bands: [bottom, height, name]; storeys of 3.3 m, or the church's one tall
	# wall in two (3.0 m with the windows, the rest above)
	var bands := []
	if spec.has("height"):
		bands = [[0.0, 3.0, "0"], [3.0, h - 3.0, "1"]]
	else:
		for f in floors:
			bands.append([f * FLOOR_H, FLOOR_H, str(f)])
	var ruined := ruin > 0.0 and roof != "full"
	var merger := _Merger.new()
	# Corner heights for broken tops, shared by the walls that meet there
	var corner_top := {}
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			corner_top[Vector2i(cx, cz)] = h - (_rng.randf_range(0.2, ruin) * _ruin_factor(spec, cz) if ruined else 0.0)
	var walls := 0
	var boxes := 0
	for side in ["n", "e", "s", "w"]:
		var frame := _side_frame(side, w, d)
		var length := w if side in ["n", "s"] else d
		var doors := []
		for dd: Array in (spec.get("doors", {}) as Dictionary).get(side, []):
			doors.append([_door_at(side, dd[0], length), dd[1]])
		var layout := _layout(length, doors, base, style["door"], spec.get("bays", false))
		# Plain wall where the roof ladder stands
		var plain_at := -1.0
		if spec.get("roof_access", false) and spec.get("ladder_side", "") == side:
			plain_at = _door_at(side, spec.get("ladder_at", 0.0), length)
		# The broken top (ruins): a jagged line along the wall, from one
		# corner's height to the other's
		var tops := PackedVector2Array()
		if ruined:
			var left := frame * Vector3(0, 0, 0)
			var right := frame * Vector3(length, 0, 0)
			tops.append(Vector2(0.0, corner_top[Vector2i(signi(roundi(left.x)), signi(roundi(left.z)))]))
			var x := 0.0
			var y: float = tops[0].y
			while true:
				x += _rng.randf_range(0.4, 1.1)
				if x > length - 0.3:
					break
				var at := frame * Vector3(x, 0, 0)
				var f := _ruin_factor(spec, -1 if at.z < -0.5 else 1)
				# Broken brickwork: a step up or down, or level for a bit
				var was := y
				if _rng.randf() > 0.2:
					y += _rng.randf_range(-0.5, 0.5) * minf(ruin, 1.2)
				y = clampf(y, h - ruin * f, h - 0.05)
				# Mostly a step (courses of brick broken off), sometimes crumbled
				# away at a slant
				if _rng.randf() < 0.7:
					tops.append(Vector2(x, was))
					tops.append(Vector2(x + 0.03, y))
				else:
					tops.append(Vector2(x, y))
			tops.append(Vector2(length, corner_top[Vector2i(signi(roundi(right.x)), signi(roundi(right.z)))]))
		for bi in bands.size():
			var band: Array = bands[bi]
			var y0: float = band[0]
			var bh: float = band[1]
			var top_band := bi == bands.size() - 1
			var grid := _Grid.new(0.0, length, bh)
			var wi := 0
			for k in layout.size():
				var slot: Array = layout[k]
				var from: float = slot[0]
				var to: float = slot[1]
				var kind: String = slot[2]
				var pieces := _slot_pieces(spec, style, side, bi, k, layout, kind, plain_at, from, to, bh)
				for pc: Array in pieces:
					var n: String = pc[0]
					var py: float = pc[1]
					var ph: float = pc[2]
					var box := _mesh(n).get_aabb()
					var sx := (to - from) / box.size.x
					var sy := ph / box.size.y
					var xf := Transform3D(Basis.from_scale(Vector3(sx, sy, THICK)), Vector3((from + to) / 2.0 - box.get_center().x * sx, py - box.position.y * sy, 0.0))
					var tris := _triangles(n)
					var cut := ruined and top_band and py + ph > bh - 0.01
					if cut:
						# The broken top, across this piece: never down into its
						# window or doorway, and leaving some of a lintel
						var low := py + 0.15
						# Over a doorway and where a sign hangs, the wall's barely broken
						if kind != "wall":
							low = maxf(low, bh - 0.05)
						for at: float in (spec.get("keep", {}) as Dictionary).get(side, []):
							var x := _door_at(side, at, length)
							if x > from - 0.8 and x < to + 0.8:
								low = maxf(low, bh - 0.05)
						var hole := _hole(n)
						if not hole.is_empty():
							low = maxf(low, py + (hole[3] - box.position.y) * sy + 0.25)
						var pts := PackedVector2Array()
						pts.append(Vector2(from, _top_at(tops, from)))
						for t in tops:
							if t.x > from + 0.05 and t.x < to - 0.05:
								pts.append(t)
						pts.append(Vector2(to, _top_at(tops, to)))
						for i in pts.size():
							pts[i].y = maxf(pts[i].y - y0, low)
						tris = _clip(tris, xf, pts)
						merger.add(tris, frame * Transform3D(Basis(), Vector3(0, y0, 0)) * xf)
					else:
						var mi := MeshInstance3D.new()
						mi.name = "%s%s%d_%d" % [n.get_slice("_", 0), side.to_upper(), bi, wi]
						mi.mesh = _mesh(n)
						mi.transform = frame * Transform3D(Basis(), Vector3(0, y0, 0)) * xf
						kit.add_child(mi)
						mi.owner = _level
					wi += 1
					grid.draw(tris, xf)
			# Parts that stand out from the wall (cornices) aren't drawn on the grid
			grid.clean()
			if bi == 0:
				for k in layout.size():
					if layout[k][2] == "wall":
						_board_up(kit, grid, frame, side, k, layout[k][0], layout[k][1])
			var split := -1
			if ruined and top_band:
				var lowest := INF
				for t in tops:
					lowest = minf(lowest, t.y)
				split = clampi(floori((lowest - y0) / CELL) - 1, 0, grid.ny)
			for r: Array in grid.boxes(split, 4):
				var cs := CollisionShape3D.new()
				cs.name = "Wall%s%s_%dCol" % [side.to_upper(), band[2], boxes]
				var sh := BoxShape3D.new()
				sh.size = Vector3(r[1] - r[0], r[3] - r[2], T)
				cs.shape = sh
				cs.transform = frame * Transform3D(Basis(), Vector3((r[0] + r[1]) / 2.0, y0 + (r[2] + r[3]) / 2.0, -T / 2.0))
				b.add_child(cs)
				cs.owner = _level
				boxes += 1
			walls += wi
		# Cornice along the top of a roofed building
		if style.has("cornice") and roof == "full" and not spec.get("roof_access", false):
			for k in layout.size():
				_cornice(kit, style["cornice"], frame, layout[k][0], layout[k][1], h, side, k)
		# Roof access: a parapet round the roof, open where the ladder comes up
		if spec.get("roof_access", false):
			_parapet(b, kit, style, frame, side, length, h, spec, plain_at)
	# Corner columns
	var ci := 0
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var top: float = corner_top[Vector2i(cx, cz)]
			if spec.get("roof_access", false):
				top = h + 1.02
			var at := Vector3(cx * w / 2.0, 0, cz * d / 2.0)
			_column(b, kit, merger, style["column"], at, top, h, ruined, ci)
			ci += 1
	if ruined:
		var mesh := merger.commit()
		var path := RUINS + (spec["name"] as String).to_snake_case() + "_broken_walls.res"
		assert(ResourceSaver.save(mesh, path) == OK)
		var mi := MeshInstance3D.new()
		mi.name = "BrokenWalls"
		mi.mesh = load(path)
		kit.add_child(mi)
		mi.owner = _level
	_stats[spec["name"]] = "%d wall pieces, %d solid boxes" % [walls, boxes]


## Boards nailed over the low part of a ground-floor window (and solid)
func _board_up(kit: Node3D, grid: _Grid, frame: Transform3D, side: String, k: int, from: float, to: float) -> void:
	var ox0 := INF
	var ox1 := -INF
	var oy0 := INF
	var top := ceili(BOARD_TOP / CELL)
	for j in mini(top, grid.ny):
		for i in grid.nx:
			var x := (i + 0.5) * CELL
			if x < from + 0.15 or x > to - 0.15 or grid.solid(i, j):
				continue
			ox0 = minf(ox0, i * CELL)
			ox1 = maxf(ox1, (i + 1) * CELL)
			oy0 = minf(oy0, j * CELL)
	if ox0 == INF:
		return
	grid.fill(ox0, ox1, 0.0, top * CELL)
	var y := maxf(oy0, 0.05) + 0.1
	var p := 0
	while y < BOARD_TOP + 0.05:
		var mi := MeshInstance3D.new()
		mi.name = "Boards%s_%d_%d" % [side.to_upper(), k, p]
		var bm := BoxMesh.new()
		bm.size = Vector3(ox1 - ox0 + 0.2, 0.17, 0.035)
		mi.mesh = bm
		mi.material_override = load(WOOD_CHARRED if _rng.randf() < 0.3 else WOOD)
		mi.transform = frame * Transform3D(Basis(Vector3.BACK, deg_to_rad(_rng.randf_range(-5, 5))),
			Vector3((ox0 + ox1) / 2.0 + _rng.randf_range(-0.05, 0.05), y, 0.11))
		kit.add_child(mi)
		mi.owner = _level
		y += _rng.randf_range(0.22, 0.3)
		p += 1


## How broken a wall top can be where it holds up what's left of a roof
## (partial roofs cover the north side): a little
func _ruin_factor(spec: Dictionary, z_sign: int) -> float:
	if spec.get("roof", "full") == "partial" and z_sign < 0:
		return 0.25
	return 1.0


## The kit pieces for one slot of one band: [[piece, bottom, height]]
func _slot_pieces(spec: Dictionary, style: Dictionary, side: String, band: int, k: int, layout: Array, kind: String,
		plain_at: float, from: float, to: float, bh: float) -> Array:
	var upper := band > 0
	var wall: String = style.get("upper_wall", style["wall"]) if upper else style["wall"]
	var window: String = style.get("upper_window", style["window"]) if upper else style["window"]
	if kind == "door" and not upper:
		# A doorway as high as the old ones, with a band of wall over it for a
		# shop's sign; or the doorway the full height
		if style.has("lintel") and bh - DOOR_FASCIA > 0.4:
			return [[style["door"], 0.0, DOOR_FASCIA], [style["lintel"], DOOR_FASCIA, bh - DOOR_FASCIA]]
		return [[style["door"], 0.0, bh]]
	if kind == "bay" and not upper:
		return [[style.get("lintel", wall), DOOR_TOP, bh - DOOR_TOP]]
	if plain_at >= 0.0 and plain_at > from - 0.6 and plain_at < to + 0.6:
		return [[wall, 0.0, bh]]
	# Street fronts: shop windows all along the ground floor, with plain wall
	# at the corners
	if not upper and spec.get("front", "") == side and style.has("shop"):
		if layout.size() >= 5 and (k == 0 or k == layout.size() - 1):
			return [[wall, 0.0, bh]]
		return [[style["shop"], 0.0, bh]]
	# Elsewhere every other piece is a window, never at the corners, the
	# same from either end
	var from_end := mini(k, layout.size() - 1 - k)
	var window_here := from_end % 2 == 1 or layout.size() <= 2
	return [[window if window_here else wall, 0.0, bh]]


func _cornice(kit: Node3D, n: String, frame: Transform3D, from: float, to: float, h: float, side: String, k: int) -> void:
	var box := _mesh(n).get_aabb()
	var sx := (to - from) / box.size.x
	var mi := MeshInstance3D.new()
	mi.name = "Cornice%s_%d" % [side.to_upper(), k]
	mi.mesh = _mesh(n)
	# Its top 0.25 m over the roof's edge
	mi.transform = frame * Transform3D(Basis.from_scale(Vector3(sx, 1.0, 1.0)),
		Vector3((from + to) / 2.0 - box.get_center().x * sx, h + 0.25 - box.end.y, -box.end.z + 0.02))
	kit.add_child(mi)
	mi.owner = _level


func _parapet(b: StaticBody3D, kit: Node3D, style: Dictionary, frame: Transform3D, side: String, length: float, h: float,
		spec: Dictionary, gap_at: float) -> void:
	var n: String = style.get("parapet", style["wall"])
	var y0 := h + 0.12
	var ph := 0.9
	var runs := []
	if gap_at >= 0.0:
		runs = [[0.0, gap_at - 0.5], [gap_at + 0.5, length]]
	else:
		runs = [[0.0, length]]
	var grid := _Grid.new(0.0, length, ph)
	var i := 0
	for r: Array in runs:
		var segs := []
		_fill(segs, r[0], r[1], 2.0)
		for s: Array in segs:
			var box := _mesh(n).get_aabb()
			var sx: float = (s[1] - s[0]) / box.size.x
			var sy := ph / box.size.y
			var xf := Transform3D(Basis.from_scale(Vector3(sx, sy, THICK)), Vector3((s[0] + s[1]) / 2.0 - box.get_center().x * sx, -box.position.y * sy, 0.0))
			var mi := MeshInstance3D.new()
			mi.name = "Parapet%s_%d" % [side.to_upper(), i]
			mi.mesh = _mesh(n)
			mi.transform = frame * Transform3D(Basis(), Vector3(0, y0, 0)) * xf
			kit.add_child(mi)
			mi.owner = _level
			grid.draw(_triangles(n), xf)
			i += 1
	grid.clean()
	var bi := 0
	for r: Array in grid.boxes():
		var cs := CollisionShape3D.new()
		cs.name = "Parapet%s_%dCol" % [side.to_upper(), bi]
		var sh := BoxShape3D.new()
		sh.size = Vector3(r[1] - r[0], r[3] - r[2], T)
		cs.shape = sh
		cs.transform = frame * Transform3D(Basis(), Vector3((r[0] + r[1]) / 2.0, y0 + (r[2] + r[3]) / 2.0, -T / 2.0))
		b.add_child(cs)
		cs.owner = _level
		bi += 1


## A column at a corner, from the ground to `top`, solid
func _column(b: StaticBody3D, kit: Node3D, merger: _Merger, n: String, at: Vector3, top: float, h: float, ruined: bool, i: int) -> void:
	var box := _mesh(n).get_aabb()
	var xf := Transform3D(Basis.from_scale(Vector3(1, top / box.size.y, 1)), at - Vector3(box.get_center().x, box.position.y * top / box.size.y, box.get_center().z))
	if ruined:
		merger.add(_triangles(n), xf)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "Corner%d" % i
		mi.mesh = _mesh(n)
		mi.transform = xf
		kit.add_child(mi)
		mi.owner = _level
	var cs := CollisionShape3D.new()
	cs.name = "Corner%dCol" % i
	var sh := BoxShape3D.new()
	sh.size = Vector3(box.size.x, top, box.size.z) * 0.9
	cs.shape = sh
	cs.position = at + Vector3(0, top / 2.0, 0)
	b.add_child(cs)
	cs.owner = _level


# ------------------------------------------------------------ the street

## The kit's street furniture: manhole covers and drains in the road, air
## conditioners on the flat roofs, planters either side of the hotel's and
## the bank's doors (solid, like the cars).
func _street_dressing() -> void:
	var street := _level.get_node("Street")
	var old := street.get_node_or_null("KitDressing")
	if old != null:
		street.remove_child(old)
		old.free()
	var body := StaticBody3D.new()
	body.name = "KitDressing"
	body.collision_layer = PhysicsLayers.STRUCTURES
	body.collision_mask = 0
	street.add_child(body)
	body.owner = _level
	var i := 0
	for at in [Vector3(0.8, 0.012, -52), Vector3(-0.8, 0.012, -9), Vector3(0.6, 0.012, 33), Vector3(-30, 0.012, 0.7), Vector3(26, 0.012, -0.6)]:
		_prop(body, "Prop_ManholeCover", "Manhole%d" % i, at, _rng.randf_range(0, 360))
		i += 1
	i = 0
	for at in [Vector3(-4.3, 0.012, -66), Vector3(4.3, 0.012, -44), Vector3(-4.3, 0.012, -30), Vector3(4.3, 0.012, -12), Vector3(-4.3, 0.012, 14), Vector3(4.3, 0.012, 40)]:
		_prop(body, "Prop_Drain", "Drain%d" % i, at, 0.0)
		i += 1
	# On the roofs (the hotel's roof, which you can climb onto, stays clear)
	i = 0
	for spec in [["GeneralStore", Vector3(-2, 0, 2), 90.0], ["Clinic", Vector3(3, 0, -2), 0.0], ["Bank", Vector3(-3, 0, 2.5), 180.0],
			["Bank", Vector3(1, 0, 2.5), 180.0], ["Garage", Vector3(3, 0, -3), 0.0], ["HouseWest", Vector3(-2, 0, 1), 90.0]]:
		var b := _level.get_node("Buildings/" + spec[0]) as Node3D
		var top := FLOOR_H + 0.12
		_prop(body, "Prop_ACUnit", "AirCon%d" % i, b.position + (spec[1] as Vector3) + Vector3(0, top, 0), spec[2])
		i += 1
	# Planters by the doors
	i = 0
	for at in [Vector3(-6.6, 0, -25.5), Vector3(-6.6, 0, -18.5), Vector3(6.6, 0, -24.5), Vector3(6.6, 0, -17.5)]:
		_prop(body, "Prop_Planter_Single", "Planter%d" % i, at, 0.0, 0.75)
		var cs := CollisionShape3D.new()
		cs.name = "Planter%dCol" % i
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.5, 0.45, 1.5)
		cs.shape = sh
		cs.position = at + Vector3(0, 0.225, 0)
		body.add_child(cs)
		cs.owner = _level
		i += 1


func _prop(parent: Node3D, n: String, name: String, at: Vector3, yaw_deg: float, scale := 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _mesh(n)
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale), at)
	parent.add_child(mi)
	mi.owner = _level


# ------------------------------------------------------------ broken tops

## The broken top's height (above the ground) at x along a wall
func _top_at(tops: PackedVector2Array, x: float) -> float:
	for i in tops.size() - 1:
		if x <= tops[i + 1].x:
			var u := clampf((x - tops[i].x) / maxf(tops[i + 1].x - tops[i].x, 0.001), 0.0, 1.0)
			return lerpf(tops[i].y, tops[i + 1].y, u)
	return tops[-1].y


## A piece's triangles cut off above a jagged line (pts: wall space, x
## along the wall, y up from the band's foot; xf: piece -> wall space), the
## cut capped.
func _clip(tris: Array, xf: Transform3D, pts: PackedVector2Array) -> Array:
	var sx := xf.basis.x.x
	var sy := xf.basis.y.y
	var cx := xf.origin.x
	var y0 := xf.origin.y
	var zmin := INF
	var zmax := -INF
	var ytop := -INF
	for surf: Array in tris:
		for v: Vector3 in surf[1]:
			zmin = minf(zmin, v.z)
			zmax = maxf(zmax, v.z)
			ytop = maxf(ytop, v.y)
	zmin = maxf(zmin, -0.2)
	zmax = minf(zmax, 0.0)
	var out := []
	var caps := []
	for i in pts.size() - 1:
		var xa := pts[i].x
		var xb := pts[i + 1].x
		var ya := pts[i].y
		var yb := pts[i + 1].y
		var k := (yb - ya) / maxf(xb - xa, 0.001)
		# This strip of the piece (piece space), below the line
		var strip := _cut(tris, 1.0, 0.0, -(xa - cx) / sx)
		strip = _cut(strip, -1.0, 0.0, (xb - cx) / sx)
		strip = _cut(strip, k * sx, -sy, ya + k * (cx - xa) - y0)
		out.append_array(strip)
		# The cap along the cut
		var la := Vector2((xa - cx) / sx, (ya - y0) / sy)
		var lb := Vector2((xb - cx) / sx, (yb - y0) / sy)
		if la.y < ytop - 0.01 or lb.y < ytop - 0.01:
			var up := Vector3(-(lb.y - la.y), lb.x - la.x, 0).normalized()
			caps.append_array([Vector3(la.x, la.y, zmax), Vector3(lb.x, lb.y, zmax), Vector3(lb.x, lb.y, zmin),
				Vector3(la.x, la.y, zmax), Vector3(lb.x, lb.y, zmin), Vector3(la.x, la.y, zmin)])
	if not caps.is_empty() and not tris.is_empty():
		var cn := PackedVector3Array()
		var cu := PackedVector2Array()
		for i in range(0, caps.size(), 6):
			var e := (caps[i] as Vector3) - (caps[i + 2] as Vector3)
			var nrm := Vector3(-((caps[i + 1] as Vector3).y - (caps[i] as Vector3).y), (caps[i + 1] as Vector3).x - (caps[i] as Vector3).x, 0).normalized()
			for c in 6:
				cn.append(nrm)
			var len := ((caps[i + 1] as Vector3) - (caps[i] as Vector3)).length()
			cu.append_array([Vector2(0, 0), Vector2(len, 0), Vector2(len, e.length()), Vector2(0, 0), Vector2(len, e.length()), Vector2(0, e.length())])
		out.append([(tris[0] as Array)[0], PackedVector3Array(caps), cn, cu])
	return out


## Triangles cut to the side of a line where a x + b y + c >= 0 (piece space)
func _cut(tris: Array, a: float, b: float, c: float) -> Array:
	var out := []
	for surf: Array in tris:
		var pv: PackedVector3Array = surf[1]
		var pn: PackedVector3Array = surf[2]
		var pu: PackedVector2Array = surf[3]
		var ov := PackedVector3Array()
		var on := PackedVector3Array()
		var ou := PackedVector2Array()
		for t in range(0, pv.size(), 3):
			var kept := []
			for e in 3:
				var p := t + e
				var q := t + (e + 1) % 3
				var fp := a * pv[p].x + b * pv[p].y + c
				var fq := a * pv[q].x + b * pv[q].y + c
				if fp >= 0.0:
					kept.append([pv[p], pn[p], pu[p]])
				if (fp >= 0.0) != (fq >= 0.0):
					var u := fp / (fp - fq)
					kept.append([pv[p].lerp(pv[q], u), pn[p].lerp(pn[q], u).normalized(), pu[p].lerp(pu[q], u)])
			for e in range(1, kept.size() - 1):
				for v: Array in [kept[0], kept[e], kept[e + 1]]:
					ov.append(v[0])
					on.append(v[1])
					ou.append(v[2])
		if not ov.is_empty():
			out.append([surf[0], ov, on, ou])
	return out


## Pieces gathered into one mesh, one surface per material
class _Merger:
	var _parts := {}  # material -> SurfaceTool

	func add(tris: Array, xf: Transform3D) -> void:
		var nb := xf.basis.inverse().transposed()
		for surf: Array in tris:
			var m: Material = surf[0]
			if not _parts.has(m):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(m)
				_parts[m] = st
			var st: SurfaceTool = _parts[m]
			var pv: PackedVector3Array = surf[1]
			var pn: PackedVector3Array = surf[2]
			var pu: PackedVector2Array = surf[3]
			for i in pv.size():
				st.set_normal((nb * pn[i]).normalized())
				st.set_uv(pu[i])
				st.add_vertex(xf * pv[i])

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for m: Material in _parts:
			var st: SurfaceTool = _parts[m]
			st.index()
			st.generate_tangents()
			st.commit(mesh)
		return mesh
