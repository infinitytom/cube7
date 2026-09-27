class_name VoxelWorld
extends Node3D
## 轻量体素世界：固定大小的方块网格，按 16³ 分块生成网格与碰撞。
## 只负责“方块数据 + 显示 + 破坏”，谜题逻辑通过信号监听它。
## 以后若换成 Voxel Tools，只需保持 get_block / set_block / try_break 这几个接口不变。

signal block_changed(pos: Vector3i, old_type: int, new_type: int)
signal block_broken(pos: Vector3i, type: int)
signal item_dropped(item_id: String, world_pos: Vector3)

const VOXEL := 0.5          ## 1 体素 = 0.5 米
const CHUNK := 16
const FALL_STEP := 0.05     ## 砂块下落一格的间隔（秒）

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## 每个面的两条切线方向（用于摆放四个角与计算 AO）
const TANGENTS: Array = [
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
]
const FACE_SHADE: Array[float] = [0.80, 0.80, 1.0, 0.55, 0.88, 0.88]
const AO_CURVE: Array[float] = [1.0, 0.78, 0.62, 0.48]

const PickupScript := preload("res://scripts/voxel/pickup.gd")

@export var size := Vector3i(112, 32, 64)

var data := PackedByteArray()
var _lin_colors := PackedColorArray()
var _chunks := {}
var _dirty := {}
var _falling := {}
var _fall_timer := 0.0
var _materials: Array[Material] = []
## 每个面的三角形索引顺序（考虑 Godot 顺时针为正面）
var _face_ccw: Array[bool] = []

func _ready() -> void:
	add_to_group("voxel_world")
	data.resize(size.x * size.y * size.z)
	data.fill(Blocks.AIR)
	_lin_colors.resize(Blocks.COUNT)
	for t in Blocks.COUNT:
		_lin_colors[t] = Blocks.colors[t].srgb_to_linear()
	_materials = [
		null,
		_shader_mat("res://shaders/voxel_opaque.gdshader"),
		_shader_mat("res://shaders/voxel_glass.gdshader"),
		_shader_mat("res://shaders/voxel_glow.gdshader"),
	]
	for f in 6:
		var u: Vector3i = TANGENTS[f][0]
		var v: Vector3i = TANGENTS[f][1]
		_face_ccw.append(Vector3(u).cross(Vector3(v)).dot(Vector3(DIRS[f])) > 0.0)

func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

# ---------------------------------------------------------------- 数据访问

func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z

func get_block(p: Vector3i) -> int:
	if not in_bounds(p):
		return Blocks.AIR
	return data[p.x + size.x * (p.y + size.y * p.z)]

func set_block(p: Vector3i, t: int) -> void:
	if not in_bounds(p):
		return
	var i := p.x + size.x * (p.y + size.y * p.z)
	var old := data[i]
	if old == t:
		return
	data[i] = t
	_mark_dirty_around(p)
	if t == Blocks.AIR:
		var above := p + Vector3i.UP
		if Blocks.falls[get_block(above)] == 1:
			_falling[above] = true
	elif Blocks.falls[t] == 1:
		_falling[p] = true
	block_changed.emit(p, old, t)

## 关卡搭建用：批量填充，不发信号
func fill_box(a: Vector3i, b: Vector3i, t: int) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := Vector3i(x, y, z)
				if in_bounds(p):
					data[x + size.x * (y + size.y * z)] = t
	_mark_dirty_box(lo, hi)

func world_to_voxel(w: Vector3) -> Vector3i:
	var l := to_local(w) / VOXEL
	return Vector3i(floori(l.x), floori(l.y), floori(l.z))

func voxel_center(p: Vector3i) -> Vector3:
	return to_global((Vector3(p) + Vector3(0.5, 0.5, 0.5)) * VOXEL)

func voxel_top(p: Vector3i) -> Vector3:
	return to_global((Vector3(p) + Vector3(0.5, 1.0, 0.5)) * VOXEL)

# ---------------------------------------------------------------- 破坏

## tool: "impact"（撞击，power = 速度）或 "drill"（钻头）
func try_break(p: Vector3i, tool: String, power: float, fx := true) -> bool:
	var t := get_block(p)
	if not Blocks.can_break(t, tool, power):
		return false
	set_block(p, Blocks.AIR)
	GameState.blocks_broken += 1
	if fx:
		_spawn_break_fx(p, t)
	block_broken.emit(p, t)
	return true

## 机关用：无视硬度移除方块（有碎屑特效，不给掉落）
func try_break_any(p: Vector3i) -> void:
	var t := get_block(p)
	if t == Blocks.AIR:
		return
	set_block(p, Blocks.AIR)
	_spawn_debris(voxel_center(p), Blocks.colors[t])

## 以世界坐标为球心破坏一片方块，返回破坏数量
func break_sphere(center: Vector3, radius: float, tool: String, power: float) -> int:
	var c := world_to_voxel(center)
	var r := int(ceil(radius / VOXEL))
	var count := 0
	for z in range(c.z - r, c.z + r + 1):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var p := Vector3i(x, y, z)
				if voxel_center(p).distance_to(center) > radius:
					continue
				if try_break(p, tool, power, count < 14):
					count += 1
	if count > 0:
		GameState.shake.emit(minf(0.08 + count * 0.02, 0.35))
	return count

func _spawn_break_fx(p: Vector3i, t: int) -> void:
	var pos := voxel_center(p)
	_spawn_debris(pos, Blocks.colors[t])
	var d := Blocks.def(t)
	for i in int(d.get("coins", 0)):
		PickupScript.spawn(self, "coin", pos)
	for i in int(d.get("energy", 0)):
		PickupScript.spawn(self, "energy", pos)
	var item: String = d.get("item", "")
	if item != "":
		item_dropped.emit(item, pos)

## 碎屑只是视觉粒子，0.5 秒内消散，不参与物理
func _spawn_debris(pos: Vector3, color: Color) -> void:
	var ps := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.13
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material = mat
	ps.mesh = mesh
	ps.amount = 8
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 0.5
	ps.direction = Vector3.UP
	ps.spread = 70.0
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 4.5
	ps.gravity = Vector3(0, -14, 0)
	ps.angular_velocity_min = -360.0
	ps.angular_velocity_max = 360.0
	ps.scale_amount_curve = _shrink_curve()
	add_child(ps)
	ps.global_position = pos
	ps.emitting = true
	get_tree().create_timer(0.8).timeout.connect(ps.queue_free)

static var _curve_cache: Curve
static func _shrink_curve() -> Curve:
	if _curve_cache == null:
		_curve_cache = Curve.new()
		_curve_cache.add_point(Vector2(0, 1))
		_curve_cache.add_point(Vector2(1, 0))
	return _curve_cache

# ---------------------------------------------------------------- 更新

func _process(delta: float) -> void:
	if not _falling.is_empty():
		_fall_timer += delta
		if _fall_timer >= FALL_STEP:
			_fall_timer = 0.0
			_step_falling()
	if not _dirty.is_empty():
		for c in _dirty.keys():
			_build_chunk(c)
		_dirty.clear()

func _step_falling() -> void:
	var current := _falling.keys()
	_falling.clear()
	for p in current:
		var t := get_block(p)
		if Blocks.falls[t] == 0:
			continue
		var below: Vector3i = p + Vector3i.DOWN
		if in_bounds(below) and get_block(below) == Blocks.AIR:
			set_block(p, Blocks.AIR)      # 会把上方的砂加入下落队列
			set_block(below, t)           # 会把自己加入下一轮

func rebuild_all() -> void:
	var t0 := Time.get_ticks_msec()
	for cz in ceili(size.z / float(CHUNK)):
		for cy in ceili(size.y / float(CHUNK)):
			for cx in ceili(size.x / float(CHUNK)):
				_build_chunk(Vector3i(cx, cy, cz))
	_dirty.clear()
	print("[VoxelWorld] 全部区块生成耗时 %d ms" % (Time.get_ticks_msec() - t0))

func _mark_dirty_around(p: Vector3i) -> void:
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector3i(dx, dy, dz)
				_dirty[Vector3i(floori(q.x / float(CHUNK)), floori(q.y / float(CHUNK)), floori(q.z / float(CHUNK)))] = true

func _mark_dirty_box(lo: Vector3i, hi: Vector3i) -> void:
	for cz in range(floori((lo.z - 1) / float(CHUNK)), floori((hi.z + 1) / float(CHUNK)) + 1):
		for cy in range(floori((lo.y - 1) / float(CHUNK)), floori((hi.y + 1) / float(CHUNK)) + 1):
			for cx in range(floori((lo.x - 1) / float(CHUNK)), floori((hi.x + 1) / float(CHUNK)) + 1):
				_dirty[Vector3i(cx, cy, cz)] = true

# ---------------------------------------------------------------- 网格生成

func _is_occluder(t: int) -> bool:
	var r := Blocks.render[t]
	return r == Blocks.Render.OPAQUE or r == Blocks.Render.GLOW

func _face_visible(t: int, nt: int) -> bool:
	if nt == Blocks.AIR:
		return true
	if Blocks.render[nt] == Blocks.Render.GLASS:
		return nt != t
	return false

func _build_chunk(c: Vector3i) -> void:
	var origin := c * CHUNK
	if origin.x < 0 or origin.y < 0 or origin.z < 0 or origin.x >= size.x or origin.y >= size.y or origin.z >= size.z:
		return
	# 每种渲染方式一组顶点数组
	# 注意：Packed 数组是值类型，放进 Array 后无法原地 append，所以先用普通 Array 收集
	var verts: Array = [[], [], [], []]
	var norms: Array = [[], [], [], []]
	var cols: Array = [[], [], [], []]
	var faces := PackedVector3Array()
	var sx := size.x
	var sxy := size.x * size.y
	var end := Vector3i(mini(origin.x + CHUNK, size.x), mini(origin.y + CHUNK, size.y), mini(origin.z + CHUNK, size.z))
	var corner_sign: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

	for z in range(origin.z, end.z):
		for y in range(origin.y, end.y):
			for x in range(origin.x, end.x):
				var t: int = data[x + sx * y + sxy * z]
				if t == Blocks.AIR:
					continue
				var p := Vector3i(x, y, z)
				var r: int = Blocks.render[t]
				var base: Color = _lin_colors[t]
				var h := ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 255
				var vary := 0.97 + (h / 255.0) * 0.06
				for f in 6:
					var n := DIRS[f]
					var nt := get_block(p + n)
					if not _face_visible(t, nt):
						continue
					var u: Vector3i = TANGENTS[f][0]
					var v: Vector3i = TANGENTS[f][1]
					var center := (Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5) * VOXEL
					var q: Array[Vector3] = []
					var ao: Array[float] = []
					for cs in corner_sign:
						q.append(center + (Vector3(u) * cs.x + Vector3(v) * cs.y) * (0.5 * VOXEL))
						var s1 := _is_occluder(get_block(p + n + u * cs.x))
						var s2 := _is_occluder(get_block(p + n + v * cs.y))
						var cc := _is_occluder(get_block(p + n + u * cs.x + v * cs.y))
						var occ := 3 if (s1 and s2) else int(s1) + int(s2) + int(cc)
						ao.append(AO_CURVE[occ])
					var idx: Array
					var flip := ao[0] + ao[2] < ao[1] + ao[3]
					if _face_ccw[f]:
						idx = [0, 2, 1, 0, 3, 2] if not flip else [0, 3, 1, 1, 3, 2]
					else:
						idx = [0, 1, 2, 0, 2, 3] if not flip else [0, 1, 3, 1, 2, 3]
					var shade := FACE_SHADE[f] * vary
					var nf := Vector3(n)
					for k in idx:
						verts[r].append(q[k])
						norms[r].append(nf)
						var a := ao[k] * shade
						cols[r].append(Color(base.r * a, base.g * a, base.b * a, 1.0))
						faces.append(q[k])

	var node: Dictionary = _chunks.get(c, {})
	if node.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_%d" % [c.x, c.y, c.z]
		add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("voxel_body")
		mi.add_child(body)
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		node = {"mesh": mi, "body": body, "shape": cs}
		_chunks[c] = node

	var mesh := ArrayMesh.new()
	for rm in [Blocks.Render.OPAQUE, Blocks.Render.GLASS, Blocks.Render.GLOW]:
		if (verts[rm] as Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts[rm])
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(norms[rm])
		arr[Mesh.ARRAY_COLOR] = PackedColorArray(cols[rm])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[rm])
	var mi2: MeshInstance3D = node["mesh"]
	mi2.mesh = mesh if mesh.get_surface_count() > 0 else null
	var cshape: CollisionShape3D = node["shape"]
	if faces.is_empty():
		cshape.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		cshape.shape = shape
