extends SceneTree
## Rendering benchmark: opens the game's main scene and stands at a fixed
## set of spots, recording what the renderer draws at each.
##
##   godot --path . -s res://tools/benchmark.gd [-- [--no-batch] [<out.json>]]
##
## --no-batch loads the zone without StaticBatcher, to compare.
##
## Objects, draw calls and primitives are exact on any machine, so the
## numbers compare across changes. FPS only means something on real
## hardware (run it on your own computer for that).
## Raiders are switched off so every run sees the same scene.

## [name, position (feet), yaw (deg, 0 = north), pitch (deg)]
const ROUTE := [
	["Outpost yard", Vector3(4, 0, 10), -60.0, 0.0],
	["Outpost gate, looking out", Vector3(0, 0, 30), 180.0, 0.0],
	["Main road to Halden's", Vector3(300, 0, 8), 140.0, 0.0],
	["Halden's, Main Street", Vector3(450, 0, -230), 0.0, 0.0],
	["Halden's water tower", Vector3(416, 9.15, -237), 115.0, -4.0],
	["Farm, looking at Halden's", Vector3(336, 0, -88), -40.0, 0.0],
	["Inside the hospital", Vector3(244, 0, -205), 0.0, 0.0],
	["Hospital roof", Vector3(241, 7.0, -203), 60.0, -3.0],
	["Smuggler's Gulch", Vector3(158, 0, -365), 0.0, 0.0],
	["Black Ridge Mine", Vector3(290, 0, -545), 90.0, 0.0],
	["Northwatch", Vector3(400, 0, -652), 0.0, 0.0],
	["Open ground", Vector3(200, 0, -150), -30.0, 0.0],
]

var results: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var no_batch := args.has("--no-batch")
	args.erase("--no-batch")
	var t_load := Time.get_ticks_msec()
	var zone := (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	zone.set("batch_sites", not no_batch)
	root.add_child(zone)
	current_scene = zone
	for i in 10:
		await process_frame
	print("zone loaded in %d ms%s" % [Time.get_ticks_msec() - t_load, " (no batching)" if no_batch else ""])
	var stats: Dictionary = zone.get("batch_stats")
	if stats.has("_ms"):
		var from := 0
		var into := 0
		var interior := 0
		for k in stats:
			if k != "_ms":
				from += stats[k].merged_from
				into += stats[k].merged_into
				interior += stats[k].interior
		print("batching: %d meshes merged into %d, %d interior things, in %d ms" % [from, into, interior, stats["_ms"]])
	for n in zone.find_children("*", "Node3D", true, false):
		if n is EnemySpawner:
			(n as EnemySpawner).enabled = false
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	var p := zone.get_node("Player") as PlayerController
	p.set_physics_process(false)
	await create_timer(1.0).timeout
	print("%-28s %8s %8s %10s %6s" % ["spot", "objects", "draws", "prims", "fps"])
	for stop in ROUTE:
		p.global_position = stop[1] + Vector3(0, 0.05, 0)
		p.rotation_degrees.y = stop[2]
		p.head.rotation_degrees.x = stop[3]
		for i in 8:
			await process_frame
		var fps_sum := 0.0
		var t0 := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - t0 < 600000 or frames < 3:
			await process_frame
			frames += 1
		fps_sum = frames / ((Time.get_ticks_usec() - t0) / 1000000.0)
		var r := {
			"spot": stop[0],
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"fps": snappedf(fps_sum, 0.1),
		}
		results.append(r)
		print("%-28s %8d %8d %10d %6.1f" % [r.spot, r.objects, r.draw_calls, r.primitives, r.fps])
	var total := 0
	for r in results:
		total += r.draw_calls
	print("total draw calls over the route: %d" % total)
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "spots": results, "total_draw_calls": total}, "  "))
	quit()
