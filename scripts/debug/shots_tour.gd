extends "res://scripts/debug/screenshots.gd"
## 画面巡检：在检查点 / 种子 / 重构点附近各拍一张游戏画面（带 HUD）
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://scenes/main.tscn -- --chapter=N --debugscript=res://scripts/debug/shots_tour.gd --out=<目录>

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	P = main.player
	W = main.world
	cam = GameState.camera
	_tour()

func _tour() -> void:
	await get_tree().create_timer(2.0).timeout
	var tag := "ch%d" % GameState.chapter
	await _save(tag + "_00_spawn")
	var spots: Array[Vector3] = []
	for n in main.level.find_children("*", "Checkpoint", true, false):
		spots.append((n as Node3D).global_position)
	for n in get_tree().get_nodes_in_group("seed_cube"):
		spots.append((n as Node3D).global_position)
	for n in get_tree().get_nodes_in_group("rebuild_site"):
		spots.append((n as Node3D).global_position)
	# 均匀抽 7 个
	var pick: Array[Vector3] = []
	var step := maxf(1.0, spots.size() / 7.0)
	var f := 0.0
	while int(f) < spots.size() and pick.size() < 7:
		pick.append(spots[int(f)])
		f += step
	var i := 1
	for p in pick:
		P.debug_override = true
		P.teleport(p + Vector3.UP * 1.2)
		cam.yaw = randf() * TAU
		await get_tree().create_timer(2.0).timeout
		await _save("%s_%02d" % [tag, i])
		i += 1
	# 破坏一下看特效
	W.break_sphere(P.global_position + Vector3(1.5, -0.6, 0), 1.7, "impact", 16.0, Vector3.DOWN)
	await get_tree().create_timer(0.25).timeout
	await _save(tag + "_99_break")
	get_tree().quit()
