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
