class_name HealthComponent
extends Node
## Reusable health for anything that can be damaged: players, NPCs, target
## dummies, later structures. Add it as a child node (named "HealthComponent").
##
## Weapons find it with HealthComponent.find_on(collider), which checks the
## hit node and up to three of its parents, so the collider can be nested
## below the object that owns the health.
##
## AUTHORITY: apply_damage(), heal() and revive() change game state. In co-op
## only the host calls them; clients just listen to the signals.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, info: DamageInfo)
signal healed(amount: float)
signal died(info: DamageInfo)
signal revived

@export var max_health := 100.0
## Ignores all damage (cutscenes, safe zones, debugging).
@export var invulnerable := false

var current_health := 0.0
var _dead := false


func _ready() -> void:
	current_health = max_health


func is_dead() -> bool:
	return _dead


func get_fraction() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


## Applies damage and returns how much was actually removed.
func apply_damage(info: DamageInfo) -> float:
	if _dead or invulnerable or info == null or info.amount <= 0.0:
		return 0.0
	var dealt := minf(info.amount, current_health)
	current_health -= dealt
	damaged.emit(dealt, info)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		current_health = 0.0
		_dead = true
		died.emit(info)
	return dealt


## Restores health (not above max). Returns the amount restored.
func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var restored := minf(amount, max_health - current_health)
	if restored <= 0.0:
		return 0.0
	current_health += restored
	healed.emit(restored)
	health_changed.emit(current_health, max_health)
	return restored


## Brings a dead component back with a fraction of max health.
func revive(health_fraction := 1.0) -> void:
	_dead = false
	current_health = max_health * clampf(health_fraction, 0.01, 1.0)
	revived.emit()
	health_changed.emit(current_health, max_health)


## Finds the HealthComponent belonging to `node`: a child of the node itself
## or of one of its first three ancestors. Returns null if there is none.
static func find_on(node: Node) -> HealthComponent:
	var current := node
	for i in 4:
		if current == null:
			return null
		for child in current.get_children():
			if child is HealthComponent:
				return child
		current = current.get_parent()
	return null
