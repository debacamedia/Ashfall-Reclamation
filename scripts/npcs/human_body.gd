class_name HumanBody
extends Node3D
## A person (Increment 29): one of the Quaternius base bodies, dressed by
## shaders/human_body (shirt, trousers and boots coloured per person), with
## hair, playing the Universal Animation Library's animations. Settlers and
## raiders both wear one, under their Visual node.
##
## Faces -Z like the settlers and raiders (the body itself faces +Z, so it's
## turned round). Gear goes on bones with slot(): a hat on "Head", a gun in
## "RightHand". Nodes under it with a "slot" meta are moved onto that bone
## when it's built, keeping their transform as an offset from the bone.

const LIBRARY := "res://assets/characters/quaternius/animations/AnimationLibrary_Godot_Standard.glb"
const BODIES := {
	false: ["res://assets/characters/quaternius/bodies/Superhero_Male_FullBody.gltf", "SuperHero_Male", "res://assets/characters/quaternius/bodies/male_dressed.res"],
	true: ["res://assets/characters/quaternius/bodies/Superhero_Female_FullBody.gltf", "Superhero_Female", "res://assets/characters/quaternius/bodies/female_dressed.res"],
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

var skeleton: Skeleton3D
var anim: AnimationPlayer
var body_mesh: MeshInstance3D
var _slots := {}
var _current := &""
var _built := false

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
	body_mesh.mesh = load(spec[2])
	body_mesh.material_override = _body_material()
	# Hair (rigged to the same skeleton)
	if hair != &"":
		_add_hair(hair)
	# A beard comes with short hair
	if hair == &"Hair_Beard":
		_add_hair(&"Hair_Buzzed")
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
	var key := "hair_%s" % String(id)
	var mat := hm.get_active_material(0)
	if mat is StandardMaterial3D:
		var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = hair_colour * 1.6
		hm.material_override = m
	hs.free()


func apply_colours() -> void:
	if body_mesh == null:
		return
	body_mesh.set_instance_shader_parameter(&"shirt_color", shirt)
	body_mesh.set_instance_shader_parameter(&"trousers_color", trousers)
	body_mesh.set_instance_shader_parameter(&"boots_color", boots)
	body_mesh.set_instance_shader_parameter(&"long_sleeves", 1.0 if long_sleeves else 0.0)
	body_mesh.set_instance_shader_parameter(&"skin_tint", (SKIN_TONES[skin_tone][1] as Color))


## Something worn over the shirt or trousers (armour, Wool Clothes): its
## colour, and whether it's metal. A null colour takes it off.
func set_worn(region: StringName, colour: Variant, metal := 0.0) -> void:
	if body_mesh == null:
		return
	if region == &"body":
		body_mesh.set_instance_shader_parameter(&"shirt_color", colour if colour != null else shirt)
		body_mesh.set_instance_shader_parameter(&"shirt_metal", metal if colour != null else 0.0)
		body_mesh.set_instance_shader_parameter(&"long_sleeves", 1.0 if colour != null or long_sleeves else 0.0)
	elif region == &"legs":
		body_mesh.set_instance_shader_parameter(&"trousers_color", colour if colour != null else trousers)
		body_mesh.set_instance_shader_parameter(&"trousers_metal", metal if colour != null else 0.0)


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
