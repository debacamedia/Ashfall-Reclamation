class_name StaticBatcher
extends RefCounted
## Makes a site cheap to draw, when the zone loads (Increment 16.5):
##
## 1. **Interiors.** Small things inside a building (furniture, loot,
##    containers, lamps) are only drawn within INTERIOR_RANGE and cast no
##    sun shadow: you can't see into a building from further off, and the
##    sun doesn't reach inside.
## 2. **Merging.** The plain meshes that make up buildings, walls and fixed
##    dressing are merged into one mesh per material (and size class, and
##    48 m cell), so a building is a handful of draw calls instead of dozens.
##    Collision is untouched: only the visible meshes are combined.
## 3. **Tiny things** (under 0.5 m) cast no sun shadow.
## 4. **Occluders.** Each building's walls, floors and roofs hide what's
##    behind them (occlusion culling), so a street of buildings doesn't draw
##    the rooms and streets beyond. Made from the walls' collision boxes,
##    shrunk a little, so they never hide something you can actually see.
##
## Props you can move or scrap and salvage piles keep their own node (so
## moving, scrapping and breaking down work as before), but their pieces are
## merged inside them.
##
## Never merged: anything with a script on it or above it in the site (beyond
## those props: containers, pickups, ladders, gates, raiders),
## anything saved, anything with children, transparent or shader materials,
## mirrored meshes, and meshes that already have a draw distance (terrain,
## rocks, crops). The scene files are unchanged, so they stay editable.

const INTERIOR_RANGE := 70.0
const CELL := 48.0
const NO_SHADOW_BELOW := 0.5

## What batch() did, for tests and the benchmark.
class Stats:
	var merged_from := 0
	var merged_into := 0
	var interior := 0
	var no_shadow := 0
	var occluders := 0
	var props_merged := 0


static func batch(site: Node3D) -> Stats:
	var st := Stats.new()
	var shells := building_shells(site)
	_mark_interiors(site, shells, st)
	_merge(site, st)
	_add_occluders(site, st)
	return st


## The boxes (site space) that roofed buildings enclose: each body under
## Buildings, from its meshes. [Array of [AABB, min footprint side]]
static func building_shells(site: Node3D, roofed_only := true) -> Array:
	var out := []
	var group := site.get_node_or_null("Buildings")
	if group == null:
		return out
	var inv := site.global_transform.affine_inverse() if site.is_inside_tree() else Transform3D.IDENTITY
	for b in group.get_children():
		if not b is StaticBody3D:
			continue
		var box := AABB()
		var first := true
		var parts: Array[AABB] = []
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var a := (inv * mi.global_transform) * mi.get_aabb()
			parts.append(a)
			box = a if first else box.merge(a)
			first = false
		if first or box.size.y < 2.4 or box.size.x < 2.5 or box.size.z < 2.5:
			continue
		# Only roofed buildings: the sun reaches into a roofless ruin, and you
		# see into it over its broken walls
		var roofed := parts.any(func(a: AABB) -> bool:
			return a.size.x >= 0.6 * box.size.x and a.size.z >= 0.6 * box.size.z and a.get_center().y > box.position.y + 2.0)
		if roofed_only and not roofed:
			continue
		# Inside the walls and under the roof, down to (and just below) the floor
		var inner := box.grow(-0.35)
		inner.size.y += inner.position.y - (box.position.y - 0.1)
		inner.position.y = box.position.y - 0.1
		out.append([inner, minf(box.size.x, box.size.z)])
	return out


static func _inside(shells: Array, p: Vector3, size: float) -> bool:
	for s in shells:
		if (s[0] as AABB).has_point(p) and size < 0.75 * float(s[1]):
			return true
	return false


static func _mark_interiors(site: Node3D, shells: Array, st: Stats) -> void:
	var inv := site.global_transform.affine_inverse()
	for n in site.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.has_meta("no_draw_distance"):
			continue
		var size := Zone._size_of(g)
		if size <= 0.0:
			continue
		var centre := inv * (g.global_transform * g.get_aabb().get_center())
		if _inside(shells, centre, size):
			if g.visibility_range_end <= 0.0 or g.visibility_range_end > INTERIOR_RANGE:
				g.visibility_range_end = INTERIOR_RANGE
				g.visibility_range_end_margin = 5.0
				g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.set_meta("interior", true)
			st.interior += 1
		elif size < NO_SHADOW_BELOW and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			st.no_shadow += 1


## A plain mesh that can be folded into a batch.
static func mergeable(mi: MeshInstance3D, site: Node) -> bool:
	if mi.mesh == null or mi.get_child_count() > 0 or not mi.visible or mi.get_script() != null:
		return false
	if mi.has_meta("no_draw_distance") or mi.has_meta("no_merge") or mi.material_overlay != null or mi.skin != null:
		return false
	if mi.visibility_range_end > 0.0 and not mi.has_meta("interior"):
		return false
	if mi.global_transform.basis.determinant() <= 0.0:
		return false
	var a: Node = mi.get_parent()
	while a != null and a != site:
		if a.get_script() != null or a.is_in_group("persist") or a.is_in_group("level_props"):
			return false
		if a is Node3D and not (a as Node3D).visible:
			return false
		a = a.get_parent()
	if a == null:
		return false
	for i in mi.mesh.get_surface_count():
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var m := _material(mi, i)
		if m is ShaderMaterial:
			return false
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or bm.render_priority != 0 or bm.next_pass != null:
				return false
	return true


static func _material(mi: MeshInstance3D, surface: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var m := mi.get_surface_override_material(surface)
	return m if m != null else mi.mesh.surface_get_material(surface)


## Which vertex arrays a surface has (surfaces only merge with their like).
static func _format(mesh: Mesh, surface: int, cache: Dictionary) -> int:
	var key := Vector2i(mesh.get_instance_id(), surface)
	if cache.has(key):
		return cache[key]
	var f := 0
	if mesh is ArrayMesh:
		f = (mesh as ArrayMesh).surface_get_format(surface)
	else:
		var arrays := mesh.surface_get_arrays(surface)
		for a in [[Mesh.ARRAY_NORMAL, Mesh.ARRAY_FORMAT_NORMAL], [Mesh.ARRAY_TANGENT, Mesh.ARRAY_FORMAT_TANGENT],
				[Mesh.ARRAY_COLOR, Mesh.ARRAY_FORMAT_COLOR], [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_FORMAT_TEX_UV],
				[Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_FORMAT_TEX_UV2], [Mesh.ARRAY_INDEX, Mesh.ARRAY_FORMAT_INDEX]]:
			if arrays[a[0]] != null:
				f |= a[1]
	f &= Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_INDEX
	cache[key] = f
	return f


static func _class_range(size: float) -> float:
	return Zone.SMALL_RANGE if size < Zone.SMALL else (Zone.MEDIUM_RANGE if size < Zone.MEDIUM else Zone.LARGE_RANGE)


static func _merge(site: Node3D, st: Stats) -> void:
	var meshes: Array[MeshInstance3D] = []
	for n in site.find_children("*", "MeshInstance3D", true, false):
		if mergeable(n as MeshInstance3D, site):
			meshes.append(n)
	if not meshes.is_empty():
		var holder := Node3D.new()
		holder.name = "Batched"
		site.add_child(holder)
		st.merged_into += _merge_meshes(site, holder, meshes, true)
		st.merged_from += meshes.size()
	# Props you can move or scrap, and salvage piles, stay their own nodes,
	# but their many pieces become one mesh per material inside them
	for n in site.find_children("*", "Node3D", true, false):
		if not ((n is LevelProp and not n is ContainerProp) or n is SalvagePile):
			continue
		if n.find_children("*", "AnimationPlayer", true, false).size() > 0:
			continue
		var inner: Array[MeshInstance3D] = []
		var ok := true
		for c in n.find_children("*", "Node", true, false):
			if c.get_script() != null:
				ok = false
				break
			if c is MeshInstance3D and mergeable(c as MeshInstance3D, n):
				inner.append(c)
		if not ok or inner.size() < 2:
			continue
		st.props_merged += 1
		st.merged_into += _merge_meshes(n, n, inner, false)
		st.merged_from += inner.size()


## Merges `meshes` into new MeshInstance3Ds under `parent`, in the space of
## `space`, one per material/format/shadow/draw distance (and 48 m cell when
## `cells`). Frees the originals. Returns how many meshes it made.
static func _merge_meshes(space: Node3D, parent: Node3D, meshes: Array[MeshInstance3D], cells: bool) -> int:
	var inv := space.global_transform.affine_inverse()
	var groups := {}
	var formats := {}
	for mi in meshes:
		var interior: bool = mi.has_meta("interior")
		# Site batches carry their size's draw distance; inside a prop the
		# zone gives the merged mesh one by its own size, as before
		var draw_range := INTERIOR_RANGE if interior else (_class_range(Zone._size_of(mi)) if cells else 0.0)
		var xf := inv * mi.global_transform
		var cell := Vector2i.ZERO
		if cells:
			var centre := xf * mi.get_aabb().get_center()
			cell = Vector2i(floori(centre.x / CELL), floori(centre.z / CELL))
		for i in mi.mesh.get_surface_count():
			var mat := _material(mi, i)
			var key := [mat.get_instance_id() if mat else 0, _format(mi.mesh, i, formats), mi.cast_shadow, mi.layers, draw_range, cell]
			if not groups.has(key):
				var t := SurfaceTool.new()
				t.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool": t, "material": mat, "range": draw_range, "shadow": mi.cast_shadow, "layers": mi.layers}
			(groups[key]["tool"] as SurfaceTool).append_from(mi.mesh, i, xf)
	var k := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var out := MeshInstance3D.new()
		out.name = "Batch%d" % k
		k += 1
		out.mesh = (g["tool"] as SurfaceTool).commit()
		out.material_override = g["material"]
		out.cast_shadow = g["shadow"]
		out.layers = g["layers"]
		if g["range"] > 0.0:
			out.visibility_range_end = g["range"]
			out.visibility_range_end_margin = 8.0
			out.set_meta("no_draw_distance", true)
		parent.add_child(out)
	for mi in meshes:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	return k


## Occluder boxes from the buildings' own collision boxes: walls (2 m+ tall
## and long) and slabs (floors and roofs 3 m+ across).
static func _add_occluders(site: Node3D, st: Stats) -> void:
	var group := site.get_node_or_null("Buildings")
	if group == null:
		return
	var holder := Node3D.new()
	holder.name = "Occluders"
	site.add_child(holder)
	var inv := site.global_transform.affine_inverse()
	for b in group.get_children():
		if not b is StaticBody3D:
			continue
		for cs in b.find_children("*", "CollisionShape3D", true, false):
			var box := (cs as CollisionShape3D).shape as BoxShape3D
			if box == null or (cs as CollisionShape3D).disabled:
				continue
			var xf := inv * (cs as Node3D).global_transform
			var sc := xf.basis.get_scale()
			var size := box.size * sc.abs()
			var wall := size.y >= 2.0 and maxf(size.x, size.z) >= 2.0
			var slab := size.x >= 3.0 and size.z >= 3.0
			if not wall and not slab:
				continue
			var occ := BoxOccluder3D.new()
			occ.size = Vector3(maxf(size.x - 0.12, 0.05), maxf(size.y - 0.12, 0.05), maxf(size.z - 0.12, 0.05))
			var oi := OccluderInstance3D.new()
			oi.occluder = occ
			oi.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
			holder.add_child(oi)
			st.occluders += 1
