extends Node
## 快速平滑地形路径和慢速路径对比（顶点数、包围盒）
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var W: VoxelWorld = get_parent().world
	var n := Vector3i(17, 17, 17)
	var cnt := 0
	var t_fast := 0.0
	var t_slow := 0.0
	var lv: Node3D = get_parent().level
	var sv := W.to_v(lv.spawn_position())
	var gs := [sv / VoxelWorld.GSIZE, sv / VoxelWorld.GSIZE + Vector3i.DOWN]
	print("world size ", W.size, " spawn group ", gs[0], " has ", W._gsmooth.has(gs[0]), W._gsmooth.has(gs[1]))
	for g in gs + W._gsmooth.keys().slice(0, 10):
		var lo: Vector3i = g * VoxelWorld.GSIZE
		var t0 := Time.get_ticks_usec()
		var a := W._smooth_group_vt(lo, n)
		t_fast += (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var b := W._smooth_group_vt_slow(lo, n)
		t_slow += (Time.get_ticks_usec() - t0) / 1000.0
		var va: int = (a.get("verts", PackedVector3Array()) as PackedVector3Array).size()
		var vb: int = (b.get("verts", PackedVector3Array()) as PackedVector3Array).size()
		if cnt < 6:
			var aa := AABB()
			var bb := AABB()
			if va > 0:
				var pa: PackedVector3Array = a.verts
				aa = AABB(pa[0], Vector3.ZERO)
				for v: Vector3 in pa: aa = aa.expand(v)
			if vb > 0:
				var pb: PackedVector3Array = b.verts
				bb = AABB(pb[0], Vector3.ZERO)
				for v: Vector3 in pb: bb = bb.expand(v)
			print("group ", g, " fast verts ", va, " slow verts ", vb, " aabb ", aa, " vs ", bb)
		cnt += 1
	print("fast %.1fms slow %.1fms for %d groups" % [t_fast, t_slow, cnt])
	get_tree().quit()
