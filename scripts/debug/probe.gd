extends Node
## 性能探针：测一次大破坏各部分耗时
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var W: VoxelWorld = get_parent().world
	var G := AreaGreenhouse.G
	# 单个区块重建耗时
	var t0 := Time.get_ticks_usec()
	var tgt := Vector3i(40, G + 6, 74)
	while W.get_block(tgt) == Blocks.AIR and tgt.y > 0:
		tgt.y -= 1
	var tris := 0
	var nodes := 0
	for ch in W.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			nodes += 1
			var m: ArrayMesh = (ch as MeshInstance3D).mesh
			for s in m.get_surface_count():
				tris += m.surface_get_array_len(s) / 3
	print("体素网格节点 %d 个，三角形 %d" % [nodes, tris])
	print("目标方块 ", tgt, " 类型 ", W.get_block(tgt))
	for i in 10:
		W._build_chunk(tgt * VoxelWorld.CELL / VoxelWorld.CHUNK)
	W._commit_groups()
	print("单区块重建平均 %.1f ms" % ((Time.get_ticks_usec() - t0) / 10000.0))
	# 大破坏：下砸级别 + 碎块
	var c := W.voxel_center(tgt)
	t0 = Time.get_ticks_usec()
	var n := W.break_sphere(c, 1.3, "impact", 20.0, Vector3.DOWN)
	var t1 := Time.get_ticks_usec()
	print("break_sphere 破坏 %d 块：%.1f ms（不含重建）" % [n, (t1 - t0) / 1000.0])
	var frames: Array = []
	for i in 30:
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		frames.append((Time.get_ticks_usec() - f0) / 1000.0)
	print("之后 30 帧耗时(ms)：", frames.map(func(x): return snappedf(x, 0.1)))
	get_tree().quit()
