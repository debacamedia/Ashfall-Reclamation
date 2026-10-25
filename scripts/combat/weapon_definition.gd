class_name WeaponDefinition
extends Resource
## Data for one firearm type, saved as a .tres in resources/items/weapons/.
## Tune weapons by editing the .tres in the Inspector, never in code.
## Later this becomes the weapon half of an ItemDefinition (inventory).

enum FireMode { SEMI_AUTO, FULL_AUTO }

@export var id: StringName = &"weapon"
@export var display_name := "Weapon"
## Short name for the HUD slot strip ("RIFLE").
@export var short_name := "WEAPON"
## Loadout slot (number key): 1 rifle, 2 sidearm, 3 shotgun, 4 marksman,
## 5 melee.
@export_range(1, 5) var slot := 1
## Better guns have a higher tier; crafting never replaces a gun in the
## same slot with a worse one (pipe pistol 0 < pistol 1).
@export var tier := 1
## The weapon scene (a HitscanWeapon root) the loadout instances. A path,
## not a PackedScene, because the scene itself references this definition.
@export_file("*.tscn") var scene_path := ""


func instantiate_weapon() -> HitscanWeapon:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return null
	var w := (load(scene_path) as PackedScene).instantiate() as HitscanWeapon
	if w != null:
		w.definition = self
	return w

@export_group("Damage")
@export var damage := 30.0
## Damage starts dropping beyond this distance (m)...
@export var falloff_start := 50.0
## ...and reaches its minimum here (m).
@export var falloff_end := 200.0
@export_range(0.0, 1.0) var falloff_min_multiplier := 0.6
@export var max_range := 300.0
## Rays per shot. Shotguns fire several pellets, each doing `damage` and
## spread across the cone (base_spread).
@export_range(1, 20) var pellets := 1

@export_group("Melee")
## A blade: no ammo, no aiming; each swing checks a short fan of rays.
@export var melee := false
## Total width of the swing (degrees) and how many rays cover it.
@export var melee_arc := 60.0
@export_range(1, 15) var melee_rays := 7

@export_group("Handling")
@export var fire_mode: FireMode = FireMode.FULL_AUTO
@export var rounds_per_minute := 600.0
@export var magazine_size := 30
## Spare rounds carried at the start. Becomes inventory ammo in Increment 6.
@export var starting_reserve := 90
## Most spare rounds that can be carried.
@export var max_reserve := 240
## Which ammo items refill this weapon (ItemDefinition.ammo_type).
@export var ammo_type: StringName = &"rifle_556"
@export var reload_time := 2.3
## Load one round per `reload_time` (shotgun shells) instead of a whole
## magazine. Firing interrupts the reload if there's a round chambered.
@export var reload_per_round := false
## Seconds to raise this weapon after switching to it.
@export var draw_time := 0.45
## Seconds after a shot before the pump/bolt sound (0 = none).
@export var cycle_sound_delay := 0.0

## Enemies within this distance hear each shot (m). 0 = silent.
@export var noise_radius := 60.0

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

@export_group("Aiming down sights")
## Camera zoom while aiming (1.0 = none). FOV is divided by this.
@export_range(1.0, 8.0, 0.05) var ads_zoom := 1.4
## Seconds to raise the sights fully.
@export var ads_time := 0.2
## Spread and recoil multipliers at full aim.
@export_range(0.0, 1.0) var ads_spread_multiplier := 0.35
@export_range(0.0, 1.0) var ads_recoil_multiplier := 0.65
## Movement speed multiplier at full aim.
@export_range(0.1, 1.0) var ads_move_multiplier := 0.55
## How far in front of the eye the rear of the sight sits (m).
@export var ads_eye_distance := 0.2
## Full-screen scope view when aimed (the gun model is hidden).
@export var scope_overlay := false

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
