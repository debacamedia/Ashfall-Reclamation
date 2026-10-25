class_name AttachmentDefinition
extends Resource
## A weapon attachment: red dot, scope, suppressor, extended magazine,
## foregrip. Fitted at the weapons bench; changes the gun's stats while it's
## on (HitscanWeapon.recompute_stats) and shows its model on the gun's mount.
##
## Every effect is a multiplier (1 = no change) or an override (0 = keep), so
## one attachment can do several things.

enum Slot { OPTIC, MUZZLE, MAGAZINE, UNDERBARREL }

@export var id: StringName = &"attachment"
@export var display_name := "Attachment"
@export var slot: Slot = Slot.OPTIC
## Weapon ids it fits (WeaponDefinition.id).
@export var compatible: Array[StringName] = []
## Model shown on the gun, authored with its origin at the mount point. An
## optic's model contains a Marker3D named "Sight" on its sight line.
@export_file("*.tscn") var model_path := ""

@export_group("Aiming")
## Replaces the gun's zoom (0 = keep).
@export var ads_zoom := 0.0
## Multiplies the gun's zoom (red dots magnify a little).
@export var ads_zoom_multiplier := 1.0
@export var scope_overlay := false
@export var ads_time_multiplier := 1.0
@export var ads_spread_multiplier := 1.0
@export var ads_move_multiplier := 1.0

@export_group("Handling")
@export var hip_spread_multiplier := 1.0
@export var recoil_multiplier := 1.0
## Extra magazine capacity as a fraction (0.5 = +50%).
@export var magazine_bonus := 0.0
@export var reload_time_multiplier := 1.0

@export_group("Signature")
## Suppressors: how far shots are heard.
@export var noise_multiplier := 1.0
@export var damage_multiplier := 1.0
## Muzzle flash size.
@export var flash_multiplier := 1.0


func fits(weapon_id: StringName) -> bool:
	return compatible.has(weapon_id)


static func slot_name(s: Slot) -> String:
	return ["Optic", "Muzzle", "Magazine", "Underbarrel"][s]
