extends Node
## 截图脚本：godot --path . --rendering-driver opengl3 -- --shots=<目录>

var out_dir := "user://shots"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func shot(name: String, voxel: Vector3i, yaw: float, pitch: float, model := false, wait := 1.2) -> void:
	var main := get_parent()
	var P: MorphBall = main.player
	var W: VoxelWorld = main.world
	var cam: CameraRig = GameState.camera
	P.debug_override = true
	P.teleport(W.voxel_top(voxel + Vector3i.DOWN) + Vector3.UP * 0.5)
	cam.yaw = yaw
	cam.pitch = pitch
	cam.model_view = model
	cam.global_position = W.voxel_top(voxel) + Vector3.UP * 0.6
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	GameState.say("PIX，醒醒！我是站点 AI NOVA。坏消息：整颗星球……好像被变成了方块。")
	await shot("01_spawn", Vector3i(6, 4, 32), -PI / 2.0 - 0.35, -0.3, false, 2.5)
	await shot("02_overview", Vector3i(14, 4, 32), -PI / 2.0 - 0.6, -0.4, true)
	await shot("03_glass", Vector3i(24, 4, 30), -PI / 2.0 + 0.2, -0.2)
	await shot("04_rock", Vector3i(46, 4, 30), -PI / 2.0 - 0.3, -0.25)
	await shot("05_lab", Vector3i(62, 4, 26), -PI / 2.0 - 0.9, -0.35, true)
	await shot("06_track", Vector3i(94, 4, 31), -PI / 2.0 - 0.5, -0.45, true)
	get_tree().quit()
