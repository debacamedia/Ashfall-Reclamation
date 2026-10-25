class_name RandomSoundEmitter
extends AudioStreamPlayer3D
## Plays its stream now and then from a fixed spot: a metal clank from the
## motor pool, a creak from a tower. Each play waits a random time between
## `min_interval` and `max_interval` and varies the pitch a little, so it
## doesn't sound like a loop.
##
## Purely cosmetic: no gameplay, no saving. Raiders don't hear it.

@export var min_interval := 9.0
@export var max_interval := 24.0
## Pitch is picked from 1 ± this.
@export_range(0.0, 0.5) var pitch_variation := 0.15

var _rng := RandomNumberGenerator.new()
var _wait := 0.0


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(min_interval * 0.3, max_interval)


func _process(delta: float) -> void:
	if stream == null:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	play()
	_wait = _rng.randf_range(min_interval, max_interval)
