extends "res://scripts/debug/screenshots.gd"
## 第五章截图：--chapter=5 --debugscript=res://scripts/debug/shots_rust.gd --out=<目录>

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
	var R := AreaRust
	await aerial("s01_overview", Vector3(-30, 90, 200), Vector3(90, 10, 80), 2.0)
	await aerial("s02_top", Vector3(80, 170, 150), Vector3(80, 0, 78), 1.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await shot("s03_spawn", R.SPAWN, -PI / 2.0 + 0.5, -0.3, false, 1.5)
	await shot("s04_flats", Vector3i(50, R.GW, 124), -PI / 2.0 - 0.4, -0.35, false, 1.5)
	await shot("s05_graveyard", Vector3i(66, R.G, 104), -PI / 2.0, -0.3, false, 1.5)
	await shot("s06_pier", Vector3i(R.PIER.x - 4, R.G, R.PIER.y), -PI / 2.0, -0.25, false, 1.5)
	await aerial("s07_lighthouse", Vector3(110, 40, 90), Vector3(136, 18, 60), 1.0)
	await shot("s08_liner", Vector3i(30, R.G, 88), PI, -0.3, false, 1.5)
	get_tree().quit()
