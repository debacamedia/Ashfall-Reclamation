class_name ConstructionSite
extends Interactable
## Something being built at a settlement (Increment 19.6): a see-through
## outline of the finished thing, with a sign saying what it still needs.
##
##   1. Materials: tap E to hand over what you carry that it needs. The
##      settlement also brings it what's in its stores (Settlement).
##   2. Work: once it has everything, the settlement's Builders put in the
##      hours (SettlementPlans). Hold E to lend a hand yourself.
##   3. It becomes SettlementBuildings (Structures), piece by piece: a fence
##      run goes up a length at a time.
##
## A site is one plan (SettlementPlans) and one or more pieces: transforms,
## relative to the site, where each finished Structure will stand. Planned
## sites (`key` set) come from the settlement's own plan when you claim it;
## others you place in build mode (B).
##
## Lives under the Settlement's "Sites" node; saved with the game (persist),
## re-created from res://scenes/settlement/construction_site.tscn.

signal changed
signal finished(site: ConstructionSite)

## How much of a Builder's hour one hold of E is worth.
const HELP_HOURS := 0.15
const HELP_HOLD := 1.5

@export var plan_id: StringName = &"bunkhouse"
## The settlement plan this came from ("" = placed by a player).
@export var key := ""

## Where each piece will stand (relative to this node).
var pieces: Array[Transform3D] = []
## How many pieces are built.
var built := 0
## Materials handed over so far: item id -> count.
var delivered := {}
## Hours of work put in.
var work := 0.0

var _ghosts: Array[Node3D] = []
var _shapes: Array[CollisionShape3D] = []
var _label: Label3D
var _mat: StandardMaterial3D

static var _mesh_cache := {}


func _ready() -> void:
	add_to_group("construction_sites")
	add_to_group("persist")
	action_name = "Build"
	max_distance = 3.5
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rebuild()


## Sets it up before it's added: the plan and where its pieces go.
func configure(plan: StringName, local_pieces: Array[Transform3D], plan_key := "") -> void:
	plan_id = plan
	pieces = local_pieces
	key = plan_key


func display_name() -> String:
	return SettlementPlans.display_name(plan_id)


func total_cost() -> Dictionary:
	return SettlementPlans.cost(plan_id, pieces.size())


## What it still needs: item id -> count (empty when it has everything).
func missing() -> Dictionary:
	var out := {}
	var c := total_cost()
	for id: StringName in c:
		var short := int(c[id]) - int(delivered.get(id, 0))
		if short > 0:
			out[id] = short
	return out


func is_supplied() -> bool:
	return missing().is_empty()


func total_hours() -> float:
	return SettlementPlans.hours(plan_id, pieces.size())


func progress() -> float:
	return clampf(work / total_hours(), 0.0, 1.0)


func is_done() -> bool:
	return built >= pieces.size()


## The settlement it belongs to.
func settlement() -> Settlement:
	var n := get_parent()
	while n != null:
		if n is Settlement:
			return n as Settlement
		n = n.get_parent()
	return null


## Moves what it still needs out of `inv`. Returns how many items moved.
func take_from(inv: InventoryComponent) -> int:
	if inv == null:
		return 0
	var moved := 0
	var need := missing()
	for id: StringName in need:
		var n := mini(inv.count_of(id), int(need[id]))
		if n <= 0:
			continue
		inv.remove_item(id, n)
		delivered[id] = int(delivered.get(id, 0)) + n
		moved += n
	if moved > 0:
		_refresh()
		changed.emit()
	return moved


## True if `inv` holds anything this site still needs.
func wants_any(inv: InventoryComponent) -> bool:
	if inv == null:
		return false
	var need := missing()
	for id: StringName in need:
		if inv.count_of(id) > 0:
			return true
	return false


## Puts in `hours` of work (once it has its materials). Finished pieces
## become real structures as the work passes them; when it's all built, the
## site goes.
func add_work(hours: float) -> void:
	if hours <= 0.0 or not is_supplied() or is_done() or is_queued_for_deletion():
		return
	work = minf(work + hours, total_hours())
	var should := mini(floori(work / total_hours() * pieces.size() + 0.0001), pieces.size())
	while built < should:
		_build_piece(built)
		built += 1
	_refresh()
	changed.emit()
	if is_done():
		finished.emit(self)
		var st := settlement()
		if st != null:
			st._on_site_finished(self)
		queue_free()


## Where a Builder should stand to work on the next piece.
func work_point() -> Vector3:
	var i := clampi(built, 0, maxi(pieces.size() - 1, 0))
	if pieces.is_empty():
		return global_position
	var def := SettlementPlans.structure(plan_id)
	var xf := global_transform * pieces[i]
	var depth := def.footprint.z if def != null else 1.0
	return xf.origin + xf.basis.z.normalized() * (depth * 0.5 + 0.9)


## The middle of the site (for the sign, the map and distances).
func centre() -> Vector3:
	if pieces.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for p in pieces:
		sum += global_transform * p.origin
	return sum / pieces.size()


# ---------------------------------------------------------------- interaction

func get_prompt(interactor: Node3D) -> String:
	if not is_supplied():
		var p := interactor as PlayerController
		if p != null and wants_any(p.inventory):
			return "Hand over materials for the %s" % display_name()
		return "%s: needs %s" % [display_name(), SettlementPlans.cost_text(missing())]
	return "Help build the %s (%d%%)" % [display_name(), roundi(progress() * 100.0)]


func get_block_reason(interactor: Node3D) -> String:
	if is_supplied():
		return ""
	var p := interactor as PlayerController
	if p != null and not wants_any(p.inventory):
		return "Needs %s" % SettlementPlans.cost_text(missing())
	return ""


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player == null:
		return
	if is_supplied():
		player.request_help_build(self)
	else:
		player.request_deliver_to_site(self)


func _process(_delta: float) -> void:
	# A tap hands over materials; once it has them all, holding E helps build
	hold_time = HELP_HOLD if is_supplied() else 0.0


# ---------------------------------------------------------------- building

func _build_piece(i: int) -> void:
	var def := SettlementPlans.structure(plan_id)
	var root := _structures_root()
	if def == null or root == null:
		return
	var s := (load(def.scene_path) as PackedScene).instantiate() as Structure
	s.name = "%s_%d" % [def.id, (Time.get_ticks_usec() + i * 7) % 100000000]
	s.transform = root.global_transform.affine_inverse() * (global_transform * pieces[i])
	root.add_child(s)
	s._one_shot(load("res://assets/audio/build_place.wav"))
	if i < _ghosts.size() and _ghosts[i] != null:
		_ghosts[i].visible = false
	if i < _shapes.size() and _shapes[i] != null:
		_shapes[i].disabled = true


func _structures_root() -> Node3D:
	var n := get_parent()
	while n != null:
		var s := ConstructionRules.structures_root(n)
		if s != null:
			return s
		n = n.get_parent()
	return null


# ---------------------------------------------------------------- looks

func _rebuild() -> void:
	for g in _ghosts:
		if g != null:
			g.queue_free()
	for s in _shapes:
		if s != null:
			s.queue_free()
	_ghosts.clear()
	_shapes.clear()
	var def := SettlementPlans.structure(plan_id)
	if def == null:
		return
	var meshes := _meshes_of(def)
	for i in pieces.size():
		var g := Node3D.new()
		g.name = "Ghost%d" % i
		g.transform = pieces[i]
		for m: Array in meshes:
			var mi := MeshInstance3D.new()
			mi.mesh = m[0]
			mi.transform = m[1]
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(mi)
		add_child(g)
		g.visible = i >= built
		_ghosts.append(g)
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % i
		var box := BoxShape3D.new()
		box.size = Vector3(def.footprint.x, minf(def.footprint.y, 2.2), def.footprint.z)
		cs.shape = box
		cs.transform = pieces[i] * Transform3D(Basis.IDENTITY, Vector3(0, box.size.y * 0.5, 0))
		cs.disabled = i < built
		add_child(cs)
		_shapes.append(cs)
	if _label == null:
		_label = Label3D.new()
		_label.name = "Sign"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 40
		_label.pixel_size = 0.006
		_label.outline_size = 10
		_label.no_depth_test = false
		_label.visibility_range_end = 45.0
		add_child(_label)
	var top := def.footprint.y
	_label.global_position = centre() + Vector3.UP * clampf(top + 0.6, 2.0, 6.5)
	_refresh()


func _refresh() -> void:
	if _mat != null:
		_mat.albedo_color = Color(1.0, 0.92, 0.7, 0.24) if is_supplied() else Color(0.55, 0.8, 1.0, 0.2)
	if _label == null:
		return
	var lines: PackedStringArray = [display_name().to_upper()]
	if not is_supplied():
		lines.append("Needs " + SettlementPlans.cost_text(missing()))
	else:
		lines.append("Building  %d%%" % roundi(progress() * 100.0))
	_label.text = "\n".join(lines)


## The meshes of `def`'s scene: [[mesh, transform]...] (cached).
static func _meshes_of(def: StructureDefinition) -> Array:
	if _mesh_cache.has(def.scene_path):
		return _mesh_cache[def.scene_path]
	var out := []
	var scene := (load(def.scene_path) as PackedScene).instantiate()
	_collect(scene, Transform3D.IDENTITY, out)
	scene.free()
	_mesh_cache[def.scene_path] = out
	return out


static func _collect(node: Node, parent_xform: Transform3D, out: Array) -> void:
	for c in node.get_children():
		var xf := parent_xform
		if c is Node3D:
			xf = parent_xform * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append([(c as MeshInstance3D).mesh, xf])
		_collect(c, xf, out)


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var ps := []
	for p in pieces:
		ps.append(_xf_to_array(p))
	var d := {}
	for id: StringName in delivered:
		d[String(id)] = delivered[id]
	return {"plan": String(plan_id), "key": key, "at": _xf_to_array(transform), "pieces": ps,
		"built": built, "delivered": d, "work": work}


func load_state(data: Dictionary) -> void:
	var plan := StringName(str(data.get("plan", "")))
	if SettlementPlans.has(plan):
		plan_id = plan
	key = str(data.get("key", ""))
	var at: Variant = _xf_from_array(data.get("at"))
	if at != null:
		transform = at
	pieces.clear()
	var ps: Variant = data.get("pieces", [])
	if ps is Array:
		for p in ps:
			var xf: Variant = _xf_from_array(p)
			if xf != null:
				pieces.append(xf)
	built = clampi(int(Settlement._num(data.get("built"), 0.0)), 0, pieces.size())
	work = maxf(Settlement._num(data.get("work"), 0.0), 0.0)
	delivered.clear()
	var d: Variant = data.get("delivered", {})
	if d is Dictionary:
		for id in d:
			var n := int(Settlement._num(d[id], 0.0))
			if n > 0 and ItemDatabase.get_item(StringName(str(id))) != null:
				delivered[StringName(str(id))] = n
	if is_inside_tree():
		_rebuild()


func is_save_removable() -> bool:
	return true


static func _xf_to_array(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _xf_from_array(v: Variant) -> Variant:
	if not v is Array or (v as Array).size() != 12:
		return null
	for x in v:
		if not ((x is float or x is int) and is_finite(float(x))):
			return null
	var a: Array = v
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])).orthonormalized(),
		Vector3(a[9], a[10], a[11]))
