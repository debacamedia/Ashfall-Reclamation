extends SceneTree
## Increment 34: puts the story's radio (StoryRadio, "Answer the radio") on
## Northwatch's comms radio in its command post. Run once:
##   godot --headless --path . -s res://tools/add_story_radio.gd
## then build_early_zone.gd -- zone-only (the zone instances the place).

const LEVEL := "res://levels/northwatch_outpost/northwatch_outpost.tscn"


func _initialize() -> void:
	var lvl := (load(LEVEL) as PackedScene).instantiate() as Node3D
	var old := lvl.get_node_or_null("StoryRadio")
	if old != null:
		lvl.remove_child(old)
		old.free()
	var radio := lvl.get_node("Props/CommsRadio") as Node3D
	var r := StoryRadio.new()
	r.name = "StoryRadio"
	r.position = radio.position + Vector3(0, 0.9, 0)
	r.focus_offset = Vector3.ZERO
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.6, 0.6)
	cs.shape = box
	r.add_child(cs)
	lvl.add_child(r)
	r.owner = lvl
	cs.owner = lvl
	var ps := PackedScene.new()
	assert(ps.pack(lvl) == OK)
	print("saved ", LEVEL, ": ", error_string(ResourceSaver.save(ps, LEVEL)))
	lvl.free()
	quit()
