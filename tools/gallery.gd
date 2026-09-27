extends SceneTree
## 素材预览：godot --path . --rendering-driver opengl3 -s res://tools/gallery.gd -- <文件夹> <输出png> [过滤词]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var out: String = args[1]
	var filt: String = args[2] if args.size() > 2 else ""
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb") and (filt == "" or filt in f):
			files.append(f)
	files.sort()
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 1.0)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var cols := int(ceil(sqrt(files.size() * 1.6)))
	var i := 0
	for f in files:
		var sc := load(dir.path_join(f)) as PackedScene
		if sc == null:
			continue
		var n := sc.instantiate() as Node3D
		root.add_child(n)
		# 按包围盒缩放到约 1.6 单位
		var aabb := _aabb(n)
		var s := 1.6 / maxf(maxf(aabb.size.x, aabb.size.y), maxf(aabb.size.z, 0.01))
		n.scale = Vector3.ONE * s
		n.position = Vector3((i % cols) * 2.2, -aabb.position.y * s, (i / cols) * 2.4)
		var l := Label3D.new()
		l.text = f.get_basename()
		l.font_size = 22
		l.pixel_size = 0.006
		l.position = n.position + Vector3(0, -0.15, 1.0)
		l.rotation_degrees.x = -60
		l.modulate = Color.BLACK
		root.add_child(l)
		i += 1
	var rows := int(ceil(float(i) / cols))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(cols * 2.2, rows * 2.4 * 1.8) * 0.62
	root.add_child(cam)
	cam.look_at_from_position(Vector3((cols - 1) * 1.1, 30, (rows - 1) * 1.2 + 17), Vector3((cols - 1) * 1.1, 0, (rows - 1) * 1.2))
	cam.current = true
	for k in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := Transform3D()
		var cur: Node = mi
		while cur != n and cur is Node3D:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
