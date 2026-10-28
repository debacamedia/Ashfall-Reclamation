class_name DamageInfo
extends RefCounted
## Everything a HealthComponent needs to know about one instance of damage.
## Built by whoever deals damage (weapon, melee, fall, explosion) and passed to
## HealthComponent.apply_damage(). Listeners of `damaged`/`died` read it for
## hit reactions, kill feeds and AI awareness.

enum Type { BALLISTIC, MELEE, FALL, EXPLOSIVE, ENVIRONMENT, VEHICLE }

var amount := 0.0
var type: Type = Type.BALLISTIC
## The node responsible (the shooter), or null for environment damage.
var source: Node = null
var hit_position := Vector3.ZERO
var hit_normal := Vector3.ZERO
## Direction the damage travelled (e.g. the bullet direction).
var direction := Vector3.ZERO
## Hit-zone multiplier already included in `amount` (2.0 = headshot).
var zone_multiplier := 1.0


static func create(amount_value: float, damage_type: Type, source_node: Node = null) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_value
	info.type = damage_type
	info.source = source_node
	return info
