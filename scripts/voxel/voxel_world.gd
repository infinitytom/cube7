class_name VoxelWorld
extends Node3D
## 轻量体素世界：固定大小的方块网格。
## 两套坐标：
##   · 体素（voxel，0.25 米）——引擎内部、破坏、网格都用它，函数名以 v 开头（vget / vset / vfill …）
##   · 格（cell，0.5 米 = 2×2×2 体素）——关卡搭建和谜题逻辑用它（get_block / set_block / fill_box …）
## 网格：每 8³ 体素算一个小区块（破坏时只重建很小一块），每 2×2×2 个小区块合并成一个渲染/碰撞节点（减少绘制调用）。
## 只负责“方块数据 + 显示 + 破坏”，谜题逻辑通过信号监听它。
## 以后若换成 Voxel Tools，只需保持 vget / vset / vbreak 这几个接口不变。

signal block_changed(pos: Vector3i, old_type: int, new_type: int)
signal block_broken(pos: Vector3i, type: int)
signal item_dropped(item_id: String, world_pos: Vector3)
## 同 block_changed，但坐标换算成“格”（给关卡/谜题/装饰用）
signal cell_changed(cell: Vector3i, old_type: int, new_type: int)

const VOXEL := 0.25         ## 1 体素 = 0.25 米
const CELL := 2             ## 1 格 = 2 体素 = 0.5 米（关卡搭建单位）
const CELL_M := VOXEL * CELL
const GROUP := 2            ## 每个渲染节点合并 GROUP³ 个小区块
const CHUNK := 8            ## 小区块：破坏时只需重建很小的一块，避免卡顿
const FALL_STEP := 0.025    ## 砂块下落一个体素的间隔（秒）
const SMOOTH_SET := 4       ## 远景网格里的第 4 组：平滑曲面（自然材质）
const GSIZE := CHUNK * GROUP   ## 一个渲染组的边长（体素）——平滑地形按渲染组整块生成

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
## 烘焙的朝向明暗：实时的卡通光照已经负责明暗，这里只留一点点，让方块边角更清楚
const FACE_SHADE: Array[float] = [0.94, 0.94, 1.0, 0.85, 0.97, 0.97]
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

@export var size := Vector3i(224, 64, 128)
var csize := Vector3i(112, 32, 64)

var data := PackedByteArray()
## 形状：0 = 立方体，其余为斜坡（见 SHAPE_HEIGHTS）
var shapes := PackedByteArray()
var _lin_colors := PackedColorArray()
var _chunks := {}          ## 渲染组坐标 -> 节点
var _sub := {}             ## 小区块坐标 -> [网格数组, 碰撞三角形, 玻璃碰撞三角形, 有没有平滑材质]
var _gsmooth := {}         ## 渲染组坐标 -> 平滑地形网格（TerrainMesher 的输出）
var _gdirty := {}
var _dirty := {}
var _cell_hit := {}        ## 已经掉过落物的格（一格只掉一次金币/能量/道具）
var _cell_shapes := {}
var fire: VoxelFire
var _falling := {}
var _fall_timer := 0.0
var _materials: Array[Material] = []
## 每个面的三角形索引顺序（考虑 Godot 顺时针为正面）
var _face_ccw: Array[bool] = []

func _ready() -> void:
	add_to_group("voxel_world")
	fire = VoxelFire.new()
	fire.name = "Fire"
	fire.world = self
	add_child(fire)
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
## new_size 按“格”计
func setup(new_size: Vector3i) -> void:
	track_damage = false
	damage.clear()
	for c in _chunks.values():
		(c["mesh"] as Node).queue_free()
	_chunks.clear()
	_sub.clear()
	_gsmooth.clear()
	if fire:
		fire.burning.clear()
		fire.sources.clear()
	_gdirty.clear()
	_dirty.clear()
	_falling.clear()
	_cell_hit.clear()
	_cell_shapes.clear()
	csize = new_size
	size = new_size * CELL
	data.resize(size.x * size.y * size.z)
	data.fill(Blocks.AIR)
	shapes.resize(data.size())
	shapes.fill(0)

## 关卡搭建用：快速填一整列（不发信号）
func vfill_column(x: int, z: int, y0: int, y1: int, t: int) -> void:
	if x < 0 or z < 0 or x >= size.x or z >= size.z:
		return
	for y in range(maxi(y0, 0), mini(y1, size.y - 1) + 1):
		var i := x + size.x * (y + size.y * z)
		data[i] = t
		shapes[i] = 0

# ---------------------------------------------------------------- 数据访问

func vin(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z

func vget(p: Vector3i) -> int:
	if not vin(p):
		return Blocks.AIR
	return data[p.x + size.x * (p.y + size.y * p.z)]

## 某一格被挖空时回调一次（道具放在地面上：地面没了就弹飞）。比每个道具都连 cell_changed 快得多
var _cell_watch := {}
func watch_cell(cell: Vector3i, cb: Callable) -> void:
	if not _cell_watch.has(cell):
		_cell_watch[cell] = []
	(_cell_watch[cell] as Array).append(cb)

func vset(p: Vector3i, t: int) -> void:
	if not vin(p):
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
			if Blocks.falls[vget(p + d)] == 1:
				_falling[p + d] = true
	elif Blocks.falls[t] == 1:
		_falling[p] = true
	if Blocks.ignites[t] == 1 and fire:
		fire.sources[p] = true
	block_changed.emit(p, old, t)
	var cc := Vector3i(p.x >> 1, p.y >> 1, p.z >> 1)
	cell_changed.emit(cc, old, t)
	if t == Blocks.AIR and _cell_watch.has(cc):
		var list: Array = _cell_watch[cc]
		_cell_watch.erase(cc)
		for cb: Callable in list:
			if cb.is_valid():
				cb.call()

## 关卡搭建用：批量填充，不发信号
func vfill(a: Vector3i, b: Vector3i, t: int) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := Vector3i(x, y, z)
				if vin(p):
					data[x + size.x * (y + size.y * z)] = t
					shapes[x + size.x * (y + size.y * z)] = 0
	_mark_dirty_box(lo, hi)

func vshape(p: Vector3i) -> int:
	if not vin(p):
		return 0
	return shapes[p.x + size.x * (p.y + size.y * p.z)]

## 关卡搭建用：放一个斜坡方块
func vset_ramp(p: Vector3i, t: int, shape: int) -> void:
	if not vin(p):
		return
	var i := p.x + size.x * (p.y + size.y * p.z)
	data[i] = t
	shapes[i] = shape
	_mark_dirty_box(p, p)

## 关卡搭建用：沿 dir 方向铺一段坡道。a..b 为坡道占地（含端点，y 取 a.y 为坡底所在层）
## gentle = true 时每两格升一格，否则每格升一格。坡道下方自动用 fill 材质垫实
func vfill_ramp(a: Vector3i, b: Vector3i, dir: int, t: int, gentle := true, fill := -1) -> void:
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
			vset_ramp(Vector3i(x, y, z), t, shape)
			var f := t if fill < 0 else fill
			for yy in range(lo.y, y):
				vset_ramp(Vector3i(x, yy, z), f, 0)

func to_v(w: Vector3) -> Vector3i:
	var l := to_local(w) / VOXEL
	return Vector3i(floori(l.x), floori(l.y), floori(l.z))

func vcenter(p: Vector3i) -> Vector3:
	return to_global((Vector3(p) + Vector3(0.5, 0.5, 0.5)) * VOXEL)

func vtop(p: Vector3i) -> Vector3:
	return to_global((Vector3(p) + Vector3(0.5, 1.0, 0.5)) * VOXEL)

# ---------------------------------------------------------------- “格”坐标接口（0.5 米一格，关卡和谜题用）

func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < csize.x and c.y < csize.y and c.z < csize.z

## 一格里有任何实心体素就返回它的类型（优先返回最上层的，即“这一格表面是什么”），全空返回 AIR
func get_block(c: Vector3i) -> int:
	if not in_bounds(c):
		return Blocks.AIR
	var b := c * CELL
	for dy in range(CELL - 1, -1, -1):
		for dz in CELL:
			for dx in CELL:
				var t := data[(b.x + dx) + size.x * ((b.y + dy) + size.y * (b.z + dz))]
				if t != Blocks.AIR:
					return t
	return Blocks.AIR

func set_block(c: Vector3i, t: int) -> void:
	_cell_shapes.erase(c)
	var b := c * CELL
	for dy in CELL:
		for dz in CELL:
			for dx in CELL:
				vset(b + Vector3i(dx, dy, dz), t)

func fill_box(a: Vector3i, b: Vector3i, t: int) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	vfill(lo * CELL, hi * CELL + Vector3i.ONE * (CELL - 1), t)

func fill_column(x: int, z: int, y0: int, y1: int, t: int) -> void:
	for dz in CELL:
		for dx in CELL:
			vfill_column(x * CELL + dx, z * CELL + dz, y0 * CELL, y1 * CELL + CELL - 1, t)

func get_shape(c: Vector3i) -> int:
	return int(_cell_shapes.get(c, 0))

## 放一个“格”大小的斜坡：按四角高度切成 2×2×2 个体素斜坡/立方体
func set_ramp(c: Vector3i, t: int, shape: int) -> void:
	if shape == 0:
		fill_box(c, c, t)
		_cell_shapes.erase(c)
		return
	_cell_shapes[c] = shape
	var hs: Array = SHAPE_HEIGHTS[shape]
	var b := c * CELL
	for sy in CELL:
		for sz in CELL:
			for sx in CELL:
				# 这个体素四个顶角处的“格高度”，换算成体素内的高度 0..1
				var hv: Array[float] = []
				for corner in [Vector2(sx, sz), Vector2(sx + 1, sz), Vector2(sx + 1, sz + 1), Vector2(sx, sz + 1)]:
					var u: float = corner.x / CELL
					var w: float = corner.y / CELL
					var hc: float = lerpf(lerpf(hs[0], hs[1], u), lerpf(hs[3], hs[2], u), w)
					hv.append(clampf(hc * CELL - sy, 0.0, 1.0))
				var p := b + Vector3i(sx, sy, sz)
				var i := p.x + size.x * (p.y + size.y * p.z)
				if not vin(p):
					continue
				if hv.max() <= 0.001:
					data[i] = Blocks.AIR
					shapes[i] = 0
				elif hv.min() >= 0.999:
					data[i] = t
					shapes[i] = 0
				else:
					data[i] = t
					shapes[i] = _match_shape(hv)
	_mark_dirty_box(b, b + Vector3i.ONE * (CELL - 1))

func _match_shape(hv: Array[float]) -> int:
	var best := 0
	var best_e := 1e9
	for k in SHAPE_HEIGHTS:
		var h: Array = SHAPE_HEIGHTS[k]
		var e := 0.0
		for j in 4:
			e += absf(h[j] - hv[j])
		if e < best_e:
			best_e = e
			best = k
	return best

## 沿 dir 方向铺一段坡道（格坐标）。gentle = true 时每两格升一格
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
	var l := to_local(w) / CELL_M
	return Vector3i(floori(l.x), floori(l.y), floori(l.z))

func voxel_center(c: Vector3i) -> Vector3:
	return to_global((Vector3(c) + Vector3(0.5, 0.5, 0.5)) * CELL_M)

## 格顶面中心：以这一格实际最高的体素为准（被削掉一半的格子也能放准东西）
func voxel_top(c: Vector3i) -> Vector3:
	var top := float(c.y + 1) * CELL_M
	var b := c * CELL
	for dy in range(CELL - 1, -1, -1):
		var any := false
		for dz in CELL:
			for dx in CELL:
				if vget(b + Vector3i(dx, dy, dz)) != Blocks.AIR:
					any = true
		if any:
			top = (b.y + dy + 1) * VOXEL
			break
	return to_global(Vector3((c.x + 0.5) * CELL_M, top, (c.z + 0.5) * CELL_M))

func try_break(c: Vector3i, tool: String, power: float, fx := true) -> bool:
	var any := false
	var b := c * CELL
	for dy in CELL:
		for dz in CELL:
			for dx in CELL:
				if vbreak(b + Vector3i(dx, dy, dz), tool, power, fx and not any):
					any = true
	return any

func try_break_any(c: Vector3i) -> void:
	var b := c * CELL
	for dy in CELL:
		for dz in CELL:
			for dx in CELL:
				vbreak_any(b + Vector3i(dx, dy, dz))

# ---------------------------------------------------------------- 细节：让体素地形更自然
## 关卡用“格”搭好后，在体素精度上做一遍自然化：
##   · 草皮只留最上面一层体素，崖边往下垂一点草皮
##   · 悬崖岩按高度分出几种颜色的岩层（带起伏）
##   · 露在外面的地形棱角随机崩掉一些（边缘参差），崖壁上随机凹坑
## protect：不处理的区域（格坐标 AABB 列表，谜题关键位置）
func naturalize(y_max_cell: int, protect: Array = [], seed_v := 7) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.05
	var ymax := mini(size.y - 1, (y_max_cell + 1) * CELL)
	var sx := size.x
	var sxy := size.x * size.y
	# 1) 每一列的最高实心体素
	var tops := PackedInt32Array()
	tops.resize(size.x * size.z)
	for z in size.z:
		for x in size.x:
			var top := -1
			var i := x + sxy * z
			for y in range(ymax, -1, -1):
				if data[i + sx * y] != Blocks.AIR:
					top = y
					break
			tops[x + size.x * z] = top
	var natural := {Blocks.GRASS: true, Blocks.DIRT: true, Blocks.CLIFF: true, Blocks.MOSS: true, Blocks.CLIFF_B: true, Blocks.CLIFF_C: true}
	var removes: Array[Vector3i] = []
	var sets: Array = []
	for z in size.z:
		for x in size.x:
			var top := tops[x + size.x * z]
			if top < 1:
				continue
			var cell := Vector3i(x >> 1, top >> 1, z >> 1)
			var skip := false
			for box in protect:
				if (box as AABB).has_point(Vector3(cell) + Vector3.ONE * 0.5):
					skip = true
					break
			if skip:
				continue
			var ti := x + sx * top + sxy * z
			var tt := data[ti]
			if shapes[ti] != 0:
				continue
			# 邻居列最低的顶
			var nmin := top
			var open_sides := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var nz: int = z + d.y
				var nt := -1 if nx < 0 or nz < 0 or nx >= size.x or nz >= size.z else tops[nx + size.x * nz]
				nmin = mini(nmin, nt)
				if nt < top:
					open_sides += 1
			# 草皮只留一层
			if tt == Blocks.GRASS and top >= 1 and data[ti - sx] == Blocks.GRASS:
				data[ti - sx] = Blocks.DIRT
			# 崖壁：岩层 + 凹坑 + 垂下的草皮
			var hang_len := int(clampf((noise.get_noise_2d(x * 1.6, z * 1.6) + 0.25) * 4.0, 0.0, 3.0))
			for y in range(maxi(nmin + 1, 0), top):
				var i := x + sx * y + sxy * z
				var t := data[i]
				if t == Blocks.CLIFF or t == Blocks.CLIFF_B or t == Blocks.CLIFF_C:
					var band := y * 0.5 + noise.get_noise_2d(x * 0.7, z * 0.7) * 3.0
					var k := posmod(int(floor(band / 3.0)), 5)
					data[i] = [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF, Blocks.CLIFF_C, Blocks.CLIFF_B][k]
					# 成片的风化凹坑（噪声决定位置，比随机单点自然）
					if y < top - 2 and noise.get_noise_3d(x * 2.2, y * 2.2, z * 2.2) > 0.42:
						removes.append(Vector3i(x, y, z))
				if tt == Blocks.GRASS and y >= top - hang_len and (t == Blocks.DIRT or t == Blocks.CLIFF):
					data[i] = Blocks.GRASS
			# 露在外面的棱角崩掉一些（角上更容易崩）
			if natural.has(tt) and open_sides > 0 and top - nmin >= 2:
				var p := 0.22 if open_sides == 1 else 0.55
				if rng.randf() < p:
					removes.append(Vector3i(x, top, z))
					if open_sides >= 2 and rng.randf() < 0.35:
						removes.append(Vector3i(x, top - 1, z))
	for p in removes:
		var i := p.x + sx * p.y + sxy * p.z
		data[i] = Blocks.AIR
		shapes[i] = 0
	# 被崩掉顶的草地，下面露出来的土重新长草
	for p in removes:
		var below := p + Vector3i.DOWN
		if vget(below) == Blocks.DIRT and vget(p) == Blocks.AIR and rng.randf() < 0.7:
			data[below.x + sx * below.y + sxy * below.z] = Blocks.GRASS
	_mark_dirty_box(Vector3i.ZERO, size - Vector3i.ONE)
	print("[VoxelWorld] 自然化 %d ms（崩掉 %d 个体素）" % [Time.get_ticks_msec() - t0, removes.size()])

# ---------------------------------------------------------------- 体素树
## 在体素 root（树根所在的空气体素）长一棵树。只填空气，不会覆盖地形。
## kind: "round" 圆冠阔叶树 / "pine" 分层松树 / "blossom" 开花的树
func put_tree(root: Vector3i, trunk_h: int, crown_r: float, kind: String, rng: RandomNumberGenerator) -> void:
	var lo := root
	var hi := root
	var lean := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.12
	# 树干：2×2 体素，微微倾斜，根部多一圈
	var top := root
	for y in trunk_h:
		var off := Vector2i(roundi(lean.x * y), roundi(lean.y * y))
		for dz in 2:
			for dx in 2:
				var p := root + Vector3i(off.x + dx, y, off.y + dz)
				_put(p, Blocks.WOOD)
		top = root + Vector3i(off.x, y, off.y)
	for d in [Vector3i(-1, 0, 0), Vector3i(2, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 2)]:
		if rng.randf() < 0.7:
			_put(root + d, Blocks.WOOD)
	var leaf := Blocks.LEAVES
	if kind == "pine":
		leaf = Blocks.PINE
	elif kind == "blossom":
		leaf = Blocks.BLOSSOM
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.35
	var r := crown_r / VOXEL
	var c := Vector3(top) + Vector3(1.0, 0.0, 1.0)
	if kind == "pine":
		# 分层的圆锥：每层是一个扁圆盘，越往上越小
		var tiers := 4
		var y0 := int(trunk_h * 0.35)
		var total := trunk_h - y0 + int(r * 1.2)
		for yi in total:
			var f := float(yi) / total
			var tier_f := fmod(f * tiers, 1.0)
			var rad := r * (1.0 - f * 0.85) * (0.75 + 0.35 * (1.0 - tier_f))
			var yy := root.y + y0 + yi
			var ir := int(ceil(rad)) + 1
			for dz in range(-ir, ir + 1):
				for dx in range(-ir, ir + 1):
					var d := Vector2(dx + 0.5 - 1.0, dz + 0.5 - 1.0).length()
					if d <= rad + noise.get_noise_3d(dx, yy, dz) * 0.9:
						_put(Vector3i(int(c.x) + dx, yy, int(c.z) + dz), leaf)
		lo = root - Vector3i(ir_of(r), 0, ir_of(r))
		hi = root + Vector3i(ir_of(r), trunk_h + int(r * 1.3) + 2, ir_of(r))
	else:
		# 几个互相重叠的球组成树冠，表面用噪声抖一下，底部削平
		var blobs := [[c + Vector3(0, r * 0.35, 0), r]]
		for k in 3:
			var a := rng.randf() * TAU
			blobs.append([c + Vector3(cos(a) * r * 0.55, r * rng.randf_range(0.0, 0.5), sin(a) * r * 0.55), r * rng.randf_range(0.55, 0.75)])
		var ir := int(ceil(r * 1.4)) + 1
		for dz in range(-ir, ir + 1):
			for dy in range(-int(r * 0.6), ir + 1):
				for dx in range(-ir, ir + 1):
					var p := Vector3(c.x + dx, c.y + dy, c.z + dz)
					var inside := false
					for b in blobs:
						var bc: Vector3 = b[0]
						var br: float = b[1]
						if (p - bc).length() <= br + noise.get_noise_3dv(p) * 1.1:
							inside = true
							break
					if inside and p.y > c.y - r * 0.45:
						_put(Vector3i(p.floor()), leaf)
		lo = Vector3i(c.floor()) - Vector3i(ir, int(r) + trunk_h, ir)
		hi = Vector3i(c.floor()) + Vector3i(ir, ir + 1, ir)
	_mark_dirty_box(lo - Vector3i.ONE * 2, hi + Vector3i.ONE * 2)

func ir_of(r: float) -> int:
	return int(ceil(r)) + 3

## 搭建用：直接写一个体素（不发信号，稍后统一重建）
func vset_raw(p: Vector3i, t: int) -> void:
	if not vin(p):
		return
	var i := p.x + size.x * (p.y + size.y * p.z)
	data[i] = t
	shapes[i] = 0
	_dirty[Vector3i(p.x >> 3, p.y >> 3, p.z >> 3)] = true

func _put(p: Vector3i, t: int) -> void:
	if not vin(p):
		return
	var i := p.x + size.x * (p.y + size.y * p.z)
	if data[i] == Blocks.AIR:
		data[i] = t
		shapes[i] = 0

## 立刻重建所有脏区块（关卡搭建完后用）
func flush_dirty() -> void:
	for c in _dirty.keys():
		_build_chunk(c)
	_dirty.clear()
	_commit_groups()

# ---------------------------------------------------------------- 破坏记录与重构

## 关卡搭好以后打开：记下 PIX 砸掉的每一个地形体素（原来是什么），重构塔点亮时让它们飞回原位
var track_damage := false
var damage := {}

const RESTORABLE := [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.ROCK, Blocks.MOSS, Blocks.LOOSE, Blocks.PLANK, Blocks.WOOD,
	Blocks.LEAVES, Blocks.PINE, Blocks.BLOSSOM, Blocks.ORE, Blocks.GEODE, Blocks.RUST, Blocks.PAVING, Blocks.CLIFF, Blocks.CLIFF_B,
	Blocks.CLIFF_C, Blocks.GLOWSHROOM, Blocks.DARKROCK, Blocks.DARKROCK_B, Blocks.TILE, Blocks.HULL, Blocks.HULL_DARK,
	Blocks.RUSTDUNE, Blocks.RUSTROCK]

static var _restorable_lut := PackedByteArray()
func log_damage(p: Vector3i, t: int) -> void:
	if not track_damage:
		return
	if _restorable_lut.is_empty():
		_restorable_lut.resize(256)
		for r in RESTORABLE:
			_restorable_lut[r] = 1
	if _restorable_lut[t] == 1 and not damage.has(p):
		damage[p] = t

## 重构波：以 center 为圆心，radius 米以内被砸掉的地形在 dur 秒内由近到远一格格飞回来。返回飞回来的块数
func restore_wave(center: Vector3, radius: float, dur: float, from_below := true) -> int:
	# 按 0.5 米的格分组：一格一个飞行方块，落地时写回这一格里所有被砸掉的体素
	var cells := {}
	for p: Vector3i in damage.keys():
		var w := vcenter(p)
		if w.distance_to(center) > radius:
			continue
		if vget(p) != Blocks.AIR:
			damage.erase(p)
			continue
		var c := Vector3i(p.x >> 1, p.y >> 1, p.z >> 1)
		if not cells.has(c):
			cells[c] = []
		(cells[c] as Array).append([p, damage[p]])
	if cells.is_empty():
		return 0
	var rb := VoxelRebuilder.new()
	rb.world = self
	add_child(rb)
	var keys := cells.keys()
	var dists := {}
	for c: Vector3i in keys:
		dists[c] = voxel_center(c).distance_to(center)
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return dists[a] < dists[b])
	for c: Vector3i in keys:
		var to := voxel_center(c)
		var d: float = dists[c]
		var from := to + (Vector3(_rng.randf_range(-1.5, 1.5), -6.0, _rng.randf_range(-1.5, 1.5)) if from_below else (to - center).normalized() * 4.0 + Vector3.UP * 3.0)
		rb.add(cells[c], to, from, d / maxf(radius, 1.0) * dur + _rng.randf_range(0.0, 0.25), _rng.randf_range(0.5, 0.8))
	return keys.size()

# ---------------------------------------------------------------- 破坏

## tool: "impact"（撞击，power = 速度）或 "drill"（钻头）
func vbreak(p: Vector3i, tool: String, power: float, fx := true) -> bool:
	var t := vget(p)
	if not Blocks.can_break(t, tool, power):
		return false
	log_damage(p, t)
	vset(p, Blocks.AIR)
	if _first_hit(p):
		GameState.blocks_broken += 1
		_drops(p, t)
	if fx:
		_spawn_break_fx(p, t)
	block_broken.emit(p, t)
	# 燃料桶被撞碎/钻破也会炸
	if Blocks.explodes[t] == 1 and fire:
		fire.explode_at.call_deferred(vcenter(p))
	if Blocks.chain[t] == 1:
		_chain_from(p, t)
	return true

## 批量破坏（break_sphere 用）：和 vbreak 一样，但不逐个体素发信号——
## 每一格（0.5 米）只发一次 cell_changed，大坑一次几百个体素也不卡
var _batch_cells := {}
func _vbreak_batch(p: Vector3i, i: int, t: int, tool: String, power: float) -> bool:
	if not Blocks.can_break(t, tool, power):
		return false
	if Blocks.explodes[t] == 1 or Blocks.chain[t] == 1 or Blocks.ignites[t] == 1 or Blocks.falls[t] == 1:
		return vbreak(p, tool, power, false)
	log_damage(p, t)
	data[i] = Blocks.AIR
	shapes[i] = 0
	_mark_dirty_around(p)
	for d in [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1)]:
		if Blocks.falls[vget(p + d)] == 1:
			_falling[p + d] = true
	var cc := Vector3i(p.x >> 1, p.y >> 1, p.z >> 1)
	if not _batch_cells.has(cc):
		_batch_cells[cc] = t
	if _has_block_listeners:
		block_changed.emit(p, t, Blocks.AIR)
	if _first_hit(p):
		GameState.blocks_broken += 1
		_drops(p, t)
	return true

var _has_block_listeners := false

func _flush_batch_signals() -> void:
	for cc: Vector3i in _batch_cells:
		cell_changed.emit(cc, _batch_cells[cc], Blocks.AIR)
		if _cell_watch.has(cc):
			var list: Array = _cell_watch[cc]
			_cell_watch.erase(cc)
			for cb: Callable in list:
				if cb.is_valid():
					cb.call()
	_batch_cells.clear()

## 连锁崩塌：相邻的同类方块在 0.06 秒后依次崩塌，像多米诺骨牌
func _chain_from(p: Vector3i, t: int) -> void:
	get_tree().create_timer(0.06).timeout.connect(func() -> void:
		for d in DIRS:
			var q: Vector3i = p + d
			if vget(q) == t:
				log_damage(q, t)
				vset(q, Blocks.AIR)
				_spawn_break_fx(q, t)
				if _first_hit(q):
					_drops(q, t)
				block_broken.emit(q, t)
				_chain_from(q, t)
				# 连锁崩掉的支撑上面托着的东西也要检查（落石陷阱：木架塌了，石头掉下来）
				var around: Array[Vector3i] = [q]
				detach_floating(around)
		GameState.shake.emit(0.12))

## Boss 啃地形：球形范围里除了 protect 列表以外的方块全部挖掉（记进破坏记录，有碎屑，不给掉落）
func carve_sphere(center: Vector3, radius: float, protect: Array) -> int:
	var c := to_v(center)
	var r := int(ceil(radius / VOXEL))
	var broken: Array[Vector3i] = []
	for z in range(c.z - r, c.z + r + 1):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var p := Vector3i(x, y, z)
				var t := vget(p)
				if t == Blocks.AIR or t in protect:
					continue
				if vcenter(p).distance_to(center) > radius * _rng.randf_range(0.9, 1.1):
					continue
				log_damage(p, t)
				vset(p, Blocks.AIR)
				if broken.size() % 6 == 0:
					_spawn_break_fx(p, t)
				broken.append(p)
	if not broken.is_empty():
		detach_floating(broken)
	return broken.size()

## 机关用：无视硬度移除方块（有碎屑特效，不给掉落）
func vbreak_any(p: Vector3i) -> void:
	var t := vget(p)
	if t == Blocks.AIR:
		return
	vset(p, Blocks.AIR)
	_spawn_debris(vcenter(p), t)

## 以世界坐标为球心破坏一片方块，返回破坏数量。
## 破坏形状模拟真实材料：
##   · 坑口轮廓由连续噪声决定（不是逐格随机的“麻点”），边缘参差但连贯
##   · 沿撞击方向拉长，撞得越狠坑越深
##   · 脆的材料（岩、石板、加固墙……）按 Voronoi 裂成几大块：坑边缘的整块碎片会被崩飞出去
##   · 土、草、沙是碗状的坑，带一圈震松的边；木头碎成木片，玻璃碎成薄片
##   · 破坏后和大地断开的部分会整块掉落、翻滚，落地再碎
## min_y：低于这个高度（世界坐标）的体素不破坏——横着撞墙时不把脚下的地面一起啃掉
func break_sphere(center: Vector3, radius: float, tool: String, power: float, dir := Vector3.ZERO, soft_only := false, min_y := -INF) -> int:
	prof_t0 = Time.get_ticks_usec()
	var c := to_v(center)
	var r := int(ceil(radius * 1.45 / VOXEL))
	var count := 0
	var broken: Array[Vector3i] = []
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	# 裂块的种子点：坑周围随机撒几颗，离中心近的种子所在的整块都会碎掉
	var seeds: Array[Vector3] = []
	var nseed := 5 + int(radius * 4.0)
	for i in nseed:
		var sp := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.2, 1.5) * radius
		seeds.append(center + sp)
	# 只有重击（撞击、爆炸，半径够大）才会把岩石裂成大块；钻头是干净的圆隧道
	var brittle := tool == "impact" and radius >= 0.9
	# 最远可能被波及的距离（脆性裂块 1.45 倍，噪声坑沿 1.32 倍 + 一圈掉渣）
	var reach := radius * 1.45 if brittle else radius * 1.32 + VOXEL * 1.5
	r = int(ceil(reach / VOXEL)) + 1
	var first_t := Blocks.ROCK
	_has_block_listeners = block_changed.get_connections().size() > 0
	var frag := {}     # 种子序号 -> 这块碎片里被拆下来的体素（之后整块崩飞）
	_crack_noise.seed = _rng.randi()
	# 只遍历球内的体素（按行算出 x 的范围），直接读数组——大坑一次几千个体素，这里要快
	var rr := float(r * r)
	var gxf := global_transform
	var sx := size.x
	var sxy := size.x * size.y
	for z in range(maxi(c.z - r, 0), mini(c.z + r, size.z - 1) + 1):
		var dz := z - c.z
		for y in range(maxi(c.y - r, 0), mini(c.y + r, size.y - 1) + 1):
			var dy := y - c.y
			var rem := rr - dz * dz - dy * dy
			if rem < 0.0:
				continue
			var hx := int(sqrt(rem))
			var row := sx * y + sxy * z
			for x in range(maxi(c.x - hx, 0), mini(c.x + hx, sx - 1) + 1):
				var bt: int = data[row + x]
				if bt == Blocks.AIR or (soft_only and Blocks.soft[bt] == 0 and bt != Blocks.COPPER):
					continue
				var p := Vector3i(x, y, z)
				var vc := gxf * ((Vector3(p) + Vector3(0.5, 0.5, 0.5)) * VOXEL)
				if vc.y < min_y:
					continue
				var off := vc - center
				# 沿撞击方向压扁距离 → 坑沿着冲击方向更深
				var along := off.dot(d)
				var dist := (off - d * along).length() + absf(along) * (0.7 if along > 0.0 else 1.0)
				if dist > reach:
					continue
				var kind := Blocks.frag_kind(bt)
				var inside := false
				var seed_id := -1
				if kind == Blocks.Frag.ROCK and brittle:
					# 脆：落在“近种子”所属的 Voronoi 块里就整块碎（坑壁是一个个裂面）
					var best := INF
					for si in seeds.size():
						var dd := vc.distance_squared_to(seeds[si])
						if dd < best:
							best = dd
							seed_id = si
					var sd := seeds[seed_id].distance_to(center)
					inside = dist <= radius * 0.75 or (sd <= radius * 1.05 and dist <= radius * 1.45)
				else:
					# 韧 / 松：连续噪声决定坑沿（只往外扩，坑不会比原来小）；坑里面不用算噪声
					if dist <= radius:
						inside = true
					else:
						var nv := _crack_noise.get_noise_3dv(vc * 1.6) * 0.5 + 0.5
						var edge := radius * (1.0 + 0.32 * nv)
						inside = dist <= edge
						if not inside and kind == Blocks.Frag.EARTH and dist <= edge + VOXEL * 1.5:
							# 震松的一圈：零星掉渣
							inside = _rng.randf() < 0.12
				if inside and _vbreak_batch(p, row + x, bt, tool, power):
					if count == 0:
						first_t = bt
					count += 1
					broken.append(p)
					if seed_id >= 0 and seeds[seed_id].distance_to(center) > radius * 0.55:
						if not frag.has(seed_id):
							frag[seed_id] = []
						(frag[seed_id] as Array).append([vc, bt])
					elif count % 4 == 0:
						_spawn_debris(vc, bt)
	_flush_batch_signals()
	var t_loop := Time.get_ticks_usec()
	if count > 0:
		if tool == "impact":
			GameState.shake.emit(minf(0.08 + count * 0.02, 0.35))
		_fling_fragments(frag, center, d, power)
		var t_frag := Time.get_ticks_usec()
		Sfx.break_sound(first_t, center)
		detach_floating(broken)
		if PROFILE:
			prof_acc[0] += t_loop - prof_t0
			prof_acc[1] += t_frag - t_loop
			prof_acc[2] += Time.get_ticks_usec() - t_frag
	return count

static var PROFILE := false
static var prof_acc := [0, 0, 0]
var prof_t0 := 0

## 把裂下来的整块碎片崩飞出去（纯视觉 + 物理，掉落已经在 vbreak 里结算过了）
const MAX_FRAGMENTS := 5
func _fling_fragments(frag: Dictionary, center: Vector3, dir: Vector3, power: float) -> void:
	var keys := frag.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return (frag[a] as Array).size() > (frag[b] as Array).size())
	var n := 0
	for k in keys:
		var list: Array = frag[k]
		if list.size() < 3 or n >= MAX_FRAGMENTS or VoxelChunk.alive >= VoxelChunk.MAX_ALIVE:
			for e in list:
				_spawn_debris(e[0], e[1])
			continue
		n += 1
		var sum := Vector3.ZERO
		for e in list:
			sum += e[0]
		var mid := sum / list.size()
		var blocks := []
		for e in list:
			blocks.append([(e[0] as Vector3) - mid, e[1]])
		var ch := VoxelChunk.new()
		ch.world = self
		ch.blocks = blocks
		ch.spawn_origin = to_local(mid)
		ch.fragment = true
		add_child(ch)
		ch.global_position = mid
		var outv := (mid - center).normalized()
		if outv.length() < 0.1:
			outv = Vector3.UP
		var spd := clampf(power * 0.25, 2.0, 6.0) * _rng.randf_range(0.6, 1.1)
		ch.linear_velocity = (outv + Vector3.UP * 0.6 + dir * 0.4).normalized() * spd
		ch.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))

var _crack_noise := _make_crack_noise()
static func _make_crack_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.9
	n.fractal_octaves = 2
	return n

var _rng := RandomNumberGenerator.new()

const DETACH_LIMIT := 900

## 检查被破坏位置周围：和大地失去连接、又足够小的一团方块会变成掉落的碎块。
## 连到打不坏的方块（合金、金属……）、或者一团超过 DETACH_LIMIT 格，都算“有支撑”。
func detach_floating(around: Array[Vector3i]) -> void:
	# 留到下一帧再算：破坏这一帧已经够忙了，断开的碎块晚一帧掉下来看不出来
	_pending_detach.append_array(around)

var _pending_detach: Array[Vector3i] = []

func _process_detach() -> void:
	if _pending_detach.is_empty():
		return
	var around := _pending_detach
	_pending_detach = []
	_init_det()
	var checked := {}
	var sx := size.x
	var sxy := size.x * size.y
	for p in around:
		for dd in DIRS:
			var q: Vector3i = p + dd
			if not vin(q):
				continue
			var qi := q.x + sx * q.y + sxy * q.z
			if checked.has(qi) or _det[data[qi]] == 0:
				continue
			var comp := _component_i(qi, checked)
			if comp.is_empty():
				continue
			_spawn_chunk(comp)

## 燃烧中的方块在烧完之前仍然算“撑着”（否则烧到一半的木架会一块块掉下去，把火也带走）
func _detachable(t: int) -> bool:
	return t != Blocks.AIR and t != Blocks.FIRE and Blocks.falls[t] == 0 and (Blocks.impact[t] >= 0.0 or Blocks.drill[t] == 1)

var _det := PackedByteArray()
func _init_det() -> void:
	if _det.is_empty():
		_det.resize(256)
		for t in Blocks.COUNT:
			_det[t] = 1 if _detachable(t) else 0

## 从 start 出发找连通块；有支撑返回空数组。
## “支撑”要够结实：一大块东西只靠一两根细木头连着固定的方块，也会被压塌（ANCHOR_WEIGHT 个体素 / 每个接触面）
## 用整数下标做广度搜索（不用 Vector3i 和函数调用），大破坏时快很多
const ANCHOR_WEIGHT := 90

## 访问标记：整个世界一张 int 表，每次搜索换一个“代号”，不用每次清空，也不用字典
var _visit := PackedInt32Array()
var _visit_gen := 0

func _component_i(start: int, checked: Dictionary) -> Array[Vector3i]:
	var sx := size.x
	var sy := size.y
	var sz := size.z
	var sxy := sx * sy
	if _visit.size() != data.size():
		_visit.resize(data.size())
		_visit.fill(0)
		_visit_gen = 0
	_visit_gen += 1
	var gen := _visit_gen
	var out := PackedInt32Array()
	var queue := PackedInt32Array([start])
	_visit[start] = gen
	var anchors := 0
	var supported := false
	# 先进先出（真正的广度优先）：从坑边往外一圈圈搜，搜过的一大片都会记成“有支撑”，
	# 坑边其他起点基本都落在里面，不用再各自搜一遍
	var head := 0
	while head < queue.size():
		var q: int = queue[head]
		head += 1
		out.append(q)
		var x := q % sx
		var y := (q / sx) % sy
		var z := q / sxy
		if out.size() > DETACH_LIMIT or y <= 0:
			supported = true
			break
		for k in 6:
			var n := -1
			match k:
				0: n = q + 1 if x < sx - 1 else -1
				1: n = q - 1 if x > 0 else -1
				2: n = q + sx if y < sy - 1 else -1
				3: n = q - sx
				4: n = q + sxy if z < sz - 1 else -1
				5: n = q - sxy if z > 0 else -1
			if n < 0 or _visit[n] == gen:
				continue
			var nt: int = data[n]
			if nt == 0:
				continue
			if _det[nt] == 0:
				anchors += 1
				# 接触到的固定方块已经多到“无论这团多大都撑得住”：不用再搜了
				if anchors * ANCHOR_WEIGHT > DETACH_LIMIT:
					supported = true
					break
				continue
			# 连到了前面已经确认“有支撑”的那一大团：这团也有支撑，不用再搜
			if checked.has(n):
				supported = true
				break
			_visit[n] = gen
			queue.append(n)
		if supported:
			break
	if supported or anchors * ANCHOR_WEIGHT >= out.size():
		# 有支撑：这次搜过的都记成“有支撑”（只记已出队的 + 队列里的，够用了）
		for qi in range(queue.size()):
			checked[queue[qi]] = true
		return []
	var res: Array[Vector3i] = []
	for q in out:
		checked[q] = true
		res.append(Vector3i(q % sx, (q / sx) % sy, q / sxy))
	return res

## （兼容旧调用）
func _component(start: Vector3i, checked: Dictionary) -> Array[Vector3i]:
	_init_det()
	return _component_i(start.x + size.x * start.y + size.x * size.y * start.z, checked)

func _spawn_chunk(cells: Array[Vector3i]) -> void:
	var sum := Vector3.ZERO
	for q in cells:
		sum += vcenter(q)
	var mid := sum / cells.size()
	var list := []
	for q in cells:
		list.append([vcenter(q) - mid, vget(q)])
	for q in cells:
		log_damage(q, vget(q))
		vset(q, Blocks.AIR)
		if _first_hit(q):
			GameState.blocks_broken += 1
	var ch := VoxelChunk.new()
	ch.world = self
	ch.blocks = list
	ch.spawn_origin = to_local(mid)
	add_child(ch)
	ch.global_position = mid
	# 小碎块崩开时带一点随机翻滚；大块结构（桥板、墙）直直地往下掉
	var k := clampf(1.0 - (cells.size() - 24) / 150.0, 0.0, 1.0)
	ch.angular_velocity = Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1), _rng.randf_range(-2, 2)) * k
	ch.linear_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)) * k

## 在世界坐标处播放破坏特效和掉落（碎块落地时用）
func break_fx_at(pos: Vector3, t: int, drops: bool) -> void:
	_spawn_debris(pos, t)
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
	var pos := vcenter(p)
	_spawn_debris(pos, t)
	Sfx.break_sound(t, pos)

## 一格（2×2×2 体素）里第一次有体素被破坏时返回 true
func _first_hit(p: Vector3i) -> bool:
	var c := Vector3i(p.x >> 1, p.y >> 1, p.z >> 1)
	if _cell_hit.has(c):
		return false
	_cell_hit[c] = true
	return true

func _drops(p: Vector3i, t: int) -> void:
	var pos := vcenter(p)
	var d := Blocks.def(t)
	for i in int(d.get("coins", 0)):
		PickupScript.spawn(self, "coin", pos)
	for i in int(d.get("energy", 0)):
		PickupScript.spawn(self, "energy", pos)
	var item: String = d.get("item", "")
	if item != "":
		item_dropped.emit(item, pos)

## 碎屑只是视觉粒子，不参与物理。按材质分成几种形状：
##   岩石 → 不规则的多面体小石块；泥土 → 圆圆的土块；木头 → 细长的木片（翻得快）；
##   玻璃 → 薄薄的三角碎片（闪一下）；树叶 → 小叶片（飘着落下）；金属 → 小块 + 零星火花
## 同一帧、同一种材质的碎屑合并成一个粒子系统（各自带方块颜色），大破坏也不会卡。
var _debris := {}      # Frag -> [PackedVector3Array 位置, PackedColorArray 颜色]
static var _frag_meshes := {}

func _spawn_debris(pos: Vector3, t: int) -> void:
	var k := Blocks.frag_kind(t)
	if not _debris.has(k):
		_debris[k] = [PackedVector3Array(), PackedColorArray()]
	var e: Array = _debris[k]
	var pts: PackedVector3Array = e[0]
	if pts.size() >= 40:
		return
	pts.append(to_local(pos))
	var cols: PackedColorArray = e[1]
	# 颜色带一点深浅变化（碎块的断面比表面暗）
	cols.append(Blocks.colors[t] * _rng.randf_range(0.72, 1.05))
	e[0] = pts
	e[1] = cols

static func _frag_mesh(k: int) -> Mesh:
	if _frag_meshes.has(k):
		return _frag_meshes[k]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	var m: Mesh
	match k:
		Blocks.Frag.WOOD:
			var b := BoxMesh.new()
			b.size = Vector3(0.05, 0.05, 0.24)
			m = b
		Blocks.Frag.GLASS:
			m = _shard_mesh(0.16, 0.012)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1, 1, 1, 0.75)
			mat.metallic_specular = 1.0
			mat.roughness = 0.05
		Blocks.Frag.LEAF:
			m = _shard_mesh(0.12, 0.004)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		Blocks.Frag.EARTH:
			var sp := SphereMesh.new()
			sp.radius = 0.06
			sp.height = 0.1
			sp.radial_segments = 6
			sp.rings = 3
			m = sp
		Blocks.Frag.CRYSTAL:
			m = _shard_mesh(0.14, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.8, 1.0)
			mat.emission_energy_multiplier = 0.6
		Blocks.Frag.METAL:
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.09, 0.03, 0.09)
			m = b2
			mat.metallic = 0.6
			mat.roughness = 0.35
		_:
			m = _pebble_mesh(0.08)
	m.surface_set_material(0, mat)
	_frag_meshes[k] = m
	return m

## 不规则小石块：随机挤压过的八面体（每个面都是斜的，像敲下来的碎石）
static func _pebble_mesh(r: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pts: Array[Vector3] = []
	for v in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		pts.append(v * r * rng.randf_range(0.6, 1.25) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * r * 0.25)
	var tris := [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var a: Vector3 = pts[t[0]]
		var b: Vector3 = pts[t[1]]
		var c: Vector3 = pts[t[2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	return st.commit()

## 薄片（玻璃 / 叶子 / 晶片）：一个有厚度的三角形
static func _shard_mesh(r: float, th: float) -> ArrayMesh:
	var a := Vector3(0, 0, r)
	var b := Vector3(r * 0.8, 0, -r * 0.5)
	var c := Vector3(-r * 0.6, 0, -r * 0.6)
	var up := Vector3.UP * th
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		st.set_normal(Vector3.UP * side)
		if side > 0.0:
			st.add_vertex(a + up); st.add_vertex(b + up); st.add_vertex(c + up)
		else:
			st.add_vertex(a - up); st.add_vertex(c - up); st.add_vertex(b - up)
	return st.commit()

func _flush_debris() -> void:
	if _debris.is_empty():
		return
	var all_pts := PackedVector3Array()
	for k: int in _debris:
		var e: Array = _debris[k]
		var pts: PackedVector3Array = e[0]
		if pts.is_empty():
			continue
		all_pts.append_array(pts)
		var ps := CPUParticles3D.new()
		ps.mesh = _frag_mesh(k)
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		ps.emission_points = pts
		ps.emission_colors = e[1]
		ps.one_shot = true
		ps.explosiveness = 0.95
		ps.direction = Vector3.UP
		ps.particle_flag_rotate_y = false
		ps.angular_velocity_min = -540.0
		ps.angular_velocity_max = 540.0
		ps.scale_amount_curve = _shrink_curve()
		ps.local_coords = false
		match k:
			Blocks.Frag.LEAF:
				ps.amount = clampi(pts.size() * 4, 6, 80)
				ps.lifetime = 1.6
				ps.spread = 90.0
				ps.initial_velocity_min = 1.0
				ps.initial_velocity_max = 3.0
				ps.gravity = Vector3(0, -2.2, 0)
				ps.damping_min = 1.5
				ps.damping_max = 3.0
				ps.scale_amount_min = 0.7
				ps.scale_amount_max = 1.3
			Blocks.Frag.WOOD:
				ps.amount = clampi(pts.size() * 4, 5, 90)
				ps.lifetime = 1.0
				ps.spread = 70.0
				ps.initial_velocity_min = 3.0
				ps.initial_velocity_max = 7.0
				ps.gravity = Vector3(0, -15, 0)
				ps.angular_velocity_min = -900.0
				ps.angular_velocity_max = 900.0
				ps.scale_amount_min = 0.5
				ps.scale_amount_max = 1.3
			Blocks.Frag.GLASS, Blocks.Frag.CRYSTAL:
				ps.amount = clampi(pts.size() * 5, 6, 90)
				ps.lifetime = 0.9
				ps.spread = 85.0
				ps.initial_velocity_min = 3.0
				ps.initial_velocity_max = 8.0
				ps.gravity = Vector3(0, -16, 0)
				ps.scale_amount_min = 0.5
				ps.scale_amount_max = 1.4
			Blocks.Frag.EARTH:
				ps.amount = clampi(pts.size() * 4, 5, 100)
				ps.lifetime = 0.8
				ps.spread = 60.0
				ps.initial_velocity_min = 2.0
				ps.initial_velocity_max = 5.5
				ps.gravity = Vector3(0, -15, 0)
				ps.scale_amount_min = 0.6
				ps.scale_amount_max = 1.6
			_:
				ps.amount = clampi(pts.size() * 4, 5, 100)
				ps.lifetime = 0.95
				ps.spread = 75.0
				ps.initial_velocity_min = 2.5
				ps.initial_velocity_max = 6.5
				ps.gravity = Vector3(0, -16, 0)
				ps.scale_amount_min = 0.5
				ps.scale_amount_max = 1.8
		add_child(ps)
		ps.emitting = true
		get_tree().create_timer(ps.lifetime + 0.4).timeout.connect(ps.queue_free)
	if all_pts.size() >= 12:
		_dust(all_pts)
	_debris.clear()

## 大破坏时腾起的一团尘土
static var _dust_mesh: SphereMesh
func _dust(pts: PackedVector3Array) -> void:
	if _dust_mesh == null:
		_dust_mesh = SphereMesh.new()
		_dust_mesh.radius = 0.22
		_dust_mesh.height = 0.44
		_dust_mesh.radial_segments = 8
		_dust_mesh.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.92, 0.86, 0.76, 0.22)
		_dust_mesh.material = m
	var ps := CPUParticles3D.new()
	ps.mesh = _dust_mesh
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	ps.emission_points = pts
	ps.amount = clampi(pts.size() / 5, 3, 8)
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.lifetime = 0.8
	ps.direction = Vector3.UP
	ps.spread = 90.0
	ps.initial_velocity_min = 0.4
	ps.initial_velocity_max = 1.4
	ps.gravity = Vector3(0, 0.4, 0)
	ps.damping_min = 1.0
	ps.damping_max = 2.0
	ps.scale_amount_min = 0.8
	ps.scale_amount_max = 1.5
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 1.2))
	ps.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	ps.color_ramp = g
	ps.local_coords = false
	add_child(ps)
	ps.emitting = true
	get_tree().create_timer(1.5).timeout.connect(ps.queue_free)

static var _curve_cache: Curve
static func _shrink_curve() -> Curve:
	if _curve_cache == null:
		_curve_cache = Curve.new()
		_curve_cache.add_point(Vector2(0, 1))
		_curve_cache.add_point(Vector2(1, 0))
	return _curve_cache

# ---------------------------------------------------------------- 更新

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_detach()
	var t1 := Time.get_ticks_usec()
	if not _falling.is_empty():
		_fall_timer += delta
		if _fall_timer >= FALL_STEP:
			_fall_timer = 0.0
			_step_falling()
	if not _dirty.is_empty():
		_rebuild_dirty()
	var t2 := Time.get_ticks_usec()
	_flush_debris()
	if PROFILE:
		prof_frame[0] += t1 - t0
		prof_frame[1] += t2 - t1
		prof_frame[2] += Time.get_ticks_usec() - t2

static var prof_frame := [0, 0, 0]
static var prof_rb := [0, 0, 0, 0]

const REBUILD_BUDGET_MS := 5.0

## 重建脏区块：按渲染组（GROUP³ 个小区块）来，离主角最近的组先重建。
## 每帧的预算把“合并网格 + 重建碰撞”（最贵的一步）也算进去；至少处理一个组，剩下的留到后面几帧
func _rebuild_dirty() -> void:
	var groups := {}
	for c: Vector3i in _dirty:
		var g := Vector3i(c.x >> 1, c.y >> 1, c.z >> 1)
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(c)
	var gkeys := groups.keys()
	var pl := GameState.player as Node3D
	if pl and gkeys.size() > 1:
		var pg := to_v(pl.global_position) / (CHUNK * GROUP)
		gkeys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return (a - pg).length_squared() < (b - pg).length_squared())
	var t0 := Time.get_ticks_usec()
	for i in gkeys.size():
		var g: Vector3i = gkeys[i]
		var ta := Time.get_ticks_usec()
		for c: Vector3i in groups[g]:
			_dirty.erase(c)
			_build_chunk(c)
		var tb := Time.get_ticks_usec()
		if _group_needs_smooth(g):
			_smooth_group(g)
		var tc := Time.get_ticks_usec()
		_commit_group(g)
		if PROFILE:
			prof_rb[0] += tb - ta
			prof_rb[1] += tc - tb
			prof_rb[2] += Time.get_ticks_usec() - tc
			prof_rb[3] += 1
		_gdirty.erase(g)
		# 积压多（大破坏、重构波）时多给一点预算，让地形尽快跟上，不留空洞
		var budget := REBUILD_BUDGET_MS * (1.4 if gkeys.size() > 8 else 1.0)
		if (Time.get_ticks_usec() - t0) > budget * 1000.0:
			break

func _step_falling() -> void:
	var current := _falling.keys()
	_falling.clear()
	for p in current:
		var t := vget(p)
		if Blocks.falls[t] == 0:
			continue
		var below: Vector3i = p + Vector3i.DOWN
		if vin(below) and vget(below) == Blocks.AIR:
			vset(p, Blocks.AIR)      # 会把上方的砂加入下落队列
			vset(below, t)           # 会把自己加入下一轮
			continue
		# 下方被挡住：像真实砂堆一样往斜下方滑（形成约 45° 的休止角）
		var dirs: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		dirs.shuffle()
		for d in dirs:
			var side: Vector3i = p + d
			var dest: Vector3i = side + Vector3i.DOWN
			if vin(dest) and vget(side) == Blocks.AIR and vget(dest) == Blocks.AIR:
				vset(p, Blocks.AIR)
				vset(dest, t)
				break

func rebuild_all() -> void:
	var t0 := Time.get_ticks_msec()
	_init_tables()
	# 所有小区块分给多个线程并行生成（只读体素数据，写结果时加锁）
	var list: Array[Vector3i] = []
	for cz in ceili(size.z / float(CHUNK)):
		for cy in ceili(size.y / float(CHUNK)):
			for cx in ceili(size.x / float(CHUNK)):
				list.append(Vector3i(cx, cy, cz))
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void: _build_chunk(list[i]), list.size(), -1, true, "voxel mesh")
	WorkerThreadPool.wait_for_group_task_completion(task)
	print("[VoxelWorld] 网格生成 %d ms（%d 个小区块）" % [Time.get_ticks_msec() - t0, list.size()])
	_dirty.clear()
	_commit_groups()
	print("[VoxelWorld] 全部区块生成耗时 %d ms" % (Time.get_ticks_msec() - t0))

func _mark_dirty_around(p: Vector3i) -> void:
	# 只有贴着区块边界的体素才会影响相邻区块（每次破坏几百个体素，这里要快）
	var cx := p.x >> 3
	var cy := p.y >> 3
	var cz := p.z >> 3
	var lx := p.x & 7
	var ly := p.y & 7
	var lz := p.z & 7
	# 平滑曲面要看周围 3 格（模糊 + 接缝），所以离边界 3 格以内都会影响隔壁区块
	var x0 := cx - 1 if lx < 3 else cx
	var x1 := cx + 1 if lx > 4 else cx
	var y0 := cy - 1 if ly < 3 else cy
	var y1 := cy + 1 if ly > 4 else cy
	var z0 := cz - 1 if lz < 3 else cz
	var z1 := cz + 1 if lz > 4 else cz
	if x0 == x1 and y0 == y1 and z0 == z1:
		_dirty[Vector3i(cx, cy, cz)] = true
		return
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				_dirty[Vector3i(x, y, z)] = true

func _mark_dirty_box(lo: Vector3i, hi: Vector3i) -> void:
	for cz in range(floori((lo.z - 3) / float(CHUNK)), floori((hi.z + 3) / float(CHUNK)) + 1):
		for cy in range(floori((lo.y - 3) / float(CHUNK)), floori((hi.y + 3) / float(CHUNK)) + 1):
			for cx in range(floori((lo.x - 3) / float(CHUNK)), floori((hi.x + 3) / float(CHUNK)) + 1):
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
	if not _is_occluder(vget(p + Vector3i.DOWN)):
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
		if _is_occluder(vget(nb)) and vshape(nb) == 0:
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

func _chunk_all_air(origin: Vector3i) -> bool:
	var x0 := maxi(origin.x - 1, 0)
	var x1 := mini(origin.x + CHUNK + 1, size.x)
	for z in range(maxi(origin.z - 1, 0), mini(origin.z + CHUNK + 1, size.z)):
		for y in range(maxi(origin.y - 1, 0), mini(origin.y + CHUNK + 1, size.y)):
			var row := size.x * (y + size.y * z)
			var sl := data.slice(row + x0, row + x1)
			if sl.count(0) != sl.size():
				return false
	return true

# 网格生成用的缓冲（成员变量，避免 Packed 数组放进 Array 后无法原地追加）
var _bv: Array = []
var _occ := PackedByteArray()
var _cat := PackedByteArray()

var _mesh_mutex := Mutex.new()

var _smooth := PackedByteArray()
var _dens_tab := PackedFloat32Array()
const RAMP_FILL := {1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25, 5: 0.75, 6: 0.75, 7: 0.75, 8: 0.75, 9: 0.5, 10: 0.5, 11: 0.5, 12: 0.5}

func _init_tables() -> void:
	if _occ.is_empty():
		_occ.resize(256)
		_cat.resize(256)
		_smooth.resize(256)
		_dens_tab.resize(256)
		for t in Blocks.COUNT:
			_occ[t] = 1 if _is_occluder(t) else 0
			_cat[t] = _category(t)
			_smooth[t] = Blocks.smooth[t]
			_dens_tab[t] = 1.0 if _occ[t] == 1 else 0.0

## 平滑地形的填充度：只有平滑材质算“实心”（方块类的箱子、金属、玻璃对地形来说是空的，交界处由方块自己的面盖住）
func _sdens(t: int, sh: int) -> float:
	if _smooth[t] == 0:
		return 0.0
	return 1.0 if sh == 0 else float(RAMP_FILL.get(sh, 0.5))

## 一个渲染组的平滑地形（可以在工作线程里调用：只读体素数据）
func _smooth_group(g: Vector3i) -> void:
	var res := {}
	var lo := g * GSIZE
	var n := Vector3i(GSIZE + 1, GSIZE + 1, GSIZE + 1)
	if TerrainMesher.available():
		res = _smooth_group_vt(lo, n)
	if res.has("fallback") or not TerrainMesher.available():
		res = _smooth_group_sn(lo, n)
	_mesh_mutex.lock()
	if res.is_empty():
		_gsmooth.erase(g)
	else:
		_gsmooth[g] = res
	_mesh_mutex.unlock()

func _smooth_xf(g: Vector3i) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * VOXEL), (Vector3(g * GSIZE) + Vector3(0.5, 0.5, 0.5)) * VOXEL)

## Voxel Tools 快速路径：按行整段拷贝方块类型（几百次切片），剩下的全交给 VoxelBuffer 的 C++ 运算
func _smooth_group_vt(lo: Vector3i, n: Vector3i) -> Dictionary:
	var rs := n + Vector3i(4, 4, 4)
	var ro := lo - Vector3i(2, 2, 2)
	var bytes := PackedByteArray()
	var zero_row := PackedByteArray()
	zero_row.resize(rs.x)
	var sx := size.x
	var sxy := size.x * size.y
	var x0 := maxi(ro.x, 0)
	var x1 := mini(ro.x + rs.x, sx)
	var pre := PackedByteArray()
	pre.resize(maxi(x0 - ro.x, 0))
	var post := PackedByteArray()
	post.resize(maxi(ro.x + rs.x - x1, 0))
	var any := false
	for z in rs.z:
		var wz := ro.z + z
		for y in rs.y:
			var wy := ro.y + y
			if wz < 0 or wz >= size.z or wy < 0 or wy >= size.y or x1 <= x0:
				bytes.append_array(zero_row)
				continue
			var row := sxy * wz + sx * wy
			var sl := data.slice(row + x0, row + x1)
			if not any and sl.count(0) != sl.size():
				any = true
			bytes.append_array(pre)
			bytes.append_array(sl)
			bytes.append_array(post)
	if not any:
		return {}
	if OS.has_environment("CUBE7_SLOW_TERRAIN"):
		return _smooth_group_vt_slow(lo, n)
	return TerrainMesher.build_vt_fast(bytes, rs, n)

## （旧的逐体素版本，保留做对照）
func _smooth_group_vt_slow(lo: Vector3i, n: Vector3i) -> Dictionary:
	var bs := n + Vector3i(2, 2, 2)
	var rs := bs + Vector3i(2, 2, 2)
	var ro := lo - Vector3i(2, 2, 2)
	var dens := PackedFloat32Array()
	dens.resize(rs.x * rs.y * rs.z)
	var slots := PackedByteArray()
	slots.resize(bs.x * bs.y * bs.z)
	var slot_tab := TerrainPalette.table()
	var sx := size.x
	var sxy := size.x * size.y
	var any := false
	var i := 0
	for z in rs.z:
		var wz := ro.z + z
		var zin := wz >= 0 and wz < size.z
		for x in rs.x:
			var wx := ro.x + x
			var xin := zin and wx >= 0 and wx < sx
			var bz := z - 1
			var bx := x - 1
			var inner_xz := bz >= 0 and bz < bs.z and bx >= 0 and bx < bs.x
			for y in rs.y:
				var wy := ro.y + y
				if xin and wy >= 0 and wy < size.y:
					var wi := wx + sx * wy + sxy * wz
					var t: int = data[wi]
					if t != 0 and _smooth[t] == 1:
						var sh: int = shapes[wi]
						dens[i] = 1.0 if sh == 0 else float(RAMP_FILL.get(sh, 0.5))
						any = true
						var by := y - 1
						if inner_xz and by >= 0 and by < bs.y:
							slots[by + bs.y * (bx + bs.x * bz)] = slot_tab[t]
				i += 1
	if not any:
		return {}
	return TerrainMesher.build_vt(dens, slots, n)

## 没有 Voxel Tools：GDScript Surface Nets（XYZ 顺序、四周 PAD 格边框）
func _smooth_group_sn(lo: Vector3i, n: Vector3i) -> Dictionary:
	var pad := SmoothMesher.PAD
	var dims := n + Vector3i(pad * 2, pad * 2, pad * 2)
	var types := PackedByteArray()
	types.resize(dims.x * dims.y * dims.z)
	var dens := PackedFloat32Array()
	dens.resize(types.size())
	var sx := size.x
	var sxy := size.x * size.y
	var o := lo - Vector3i(pad, pad, pad)
	var any := false
	var i := 0
	for lz in dims.z:
		var z := o.z + lz
		for ly in dims.y:
			var y := o.y + ly
			var row_ok := z >= 0 and z < size.z and y >= 0 and y < size.y
			var row := sx * y + sxy * z
			for lx in dims.x:
				var x := o.x + lx
				if row_ok and x >= 0 and x < sx:
					var t: int = data[row + x]
					if t != 0 and _smooth[t] == 1:
						types[i] = t
						dens[i] = _sdens(t, shapes[row + x])
						any = true
				i += 1
	if not any:
		return {}
	var r := SmoothMesher.build_dict(types, dens, dims, n)
	if (r["verts"] as PackedVector3Array).is_empty():
		return {}
	return r

func _build_chunk(c: Vector3i) -> void:
	var origin := c * CHUNK
	if origin.x < 0 or origin.y < 0 or origin.z < 0 or origin.x >= size.x or origin.y >= size.y or origin.z >= size.z:
		return
	_init_tables()
	# 1) 把区块连同一圈邻居拷进带边框的小数组，之后查邻居不用再做边界判断
	const P := CHUNK + 2
	const PP := P * P
	# 整个小区块连同邻居都是空气就不用生成（大部分天空区块）
	if _chunk_all_air(origin):
		_mesh_mutex.lock()
		_sub.erase(c)
		_gdirty[Vector3i(c.x >> 1, c.y >> 1, c.z >> 1)] = true
		_mesh_mutex.unlock()
		return
	var pb := PackedByteArray()
	var psh := PackedByteArray()
	var sx := size.x
	var sxy := size.x * size.y
	var inner := origin.x >= 1 and origin.y >= 1 and origin.z >= 1 and origin.x + CHUNK + 1 <= size.x and origin.y + CHUNK + 1 <= size.y and origin.z + CHUNK + 1 <= size.z
	if inner:
		# 整块在世界内部：按行整段拷贝（比逐个体素快很多），顺便看看有没有露出来的面
		var any_open := false
		for lz in P:
			var z := origin.z - 1 + lz
			for ly in P:
				var row := sx * (origin.y - 1 + ly) + sxy * z + origin.x - 1
				var sl := data.slice(row, row + P)
				var sh := shapes.slice(row, row + P)
				pb.append_array(sl)
				psh.append_array(sh)
				if not any_open and (sl.count(0) > 0 or sl.count(Blocks.GLASS) > 0 or sh.count(0) != P):
					any_open = true
		if not any_open:
			# 全实心、四周也全实心：没有任何面
			_mesh_mutex.lock()
			if _sub.has(c):
				_sub.erase(c)
				_gdirty[Vector3i(c.x >> 1, c.y >> 1, c.z >> 1)] = true
			_mesh_mutex.unlock()
			return
	else:
		pb.resize(P * PP)
		psh.resize(P * PP)
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
	var has_smooth := false
	for lz in range(1, ez + 1):
		for ly in range(1, ey + 1):
			for lx in range(1, ex + 1):
				var i := lx + P * ly + PP * lz
				var t: int = pb[i]
				if t == Blocks.AIR:
					continue
				if _smooth[t] == 1:
					has_smooth = true
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
					# 挨着平滑地形的面也要画：地形曲面在交界处是圆的，会露出方块的边
					var visible := nt == Blocks.AIR or (Blocks.render[nt] == Blocks.Render.GLASS and nt != t) or psh[ni] != 0 or _smooth[nt] == 1
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
	var g := Vector3i(c.x >> 1, c.y >> 1, c.z >> 1)
	_mesh_mutex.lock()
	_gdirty[g] = true
	if v1.is_empty() and v2.is_empty() and v3.is_empty() and not has_smooth:
		_sub.erase(c)
		_mesh_mutex.unlock()
		return
	_sub[c] = [[null, [v1, n1, c1, u1, w1], [v2, n2, c2, u2, w2], [v3, n3, c3, u3, w3]], faces, glass_faces, has_smooth]
	_mesh_mutex.unlock()

## 把一个渲染组（GROUP³ 个小区块）的网格和碰撞拼起来
func _commit_group(g: Vector3i) -> void:
	var sets := [null, [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()],
		[PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()],
		[PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]]
	var faces := PackedVector3Array()
	var glass_faces := PackedVector3Array()
	for dz in GROUP:
		for dy in GROUP:
			for dx in GROUP:
				var sc: Vector3i = g * GROUP + Vector3i(dx, dy, dz)
				if not _sub.has(sc):
					continue
				var sub: Array = _sub[sc]
				for rm in [1, 2, 3]:
					var src: Array = sub[0][rm]
					var dst: Array = sets[rm]
					for k in 5:
						dst[k].append_array(src[k])
				faces.append_array(sub[1])
				glass_faces.append_array(sub[2])
	_mesh_mutex.lock()
	var sm: Dictionary = _gsmooth.get(g, {})
	_mesh_mutex.unlock()
	var node: Dictionary = _chunks.get(g, {})
	var empty := faces.is_empty() and glass_faces.is_empty() and (sets[1][0] as PackedVector3Array).is_empty() and (sets[2][0] as PackedVector3Array).is_empty() and (sets[3][0] as PackedVector3Array).is_empty() and sm.is_empty()
	if empty:
		if not node.is_empty():
			(node["mesh"] as Node).queue_free()
			_chunks.erase(g)
		return
	if node.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_%d" % [g.x, g.y, g.z]
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
		_chunks[g] = node

	var mesh := ArrayMesh.new()
	# 平滑地形先放进网格，顺便拿它的三角形做碰撞（C++ 里展开，不用逐个三角形循环）
	if not sm.is_empty():
		TerrainMesher.add_surface(mesh, sm, _smooth_xf(g), TerrainPalette.material())
		if mesh.get_surface_count() > 0:
			faces.append_array(mesh.get_faces())
	for rm in [Blocks.Render.OPAQUE, Blocks.Render.GLASS, Blocks.Render.GLOW]:
		var set: Array = sets[rm]
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

func _commit_groups() -> void:
	_smooth_groups(_gdirty.keys())
	for g in _gdirty.keys():
		_commit_group(g)
	_gdirty.clear()

## 组里有没有平滑材质（看各小区块生成时记下的标记；以前有平滑网格的也要重算一次，好把它清掉）
func _group_needs_smooth(g: Vector3i) -> bool:
	if _gsmooth.has(g):
		return true
	for dz in GROUP:
		for dy in GROUP:
			for dx in GROUP:
				var sub: Array = _sub.get(g * GROUP + Vector3i(dx, dy, dz), [])
				if sub.size() > 3 and sub[3]:
					return true
	return false

## 多个组的平滑地形（主线程串行：Voxel Tools 的网格器放进 WorkerThreadPool 会和它自己的线程池互相等待；
## 每组约 2 毫秒，整关几百组不到 1 秒）
func _smooth_groups(groups: Array) -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	for g: Vector3i in groups:
		if _group_needs_smooth(g):
			_smooth_group(g)
			n += 1
	if n > 20:
		print("[Terrain] 平滑地形 %d 组 %d ms" % [n, Time.get_ticks_msec() - t0])
