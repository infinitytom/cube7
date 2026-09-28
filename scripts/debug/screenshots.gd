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
	c.global_position = from * VoxelWorld.CELL_M
	c.look_at(to * VoxelWorld.CELL_M)
	c.current = true
	await get_tree().create_timer(wait).timeout
	await _save(name)
	c.queue_free()

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	if OS.get_cmdline_user_args().has("--enemies"):
		var lv: Node3D = main.level
		var list := [Scrapling.new(), Rustfly.new(), Spikeshell.new(), Mortar.new(), FurnaceWarden.new()]
		var i := 0
		for e in list:
			e.set("ai", false)
			lv.add_child(e)
			e.global_position = W.voxel_top(Vector3i(12 + i * 4, 3, 30)) + Vector3.UP * (1.2 if e is Rustfly else 0.05)
			e.rotation.y = -PI / 2.0 - 0.5
			i += 1
		P.debug_override = true
		P.teleport(W.voxel_top(Vector3i(8, 3, 36)) + Vector3.UP * 0.5)
		await get_tree().create_timer(1.0).timeout
		await aerial("e01_lineup", Vector3(6, 8, 42), Vector3(20, 4, 30), 1.0)
		await aerial("e02_close", Vector3(12, 6, 36), Vector3(16, 4, 30), 0.5)
		await aerial("e03_boss", Vector3(22, 8, 38), Vector3(28, 5, 30), 0.5)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--gw2"):
		var G := AreaGearworks.G
		await aerial("w01_overview", Vector3(-30, 80, 180), Vector3(70, 22, 55), 2.0)
		await aerial("w02_dock", Vector3(4, G + 8, 100), Vector3(40, G + 4, 70), 1.0)
		await aerial("w03_yard", Vector3(50, G + 14, 30), Vector3(80, G + 4, 60), 1.0)
		await aerial("w04_arena", Vector3(96, G + 20, 84), Vector3(116, G + 10, 60), 1.0)
		await aerial("w05_chimney", Vector3(56, G + 20, 70), Vector3(72, G + 20, 46), 1.0)
		await shot("w06_hall", Vector3i(64, G, 76), -PI / 2.0 + 0.4, -0.25, false, 1.5)
		await shot("w07_walk", Vector3i(88, AreaGearworks.WALK_Y + 1, 61), -PI / 2.0, -0.2, false, 1.5)
		get_tree().quit()
		return
	if main.level is AreaGearworks:
		var G := AreaGearworks.G
		await aerial("g00_overview", Vector3(-10, 70, 140), Vector3(60, 22, 64), 3.0)
		await aerial("g01_dock", Vector3(2, 34, 96), Vector3(26, 22, 76), 1.0)
		await aerial("g02_chasm", Vector3(36, 32, 92), Vector3(54, 22, 76), 1.0)
		await aerial("g03_yard", Vector3(56, 40, 36), Vector3(78, 22, 62), 1.0)
		await aerial("g04_hall", Vector3(64, 44, 90), Vector3(80, 22, 66), 1.0)
		await aerial("g05_catwalk", Vector3(84, 42, 76), Vector3(104, 32, 60), 1.0)
		await shot("g06_barricade", Vector3i(24, G, 76), -PI / 2.0 + 0.2, -0.25, false, 2.0)
		W.fire.ignite_sphere(W.voxel_center(Vector3i(30, G + 1, 77)), 1.0)
		await shot("g07_fire", Vector3i(25, G, 77), -PI / 2.0 + 0.15, -0.2, false, 3.0)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--gh2"):
		var G := AreaGreenhouse.G
		await aerial("h01_overview", Vector3(-30, 70, 200), Vector3(60, 22, 60), 2.0)
		await aerial("h02_tree", Vector3(40, G + 6, 80), Vector3(10, G + 16, 52), 1.0)
		await aerial("h03_camp", Vector3(60, G + 16, 130), Vector3(34, G, 108), 1.0)
		await aerial("h04_tower", Vector3(80, G + 10, 50), Vector3(100, G + 20, 24), 1.0)
		await shot("h05_spawn", Vector3i(19, G - 2, 74), -0.75, -0.3, false, 1.5)
		await shot("h06_deck", main.level.deck_cell, 0.9, -0.2, false, 1.5)
		await aerial("h07_ruins", Vector3(80, G + 14, 80), Vector3(100, G + 8, 58), 1.0)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--vista"):
		await aerial("v01_wide", Vector3(-40, 60, 170), Vector3(64, 20, 40), 2.0)
		await aerial("v02_north", Vector3(40, 30, 110), Vector3(60, 30, -100), 1.0)
		await aerial("v03_east", Vector3(20, 34, 60), Vector3(300, 40, -300), 1.0)
		await aerial("v04_west", Vector3(150, 40, 60), Vector3(-100, 20, 30), 1.0)
		await aerial("v05_under", Vector3(-30, -10, 150), Vector3(64, 10, 50), 1.0)
		get_tree().quit()
		return
	if main.level is AreaGreenhouse and OS.get_cmdline_user_args().has("--quick"):
		var G := AreaGreenhouse.G
		await aerial("q00_overview", Vector3(-15, 55, 120), Vector3(55, 18, 55), 2.5)
		await aerial("q00_garden", Vector3(20, 34, 96), Vector3(40, 20, 72), 1.0)
		var e: Node3D = main.level.enemies[0]
		var ev := W.world_to_voxel(e.global_position)
		await shot("q01_enemy", ev + Vector3i(-7, 1, 3), -PI / 2.0 + 0.35, -0.3, false, 2.5)
		await shot("q02_pipe", Vector3i(46, G, 76), -PI / 2.0 + 0.3, -0.22, false, 2.0)
		# 角色特写：三种形态（自由机位对着主角）
		for fi in [MorphBall.BALL, MorphBall.DRILL, MorphBall.BUBBLE]:
			P.apply_form(fi, false)
			P.debug_override = true
			P.teleport(W.voxel_top(Vector3i(36, G - 1, 76)) + Vector3.UP * 0.5)
			await get_tree().create_timer(1.8).timeout
			var pv := P.global_position / VoxelWorld.CELL_M
			await aerial("q03_pix_%d" % fi, pv + Vector3(-3.5, 1.6, 3.0), pv + Vector3(0, 0.3, 0), 0.4)
		# 钻头工作中：朝泥土墙钻
		P.apply_form(MorphBall.DRILL, false)
		P.teleport(W.voxel_top(Vector3i(73, G + 5, 52)) + Vector3.UP * 0.5)
		await get_tree().create_timer(0.5).timeout
		P.debug_input = Vector2(0, -1)
		P.debug_ability = true
		await get_tree().create_timer(0.9).timeout
		var dv := P.global_position / VoxelWorld.CELL_M
		await aerial("q04_drilling", dv + Vector3(-2.5, 2.5, 5.0), dv, 0.2)
		P.debug_ability = false
		P.debug_input = Vector2.ZERO
		cam.distance = 7.0
		P.debug_override = false
		get_tree().quit()
		return
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
