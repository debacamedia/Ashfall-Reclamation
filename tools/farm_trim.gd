extends RefCounted
## Increment 31: farm buildings in the style of Quaternius's Farm Buildings
## pack (CC0): red board-and-batten barns and white lap-sided farmhouses,
## white trim at every corner, eave and opening, sliding barn doors with
## white X braces, hayloft doors in the gables, and shingled roofs.
##
## Used by tools/site_kit.gd when a building has a "trim" option: "barn" or
## "farmhouse". It only adds to what you see: the walls, doorways, windows,
## floors and roof stay the solid shapes they were. The detail is one mesh
## per building (saved next to the scene) so it costs a few draw calls.

const WALL_T := 0.3
const DOOR := Vector2(1.6, 2.4)
const WIDE := Vector2(4.0, 4.0)
const WINDOW := Vector2(1.2, 1.2)
const SILL := 1.0

const M := "res://assets/materials/farm/"
const STYLES := {
	"barn": {"wall": "farm_red", "battens": "farm_red_dark", "trim": "farm_white", "roof": "farm_shingle"},
	"farmhouse": {"wall": "farm_siding", "siding": "farm_siding", "trim": "farm_white", "roof": "farm_shingle", "shutters": "farm_shutter"},
}

var _st := {}  # material path -> SurfaceTool


static func dress(b: StaticBody3D, size: Vector2, h: float, storeys: int, openings: Array, opts: Dictionary, path: String) -> MeshInstance3D:
	var t := new()
	return t._dress(b, size, h, storeys, openings, opts, path)


func _mat(key: String) -> Material:
	return load(M + key + ".tres")


func _dress(b: StaticBody3D, size: Vector2, h: float, storeys: int, openings: Array, opts: Dictionary, path: String) -> MeshInstance3D:
	var style: Dictionary = STYLES[opts["trim"]]
	var top := storeys * h
	# Paint: the walls, and shingles on the roof
	for c in b.get_children():
		if c is MeshInstance3D and (c.name.begins_with("Wall") or c.name.begins_with("Parapet")):
			(c as MeshInstance3D).material_override = _mat(style["wall"])
		if c is MeshInstance3D and c.name == "Roof" and opts.get("roof", "flat") == "pitched":
			(c as MeshInstance3D).material_override = _mat(style["roof"])
	for side in ["N", "S", "W", "E"]:
		var ops := openings.filter(func(o: Array) -> bool: return o[0] == side)
		var length := size.x if side in ["N", "S"] else size.y
		# The opening spans on this side: [from, to, bottom, top, kind]
		var spans := []
		for o: Array in ops:
			var y0: float = (o[3] if o.size() > 3 else 0) * h
			var sz := _opening(o[2])
			var bottom := y0 + (SILL if o[2] == "window" else 0.0)
			spans.append([float(o[1]) - sz.x / 2.0, float(o[1]) + sz.x / 2.0, bottom, bottom + sz.y, o[2]])
		# Corner boards, base and eave boards
		for e: float in [-1.0, 1.0]:
			_board(side, size, e * (length / 2.0 - 0.11), 0.0, top, 0.22, 0.045, 0.0, style["trim"])
		_run(side, size, length, spans, 0.0, 0.25, 0.05, style["trim"], true)
		_run(side, size, length, [], top - 0.3, top, 0.05, style["trim"], false)
		# The walls' boards
		if style.has("battens"):
			var a := -length / 2.0 + 0.5
			while a < length / 2.0 - 0.4:
				_cut_vertical(side, size, a, 0.25, top - 0.3, 0.07, 0.035, spans, style["battens"])
				a += 0.6
		if style.has("siding"):
			var y := 0.25
			while y < top - 0.35:
				_siding_row(side, size, length, y, minf(y + 0.3, top - 0.3), spans, style["siding"])
				y += 0.26
		# Frames round doors and windows, shutters, barn doors
		for sp: Array in spans:
			var w: float = sp[1] - sp[0]
			var mid: float = (sp[0] + sp[1]) / 2.0
			var fw := 0.2 if sp[4] == "wide" else 0.13
			for e: float in [-1.0, 1.0]:
				_board(side, size, mid + e * (w / 2.0 + fw / 2.0), sp[2] - (0.08 if sp[4] == "window" else 0.0), sp[3] + fw, fw, 0.06, 0.0, style["trim"])
			_board(side, size, mid, sp[3], sp[3] + fw, w + 2.0 * fw, 0.06, 0.0, style["trim"])
			if sp[4] == "window":
				_board(side, size, mid, sp[2] - 0.1, sp[2], w + 0.36, 0.12, 0.0, style["trim"])
				if style.has("shutters"):
					for e: float in [-1.0, 1.0]:
						var sx := mid + e * (w / 2.0 + fw + 0.3)
						if absf(sx) < length / 2.0 - 0.5:
							_board(side, size, sx, sp[2], sp[3], 0.5, 0.04, 0.0, style["shutters"])
							for k in 4:
								var ly: float = sp[2] + 0.15 + k * (sp[3] - sp[2] - 0.3) / 3.0
								_board(side, size, sx, ly - 0.02, ly + 0.02, 0.5, 0.06, 0.0, style["shutters"])
			if sp[4] == "wide" and style.has("battens"):
				_barn_doors(side, size, length, sp, style)
	if opts.get("roof", "flat") == "pitched":
		_roof(size, top, float(opts.get("pitch", 2.2)), style, opts.get("trim") == "barn")
	var mesh := ArrayMesh.new()
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		st.index()
		st.generate_tangents()
		st.commit(mesh)
	var err := ResourceSaver.save(mesh, path)
	assert(err == OK, "save " + path)
	var mi := MeshInstance3D.new()
	mi.name = "FarmTrim"
	mi.mesh = load(path)
	b.add_child(mi)
	return mi


func _opening(kind: String) -> Vector2:
	return DOOR if kind == "door" else (WIDE if kind == "wide" else WINDOW)


## A wall's frame: x along the wall, y up, z out of the building, at the
## wall's outer face. (On the N and E walls x runs against the openings'
## offsets: _on() turns them round.)
func _frame(side: String, size: Vector2) -> Transform3D:
	match side:
		"N": return Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(0, 0, -size.y / 2.0))
		"S": return Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), Vector3(0, 0, size.y / 2.0))
		"W": return Transform3D(Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT), Vector3(-size.x / 2.0, 0, 0))
		_: return Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), Vector3(size.x / 2.0, 0, 0))


## A point `a` along a wall (as the openings' offsets run), y up, z out
func _on(side: String, size: Vector2, a: float, y: float, z: float) -> Transform3D:
	var sgn := -1.0 if side in ["N", "E"] else 1.0
	var f := _frame(side, size)
	return Transform3D(f.basis, f * Vector3(sgn * a, y, z))


## A flat board on a wall: centred at `a` along it, from y0 to y1, `w` wide,
## `t` thick (standing out from the wall), tilted by `tilt` (radians, its
## foot out from the wall)
func _board(side: String, size: Vector2, a: float, y0: float, y1: float, w: float, t: float, tilt: float, key: String) -> void:
	if y1 - y0 < 0.01 or w < 0.01:
		return
	var at := _on(side, size, a, (y0 + y1) / 2.0, t / 2.0 + 0.005)
	_box(Transform3D(at.basis * Basis(Vector3.RIGHT, tilt), at.origin), Vector3(w, y1 - y0, t), key)


## A horizontal board along the wall from y0 to y1, broken where `spans`
## cut it (doorways only, when `doors_only`)
func _run(side: String, size: Vector2, length: float, spans: Array, y0: float, y1: float, t: float, key: String, doors_only: bool) -> void:
	var from := -length / 2.0
	var cuts := spans.filter(func(sp: Array) -> bool: return (not doors_only or sp[4] != "window") and sp[2] < y1 and sp[3] > y0)
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for sp: Array in cuts:
		_board(side, size, (from + sp[0]) / 2.0, y0, y1, sp[0] - from, t, 0.0, key)
		from = sp[1]
	_board(side, size, (from + length / 2.0) / 2.0, y0, y1, length / 2.0 - from, t, 0.0, key)


## A vertical batten, broken round openings
func _cut_vertical(side: String, size: Vector2, a: float, y0: float, y1: float, w: float, t: float, spans: Array, key: String) -> void:
	var lo := y0
	var cuts := spans.filter(func(sp: Array) -> bool: return a > sp[0] - 0.3 and a < sp[1] + 0.3)
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[2] < q[2])
	for sp: Array in cuts:
		_board(side, size, a, lo, minf(sp[2] - 0.12, y1), w, t, 0.0, key)
		lo = maxf(lo, sp[3] + 0.25)
	_board(side, size, a, lo, y1, w, t, 0.0, key)


## One row of lap siding: a board tilted out at its foot, broken round
## openings
func _siding_row(side: String, size: Vector2, length: float, y0: float, y1: float, spans: Array, key: String) -> void:
	var from := -length / 2.0 + 0.22
	var to := length / 2.0 - 0.22
	var cuts := spans.filter(func(sp: Array) -> bool: return sp[2] < y1 and sp[3] > y0)
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for sp: Array in cuts:
		var e: float = sp[0] - 0.13
		if e > from:
			_board(side, size, (from + e) / 2.0, y0, y1, e - from, 0.025, -0.07, key)
		from = maxf(from, sp[1] + 0.13)
	if to > from:
		_board(side, size, (from + to) / 2.0, y0, y1, to - from, 0.025, -0.07, key)


## A wide doorway's sliding doors, slid open either side of it on their
## rail: red boards, white frames, white X braces
func _barn_doors(side: String, size: Vector2, length: float, sp: Array, style: Dictionary) -> void:
	var w: float = (sp[1] - sp[0]) / 2.0
	var dh: float = sp[3] - sp[2]
	for e: float in [-1.0, 1.0]:
		var mid: float = (sp[0] + sp[1]) / 2.0 + e * ((sp[1] - sp[0]) / 2.0 + 0.2 + w / 2.0)
		if absf(mid) + w / 2.0 > length / 2.0 - 0.2:
			continue
		var z := 0.12
		_box(_on(side, size, mid, sp[2] + dh / 2.0, z), Vector3(w, dh, 0.06), style["wall"])
		for edge: Array in [[0.0, dh / 2.0 - 0.07, w, 0.14], [0.0, -dh / 2.0 + 0.07, w, 0.14], [-w / 2.0 + 0.07, 0.0, 0.14, dh], [w / 2.0 - 0.07, 0.0, 0.14, dh], [0.0, 0.0, w, 0.12]]:
			_box(_on(side, size, mid + edge[0], sp[2] + dh / 2.0 + edge[1], z + 0.04), Vector3(edge[2], edge[3], 0.03), style["trim"])
		# An X in each half
		for half: float in [-1.0, 1.0]:
			var hh := dh / 2.0 - 0.14
			var cy: float = sp[2] + dh / 2.0 + half * (hh / 2.0 + 0.03)
			var diag := sqrt((w - 0.28) * (w - 0.28) + hh * hh)
			var ang := atan2(hh, w - 0.28)
			for s: float in [-1.0, 1.0]:
				var at := _on(side, size, mid, cy, z + 0.045)
				_box(Transform3D(at.basis * Basis(Vector3.BACK, s * ang), at.origin), Vector3(diag, 0.11, 0.03), style["trim"])
	# The rail the doors hang from
	_box(_on(side, size, (sp[0] + sp[1]) / 2.0, sp[3] + 0.32, 0.12), Vector3(minf((sp[1] - sp[0]) * 2.2, length - 0.6), 0.1, 0.08), "farm_shingle")


## Shingles in overlapping rows down both slopes, a ridge cap, the gables
## boarded in, and (on a barn) a hayloft door high in each gable
func _roof(size: Vector2, top: float, pitch: float, style: Dictionary, barn: bool) -> void:
	var ridge_z := size.y >= size.x
	var span := (size.x if ridge_z else size.y) + 0.6
	var length := (size.y if ridge_z else size.x) + 0.6
	var base := top + 0.12
	# The roof's frame: x across the ridge, y up, z along it
	var rf := Transform3D(Basis() if ridge_z else Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	var slope_len := sqrt(span * span / 4.0 + pitch * pitch)
	var ang := atan2(pitch, span / 2.0)
	for e: float in [-1.0, 1.0]:
		# Down-slope direction and outward normal of this side
		var down := Vector3(e * cos(ang), -sin(ang), 0)
		var up_n := Vector3(e * sin(ang), cos(ang), 0)
		var ridge := Vector3(0, base + pitch, 0)
		var d := 0.15
		while d < slope_len:
			var row := minf(0.45, slope_len - d + 0.1)
			var c := ridge + down * (d + row / 2.0) + up_n * 0.03
			var basis := Basis(Vector3.BACK, e * -ang) * Basis(Vector3.RIGHT, 0.0)
			# Each row's lower edge lifted a little: the shingles' step
			var tilt := Basis(Vector3.BACK, e * -0.06)
			_box(rf * Transform3D(basis * tilt, c), Vector3(row, 0.04, length + 0.04), style["roof"])
			d += 0.38
	_box(rf * Transform3D(Basis(), Vector3(0, base + pitch + 0.04, 0)), Vector3(0.32, 0.12, length + 0.1), style["roof"])
	# Gables
	for e: float in [-1.0, 1.0]:
		var gz := e * (length / 2.0 + 0.012)
		_gable(rf, span - 0.5, pitch * (span - 0.5) / span, base, gz, e, style["wall"])
		# Rake boards up the gable's edges
		for s: float in [-1.0, 1.0]:
			var c := Vector3(s * span / 4.0, base + pitch / 2.0, e * (length / 2.0 + 0.035))
			_box(rf * Transform3D(Basis(Vector3.BACK, -s * ang), c), Vector3(slope_len, 0.18, 0.04), style["trim"])
		if barn and pitch >= 2.4:
			var hw := 1.5
			var y0 := base + 0.25
			var y1 := base + minf(pitch - 0.5, 2.2)
			var z := e * (length / 2.0 + 0.05)
			var mid := Vector3(0, (y0 + y1) / 2.0, z)
			_box(rf * Transform3D(Basis(), mid), Vector3(hw, y1 - y0, 0.03), style["wall"])
			for edge: Array in [[0.0, (y1 - y0) / 2.0, hw + 0.2, 0.12], [0.0, -(y1 - y0) / 2.0, hw + 0.2, 0.12], [-hw / 2.0, 0.0, 0.12, y1 - y0], [hw / 2.0, 0.0, 0.12, y1 - y0]]:
				_box(rf * Transform3D(Basis(), mid + Vector3(edge[0], edge[1], e * 0.02)), Vector3(edge[2], edge[3], 0.03), style["trim"])
			var diag := sqrt(hw * hw + (y1 - y0) * (y1 - y0)) - 0.15
			var da := atan2(y1 - y0, hw)
			for s: float in [-1.0, 1.0]:
				_box(rf * Transform3D(Basis(Vector3.BACK, s * da), mid + Vector3(0, 0, e * 0.025)), Vector3(diag, 0.1, 0.03), style["trim"])


## A gable's triangle of boarding, just outside the roof's end
func _gable(rf: Transform3D, w: float, hgt: float, base: float, z: float, e: float, key: String) -> void:
	var st := _tool(key)
	var n := rf.basis * Vector3(0, 0, e)
	var pts := [Vector3(-w / 2.0, base, z), Vector3(w / 2.0, base, z), Vector3(0, base + hgt, z)]
	# (Clockwise, seen from outside)
	if e > 0:
		pts = [pts[1], pts[0], pts[2]]
	for p: Vector3 in pts:
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.y))
		st.add_vertex(rf * p)


func _tool(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_mat(key))
		_st[key] = st
	return _st[key]


## A box (size, at xf) into the material's surface
func _box(xf: Transform3D, s: Vector3, key: String) -> void:
	var st := _tool(key)
	var h := s / 2.0
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var q := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		var nn := (xf.basis.inverse().transposed() * n).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nn)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(xf * (q[i] as Vector3))
