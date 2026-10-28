class_name Truck
extends VehicleBody3D
## A truck you can drive (Increment 18): get in at the driver's door (E),
## W / S to drive and reverse, A / D to steer, Space for the handbrake,
## T to switch between the cab and a camera behind, E to get out.
##
## It carries cargo in its bed (TruckCargo, opened at the tailgate), runs on
## fuel (a Fuel Can adds 10 L at the fuel cap, TruckFuelCap), raiders hear
## its engine, and running into a raider hurts them. It shows on the map and
## the compass, and is saved where you left it with its fuel.
##
## The truck's front is +Z (Godot's VehicleBody3D drives that way).
##
## AUTHORITY: the host runs the physics. The driver's InputFrame reaches the
## truck through PlayerController (set_controls); getting in and out, and
## refuelling, are validated here.
##
## Scene: res://scenes/vehicles/cargo_truck.tscn (built by
## tools/build_truck.gd).

signal driver_changed(driver: PlayerController)
signal out_of_fuel
signal refuelled(litres: float)

@export var display_name := "Cargo Truck"

@export_group("Driving")
## Engine push at a standstill (N); it fades to nothing at top speed.
@export var engine_force_max := 6000.0
@export var reverse_force := 4500.0
@export var brake_force := 90.0
## Held on when nobody's driving.
@export var parking_brake := 60.0
## Slows a coasting truck a little.
@export var coast_brake := 3.0
## m/s (22 = 79 km/h).
@export var top_speed := 22.0
@export var reverse_top_speed := 6.0
## Wheel angle at full lock (radians), at a crawl…
@export var max_steer := 0.55
## …and at top speed, so fast turns don't roll it.
@export var steer_at_top_speed := 0.12
## How fast the wheels turn (radians a second).
@export var steer_rate := 2.2
## Keeps it on its wheels in hard turns: a push back upright, per radian
## of lean, per kg (an arcade truck: real ones roll).
@export var stabilizer := 14.0

@export_group("Fuel")
@export var fuel_capacity := 40.0
@export var fuel := 15.0
@export var litres_per_km := 6.0
@export var litres_per_can := 10.0

@export_group("Raiders")
## Running into a raider faster than this (m/s) hurts them…
@export var hit_speed := 4.0
## …this much per m/s over half of it.
@export var hit_damage_per_mps := 9.0
## The engine is heard this far away (m), more when going fast.
@export var engine_noise_radius := 24.0

## Local direction of travel.
const FORWARD := Vector3(0, 0, 1)
## How far the driver can turn their head from straight ahead (radians).
const LOOK_LIMIT := 2.0
const CHASE_OFFSET := Vector3(0, 4.4, -10.0)

var driver: PlayerController
## Driver's controls, -1..1: throttle (forward +), steer (right +).
var throttle := 0.0
var steer_input := 0.0
var handbrake := false
## The chase camera is in use (the local driver's choice).
var third_person := false
## Metres driven, ever.
var odometer := 0.0

var _last_position := Vector3.ZERO
var _parked_for := 0.0
var _noise_left := 0.0
var _hit_cooldowns := {}
var _told_empty := false

@onready var eye: Marker3D = $Eye
@onready var door: Interactable = $DriverDoor
@onready var fuel_cap: Interactable = $FuelCap
@onready var cargo: SalvageContainer = $Cargo
@onready var bumper: Area3D = $Bumper
@onready var chase_camera: Camera3D = $ChaseCamera
@onready var engine_sound: AudioStreamPlayer3D = get_node_or_null("EngineSound")
@onready var steering_wheel: Node3D = get_node_or_null("SteeringWheel")
@onready var crates: Node3D = get_node_or_null("CargoCrates")


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("persist")
	_last_position = global_position
	if cargo != null and cargo.inventory != null:
		cargo.inventory.contents_changed.connect(func(_s: PackedInt32Array) -> void: _update_crates())
	_update_crates()


# ---------------------------------------------------------------- state

## Speed along the truck's nose (m/s): negative when reversing.
func forward_speed() -> float:
	return linear_velocity.dot(global_basis * FORWARD)


func speed_kmh() -> float:
	return absf(forward_speed()) * 3.6


func engine_running() -> bool:
	return driver != null and fuel > 0.0


func fuel_fraction() -> float:
	return fuel / fuel_capacity if fuel_capacity > 0.0 else 0.0


## Where the driver's eyes are, and which way they face (along the nose).
func seat_transform(for_player: PlayerController) -> Transform3D:
	var b := (global_basis * Basis(Vector3.UP, PI)).orthonormalized()
	var head_height := for_player.head.position.y if for_player != null and for_player.head != null else 1.6
	return Transform3D(b, eye.global_position - b.y * head_height)


## The truck's heading on the map (radians, as a player's yaw: 0 = north).
func map_heading() -> float:
	var f := global_basis * FORWARD
	return atan2(-f.x, -f.z)


# ---------------------------------------------------------------- driver

## Why `p` can't get in to drive ("" = they can).
func entry_refusal_reason(p: Node3D) -> String:
	var pc := p as PlayerController
	if pc == null:
		return "Can't use that"
	if pc.is_dead():
		return "Can't do that now"
	if driver != null and driver != pc:
		return "Someone's driving"
	return ""


## Called by PlayerController.enter_vehicle after validating.
func take_driver(p: PlayerController) -> void:
	freeze = false
	_parked_for = 0.0
	driver = p
	_told_empty = fuel <= 0.0
	driver_changed.emit(p)


## Called by PlayerController when the driver gets out (or dies).
func release_driver() -> void:
	if driver == null:
		return
	var was := driver
	if third_person and is_instance_valid(was) and was.controlled_locally:
		was.camera.make_current()
	third_person = false
	driver = null
	throttle = 0.0
	steer_input = 0.0
	handbrake = false
	driver_changed.emit(null)


func set_controls(throttle_value: float, steer_value: float, handbrake_on: bool) -> void:
	throttle = clampf(throttle_value, -1.0, 1.0)
	steer_input = clampf(steer_value, -1.0, 1.0)
	handbrake = handbrake_on


## Where someone getting out stands: beside the driver's door if there's
## room, else the other side, behind or in front. Vector3.INF if nowhere.
func exit_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	for local in [Vector3(2.0, 0, 1.0), Vector3(-2.0, 0, 1.0), Vector3(0, 0, -4.4), Vector3(0, 0, 4.6), Vector3(2.0, 0, -1.5), Vector3(-2.0, 0, -1.5)]:
		var p: Vector3 = global_transform * local
		var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 3.0, PhysicsLayers.WORLD_SOLID, [get_rid()])
		var ground := space.intersect_ray(down)
		if ground.is_empty():
			continue
		var feet: Vector3 = ground["position"]
		# Somewhere you could step to from the cab, not past a wall
		var from := global_transform * Vector3(0, 1.4, 0.6)
		var sight := PhysicsRayQueryParameters3D.create(from, feet + Vector3.UP * 1.0, PhysicsLayers.WORLD_SOLID, [get_rid()])
		if not space.intersect_ray(sight).is_empty():
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis(), feet + Vector3.UP * 0.96)
		q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.NPCS
		q.exclude = [get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return feet + Vector3.UP * 0.05
	return Vector3.INF


# ---------------------------------------------------------------- fuel

## Why `p` can't refuel now ("" = they can).
func refuel_refusal_reason(p: Node3D) -> String:
	var pc := p as PlayerController
	if pc == null or pc.is_dead():
		return "Can't do that now"
	if fuel >= fuel_capacity - 0.5:
		return "The tank's full"
	if pc.inventory == null or pc.inventory.count_of(&"fuel") <= 0:
		return "You need a Fuel Can"
	return ""


## Empties one of `p`'s Fuel Cans into the tank (validated). Returns the
## litres added (0 if refused).
func refuel_from(p: PlayerController) -> float:
	if refuel_refusal_reason(p) != "":
		return 0.0
	p.inventory.remove_item(&"fuel", 1)
	var before := fuel
	fuel = minf(fuel + litres_per_can, fuel_capacity)
	_told_empty = false
	refuelled.emit(fuel - before)
	return fuel - before


# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	var v := forward_speed()
	if driver != null and not is_instance_valid(driver):
		release_driver()
	if driver == null:
		engine_force = 0.0
		brake = parking_brake
		steering = move_toward(steering, 0.0, steer_rate * delta)
		_park(delta)
	else:
		_drive(v, delta)
	# Fuel, by distance driven with the engine running (not the suspension
	# settling, or a load moving it)
	var moved := Vector2(global_position.x - _last_position.x, global_position.z - _last_position.z).length()
	_last_position = global_position
	if moved < 5.0 and moved > 0.3 * delta:
		odometer += moved
		if engine_running():
			fuel = maxf(fuel - moved / 1000.0 * litres_per_km, 0.0)
			if fuel <= 0.0 and not _told_empty:
				_told_empty = true
				out_of_fuel.emit()
	_stabilize()
	_engine_noise(v, delta)
	_hit_raiders(delta)


func _stabilize() -> void:
	if freeze:
		return
	var up := global_basis.y
	if up.y > 0.2:  # (not if it's somehow on its roof)
		apply_torque(up.cross(Vector3.UP) * mass * stabilizer)


## A parked truck, once it's settled, is held still (Godot's vehicles creep
## a few centimetres a second otherwise). Anyone getting in releases it.
func _park(delta: float) -> void:
	if freeze:
		return
	if linear_velocity.length() < 0.3 and angular_velocity.length() < 0.2:
		_parked_for += delta
		if _parked_for > 0.5:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
	else:
		_parked_for = 0.0


func _drive(v: float, delta: float) -> void:
	var t := throttle
	# No fuel, no power (the brakes still work)
	var power := 1.0 if fuel > 0.0 else 0.0
	engine_force = 0.0
	# Coasting slows it a little; at a crawl with no throttle it holds still
	brake = coast_brake if absf(v) > 1.0 else parking_brake
	if t > 0.05:
		if v < -0.5:
			brake = brake_force * t  # rolling back: brake first
		else:
			engine_force = engine_force_max * t * clampf(1.0 - v / top_speed, 0.0, 1.0) * power
			brake = 0.0 if power > 0.0 else brake
	elif t < -0.05:
		if v > 0.5:
			brake = brake_force * -t  # moving forward: S brakes, then reverses
		else:
			engine_force = -reverse_force * -t * clampf(1.0 - -v / reverse_top_speed, 0.0, 1.0) * power
			brake = 0.0 if power > 0.0 else brake
	if handbrake:
		engine_force = 0.0
		brake = brake_force
	# Less lock the faster you go
	var lock := lerpf(max_steer, steer_at_top_speed, clampf(absf(v) / top_speed, 0.0, 1.0))
	steering = move_toward(steering, -steer_input * lock, steer_rate * delta)


func _engine_noise(v: float, delta: float) -> void:
	if not engine_running():
		_noise_left = 0.0
		return
	_noise_left -= delta
	if _noise_left > 0.0:
		return
	_noise_left = 0.7
	get_tree().call_group("noise_listeners", "hear_noise", global_position, engine_noise_radius + absf(v) * 2.2, driver)


## Raiders in the truck's way when it's moving fast take damage, once a
## second each, and are shoved aside.
func _hit_raiders(delta: float) -> void:
	for k in _hit_cooldowns.keys():
		_hit_cooldowns[k] -= delta
		if _hit_cooldowns[k] <= 0.0 or not is_instance_valid(k):
			_hit_cooldowns.erase(k)
	var vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var speed := vel.length()
	if speed < hit_speed:
		return
	for body in bumper.get_overlapping_bodies():
		if body == driver or _hit_cooldowns.has(body) or not body is Node3D:
			continue
		var to := (body as Node3D).global_position - global_position
		if Vector3(to.x, 0, to.z).dot(vel) <= 0.0:
			continue  # it's behind us
		var health := HealthComponent.find_on(body)
		if health == null or health.is_dead():
			continue
		_hit_cooldowns[body] = 1.0
		var info := DamageInfo.create((speed - hit_speed * 0.5) * hit_damage_per_mps, DamageInfo.Type.VEHICLE, driver)
		info.direction = vel.normalized()
		info.hit_position = (body as Node3D).global_position + Vector3.UP
		health.apply_damage(info)
		if body is CharacterBody3D:
			(body as CharacterBody3D).velocity += vel.normalized() * speed * 0.6 + Vector3.UP * 3.0


# ---------------------------------------------------------------- presentation

func _process(delta: float) -> void:
	# The driver rides in the seat (also between physics ticks, for a smooth view)
	if driver != null and is_instance_valid(driver):
		driver.global_transform = seat_transform(driver)
	if steering_wheel != null:
		steering_wheel.rotation.z = steering * 5.0
	if engine_sound != null:
		if engine_running():
			if not engine_sound.playing:
				engine_sound.play()
			var load_amount := absf(throttle)
			engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, 0.75 + absf(forward_speed()) / top_speed * 0.9 + load_amount * 0.12, 1.0 - exp(-4.0 * delta))
			engine_sound.volume_db = lerpf(-8.0, 0.0, clampf(load_amount + absf(forward_speed()) / top_speed, 0.0, 1.0))
		elif engine_sound.playing:
			engine_sound.stop()
	if third_person:
		_follow(delta, false)


func _unhandled_input(event: InputEvent) -> void:
	if driver != null and is_instance_valid(driver) and driver.controlled_locally and event.is_action_pressed("camera_toggle"):
		set_third_person(not third_person)
		get_viewport().set_input_as_handled()


## Switches the local driver's view between the cab and behind the truck.
func set_third_person(on: bool) -> void:
	if driver == null or not driver.controlled_locally:
		return
	third_person = on
	if on:
		_follow(0.0, true)
		chase_camera.make_current()
	else:
		driver.camera.make_current()


func _follow(delta: float, snap: bool) -> void:
	var f := global_basis * FORWARD
	var yaw := Basis(Vector3.UP, atan2(f.x, f.z))
	var want := global_position + yaw * CHASE_OFFSET
	chase_camera.global_position = want if snap else chase_camera.global_position.lerp(want, 1.0 - exp(-5.0 * delta))
	chase_camera.look_at(global_position + Vector3.UP * 1.6 + f * 3.0, Vector3.UP)


## Crates in the bed show how full it is.
func _update_crates() -> void:
	if crates == null or cargo == null or cargo.inventory == null:
		return
	var inv := cargo.inventory
	var used := inv.slot_count - inv.get_free_slot_count()
	var shown := ceili(float(used) / inv.slot_count * crates.get_child_count()) if used > 0 else 0
	for i in crates.get_child_count():
		(crates.get_child(i) as Node3D).visible = i < shown


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var p := global_position
	var q := global_basis.get_rotation_quaternion()
	return {"position": [p.x, p.y, p.z], "rotation": [q.x, q.y, q.z, q.w], "fuel": fuel, "odometer": odometer}


func load_state(data: Dictionary) -> void:
	if driver != null and is_instance_valid(driver):
		driver.leave_vehicle(true)
	var raw_p: Variant = data.get("position")
	var raw_q: Variant = data.get("rotation")
	var xform := global_transform
	if raw_p is Array and raw_p.size() == 3 and raw_p.all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))):
		xform.origin = Vector3(raw_p[0], raw_p[1], raw_p[2])
	if raw_q is Array and raw_q.size() == 4 and raw_q.all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))):
		var q := Quaternion(raw_q[0], raw_q[1], raw_q[2], raw_q[3])
		if q.length() > 0.5:
			xform.basis = Basis(q.normalized())
	freeze = false
	_parked_for = 0.0
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_position = global_position
	var f: Variant = data.get("fuel")
	if (f is float or f is int) and is_finite(float(f)):
		fuel = clampf(float(f), 0.0, fuel_capacity)
	var o: Variant = data.get("odometer")
	if (o is float or o is int) and is_finite(float(o)):
		odometer = maxf(float(o), 0.0)
	_told_empty = fuel <= 0.0
