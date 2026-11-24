extends "res://tests/test_case.gd"
## Increment 30.1: from the user's bug report. Standing in a chicken coop as
## it finished being built, you were stuck in its walls and could die, and
## dying out of the world dropped your gear out of reach below it.

var RIFLE: ItemDefinition = load("res://resources/items/weapons/service_rifle_item.tres")


func _free(zone: Node3D) -> void:
	zone.queue_free()
	await wait_physics(2)


func _farm(zone: Node3D) -> Settlement:
	return zone.get_node("AshCreekFarms/Settlement") as Settlement


func _claimed(zone: Node3D) -> Settlement:
	var st := _farm(zone)
	var p := zone.get_node("Player") as PlayerController
	p.global_position = st.claim_point.global_transform * Vector3(0, -1.35, 1.6)
	await wait_physics(5)
	st.request_claim(p)
	st.next_raid_in = 9999.0
	st.arrival_in = 9999.0
	return st


## Plans `plan` at `local` (farm space) from 10 m off, supplies it, then
## puts the player (and a settler) where it's going up and finishes it.
func _finish_on_top(zone: Node3D, plan: StringName, local: Vector3, stand: Vector3) -> Array:
	var st := await _claimed(zone)
	var p := zone.get_node("Player") as PlayerController
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var xf := site_root.global_transform * Transform3D(Basis(), local)
	p.global_position = xf.origin + site_root.global_basis * Vector3(0, 0.1, 10)
	await wait_physics(3)
	var site := p.request_place_site(plan, xf)
	check(site != null, "planned a %s (%s)" % [plan, p.site_refusal_reason(plan, xf)])
	await wait_physics(2)
	site.delivered = site.total_cost().duplicate()
	p.global_position = site_root.global_transform * stand
	p.velocity = Vector3.ZERO
	await wait_physics(4)
	site.add_work(site.total_hours())
	await wait_physics(2)
	return [st, p, site_root]


func test_standing_in_a_coop_as_it_goes_up() -> void:
	var zone := await load_zone()
	# The hen house goes up 2.6 m in from the pen's back-left corner: stand there
	var r := await _finish_on_top(zone, &"chicken_coop", Vector3(22, 0, 24), Vector3(22 - 2.6, 0.1, 24 - 1.9))
	var p := r[1] as PlayerController
	var site_root := r[2] as Node3D
	var pen: SettlementBuilding = null
	for n in zone.get_node("Structures").get_children():
		if n is SettlementBuilding and (n as SettlementBuilding).definition.id == &"chicken_coop":
			pen = n
	check(pen != null, "the coop is built")
	# Not inside any of its solid parts
	var stuck := false
	for cs: CollisionShape3D in pen.find_children("*", "CollisionShape3D", true, false):
		if cs.disabled:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.collision_mask = PhysicsLayers.PLAYER
		if not p.get_world_3d().direct_space_state.intersect_shape(q, 4).is_empty():
			stuck = true
	check(not stuck, "you're moved out of its walls (at %s)" % site_root.to_local(p.global_position).snapped(Vector3.ONE * 0.1))
	# And you can walk away, still alive and on the ground
	var f := InputFrame.new()
	f.move = Vector2(0, -1)
	var from := p.global_position
	for i in 90:
		await wait_physics(1)
		p.simulate(f, 1.0 / 60.0)
	check(not p.is_dead() and p.global_position.y > -1.0 and p.global_position.distance_to(from) > 1.5,
		"free to walk off (%.1f m, height %.2f)" % [p.global_position.distance_to(from), p.global_position.y])
	await _free(zone)


func test_a_settler_in_the_way_steps_out_too() -> void:
	var zone := await load_zone()
	var st := await _claimed(zone)
	var site_root := zone.get_node("AshCreekFarms") as Node3D
	var s := st.spawn_newcomer()
	await wait_physics(5)
	s.set_physics_process(false)
	# A guard post goes up with one of its solid parts where they stand
	var where := site_root.global_transform * Vector3(10, 0, 20)
	var post := (load(SettlementPlans.structure(&"guard_post").scene_path) as PackedScene).instantiate() as Node3D
	zone.get_node("Structures").add_child(post)
	post.global_position = where
	var part := post.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	where = Vector3(part.global_position.x, where.y, part.global_position.z)
	s.global_position = where + Vector3.UP * 0.05
	await wait_physics(1)
	var moved := ConstructionSite.clear_space(post)
	check(moved.has(s) and s.global_position.distance_to(where) > 1.0, "the settler is moved out of the post's way (%.1f m)" % s.global_position.distance_to(where))
	await _free(zone)


func test_gear_never_falls_out_of_the_world() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	p.give_weapon(RIFLE.weapon)
	for i in 30:
		await wait_physics(1)
		p.simulate(InputFrame.new(), 1.0 / 60.0)
	var safe := p.last_safe_position
	check(safe != Vector3.INF and absf(safe.y - p.global_position.y) < 0.5, "where you last stood is remembered (%s)" % safe)
	# Through the floor and out of the world
	p.set_physics_process(false)
	p.global_position = safe + Vector3(0, -40, 0)
	p.set_physics_process(true)
	await wait_physics(5)
	check(p.is_dead(), "fell out of the world: dead")
	var gm := zone.find_child("GameMode", true, false) as GameMode
	var cache := gm.get_dropped_gear(p) if gm != null else null
	check(cache != null and cache.global_position.distance_to(safe) < 1.5 and cache.global_position.y > safe.y - 1.0,
		"your gear is where you last stood, not under the world (%s v %s)" % [cache.global_position if cache else "none", safe])
	await _free(zone)
