extends SceneTree
## Builds the drivable cargo truck (Increment 18):
## scenes/vehicles/cargo_truck.tscn, a VehicleBody3D with four wheels, a cab
## you can see out of, a bed with crates that fill up as you load it, and
## the parts you use: driver's door, fuel cap, tailgate (cargo).
##
##   godot --headless --path . -s res://tools/build_truck.gd
##
## Its front is +Z, as Godot's vehicles drive. Re-run to rebuild it.

const OUT := "res://scenes/vehicles/cargo_truck.tscn"
const MAT := "res://assets/materials/"

var M := {}
var truck: Truck


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	M["body"] = load(MAT + "olive_drab.tres")
	M["dark"] = load(MAT + "metal_dark.tres")
	M["glass"] = _glass_mat()
	M["rubber"] = load(MAT + "rubber.tres")
	M["canvas"] = load(MAT + "sandbag.tres")
	M["wood"] = load(MAT + "wood.tres")
	M["head"] = _light_mat("truck_headlight", Color(1.0, 0.95, 0.8), 2.5)
	M["tail"] = _light_mat("truck_taillight", Color(0.9, 0.12, 0.08), 1.5)

	truck = Truck.new()
	truck.name = "CargoTruck"
	truck.mass = 2600.0
	truck.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	truck.center_of_mass = Vector3(0, 0.5, 0.35)
	truck.collision_layer = PhysicsLayers.STRUCTURES
	truck.collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES
	truck.can_sleep = true
	truck.angular_damp = 0.6
	truck.set_meta("no_draw_distance", true)

	var body := _node("Body", truck)
	# Chassis and front end
	_box(body, "FrameRails", Vector3(1.2, 0.22, 6.0), Vector3(0, 0.62, 0.15), "dark")
	_box(body, "FrontBumper", Vector3(2.3, 0.28, 0.25), Vector3(0, 0.66, 3.22), "dark")
	_box(body, "Grille", Vector3(1.6, 0.6, 0.06), Vector3(0, 1.17, 3.12), "dark")
	_box(body, "Hood", Vector3(2.0, 0.66, 1.25), Vector3(0, 1.2, 2.5), "body")
	_box(body, "HeadlightL", Vector3(0.32, 0.22, 0.06), Vector3(0.72, 1.22, 3.15), "head")
	_box(body, "HeadlightR", Vector3(0.32, 0.22, 0.06), Vector3(-0.72, 1.22, 3.15), "head")
	for side in [1.0, -1.0]:
		var tag := "L" if side > 0 else "R"
		_box(body, "FrontFender" + tag, Vector3(0.44, 0.12, 1.3), Vector3(0.99 * side, 1.02, 2.05), "body")
		_box(body, "Step" + tag, Vector3(0.3, 0.06, 1.0), Vector3(1.12 * side, 0.6, 1.2), "dark")
	# The cab: open enough to see out of from the driver's seat
	_box(body, "CabFloor", Vector3(2.1, 0.12, 1.35), Vector3(0, 0.86, 1.22), "dark")
	_box(body, "CabRoof", Vector3(2.14, 0.1, 1.48), Vector3(0, 2.66, 1.2), "body")
	_box(body, "Cowl", Vector3(2.1, 0.62, 0.08), Vector3(0, 1.16, 1.9), "body")
	_box(body, "Dashboard", Vector3(2.0, 0.24, 0.36), Vector3(0, 1.42, 1.72), "dark")
	_box(body, "Windshield", Vector3(1.92, 1.06, 0.03), Vector3(0, 2.07, 1.9), "glass")
	_box(body, "BackWall", Vector3(2.1, 0.72, 0.08), Vector3(0, 1.24, 0.56), "body")
	_box(body, "BackWindow", Vector3(1.5, 0.72, 0.03), Vector3(0, 1.97, 0.56), "glass")
	for side in [1.0, -1.0]:
		var tag := "L" if side > 0 else "R"
		_box(body, "APillar" + tag, Vector3(0.1, 1.16, 0.1), Vector3(1.02 * side, 2.06, 1.9), "body")
		_box(body, "BPillar" + tag, Vector3(0.1, 1.36, 0.12), Vector3(1.04 * side, 1.98, 0.58), "body")
		_box(body, "BackPost" + tag, Vector3(0.3, 0.72, 0.08), Vector3(0.9 * side, 1.97, 0.56), "body")
		_box(body, "Door" + tag, Vector3(0.08, 0.72, 1.26), Vector3(1.05 * side, 1.24, 1.23), "body")
		_box(body, "DoorWindow" + tag, Vector3(0.03, 0.76, 1.0), Vector3(1.05 * side, 2.0, 1.25), "glass")
		_box(body, "Mirror" + tag, Vector3(0.06, 0.28, 0.18), Vector3(1.22 * side, 1.86, 1.86), "dark")
	_box(body, "Seat", Vector3(1.8, 0.18, 0.55), Vector3(0, 1.12, 0.98), "canvas")
	_box(body, "SeatBack", Vector3(1.8, 0.62, 0.14), Vector3(0, 1.5, 0.7), "canvas")
	# Bed
	_box(body, "BedFloor", Vector3(2.25, 0.1, 3.4), Vector3(0, 1.02, -1.25), "wood")
	_box(body, "BedFront", Vector3(2.25, 0.8, 0.08), Vector3(0, 1.45, 0.42), "body")
	_box(body, "Tailgate", Vector3(2.25, 0.55, 0.08), Vector3(0, 1.32, -2.93), "body")
	for side in [1.0, -1.0]:
		var tag := "L" if side > 0 else "R"
		_box(body, "BedSide" + tag, Vector3(0.08, 0.55, 3.4), Vector3(1.12 * side, 1.32, -1.25), "body")
		_box(body, "TailLight" + tag, Vector3(0.18, 0.12, 0.05), Vector3(0.95 * side, 1.12, -2.98), "tail")
		_box(body, "RearMudflap" + tag, Vector3(0.4, 0.4, 0.03), Vector3(0.98 * side, 0.65, -2.4), "rubber")
	var tank := MeshInstance3D.new()
	tank.name = "FuelTank"
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.22
	tank_mesh.bottom_radius = 0.22
	tank_mesh.height = 0.9
	tank.mesh = tank_mesh
	tank.material_override = M["dark"]
	tank.rotation_degrees = Vector3(90, 0, 0)
	tank.position = Vector3(-0.88, 0.74, 0.2)
	_add(body, tank)
	_box(body, "FuelCapMark", Vector3(0.05, 0.12, 0.12), Vector3(-1.12, 0.92, 0.2), "head")

	# Steering wheel: the pivot is tilted with the column; Truck spins it on Z
	var wheel_pivot := Node3D.new()
	wheel_pivot.name = "SteeringWheel"
	wheel_pivot.position = Vector3(0.45, 1.66, 1.5)
	wheel_pivot.rotation_degrees = Vector3(37, 0, 0)
	_add(truck, wheel_pivot)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.19
	torus.rings = 16
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = M["dark"]
	rim.rotation_degrees = Vector3(90, 0, 0)
	_add(wheel_pivot, rim)
	_box(wheel_pivot, "Spoke", Vector3(0.32, 0.035, 0.03), Vector3.ZERO, "dark")

	# Collision (clear of the wheels, so it rides on its suspension)
	_shape("CabCol", Vector3(2.1, 1.82, 1.42), Vector3(0, 1.78, 1.22))
	_shape("HoodCol", Vector3(2.1, 0.86, 1.4), Vector3(0, 1.12, 2.58))
	_shape("BedCol", Vector3(2.3, 0.76, 3.52), Vector3(0, 1.22, -1.25))
	_shape("ChassisCol", Vector3(1.3, 0.3, 6.1), Vector3(0, 0.72, 0.15))

	# Wheels: front ones steer, all four drive
	for spec in [["WheelFL", Vector3(0.98, 0.86, 2.05), true], ["WheelFR", Vector3(-0.98, 0.86, 2.05), true],
			["WheelRL", Vector3(0.98, 0.86, -1.75), false], ["WheelRR", Vector3(-0.98, 0.86, -1.75), false]]:
		var w := VehicleWheel3D.new()
		w.name = spec[0]
		w.position = spec[1]
		w.use_as_steering = spec[2]
		w.use_as_traction = true
		w.wheel_radius = 0.48
		w.wheel_rest_length = 0.38
		w.suspension_travel = 0.25
		w.suspension_stiffness = 60.0
		w.suspension_max_force = 80000.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.1
		w.wheel_friction_slip = 2.6
		w.wheel_roll_influence = 0.05
		_add(truck, w)
		var tyre := MeshInstance3D.new()
		tyre.name = "Tyre"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.48
		cyl.bottom_radius = 0.48
		cyl.height = 0.34
		cyl.radial_segments = 18
		tyre.mesh = cyl
		tyre.material_override = M["rubber"]
		tyre.rotation_degrees = Vector3(0, 0, 90)
		_add(w, tyre)
		var hub := MeshInstance3D.new()
		hub.name = "Hub"
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = 0.24
		hub_mesh.bottom_radius = 0.24
		hub_mesh.height = 0.36
		hub_mesh.radial_segments = 8
		hub.mesh = hub_mesh
		hub.material_override = M["dark"]
		hub.rotation_degrees = Vector3(0, 0, 90)
		_add(w, hub)

	# Where the driver's eyes are
	var eye := Marker3D.new()
	eye.name = "Eye"
	eye.position = Vector3(0.45, 2.0, 0.95)
	_add(truck, eye)

	# The parts you use
	var door := TruckDoor.new()
	door.name = "DriverDoor"
	door.position = Vector3(1.16, 1.5, 1.22)
	_add(truck, door)
	_area_shape(door, Vector3(0.3, 1.2, 1.3))
	var cap := TruckFuelCap.new()
	cap.name = "FuelCap"
	cap.position = Vector3(-1.2, 1.0, 0.2)
	_add(truck, cap)
	_area_shape(cap, Vector3(0.3, 0.45, 0.45))
	var cargo := TruckCargo.new()
	cargo.name = "Cargo"
	cargo.container_name = "Truck Bed"
	cargo.position = Vector3(0, 1.35, -3.06)
	cargo.max_distance = 3.2
	_add(truck, cargo)
	_area_shape(cargo, Vector3(2.2, 0.8, 0.3))
	var inv := InventoryComponent.new()
	inv.name = "Inventory"
	inv.slot_count = 48
	inv.max_weight = 400.0
	_add(cargo, inv)
	inv.unique_name_in_owner = true
	for s in [["OpenSound", "res://assets/ashfall_pack_v3/audio/locker_open.wav"], ["CloseSound", "res://assets/ashfall_pack_v3/audio/locker_close.wav"]]:
		var a := AudioStreamPlayer3D.new()
		a.name = s[0]
		a.stream = load(s[1])
		a.unit_size = 4.0
		_add(cargo, a)
		a.unique_name_in_owner = true
	# Crates that fill the bed as you load it (Truck shows them)
	var crates := _node("CargoCrates", truck)
	var i := 0
	for z in [-0.2, -1.2, -2.2]:
		for x in [0.5, -0.5]:
			var c := _box(crates, "Crate%d" % i, Vector3(0.78, 0.5, 0.8), Vector3(x, 1.32, z), "wood")
			c.rotation_degrees.y = [3.0, -4.0, 6.0, -2.0, 1.0, -6.0][i]
			c.visible = false
			i += 1
	# Running into raiders
	var bumper := Area3D.new()
	bumper.name = "Bumper"
	bumper.collision_layer = 0
	bumper.collision_mask = PhysicsLayers.NPCS
	bumper.monitorable = false
	_add(truck, bumper)
	var bs := CollisionShape3D.new()
	bs.name = "Shape"
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(2.6, 1.8, 6.8)
	bs.shape = bbox
	bs.position = Vector3(0, 1.3, 0.15)
	_add(bumper, bs)
	# Camera behind, for driving in third person (T)
	var cam := Camera3D.new()
	cam.name = "ChaseCamera"
	cam.fov = 70.0
	cam.far = 1000.0
	cam.position = Vector3(0, 4.4, -10.0)
	_add(truck, cam)
	# On the compass and the map
	var mark := Landmark.new()
	mark.name = "Marker"
	mark.display_name = "Your truck"
	mark.compass_name = "Truck"
	mark.radius = 0.0
	mark.marker_color = Color(0.55, 0.8, 1.0)
	mark.position = Vector3(0, 2.0, 0)
	_add(truck, mark)
	var engine := AudioStreamPlayer3D.new()
	engine.name = "EngineSound"
	engine.stream = load("res://assets/audio/truck_engine_loop.wav")
	engine.unit_size = 10.0
	engine.max_distance = 140.0
	engine.position = Vector3(0, 1.2, 2.4)
	_add(truck, engine)

	var packed := PackedScene.new()
	var err := packed.pack(truck)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("wrote ", OUT, " (", error_string(err), ")")
	truck.free()
	quit()


## Clear enough to drive behind (the outpost's dirty glass is too dark).
func _glass_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.7, 0.78, 0.8, 0.12)
	m.roughness = 0.1
	m.metallic_specular = 0.8
	var path := MAT + "truck_glass.tres"
	ResourceSaver.save(m, path)
	return load(path)


func _light_mat(name: String, color: Color, energy: float) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	var path := MAT + name + ".tres"
	ResourceSaver.save(m, path)
	return load(path)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = truck


func _node(name: String, parent: Node) -> Node3D:
	var n := Node3D.new()
	n.name = name
	_add(parent, n)
	return n


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = M[mat]
	mi.position = pos
	if mat == "glass":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(parent, mi)
	return mi


func _shape(name: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	_add(truck, cs)


func _area_shape(area: Area3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	_add(area, cs)
