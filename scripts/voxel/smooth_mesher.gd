class_name SmoothMesher
extends RefCounted
## 平滑体素网格（Surface Nets）。
## 底层仍是 0.25 米的体素格子：哪些体素是实心、谁能被打碎，规则都不变；
## 只是自然材质（草、土、岩、沙、树冠……）的表面不再画成立方体，而是在体素之间生成一张柔和的曲面——
## 坑会是碗状的，崖边是圆润的，掉下来的碎块像石头而不是一摞小方块。
##
## 输入是一块带边框的体素数组（边框 PAD 格，用来让相邻区块的接缝处顶点完全一致）：
##   types[i]：方块类型；dens[i]：填充度 0..1（空气 / 玻璃 = 0，满格 = 1，斜坡 = 平均高度）
## 只为“拥有”的体素（索引 PAD .. dims-PAD-1）和它的 +x/+y/+z 邻居之间的面生成网格，所以区块之间不会重复。

const PAD := 3

## 每格 8 个角（按位：bit0 = x，bit1 = y，bit2 = z）和 12 条棱
const EDGES: Array = [
	[0, 1], [2, 3], [4, 5], [6, 7],   # 沿 x
	[0, 2], [1, 3], [4, 6], [5, 7],   # 沿 y
	[0, 4], [1, 5], [2, 6], [3, 7],   # 沿 z
]

## 方块是否走平滑网格（由 Blocks.smooth 填）
static var smooth_table := PackedByteArray()
## 地面类材质（草、土、岩、沙……）之间颜色柔和过渡；树干、树冠不参与（免得糊成一片）
static var blend_table := PackedByteArray()

## dims：带边框的尺寸；base：数组索引 0 对应的体素坐标（世界体素空间），voxel：体素边长（米）
## lin_colors / cats：每种方块的线性颜色、类别（给着色器）
## out：[verts, normals, colors, custom1(PackedFloat32Array，每顶点 2 个，材质槽位打包)]；want_faces = true 时碰撞三角形放在 out[4]（Packed 数组按值传递，必须放进 out 里带回）
## owned_lo / owned_hi：拥有的体素索引范围（含 lo，不含 hi）；默认是去掉边框的部分
static func build(types: PackedByteArray, dens: PackedFloat32Array, dims: Vector3i, base: Vector3, voxel: float,
		lin_colors: PackedColorArray, cats: PackedByteArray, out: Array, want_faces: bool, owned_lo := Vector3i(PAD, PAD, PAD), owned_hi := Vector3i(-1, -1, -1)) -> int:
	if owned_hi.x < 0:
		owned_hi = dims - Vector3i(PAD, PAD, PAD)
	var sx := dims.x
	var sxy := dims.x * dims.y
	var n := dims.x * dims.y * dims.z
	# 1) 3×3×3 盒式模糊（可分离）：决定顶点落在哪、法线朝哪 —— 让曲面更圆润，而不是 45° 的倒角
	var b := _blur3(dens, dims)
	# 和 Voxel Tools 那条路用同一个场：0.55 × 原始 + 0.45 × 模糊（两种引擎下地形形状、碰撞一致）
	for i in n:
		b[i] = dens[i] * TerrainMesher.BLUR_RAW + b[i] * (1.0 - TerrainMesher.BLUR_RAW)
	# 2) 每格顶点（懒计算）
	var cell_v := PackedInt32Array()
	cell_v.resize(n)
	cell_v.fill(-1)
	var vp := PackedVector3Array()   # 顶点位置（体素中心坐标）
	var vn := PackedVector3Array()   # 法线
	var va := PackedFloat32Array()   # 遮蔽
	var vc := PackedColorArray()     # 材质颜色（周围实心体素的平均 → 交界处柔和过渡）
	var verts: PackedVector3Array = out[0]
	var norms: PackedVector3Array = out[1]
	var cols: PackedColorArray = out[2]
	var c1s: PackedFloat32Array = out[3]
	var faces := PackedVector3Array()
	var emitted := 0
	var axis_off: Array[int] = [1, sx, sxy]
	for z in range(owned_lo.z, owned_hi.z):
		for y in range(owned_lo.y, owned_hi.y):
			for x in range(owned_lo.x, owned_hi.x):
				var i := x + sx * y + sxy * z
				var da := dens[i]
				var sa := da >= 0.5
				for d in 3:
					var j: int = i + axis_off[d]
					var sb := dens[j] >= 0.5
					if sa == sb:
						continue
					var solid := i if sa else j
					var t: int = types[solid]
					if smooth_table[t] == 0:
						continue
					# 这条“体素中心连线”周围的 4 个格：沿轴坐标 = 本体素，另外两轴各取 -1 / 0
					var c := Vector3i(x, y, z)
					var u := Vector3i.ZERO
					var v := Vector3i.ZERO
					if d == 0:
						u = Vector3i(0, 1, 0); v = Vector3i(0, 0, 1)
					elif d == 1:
						u = Vector3i(1, 0, 0); v = Vector3i(0, 0, 1)
					else:
						u = Vector3i(1, 0, 0); v = Vector3i(0, 1, 0)
					var q: Array[int] = [
						_vertex(c - u - v, dims, dens, b, cell_v, vp, vn, va, types, lin_colors, vc),
						_vertex(c - v, dims, dens, b, cell_v, vp, vn, va, types, lin_colors, vc),
						_vertex(c, dims, dens, b, cell_v, vp, vn, va, types, lin_colors, vc),
						_vertex(c - u, dims, dens, b, cell_v, vp, vn, va, types, lin_colors, vc),
					]
					if q[0] < 0 or q[1] < 0 or q[2] < 0 or q[3] < 0:
						continue
					var outward := Vector3.ZERO
					outward[d] = 1.0 if sa else -1.0
					var base_col: Color = lin_colors[t]
					var pk: Vector2 = _packed(t)
					# 沿较短的对角线切成两个三角形（曲面更顺）
					var p0 := vp[q[0]]; var p1 := vp[q[1]]; var p2 := vp[q[2]]; var p3 := vp[q[3]]
					var tris: Array
					if p0.distance_squared_to(p2) <= p1.distance_squared_to(p3):
						tris = [[0, 1, 2], [0, 2, 3]]
					else:
						tris = [[0, 1, 3], [1, 2, 3]]
					for tri in tris:
						var a: int = q[tri[0]]
						var bb: int = q[tri[1]]
						var cc: int = q[tri[2]]
						# Godot 顺时针为正面
						if (vp[bb] - vp[a]).cross(vp[cc] - vp[a]).dot(outward) > 0.0:
							var tmp := bb
							bb = cc
							cc = tmp
						for k: int in [a, bb, cc]:
							var wp := (base + vp[k] + Vector3(0.5, 0.5, 0.5)) * voxel
							verts.append(wp)
							norms.append(vn[k])
							var mc: Color = base_col
							if blend_table[t] == 1 and vc[k].a > 0.0:
								mc = base_col.lerp(vc[k], 0.6)
							cols.append(Color(mc.r, mc.g, mc.b, va[k]))
							c1s.append(pk.x)
							c1s.append(pk.y)
							if want_faces:
								faces.append(wp)
						emitted += 1
	out[0] = verts
	out[1] = norms
	out[2] = cols
	out[3] = c1s
	if want_faces:
		if out.size() < 5:
			out.append(faces)
		else:
			out[4] = faces
	return emitted

static var _pk_cache := {}
static func _packed(t: int) -> Vector2:
	if not _pk_cache.has(t):
		_pk_cache[t] = TerrainPalette.packed_single(TerrainPalette.slot_of(t))
	return _pk_cache[t]

## 统一入口：和 TerrainMesher.build_vt 一样的输出格式（体素中心坐标）
## types / dens：XYZ 顺序（x 最快）的带边框数组；n：要覆盖的格点数；数组索引 PAD 对应格点 0
static func build_dict(types: PackedByteArray, dens: PackedFloat32Array, dims: Vector3i, n: Vector3i) -> Dictionary:
	var lin := PackedColorArray()
	lin.resize(256)
	for t in Blocks.COUNT:
		lin[t] = Blocks.colors[t].srgb_to_linear()
	var out: Array = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedFloat32Array()]
	# 体素中心坐标：数组索引 PAD → 0；SmoothMesher 输出的是 (base + 索引 + 0.5) * voxel，令 voxel = 1、base = -PAD - 0.5
	build(types, dens, dims, Vector3(-PAD, -PAD, -PAD) - Vector3(0.5, 0.5, 0.5), 1.0, lin, PackedByteArray(), out, false,
		Vector3i(PAD, PAD, PAD), Vector3i(PAD, PAD, PAD) + n - Vector3i.ONE)
	return {"verts": out[0], "normals": out[1], "colors": out[2], "custom1": out[3], "indices": PackedInt32Array()}

static func _blur3(src: PackedFloat32Array, dims: Vector3i) -> PackedFloat32Array:
	var sx := dims.x
	var sxy := dims.x * dims.y
	var a := src.duplicate()
	var bb := src.duplicate()
	# x
	for z in dims.z:
		for y in dims.y:
			var row := sx * y + sxy * z
			for x in range(1, dims.x - 1):
				var i := row + x
				bb[i] = (src[i - 1] + src[i] + src[i + 1]) * (1.0 / 3.0)
	# y
	for z in dims.z:
		for y in range(1, dims.y - 1):
			var row := sx * y + sxy * z
			for x in dims.x:
				var i := row + x
				a[i] = (bb[i - sx] + bb[i] + bb[i + sx]) * (1.0 / 3.0)
	# z
	for z in range(1, dims.z - 1):
		for y in dims.y:
			var row := sx * y + sxy * z
			for x in dims.x:
				var i := row + x
				bb[i] = (a[i - sxy] + a[i] + a[i + sxy]) * (1.0 / 3.0)
	return bb

## 三线性采样（坐标为体素中心坐标，越界时夹到边上）
static func _sample(f: PackedFloat32Array, dims: Vector3i, p: Vector3) -> float:
	var x0 := clampi(floori(p.x), 0, dims.x - 2)
	var y0 := clampi(floori(p.y), 0, dims.y - 2)
	var z0 := clampi(floori(p.z), 0, dims.z - 2)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var fz := clampf(p.z - z0, 0.0, 1.0)
	var sx := dims.x
	var sxy := dims.x * dims.y
	var i := x0 + sx * y0 + sxy * z0
	var c00 := lerpf(f[i], f[i + 1], fx)
	var c10 := lerpf(f[i + sx], f[i + sx + 1], fx)
	var c01 := lerpf(f[i + sxy], f[i + sxy + 1], fx)
	var c11 := lerpf(f[i + sxy + sx], f[i + sxy + sx + 1], fx)
	return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)

## 格 c（角为体素 c .. c+1）的顶点；格里没有表面时返回 -1
static func _vertex(c: Vector3i, dims: Vector3i, dens: PackedFloat32Array, b: PackedFloat32Array,
		cell_v: PackedInt32Array, vp: PackedVector3Array, vn: PackedVector3Array, va: PackedFloat32Array,
		types: PackedByteArray, lin: PackedColorArray, vc: PackedColorArray) -> int:
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= dims.x - 1 or c.y >= dims.y - 1 or c.z >= dims.z - 1:
		return -1
	var sx := dims.x
	var sxy := dims.x * dims.y
	var ci := c.x + sx * c.y + sxy * c.z
	var have := cell_v[ci]
	if have >= 0:
		return have
	var cd := PackedFloat32Array()
	var cb := PackedFloat32Array()
	cd.resize(8)
	cb.resize(8)
	var mask := 0
	var csum := Color(0, 0, 0, 0)
	var cw := 0.0
	for k in 8:
		var idx := ci + (k & 1) + sx * ((k >> 1) & 1) + sxy * ((k >> 2) & 1)
		cd[k] = dens[idx]
		cb[k] = b[idx]
		if cd[k] >= 0.5:
			mask |= 1 << k
			var tt: int = types[idx]
			if blend_table[tt] == 1:
				var lc: Color = lin[tt]
				csum += Color(lc.r, lc.g, lc.b, 0.0)
				cw += 1.0
	if mask == 0 or mask == 255:
		return -1
	var sum := Vector3.ZERO
	var cnt := 0
	for e: Array in EDGES:
		var k0: int = e[0]
		var k1: int = e[1]
		var s0 := (mask >> k0) & 1
		var s1 := (mask >> k1) & 1
		if s0 == s1:
			continue
		var b0 := cb[k0]
		var b1 := cb[k1]
		var t := 0.5
		if (b0 - 0.5) * (b1 - 0.5) < 0.0:
			t = clampf((0.5 - b0) / (b1 - b0), 0.12, 0.88)
		var p0 := Vector3(k0 & 1, (k0 >> 1) & 1, (k0 >> 2) & 1)
		var p1 := Vector3(k1 & 1, (k1 >> 1) & 1, (k1 >> 2) & 1)
		sum += p0.lerp(p1, t)
		cnt += 1
	var pos := sum / float(cnt)
	# 模糊场的梯度 → 平滑法线
	var g := _grad(cb, pos)
	if g.length_squared() < 1e-6:
		g = _grad(cd, pos)
	var nrm := (-g).normalized() if g.length_squared() > 1e-8 else Vector3.UP
	var lp := Vector3(c) + pos
	# 遮蔽：沿法线往外 0.9 格采样模糊密度，缝里、坑底更暗
	var occ := _sample(b, dims, lp + nrm * 0.9)
	var ao := clampf(1.0 - (occ - 0.2) * 1.5, 0.42, 1.0)
	var id := vp.size()
	vp.append(lp)
	vn.append(nrm)
	va.append(ao)
	vc.append(Color(csum.r / cw, csum.g / cw, csum.b / cw, 1.0) if cw > 0.0 else Color(0, 0, 0, -1.0))
	cell_v[ci] = id
	return id

static func _grad(f: PackedFloat32Array, p: Vector3) -> Vector3:
	var fx := p.x
	var fy := p.y
	var fz := p.z
	# 角 k 的值 f[k]，k = x + 2y + 4z
	var gx := lerpf(lerpf(f[1] - f[0], f[3] - f[2], fy), lerpf(f[5] - f[4], f[7] - f[6], fy), fz)
	var gy := lerpf(lerpf(f[2] - f[0], f[3] - f[1], fx), lerpf(f[6] - f[4], f[7] - f[5], fx), fz)
	var gz := lerpf(lerpf(f[4] - f[0], f[5] - f[1], fx), lerpf(f[6] - f[2], f[7] - f[3], fx), fy)
	return Vector3(gx, gy, gz)
