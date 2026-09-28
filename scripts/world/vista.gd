class_name Vista
extends Node3D
## 远景管理：把 VistaBuilder 的活儿丢进后台线程，做好了再在主线程挂上网格、瀑布、光柱、烟。
## 用法：vista.add("island", {...参数}, 位置(米，岛顶中心), 朝向, {"falls_to": 云海高度, ...})

var sea_y := -30.0
var _jobs: Array = []          ## 等待挂载的 [结果, 位置, 朝向, 额外]
var _mutex := Mutex.new()
var _pending := 0
var _tasks: Array[int] = []
var _spinners: Array = []      ## [节点, 轴, 速度]
var _bobbers: Array = []       ## [节点, 基准 y, 相位, 幅度]
var _t := 0.0
var sync_build := false        ## 截图 / 测试时同步生成
var _t0 := Time.get_ticks_msec()

signal all_built

func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()

## 生成结果按参数缓存（标题画面 → 新游戏、重开关卡时不用再算一遍）
static var _cache := {}
static var _cache_mutex := Mutex.new()

func add(kind: String, params: Dictionary, pos: Vector3, yaw := 0.0, extra := {}) -> void:
	_pending += 1
	var key := kind + str(params) + str(extra.get("skip_bottom", false))
	_cache_mutex.lock()
	var hit: Dictionary = _cache.get(key, {})
	_cache_mutex.unlock()
	if not hit.is_empty():
		_mutex.lock()
		_jobs.append([hit, pos, yaw, extra])
		_mutex.unlock()
		_mount_ready()
		return
	var job := func() -> void:
		var res: Dictionary = VistaBuilder.build(kind, params)
		var gr: VistaGrid = res.grid
		res["arrays"] = gr.build_arrays(extra.get("skip_bottom", false))
		res.erase("grid")
		res.erase("heights")
		_cache_mutex.lock()
		_cache[key] = res
		_cache_mutex.unlock()
		_mutex.lock()
		_jobs.append([res, pos, yaw, extra])
		_mutex.unlock()
	if sync_build:
		job.call()
		_mount_ready()
	else:
		_tasks.append(WorkerThreadPool.add_task(job, false, "vista " + kind))

## 自定义网格（比如岛底）：grid_fn 在线程里返回 VistaGrid，放在 origin（网格原点的世界坐标）
func add_grid(grid_fn: Callable, origin: Vector3, extra := {}) -> void:
	_pending += 1
	var key: String = extra.get("cache_key", "")
	if key != "":
		_cache_mutex.lock()
		var hit: Dictionary = _cache.get(key, {})
		_cache_mutex.unlock()
		if not hit.is_empty():
			_mutex.lock()
			_jobs.append([hit, origin, 0.0, extra])
			_mutex.unlock()
			_mount_ready()
			return
	var job := func() -> void:
		var gr: VistaGrid = grid_fn.call()
		var res := {"arrays": gr.build_arrays(extra.get("skip_bottom", false)), "anchor": Vector3.ZERO, "falls": []}
		if key != "":
			_cache_mutex.lock()
			_cache[key] = res
			_cache_mutex.unlock()
		_mutex.lock()
		_jobs.append([res, origin, 0.0, extra])
		_mutex.unlock()
	if sync_build:
		job.call()
		_mount_ready()
	else:
		_tasks.append(WorkerThreadPool.add_task(job, false, "vista grid"))

func is_done() -> bool:
	return _pending == 0

## 等全部生成完（截图/测试用）
func wait_all() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_mount_ready()

func _process(delta: float) -> void:
	_t += delta
	_mount_ready()
	for s in _spinners:
		(s[0] as Node3D).rotate_object_local(s[1], s[2] * delta)
	for b in _bobbers:
		var n := b[0] as Node3D
		n.position.y = float(b[1]) + sin(_t * 0.25 + float(b[2])) * float(b[3])

func _mount_ready() -> void:
	_mutex.lock()
	var list := _jobs.duplicate()
	_jobs.clear()
	_mutex.unlock()
	for j in list:
		_mount(j[0], j[1], j[2], j[3])
		_pending -= 1
	if not list.is_empty() and _pending == 0:
		var tris := 0
		for mi in find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m is ArrayMesh:
				for si in m.get_surface_count():
					tris += (m.surface_get_array_index_len(si)) / 3
		print("[Vista] 远景全部生成完毕（%.1f 秒，%d 万个三角形）" % [(Time.get_ticks_msec() - _t0) / 1000.0, tris / 10000])
		all_built.emit()

func _mount(res: Dictionary, pos: Vector3, yaw: float, extra: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var mi := MeshInstance3D.new()
	mi.mesh = VistaGrid.arrays_to_mesh(res.arrays)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if extra.get("shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var anchor: Vector3 = res.anchor
	mi.position = -anchor
	root.add_child(mi)
	var fall_to: float = extra.get("falls_to", sea_y)
	for f in res.get("falls", []):
		var lp: Vector3 = (f[0] as Vector3) - anchor
		var world_top := root.to_global(lp)
		add_waterfall(world_top, root.global_basis * (f[1] as Vector3), world_top.y - fall_to, extra.get("fall_width", 3.0))
	if res.has("top") and extra.get("beam", false):
		add_beam(root.to_global((res.top as Vector3) - anchor), extra.get("beam_color", Color(0.45, 1.0, 0.8)))
	for s in res.get("stacks", []):
		add_smoke(root.to_global((s as Vector3) - anchor), extra.get("smoke_scale", 1.0))
	if extra.has("spin"):
		_spinners.append([mi, Vector3(0, 0, 1), float(extra.spin)])
		mi.position = Vector3.ZERO
		var pivot := Node3D.new()
		root.add_child(pivot)
		mi.reparent(pivot, false)
		mi.position = -anchor
		_spinners[-1][0] = pivot
	if extra.get("bob", 0.0) > 0.0:
		_bobbers.append([root, root.position.y, randf() * TAU, float(extra.bob)])
	if extra.has("name"):
		root.name = str(extra.name)

# ---------------------------------------------------------------- 瀑布 / 光柱 / 烟

static var _fall_mat: ShaderMaterial

func add_waterfall(top: Vector3, out_dir: Vector3, length: float, width := 3.0) -> void:
	if length <= 1.0:
		return
	if _fall_mat == null:
		_fall_mat = ShaderMaterial.new()
		_fall_mat.shader = load("res://shaders/waterfall.gdshader")
	var od := Vector3(out_dir.x, 0, out_dir.z).normalized()
	if od.length() < 0.1:
		od = Vector3.FORWARD
	var node := Node3D.new()
	add_child(node)
	node.global_position = top
	node.look_at(top + od, Vector3.UP)
	# 两片交叉的水帘：从侧面看也有厚度；先向外冲出一点再落下（弧形）
	var mat := _fall_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("length_m", length)
	mat.set_shader_parameter("cells_x", maxf(width / 0.5, 2.0))
	var mesh := _fall_mesh(length, width)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# 瀑布口的水花
	var mist := CPUParticles3D.new()
	mist.amount = 10
	mist.lifetime = 1.6
	mist.direction = Vector3(0, 0.3, -1)
	mist.spread = 30.0
	mist.gravity = Vector3(0, -2.0, 0)
	mist.initial_velocity_min = 0.6
	mist.initial_velocity_max = 1.4
	mist.scale_amount_min = 0.5
	mist.scale_amount_max = 1.1
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(1, 1, 1, 0.35)
	sm.material = smat
	mist.mesh = sm
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(width * 0.4, 0.2, 0.2)
	mist.position = Vector3(0, -0.4, -0.6)
	node.add_child(mist)

## 瀑布网格：沿本地 -Z（向外）先冲出，再竖直落下的弧形条带
func _fall_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		var y := -t * length
		var out := 1.6 * sqrt(clampf(t * length / 6.0, 0.0, 1.0)) + t * 0.8
		pts.append(Vector3(0, y, -out))
	for side in 2:
		for i in segs:
			var a := pts[i]
			var b := pts[i + 1]
			var w := width * (1.0 + float(i) / segs * 0.5)
			var w2 := width * (1.0 + float(i + 1) / segs * 0.5)
			var off := Vector3(0, 0, 0.25 * side)
			var q := [a + Vector3(-w * 0.5, 0, 0) + off, a + Vector3(w * 0.5, 0, 0) + off, b + Vector3(w2 * 0.5, 0, 0) + off, b + Vector3(-w2 * 0.5, 0, 0) + off]
			var uv := [Vector2(0, float(i) / segs), Vector2(1, float(i) / segs), Vector2(1, float(i + 1) / segs), Vector2(0, float(i + 1) / segs)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[k])
				st.add_vertex(q[k])
	return st.commit()

## 光柱：点亮的重构塔向天上打的一道光
func add_beam(base: Vector3, color: Color, height := 400.0, radius := 1.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.6
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, 0.55)
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = base + Vector3.UP * height * 0.5
	var inner := MeshInstance3D.new()
	var cm2 := cm.duplicate() as CylinderMesh
	cm2.top_radius = radius * 0.25
	cm2.bottom_radius = radius * 0.4
	inner.mesh = cm2
	var m2 := m.duplicate() as StandardMaterial3D
	m2.albedo_color = Color(1, 1, 1, 0.7)
	inner.material_override = m2
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(inner)
	return mi

## 烟囱的烟：大团的软烟慢慢升起、被风吹斜
func add_smoke(at: Vector3, sc := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.direction = Vector3(0.2, 1, 0)
	p.spread = 8.0
	p.gravity = Vector3(1.2, 0.35, 0.3)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 2.0 * sc
	p.scale_amount_max = 4.0 * sc
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.5, 0.52, 0.0))
	grad.add_point(0.1, Color(0.6, 0.55, 0.58, 0.5))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.75, 0.78, 0.0))
	p.color_ramp = grad
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 1)
	sm.material = mat
	p.mesh = sm
	add_child(p)
	p.global_position = at

# ---------------------------------------------------------------- 岛底：把玩法世界的底部延伸成巨大的倒悬岩体

## 读取玩法世界最底下的轮廓，生成一块向下收拢的岩体（0.5 米体素，和玩法世界对齐）
func add_underside(world: VoxelWorld, depth_cells := 44, seed_v := 5) -> void:
	var cs := world.csize
	# 主线程：每列（格）最底部实心格的 y（只看贴近世界底部的列）
	var foot := PackedInt32Array()
	foot.resize(cs.x * cs.z)
	foot.fill(-1)
	for z in cs.z:
		for x in cs.x:
			for y in range(0, 4):
				if world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
					foot[x + cs.x * z] = y
					break
	var grid_fn := func() -> VistaGrid:
		var gr := VistaGrid.new(Vector3i(cs.x, depth_cells + 4, cs.z), VoxelWorld.CELL_M)
		# 到轮廓边缘的距离（两遍倒角距离变换）
		var dist := PackedFloat32Array()
		dist.resize(cs.x * cs.z)
		for i in dist.size():
			dist[i] = 0.0 if foot[i] < 0 else 1e6
		for z in cs.z:
			for x in cs.x:
				var i := x + cs.x * z
				if dist[i] == 0.0:
					continue
				var best := dist[i]
				if x > 0: best = minf(best, dist[i - 1] + 1.0)
				else: best = minf(best, 1.0)
				if z > 0: best = minf(best, dist[i - cs.x] + 1.0)
				else: best = minf(best, 1.0)
				if x > 0 and z > 0: best = minf(best, dist[i - cs.x - 1] + 1.414)
				if x < cs.x - 1 and z > 0: best = minf(best, dist[i - cs.x + 1] + 1.414)
				dist[i] = best
		for z in range(cs.z - 1, -1, -1):
			for x in range(cs.x - 1, -1, -1):
				var i := x + cs.x * z
				if dist[i] == 0.0:
					continue
				var best := dist[i]
				if x < cs.x - 1: best = minf(best, dist[i + 1] + 1.0)
				else: best = minf(best, 1.0)
				if z < cs.z - 1: best = minf(best, dist[i + cs.x] + 1.0)
				else: best = minf(best, 1.0)
				if x < cs.x - 1 and z < cs.z - 1: best = minf(best, dist[i + cs.x + 1] + 1.414)
				if x > 0 and z < cs.z - 1: best = minf(best, dist[i + cs.x - 1] + 1.414)
				dist[i] = best
		var n := FastNoiseLite.new()
		n.seed = seed_v
		n.frequency = 0.07
		var n2 := FastNoiseLite.new()
		n2.seed = seed_v + 9
		n2.frequency = 0.25
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		for z in cs.z:
			for x in cs.x:
				var i := x + cs.x * z
				if foot[i] < 0:
					continue
				var dd := dist[i]
				var dep := minf(dd * 1.7, float(depth_cells)) * (0.7 + 0.35 * (0.5 + 0.5 * n.get_noise_2d(x, z)))
				dep += n2.get_noise_2d(x, z) * 2.0
				if rng.randf() < 0.02 and dd > 3.0:
					dep += rng.randf_range(4.0, 10.0)
				var top := depth_cells - 1 + foot[i]
				var bot := maxi(0, depth_cells - int(dep))
				for y in range(bot, top + 1):
					var band := int(floor((y + n.get_noise_2d(x * 2.0, z * 2.0) * 2.0) / 3.0)) % 3
					var t: int = [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C][band]
					if y < depth_cells - 18 and (x + y + z) % 11 == 0:
						t = Blocks.ROCK
					gr.s(x, y, z, t)
				# 零星的水晶和倒垂的草根
				if bot > 0 and rng.randf() < 0.012:
					for k in rng.randi_range(1, 3):
						gr.put(x, bot - 1 - k, z, Blocks.CRYSTAL)
				elif dd < 2.5 and rng.randf() < 0.18:
					for k in rng.randi_range(1, 4):
						gr.put(x, depth_cells - 1 - k, z, Blocks.PINE if k % 2 else Blocks.LEAVES)
		return gr
	add_grid(grid_fn, world.to_global(Vector3(0, -depth_cells * VoxelWorld.CELL_M, 0)), {"skip_bottom": false, "cache_key": "under:%s:%d:%d" % [cs, hash(foot), seed_v]})
