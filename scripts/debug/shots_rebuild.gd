extends "res://scripts/debug/screenshots.gd"
## 破坏与重构截图：--chapter=1 --debugscript=res://scripts/debug/shots_rebuild.gd --out=<目录>

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
	await get_tree().create_timer(2.0).timeout
	var L: Node = main.level
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var sites := get_tree().get_nodes_in_group("rebuild_site")
	var s: RebuildSite = sites[0]
	var pad := W.world_to_voxel(s.global_position + Vector3.UP * 0.1)
	await shot("r1_ghost", pad + Vector3i(-6, 0, 2), -PI / 2.0 - 0.3, -0.35, false, 2.5)
	GameState.add_matter(s.cost + 10)
	P.teleport(s.global_position + Vector3.UP * 0.6)
	await get_tree().create_timer(1.6).timeout
	await _save("r2_building")
	await get_tree().create_timer(6.0).timeout
	await shot("r3_built", pad + Vector3i(-8, 0, 3), -PI / 2.0 - 0.3, -0.3, false, 1.0)
	# 大坑 + 重构波
	var at := W.world_to_voxel(P.global_position) + Vector3i(0, 0, 10)
	var c := W.voxel_center(at + Vector3i.DOWN)
	for k in 5:
		W.break_sphere(c + Vector3(k * 1.2 - 2.4, 0, 0), 1.7, "impact", 16.0, Vector3.DOWN)
	await shot("r4_crater", at + Vector3i(0, 0, -9), PI, -0.55, false, 1.5)
	L.call("reconstruct", c, 25.0, 3.0)
	await get_tree().create_timer(1.2).timeout
	await _save("r5_restore")
	await get_tree().create_timer(4.0).timeout
	await _save("r6_restored")
	get_tree().quit()
