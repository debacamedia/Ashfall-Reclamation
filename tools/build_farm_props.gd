extends SceneTree
## Increment 30: Quaternius's Farm Buildings (CC0) made ready for the game:
## each OBJ's flat colours brought into the right colour space (the OBJ
## colours are linear) and weathered (faded and a little darker, for a farm
## that's stood empty since the ash), saved as
## assets/models/quaternius/farm/built/<name>.res for build_sites.gd and
## build_settlement_buildings.gd to use.
##
##   godot --headless --path . -s res://tools/build_farm_props.gd

const SRC := "res://assets/models/quaternius/farm/"
const OUT := "res://assets/models/quaternius/farm/built/"
const USED := ["Silo", "TowerWindmill", "ChickenCoop", "Well", "Windmill", "Barn", "SmallBarn", "OpenBarn", "BigBarn", "WaterTower", "Silo_House", "Fence", "Fence2"]
## How faded (toward grey) and how much darker
const FADE := 0.3
const DARKEN := 0.85

var _mats := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for n: String in USED:
		var src := load(SRC + n + ".obj") as ArrayMesh
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			out.surface_set_material(s, _material(src.surface_get_material(s)))
		var err := ResourceSaver.save(out, OUT + n.to_snake_case() + ".res")
		print(n, ": ", error_string(err), " ", out.get_aabb().size)
	quit()


func _material(src: Material) -> StandardMaterial3D:
	var name := src.resource_name if src != null else "Grey"
	var kd := (src as StandardMaterial3D).albedo_color if src is StandardMaterial3D else Color(0.2, 0.2, 0.2)
	if _mats.has(name + kd.to_html()):
		return _mats[name + kd.to_html()]
	var c := kd.linear_to_srgb()
	var grey := c.get_luminance()
	c = Color(lerpf(c.r, grey, FADE), lerpf(c.g, grey, FADE), lerpf(c.b, grey, FADE)) * DARKEN
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	m.roughness = 0.9
	if name.to_lower().contains("grey") or name.to_lower().contains("black"):
		m.metallic = 0.3
		m.roughness = 0.7
	_mats[name + kd.to_html()] = m
	return m
