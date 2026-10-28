extends SceneTree
## Renders a zone's map (Increment 17): the whole zone seen from straight
## above, in square tiles with an orthographic camera, stitched into one
## picture. Past the playable edge the ground is dimmed and tinted like the
## ash storm.
##
## Needs a real renderer (not --headless). Run after build_sites and
## build_early_zone, whenever the zone's look changes:
##   godot --path . -s res://tools/render_map.gd
##
## Writes levels/early_zone/map.webp (the picture) and map.tres (a ZoneMap).

const ZONE := "res://levels/early_zone/early_zone.tscn"
const OUT := "res://levels/early_zone/"
const TITLE := "Early Zone"
## The ground the map covers (x, z of the north-west corner, then size), m.
## The playable area runs x -160…660, z -800…160; this leaves ~70 m round it.
const RECT := Rect2(-232, -872, 960, 1104)
const PX_PER_M := 2.0
## Each tile is this many metres square.
const TILE_M := 128.0
const CAMERA_HEIGHT := 160.0

var vp: SubViewport
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tile_px := int(TILE_M * PX_PER_M)
	vp = SubViewport.new()
	vp.size = Vector2i(tile_px, tile_px)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var zone := (load(ZONE) as PackedScene).instantiate()
	vp.add_child(zone)
	for i in 6:
		await process_frame
	_prepare(zone)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TILE_M
	cam.near = 1.0
	cam.far = CAMERA_HEIGHT + 60.0
	cam.rotation_degrees = Vector3(-90, 0, 0)  # straight down, north up
	vp.add_child(cam)
	cam.make_current()
	for i in 4:
		await process_frame

	var w := int(RECT.size.x * PX_PER_M)
	var h := int(RECT.size.y * PX_PER_M)
	var image := Image.create(w, h, false, Image.FORMAT_RGB8)
	var cols := ceili(RECT.size.x / TILE_M)
	var rows := ceili(RECT.size.y / TILE_M)
	var t0 := Time.get_ticks_msec()
	for row in rows:
		for col in cols:
			var corner := RECT.position + Vector2(col, row) * TILE_M
			cam.position = Vector3(corner.x + TILE_M / 2.0, CAMERA_HEIGHT, corner.y + TILE_M / 2.0)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var tile := vp.get_texture().get_image()
			tile.convert(Image.FORMAT_RGB8)
			var at := Vector2i(col * tile_px, row * tile_px)
			var fit := Vector2i(mini(tile_px, w - at.x), mini(tile_px, h - at.y))
			image.blit_rect(tile, Rect2i(Vector2i.ZERO, fit), at)
		print("  row %d / %d" % [row + 1, rows])
	print("rendered %d tiles in %d ms" % [rows * cols, Time.get_ticks_msec() - t0])

	var boundary := ZoneBoundary.find_in(self)
	_storm_tint(image, boundary.polygon if boundary != null else PackedVector2Array())
	var pic := OUT + "map.webp"
	image.save_webp(ProjectSettings.globalize_path(pic), true, 0.9)
	print("wrote ", pic, " (", w, " x ", h, ")")
	# The ZoneMap, written as text: the picture isn't imported until the
	# editor (or --import) next runs
	var f := FileAccess.open(OUT + "map.tres", FileAccess.WRITE)
	f.store_string("""[gd_resource type="Resource" script_class="ZoneMap" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/world/zone_map.gd" id="1_map"]
[ext_resource type="Texture2D" path="%s" id="2_pic"]

[resource]
script = ExtResource("1_map")
title = "%s"
texture = ExtResource("2_pic")
world_rect = Rect2(%s, %s, %s, %s)
""" % [pic, TITLE, RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y])
	f.close()
	print("wrote ", OUT, "map.tres")
	quit()


## Only what you'd see from above in daylight: no player, HUD, raiders,
## haze or draw distances (so tiles join up), and a high, clear sun.
func _prepare(zone: Node) -> void:
	var hud := zone.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
		hud.process_mode = Node.PROCESS_MODE_DISABLED
	var player := zone.get_node_or_null("Player") as Node3D
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
	for n in zone.find_children("*", "", true, false):
		if n is EnemySpawner:
			(n as EnemySpawner).enabled = false
		elif n is GPUParticles3D or n is CPUParticles3D or n is FogVolume:
			(n as Node3D).visible = false
		elif n is CanvasLayer:
			(n as CanvasLayer).visible = false
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			g.visibility_range_begin = 0.0
			g.visibility_range_end = 0.0
			g.lod_bias = 100.0
		if n.has_method("set_process"):
			n.set_process(false)
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	# Vehicles move: they don't belong in the picture (the map marks them)
	for v in get_nodes_in_group("vehicles"):
		(v as Node3D).visible = false
	var we := zone.get_node("Lighting/WorldEnvironment") as WorldEnvironment
	var env := we.environment.duplicate() as Environment
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = true
	env.ambient_light_energy = 0.9
	we.environment = env
	var sun := zone.get_node("Lighting/Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-62, 35, 0)  # from the south-east, high
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = CAMERA_HEIGHT + 120.0
	sun.shadow_opacity = 0.75


## Past the playable edge: darker and greyer, like the storm. Inside, a
## little less saturated.
func _storm_tint(image: Image, edge: PackedVector2Array) -> void:
	if edge.size() < 3:
		return
	var storm := Color(0.3, 0.27, 0.25)
	for y in image.get_height():
		var z := RECT.position.y + (y + 0.5) / PX_PER_M
		# Where the edge crosses this row: inside between pairs of crossings
		var xs: Array[float] = []
		for i in edge.size():
			var a := edge[i]
			var b := edge[(i + 1) % edge.size()]
			if (a.y <= z) != (b.y <= z):
				xs.append(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for x in image.get_width():
			var wx := RECT.position.x + (x + 0.5) / PX_PER_M
			var crossings := 0
			for c in xs:
				if c < wx:
					crossings += 1
			var c := image.get_pixel(x, y)
			var grey := c.get_luminance()
			if crossings % 2 == 1:
				# Inside: a little less saturated, so the markers stand out
				image.set_pixel(x, y, Color(grey, grey, grey).lerp(c, 0.78))
				continue
			image.set_pixel(x, y, Color(grey, grey, grey).lerp(c, 0.35).lerp(storm, 0.45) * 0.8)
