class_name TargetDummy
extends Node3D
## Range target: shows damage numbers, flinches when hit, falls back when its
## health runs out, then resets after a delay. Its torso and head are separate
## collision shapes so headshots (damage_multiplier = 2) can be tested.
##
## Scene: res://scenes/world/range/target_dummy.tscn

signal reset_finished

## Seconds lying down before standing back up.
@export var reset_delay := 3.0
@export var show_damage_numbers := true

@onready var health: HealthComponent = %HealthComponent
@onready var hinge: Node3D = %Hinge
@onready var damage_label: Label3D = %DamageLabel
@onready var _ping_sound: AudioStreamPlayer3D = get_node_or_null("%PingSound")

var _label_timer := 0.0
var _hit_tween: Tween


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	damage_label.visible = false


func _process(delta: float) -> void:
	if _label_timer > 0.0:
		_label_timer -= delta
		damage_label.position.y += delta * 0.3
		damage_label.modulate.a = clampf(_label_timer / 0.4, 0.0, 1.0)
		if _label_timer <= 0.0:
			damage_label.visible = false


func _on_damaged(amount: float, info: DamageInfo) -> void:
	if _ping_sound != null:
		_ping_sound.play()
	if show_damage_numbers:
		damage_label.text = ("%d!" if info.zone_multiplier > 1.0 else "%d") % roundi(amount)
		damage_label.modulate = Color(1.0, 0.85, 0.2) if info.zone_multiplier > 1.0 else Color.WHITE
		damage_label.position = Vector3(0, 2.15, 0)
		damage_label.visible = true
		_label_timer = 0.8
	if health.is_dead():
		return
	# Small flinch backwards
	if _hit_tween != null:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(hinge, "rotation_degrees:x", -9.0, 0.05)
	_hit_tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_died(_info: DamageInfo) -> void:
	if _hit_tween != null:
		_hit_tween.kill()
	var tween := create_tween()
	tween.tween_property(hinge, "rotation_degrees:x", -85.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(reset_delay)
	tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_reset)


func _reset() -> void:
	health.revive()
	reset_finished.emit()
