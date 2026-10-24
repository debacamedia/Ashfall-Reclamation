class_name DamageZone
extends Area3D
## Hurts anything with a HealthComponent that stays inside it: fire, toxic
## water, radiation, electrified fences. Damage is applied in steps every
## `tick_interval` seconds, the first step immediately on entering.
##
## Needs a CollisionShape3D child. Put the zone on the "triggers" layer (7)
## and let it detect players and NPCs (layers 3 and 4).
##
## AUTHORITY: damage is only applied where the game state lives (host).

signal damaged_body(body: Node3D, amount: float)

@export var damage_per_second := 12.0
@export var damage_type: DamageInfo.Type = DamageInfo.Type.ENVIRONMENT
@export var tick_interval := 0.5
@export var enabled := true
## Shown on the death screen if this zone kills a player.
@export var death_message := "You were killed by the environment"

## body -> seconds until its next damage step
var _timers := {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	for body: Node3D in _timers.keys():
		if not is_instance_valid(body):
			_timers.erase(body)
			continue
		_timers[body] -= delta
		if _timers[body] <= 0.0:
			_timers[body] += tick_interval
			_hurt(body)


func _on_body_entered(body: Node3D) -> void:
	if HealthComponent.find_on(body) == null:
		return
	_timers[body] = 0.0  # first step on the next physics tick


func _on_body_exited(body: Node3D) -> void:
	_timers.erase(body)


func _hurt(body: Node3D) -> void:
	var health := HealthComponent.find_on(body)
	if health == null or health.is_dead():
		return
	var info := DamageInfo.create(damage_per_second * tick_interval, damage_type, self)
	info.hit_position = body.global_position
	info.direction = (body.global_position - global_position).normalized()
	var dealt := health.apply_damage(info)
	if dealt > 0.0:
		damaged_body.emit(body, dealt)
