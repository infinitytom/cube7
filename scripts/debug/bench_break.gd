extends Node
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var W: VoxelWorld = get_parent().world
	var P: MorphBall = get_parent().player
	var c := W.to_v(P.global_position) + Vector3i(0, -6, 0)
	var pts: Array[Vector3i] = []
	for z in 8:
		for x in 8:
			for y in 4:
				var p := c + Vector3i(x, -y, z)
				if W.vget(p) != 0:
					pts.append(p)
	var t := Time.get_ticks_usec()
	for p in pts.slice(0, pts.size() / 4):
		W.vset_raw(p, Blocks.AIR)
	var a := (Time.get_ticks_usec() - t) / float(pts.size() / 4)
	t = Time.get_ticks_usec()
	for p in pts.slice(pts.size() / 4, pts.size() / 2):
		W.vset(p, Blocks.AIR)
	var b := (Time.get_ticks_usec() - t) / float(pts.size() / 4)
	t = Time.get_ticks_usec()
	for p in pts.slice(pts.size() / 2, pts.size() * 3 / 4):
		W.log_damage(p, W.vget(p))
	var c2 := (Time.get_ticks_usec() - t) / float(pts.size() / 4)
	t = Time.get_ticks_usec()
	for p in pts.slice(pts.size() * 3 / 4):
		W.vbreak(p, "drill", 99.0, false)
	var d := (Time.get_ticks_usec() - t) / float(pts.size() / 4)
	print("per voxel us: vset_raw=%.1f vset=%.1f log_damage=%.1f vbreak=%.1f n=%d" % [a, b, c2, d, pts.size()])
	print("listeners cell_changed=%d block_changed=%d block_broken=%d" % [W.cell_changed.get_connections().size(), W.block_changed.get_connections().size(), W.block_broken.get_connections().size()])
	get_tree().quit()
