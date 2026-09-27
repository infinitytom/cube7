extends Node
## 截图脚本：godot --path . --rendering-driver opengl3 -- --shots=<目录> [--level=test]

var out_dir := "user://shots"
var main: Node
var P: MorphBall
var W: VoxelWorld
var cam: CameraRig

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
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

## 主角放在 voxel，镜头按 yaw/pitch 跟随
func shot(name: String, voxel: Vector3i, yaw: float, pitch: float, model := false, wait := 1.5) -> void:
	P.debug_override = true
	P.teleport(W.voxel_top(voxel + Vector3i.DOWN) + Vector3.UP * 0.5)
	cam.yaw = yaw
	cam.pitch = pitch
	cam.model_view = model
	await get_tree().create_timer(wait).timeout
	await _save(name)

## 自由机位：从 from 看向 to（体素坐标）
func aerial(name: String, from: Vector3, to: Vector3, wait := 1.0) -> void:
	var c := Camera3D.new()
	c.fov = 60.0
	add_child(c)
	c.global_position = from * VoxelWorld.VOXEL
	c.look_at(to * VoxelWorld.VOXEL)
	c.current = true
	await get_tree().create_timer(wait).timeout
	await _save(name)
	c.queue_free()

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	if main.level is AreaGreenhouse:
		var G := AreaGreenhouse.G
		await aerial("g01_island", Vector3(-10, 70, 150), Vector3(64, 20, 50), 2.0)
		await aerial("g02_top", Vector3(64, 110, 60), Vector3(64, 20, 50))
		await shot("g03_spawn", Vector3i(19, G - 2, 74), -PI / 2.0 + 0.4, -0.35, false, 3.0)
		await shot("g04_garden", Vector3i(34, G, 74), -PI / 2.0, -0.4, false, 2.0)
		await shot("g05_sandtower", Vector3i(42, G, 72), -PI / 2.0 + 0.5, -0.3, false, 2.0)
		await shot("g06_dome", Vector3i(64, G + 6, 56), 0.0, -0.3, false, 2.0)
		await shot("g07_dome_inside", Vector3i(64, G + 6, 42), 0.0, -0.45, false, 2.0)
		await shot("g08_cave", Vector3i(92, G + 2, 48), PI, -0.2, false, 2.0)
		await shot("g09_pylon", Vector3i(96, G + 2, 36), -0.4, -0.35, false, 2.0)
		await aerial("g10_bridge_area", Vector3(130, 50, 20), Vector3(100, 24, 50))
	else:
		await shot("t01_spawn", Vector3i(9, 4, 32), -PI / 2.0 - 0.35, -0.3, false, 2.5)
	get_tree().quit()
