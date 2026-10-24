class_name WeaponDefinition
extends Resource
## Data for one firearm type, saved as a .tres in resources/items/weapons/.
## Tune weapons by editing the .tres in the Inspector, never in code.
## Later this becomes the weapon half of an ItemDefinition (inventory).

enum FireMode { SEMI_AUTO, FULL_AUTO }

@export var id: StringName = &"weapon"
@export var display_name := "Weapon"

@export_group("Damage")
@export var damage := 30.0
## Damage starts dropping beyond this distance (m)...
@export var falloff_start := 50.0
## ...and reaches its minimum here (m).
@export var falloff_end := 200.0
@export_range(0.0, 1.0) var falloff_min_multiplier := 0.6
@export var max_range := 300.0

@export_group("Handling")
@export var fire_mode: FireMode = FireMode.FULL_AUTO
@export var rounds_per_minute := 600.0
@export var magazine_size := 30
## Spare rounds carried at the start. Becomes inventory ammo in Increment 6.
@export var starting_reserve := 90
@export var reload_time := 2.3

@export_group("Accuracy (degrees)")
## Cone half-angle when standing still and not firing.
@export var base_spread := 0.35
## Extra spread added per shot (bloom)...
@export var spread_per_shot := 0.25
## ...up to this much extra...
@export var max_bloom := 3.0
## ...recovering at this rate per second...
@export var bloom_recovery := 6.0
## ...once this many seconds have passed since the last shot.
@export var bloom_recovery_delay := 0.2

@export_group("Recoil (degrees per shot)")
@export var recoil_pitch := 0.55
@export var recoil_yaw := 0.2


func get_shot_interval() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


func damage_at_distance(distance: float) -> float:
	if distance <= falloff_start:
		return damage
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.001), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min_multiplier, t)
