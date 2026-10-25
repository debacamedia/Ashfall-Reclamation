extends Node
## Base class for test suites. Each method named test_* runs in a fresh
## instance of the suite, which is freed afterwards (so nodes a test adds as
## children are cleaned up). Tests may `await` physics frames.

var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(value: float, expected: float, tolerance: float, message: String) -> void:
	if absf(value - expected) > tolerance:
		failures.append("%s (got %.3f, expected %.3f ± %.3f)" % [message, value, expected, tolerance])


func check_between(value: float, low: float, high: float, message: String) -> void:
	if value < low or value > high:
		failures.append("%s (got %.3f, expected %.3f..%.3f)" % [message, value, low, high])


func wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Builds a flat test floor with optional obstacles. Returns the floor node.
func make_static_box(size: Vector3, position: Vector3, layer := PhysicsLayers.STRUCTURES) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


## Builds a flat navigable floor (with optional box obstacles: [size, position])
## inside a NavigationRegion3D, bakes it, and waits until paths work.
func make_nav_floor(size := Vector3(60, 1, 60), obstacles: Array = []) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.25
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	region.navigation_mesh = nm
	add_child(region)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.TERRAIN
	floor_body.position = Vector3(0, -size.y / 2.0, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	floor_body.add_child(shape)
	region.add_child(floor_body)
	for o in obstacles:
		var body := StaticBody3D.new()
		body.collision_layer = PhysicsLayers.STRUCTURES
		body.position = o[1]
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = o[0]
		cs.shape = b
		body.add_child(cs)
		region.add_child(body)
	region.bake_navigation_mesh(false)
	await wait_for_navigation(region.get_world_3d().navigation_map)
	return region


## Waits (up to ~5 s) until the navigation map answers path queries.
func wait_for_navigation(map: RID) -> void:
	for i in 300:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_regions(map).size() > 0:
			var probe := NavigationServer3D.map_get_closest_point(map, Vector3.ZERO)
			if NavigationServer3D.map_get_path(map, probe, probe + Vector3(1, 0, 0), true).size() > 0:
				return


## The Increment 10 starting kit (service rifle + pistol, 120 rifle rounds,
## 36 pistol rounds, one medkit). Older suites were written against it; call
## on a freshly instantiated player BEFORE adding it to the tree. The real
## start (Increment 11) is a machete plus scrap for a pipe pistol.
func classic_kit(p: PlayerController) -> PlayerController:
	var guns: Array[WeaponDefinition] = [
		load("res://resources/items/weapons/service_rifle.tres"),
		load("res://resources/items/weapons/pistol.tres"),
	]
	p.get_node("WeaponSlots").set("starting_weapons", guns)
	var kit: Dictionary[ItemDefinition, int] = {
		ItemDatabase.get_item(&"rifle_ammo"): 120,
		ItemDatabase.get_item(&"pistol_ammo"): 36,
		ItemDatabase.get_item(&"medkit"): 1,
	}
	p.get_node("Inventory").set("starting_items", kit)
	return p
