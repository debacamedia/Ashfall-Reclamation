class_name BulletImpact
extends Node3D
## Bullet hole decal plus a dust puff. Spawned by HitscanWeapon at each hit,
## oriented so local +Y points out of the surface. Frees itself after a while;
## the weapon also caps how many exist at once.
##
## Scene: res://scenes/weapons/effects/bullet_impact.tscn

@export var lifetime := 12.0
## Set by the weapon before the impact enters the tree.
var hard_surface := false


func _ready() -> void:
	add_to_group("bullet_impacts")
	var dust := get_node_or_null("%Dust") as GPUParticles3D
	if dust != null:
		dust.restart()
	var sound := get_node_or_null("%HardSound" if hard_surface else "%DirtSound") as AudioStreamPlayer3D
	if sound != null:
		sound.play()
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
