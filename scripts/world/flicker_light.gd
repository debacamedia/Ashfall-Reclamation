extends OmniLight3D
## Makes a light flicker like fire. Purely visual.

@export var base_energy := 2.0
@export var flicker_amount := 0.6
@export var speed := 12.0

var _time := 0.0


func _ready() -> void:
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * speed
	var n := sin(_time) * 0.5 + sin(_time * 2.3 + 1.7) * 0.3 + sin(_time * 5.1) * 0.2
	light_energy = base_energy + n * flicker_amount
