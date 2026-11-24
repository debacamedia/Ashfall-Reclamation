extends SceneTree
## Increment 29: dresses the Quaternius bodies. Each body's mesh is baked
## again with its regions in the vertex colour, for shaders/human_body:
##   red    shirt (torso and arms; alpha marks the forearm, for rolled sleeves)
##   green  trousers (hips and legs)
##   blue   boots (feet, and the leg up to the boot top)
##   none   skin (head, neck, hands)
## from which bone moves each vertex most, and how high it is in the rest
## pose. Writes assets/characters/quaternius/bodies/<male|female>_dressed.res.
##
##   godot --headless --path . -s res://tools/build_characters.gd
## (after tools/build_character_import.gd and an --import)

const ROOT := "res://assets/characters/quaternius/bodies/"
const BODIES := {
	"male": ["Superhero_Male_FullBody.gltf", "SuperHero_Male"],
	"female": ["Superhero_Female_FullBody.gltf", "Superhero_Female"],
}
## The waist: torso below this is trousers (m, rest pose)
const WAIST := 0.99
## The boot tops (m)
const BOOT_TOP := 0.24

const SKIN_BONES := ["Head", "Neck", "Jaw", "LeftEye", "RightEye", "LeftHand", "RightHand"]
const SHIRT_BONES := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm"]
const FOREARM_BONES := ["LeftLowerArm", "RightLowerArm"]
const LEG_BONES := ["Hips", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]
## What's left of the body under an outfit (29.1)
const HEAD_BONES := ["Head", "Neck", "Jaw", "LeftEye", "RightEye"]


func _initialize() -> void:
	for key: String in BODIES:
		var spec: Array = BODIES[key]
		var scene := (load(ROOT + spec[0]) as PackedScene).instantiate()
		var mi := scene.find_child(spec[1], true, false) as MeshInstance3D
		var out := _dress(mi)
		var path := ROOT + key + "_dressed.res"
		var err := ResourceSaver.save(out, path)
		print(key, ": ", error_string(err), " -> ", path)
		# 29.1: just the head and neck, for under the outfits
		var head := _head_only(out, _bind_names(mi))
		path = ROOT + key + "_head.res"
		err = ResourceSaver.save(head, path)
		print(key, " head: ", error_string(err), " -> ", path)
		scene.free()
	quit()


func _bind_names(mi: MeshInstance3D) -> Array[String]:
	var skin := mi.skin
	var bind_names: Array[String] = []
	for b in skin.get_bind_count():
		var n := String(skin.get_bind_name(b))
		if n == "":
			var sk := mi.get_node(mi.skeleton) as Skeleton3D
			n = sk.get_bone_name(skin.get_bind_bone(b))
		bind_names.append(n)
	return bind_names


## 29.1: the outfits come with their own bodies (Quaternius: "only the head
## of the model is required"), so this keeps the triangles moved by the head
## and neck alone.
func _head_only(src: ArrayMesh, bind_names: Array[String]) -> ArrayMesh:
	var out := ArrayMesh.new()
	var kept := 0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := bones.size() / verts.size()
		var on_head := PackedByteArray()
		on_head.resize(verts.size())
		for v in verts.size():
			var best := -1
			var best_w := -1.0
			for k in per:
				if weights[v * per + k] > best_w:
					best_w = weights[v * per + k]
					best = bones[v * per + k]
			var bone := bind_names[best] if best >= 0 and best < bind_names.size() else ""
			on_head[v] = 1 if bone in HEAD_BONES else 0
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if on_head[idx[t]] == 1 and on_head[idx[t + 1]] == 1 and on_head[idx[t + 2]] == 1:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if keep.is_empty():
			continue
		kept += keep.size() / 3
		# Only the vertices used, so its bounds are the head's
		var remap := {}
		var order := PackedInt32Array()
		for i in keep.size():
			if not remap.has(keep[i]):
				remap[keep[i]] = order.size()
				order.append(keep[i])
			keep[i] = remap[keep[i]]
		for a in Mesh.ARRAY_MAX:
			if a == Mesh.ARRAY_INDEX or arrays[a] == null:
				continue
			var src_arr: Variant = arrays[a]
			var stride: int = src_arr.size() / verts.size()
			var dst: Variant = src_arr.duplicate()
			dst.resize(order.size() * stride)
			for i in order.size():
				for k in stride:
					dst[i * stride + k] = src_arr[order[i] * stride + k]
			arrays[a] = dst
		arrays[Mesh.ARRAY_INDEX] = keep
		var fmt := src.surface_get_format(s)
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], {}, fmt)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	print("  head: ", kept, " triangles in ", out.get_surface_count(), " surfaces")
	return out


func _dress(mi: MeshInstance3D) -> ArrayMesh:
	var src := mi.mesh as ArrayMesh
	var bind_names := _bind_names(mi)
	var out := ArrayMesh.new()
	var counts := {"skin": 0, "shirt": 0, "trousers": 0, "boots": 0}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var colors := PackedColorArray()
		colors.resize(verts.size())
		for v in verts.size():
			var best := -1
			var best_w := -1.0
			for k in per:
				var w := weights[v * per + k]
				if w > best_w:
					best_w = w
					best = bones[v * per + k]
			var bone := bind_names[best] if best >= 0 and best < bind_names.size() else ""
			var y := verts[v].y
			var c := Color(0, 0, 0, 0)
			if bone in FOOT_BONES or (bone in LEG_BONES and y < BOOT_TOP):
				c = Color(0, 0, 1, 0)
				counts["boots"] += 1
			elif bone in LEG_BONES or (bone in SHIRT_BONES and y < WAIST):
				c = Color(0, 1, 0, 0)
				counts["trousers"] += 1
			elif bone in SHIRT_BONES:
				c = Color(1, 0, 0, 0)
				counts["shirt"] += 1
			elif bone in FOREARM_BONES:
				c = Color(1, 0, 0, 1)
				counts["shirt"] += 1
			else:
				counts["skin"] += 1
			colors[v] = c
		arrays[Mesh.ARRAY_COLOR] = colors
		var fmt := src.surface_get_format(s) | Mesh.ARRAY_FORMAT_COLOR
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], {}, fmt)
		out.surface_set_material(s, src.surface_get_material(s))
	print("  regions ", counts, " binds ", bind_names.slice(0, 6))
	return out
