class_name SpikeTrap
extends Structure
## Sharpened stakes on a frame. Raiders who step in take damage (once a
## second while they stay in it); each hit wears the trap down, so it breaks
## after about ten. Your own traps don't hurt you. Not an obstacle: raiders
## don't know to avoid it.
##
## Scene: res://scenes/structures/spike_trap.tscn. Root → %Spikes (Area3D,
## mask NPCS) + meshes, %HitSound.

@export var damage := 25.0
@export var wear_per_hit := 10.0
@export var interval := 1.0

var _cooldowns := {}  # body -> seconds until it can be hurt again

@onready var _spikes: Area3D = %Spikes


func _physics_process(delta: float) -> void:
	for body in _cooldowns.keys():
		_cooldowns[body] -= delta
		if _cooldowns[body] <= 0.0 or not is_instance_valid(body):
			_cooldowns.erase(body)
	if health <= 0.0:
		return
	for body in _spikes.get_overlapping_bodies():
		if _cooldowns.has(body) or not body.is_in_group("enemies"):
			continue
		var h := body.get_node_or_null("%HealthComponent") as HealthComponent
		if h == null or h.is_dead():
			continue
		var info := DamageInfo.create(damage, DamageInfo.Type.ENVIRONMENT, self)
		info.hit_position = body.global_position + Vector3.UP * 0.3
		h.apply_damage(info)
		_cooldowns[body] = interval
		apply_damage(wear_per_hit, body)
		if health <= 0.0:
			return
