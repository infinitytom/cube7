extends Node
## 扫描效果截图：godot --path . --rendering-driver opengl3 res://scenes/main.tscn -- --chapter=1 --debugscript=res://scripts/debug/shots_explore.gd --out=<目录>
var out_dir := "user://explore"
var P: MorphBall
var W: VoxelWorld
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	P = get_parent().player
	W = get_parent().world
	_run()
func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("saved ", n)
func _run() -> void:
	if OS.get_cmdline_user_args().has("--nomsaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	await get_tree().create_timer(2.0).timeout
	P.debug_override = true
	var cores := get_tree().get_nodes_in_group("scan_target")
	var target := cores[1] as Node3D
	var tv := W.to_v(target.global_position)
	var top := tv
	while W.vget(top) == Blocks.AIR and top.y < W.size.y - 2:
		top += Vector3i.UP
	while (W.vget(top) != Blocks.AIR or W.vget(top + Vector3i.UP) != Blocks.AIR) and top.y < W.size.y - 4:
		top += Vector3i.UP
	P.teleport(W.vcenter(top) + Vector3.UP * 0.6 + Vector3(3, 0, 3))
	var cam := GameState.camera as CameraRig
	cam.pitch = -0.6
	cam.yaw = 2.4
	await get_tree().create_timer(1.5).timeout
	await _save("e01_before")
	(get_tree().get_first_node_in_group("echo_scan") as EchoScan).scan()
	await get_tree().create_timer(0.5).timeout
	await _save("e02_wave")
	await get_tree().create_timer(1.3).timeout
	await _save("e03_marks")
	var lv: Node3D = get_parent().level
	for e in lv.get_meta("spice_caves", []):
		var ev: Vector3i = e
		var wp := W.vcenter(ev)
		await _aerial("e04_cave", wp + Vector3(-4.5, 3.5, 4.5), wp, 1.0)
		break
	var traps: Array = lv.get_meta("spice_traps", [])
	if not traps.is_empty():
		var trv: Vector3i = traps[0]
		var wp2 := W.vcenter(trv)
		await _aerial("e05_trap", wp2 + Vector3(-5, 3.5, 5), wp2 + Vector3.UP * 1.5, 1.0)
		# 撞断木架
		W.break_sphere(wp2 + Vector3(0.25, 0.3, 0.25), 0.7, "impact", 12.0, Vector3.RIGHT)
		await _aerial("e06_fall", wp2 + Vector3(-5, 3.5, 5), wp2 + Vector3.UP * 1.0, 0.45)
		await _aerial("e07_landed", wp2 + Vector3(-5, 3.5, 5), wp2 + Vector3.UP * 0.5, 2.0)
	get_tree().quit()

func _aerial(n: String, from: Vector3, to: Vector3, wait := 1.0) -> void:
	var c := Camera3D.new()
	c.fov = 60.0
	add_child(c)
	c.global_position = from
	c.look_at(to)
	c.current = true
	await get_tree().create_timer(wait).timeout
	await _save(n)
	c.queue_free()
