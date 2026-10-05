extends Node
## 画风 / 破坏效果对比截图（第一章）：
## godot --path . --rendering-driver opengl3 res://scenes/main.tscn -- --chapter=1 --debugscript=res://scripts/debug/shots_style.gd --out=<目录>

var out_dir := "user://style"
var main: Node
var P: MorphBall
var W: VoxelWorld
var cam: CameraRig

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	P = main.player
	W = main.world
	cam = GameState.camera
	_run()

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

func _hide_ui() -> void:
	for n in get_tree().get_nodes_in_group("hud"):
		(n as CanvasItem).visible = false
	if main.hud:
		main.hud.visible = false
	for c in get_tree().root.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in main.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

func aerial(name: String, from: Vector3, to: Vector3, wait := 1.0) -> void:
	var c := Camera3D.new()
	c.fov = 55.0
	add_child(c)
	c.global_position = from * VoxelWorld.CELL_M
	c.look_at(to * VoxelWorld.CELL_M)
	c.current = true
	await get_tree().create_timer(wait).timeout
	_hide_ui()
	await _save(name)
	c.queue_free()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_hide_ui()
	var G := AreaGreenhouse.G
	P.debug_override = true
	P.teleport(W.voxel_top(Vector3i(36, G - 1, 76)) + Vector3.UP * 0.5)
	await aerial("s01_garden", Vector3(22, G + 9, 92), Vector3(38, G, 74), 2.0)
	await aerial("s02_tree", Vector3(30, G + 10, 70), Vector3(12, G + 12, 54), 1.0)
	await aerial("s03_cliff", Vector3(-6, G + 2, 96), Vector3(18, G - 6, 74), 1.0)
	var pv := P.global_position / VoxelWorld.CELL_M
	await aerial("s04_pix", pv + Vector3(-3.5, 1.6, 3.0), pv + Vector3(0, 0.3, 0), 1.0)
	await play_view("p01_play", Vector3i(19, G - 2, 74), -PI / 2.0 + 0.4, -0.3)
	await play_view("p02_play", Vector3i(34, G, 74), -PI / 2.0, -0.35)
	await play_view("p03_play", Vector3i(64, G + 6, 56), 0.0, -0.3)
	# 破坏：镜头正对的地面砸一个坑（下砸），再横着撞崖壁
	await _crater_test("s05", Vector3(16, G + 6, 88), Vector3(22, G - 1, 80), 1.3, Vector3.DOWN)
	await _crater_test("s08", Vector3(4, G + 1, 92), Vector3(12, G - 4, 80), 1.4, Vector3(0.5, 0, -0.8))
	get_tree().quit()

func _crater_test(tag: String, from: Vector3, to: Vector3, radius: float, dir: Vector3) -> void:
	var a := from * VoxelWorld.CELL_M
	var b := a + (to * VoxelWorld.CELL_M - a) * 3.0
	await get_tree().physics_frame
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		var pp := P.global_position
		var q2 := PhysicsRayQueryParameters3D.create(pp + Vector3.UP, pp + Vector3.DOWN * 5.0, 1)
		print("no hit ", tag, " a=", a, " b=", b, " down-probe=", get_viewport().get_world_3d().direct_space_state.intersect_ray(q2))
		return
	await aerial(tag + "_before", from, to, 0.3)
	W.break_sphere(hit.position + dir * 0.15, radius, "drill", 99.0, dir)
	await get_tree().create_timer(0.15).timeout
	await aerial(tag + "_impact", from, to, 0.0)
	await get_tree().create_timer(2.5).timeout
	await aerial(tag + "_after", from, to, 0.3)

func play_view(name: String, voxel: Vector3i, yaw: float, pitch: float) -> void:
	P.debug_override = true
	P.teleport(W.voxel_top(voxel + Vector3i.DOWN) + Vector3.UP * 0.5)
	cam.yaw = yaw
	cam.pitch = pitch
	await get_tree().create_timer(1.5).timeout
	_hide_ui()
	await _save(name)
