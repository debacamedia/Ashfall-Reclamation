class_name SettlementGate
extends SettlementBuilding
## A double gate in a settlement's fence (Increment 27), 8 m across: two
## leaves of planks braced with scrap. It opens by itself for your people,
## you and your settlers, and shuts behind them. Raiders can't open it: with
## a raider near, it stays shut (even on a settler) and they have to break it
## down.
##
## The leaves aren't in the navmesh (NavRebaker leaves out bodies in the
## "nav_passable" group), so paths run through the gate: settlers walk up to
## it and it opens; raiders walk up to it and find it shut, and hack at it
## (Raider._structure_in_way). Its posts are in the navmesh, like a fence's.
##
## Scene: res://scenes/settlement/settlement_gate.tscn (made by
## tools/build_settlement_buildings.gd). Root → Body (the posts), %LeafL and
## %LeafR (pivots at the hinges, each holding an AnimatableBody3D in
## "nav_passable"), %SwingSound.

## How far each leaf swings in (degrees). The left leaf runs +X from its
## hinge, the right leaf -X; both swing to -Z (inside).
const OPEN_ANGLE := 95.0
## Half the gate's width (m), for distances to it.
const HALF_WIDTH := 4.0
## One of your settlers this close to the gate opens it…
const OPEN_FOR_SETTLER := 3.0
## …or you, this close (further, for a truck's nose).
const OPEN_FOR_PLAYER := 7.0
## A raider this close keeps it shut.
const SHUT_FOR_RAIDER := 12.0

var is_open := false

@onready var _left: Node3D = %LeafL
@onready var _right: Node3D = %LeafR
@onready var _swing_sound: AudioStreamPlayer3D = get_node_or_null("%SwingSound")
var _tween: Tween
var _check := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("settlement_gates")


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	var want := should_open()
	if want != is_open:
		set_open(want)


## Open for one of yours close by, and no raider near.
func should_open() -> bool:
	if not is_inside_tree():
		return false
	if raider_near():
		return false
	for p in get_tree().get_nodes_in_group("players"):
		var pl := p as PlayerController
		if pl != null and not pl.is_dead() and distance_to(pl.global_position) <= OPEN_FOR_PLAYER:
			return true
	for n in get_tree().get_nodes_in_group("settlers"):
		var s := n as Settler
		if s != null and s.settlement != null and not s.is_dead() and not s.is_down() \
				and distance_to(s.global_position) <= OPEN_FOR_SETTLER:
			return true
	return false


func raider_near() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		var r := e as Node3D
		if r == null or (r.has_method("is_dead") and r.call("is_dead")):
			continue
		if distance_to(r.global_position) <= SHUT_FOR_RAIDER:
			return true
	return false


## How far `p` is from the gate's line (the opening, post to post).
func distance_to(p: Vector3) -> float:
	var local := global_transform.affine_inverse() * p
	var dx := maxf(absf(local.x) - HALF_WIDTH, 0.0)
	return Vector2(dx, local.z).length()


func set_open(open: bool, animate := true) -> void:
	if open == is_open and animate:
		return
	is_open = open
	var a := deg_to_rad(OPEN_ANGLE) if open else 0.0
	if _tween != null:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_left, "rotation:y", a, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(_right, "rotation:y", -a, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if _swing_sound != null:
			_swing_sound.play()
	else:
		_left.rotation.y = a
		_right.rotation.y = -a


func save_state() -> Dictionary:
	var d := super.save_state()
	d["open"] = is_open
	return d


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var open: Variant = data.get("open", false)
	set_open(open is bool and open, false)
