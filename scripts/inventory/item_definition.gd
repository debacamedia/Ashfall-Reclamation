class_name ItemDefinition
extends Resource
## Data for one kind of item, saved as a .tres in resources/items/.
## Items are identified by `id` everywhere (saves, trading, recipes), so never
## change an id once it ships.

enum Category { RESOURCE, AMMO, MEDICAL, WEAPON, TOOL, MISC, PART, ATTACHMENT, STRUCTURE, EQUIPMENT }

@export var id: StringName = &"item"
@export var display_name := "Item"
@export_multiline var description := ""
@export var category: Category = Category.RESOURCE
@export var icon: Texture2D

@export_group("Stacking and weight")
@export var max_stack := 50
## Kilograms per unit; drives carrying capacity (Increment 6).
@export var weight := 0.5

@export_group("Economy")
## Base price in Marks before supply and demand.
@export var base_value := 1

@export_group("World")
## Model shown when the item lies in the world (pickup).
@export var world_model: PackedScene
## Seconds the interact key must be held to pick it up (0 = instant).
@export var pickup_hold_time := 0.0
## Sound played when picked up.
@export var pickup_sound: AudioStream

@export_group("Use")
## Health restored when used (medical items).
@export var heal_amount := 0.0
## Seconds it takes to use one (medkits: 2 s, during which the gun is lowered).
@export var use_time := 0.0
## Sound played when the use completes.
@export var use_sound: AudioStream
## For ammo items: the weapon ammo type this refills (matches WeaponDefinition.ammo_type).
@export var ammo_type: StringName = &""
## For weapon items: the gun you get when you pick it up (it goes into its
## loadout slot, not the inventory grid).
@export var weapon: WeaponDefinition
## For attachment items: what fitting it does.
@export var attachment: AttachmentDefinition
## Structure kits (Increment 13): what this kit builds in build mode (B).
@export var structure: StructureDefinition


@export_group("Backpack")
## A backpack you can wear (Increment 16.8): how many slots it gives you…
@export var pack_slots := 0
## …and how much it carries (kg). Worn, its own weight doesn't count.
@export var pack_carry_weight := 0.0
## A big frame pack rattles: moving makes a noise raiders hear this far
## (m) when walking, half again when sprinting; never when crouched. 0 = quiet.
@export var pack_rattle_radius := 0.0


## A backpack you can wear.
func is_pack() -> bool:
	return pack_slots > 0 and pack_carry_weight > 0.0


func get_label(quantity: int) -> String:
	return display_name if quantity <= 1 else "%s ×%d" % [display_name, quantity]
