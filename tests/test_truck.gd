extends "res://tests/test_case.gd"
## Increment 18: the truck. Get in, drive, steer, brake and reverse; fuel
## and refuelling; the cargo bed; running into raiders; saving; and the
## real one in Outpost 17's motor pool.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TRUCK_SCENE := preload("res://scenes/vehicles/cargo_truck.tscn")
const DT := 1.0 / 60.0

var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")
var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")


class Listener extends Node3D:
	var heard: Array = []

	func _ready() -> void:
		add_to_group("noise_listeners")

	func hear_noise(origin: Vector3, radius: float, source: Node) -> void:
		heard.append([origin, radius, source])


## Flat ground, a truck at the origin (nose +Z), a player by its door.
func _scene() -> Array:
	make_static_box(Vector3(3000, 1, 3000), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var t := TRUCK_SCENE.instantiate() as Truck
	t.position = Vector3(0, 0.15, 0)
	add_child(t)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(2.3, 0.05, 1.2)
	p.rotation.y = PI / 2.0  # facing the door (west, toward -X… the truck's left is +X)
	add_child(p)
	await wait_physics(60)
	p.inventory.clear()
	return [t, p]


func _ticks(p: PlayerController, f: InputFrame, n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _frame(forward := 0.0, right := 0.0) -> InputFrame:
	var f := InputFrame.new()
	f.move = Vector2(right, -forward)
	return f


func _get_in(t: Truck, p: PlayerController) -> bool:
	return t.door.try_interact(p, p.head.global_position)


# ---------------------------------------------------------------- the truck

func test_the_truck_is_built_to_drive() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	check(t is VehicleBody3D and t.is_in_group("vehicles") and t.is_in_group("persist"), "a vehicle, saved with the game")
	var wheels := t.find_children("*", "VehicleWheel3D", false, false)
	check(wheels.size() == 4, "four wheels")
	check(wheels.filter(func(w: VehicleWheel3D) -> bool: return w.use_as_steering).size() == 2, "the front two steer")
	check(absf(t.global_position.y) < 0.2 and t.global_basis.y.y > 0.99, "sits level on its wheels (y %.2f)" % t.global_position.y)
	await wait_physics(60)
	var at := t.global_position
	await wait_physics(120)
	check(t.global_position.distance_to(at) < 0.01, "parked: it doesn't creep (%.3f m in 2 s)" % t.global_position.distance_to(at))
	check(t.cargo.inventory.slot_count == 48 and is_equal_approx(t.cargo.inventory.max_weight, 400.0), "a 48-slot, 400 kg bed")
	for part in [t.door, t.fuel_cap, t.cargo]:
		check((part as Area3D).collision_layer == PhysicsLayers.INTERACTABLES, "%s can be used" % part.name)
	var mark := t.get_node("Marker") as Landmark
	check(mark.is_in_group("landmarks") and mark.radius == 0.0 and mark.display_name == "Your truck", "on the compass")
	check(t.collision_layer == PhysicsLayers.STRUCTURES and t.collision_mask & PhysicsLayers.NPCS == 0, "solid, but it doesn't stop dead on a raider")


func test_get_in_drive_off_get_out() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	check(t.door.get_prompt(p) == "Drive Cargo Truck", "prompt: %s" % t.door.get_prompt(p))
	check(_get_in(t, p), "E at the door gets you in")
	check(p.vehicle == t and t.driver == p and p.is_driving(), "you're driving")
	check(p.collision_layer == 0 and p.collision_mask == 0, "your body doesn't collide while seated")
	check(p.weapon == null or not p.weapon.visible, "hands on the wheel, gun away")
	check(p.get_state_name() == "DRIVING", "state: driving")
	check(p.head.global_position.distance_to(t.eye.global_position) < 0.05, "eyes where the driver's are")
	check((-p.global_basis.z).dot(t.global_basis.z) > 0.99, "looking along the nose")
	# Still holding the E that got you in: you stay in
	var hold := InputFrame.new()
	hold.interact = true
	await _ticks(p, hold, 10)
	check(p.vehicle == t, "the E that got you in doesn't throw you out")
	# Drive forward a bit
	await _ticks(p, _frame(1.0), 120)
	check(t.global_position.z > 5.0 and t.forward_speed() > 4.0, "W drives it forward (%.1f m, %.0f km/h)" % [t.global_position.z, t.speed_kmh()])
	check(p.head.global_position.distance_to(t.eye.global_position) < 0.4, "you ride along in the seat")
	await _ticks(p, _frame(-1.0), 120)
	await _ticks(p, InputFrame.new(), 5)
	await _ticks(p, hold, 1)
	check(p.vehicle == null and t.driver == null, "E again gets you out")
	check(p.collision_layer != 0 and p.weapon != null and p.weapon.visible, "on foot again, gun in hand")
	var side := (p.global_position - t.global_position)
	check(side.dot(t.global_basis.x) > 1.4 and absf(p.global_position.y - 0.05) < 0.4, "standing beside the driver's door")
	check((-p.global_basis.z).dot(t.global_basis.z) > 0.9, "facing the way the truck faces")
	await _ticks(p, InputFrame.new(), 60)
	check(t.linear_velocity.length() < 0.3, "and it stays put with nobody in it")


func test_no_room_to_get_out() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	_get_in(t, p)
	# Walls hard against every side
	make_static_box(Vector3(0.5, 4, 12), Vector3(1.55, 2, 0))
	make_static_box(Vector3(0.5, 4, 12), Vector3(-1.55, 2, 0))
	make_static_box(Vector3(4, 4, 0.5), Vector3(0, 2, 3.65))
	make_static_box(Vector3(4, 4, 0.5), Vector3(0, 2, -3.4))
	# (the spots past those walls are clear, but you can't get there)
	await wait_physics(3)
	var refused := []
	p.vehicle_refused.connect(func(r: String) -> void: refused.append(r))
	check(not p.leave_vehicle(), "boxed in: you can't get out")
	check(refused.size() == 1 and p.vehicle == t, "told why, still driving: %s" % str(refused))


func test_steer_brake_reverse_handbrake() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	t.fuel = t.fuel_capacity
	_get_in(t, p)
	await _ticks(p, _frame(1.0), 240)
	var kmh := t.speed_kmh()
	check(kmh > 30.0 and kmh < 80.0, "4 s of W: %.0f km/h" % kmh)
	# Steer right: facing +Z, right is -X
	var x0 := t.global_position.x
	await _ticks(p, _frame(0.6, 1.0), 120)
	check(t.global_position.x < x0 - 3.0, "D steers right (x %.1f → %.1f)" % [x0, t.global_position.x])
	check(t.global_basis.y.y > 0.95, "and it stays on its wheels")
	await _ticks(p, _frame(1.0, -1.0), 60)
	await _ticks(p, _frame(1.0), 120)
	# Brake with S
	var start := t.global_position
	var from_kmh := t.speed_kmh()
	var n := 0
	while t.forward_speed() > 0.3 and n < 600:
		await _ticks(p, _frame(-1.0), 1)
		n += 1
	var stop := t.global_position.distance_to(start)
	check(stop < 45.0, "S brakes: from %.0f km/h to a stop in %.0f m" % [from_kmh, stop])
	await _ticks(p, _frame(-1.0), 180)
	check(t.forward_speed() < -2.0 and t.forward_speed() > -t.reverse_top_speed - 0.5, "keep holding S and it reverses (%.1f m/s)" % t.forward_speed())
	# Handbrake
	await _ticks(p, _frame(1.0), 180)
	var hb := InputFrame.new()
	hb.jump_held = true
	await _ticks(p, hb, 150)
	check(t.linear_velocity.length() < 0.5, "Space (handbrake) stops it")


func test_fuel_runs_out_and_refills() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	t.fuel = 2.0
	var empty := []
	t.out_of_fuel.connect(func() -> void: empty.append(true))
	_get_in(t, p)
	var n := 0
	while t.fuel > 0.0 and n < 3000:
		await _ticks(p, _frame(1.0), 1)
		n += 1
	var odo := t.odometer
	await _ticks(p, _frame(1.0), 60)
	check(t.fuel == 0.0 and empty.size() == 1, "2 L runs out (once): %.0f m driven" % odo)
	check_near(odo, 2.0 / t.litres_per_km * 1000.0, 15.0, "about %d m on 2 L" % int(2.0 / t.litres_per_km * 1000.0))
	await _ticks(p, _frame(-1.0), 400)
	var at := t.global_position
	await _ticks(p, _frame(1.0), 120)
	check(t.global_position.distance_to(at) < 0.5, "an empty tank goes nowhere")
	await _ticks(p, InputFrame.new(), 5)
	var e := InputFrame.new()
	e.interact = true
	await _ticks(p, e, 1)
	check(p.vehicle == null, "out to refuel")
	# The fuel cap, on the other side
	check(t.refuel_refusal_reason(p) == "You need a Fuel Can", "no cans: %s" % t.refuel_refusal_reason(p))
	p.inventory.add_item(FUEL, 3)  # 27 kg: a satchel's worth
	check(p.request_refuel(t) == 10.0 and is_equal_approx(t.fuel, 10.0), "one can: 10 L")
	check(p.inventory.count_of(&"fuel") == 2, "the can is used")
	t.fuel = 35.0
	check(p.request_refuel(t) == 5.0 and is_equal_approx(t.fuel, t.fuel_capacity), "tops up to 40 L (a can's last 5 L are lost)")
	check(p.inventory.count_of(&"fuel") == 1, "one can left")
	check(t.refuel_refusal_reason(p) == "The tank's full" and p.request_refuel(t) == 0.0, "no more when it's full")
	check(t.fuel_cap.get_prompt(p).contains("40 / 40 L"), "the cap says how full: %s" % t.fuel_cap.get_prompt(p))
	check(t.fuel_cap.hold_time > 0.0, "hold E to pour")


func test_cargo_bed() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	# Round to the tailgate
	p.global_position = t.global_transform * Vector3(0, 0.05, -4.0)
	p.look_at(t.cargo.global_position, Vector3.UP)
	p.rotation.x = 0.0
	await wait_physics(3)
	check(t.cargo.is_searched, "nothing to search: just open it")
	check(t.cargo.try_interact(p, p.head.global_position), "E at the tailgate opens the bed")
	check(p.current_container == t.cargo, "it's open")
	p.inventory.add_item(SCRAP, 20)
	p.inventory.add_item(FUEL, 2)
	var crates := t.get_node("CargoCrates")
	check(crates.get_children().all(func(c: Node3D) -> bool: return not c.visible), "an empty bed")
	for i in p.inventory.slot_count:
		if p.inventory.get_slot_item(i) != null:
			p.request_store(i)
	check(t.cargo.inventory.count_of(&"scrap_metal") == 20 and t.cargo.inventory.count_of(&"fuel") == 2, "loaded")
	check(crates.get_children().any(func(c: Node3D) -> bool: return c.visible), "crates show in the bed")
	# 400 kg is the limit
	var heavy := t.cargo.inventory.can_add(FUEL, 100)
	check(heavy < 100 and heavy * FUEL.weight + t.cargo.inventory.get_total_weight() <= 400.01, "up to 400 kg (%d more cans fit)" % heavy)
	check(t.cargo.get_prompt(p).contains("kg"), "the prompt shows the load: %s" % t.cargo.get_prompt(p))
	# Drive off and the bed shuts; the load goes with the truck
	p.close_container()
	p.global_position = t.global_transform * Vector3(2.3, 0.05, 1.2)
	p.rotation.y = PI / 2.0
	await wait_physics(3)
	_get_in(t, p)
	t.fuel = 20.0
	await _ticks(p, _frame(1.0), 180)
	check(t.cargo.inventory.count_of(&"scrap_metal") == 20, "the load rides along")
	check(t.cargo.global_position.distance_to(Vector3(0, 1.35, -3.06)) > 10.0, "and the bed with it")


func test_running_into_raiders() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	var listener := Listener.new()
	listener.position = Vector3(0, 0, 60)
	add_child(listener)
	# A stand-in raider in the road ahead
	var raider := CharacterBody3D.new()
	raider.collision_layer = PhysicsLayers.NPCS
	raider.collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	shape.shape = cap
	shape.position.y = 1.0
	raider.add_child(shape)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 400.0
	raider.add_child(health)
	raider.position = Vector3(0, 0, 45)
	add_child(raider)
	t.fuel = 20.0
	_get_in(t, p)
	await _ticks(p, _frame(1.0), 60)
	check(not listener.heard.is_empty() and listener.heard[0][2] == p, "raiders hear the engine")
	var r0: float = listener.heard[0][1]
	check(r0 >= t.engine_noise_radius, "%.0f m away at least" % r0)
	var hurt := []
	health.damaged.connect(func(amount: float, info: DamageInfo) -> void: hurt.append([amount, info]))
	var n := 0
	while hurt.is_empty() and n < 600:
		await _ticks(p, _frame(1.0), 1)
		n += 1
	check(not hurt.is_empty(), "running into a raider hurts them")
	if not hurt.is_empty():
		check(hurt[0][0] > 50.0, "a lot, at speed (%.0f)" % hurt[0][0])
		check((hurt[0][1] as DamageInfo).type == DamageInfo.Type.VEHICLE and (hurt[0][1] as DamageInfo).source == p, "credited to the driver")
	await _ticks(p, _frame(1.0), 30)
	check(hurt.size() == 1, "once per hit, not every tick")
	var louder: float = listener.heard[listener.heard.size() - 1][1]
	check(louder > r0, "louder going fast (%.0f m)" % louder)
	# Crawling into one doesn't hurt
	var slow := Truck.new()
	check(slow.hit_speed >= 3.0, "only above walking pace (%.0f m/s)" % slow.hit_speed)
	slow.free()


func test_saved_where_you_left_it() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	t.fuel = 30.0
	_get_in(t, p)
	await _ticks(p, _frame(1.0, 0.4), 150)
	await _ticks(p, _frame(-1.0), 150)
	t.cargo.inventory.add_item(SCRAP, 7)
	# Saving while driving puts you beside the truck in the save
	var pdata := p.save_state()
	var ppos := Vector3(pdata["position"][0], pdata["position"][1], pdata["position"][2])
	check(ppos.distance_to(t.global_position) > 1.2 and ppos.distance_to(t.global_position) < 6.0 and absf(ppos.y) < 0.6, "saved standing beside it")
	var data := JSON.parse_string(JSON.stringify(t.save_state())) as Dictionary
	var cdata := JSON.parse_string(JSON.stringify(t.cargo.save_state())) as Dictionary
	var where := t.global_transform
	var fuel := t.fuel
	# Move it all away, then load
	p.leave_vehicle(true)
	t.global_transform = Transform3D(Basis(), Vector3(-50, 0.2, -50))
	t.fuel = 1.0
	t.cargo.inventory.clear()
	await wait_physics(5)
	_get_in(t, p)  # (it's not near now: the load puts you out)
	p.global_position = t.global_transform * Vector3(2.3, 0.05, 1.2)
	t.load_state(data)
	t.cargo.load_state(cdata)
	check(t.global_position.distance_to(where.origin) < 0.05 and t.global_basis.z.dot(where.basis.z) > 0.999, "back where it was, facing the same way")
	check(is_equal_approx(t.fuel, fuel), "with its fuel (%.1f L)" % fuel)
	check(t.cargo.inventory.count_of(&"scrap_metal") == 7 and is_equal_approx(t.cargo.inventory.max_weight, 400.0), "and its load (still 400 kg max)")
	check(t.driver == null and p.vehicle == null, "loading puts the driver out")
	await wait_physics(30)
	check(t.linear_velocity.length() < 0.5, "and it doesn't fly off")
	# Junk is ignored
	t.load_state({"position": "x", "rotation": [0, 0, 0, 0], "fuel": NAN})
	check(t.global_position.distance_to(where.origin) < 0.5 and is_equal_approx(t.fuel, fuel), "bad save data changes nothing")


func test_dying_at_the_wheel() -> void:
	var s := await _scene()
	var t: Truck = s[0]
	var p: PlayerController = s[1]
	_get_in(t, p)
	p.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.MELEE))
	check(p.vehicle == null and t.driver == null, "you're out of the truck when you die")
	check(p.global_position.distance_to(t.global_position) > 1.2, "on the ground beside it")
	check(p.collision_layer != 0, "with a body again")


func test_input_and_controls() -> void:
	var f := InputFrame.new()
	f.jump_held = true
	check(InputFrame.from_dict(f.to_dict()).jump_held, "the handbrake (Space held) goes over the network")
	check(not InputFrame.from_dict({"jh": "yes"}).jump_held, "only a real true")
	check(InputMap.has_action("camera_toggle"), "a camera action")
	var t_key := false
	for e in InputMap.action_get_events("camera_toggle"):
		t_key = t_key or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_T)
	check(t_key, "on T")


# ---------------------------------------------------------------- in the zone

func test_the_truck_at_outpost_17() -> void:
	var zone := await load_zone()
	var t := zone.get_node_or_null("Vehicles/CargoTruck") as Truck
	check(t != null, "Outpost 17 has a truck")
	if t == null:
		return
	await wait_physics(30)
	check(t.global_basis.y.y > 0.99 and absf(t.global_position.y) < 0.3, "parked level on the ground")
	check(t.global_position.distance_to(Vector3(5.5, 0, 8)) < 1.0, "in the outpost yard, by the motor pool")
	check(t.global_basis.z.z > 0.95, "nose to the gate (south)")
	check(t.fuel > 0.0 and t.fuel < t.fuel_capacity, "part full (%.0f L): you'll need fuel" % t.fuel)
	var mesh_count := t.find_children("*", "MeshInstance3D", true, false).size()
	check(mesh_count > 40, "its own meshes, not merged into the outpost (%d)" % mesh_count)
	# Shown on the map
	var hud := zone.get_node("HUD") as HUD
	hud.map_screen.view.player = zone.get_node("Player")
	var trucks := hud.map_screen.view.markers().filter(func(m: Dictionary) -> bool: return m["kind"] == "truck")
	check(trucks.size() == 1 and (trucks[0]["at"] as Vector2).distance_to(Vector2(5.5, 8)) < 1.0, "on the map")
	# Drive it out of the gate and down the road
	var p := zone.get_node("Player") as PlayerController
	p.global_position = t.global_transform * Vector3(2.3, 0.05, 1.2)
	p.rotation.y = t.map_heading() + PI / 2.0
	await wait_physics(3)
	check(_get_in(t, p), "get in")
	for target in [Vector2(1.5, 19), Vector2(0, 30), Vector2(0, 66)]:
		var n := 0
		while Vector2(t.global_position.x, t.global_position.z).distance_to(target as Vector2) > 3.0 and n < 900:
			var f := t.global_basis.z
			var to: Vector2 = target - Vector2(t.global_position.x, t.global_position.z)
			var err := wrapf(atan2(to.x, to.y) - atan2(f.x, f.z), -PI, PI)
			await _ticks(p, _frame(0.6, clampf(-err * 2.0, -1.0, 1.0)), 1)
			n += 1
	check(t.global_position.z > 60.0, "out through the gate and onto the road (z %.0f)" % t.global_position.z)
	check(t.global_basis.y.y > 0.95, "upright")
	# The cab and chase cameras
	p.controlled_locally = true
	t.set_third_person(true)
	check(t.chase_camera.current, "T: the camera behind")
	t.set_third_person(false)
	check(p.camera.current, "T again: back in the cab")
	t.set_third_person(true)
	await _ticks(p, InputFrame.new(), 5)
	var e := InputFrame.new()
	e.interact = true
	await _ticks(p, e, 1)
	check(p.vehicle == null and p.camera.current, "getting out puts your own view back")
	p.controlled_locally = false
	# Saved with the zone
	var data := SaveManager.build_save_data(zone)
	var found := false
	for entry in data.get("entries", data.get("nodes", [])):
		if entry is Dictionary and str(entry.get("path", "")).contains("CargoTruck") and not str(entry.get("path", "")).contains("Cargo/"):
			found = found or (entry.get("data", {}) as Dictionary).has("fuel")
	check(found or JSON.stringify(data).contains("\"fuel\""), "the truck is in the save")
