extends "res://tests/test_case.gd"
## ASHFALL Resource Pack 1.0 in Outpost 17: the pack loads, the level uses
## its materials through per-instance overrides (shared scenes and original
## materials untouched), the signs are visual only, and the new sounds loop.

const LEVEL := preload("res://levels/outpost_17/outpost_17.tscn")
const PACK := "res://assets/ashfall_pack_v1/"


func test_pack_resources_load() -> void:
	for m in ["concrete_weathered", "concrete_cracked", "asphalt_worn", "gravel_mixed", "dirt_dry", "rusted_steel",
			"corrugated_metal", "wood_weathered", "sandbag_canvas"]:
		var mat := load(PACK + "materials/%s.tres" % m) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null and mat.normal_texture != null and mat.roughness_texture != null,
			"%s: material with albedo, normal and roughness" % m)
	for d in ["restricted", "warning", "outpost_17", "salvage"]:
		check(load(PACK + "decals/%s.png" % d) is Texture2D, "decal %s" % d)
	for a in ["generator_idle", "radio_static", "distant_wind", "metal_clank"]:
		check(load(PACK + "audio/%s.wav" % a) is AudioStreamWAV, "sound %s" % a)


func test_shared_scenes_and_original_materials_untouched() -> void:
	# The reusable scenes still use the original materials: the pack is only
	# applied to Outpost 17's own instances.
	var wall := (load("res://scenes/world/props/concrete_wall_segment.tscn") as PackedScene).instantiate()
	for m in wall.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override
		check(mat == null or not mat.resource_path.begins_with(PACK), "wall segment scene keeps its materials (%s)" % m.name)
	wall.free()
	var sandbags := (load("res://scenes/world/props/sandbag_wall.tscn") as PackedScene).instantiate()
	for m in sandbags.find_children("*", "MeshInstance3D", true, false):
		check((m as MeshInstance3D).material_override.resource_path == "res://assets/materials/sandbag.tres", "sandbag scene keeps sandbag.tres")
	sandbags.free()
	check(load("res://assets/materials/concrete.tres").resource_path == "res://assets/materials/concrete.tres", "originals still load")


func test_outpost_uses_the_pack() -> void:
	var lvl := LEVEL.instantiate()
	var counts := {}
	for m in lvl.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override
		if mat != null and mat.resource_path.begins_with(PACK):
			var key := mat.resource_path.get_file().get_basename()
			counts[key] = counts.get(key, 0) + 1
	for key in ["concrete_weathered", "concrete_cracked", "asphalt_worn", "gravel_mixed", "dirt_dry", "rusted_steel",
			"corrugated_metal", "wood_weathered", "sandbag_canvas"]:
		check(counts.get(key, 0) > 0, "Outpost 17 uses %s (%d meshes)" % [key, counts.get(key, 0)])
	check(((lvl.get_node("Terrain/Ground") as MeshInstance3D).material_override as Resource).resource_path == PACK + "materials/dirt_dry.tres", "ground is dry dirt")
	check(((lvl.get_node("Surfaces/MainRoad") as MeshInstance3D).material_override as Resource).resource_path == PACK + "materials/asphalt_worn.tres", "road is worn asphalt")
	lvl.free()


func test_signs_are_visual_only_and_sit_on_walls() -> void:
	var lvl := LEVEL.instantiate() as Node3D
	(lvl.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	add_child(lvl)
	await wait_physics(3)
	var signs := lvl.get_node("Signage").get_children()
	check(signs.size() == 4, "4 signs (%d)" % signs.size())
	var space := lvl.get_world_3d().direct_space_state
	for s: MeshInstance3D in signs:
		check(s.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s has no collision" % s.name)
		check(s.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % s.name)
		var mat := s.material_override as StandardMaterial3D
		check(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and mat.albedo_texture != null, "%s: alpha-tested decal" % s.name)
		# A wall right behind it (within 2 cm), so it can't float or z-fight
		var facing := s.global_basis.z.normalized()
		var q := PhysicsRayQueryParameters3D.create(s.global_position + facing * 0.05, s.global_position - facing * 0.05, PhysicsLayers.WORLD_SOLID)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty(), "%s is on a wall" % s.name)
		if not hit.is_empty():
			var gap := s.global_position.distance_to(hit["position"])
			check_between(gap, 0.002, 0.02, "%s sits just in front of the wall" % s.name)
	remove_child(lvl)
	lvl.free()


func test_soundscape() -> void:
	var lvl := LEVEL.instantiate()
	var s := lvl.get_node("Soundscape")
	for name in ["GeneratorHum", "RadioStatic", "DistantWind"]:
		var p := s.get_node(name)
		var stream := p.get("stream") as AudioStreamWAV
		check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)
		check(p.get("autoplay") == true, "%s plays on its own" % name)
	var clank := s.get_node("MotorPoolClank") as RandomSoundEmitter
	check(clank != null and clank.stream != null and not clank.autoplay, "metal clank plays now and then")
	check(clank.min_interval > 0.0 and clank.max_interval >= clank.min_interval, "clank interval sensible")
	check((s.get_node("GeneratorHum") as AudioStreamPlayer3D).bus == &"SFX" and (s.get_node("DistantWind") as AudioStreamPlayer).bus == &"Ambience", "on the right buses")
	# The original ambience is still there
	check(lvl.get_node("%Ambience") != null and (lvl.get_node("%Ambience") as AudioStreamPlayer).stream.resource_path == "res://assets/audio/wind_loop.wav", "original wind ambience kept")
	lvl.free()
