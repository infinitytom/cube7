class_name VoxelWorld
extends Node3D
## 轻量体素世界：固定大小的方块网格，按 16³ 分块生成网格与碰撞。
## 只负责“方块数据 + 显示 + 破坏”，谜题逻辑通过信号监听它。
## 以后若换成 Voxel Tools，只需保持 get_block / set_block / try_break 这几个接口不变。

signal block_changed(pos: Vector3i, old_type: int, new_type: int)
signal block_broken(pos: Vector3i, type: int)
signal item_dropped(item_id: String, world_pos: Vector3)

const VOXEL := 0.5          ## 1 体素 = 0.5 米
const CHUNK := 8            ## 小区块：破坏时只需重建很小的一块，避免卡顿
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

## 斜坡形状：四个顶角高度 [h(0,0), h(1,0), h(1,1), h(0,1)]，按 (x, z) 排列，单位为方块高度
## 1-4 缓坡下半段、5-8 缓坡上半段（两格升一格，约 27°），9-12 陡坡（45°）
## 方向顺序：朝 +X 升高、朝 -X、朝 +Z、朝 -Z
enum Ramp { PX, NX, PZ, NZ }
const SHAPE_HEIGHTS := {
	1: [0.0, 0.5, 0.5, 0.0], 2: [0.5, 0.0, 0.0, 0.5], 3: [0.0, 0.0, 0.5, 0.5], 4: [0.5, 0.5, 0.0, 0.0],
	5: [0.5, 1.0, 1.0, 0.5], 6: [1.0, 0.5, 0.5, 1.0], 7: [0.5, 0.5, 1.0, 1.0], 8: [1.0, 1.0, 0.5, 0.5],
	9: [0.0, 1.0, 1.0, 0.0], 10: [1.0, 0.0, 0.0, 1.0], 11: [0.0, 0.0, 1.0, 1.0], 12: [1.0, 1.0, 0.0, 0.0],
}

@export var size := Vector3i(112, 32, 64)

var data := PackedByteArray()
## 形状：0 = 立方体，其余为斜坡（见 SHAPE_HEIGHTS）
var shapes := PackedByteArray()
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
	shapes.resize(data.size())
	shapes.fill(0)
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

## 关卡开始时调用：按新尺寸清空世界
func setup(new_size: Vector3i) -> void:
	for c in _chunks.values():
		(c["mesh"] as Node).queue_free()
	_chunks.clear()
	_dirty.clear()
	_falling.clear()
	size = new_size
	data.resize(size.x * size.y * size.z)
	data.fill(Blocks.AIR)
	shapes.resize(data.size())
	shapes.fill(0)

## 关卡搭建用：快速填一整列（不发信号）
func fill_column(x: int, z: int, y0: int, y1: int, t: int) -> void:
	if x < 0 or z < 0 or x >= size.x or z >= size.z:
		return
	for y in range(maxi(y0, 0), mini(y1, size.y - 1) + 1):
		var i := x + size.x * (y + size.y * z)
		data[i] = t
		shapes[i] = 0

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
	shapes[i] = 0
	_mark_dirty_around(p)
	if t == Blocks.AIR:
		# 上方和斜上方的砂块可能会落/滑进这个空位（连锁坍塌）
		for d: Vector3i in [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1)]:
			if Blocks.falls[get_block(p + d)] == 1:
				_falling[p + d] = true
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
					shapes[x + size.x * (y + size.y * z)] = 0
	_mark_dirty_box(lo, hi)

func get_shape(p: Vector3i) -> int:
	if not in_bounds(p):
		return 0
	return shapes[p.x + size.x * (p.y + size.y * p.z)]

## 关卡搭建用：放一个斜坡方块
func set_ramp(p: Vector3i, t: int, shape: int) -> void:
	if not in_bounds(p):
		return
	var i := p.x + size.x * (p.y + size.y * p.z)
	data[i] = t
	shapes[i] = shape
	_mark_dirty_box(p, p)

## 关卡搭建用：沿 dir 方向铺一段坡道。a..b 为坡道占地（含端点，y 取 a.y 为坡底所在层）
## gentle = true 时每两格升一格，否则每格升一格。坡道下方自动用 fill 材质垫实
func fill_ramp(a: Vector3i, b: Vector3i, dir: int, t: int, gentle := true, fill := -1) -> void:
	var lo := Vector3i(mini(a.x, b.x), a.y, mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), a.y, maxi(a.z, b.z))
	var along_x := dir == Ramp.PX or dir == Ramp.NX
	var n := (hi.x - lo.x + 1) if along_x else (hi.z - lo.z + 1)
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var k := (x - lo.x) if along_x else (z - lo.z)
			if dir == Ramp.NX or dir == Ramp.NZ:
				k = n - 1 - k
			var step := k / 2 if gentle else k
			var y := lo.y + step
			var shape: int
			if gentle:
				shape = (1 if k % 2 == 0 else 5) + dir
			else:
				shape = 9 + dir
			set_ramp(Vector3i(x, y, z), t, shape)
			var f := t if fill < 0 else fill
			for yy in range(lo.y, y):
				set_ramp(Vector3i(x, yy, z), f, 0)

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
	if Blocks.chain[t] == 1:
		_chain_from(p, t)
	return true

## 连锁崩塌：相邻的同类方块在 0.06 秒后依次崩塌，像多米诺骨牌
func _chain_from(p: Vector3i, t: int) -> void:
	get_tree().create_timer(0.06).timeout.connect(func() -> void:
		for d in DIRS:
			var q: Vector3i = p + d
			if get_block(q) == t:
				set_block(q, Blocks.AIR)
				_spawn_break_fx(q, t)
				block_broken.emit(q, t)
				_chain_from(q, t)
		GameState.shake.emit(0.12))

## 机关用：无视硬度移除方块（有碎屑特效，不给掉落）
func try_break_any(p: Vector3i) -> void:
	var t := get_block(p)
	if t == Blocks.AIR:
		return
	set_block(p, Blocks.AIR)
	_spawn_debris(voxel_center(p), Blocks.colors[t])

## 以世界坐标为球心破坏一片方块，返回破坏数量。
## 为了更像真实的破坏，形状带随机性：
##   · 每一格的“破坏半径”都随机抖动，坑口边缘参差不齐
##   · 沿撞击方向拉长，撞得越狠坑越深
##   · 坑外一圈的方块有一定概率被震裂
##   · 破坏后和大地断开的小碎块会整块掉落、翻滚、落地再碎
func break_sphere(center: Vector3, radius: float, tool: String, power: float, dir := Vector3.ZERO) -> int:
	var c := world_to_voxel(center)
	var r := int(ceil(radius * 1.35 / VOXEL))
	var count := 0
	var broken: Array[Vector3i] = []
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	for z in range(c.z - r, c.z + r + 1):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var p := Vector3i(x, y, z)
				if get_block(p) == Blocks.AIR:
					continue
				var off := voxel_center(p) - center
				# 沿撞击方向压扁距离 → 坑沿着冲击方向更深
				var along := off.dot(d)
				var dist := (off - d * along).length() + absf(along) * (0.7 if along > 0.0 else 1.0)
				var jitter := _rng.randf_range(0.95, 1.22)   # 只往外抖：坑不会比原来小，边缘更参差
				var inside := dist <= radius * jitter
				var fringe := not inside and dist <= radius * 1.35 and _rng.randf() < 0.28
				if (inside or fringe) and try_break(p, tool, power, count < 16):
					count += 1
					broken.append(p)
	if count > 0:
		GameState.shake.emit(minf(0.08 + count * 0.02, 0.35))
		detach_floating(broken)
	return count

var _rng := RandomNumberGenerator.new()

const DETACH_LIMIT := 48

## 检查被破坏位置周围：和大地失去连接、又足够小的一团方块会变成掉落的碎块。
## 连到打不坏的方块（合金、金属……）、或者一团超过 DETACH_LIMIT 格，都算“有支撑”。
func detach_floating(around: Array[Vector3i]) -> void:
	var checked := {}
	for p in around:
		for dd in DIRS:
			var q: Vector3i = p + dd
			if checked.has(q) or not _detachable(get_block(q)):
				continue
			var comp := _component(q, checked)
			if comp.is_empty():
				continue
			_spawn_chunk(comp)

func _detachable(t: int) -> bool:
	return t != Blocks.AIR and Blocks.falls[t] == 0 and (Blocks.impact[t] >= 0.0 or Blocks.drill[t] == 1)

## 从 start 出发找连通块；有支撑返回空数组
func _component(start: Vector3i, checked: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start]
	var seen := {start: true}
	var supported := false
	while not queue.is_empty():
		var q: Vector3i = queue.pop_back()
		var t := get_block(q)
		if t == Blocks.AIR:
			continue
		if not _detachable(t):
			supported = true
			break
		out.append(q)
		if out.size() > DETACH_LIMIT or q.y <= 0:
			supported = true
			break
		for dd in DIRS:
			var n: Vector3i = q + dd
			if not seen.has(n) and get_block(n) != Blocks.AIR:
				seen[n] = true
				queue.append(n)
	for q in out:
		checked[q] = true
	if supported:
		return []
	return out

func _spawn_chunk(cells: Array[Vector3i]) -> void:
	var sum := Vector3.ZERO
	for q in cells:
		sum += voxel_center(q)
	var mid := sum / cells.size()
	var list := []
	for q in cells:
		list.append([voxel_center(q) - mid, get_block(q)])
	for q in cells:
		set_block(q, Blocks.AIR)
		GameState.blocks_broken += 1
	var ch := VoxelChunk.new()
	ch.world = self
	ch.blocks = list
	add_child(ch)
	ch.global_position = mid
	ch.angular_velocity = Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1), _rng.randf_range(-2, 2))
	ch.linear_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1))

## 在世界坐标处播放破坏特效和掉落（碎块落地时用）
func break_fx_at(pos: Vector3, t: int, drops: bool) -> void:
	_spawn_debris(pos, Blocks.colors[t])
	Sfx.break_sound(t, pos)
	if not drops:
		return
	var d := Blocks.def(t)
	for i in int(d.get("coins", 0)):
		PickupScript.spawn(self, "coin", pos)
	for i in int(d.get("energy", 0)):
		PickupScript.spawn(self, "energy", pos)
	var item: String = d.get("item", "")
	if item != "":
		item_dropped.emit(item, pos)

func _spawn_break_fx(p: Vector3i, t: int) -> void:
	var pos := voxel_center(p)
	_spawn_debris(pos, Blocks.colors[t])
	Sfx.break_sound(t, pos)
	var d := Blocks.def(t)
	for i in int(d.get("coins", 0)):
		PickupScript.spawn(self, "coin", pos)
	for i in int(d.get("energy", 0)):
		PickupScript.spawn(self, "energy", pos)
	var item: String = d.get("item", "")
	if item != "":
		item_dropped.emit(item, pos)

## 碎屑只是视觉粒子，0.6 秒内消散，不参与物理。
## 同一帧里的所有碎屑合并成一个粒子系统（按位置发射、各自带方块颜色），大破坏也不会卡。
var _debris_pts := PackedVector3Array()
var _debris_cols := PackedColorArray()
static var _debris_mesh: BoxMesh

func _spawn_debris(pos: Vector3, color: Color) -> void:
	if _debris_pts.size() < 48:
		_debris_pts.append(to_local(pos))
		_debris_cols.append(color)

func _flush_debris() -> void:
	if _debris_pts.is_empty():
		return
	if _debris_mesh == null:
		_debris_mesh = BoxMesh.new()
		_debris_mesh.size = Vector3.ONE * 0.14
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.8
		_debris_mesh.material = mat
	var ps := CPUParticles3D.new()
	ps.mesh = _debris_mesh
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	ps.emission_points = _debris_pts
	ps.emission_colors = _debris_cols
	ps.amount = clampi(_debris_pts.size() * 5, 6, 80)
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 0.6
	ps.direction = Vector3.UP
	ps.spread = 75.0
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 5.0
	ps.gravity = Vector3(0, -14, 0)
	ps.angular_velocity_min = -360.0
	ps.angular_velocity_max = 360.0
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.4
	ps.scale_amount_curve = _shrink_curve()
	ps.local_coords = false
	add_child(ps)
	ps.emitting = true
	get_tree().create_timer(0.9).timeout.connect(ps.queue_free)
	_debris_pts = PackedVector3Array()
	_debris_cols = PackedColorArray()

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
		_rebuild_dirty()
	_flush_debris()

const REBUILD_BUDGET_MS := 6.0

## 重建脏区块：先重建离主角最近的，每帧最多花 REBUILD_BUDGET_MS 毫秒，剩下的留到下一帧
func _rebuild_dirty() -> void:
	var keys := _dirty.keys()
	var pl := GameState.player as Node3D
	if pl and keys.size() > 1:
		var pc := world_to_voxel(pl.global_position) / CHUNK
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return (a - pc).length_squared() < (b - pc).length_squared())
	var t0 := Time.get_ticks_usec()
	for i in keys.size():
		var c: Vector3i = keys[i]
		_dirty.erase(c)
		_build_chunk(c)
		# 至少重建两个（通常就是主角撞到的地方），再看时间预算
		if i >= 1 and (Time.get_ticks_usec() - t0) > REBUILD_BUDGET_MS * 1000.0:
			break

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
			continue
		# 下方被挡住：像真实砂堆一样往斜下方滑（形成约 45° 的休止角）
		var dirs: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		dirs.shuffle()
		for d in dirs:
			var side: Vector3i = p + d
			var dest: Vector3i = side + Vector3i.DOWN
			if in_bounds(dest) and get_block(side) == Blocks.AIR and get_block(dest) == Blocks.AIR:
				set_block(p, Blocks.AIR)
				set_block(dest, t)
				break

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

## 斜坡方块的网格：顶面按四角高度倾斜，侧面为梯形/三角形
func _mesh_shape(p: Vector3i, t: int, sh: int, vv: Array, nn: Array, cc: Array, uu: Array, u2: Array, faces: PackedVector3Array) -> void:
	var hs: Array = SHAPE_HEIGHTS[sh]
	var o := Vector3(p) * VOXEL
	var b00 := o
	var b10 := o + Vector3(VOXEL, 0, 0)
	var b11 := o + Vector3(VOXEL, 0, VOXEL)
	var b01 := o + Vector3(0, 0, VOXEL)
	var t00 := b00 + Vector3(0, hs[0] * VOXEL, 0)
	var t10 := b10 + Vector3(0, hs[1] * VOXEL, 0)
	var t11 := b11 + Vector3(0, hs[2] * VOXEL, 0)
	var t01 := b01 + Vector3(0, hs[3] * VOXEL, 0)
	var ctx := [vv, nn, cc, uu, u2, faces, _lin_colors[t], Vector2(t / 255.0, (_cat[t] * 16) / 255.0)]
	# 顶面（斜面）
	var top_n := (t10 - t00).cross(t01 - t00)
	if top_n.y < 0.0:
		top_n = -top_n
	_shape_quad(ctx, t00, t10, t11, t01, top_n, 0.72 + 0.28 * top_n.normalized().y)
	# 底面
	if not _is_occluder(get_block(p + Vector3i.DOWN)):
		_shape_quad(ctx, b00, b10, b11, b01, Vector3.DOWN, 0.55)
	# 四个侧面：底边两点、顶边两点、朝向、邻居方向、亮度
	var sides := [
		[b00, b01, t01, t00, Vector3.LEFT, Vector3i(-1, 0, 0), 0.8],
		[b10, b11, t11, t10, Vector3.RIGHT, Vector3i(1, 0, 0), 0.8],
		[b00, b10, t10, t00, Vector3.FORWARD, Vector3i(0, 0, -1), 0.88],
		[b01, b11, t11, t01, Vector3.BACK, Vector3i(0, 0, 1), 0.88],
	]
	for sd in sides:
		var nb: Vector3i = p + sd[5]
		if _is_occluder(get_block(nb)) and get_shape(nb) == 0:
			continue
		var s0: Vector3 = sd[0]
		var s1: Vector3 = sd[1]
		var s2: Vector3 = sd[2]
		var s3: Vector3 = sd[3]
		var h1 := s2.y - s1.y
		var h0 := s3.y - s0.y
		if h0 < 0.001 and h1 < 0.001:
			continue
		if h0 < 0.001:
			_shape_tri(ctx, [s0, s1, s2], sd[4], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], sd[6])
		elif h1 < 0.001:
			_shape_tri(ctx, [s0, s1, s3], sd[4], [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)], sd[6])
		else:
			_shape_quad(ctx, s0, s1, s2, s3, sd[4], sd[6])

func _shape_quad(ctx: Array, q0: Vector3, q1: Vector3, q2: Vector3, q3: Vector3, out: Vector3, light: float) -> void:
	_shape_tri(ctx, [q0, q1, q2], out, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], light)
	_shape_tri(ctx, [q0, q2, q3], out, [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], light)

## 输出一个三角形，自动调整为 Godot 的顺时针正面
func _shape_tri(ctx: Array, pts: Array, out: Vector3, uvl: Array, light: float) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(out) > 0.0:
		order = [0, 2, 1]
	var fn := out.normalized()
	var base: Color = ctx[6]
	var faces: PackedVector3Array = ctx[5]
	for k in order:
		(ctx[0] as Array).append(pts[k])
		(ctx[1] as Array).append(fn)
		(ctx[2] as Array).append(Color(base.r, base.g, base.b, light))
		(ctx[3] as Array).append(uvl[k])
		(ctx[4] as Array).append(ctx[7])
		faces.append(pts[k])
	ctx[5] = faces

## 方块类别（给着色器用）：0 打不坏 / 1 撞得碎 / 2 只能钻 / 3 松软（砂、松土）
func _category(t: int) -> int:
	if Blocks.falls[t] == 1 or Blocks.soft[t] == 1:
		return 3
	if Blocks.impact[t] >= 0.0:
		return 1
	if Blocks.drill[t] == 1:
		return 2
	return 0

# 网格生成用的缓冲（成员变量，避免 Packed 数组放进 Array 后无法原地追加）
var _bv: Array = []
var _occ := PackedByteArray()
var _cat := PackedByteArray()

func _build_chunk(c: Vector3i) -> void:
	var origin := c * CHUNK
	if origin.x < 0 or origin.y < 0 or origin.z < 0 or origin.x >= size.x or origin.y >= size.y or origin.z >= size.z:
		return
	if _occ.is_empty():
		_occ.resize(256)
		_cat.resize(256)
		for t in Blocks.COUNT:
			_occ[t] = 1 if _is_occluder(t) else 0
			_cat[t] = _category(t)
	# 1) 把区块连同一圈邻居拷进带边框的小数组，之后查邻居不用再做边界判断
	const P := CHUNK + 2
	const PP := P * P
	var pb := PackedByteArray()
	pb.resize(P * PP)
	var psh := PackedByteArray()
	psh.resize(P * PP)
	var sx := size.x
	var sxy := size.x * size.y
	for lz in P:
		var z := origin.z - 1 + lz
		if z < 0 or z >= size.z:
			continue
		for ly in P:
			var y := origin.y - 1 + ly
			if y < 0 or y >= size.y:
				continue
			var row := sx * y + sxy * z
			var li := P * ly + PP * lz
			for lx in P:
				var x := origin.x - 1 + lx
				if x < 0 or x >= sx:
					continue
				pb[li + lx] = data[row + x]
				psh[li + lx] = shapes[row + x]
	# 2) 逐面生成
	var v1 := PackedVector3Array(); var n1 := PackedVector3Array(); var c1 := PackedColorArray(); var u1 := PackedVector2Array(); var w1 := PackedVector2Array()
	var v2 := PackedVector3Array(); var n2 := PackedVector3Array(); var c2 := PackedColorArray(); var u2 := PackedVector2Array(); var w2 := PackedVector2Array()
	var v3 := PackedVector3Array(); var n3 := PackedVector3Array(); var c3 := PackedColorArray(); var u3 := PackedVector2Array(); var w3 := PackedVector2Array()
	var faces := PackedVector3Array()
	var glass_faces := PackedVector3Array()
	var ex := mini(CHUNK, size.x - origin.x)
	var ey := mini(CHUNK, size.y - origin.y)
	var ez := mini(CHUNK, size.z - origin.z)
	var doff: Array[int] = [1, -1, P, -P, PP, -PP]
	var uoff: Array[int] = []
	var voff: Array[int] = []
	for f in 6:
		var u: Vector3i = TANGENTS[f][0]
		var v: Vector3i = TANGENTS[f][1]
		uoff.append(u.x + u.y * P + u.z * PP)
		voff.append(v.x + v.y * P + v.z * PP)
	const CS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	const CUV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var slope_lists := [[], [], [], [], []]
	for lz in range(1, ez + 1):
		for ly in range(1, ey + 1):
			for lx in range(1, ex + 1):
				var i := lx + P * ly + PP * lz
				var t: int = pb[i]
				if t == Blocks.AIR:
					continue
				var p := Vector3i(origin.x + lx - 1, origin.y + ly - 1, origin.z + lz - 1)
				var r: int = Blocks.render[t]
				if psh[i] != 0:
					var sv := []
					var sn := []
					var sc := []
					var su := []
					var s2 := []
					_mesh_shape(p, t, psh[i], sv, sn, sc, su, s2, faces)
					for k in sv.size():
						if r == 1:
							v1.append(sv[k]); n1.append(sn[k]); c1.append(sc[k]); u1.append(su[k]); w1.append(s2[k])
						elif r == 3:
							v3.append(sv[k]); n3.append(sn[k]); c3.append(sc[k]); u3.append(su[k]); w3.append(s2[k])
					continue
				var base: Color = _lin_colors[t]
				var h := ((p.x * 73856093) ^ (p.y * 19349663) ^ (p.z * 83492791)) & 255
				var vary := 0.97 + (h / 255.0) * 0.06
				var cat: int = _cat[t]
				var is_glass := r == Blocks.Render.GLASS
				for f in 6:
					var ni := i + doff[f]
					var nt: int = pb[ni]
					var visible := nt == Blocks.AIR or (Blocks.render[nt] == Blocks.Render.GLASS and nt != t) or psh[ni] != 0
					if not visible:
						continue
					var uo: int = uoff[f]
					var vo: int = voff[f]
					var n := DIRS[f]
					var u: Vector3i = TANGENTS[f][0]
					var v: Vector3i = TANGENTS[f][1]
					var center := (Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5) * VOXEL
					# 边缘是否“露在外面”：同一平面继续延伸的边不做倒角 → 平地上看不到方格
					var mask := 0
					var edge_offs: Array[int] = [-uo, uo, -vo, vo]
					for e in 4:
						var nb: int = pb[i + edge_offs[e]]
						var cont := nb != Blocks.AIR and psh[i + edge_offs[e]] == 0 and _occ[pb[i + edge_offs[e] + doff[f]]] == 0 and (_occ[nb] == 1 or nb == t)
						if cat == 1 and nb != t:
							cont = false
						if not cont:
							mask |= 1 << e
					var q: Array[Vector3] = []
					var ao: Array[float] = []
					for k in 4:
						var cs: Vector2i = CS[k]
						q.append(center + (Vector3(u) * cs.x + Vector3(v) * cs.y) * (0.5 * VOXEL))
						var o1: int = _occ[pb[ni + uo * cs.x]]
						var o2: int = _occ[pb[ni + vo * cs.y]]
						var oc: int = _occ[pb[ni + uo * cs.x + vo * cs.y]]
						var occ := 3 if (o1 == 1 and o2 == 1) else o1 + o2 + oc
						ao.append(AO_CURVE[occ])
					var idx: Array
					var flip := ao[0] + ao[2] < ao[1] + ao[3]
					if _face_ccw[f]:
						idx = [0, 2, 1, 0, 3, 2] if not flip else [0, 3, 1, 1, 3, 2]
					else:
						idx = [0, 1, 2, 0, 2, 3] if not flip else [0, 1, 3, 1, 2, 3]
					var shade := FACE_SHADE[f] * vary
					var tuv2 := Vector2(t / 255.0, (mask + cat * 16) / 255.0)
					var nf := Vector3(n)
					for k in idx:
						var col := Color(base.r, base.g, base.b, ao[k] * shade)
						if r == 1:
							v1.append(q[k]); n1.append(nf); c1.append(col); u1.append(CUV[k]); w1.append(tuv2); faces.append(q[k])
						elif r == 2:
							v2.append(q[k]); n2.append(nf); c2.append(col); u2.append(CUV[k]); w2.append(tuv2); glass_faces.append(q[k])
						else:
							v3.append(q[k]); n3.append(nf); c3.append(col); u3.append(CUV[k]); w3.append(tuv2); faces.append(q[k])
	_bv = [null, [v1, n1, c1, u1, w1], [v2, n2, c2, u2, w2], [v3, n3, c3, u3, w3]]

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
		# 玻璃单独一层（层 4 = 值 8）：主角会撞上，镜头可以看穿
		var gbody := StaticBody3D.new()
		gbody.collision_layer = 8
		gbody.collision_mask = 0
		gbody.add_to_group("voxel_body")
		mi.add_child(gbody)
		var gcs := CollisionShape3D.new()
		gbody.add_child(gcs)
		node = {"mesh": mi, "body": body, "shape": cs, "gshape": gcs}
		_chunks[c] = node

	var mesh := ArrayMesh.new()
	for rm in [Blocks.Render.OPAQUE, Blocks.Render.GLASS, Blocks.Render.GLOW]:
		var set: Array = _bv[rm]
		if (set[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = set[0]
		arr[Mesh.ARRAY_NORMAL] = set[1]
		arr[Mesh.ARRAY_COLOR] = set[2]
		arr[Mesh.ARRAY_TEX_UV] = set[3]
		arr[Mesh.ARRAY_TEX_UV2] = set[4]
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
	var gshape: CollisionShape3D = node["gshape"]
	if glass_faces.is_empty():
		gshape.shape = null
	else:
		var gs := ConcavePolygonShape3D.new()
		gs.set_faces(glass_faces)
		gshape.shape = gs
