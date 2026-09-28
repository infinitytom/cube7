extends "res://scripts/debug/screenshots.gd"
## 终章截图：--chapter=6 --debugscript=res://scripts/debug/shots_core.gd --out=<目录>

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	P = main.player
	W = main.world
	cam = GameState.camera
	_go()

func _go() -> void:
	await get_tree().create_timer(3.0).timeout
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is RustHeart):
			e.queue_free()
	var K := AreaCore
	await aerial("k01_overview", Vector3(56 + 70, 70, 56 + 90), Vector3(56, 50, 56), 2.0)
	await shot("k02_spawn", K.SPAWN, 0.0, -0.3, false, 1.5)
	await shot("k03_ramp", Vector3i(56 + 15, K.G0 + 7, 56 - 4), 0.0, -0.3, false, 1.5)
	await aerial("k04_shaft", Vector3(56, 60, 56 + 4), Vector3(56, 96, 56), 1.0)
	await shot("k05_top", Vector3i(56, K.GT, 56 + 16), 0.0, -0.35, false, 3.0)
	get_tree().quit()
