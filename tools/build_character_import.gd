extends SceneTree
## Increment 29: sets up the Quaternius characters' import so the Universal
## Animation Library's animations play on the Universal Base Characters.
##
## The two packs name their bones differently (the animations' rig is
## Rigify's "DEF-" bones, the bodies' is Unreal-style "pelvis", "spine_01"…),
## so each file is imported through a BoneMap onto Godot's humanoid profile:
## every skeleton becomes "GeneralSkeleton" with the profile's bone names and
## the same rest (axes overwritten, silhouette fixed), and an animation from
## the library plays on any body.
##
##   godot --headless --path . -s res://tools/build_character_import.gd
##   godot --headless --path . --import

const ROOT := "res://assets/characters/quaternius/"

## Profile bone: [animation rig bone, body bone]
const BONES := {
	&"Root": ["root", "root"],
	&"Hips": ["DEF-hips", "pelvis"],
	&"Spine": ["DEF-spine.001", "spine_01"],
	&"Chest": ["DEF-spine.002", "spine_02"],
	&"UpperChest": ["DEF-spine.003", "spine_03"],
	&"Neck": ["DEF-neck", "neck_01"],
	&"Head": ["DEF-head", "Head"],
}
const SIDES := {
	&"Shoulder": ["shoulder", "clavicle"],
	&"UpperArm": ["upper_arm", "upperarm"],
	&"LowerArm": ["forearm", "lowerarm"],
	&"Hand": ["hand", "hand"],
	&"UpperLeg": ["thigh", "thigh"],
	&"LowerLeg": ["shin", "calf"],
	&"Foot": ["foot", "foot"],
	&"Toes": ["toe", "ball"],
}
## Fingers: profile [Proximal, Intermediate, Distal] (the thumb's Metacarpal,
## Proximal, Distal) from the rigs' 01, 02, 03.
const FINGERS := {
	&"Thumb": ["thumb", "thumb", ["Metacarpal", "Proximal", "Distal"]],
	&"Index": ["f_index", "index", ["Proximal", "Intermediate", "Distal"]],
	&"Middle": ["f_middle", "middle", ["Proximal", "Intermediate", "Distal"]],
	&"Ring": ["f_ring", "ring", ["Proximal", "Intermediate", "Distal"]],
	&"Little": ["f_pinky", "pinky", ["Proximal", "Intermediate", "Distal"]],
}


func _initialize() -> void:
	var anim_map := _bone_map(0)
	var body_map := _bone_map(1)
	ResourceSaver.save(anim_map, ROOT + "bonemap_animations.tres")
	ResourceSaver.save(body_map, ROOT + "bonemap_bodies.tres")
	_patch(ROOT + "animations/AnimationLibrary_Godot_Standard.glb.import", "Rig/Skeleton3D", load(ROOT + "bonemap_animations.tres"), true)
	for d in ["bodies", "hair"]:
		for f in DirAccess.get_files_at(ROOT + d):
			if f.ends_with(".gltf.import"):
				_patch(ROOT + d + "/" + f, "Armature/Skeleton3D", load(ROOT + "bonemap_bodies.tres"), false)
	quit()


## which: 0 the animation rig's names, 1 the bodies'.
func _bone_map(which: int) -> BoneMap:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for p: StringName in BONES:
		bm.set_skeleton_bone_name(p, StringName(BONES[p][which]))
	for part: StringName in SIDES:
		var stem: String = SIDES[part][which]
		for side in ["Left", "Right"]:
			var name := ("DEF-%s.%s" % [stem, "L" if side == "Left" else "R"]) if which == 0 else ("%s_%s" % [stem, "l" if side == "Left" else "r"])
			bm.set_skeleton_bone_name(StringName(side + part), StringName(name))
	for finger: StringName in FINGERS:
		var spec: Array = FINGERS[finger]
		var stem: String = spec[which]
		for i in 3:
			for side in ["Left", "Right"]:
				var name := ("DEF-%s.%02d.%s" % [stem, i + 1, "L" if side == "Left" else "R"]) if which == 0 else ("%s_%02d_%s" % [stem, i + 1, "l" if side == "Left" else "r"])
				bm.set_skeleton_bone_name(StringName(side + String(finger) + spec[2][i]), StringName(name))
	return bm


func _patch(path: String, skeleton_path: String, bone_map: BoneMap, animations: bool) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_error("no " + path)
		return
	var opts := {
		"retarget/bone_map": bone_map,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
		"retarget/rest_fixer/overwrite_axis": true,
		"retarget/rest_fixer/fix_silhouette/enable": true,
	}
	cfg.set_value("params", "_subresources", {"nodes": {"PATH:" + skeleton_path: opts}})
	# The bodies carry no animations; the library's are kept and looped as
	# their names say (…_Loop)
	cfg.set_value("params", "animation/import", animations)
	cfg.set_value("params", "meshes/generate_lods", true)
	cfg.save(path)
	print("patched ", path)
