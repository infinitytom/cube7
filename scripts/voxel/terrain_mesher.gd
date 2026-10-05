class_name TerrainMesher
extends RefCounted
## 平滑地形网格：优先用 Voxel Tools 的 Transvoxel（C++，带 4 层材质混合）；
## 用标准版 Godot 打开时（没有 Voxel Tools 模块）自动退回 GDScript 的 Surface Nets（SmoothMesher）。
##
## 输入是一块按“体素中心格点”采样的区域：
##   lattice_origin：格点 0 对应的体素坐标；n：格点数（每轴，网格覆盖 n-1 个间隔）
## 采样函数 sample(p: Vector3i) -> [填充度 0..1, 方块类型] 由调用方提供（读体素数据）。
## 输出（体素中心坐标系，乘以体素边长、加上偏移就是世界坐标）：
##   {"verts", "normals", "custom1", "indices"(可能为空 = 不带索引), "colors"(可能为空)}

const BLUR_RAW := 0.55       ## SDF = 0.5 - (BLUR_RAW × 原始填充 + (1-BLUR_RAW) × 3×3×3 模糊)：既圆润又不吃掉一格厚的细节

static var _has_vt := -1
static var _mesher: Object

## Voxel Tools 的枚举值（不同版本可能不同，运行时查）
static var C_SDF := 1
static var C_INDICES := 3
static var D8 := 0
static var D32 := 2
static var TEX_SINGLE := 2

static func available() -> bool:
	if _has_vt < 0:
		_has_vt = 1 if ClassDB.class_exists("VoxelMesherTransvoxel") and ClassDB.class_exists("VoxelBuffer") \
			and ClassDB.class_has_integer_constant("VoxelMesherTransvoxel", "TEXTURES_SINGLE_S4") \
			and ClassDB.class_has_method("VoxelBuffer", "set_channel_from_byte_array") \
			and ClassDB.class_has_method("VoxelBuffer", "op_add_buffer_f") else 0
		if _has_vt == 1:
			C_SDF = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
			C_INDICES = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_INDICES")
			D8 = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_8_BIT")
			D32 = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_32_BIT")
			TEX_SINGLE = ClassDB.class_get_integer_constant("VoxelMesherTransvoxel", "TEXTURES_SINGLE_S4")
		if _has_vt == 1:
			print("[Terrain] 使用 Voxel Tools Transvoxel 生成平滑地形")
		else:
			print("[Terrain] 没有 Voxel Tools 模块，使用 GDScript Surface Nets")
	return _has_vt == 1

## 用 Voxel Tools 生成。
## dens / slots：原始数据（ZXY 顺序：y 最快，其次 x，最后 z），尺寸 = (n+3) + 2（Transvoxel 边框 1/2 + 模糊边框 1）
## n：网格要覆盖的格点数（每轴）
static func build_vt(dens: PackedFloat32Array, slots: PackedByteArray, n: Vector3i) -> Dictionary:
	if _mesher == null:
		_mesher = ClassDB.instantiate("VoxelMesherTransvoxel")
		_mesher.set("texturing_mode", TEX_SINGLE)   # 每个体素一个材质，网格自动混合
		_mesher.set("textures_ignore_air_voxels", true)
	var bs := n + Vector3i(2, 2, 2)                  # Transvoxel 需要前 1 后 2 的边框（n 个格点 + 3 = n-1 个间隔 + 边框）
	var rs := bs + Vector3i(2, 2, 2)                 # 再加一圈给模糊
	var raw: Object = ClassDB.instantiate("VoxelBuffer")
	raw.call("create", rs.x, rs.y, rs.z)
	raw.call("set_channel_depth", C_SDF, D32)
	raw.call("decompress_channel", C_SDF)
	raw.call("set_channel_from_byte_array", C_SDF, dens.to_byte_array())
	# 3×3×3 盒式模糊（可分离，全部在 C++ 里做）
	var acc: Object = raw
	for axis in 3:
		var e := Vector3i.ZERO
		e[axis] = 1
		var sum: Object = _clone(acc, rs)
		var a: Object = _clone(acc, rs)
		a.call("copy_channel_from_area", acc, e, rs, Vector3i.ZERO, C_SDF)
		sum.call("op_add_buffer_f", a, C_SDF)
		var b2: Object = _clone(acc, rs)
		b2.call("copy_channel_from_area", acc, Vector3i.ZERO, rs - e, e, C_SDF)
		sum.call("op_add_buffer_f", b2, C_SDF)
		acc = sum
	# sdf = 0.5 - k·raw - (1-k)/27·blur
	var sdf: Object = _clone(raw, rs)
	sdf.call("op_mul_value_f", -BLUR_RAW, C_SDF)
	acc.call("op_mul_value_f", -(1.0 - BLUR_RAW) / 27.0, C_SDF)
	sdf.call("op_add_buffer_f", acc, C_SDF)
	var half: Object = ClassDB.instantiate("VoxelBuffer")
	half.call("create", rs.x, rs.y, rs.z)
	half.call("set_channel_depth", C_SDF, D32)
	half.call("fill_f", 0.5, C_SDF)
	sdf.call("op_add_buffer_f", half, C_SDF)
	# 裁掉模糊边框 → Transvoxel 的输入
	var buf: Object = ClassDB.instantiate("VoxelBuffer")
	buf.call("create", bs.x, bs.y, bs.z)
	buf.call("set_channel_depth", C_SDF, D32)
	buf.call("decompress_channel", C_SDF)
	buf.call("copy_channel_from_area", sdf, Vector3i.ONE, Vector3i.ONE + bs, Vector3i.ZERO, C_SDF)
	buf.call("set_channel_depth", C_INDICES, D8)
	buf.call("set_channel_from_byte_array", C_INDICES, slots)
	var mesh: Mesh = _mesher.call("build_mesh", buf, [], {})
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var arr := mesh.surface_get_arrays(0)
	var c1 = arr[Mesh.ARRAY_CUSTOM1]
	if c1 == null:
		# 这个版本的 Voxel Tools 没输出材质信息：以后都改用 GDScript 网格
		push_warning("[Terrain] Voxel Tools 网格没有材质数据，改用 GDScript Surface Nets")
		_has_vt = 0
		return {"fallback": true}
	# Transvoxel 的坐标：缓冲区下标 - 1 → 格点 0 在原点
	return {"verts": arr[Mesh.ARRAY_VERTEX], "normals": arr[Mesh.ARRAY_NORMAL], "custom1": c1,
		"indices": arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(), "colors": PackedColorArray()}

static func _clone(src: Object, size: Vector3i) -> Object:
	var b: Object = ClassDB.instantiate("VoxelBuffer")
	b.call("create", size.x, size.y, size.z)
	b.call("set_channel_depth", C_SDF, D32)
	b.call("copy_channel_from", src, C_SDF)
	return b

## 把结果变成 ArrayMesh 的一个面（xf：体素中心坐标 → 本地坐标）
static func add_surface(mesh: ArrayMesh, r: Dictionary, xf: Transform3D, mat: Material) -> void:
	var verts: PackedVector3Array = r["verts"]
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = xf * verts
	arr[Mesh.ARRAY_NORMAL] = r["normals"]
	arr[Mesh.ARRAY_CUSTOM1] = r["custom1"]
	var cols: PackedColorArray = r.get("colors", PackedColorArray())
	if not cols.is_empty():
		arr[Mesh.ARRAY_COLOR] = cols
	var idx: PackedInt32Array = r.get("indices", PackedInt32Array())
	if not idx.is_empty():
		arr[Mesh.ARRAY_INDEX] = idx
	var flags := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

## 碰撞三角形（世界 / 本地坐标，按三角形展开）
static func faces(r: Dictionary, xf: Transform3D) -> PackedVector3Array:
	var verts: PackedVector3Array = xf * (r["verts"] as PackedVector3Array)
	var idx: PackedInt32Array = r.get("indices", PackedInt32Array())
	if idx.is_empty():
		return verts
	var out := PackedVector3Array()
	out.resize(idx.size())
	for i in idx.size():
		out[i] = verts[idx[i]]
	return out

## 整块小网格（碎块、远景岛）：types 是 XYZ 顺序（x 最快）、尺寸 dims 的方块类型数组。
## 四周自动补一圈空气，表面会闭合。结果坐标里 types 的下标 (0,0,0) 在体素中心坐标 (0,0,0)。
static func build_grid(types: PackedByteArray, dims: Vector3i) -> Dictionary:
	var n := dims + Vector3i(2, 2, 2)          # 格点从 -1 到 dims
	var smooth := Blocks.smooth
	if available():
		var bs := n + Vector3i(2, 2, 2)
		var rs := bs + Vector3i(2, 2, 2)
		var ro := Vector3i(-3, -3, -3)           # 格点 -1，再往前：Transvoxel 前边框 1 + 模糊 1
		var dens := PackedFloat32Array()
		dens.resize(rs.x * rs.y * rs.z)
		var slots := PackedByteArray()
		slots.resize(bs.x * bs.y * bs.z)
		var tab := TerrainPalette.table()
		var any := false
		var i := 0
		for z in rs.z:
			var gz := ro.z + z
			for x in rs.x:
				var gx := ro.x + x
				var ok := gz >= 0 and gz < dims.z and gx >= 0 and gx < dims.x
				for y in rs.y:
					var gy := ro.y + y
					if ok and gy >= 0 and gy < dims.y:
						var t: int = types[gx + dims.x * (gy + dims.y * gz)]
						if t != 0 and smooth[t] == 1:
							dens[i] = 1.0
							any = true
							var bx := x - 1
							var by := y - 1
							var bz := z - 1
							if bx >= 0 and by >= 0 and bz >= 0 and bx < bs.x and by < bs.y and bz < bs.z:
								slots[by + bs.y * (bx + bs.x * bz)] = tab[t]
					i += 1
		if not any:
			return {}
		var r := build_vt(dens, slots, n)
		if r.has("fallback"):
			return build_grid(types, dims)
		if not r.is_empty():
			r["offset"] = Vector3(-1, -1, -1)
		return r
	# GDScript Surface Nets
	var pad := SmoothMesher.PAD
	var sd := n + Vector3i(pad * 2, pad * 2, pad * 2)
	var st := PackedByteArray()
	st.resize(sd.x * sd.y * sd.z)
	var sdn := PackedFloat32Array()
	sdn.resize(st.size())
	var any2 := false
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var t: int = types[x + dims.x * (y + dims.y * z)]
				if t != 0 and smooth[t] == 1:
					var j := (x + 1 + pad) + sd.x * ((y + 1 + pad) + sd.y * (z + 1 + pad))
					st[j] = t
					sdn[j] = 1.0
					any2 = true
	if not any2:
		return {}
	var r2 := SmoothMesher.build_dict(st, sdn, sd, n)
	if (r2["verts"] as PackedVector3Array).is_empty():
		return {}
	r2["offset"] = Vector3(-1, -1, -1)
	return r2

## build_grid 结果 → 一个面；voxel：体素边长；origin：下标 (0,0,0) 的体素中心在本地坐标里的位置
static func grid_surface(mesh: ArrayMesh, r: Dictionary, voxel: float, origin: Vector3, mat: Material = null) -> void:
	var off: Vector3 = r.get("offset", Vector3.ZERO)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * voxel), origin + off * voxel)
	add_surface(mesh, r, xf, mat if mat else TerrainPalette.material())
