class_name HumanBody
extends Node3D
## A person (Increment 29): one of the Quaternius base bodies with hair,
## playing the Universal Animation Library's animations. Settlers and raiders
## both wear one, under their Visual node.
##
## Dressed (29.1) in Quaternius's Modular Character Outfits: a shirt with its
## sleeves, trousers and boots, each from the Peasant or the Ranger outfit in
## one of two colourways, tinted per person (shaders/outfit). Under them only
## the base body's head is drawn. What they wear over their clothes (armour,
## Wool Clothes) swaps the pieces: wear().
##
## Faces -Z like the settlers and raiders (the body itself faces +Z, so it's
## turned round). Gear goes on bones with slot(): a hat on "Head", a gun in
## "RightHand". Nodes under it with a "slot" meta are moved onto that bone
## when it's built, keeping their transform as an offset from the bone.

const LIBRARY := "res://assets/characters/quaternius/animations/AnimationLibrary_Godot_Standard.glb"
const BODIES := {
	false: ["res://assets/characters/quaternius/bodies/Superhero_Male_FullBody.gltf", "SuperHero_Male", "res://assets/characters/quaternius/bodies/male_head.res"],
	true: ["res://assets/characters/quaternius/bodies/Superhero_Female_FullBody.gltf", "Superhero_Female", "res://assets/characters/quaternius/bodies/female_head.res"],
}
## The outfits (29.1): their colourways, and normal and occlusion-roughness-
## metal maps
const OUTFIT_DIR := "res://assets/characters/quaternius/outfits/"
const OUTFIT_WAYS := {
	&"peasant": ["T_Peasant_BaseColor.png", "T_Peasant_2_BaseColor.png"],
	&"ranger": ["T_Ranger_BaseColor.png", "T_Ranger_3_BaseColor.png"],
}
const OUTFIT_MAPS := {
	&"peasant": ["T_Peasant_Normal.png", "T_Peasant_ORM.png"],
	&"ranger": ["T_Ranger_Normal.png", "T_Ranger_ORM.png"],
}
## The pieces of someone's clothes
const PIECES: Array[StringName] = [&"body", &"arms", &"legs", &"feet", &"hood", &"pauldrons"]
## Settlers' clothes, worn and washed out
const SETTLER_TINTS := [Color(1.0, 1.0, 1.0), Color(0.95, 0.93, 0.9), Color(1.0, 0.95, 0.88), Color(0.9, 0.92, 0.96),
	Color(0.84, 0.82, 0.78), Color(1.04, 1.0, 0.94)]
## What's worn over the clothes (wear()): the piece of an outfit it's drawn
## as: [outfit, colourway, tint]
const WORN := {
	&"body": {"leather": [&"ranger", 1, Color(1.0, 1.0, 1.0)], "padded": [&"ranger", 0, Color(0.95, 0.95, 0.9)],
		"wool": [&"peasant", 0, Color(1.05, 1.02, 0.96)], "plated": [&"ranger", 1, Color(0.82, 0.82, 0.84)]},
	&"legs": {"leather": [&"ranger", 1, Color(1.0, 1.0, 1.0)], "padded": [&"ranger", 0, Color(0.95, 0.95, 0.9)],
		"wool": [&"peasant", 0, Color(1.05, 1.02, 0.96)], "plated": [&"ranger", 1, Color(0.82, 0.82, 0.84)]},
	&"head": {"leather": [&"ranger", 1, Color(1.0, 1.0, 1.0)], "padded": [&"ranger", 0, Color(0.95, 0.95, 0.9)]},
}
const SKIN_TEXTURES := {
	"male_light": "res://assets/characters/quaternius/bodies/T_Superhero_Male_Light.png",
	"male_dark": "res://assets/characters/quaternius/bodies/T_Superhero_Male_Dark.png",
	"female_light": "res://assets/characters/quaternius/bodies/T_Superhero_Female_Light.png",
	"female_dark": "res://assets/characters/quaternius/bodies/T_Superhero_Female_Dark_BaseColor.png",
}
const NORMALS := {
	false: "res://assets/characters/quaternius/bodies/T_Superhero_Male_Normal.png",
	true: "res://assets/characters/quaternius/bodies/T_Superhero_Female_Normal.png",
}
const HAIR_DIR := "res://assets/characters/quaternius/hair/"
const HAIRS_MALE := [&"Hair_SimpleParted", &"Hair_Buzzed", &"Hair_Long", &"Hair_Beard", &""]
const HAIRS_FEMALE := [&"Hair_Long", &"Hair_Buns", &"Hair_BuzzedFemale", &"Hair_SimpleParted"]
const HAIR_COLOURS := [Color(0.16, 0.11, 0.07), Color(0.32, 0.2, 0.1), Color(0.55, 0.38, 0.2),
	Color(0.08, 0.07, 0.06), Color(0.72, 0.6, 0.38), Color(0.5, 0.48, 0.46), Color(0.45, 0.18, 0.08)]
## Skin: [light or dark texture, tint]
const SKIN_TONES := [["light", Color(1.0, 0.95, 0.9)], ["light", Color(1.0, 0.88, 0.78)], ["light", Color(0.92, 0.78, 0.66)],
	["dark", Color(1.15, 1.08, 1.0)], ["dark", Color(1.0, 1.0, 1.0)], ["dark", Color(0.8, 0.78, 0.76)]]

@export var female := false
@export var skin_tone := 0
@export var hair: StringName = &"Hair_SimpleParted"
@export var hair_colour := Color(0.16, 0.11, 0.07)
@export var shirt := Color(0.5, 0.4, 0.3)
@export var trousers := Color(0.28, 0.27, 0.24)
@export var boots := Color(0.22, 0.16, 0.11)
@export var long_sleeves := true
## Build when it enters the tree (a settler or raider builds it itself,
## once it's picked its looks).
@export var build_on_ready := false
## Colours vary this much person to person (raiders' palettes).
@export var colour_jitter := 0.0
## What they wear (29.1): an outfit ("peasant" or "ranger") and its
## colourway for the shirt (with its sleeves), the trousers and the boots.
## pick_looks() picks them.
@export var top: StringName = &"peasant"
@export var top_way := 0
@export var bottoms: StringName = &"peasant"
@export var bottoms_way := 0
@export var footwear: StringName = &"peasant"
@export var footwear_way := 0
## How pick_looks() dresses them: "settler" (peasant clothes mostly, washed
## out) or "raider" (ranger clothes mostly, tinted by cloth_tint).
@export var outfit_style: StringName = &"settler"
@export var cloth_tint := Color(1.0, 1.0, 1.0)
## The Ranger's pauldrons over their clothes (Raider Veterans, Marauders),
## in this tint
@export var pauldrons := false
@export var pauldron_tint := Color(1.0, 1.0, 1.0)

var skeleton: Skeleton3D
var anim: AnimationPlayer
var body_mesh: MeshInstance3D
var _slots := {}
var _current := &""
var _built := false
## Their clothes' tint (cloth_tint, varied per person)
var tint := Color(1.0, 1.0, 1.0)
## What's worn over the clothes: region ("body", "legs", "head",
## "shoulders") -> kind
var _worn := {}
## The pieces drawn now: piece -> {"spec": [outfit, way, tint], "meshes": [MeshInstance3D]}
var _pieces := {}
var _hair: Array[MeshInstance3D] = []

static var _library: AnimationLibrary
static var _materials := {}
static var _scenes := {}


func _ready() -> void:
	if build_on_ready:
		build()


## Picks a body, skin, hair and hair colour from a seed (the same seed, the
## same person).
func pick_looks(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	female = rng.randf() < 0.45
	skin_tone = rng.randi() % SKIN_TONES.size()
	var hairs: Array = HAIRS_FEMALE if female else HAIRS_MALE
	hair = hairs[rng.randi() % hairs.size()]
	hair_colour = HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()]
	if colour_jitter > 0.0:
		for prop in [&"shirt", &"trousers", &"boots"]:
			var c: Color = get(prop)
			var k := 1.0 + rng.randf_range(-colour_jitter, colour_jitter)
			set(prop, Color(c.r * k * rng.randf_range(0.92, 1.08), c.g * k, c.b * k * rng.randf_range(0.92, 1.08)))
	# Their clothes (29.1)
	if outfit_style == &"raider":
		top = &"ranger" if rng.randf() < 0.75 else &"peasant"
		bottoms = &"ranger" if rng.randf() < 0.7 else &"peasant"
		footwear = &"ranger"
		var k := 1.0 + rng.randf_range(-colour_jitter, colour_jitter) * 0.6
		tint = Color(cloth_tint.r * k * rng.randf_range(0.94, 1.06), cloth_tint.g * k, cloth_tint.b * k * rng.randf_range(0.94, 1.06))
	else:
		top = &"peasant" if rng.randf() < 0.7 else &"ranger"
		bottoms = &"peasant" if rng.randf() < 0.6 else &"ranger"
		footwear = &"ranger" if rng.randf() < 0.5 else &"peasant"
		var t: Color = SETTLER_TINTS[rng.randi() % SETTLER_TINTS.size()]
		tint = Color(t.r * cloth_tint.r, t.g * cloth_tint.g, t.b * cloth_tint.b)
	top_way = rng.randi() % 2
	bottoms_way = rng.randi() % 2
	footwear_way = rng.randi() % 2


## Built again with new looks: the gear on the bones comes back under us
## first, so it isn't lost with the old body.
func rebuild() -> void:
	if not _built:
		build()
		return
	for b: BoneAttachment3D in _slots.values():
		for c in b.get_children():
			var xf := (c as Node3D).transform
			b.remove_child(c)
			add_child(c)
			(c as Node3D).transform = xf
	var old := get_node_or_null("Body")
	if old != null:
		remove_child(old)
		old.free()
	_slots.clear()
	_pieces.clear()
	_hair.clear()
	_current = &""
	_built = false
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var spec: Array = BODIES[female]
	var scene := (_scene(spec[0])).instantiate() as Node3D
	scene.name = "Body"
	scene.rotation.y = PI  # it faces +Z; settlers and raiders face -Z
	add_child(scene)
	skeleton = scene.find_child("GeneralSkeleton", true, false) as Skeleton3D
	body_mesh = scene.find_child(spec[1], true, false) as MeshInstance3D
	# Just the head: the outfit is the rest (29.1)
	body_mesh.mesh = load(spec[2])
	body_mesh.material_override = _body_material()
	var brows := scene.find_child("Eyebrows", true, false) as MeshInstance3D
	if brows != null:
		_colour_hair(brows)
	# Hair (rigged to the same skeleton)
	if hair != &"":
		_add_hair(hair)
	# A beard comes with short hair
	if hair == &"Hair_Beard":
		_add_hair(&"Hair_Buzzed")
	_refresh_outfit()
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	scene.add_child(anim)
	anim.add_animation_library(&"", _animations())
	anim.play(&"Idle")
	# Standing as at the start of Idle: gear is laid out on that pose (the
	# bones' rest is a T-pose, and the spine leans in it)
	anim.seek(0.0, true)
	skeleton.force_update_all_bone_transforms()
	apply_colours()
	# Gear laid out under us goes on its bone. It's laid out in the body's
	# own frame (+Y up, +Z the way they face) as an offset from where the
	# bone is standing in Idle, so the bones' own axes don't matter; gear
	# for the hands (meta "space": "bone") is laid out in the hand's frame.
	for c in get_children():
		if c != scene and c.has_meta("slot"):
			var n := c as Node3D
			# (laid out once: a rebuild puts it back where it was laid out)
			if not n.has_meta("layout"):
				n.set_meta("layout", n.transform)
			var xf: Transform3D = n.get_meta("layout")
			var bone := String(n.get_meta("slot"))
			remove_child(n)
			slot(bone).add_child(n)
			if String(n.get_meta("space", "body")) == "bone":
				n.transform = xf
			else:
				var stand := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
				var inv := stand.basis.orthonormalized().inverse()
				n.transform = Transform3D(inv * xf.basis, inv * xf.origin)


func _add_hair(id: StringName) -> void:
	var hs := (_scene(HAIR_DIR + String(id) + ".gltf")).instantiate()
	var hm := hs.find_child(String(id), true, false) as MeshInstance3D
	if hm == null:
		hs.free()
		return
	hm.get_parent().remove_child(hm)
	hm.owner = null
	skeleton.add_child(hm)
	hm.skeleton = NodePath("..")
	hm.set_meta("hair", id)
	_hair.append(hm)
	_colour_hair(hm)
	hs.free()


## Hair comes grey, to be tinted (the eyebrows too, 29.1).
func _colour_hair(hm: MeshInstance3D) -> void:
	var mat := hm.get_active_material(0)
	if mat is StandardMaterial3D:
		var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = hair_colour * 1.6
		hm.material_override = m


func apply_colours() -> void:
	if body_mesh == null:
		return
	body_mesh.set_instance_shader_parameter(&"skin_tint", (SKIN_TONES[skin_tone][1] as Color))
	for p: StringName in _pieces:
		var spec: Array = _pieces[p]["spec"]
		for mi: MeshInstance3D in _pieces[p]["meshes"]:
			_colour_piece(mi, spec[2])


func _colour_piece(mi: MeshInstance3D, piece_tint: Color) -> void:
	if mi.has_meta("skin"):
		mi.set_instance_shader_parameter(&"skin_tint", (SKIN_TONES[skin_tone][1] as Color))
	if mi.has_meta("cloth"):
		mi.set_instance_shader_parameter(&"tint", piece_tint)


## Something worn over their clothes (29.1): region "body", "legs" or
## "head"; kind "leather", "plated", "wool", "padded", or "" to take it off.
## Region "shoulders", any kind: the Ranger's pauldrons (a guard's).
## Drawn as an outfit's piece: a leather coat as the Ranger's, padded the
## Ranger's green, Wool Clothes the Peasant's, plate the Ranger's greyed with
## pauldrons; a leather or padded cap as the Ranger's hood.
func wear(region: StringName, kind: String) -> void:
	if kind == "":
		_worn.erase(region)
	else:
		_worn[region] = kind
	_refresh_outfit()


## What's worn over a region ("" for nothing).
func worn(region: StringName) -> String:
	return _worn.get(region, "")


## Which outfit a piece is from now ("body", "arms", "legs", "feet", "hood",
## "pauldrons"), or &"" if it isn't drawn.
func outfit_of(piece: StringName) -> StringName:
	return (_pieces[piece]["spec"] as Array)[0] if _pieces.has(piece) else &""


## The meshes of a piece drawn now.
func piece_meshes(piece: StringName) -> Array:
	return _pieces[piece]["meshes"] if _pieces.has(piece) else []


func _piece_specs() -> Dictionary:
	var specs := {&"body": [top, top_way, tint], &"arms": [top, top_way, tint], &"legs": [bottoms, bottoms_way, tint],
		&"feet": [footwear, footwear_way, tint], &"hood": null, &"pauldrons": null}
	if pauldrons:
		specs[&"pauldrons"] = [&"ranger", 1, pauldron_tint]
	elif _worn.has(&"shoulders"):
		specs[&"pauldrons"] = [&"ranger", 1, tint]
	var over: String = _worn.get(&"body", "")
	if WORN[&"body"].has(over):
		specs[&"body"] = WORN[&"body"][over]
		specs[&"arms"] = WORN[&"body"][over]
		if over == "plated":
			specs[&"pauldrons"] = [&"ranger", 1, Color(1.0, 1.0, 1.0)]
	over = _worn.get(&"legs", "")
	if WORN[&"legs"].has(over):
		specs[&"legs"] = WORN[&"legs"][over]
	over = _worn.get(&"head", "")
	if WORN[&"head"].has(over):
		specs[&"hood"] = WORN[&"head"][over]
	return specs


## Puts on the pieces they should be wearing, leaving those already on.
func _refresh_outfit() -> void:
	if skeleton == null:
		return
	var specs := _piece_specs()
	for p: StringName in PIECES:
		var want: Variant = specs[p]
		if _pieces.has(p):
			if want != null and _pieces[p]["spec"] == want:
				continue
			for mi: MeshInstance3D in _pieces[p]["meshes"]:
				mi.get_parent().remove_child(mi)
				mi.free()
			_pieces.erase(p)
		if want == null:
			continue
		var meshes := _add_piece(p, want[0], want[1])
		for mi: MeshInstance3D in meshes:
			_colour_piece(mi, want[2])
		_pieces[p] = {"spec": want, "meshes": meshes}
	# Under a hood: no hair but a beard
	for hm in _hair:
		hm.visible = not _pieces.has(&"hood") or hm.get_meta("hair") == &"Hair_Beard"


func _piece_file(piece: StringName, outfit: StringName) -> String:
	var part := ""
	match piece:
		&"body": part = "Body"
		&"arms": part = "Arms"
		&"legs": part = "Legs"
		&"feet": part = "Feet_Boots" if outfit == &"ranger" and not female else "Feet"
		&"hood": part = "Head_Hood"
		&"pauldrons": part = "Acc_Pauldrons" if female else "Acc_Pauldron"
	return OUTFIT_DIR + "%s_%s_%s.gltf" % ["Female" if female else "Male", "Ranger" if outfit == &"ranger" else "Peasant", part]


## An outfit's piece, skinned to our skeleton (the outfits' is the same
## shape, within 2.5 cm at the shoulders and hips): its cloth in
## shaders/outfit, its bare skin (hands, forearms) in the body's.
func _add_piece(piece: StringName, outfit: StringName, way: int) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var path := _piece_file(piece, outfit)
	if not ResourceLoader.exists(path):
		return out
	var ps := _scene(path).instantiate()
	for m in ps.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.get_parent().remove_child(mi)
		mi.owner = null
		mi.name = "%s_%s" % [String(piece).capitalize(), mi.name]
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src != null and src.resource_name.contains("Regular"):
				mi.set_surface_override_material(i, _body_material())
				mi.set_meta("skin", true)
			else:
				mi.set_surface_override_material(i, _outfit_material(outfit, way))
				mi.set_meta("cloth", true)
		out.append(mi)
	ps.free()
	return out


static func _outfit_material(outfit: StringName, way: int) -> ShaderMaterial:
	var key := "outfit_%s_%d" % [outfit, way]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/outfit.gdshader")
		var ways: Array = OUTFIT_WAYS[outfit]
		m.set_shader_parameter(&"albedo_texture", load(OUTFIT_DIR + String(ways[way % ways.size()])))
		m.set_shader_parameter(&"normal_texture", load(OUTFIT_DIR + String(OUTFIT_MAPS[outfit][0])))
		m.set_shader_parameter(&"orm_texture", load(OUTFIT_DIR + String(OUTFIT_MAPS[outfit][1])))
		_materials[key] = m
	return _materials[key]


## A bone to hang gear on ("Head", "UpperChest", "Hips", "RightHand"…).
func slot(bone: String) -> BoneAttachment3D:
	if _slots.has(bone):
		return _slots[bone]
	var b := BoneAttachment3D.new()
	b.name = "Slot" + bone
	b.bone_name = bone
	skeleton.add_child(b)
	_slots[bone] = b
	return b


## Plays an animation, blending from the last; the same one again just
## carries on (with a new speed). One that plays through once is started
## again when it's over if `again` (a swing at work), held if not (a death).
func play(anim_name: StringName, speed := 1.0, blend := 0.2, restart := false, again := true) -> void:
	if anim == null:
		return
	anim.speed_scale = speed
	if anim_name == _current and not restart and (anim.is_playing() or not again):
		return
	_current = anim_name
	anim.play(anim_name, blend)
	if restart:
		anim.seek(0.0, true)


func current() -> StringName:
	return _current


## Seconds into the animation playing.
func position_in() -> float:
	return anim.current_animation_position if anim != null and anim.is_playing() else 0.0


func length_of(anim_name: StringName) -> float:
	return _animations().get_animation(anim_name).length if _animations().has_animation(anim_name) else 0.0


func _body_material() -> ShaderMaterial:
	var key := "%s_%s" % ["female" if female else "male", SKIN_TONES[skin_tone][0]]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/human_body.gdshader")
		m.set_shader_parameter(&"skin_texture", load(SKIN_TEXTURES[key]))
		m.set_shader_parameter(&"normal_texture", load(NORMALS[female]))
		m.set_shader_parameter(&"bare", true)
		_materials[key] = m
	return _materials[key]


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _animations() -> AnimationLibrary:
	if _library == null:
		var s := (load(LIBRARY) as PackedScene).instantiate()
		var ap := s.get_node("AnimationPlayer") as AnimationPlayer
		_library = ap.get_animation_library(&"")
		# Held at their last frame, not looped: these play through once
		for n in [&"Death01", &"Fixing_Kneeling", &"Interact", &"Sword_Attack", &"Pistol_Shoot", &"Hit_Chest", &"PickUp_Table", &"Sword_Idle"]:
			if _library.has_animation(n):
				_library.get_animation(n).loop_mode = Animation.LOOP_NONE
		s.free()
	return _library
