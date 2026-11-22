extends "res://tests/test_case.gd"
## Helpers shared by the settlement-defence suites (27, 27.1): claiming
## places, newcomers, finishing sites, waiting on the navmesh, saves in a
## test folder. Not a suite itself.

const AWAY := Vector3(120, 0.1, 40)
const TEST_DIR := "user://test_saves_fortify"

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var PLANK: ItemDefinition = load("res://resources/items/wood_plank.tres")
var ELECTRONICS: ItemDefinition = load("res://resources/items/electronics.tres")
var CHEMICALS: ItemDefinition = load("res://resources/items/chemicals.tres")
var CLOTH: ItemDefinition = load("res://resources/items/cloth.tres")
var VEG: ItemDefinition = load("res://resources/items/vegetables.tres")

var saves: Node
var _old_dir := ""


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old_dir = saves.save_dir
		saves.save_dir = TEST_DIR
		_clean())
	tree_exiting.connect(func() -> void:
		_clean()
		saves.autosave_enabled = false
		saves.save_dir = _old_dir)


func _clean() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _place(zone: Node3D, site: String) -> Settlement:
	return zone.get_node(site + "/Settlement") as Settlement


func _player(zone: Node3D) -> PlayerController:
	return zone.get_node("Player") as PlayerController


func _claim(zone: Node3D, st: Settlement) -> void:
	var p := _player(zone)
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	check(st.request_claim(p), "claimed %s (%s)" % [st.settlement_name, st.claim_refusal_reason(p)])
	st.next_raid_in = 9999.0
	st.arrival_in = 9999.0
	p.global_position = AWAY
	await wait_physics(2)


func _newcomer(st: Settlement, role: Settler.Role) -> Settler:
	var s := st.spawn_newcomer()
	await wait_physics(70)
	var p := _player(st.get_parent().get_parent() as Node3D)
	check(st.request_set_role(p, s, role), "%s: %s (%s)" % [s.settler_name, Settler.ROLE_NAMES[role], st.role_refusal_reason(role)])
	return s


func _free(zone: Node) -> void:
	remove_child(zone)
	zone.free()
	await wait_physics(2)


func _keys(st: Settlement) -> Array:
	return st.sites().map(func(s: ConstructionSite) -> String: return s.key)


## Hands every site its materials and puts in all its hours: built.
func _finish_sites(st: Settlement) -> void:
	for site in st.sites():
		site.delivered = site.total_cost().duplicate()
		site.add_work(site.total_hours())
	await wait_physics(3)


## Waits for the rebake, and for the zone's map to take it in (on its own
## thread: a moment or two later).
func _wait_nav(zone: Node3D) -> void:
	var nav := NavRebaker.find_navigation(_player(zone))
	var map := zone.get_world_3d().navigation_map
	for i in 900:
		await wait_physics(1)
		if i > 10 and not NavRebaker.any_busy(nav):
			break
	var from := NavigationServer3D.map_get_iteration_id(map)
	for i in 400:
		await wait_physics(1)
		if NavigationServer3D.map_get_iteration_id(map) >= from + 2:
			break
	await wait_physics(2)


func _gate_of(st: Settlement) -> SettlementGate:
	for n in get_tree().get_nodes_in_group("settlement_gates"):
		var g := n as SettlementGate
		if g != null and g.settlement() == st and not g.is_queued_for_deletion():
			return g
	return null


func _path(zone: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := zone.get_world_3d().navigation_map
	return NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from), to, true)


## How close the path comes to the gate's opening.
func _closest_to_gate(path: PackedVector3Array, g: SettlementGate) -> float:
	var best := INF
	for i in path.size() - 1:
		var n := maxi(int(path[i].distance_to(path[i + 1]) / 0.5), 1)
		for j in n + 1:
			best = minf(best, g.distance_to(path[i].lerp(path[i + 1], float(j) / n)))
	return best


