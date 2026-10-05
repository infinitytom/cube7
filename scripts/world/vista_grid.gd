class_name VistaGrid
extends RefCounted
## 远景用的“大体素”网格：和玩法世界同一套方块颜色和着色器（圆角、AO、岩层），只是体素更大、没有碰撞。
## 在后台线程里搭建 + 生成网格数组，主线程只负责把数组变成 ArrayMesh。

var dims := Vector3i.ONE
var data := PackedByteArray()
var vsize := 1.0            ## 一个体素多少米

func _init(d: Vector3i, voxel_size: float) -> void:
	dims = d
	vsize = voxel_size
	data.resize(d.x * d.y * d.z)
	data.fill(0)

func inside(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < dims.x and y < dims.y and z < dims.z

func g(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= dims.x or y >= dims.y or z >= dims.z:
		return 0
	return data[x + dims.x * (y + dims.y * z)]

func s(x: int, y: int, z: int, t: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= dims.x or y >= dims.y or z >= dims.z:
		return
	data[x + dims.x * (y + dims.y * z)] = t

## 只在空气处写入
func put(x: int, y: int, z: int, t: int) -> void:
	if inside(x, y, z) and data[x + dims.x * (y + dims.y * z)] == 0:
		data[x + dims.x * (y + dims.y * z)] = t

func column(x: int, z: int, y0: int, y1: int, t: int) -> void:
	if x < 0 or z < 0 or x >= dims.x or z >= dims.z:
		return
	for y in range(maxi(y0, 0), mini(y1, dims.y - 1) + 1):
		data[x + dims.x * (y + dims.y * z)] = t

func box(a: Vector3i, b: Vector3i, t: int) -> void:
	for z in range(maxi(mini(a.z, b.z), 0), mini(maxi(a.z, b.z), dims.z - 1) + 1):
		for y in range(maxi(mini(a.y, b.y), 0), mini(maxi(a.y, b.y), dims.y - 1) + 1):
			for x in range(maxi(mini(a.x, b.x), 0), mini(maxi(a.x, b.x), dims.x - 1) + 1):
				data[x + dims.x * (y + dims.y * z)] = t

func sphere(c: Vector3, r: float, t: int, only_air := false, squash := Vector3.ONE) -> void:
	var ir := int(ceil(r * maxf(squash.x, maxf(squash.y, squash.z)))) + 1
	for z in range(int(c.z) - ir, int(c.z) + ir + 1):
		for y in range(int(c.y) - ir, int(c.y) + ir + 1):
			for x in range(int(c.x) - ir, int(c.x) + ir + 1):
				if not inside(x, y, z):
					continue
				var q := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) - c) / squash
				if q.length() <= r:
					if only_air:
						put(x, y, z, t)
					else:
						s(x, y, z, t)

# ---------------------------------------------------------------- 网格

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const TANG: Array = [
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1)], [Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1)], [Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0)], [Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
]
const SHADE: Array[float] = [0.80, 0.80, 1.0, 0.55, 0.88, 0.88]
const AO: Array[float] = [1.0, 0.78, 0.62, 0.48]

## 生成网格数组：返回 {render 类型: [v, n, c, uv, uv2, idx]}（在线程里调用）
## skip_bottom：不生成朝下的面（远处的岛底看不到）
func build_arrays(skip_bottom := false) -> Dictionary:
	var out := {}
	var sx := dims.x
	var sxy := dims.x * dims.y
	var doff: Array[int] = [1, -1, sx, -sx, sxy, -sxy]
	var uoff: Array[int] = []
	var voff: Array[int] = []
	var ccw: Array[bool] = []
	for f in 6:
		var u: Vector3i = TANG[f][0]
		var v: Vector3i = TANG[f][1]
		uoff.append(u.x + u.y * sx + u.z * sxy)
		voff.append(v.x + v.y * sx + v.z * sxy)
		ccw.append(Vector3(u).cross(Vector3(v)).dot(Vector3(DIRS[f])) > 0.0)
	var occ := PackedByteArray()
	occ.resize(256)
	var lin := PackedColorArray()
	lin.resize(256)
	var rnd := PackedByteArray()
	rnd.resize(256)
	var cat := PackedByteArray()
	cat.resize(256)
	for t in Blocks.COUNT:
		var r: int = Blocks.render[t]
		occ[t] = 1 if r == Blocks.Render.OPAQUE or r == Blocks.Render.GLOW else 0
		lin[t] = Blocks.colors[t].srgb_to_linear()
		rnd[t] = r
		cat[t] = 0
		if Blocks.impact[t] >= 0.0:
			cat[t] = 1
		elif Blocks.soft[t] == 1:
			cat[t] = 3
		elif Blocks.drill[t] == 1:
			cat[t] = 2
	const CS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	const CUV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var sets := {}
	var V := vsize
	var v1 := PackedVector3Array(); var n1 := PackedVector3Array(); var c1 := PackedColorArray(); var t1 := PackedVector2Array(); var w1 := PackedVector2Array(); var i1 := PackedInt32Array()
	var v2 := PackedVector3Array(); var n2 := PackedVector3Array(); var c2 := PackedColorArray(); var t2 := PackedVector2Array(); var w2 := PackedVector2Array(); var i2 := PackedInt32Array()
	var v3 := PackedVector3Array(); var n3 := PackedVector3Array(); var c3 := PackedColorArray(); var t3 := PackedVector2Array(); var w3 := PackedVector2Array(); var i3 := PackedInt32Array()
	var has_smooth := false
	# 内部三层循环用平铺下标；边界体素单独判断越界
	for z in dims.z:
		for y in dims.y:
			var row := sx * y + sxy * z
			for x in sx:
				var i := row + x
				var t: int = data[i]
				if t == 0:
					continue
				if Blocks.smooth[t] == 1:
					has_smooth = true
					continue
				var border := x == 0 or y == 0 or z == 0 or x == sx - 1 or y == dims.y - 1 or z == dims.z - 1
				var r: int = rnd[t]
				var base: Color = lin[t]
				var hsh := ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 255
				var vary := 0.96 + (hsh / 255.0) * 0.08
				var ct: int = cat[t]
				for f in 6:
					if skip_bottom and f == 3:
						continue
					var nt := 0
					if border:
						var n0: Vector3i = DIRS[f]
						nt = g(x + n0.x, y + n0.y, z + n0.z)
					else:
						nt = data[i + doff[f]]
					if occ[nt] == 1 or (nt == t):
						continue
					var n := DIRS[f]
					var u: Vector3i = TANG[f][0]
					var v: Vector3i = TANG[f][1]
					var center := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5) * V
					var mask := 0
					var ao: Array[float] = [1.0, 1.0, 1.0, 1.0]
					if border:
						mask = 15
					else:
						var eo: Array[int] = [-uoff[f], uoff[f], -voff[f], voff[f]]
						for e in 4:
							var nb: int = data[i + eo[e]]
							var cont := nb != 0 and occ[data[i + eo[e] + doff[f]]] == 0 and (occ[nb] == 1 or nb == t)
							if ct == 1 and nb != t:
								cont = false
							if not cont:
								mask |= 1 << e
						var ni := i + doff[f]
						for k in 4:
							var cs: Vector2i = CS[k]
							var a1 := ni + uoff[f] * cs.x
							var a2 := ni + voff[f] * cs.y
							var a3 := ni + uoff[f] * cs.x + voff[f] * cs.y
							if a1 < 0 or a2 < 0 or a3 < 0 or a1 >= data.size() or a2 >= data.size() or a3 >= data.size():
								continue
							var o1: int = occ[data[a1]]
							var o2: int = occ[data[a2]]
							var oc: int = occ[data[a3]]
							ao[k] = AO[3 if (o1 == 1 and o2 == 1) else o1 + o2 + oc]
					var shade := SHADE[f] * vary
					var tuv2 := Vector2(t / 255.0, (mask + ct * 16) / 255.0)
					var nf := Vector3(n)
					var flip := ao[0] + ao[2] < ao[1] + ao[3]
					var idx: Array
					if ccw[f]:
						idx = [0, 2, 1, 0, 3, 2] if not flip else [0, 3, 1, 1, 3, 2]
					else:
						idx = [0, 1, 2, 0, 2, 3] if not flip else [0, 1, 3, 1, 2, 3]
					if r == Blocks.Render.GLOW:
						var b3 := v3.size()
						for k in 4:
							var cs3: Vector2i = CS[k]
							v3.append(center + (Vector3(u) * cs3.x + Vector3(v) * cs3.y) * (0.5 * V))
							n3.append(nf)
							c3.append(Color(base.r, base.g, base.b, ao[k] * shade))
							t3.append(CUV[k])
							w3.append(tuv2)
						for k in idx:
							i3.append(b3 + k)
					elif r == Blocks.Render.GLASS:
						var b2 := v2.size()
						for k in 4:
							var cs2b: Vector2i = CS[k]
							v2.append(center + (Vector3(u) * cs2b.x + Vector3(v) * cs2b.y) * (0.5 * V))
							n2.append(nf)
							c2.append(Color(base.r, base.g, base.b, ao[k] * shade))
							t2.append(CUV[k])
							w2.append(tuv2)
						for k in idx:
							i2.append(b2 + k)
					else:
						var b1 := v1.size()
						for k in 4:
							var cs1: Vector2i = CS[k]
							v1.append(center + (Vector3(u) * cs1.x + Vector3(v) * cs1.y) * (0.5 * V))
							n1.append(nf)
							c1.append(Color(base.r, base.g, base.b, ao[k] * shade))
							t1.append(CUV[k])
							w1.append(tuv2)
						for k in idx:
							i1.append(b1 + k)
	if not v1.is_empty():
		sets[Blocks.Render.OPAQUE] = [v1, n1, c1, t1, w1, i1]
	if not v2.is_empty():
		sets[Blocks.Render.GLASS] = [v2, n2, c2, t2, w2, i2]
	if not v3.is_empty():
		sets[Blocks.Render.GLOW] = [v3, n3, c3, t3, w3, i3]
	if has_smooth:
		var sm := _smooth_arrays(occ, lin, cat)
		if not sm.is_empty():
			sm["vsize"] = vsize
			sets[VoxelWorld.SMOOTH_SET] = sm
	return sets

## 自然材质的平滑曲面（和玩法世界同一套：Voxel Tools / Surface Nets），远景的岛不再是一摞方块
func _smooth_arrays(_occ: PackedByteArray, _lin: PackedColorArray, _cat: PackedByteArray) -> Dictionary:
	return TerrainMesher.build_grid(data, dims)

static var _mats := {}

static func material(render: int) -> Material:
	if _mats.has(render):
		return _mats[render]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/voxel_glow.gdshader" if render == Blocks.Render.GLOW else ("res://shaders/voxel_glass.gdshader" if render == Blocks.Render.GLASS else "res://shaders/voxel_opaque.gdshader"))
	_mats[render] = m
	return m

## 主线程：数组 → ArrayMesh
static func arrays_to_mesh(sets: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for r in sets.keys():
		if r == VoxelWorld.SMOOTH_SET:
			# 体素中心坐标 → 本地坐标：下标 (0,0,0) 的中心在 (0.5, 0.5, 0.5) × vsize
			TerrainMesher.grid_surface(mesh, sets[r], sets[r].get("vsize", 1.0), Vector3.ONE * 0.5 * float(sets[r].get("vsize", 1.0)))
			continue
		var st: Array = sets[r]
		if (st[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = st[0]
		arr[Mesh.ARRAY_NORMAL] = st[1]
		arr[Mesh.ARRAY_COLOR] = st[2]
		arr[Mesh.ARRAY_TEX_UV] = st[3]
		arr[Mesh.ARRAY_TEX_UV2] = st[4]
		if not (st[5] as PackedInt32Array).is_empty():
			arr[Mesh.ARRAY_INDEX] = st[5]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(r))
	return mesh
