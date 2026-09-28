class_name VistaBuilder
extends RefCounted
## 远景搭建：浮岛、山峰、石柱、方舟星核塔、重构塔、工业建筑……全部生成 VistaGrid（在线程里跑）。
## 每个函数返回 {"grid": VistaGrid, "falls": [[本地位置 Vector3(米), 朝外方向 Vector3], ...], "anchor": Vector3(米)}
## anchor = 岛顶面中心相对网格原点的位置，放置时用它对齐。

static func build(kind: String, p: Dictionary) -> Dictionary:
	match kind:
		"island": return island(p)
		"pillar": return pillar(p)
		"ark_spire": return ark_spire(p)
		"recon_tower": return recon_tower(p)
		"factory_island": return factory_island(p)
		"gear": return gear(p)
		"truss": return truss(p)
		"shard": return shard(p)
		"city_island": return city_island(p)
		"wreck": return wreck(p)
	push_error("VistaBuilder: unknown kind " + kind)
	return island(p)

static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n

## 浮岛。p 里的参数（单位：体素）：
##   r 半径、top 地面厚度、under 岛底深度、hill 丘陵起伏、peak 山峰高度、peak_r 山峰半径（0..1，占半径比例）
##   trees 树的密度、kinds 树种、crystals 岛底水晶、ruins 废墟柱子、falls 瀑布数量、seed
static func island(p: Dictionary) -> Dictionary:
	var R: float = p.get("r", 20.0)
	var top: int = p.get("top", 6)
	var under: int = p.get("under", 24)
	var hill: float = p.get("hill", 3.0)
	var peak: float = p.get("peak", 0.0)
	var peak_r: float = p.get("peak_r", 0.5)
	var peak_off: Vector2 = p.get("peak_off", Vector2.ZERO)
	var tree_rate: float = p.get("trees", 0.02)
	var kinds: Array = p.get("kinds", ["round", "pine", "round", "blossom"])
	var seed_v: int = p.get("seed", 1)
	var vs: float = p.get("voxel", 1.0)
	var grass: int = p.get("grass", Blocks.GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n_shape := _noise(seed_v, 1.6)
	var n_h := _noise(seed_v + 1, 0.06)
	var n_d := _noise(seed_v + 2, 0.12)
	var n_s := _noise(seed_v + 3, 0.08)
	var pad := 4
	var W := int(R * 2.0 * 1.35) + pad * 2
	var H := under + top + int(hill) + int(peak) + 18
	var gr := VistaGrid.new(Vector3i(W, H, W), vs)
	var c := Vector2(W * 0.5, W * 0.5)
	var heights := {}
	for z in W:
		for x in W:
			var dv := Vector2(x + 0.5, z + 0.5) - c
			var ang := atan2(dv.y, dv.x)
			var rr := R * (0.82 + 0.3 * n_shape.get_noise_2d(cos(ang), sin(ang)) + 0.08 * n_shape.get_noise_2d(cos(ang) * 3.0, sin(ang) * 3.0))
			var d := dv.length() / rr
			if d > 1.0:
				continue
			var surf := under + top + int(hill * (0.5 + 0.5 * n_h.get_noise_2d(x, z)) * (1.0 - d * d))
			if peak > 0.0:
				var pd := (dv - peak_off * R).length() / (R * peak_r)
				if pd < 1.0:
					surf += int(peak * pow(1.0 - pd, 1.5) * (0.85 + 0.3 * n_h.get_noise_2d(x * 2.0, z * 2.0)))
			surf -= int(2.0 * smoothstep(0.85, 1.0, d))
			var depth := under * pow(maxf(1.0 - d, 0.0), 0.75) * (0.65 + 0.45 * (0.5 + 0.5 * n_d.get_noise_2d(x, z)))
			if rng.randf() < 0.04 and d < 0.8:
				depth += rng.randf_range(3.0, 9.0)        # 倒垂的石笋
			var bottom := maxi(0, under - int(depth) - 1)
			heights[Vector2i(x, z)] = surf
			for y in range(bottom, surf + 1):
				var t := Blocks.CLIFF
				var band := int(floor((y + n_s.get_noise_2d(x, z) * 3.0) / 4.0)) % 3
				t = [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C][band]
				if y < under - 6:
					t = Blocks.CLIFF_C if (y + x / 5 + z / 7) % 5 != 0 else Blocks.ROCK
				if y >= surf - 2:
					t = Blocks.DIRT
				gr.s(x, y, z, t)
	# 地表：陡的地方露岩，平缓处长草
	for key in heights:
		var x: int = key.x
		var z: int = key.y
		var h: int = heights[key]
		var lo := h
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			lo = mini(lo, heights.get(key + dd, -99))
		if h - lo >= 3 and lo > -99:
			gr.s(x, h, z, Blocks.CLIFF_B if (x + z) % 3 else Blocks.ROCK)
			gr.s(x, h - 1, z, Blocks.CLIFF)
		else:
			gr.s(x, h, z, grass)
			# 崖边垂下来的草皮
			if lo == -99:
				gr.s(x, h - 1, z, grass)
	# 岛底的水晶簇
	if p.get("crystals", false):
		for k in int(R * 0.6):
			var a := rng.randf() * TAU
			var dist := rng.randf_range(0.1, 0.6) * R
			var x := int(c.x + cos(a) * dist)
			var z := int(c.y + sin(a) * dist)
			var y := 0
			while y < H and gr.g(x, y, z) == 0:
				y += 1
			if y < H - 1 and y > 1:
				for s in rng.randi_range(2, 5):
					gr.put(x, y - 1 - s, z, Blocks.CRYSTAL)
				gr.put(x + 1, y - 1, z, Blocks.CRYSTAL)
				gr.put(x, y - 1, z + 1, Blocks.CRYSTAL)
	# 树
	var falls: Array = []
	var keys := heights.keys()
	keys.shuffle()
	for key in keys:
		var h: int = heights[key]
		if gr.g(key.x, h, key.y) != grass or gr.g(key.x, h + 1, key.y) != 0:
			continue
		var dv2 := Vector2(key.x + 0.5, key.y + 0.5) - c
		if rng.randf() < tree_rate * (1.3 - dv2.length() / R * 0.5):
			tree(gr, Vector3i(key.x, h + 1, key.y), rng, kinds[rng.randi() % kinds.size()], p.get("tree_scale", 1.0))
	# 废墟：几根断掉的石柱和一圈矮墙
	if p.get("ruins", false):
		for k in 6:
			var a := k * TAU / 6.0 + 0.3
			var x := int(c.x + cos(a) * R * 0.35)
			var z := int(c.y + sin(a) * R * 0.35)
			var h: int = heights.get(Vector2i(x, z), -1)
			if h < 0:
				continue
			var ph := rng.randi_range(3, 9)
			gr.box(Vector3i(x, h + 1, z), Vector3i(x + 1, h + ph, z + 1), Blocks.PAVING)
			if rng.randf() < 0.5:
				gr.box(Vector3i(x - 1, h + ph + 1, z - 1), Vector3i(x + 2, h + ph + 1, z + 2), Blocks.MOSS)
	# 瀑布：从崖边的草地流下去
	var nf: int = p.get("falls", 0)
	var tries := 0
	while falls.size() < nf and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var best := Vector2i(-1, -1)
		for step in range(int(R * 1.3), 0, -1):
			var q := Vector2i((c + dir * step).floor())
			if heights.has(q):
				best = q
				break
		if best.x < 0:
			continue
		var h: int = heights[best]
		if h > under + top + int(hill) + 1:
			continue
		var ok := true
		for f in falls:
			if (f[0] as Vector3).distance_to(Vector3(best.x, h, best.y) * vs) < R * vs * 0.8:
				ok = false
		if ok:
			# 瀑布口：把崖边挖出一个小槽
			gr.s(best.x, h, best.y, Blocks.CLIFF)
			falls.append([Vector3(best.x + 0.5, h + 0.9, best.y + 0.5) * vs, Vector3(dir.x, 0, dir.y)])
	return {"grid": gr, "falls": falls, "anchor": Vector3(c.x, under + top + 1, c.y) * vs, "heights": heights}

## 大体素树：树干一列，树冠几个球
static func tree(gr: VistaGrid, base: Vector3i, rng: RandomNumberGenerator, kind: String, sc := 1.0) -> void:
	var th := int(rng.randi_range(4, 7) * sc)
	for y in th:
		gr.put(base.x, base.y + y, base.z, Blocks.WOOD)
	var leaf := Blocks.LEAVES
	if kind == "pine":
		leaf = Blocks.PINE
		var tiers := int(rng.randi_range(3, 4) * sc)
		for k in tiers:
			var rad := (tiers - k) * 0.9 * sc + 0.6
			var yy := base.y + th - 2 + k * 2
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if Vector2(dx, dz).length() <= rad:
						gr.put(base.x + dx, yy, base.z + dz, leaf)
						if Vector2(dx, dz).length() <= rad - 1.0:
							gr.put(base.x + dx, yy + 1, base.z + dz, leaf)
		gr.put(base.x, base.y + th + tiers * 2 - 1, base.z, leaf)
		return
	if kind == "blossom":
		leaf = Blocks.BLOSSOM
	var r := rng.randf_range(1.8, 2.8) * sc
	var cc := Vector3(base.x + 0.5, base.y + th + 0.5, base.z + 0.5)
	gr.sphere(cc, r, leaf, true, Vector3(1.0, 0.8, 1.0))
	for k in 2:
		var a := rng.randf() * TAU
		gr.sphere(cc + Vector3(cos(a) * r * 0.6, rng.randf_range(-0.5, 0.8), sin(a) * r * 0.6), r * 0.7, leaf, true)

## 从云海里拔起来的石柱（顶上有草和树）
static func pillar(p: Dictionary) -> Dictionary:
	var R: float = p.get("r", 5.0)
	var Hh: int = p.get("h", 60)
	var seed_v: int = p.get("seed", 3)
	var vs: float = p.get("voxel", 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := _noise(seed_v, 0.15)
	var W := int(R * 2.6) + 6
	var gr := VistaGrid.new(Vector3i(W, Hh + 14, W), vs)
	var c := Vector2(W * 0.5, W * 0.5)
	for y in Hh:
		var f := float(y) / Hh
		var rad := R * (1.15 - 0.35 * f) * (1.0 + 0.25 * sin(f * 9.0 + seed_v)) + (R * 0.3 if y > Hh - 4 else 0.0)
		for z in W:
			for x in W:
				var dv := Vector2(x + 0.5, z + 0.5) - c
				if dv.length() <= rad + n.get_noise_3d(x, y * 0.5, z) * 1.6:
					var band := int(floor((y + n.get_noise_2d(x, z) * 2.0) / 3.0)) % 3
					if p.get("rust", false):
						gr.s(x, y, z, [Blocks.RUSTROCK, Blocks.RUST, Blocks.RUSTROCK][band])
					else:
						gr.s(x, y, z, [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C][band])
	# 顶面草皮
	for z in W:
		for x in W:
			for y in range(Hh + 2, 0, -1):
				if gr.g(x, y, z) != 0:
					gr.s(x, y, z, Blocks.RUSTDUNE if p.get("rust", false) else Blocks.GRASS)
					if gr.g(x, y - 1, z) != 0 and not p.get("rust", false):
						gr.s(x, y - 1, z, Blocks.DIRT)
					break
	var ty := Hh
	while ty > 0 and gr.g(int(c.x), ty, int(c.y)) == 0:
		ty -= 1
	if p.get("tree", true):
		tree(gr, Vector3i(int(c.x), ty + 1, int(c.y)), rng, "pine" if rng.randf() < 0.5 else "round")
	return {"grid": gr, "falls": [], "anchor": Vector3(c.x, 0, c.y) * vs}

## 方舟星核塔：整颗星球的心脏。极高的锥形塔身、发光的能量纹路、几圈悬浮的环、塔顶的核心水晶。
## lit：是否已经点亮（最后一章）——没点亮时能量纹路是暗的，只有一点点微光
static func ark_spire(p: Dictionary) -> Dictionary:
	var R: float = p.get("r", 9.0)
	var Hh: int = p.get("h", 150)
	var vs: float = p.get("voxel", 2.0)
	var W := int(R * 4.2) + 8
	var gr := VistaGrid.new(Vector3i(W, Hh + 30, W), vs)
	var c := Vector2(W * 0.5, W * 0.5)
	var line_t: int = p.get("line", Blocks.CRYSTAL)
	# 底座：宽大的阶梯基座
	for step in 5:
		var rr := R * (2.0 - step * 0.22)
		for z in W:
			for x in W:
				var dv := Vector2(x + 0.5, z + 0.5) - c
				if absf(dv.x) <= rr and absf(dv.y) <= rr:
					gr.box(Vector3i(x, step * 3, z), Vector3i(x, step * 3 + 2, z), Blocks.HULL_DARK if step % 2 == 0 else Blocks.HULL)
	var y0 := 15
	for y in range(y0, Hh):
		var f := float(y - y0) / (Hh - y0)
		var rad := R * (1.0 - 0.7 * pow(f, 0.7)) + (1.5 if (y % 28) < 3 else 0.0)
		var dark_band := (y % 14) < 2
		for z in W:
			for x in W:
				var dv := Vector2(x + 0.5, z + 0.5) - c
				# 八边形截面
				var oct := maxf(maxf(absf(dv.x), absf(dv.y)), (absf(dv.x) + absf(dv.y)) * 0.7071)
				if oct <= rad:
					var t := Blocks.HULL_DARK
					if dark_band:
						t = Blocks.HULL
					# 四条竖向能量纹路
					if oct > rad - 1.2 and (absi(int(dv.x)) == 0 or absi(int(dv.y)) == 0):
						t = line_t
					gr.s(x, y, z, t)
	# 悬浮的环（和塔身分开）
	for ring in [[0.35, 2.3], [0.62, 1.9], [0.82, 1.6]]:
		var ry := int(y0 + (Hh - y0) * ring[0])
		var rr: float = R * ring[1] * (1.0 - 0.6 * ring[0])
		for z in W:
			for x in W:
				var d := (Vector2(x + 0.5, z + 0.5) - c).length()
				if absf(d - rr) <= 0.9:
					gr.s(x, ry, z, Blocks.HULL)
					if int(d * 4.0 + x) % 9 == 0:
						gr.s(x, ry + 1, z, line_t)
	# 塔顶的核心
	gr.sphere(Vector3(c.x, Hh + 4, c.y), 3.2, line_t)
	for k in 6:
		var a := k * TAU / 6.0
		gr.box(Vector3i(int(c.x + cos(a) * 4.0), Hh - 2, int(c.y + sin(a) * 4.0)), Vector3i(int(c.x + cos(a) * 4.0), Hh + 8 + (k % 2) * 4, int(c.y + sin(a) * 4.0)), Blocks.HULL)
	return {"grid": gr, "falls": [], "anchor": Vector3(c.x, 0, c.y) * vs}

## 重构塔（五座之一）：站在自己的浮岛上。lit = 已点亮（接收器发光，会配一道光柱）
static func recon_tower(p: Dictionary) -> Dictionary:
	var vs: float = p.get("voxel", 1.0)
	var isl := island({"r": p.get("r", 14.0), "top": 4, "under": 20, "hill": 1.0, "trees": 0.02, "seed": p.get("seed", 5), "voxel": vs, "crystals": true, "falls": p.get("falls", 1)})
	var gr: VistaGrid = isl.grid
	var a: Vector3 = isl.anchor / vs
	var cx := int(a.x)
	var cz := int(a.z)
	var base := int(a.y)
	var th := 22
	gr.box(Vector3i(cx - 3, base, cz - 3), Vector3i(cx + 3, base + 1, cz + 3), Blocks.HULL_DARK)
	gr.box(Vector3i(cx - 1, base + 2, cz - 1), Vector3i(cx + 1, base + th, cz + 1), Blocks.HULL)
	for y in [base + 7, base + 14]:
		gr.box(Vector3i(cx - 1, y, cz - 1), Vector3i(cx + 1, y, cz + 1), Blocks.LAMP if p.get("lit", false) else Blocks.HULL_DARK)
	gr.box(Vector3i(cx, base + th + 1, cz), Vector3i(cx, base + th + 3, cz), Blocks.RECEIVER_ON if p.get("lit", false) else Blocks.RECEIVER)
	isl["top"] = Vector3(cx + 0.5, base + th + 3, cz + 0.5) * vs
	return isl

# ================================================================ 工坊（第二章）

## 工厂浮岛：岛上几栋厂房、烟囱、储罐、传送带架子
static func factory_island(p: Dictionary) -> Dictionary:
	var vs: float = p.get("voxel", 1.0)
	var seed_v: int = p.get("seed", 9)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var isl := island({"r": p.get("r", 22.0), "top": 5, "under": p.get("under", 26), "hill": 0.0, "trees": 0.006, "kinds": ["pine", "round"],
		"seed": seed_v, "voxel": vs, "crystals": false, "falls": 0, "grass": Blocks.MOSS})
	var gr: VistaGrid = isl.grid
	var a: Vector3 = isl.anchor / vs
	var R: float = p.get("r", 22.0)
	var base := int(a.y)
	var stacks: Array = []
	# 厂房
	for k in p.get("halls", 3):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 0.45) * R
		var hx := int(a.x + cos(ang) * dist)
		var hz := int(a.z + sin(ang) * dist)
		var w := rng.randi_range(5, 9)
		var d := rng.randi_range(6, 11)
		var hh := rng.randi_range(6, 12)
		gr.box(Vector3i(hx - w, base, hz - d), Vector3i(hx + w, base + hh, hz + d), Blocks.HULL if k % 2 == 0 else Blocks.TILE)
		# 锯齿屋顶
		for zz in range(hz - d, hz + d + 1):
			var saw := (zz - hz + d) % 4
			gr.box(Vector3i(hx - w, base + hh + 1, zz), Vector3i(hx + w, base + hh + 1 + (3 - saw) / 2, zz), Blocks.HULL_DARK)
		# 一排窗（发光）
		for xx in range(hx - w + 1, hx + w, 3):
			gr.s(xx, base + hh - 2, hz - d, Blocks.LAMP)
			gr.s(xx, base + hh - 2, hz + d, Blocks.LAMP)
	# 烟囱
	for k in p.get("chimneys", 2):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.3, 0.7) * R
		var cx := int(a.x + cos(ang) * dist)
		var cz := int(a.z + sin(ang) * dist)
		var ch := rng.randi_range(24, 40)
		for y in range(base, base + ch):
			var rad := 2.6 - float(y - base) / ch * 0.8
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if Vector2(dx, dz).length() <= rad:
						var t := Blocks.REINFORCED
						if (y - base) % 9 < 2:
							t = Blocks.BARREL      # 红白相间的警示环
						gr.s(cx + dx, y, cz + dz, t)
		gr.box(Vector3i(cx - 1, base + ch - 1, cz - 1), Vector3i(cx + 1, base + ch - 1, cz + 1), Blocks.EMBER)
		stacks.append(Vector3(cx + 0.5, base + ch + 0.5, cz + 0.5) * vs)
	# 储罐
	for k in 2:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.2, 0.6) * R
		gr.sphere(Vector3(a.x + cos(ang) * dist, base + 4, a.z + sin(ang) * dist), 4.0, Blocks.METAL, true, Vector3(1.0, 1.3, 1.0))
	isl["stacks"] = stacks
	return isl

## 巨型齿轮（单独一个网格，挂在节点上慢慢转）
static func gear(p: Dictionary) -> Dictionary:
	var R: float = p.get("r", 14.0)
	var vs: float = p.get("voxel", 1.0)
	var teeth: int = p.get("teeth", 16)
	var th := 4
	var W := int(R * 2.0 + 8)
	var gr := VistaGrid.new(Vector3i(W, W, th), vs)
	var c := Vector2(W * 0.5, W * 0.5)
	var holes := 6 if R > 8.0 else 4
	for y in W:
		for x in W:
			var dv := Vector2(x + 0.5, y + 0.5) - c
			var d := dv.length()
			var ang := atan2(dv.y, dv.x)
			var tooth := fposmod(ang / TAU * teeth, 1.0) < 0.5
			var outer := R + (2.2 if tooth else 0.0)
			if d > outer:
				continue
			var t := Blocks.METAL
			var depth := th
			if d > R - 1.5:
				t = Blocks.RUST if not tooth or d < R else Blocks.METAL
			elif d < R * 0.22:
				t = Blocks.HULL_DARK
			else:
				# 盘面上的圆孔
				var hole := false
				for k in holes:
					var ha := k * TAU / holes
					if (dv - Vector2(cos(ha), sin(ha)) * R * 0.56).length() < R * 0.2:
						hole = true
				if hole:
					continue
				depth = th - 2       # 盘面比轮缘薄一点，有层次
			var z0 := (th - depth) / 2
			for zz in range(z0, z0 + depth):
				gr.s(x, y, zz, t)
	return {"grid": gr, "falls": [], "anchor": Vector3(c.x, c.y, th * 0.5) * vs}

## 钢桁架桥（沿 x 方向），两头搭在远处的岛上
static func truss(p: Dictionary) -> Dictionary:
	var L: int = p.get("len", 60)
	var vs: float = p.get("voxel", 1.0)
	var gr := VistaGrid.new(Vector3i(L, 7, 5), vs)
	for x in L:
		gr.s(x, 0, 1, Blocks.HULL_DARK)
		gr.s(x, 0, 3, Blocks.HULL_DARK)
		gr.s(x, 6, 1, Blocks.RUST)
		gr.s(x, 6, 3, Blocks.RUST)
		gr.s(x, 1, 2, Blocks.TRACK)
		# 斜撑
		var k := x % 12
		var y := k if k <= 6 else 12 - k
		gr.s(x, y, 1, Blocks.RUST)
		gr.s(x, y, 3, Blocks.RUST)
		if x % 6 == 0:
			for yy in 7:
				gr.s(x, yy, 1, Blocks.HULL_DARK)
				gr.s(x, yy, 3, Blocks.HULL_DARK)
	# 断掉的一截
	if p.get("broken", false):
		for x in range(int(L * 0.55), int(L * 0.62)):
			for y in 7:
				for z in 5:
					gr.s(x, y, z, 0)
	return {"grid": gr, "falls": [], "anchor": Vector3(0, 0, 2.5) * vs}

## 漂浮的巨型晶体：一根斜着的六棱晶柱 + 旁边几根小的
static func shard(p: Dictionary) -> Dictionary:
	var L: int = p.get("len", 40)
	var R: float = p.get("r", 5.0)
	var vs: float = p.get("voxel", 1.0)
	var seed_v: int = p.get("seed", 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var W := int(R * 4) + 8
	var gr := VistaGrid.new(Vector3i(W, L + 6, W), vs)
	var c := Vector2(W * 0.5, W * 0.5)
	var t: int = p.get("block", Blocks.CRYSTAL)
	var pieces := [[c, R, L]]
	for k in 3:
		var a := rng.randf() * TAU
		pieces.append([c + Vector2(cos(a), sin(a)) * R * 1.3, R * 0.45, int(L * rng.randf_range(0.3, 0.55))])
	for pc in pieces:
		var pc_c: Vector2 = pc[0]
		var pr: float = pc[1]
		var pl: int = pc[2]
		for y in pl:
			var k := float(y) / pl
			var rr := pr * (1.0 if k < 0.75 else (1.0 - (k - 0.75) / 0.25))
			var lean := Vector2(k * pr * 0.6, 0)
			for z in W:
				for x in W:
					var q := Vector2(x + 0.5, z + 0.5) - pc_c - lean
					# 六边形截面
					var hx := maxf(absf(q.x) * 0.866 + absf(q.y) * 0.5, absf(q.y))
					if hx <= rr:
						gr.s(x, y, z, t)
	return {"grid": gr, "falls": [], "anchor": Vector3(c.x, 0, c.y) * vs}

## 城区浮岛：岛上几栋白色的楼（玻璃窗带、平顶或穹顶）、细高的塔
static func city_island(p: Dictionary) -> Dictionary:
	var vs: float = p.get("voxel", 1.0)
	var seed_v: int = p.get("seed", 11)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var R: float = p.get("r", 20.0)
	var isl := island({"r": R, "top": 5, "under": p.get("under", 24), "hill": 0.0, "trees": 0.01, "kinds": ["round", "blossom"], "seed": seed_v, "voxel": vs, "falls": p.get("falls", 0)})
	var gr: VistaGrid = isl.grid
	var a: Vector3 = isl.anchor / vs
	var base := int(a.y)
	for k in p.get("buildings", 5):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 0.55) * R
		var bx := int(a.x + cos(ang) * dist)
		var bz := int(a.z + sin(ang) * dist)
		var w := rng.randi_range(2, 5)
		var hh := rng.randi_range(6, 22)
		gr.box(Vector3i(bx - w, base, bz - w), Vector3i(bx + w, base + hh, bz + w), Blocks.HULL if k % 3 else Blocks.TILE)
		for y in range(base + 2, base + hh, 3):
			for xx in range(bx - w, bx + w + 1, 2):
				gr.s(xx, y, bz - w, Blocks.LAMP if rng.randf() < 0.15 else Blocks.GLASS)
				gr.s(xx, y, bz + w, Blocks.GLASS)
			for zz in range(bz - w, bz + w + 1, 2):
				gr.s(bx - w, y, zz, Blocks.GLASS)
				gr.s(bx + w, y, zz, Blocks.GLASS)
		if k % 2 == 0:
			gr.sphere(Vector3(bx + 0.5, base + hh + 1, bz + 0.5), w + 0.5, Blocks.GLASS, true, Vector3(1, 0.7, 1))
		else:
			gr.box(Vector3i(bx, base + hh, bz), Vector3i(bx, base + hh + rng.randi_range(3, 8), bz), Blocks.HULL_DARK)
	return isl

## 半沉在锈海里的巨船残骸：U 形船壳（有破洞）、船楼、断掉的桅杆。anchor = 船中央的吃水线
##   len 船长、w 船宽、h 船高、sink 沉下去的深度、tilt 横倾（每格高度偏移）、bow_up 船头翘起
static func wreck(p: Dictionary) -> Dictionary:
	var L: int = p.get("len", 60)
	var Wd: int = p.get("w", 14)
	var Hh: int = p.get("h", 12)
	var vs: float = p.get("voxel", 1.0)
	var seed_v: int = p.get("seed", 9)
	var bow_up: float = p.get("bow_up", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := _noise(seed_v, 0.12)
	var extra := int(bow_up * L) + 24
	var gr := VistaGrid.new(Vector3i(L + 2, Hh + extra, Wd + 4), vs)
	var cz := (Wd + 4) * 0.5
	for i in L:
		var t := float(i) / (L - 1)
		var taper := clampf(minf(t * 1.6, (1.0 - t) * 4.0), 0.25, 1.0)
		var w := Wd * 0.5 * taper
		var lift := int(bow_up * L * pow(t, 3.0))
		var rib := i % 5 == 0
		for y in Hh:
			for z in Wd + 4:
				var zz := (z + 0.5 - cz)
				var f := float(y) / Hh
				var half := w * (0.55 + 0.45 * sqrt(f))
				var d := absf(zz)
				if d > half:
					continue
				var shell := d > half - 1.2 or y == 0
				var deck := y == Hh - 1
				if not shell and not deck:
					continue
				# 锈穿的破洞
				if n.get_noise_3d(i * 1.0, y * 1.0, z * 1.0) > 0.42 and not rib:
					continue
				var tp := Blocks.HULL_DARK if rib else (Blocks.RUST if (i + y) % 6 else Blocks.RUSTROCK)
				if deck:
					tp = Blocks.PLANK if i % 4 else Blocks.RUST
				gr.s(i, y + lift, z, tp)
	# 船楼
	var bx := int(L * 0.2)
	for y in range(Hh, Hh + 7):
		for z in range(int(cz - Wd * 0.3), int(cz + Wd * 0.3)):
			for x in range(bx, bx + 8):
				var edge := x == bx or x == bx + 7 or z == int(cz - Wd * 0.3) or z == int(cz + Wd * 0.3) - 1 or y == Hh + 6
				if edge:
					gr.s(x, y, z, Blocks.HULL_DARK if y % 3 else Blocks.RUST)
	# 桅杆（断的）
	for k in 2:
		var mx := int(L * (0.45 + k * 0.2))
		var mh := rng.randi_range(10, 20)
		for y in range(Hh, Hh + mh):
			gr.s(mx, y, int(cz), Blocks.RUST)
		for z in range(int(cz) - 4, int(cz) + 5):
			gr.s(mx, Hh + mh - 3, z, Blocks.RUST)
	return {"grid": gr, "falls": [], "anchor": Vector3(L * 0.5, float(p.get("sink", 5)), cz) * vs}

