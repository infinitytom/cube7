class_name AreaCore
extends ChapterLevel
## 终章 · 星核：方舟星核塔的上半截。五座重构塔的光柱都汇到这里，塔顶的“锈蚀之心”是整颗星球锈蚀的源头。
##
## 一路往上爬：
##   T0 星核平台（出生）：巨大的环形平台，锈蚀从塔身上长出来，把绕塔坡道的入口封住了（蓄力冲刺撞开）
##   → 绕塔坡道：绕塔身一整圈往上（四条边，缓坡 + 拐角平台），路上长满锈瘤（拆掉攒物质），坡道断了两处——用重构物质补上
##   T1 反应堆回廊：从塔身的门进到中空的反应堆井，井底有上升气流——换气泡，一路飘上去
##   T2 上层环台：锈哨兵把守，空中轨道绕着塔身盘旋到塔顶
##   塔顶：Boss「锈蚀之心」（三种形态各用一次）→ 星核重构 → 结局
## 坐标单位为“格”（0.5 米）。

const SIZE := Vector3i(112, 150, 112)
const C := Vector2i(56, 56)
const CORE_R := 12                    ## 塔身半径
const SHAFT_R := 8                    ## 反应堆井半径（T1..T2 之间是空心的）
const G0 := 20                        ## 星核平台
const G1 := 48                        ## 反应堆回廊
const G2 := 80                        ## 上层环台
const GT := 112                       ## 塔顶
const SPAWN := Vector3i(56, G0, 82)
## 绕塔坡道：方形的一圈，四条边，每条边 = 拐角平台 + 14 格缓坡（升 7 格）+ 一段平路
const S0 := 13                        ## 坡道内沿（离塔心的格数）
const S1 := 18                        ## 坡道外沿（这一列是矮墙）
const RISE := 7                       ## 每条边升几格（4 × 7 = G1 - G0）
## 四条边：[起点拐角的方向（x 符号, z 符号）, 前进方向]：从东南角出发，沿东边往北、北边往西、西边往南、南边往东
const SIDES := [[Vector2i(1, 1), Vector2i(0, -1)], [Vector2i(1, -1), Vector2i(-1, 0)], [Vector2i(-1, -1), Vector2i(0, 1)], [Vector2i(-1, 1), Vector2i(1, 0)]]
const GAPS := [[1, 120], [2, 160]]    ## 断口：[第几条边的平路, 花费]

var heart: RustHeart
var boss_done := false
var _core_beams: Array[MeshInstance3D] = []
var gap_sites: Array[RebuildSite] = []
var _ending := false

func _init() -> void:
	chapter_id = "core"
	forms_at_start = [true, true, true] as Array[bool]
	kill_height = -2.0

func spawn_cell() -> Vector3i:
	return SPAWN

func spawn_yaw() -> float:
	return 0.0

# ================================================================ 搭建

func _build_world() -> void:
	world.setup(SIZE)
	rng.seed = 6606
	if not backdrop:
		Atmosphere.apply(self, "core")
	_plaza()
	_spire()
	_gallery(G1, 20.0, 0.0)
	_gallery(G2, 20.0, PI)
	_spiral()
	_top()
	_rust_growths()
	world.rebuild_all()
	decor.commit()
	world.flush_dirty()
	vista = Vistas.core(self, world)
	_rails()
	_make_beams()

## 五座重构塔的光柱：从远处斜着汇到塔顶的星核
func _make_beams() -> void:
	var top := Vector3(C.x, GT + 10, C.y) * VoxelWorld.CELL_M
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		var from := top + Vector3(cos(a) * 420.0, -160.0 + (k % 2) * 40.0, sin(a) * 420.0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var L := from.distance_to(top)
		cm.top_radius = 0.6
		cm.bottom_radius = 2.2
		cm.height = L
		cm.radial_segments = 12
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.45, 1.0, 0.8, 0.35)
		m.disable_fog = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var mid := (from + top) * 0.5
		var dir := (top - from).normalized()
		var b := Basis()
		b.y = dir
		b.x = dir.cross(Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		b.z = b.x.cross(b.y).normalized()
		mi.global_transform = Transform3D(b, mid)
		_core_beams.append(mi)

func _ring(y: int, r0: float, r1: float, t_top: int, t_under: int, depth := 3) -> void:
	for z in range(C.y - int(r1) - 1, C.y + int(r1) + 2):
		for x in range(C.x - int(r1) - 1, C.x + int(r1) + 2):
			var d := Vector2(x - C.x, z - C.y).length()
			if d < r0 or d > r1:
				continue
			world.fill_column(x, z, y - depth, y - 2, t_under)
			world.fill_column(x, z, y - 1, y - 1, t_top if int(d) % 5 else Blocks.HULL)
			_set_h(x, z, y)

func _plaza() -> void:
	# 星核平台：厚厚的一圈，外沿一圈矮墙和五座光柱基座
	for z in range(C.y - 32, C.y + 33):
		for x in range(C.x - 32, C.x + 33):
			var d := Vector2(x - C.x, z - C.y).length()
			var rr := 30.0 + 1.5 * sin(atan2(z - C.y, x - C.x) * 5.0)
			if d > rr or d < CORE_R - 0.5:
				continue
			var depth := 6 + int((rr - d) * 0.5)
			world.fill_column(x, z, G0 - depth, G0 - 2, Blocks.HULL_DARK)
			world.fill_column(x, z, G0 - 1, G0 - 1, Blocks.TILE if int(d) % 4 else Blocks.PAVING)
			_set_h(x, z, G0)
			if d > rr - 1.2 and int(atan2(z - C.y, x - C.x) * 20.0) % 3 != 0:
				world.fill_box(Vector3i(x, G0, z), Vector3i(x, G0, z), Blocks.HULL)
	for k in 5:
		var a := k * TAU / 5.0 - PI / 2.0
		var p := Vector2i(int(C.x + cos(a) * 25.0), int(C.y + sin(a) * 25.0))
		world.fill_box(Vector3i(p.x - 1, G0, p.y - 1), Vector3i(p.x + 1, G0 + 1, p.y + 1), Blocks.HULL_DARK)
		world.fill_box(Vector3i(p.x, G0 + 2, p.y), Vector3i(p.x, G0 + 2, p.y), Blocks.CRYSTAL)

func _spire() -> void:
	for y in range(0, GT):
		var hollow := y >= G1 and y < G2 + 4
		for z in range(C.y - CORE_R, C.y + CORE_R + 1):
			for x in range(C.x - CORE_R, C.x + CORE_R + 1):
				var dv := Vector2(x - C.x, z - C.y)
				var d := dv.length()
				if d > CORE_R + 0.3:
					continue
				if hollow and d < SHAFT_R:
					continue
				var ang := atan2(dv.y, dv.x)
				var vein := absf(fmod(ang * 8.0 / TAU + 8.0, 1.0) - 0.5) < 0.06 and d > CORE_R - 1.0
				var t := Blocks.CRYSTAL if vein else (Blocks.HULL if y % 12 == 0 else Blocks.HULL_DARK)
				world.set_block(Vector3i(x, y, z), t)
	# 反应堆井底（G1 的地板）
	for z in range(C.y - SHAFT_R, C.y + SHAFT_R + 1):
		for x in range(C.x - SHAFT_R, C.x + SHAFT_R + 1):
			if Vector2(x - C.x, z - C.y).length() < SHAFT_R:
				world.fill_box(Vector3i(x, G1 - 1, z), Vector3i(x, G1 - 1, z), Blocks.TILE if (x + z) % 3 else Blocks.CRYSTAL)
	# 井里的环形小平台（歇脚）
	for k in 3:
		var y := G1 + 9 + k * 8
		var a0 := k * 2.1
		for z in range(C.y - SHAFT_R, C.y + SHAFT_R + 1):
			for x in range(C.x - SHAFT_R, C.x + SHAFT_R + 1):
				var dv := Vector2(x - C.x, z - C.y)
				var d := dv.length()
				var da := absf(wrapf(atan2(dv.y, dv.x) - a0, -PI, PI))
				if d >= SHAFT_R - 2.5 and d < SHAFT_R and da < 0.7:
					world.fill_box(Vector3i(x, y - 1, z), Vector3i(x, y - 1, z), Blocks.METAL)
	# 井顶出口：北边一圈歇脚台，门通向 T2
	for z in range(C.y - SHAFT_R, C.y + SHAFT_R + 1):
		for x in range(C.x - SHAFT_R, C.x + SHAFT_R + 1):
			var d := Vector2(x - C.x, z - C.y).length()
			if d >= SHAFT_R - 3.0 and d < SHAFT_R and z < C.y - 2:
				world.fill_box(Vector3i(x, G2 - 1, z), Vector3i(x, G2 - 1, z), Blocks.TILE)
	world.fill_box(Vector3i(C.x - 1, G2, C.y - CORE_R - 1), Vector3i(C.x + 1, G2 + 3, C.y - SHAFT_R + 1), Blocks.AIR)
	# T1 进井的门（南边）
	world.fill_box(Vector3i(C.x - 1, G1, C.y + SHAFT_R - 1), Vector3i(C.x + 1, G1 + 3, C.y + CORE_R + 1), Blocks.AIR)

## 边上某处的格：along = 沿前进方向（-S1..S1，0 是边的中点），w = 离塔心的距离（S0..S1）
func side_cell(k: int, along: int, w: int, y: int) -> Vector3i:
	var dirv: Vector2i = SIDES[k][1]
	# 边的外法线：东边 +x、北边 -z、西边 -x、南边 +z
	var out: Vector2i = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)][k]
	var p := dirv * along + out * w
	return Vector3i(C.x + p.x, y, C.y + p.y)

## 某条边上 along 处的路面高度（第一层空气）
func side_h(k: int, along: int) -> int:
	var base := G0 + RISE * k
	var i := along + S0 - 1          ## 离开起点拐角后的第几格
	if i < 0:
		return base
	if i < RISE * 2:
		return base + i / 2 + 1 if i % 2 == 1 else base + i / 2
	return base + RISE

var gap_cells: Array = [[], []]

func _spiral() -> void:
	for k in 4:
		var sd: Array = SIDES[k]
		var dirv: Vector2i = sd[1]
		var dir: int = (VoxelWorld.Ramp.PX if dirv.x > 0 else VoxelWorld.Ramp.NX) if dirv.x != 0 else (VoxelWorld.Ramp.PZ if dirv.y > 0 else VoxelWorld.Ramp.NZ)
		var gi := -1
		for g in GAPS.size():
			if int(GAPS[g][0]) == k:
				gi = g
		for along in range(-S1, S1 + 1):
			var base := G0 + RISE * k
			var i := along + S0 - 1
			var ramp := i >= 0 and i < RISE * 2
			var y := base + (i / 2 if ramp else (0 if i < 0 else RISE))
			var shape := ((1 if i % 2 == 0 else 5) + dir) if ramp else 0
			var in_gap := gi >= 0 and not ramp and i >= RISE * 2 + 2 and i < RISE * 2 + 9
			for w in range(S0, S1 + 1):
				var c := side_cell(k, along, w, y)
				if w == S1:
					# 外沿矮墙（拐角那两格留给拐角自己）
					if absi(along) <= S0 - 1:
						world.fill_box(side_cell(k, along, w, y - 2), c + Vector3i(0, 1 if not ramp else 1, 0), Blocks.HULL)
					continue
				if in_gap:
					gap_cells[gi].append([c + Vector3i.DOWN * 2, Blocks.HULL_DARK, 0])
					gap_cells[gi].append([c + Vector3i.DOWN, Blocks.TILE, 0])
					continue
				world.fill_box(side_cell(k, along, w, y - 2), side_cell(k, along, w, y - 1), Blocks.HULL_DARK)
				if ramp:
					world.set_ramp(c, Blocks.TILE, shape)
				else:
					world.set_block(c + Vector3i.DOWN, Blocks.TILE)
		# 终点拐角：平台 + 外侧两边矮墙
		var sgn: Vector2i = SIDES[(k + 1) % 4][0]
		var top := G0 + RISE * (k + 1)
		for dz in range(S0, S1 + 1):
			for dx in range(S0, S1 + 1):
				var x := C.x + sgn.x * dx
				var z := C.y + sgn.y * dz
				world.fill_box(Vector3i(x, top - 3, z), Vector3i(x, top - 2, z), Blocks.HULL_DARK)
				world.fill_box(Vector3i(x, top - 1, z), Vector3i(x, top - 1, z), Blocks.TILE)
				if (dx == S1 or dz == S1) and k < 3:
					world.fill_box(Vector3i(x, top, z), Vector3i(x, top, z), Blocks.LAMP if dx == S1 and dz == S1 else Blocks.HULL)

func _gallery(y: int, r1: float, _door_a: float) -> void:
	_ring(y, CORE_R + 0.5, r1, Blocks.TILE, Blocks.HULL_DARK, 3)
	if y == G1:
		# 坡道最后一条边从回廊下面上来：挖掉那一截回廊地板（西南角 + 南边的坡）
		for z in range(C.y + S0 - 1, C.y + S1 + 1):
			for x in range(C.x - S1, C.x + 2):
				world.fill_box(Vector3i(x, y - 3, z), Vector3i(x, y - 1, z), Blocks.AIR)
				heights.erase(Vector2i(x, z))
	# 外沿栏杆
	for z in range(C.y - int(r1) - 1, C.y + int(r1) + 2):
		for x in range(C.x - int(r1) - 1, C.x + int(r1) + 2):
			var d := Vector2(x - C.x, z - C.y).length()
			if d > r1 - 1.0 and d <= r1 and (x + z) % 2 == 0:
				world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.HULL)

func _top() -> void:
	# 塔顶场地：一整块圆盘，外沿一圈矮墙，四座弹射炮底座
	for z in range(C.y - 21, C.y + 22):
		for x in range(C.x - 21, C.x + 22):
			var d := Vector2(x - C.x, z - C.y).length()
			if d > 20.0:
				continue
			world.fill_column(x, z, GT - 3, GT - 1, Blocks.HULL_DARK)
			world.fill_box(Vector3i(x, GT - 1, z), Vector3i(x, GT - 1, z), Blocks.TILE if int(d) % 4 else Blocks.CRYSTAL)
			_set_h(x, z, GT)
			if d > 19.0 and not (z > C.y + 15 and absi(x - C.x) <= 3):
				world.fill_box(Vector3i(x, GT, z), Vector3i(x, GT, z), Blocks.HULL)
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var p := Vector2i(int(C.x + cos(a) * 13.0), int(C.y + sin(a) * 13.0))
		world.fill_box(Vector3i(p.x - 1, GT - 1, p.y - 1), Vector3i(p.x + 1, GT - 1, p.y + 1), Blocks.HULL_DARK)
	# 轨道的终点平台（塔顶南边伸出去一截）
	world.fill_box(Vector3i(C.x - 2, GT - 1, C.y + 20), Vector3i(C.x + 2, GT - 1, C.y + 25), Blocks.TILE)
	for z in range(C.y + 20, C.y + 26):
		_set_h(C.x - 2, z, GT)

## 锈瘤：长在塔身、平台和坡道上的一团团锈铁（拆掉攒物质）
func _rust_growths() -> void:
	# 封住坡道入口的锈墙（第一条边的坡底）
	for along in range(-S0 + 1, -S0 + 3):
		for w in range(S0, S1):
			var c := side_cell(0, along, w, G0)
			# 只填空气：别把坡道本身也盖成锈（撞开以后坡道要是完整的）
			for vz in range(c.z * 2, c.z * 2 + 2):
				for vy in range(G0 * 2, (G0 + 5) * 2):
					for vx in range(c.x * 2, c.x * 2 + 2):
						if world.vget(Vector3i(vx, vy, vz)) == Blocks.AIR:
							world.vset(Vector3i(vx, vy, vz), Blocks.RUST)
	# 每条边平路上、贴着塔身长一团锈瘤；每个拐角内侧也有一团
	for k in 4:
		var c := side_cell(k, 6, S0, G0 + RISE * (k + 1))
		_blob(Vector3(c.x + 0.5, c.y + 1.0, c.z + 0.5), rng.randf_range(1.2, 1.4))
		var sgn: Vector2i = SIDES[(k + 1) % 4][0]
		if k < 3:
			_blob(Vector3(C.x + sgn.x * S0 + 0.5, G0 + RISE * (k + 1) + 1.0, C.y + sgn.y * S0 + 0.5), 1.2)
	for k in 6:
		var aa := k * TAU / 6.0 + 0.3
		_blob(Vector3(C.x + cos(aa) * 22.0, G0 + 1, C.y + sin(aa) * 22.0), rng.randf_range(2.0, 3.0))
	for k in 4:
		var aa := k * TAU / 4.0
		_blob(Vector3(C.x + cos(aa) * 16.0, G2 + 1, C.y + sin(aa) * 16.0), 2.0)

func _blob(c: Vector3, r: float) -> void:
	for z in range(int(c.z - r) - 1, int(c.z + r) + 2):
		for y in range(int(c.y - r), int(c.y + r) + 2):
			for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
				var d := Vector3(x + 0.5, y + 0.5, z + 0.5).distance_to(c)
				if d <= r and world.get_block(Vector3i(x, y, z)) == Blocks.AIR:
					world.set_block(Vector3i(x, y, z), Blocks.RUST if d < r - 0.8 or (x + y + z) % 3 else Blocks.CRATE)

func _rails() -> void:
	# T2 → 塔顶：绕塔身半圈的空中轨道
	var r := SkyRail.new()
	add_child(r)
	var pts: Array[Vector3] = []
	var n := 7
	for i in n:
		var f := float(i) / (n - 1)
		var a := -PI * 0.5 - f * PI * 1.0
		var rr := 21.0 if i < n - 1 else 22.5
		var y := lerpf(G2 + 0.4, GT + 0.4, f)
		pts.append(Vector3(C.x + cos(a) * rr, y, C.y + sin(a) * rr))
	pts.append(Vector3(C.x, GT + 0.4, C.y + 17.0))
	for p in pts:
		r.curve.add_point(p * VoxelWorld.CELL_M)
	for i in range(1, r.curve.point_count - 1):
		var prev := r.curve.get_point_position(i - 1)
		var nxt := r.curve.get_point_position(i + 1)
		r.curve.set_point_in(i, -(nxt - prev) * 0.22)
		r.curve.set_point_out(i, (nxt - prev) * 0.22)
	r.build_visual()
	# 起点站台（T2 北边伸出去一截）
	var s := Vector3(C.x, G2, C.y - 21)
	world.fill_box(Vector3i(int(s.x) - 2, G2 - 1, int(s.z) - 2), Vector3i(int(s.x) + 2, G2 - 1, int(s.z) + 2), Blocks.TILE)
	world.flush_dirty()

# ================================================================ 机关、敌人、对话

func _logic() -> void:
	# 断口的重构点
	for gi in GAPS.size():
		var k: int = GAPS[gi][0]
		var site := RebuildSite.new()
		site.world = world
		site.site_id = "core_gap%d" % gi
		site.title = "断掉的坡道"
		site.cost = int(GAPS[gi][1])
		site.blueprint = gap_cells[gi]
		site.pad_cell = side_cell(k, 2, S0 + 2, G0 + RISE * (k + 1))
		add_child(site)
		gap_sites.append(site)
	# 井底上升气流：气泡形态一路飘上去
	zone(Fan, Vector3i(C.x - 3, G1, C.y - 3), Vector3i(C.x + 3, G2 + 3, C.y + 3), {"strength": 4.6, "max_rise_speed": 4.4})
	# 塔顶弹射炮
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var p := Vector2i(int(C.x + cos(a) * 13.0), int(C.y + sin(a) * 13.0))
		var to_c := Vector2(C.x - p.x, C.y - p.y).normalized()
		zone(BouncePad, Vector3i(p.x - 1, GT, p.y - 1), Vector3i(p.x + 1, GT + 1, p.y + 1), {"launch": Vector3(to_c.x * 4.8, 19.0, to_c.y * 4.8)})
	# 敌人
	spawn_enemy(Scrapling.new(), Vector3i(C.x + 18, G0, C.y + 10))
	spawn_enemy(Scrapling.new(), Vector3i(C.x - 18, G0, C.y + 12))
	spawn_enemy(Rustfly.new(), Vector3i(C.x + 10, G0 + 8, C.y + 22), 2.0)
	spawn_enemy(Spikeshell.new(), Vector3i(C.x - 20, G0, C.y - 8))
	spawn_enemy(Rustfly.new(), Vector3i(C.x, G1 + 6, C.y + 18), 2.0)
	spawn_enemy(Sentinel.new(), Vector3i(C.x + 15, G1, C.y - 8))
	spawn_enemy(Sentinel.new(), Vector3i(C.x - 14, G2, C.y + 8))
	spawn_enemy(Sentinel.new(), Vector3i(C.x + 14, G2, C.y + 8))
	var mo := spawn_enemy(Mortar.new(), Vector3i(C.x - 16, G2, C.y - 8)) as Mortar
	if mo:
		mo.reach = 15.0
	spawn_enemy(Rustfly.new(), Vector3i(C.x, G2 + 6, C.y - 16), 2.0)
	# 收集品
	seed_at("core_s1", Vector3i(C.x + 26, G0, C.y), 0)
	seed_at("core_s2", Vector3i(C.x + 17, G1, C.y + 3), 1)
	seed_at("core_s3", Vector3i(C.x - 6, G1 + 25, C.y + 3), 2)
	seed_at("core_s4", Vector3i(C.x - 17, G2, C.y - 3), 3)
	fragment("core_1", Vector3i(C.x - 24, G0, C.y + 6), "艾拉·林，研究日志 #1：今天我们登上了方舟的顶端。星核在发光。所有人都说，这颗星球会成为我们的家。")
	fragment("core_2", Vector3i(C.x - 18, G1, C.y - 4), "艾拉·林，研究日志 #402：锈蚀的源头就在星核里。它不是病毒——它是“遗忘”。结构忘记了自己原来的样子，就开始锈。")
	fragment("core_3", Vector3i(C.x + 17, G2, C.y - 6), "艾拉·林，最后的最后：PIX，如果你读到这条——我就在你身边。一直都在。")
	zone(TreasureChest, Vector3i(C.x - 26, G0, C.y - 4), Vector3i(C.x - 26, G0 + 1, C.y - 4), {"chest_id": "core_plaza", "coins": 40, "energy": 5})
	zone(TreasureChest, Vector3i(C.x + 3, G1 + 17, C.y - 5), Vector3i(C.x + 3, G1 + 18, C.y - 5), {"chest_id": "core_shaft", "coins": 50, "energy": 5, "line": "反应堆井里的宝箱！"})
	# 检查点
	checkpoint(SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	checkpoint(Vector3i(C.x + 13, G1, C.y + 13), Vector3i(C.x + 17, G1 + 3, C.y + 17))
	checkpoint(Vector3i(C.x - 3, G1, C.y - 3), Vector3i(C.x + 3, G1 + 3, C.y + 3))
	checkpoint(Vector3i(C.x - 3, G2, C.y - 20), Vector3i(C.x + 3, G2 + 3, C.y - 15))
	checkpoint(Vector3i(C.x - 2, GT, C.y + 20), Vector3i(C.x + 2, GT + 3, C.y + 25))
	# 对话
	talk(SPAWN + Vector3i(-4, 0, -4), SPAWN + Vector3i(4, 5, 4), [
		"方舟星核……五座塔的光都汇到这里了。",
		"锈蚀是从塔顶开始的。PIX，我们一路爬上去。",
		"坡道的入口被锈封住了——那种厚锈，原地蓄力再冲。",
	])
	talk(Vector3i(C.x - 4, G1, C.y + 10), Vector3i(C.x + 4, G1 + 4, C.y + 16), [
		"反应堆井。井底有上升气流——换成气泡形态，按住{jump}能飘得更稳。",
	])
	talk(Vector3i(C.x - 4, G2, C.y - 22), Vector3i(C.x + 4, G2 + 4, C.y - 16), [
		"空中轨道一直通到塔顶。……准备好了吗？",
	])
	GameState.set_objective(0, "撞开锈墙，沿绕塔坡道往上爬", _v(side_cell(0, -S0 + 1, S0 + 2, G0)))
	objective(1, "坡道断了——拆锈瘤攒物质，重建坡道", site_pad(0), site_pad(0) + Vector3i(-3, 0, -3), site_pad(0) + Vector3i(3, 3, 3))
	objective(2, "进反应堆井，乘上升气流往上", Vector3i(C.x, G1, C.y), Vector3i(C.x + 10, G1, C.y + 10), Vector3i(C.x + 20, G1 + 4, C.y + 20))
	objective(3, "坐空中轨道去塔顶", Vector3i(C.x, G2, C.y - 21), Vector3i(C.x - 4, G2, C.y - 12), Vector3i(C.x + 4, G2 + 4, C.y - 8))
	_setup_boss()

func site_pad(i: int) -> Vector3i:
	return gap_sites[i].pad_cell if i < gap_sites.size() else Vector3i.ZERO

func _setup_boss() -> void:
	heart = RustHeart.new()
	add_child(heart)
	heart.floor_y = GT * VoxelWorld.CELL_M
	heart.home = world.voxel_center(Vector3i(C.x, GT, C.y)) - Vector3.UP * (VoxelWorld.CELL_M * 0.5)
	heart.home.y = heart.floor_y
	heart.arena_r = 9.5
	heart.global_position = heart.home + Vector3.UP * 4.0
	heart.defeated.connect(_on_boss_defeated)
	var trig := zone(Zone, Vector3i(C.x - 18, GT, C.y - 18), Vector3i(C.x + 18, GT + 8, C.y + 18))
	trig.player_entered.connect(func() -> void:
		if is_instance_valid(heart) and not heart.active and not boss_done:
			heart.start()
			Music.play_area("boss")
			Music.set_override("explore"))

func _on_boss_defeated(_e: Node) -> void:
	boss_done = true
	SaveGame.set_flag("core_boss")
	Music.play_area("core")
	Music.set_override("bright")
	GameState.say("……锈蚀之心不跳了。PIX，站到星核中间去。我们把它——重构回来。")
	_rebuild_core()

## 星核重构：一颗巨大的水晶从四面八方的方块里拼起来
func _rebuild_core() -> void:
	var c := Vector3i(C.x, GT + 10, C.y)
	var rb := VoxelRebuilder.new()
	rb.world = world
	rb.pitch_base = 0.6
	add_child(rb)
	var list: Array = []
	for y in range(-9, 10):
		var w := 6 - absi(y) * 6 / 9
		for z in range(-w, w + 1):
			for x in range(-w, w + 1):
				if absi(x) + absi(z) <= w and (absi(x) + absi(z) == w or absi(y) == 9 or (x + y + z) % 5 == 0):
					list.append(c + Vector3i(x, y, z))
	list.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y)
	var i := 0
	for cell in list:
		var to := world.voxel_center(cell)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.3), rng.randf_range(-1, 1)).normalized()
		rb.add_cell(cell, Blocks.CRYSTAL, 0, to, to + dir * rng.randf_range(20.0, 60.0), i * 0.012, rng.randf_range(1.0, 1.8))
		i += 1
	reconstruct(world.voxel_center(Vector3i(C.x, GT, C.y)), 200.0, 10.0)
	rb.finished.connect(func() -> void:
		Sfx.play("rebuild_done", Vector3.INF, 2.0, 0.0, 0.6)
		GameState.shake.emit(0.6)
		for b in _core_beams:
			var m := b.material_override as StandardMaterial3D
			create_tween().tween_property(m, "albedo_color:a", 0.9, 2.0)
		get_tree().create_timer(2.5).timeout.connect(_ending_sequence))

# ================================================================ 结局

func _ending_sequence() -> void:
	if _ending:
		return
	_ending = true
	GameState.level_complete = true
	SaveGame.set_flag("game_clear")
	SaveGame.write()
	var p := GameState.player as MorphBall
	if p:
		p.freeze = true
	var hud := get_tree().current_scene.get_node_or_null("Hud") as CanvasLayer
	if hud:
		hud.visible = false
	var V := VoxelWorld.CELL_M
	var core := Vector3(C.x, GT + 10, C.y) * V
	var cs := Cutscene.new()
	cs.shots = [
		{"from": core + Vector3(0, 2, 14), "to": core + Vector3(6, 4, 11), "look": core, "dur": 6.0, "fade": Color.WHITE,
			"lines": [["NOVA", "星核重构完成了。……你听，整座塔都在响。"], ["NOVA", "PIX，有件事我一直没告诉你。"]]},
		{"from": core + Vector3(-10, -2, 8), "to": core + Vector3(-12, 6, -4), "look": core, "dur": 7.0,
			"lines": [["NOVA", "艾拉·林——写那些日志的人——是这座站点的首席工程师。"], ["NOVA", "锈蚀爆发的那天，她把自己的记忆……放进了站点 AI 里。"], ["NOVA", "……也就是我。"]]},
		{"from": core + Vector3(40, 30, 60), "to": core + Vector3(80, 50, 110), "look": core + Vector3(0, -20, 0), "dur": 7.0, "event": "wave",
			"lines": [["NOVA", "重构需要一个记得一切的人。我记得这颗星球原来的样子。"], ["NOVA", "现在，它也想起来了。"]]},
		{"from": core + Vector3(0, 3, 9), "to": core + Vector3(0, 1.5, 5), "look": core + Vector3(0, -3, 0), "dur": 6.0,
			"lines": [["PIX", "……噗！"], ["NOVA", "谢谢你，PIX。以后，换我们一起照顾它。"]]},
	]
	cs.event.connect(func(n: String) -> void:
		if n == "wave":
			Atmosphere.apply(self, "dawn")
			reconstruct(core, 300.0, 6.0))
	add_child(cs)
	cs.play()
	await cs.finished
	var cr := Credits.new()
	get_tree().current_scene.add_child(cr)
	await cr.finished
	Music.stop()
	Flow.goto_title()

func _apply_flags(flags: Dictionary) -> void:
	if bool(flags.get("core_boss", false)):
		if is_instance_valid(heart):
			heart.queue_free()
		boss_done = true

func arrival_shots() -> Array:
	var V := VoxelWorld.CELL_M
	return [
		{"from": Vector3(C.x + 90, G0 - 40, C.y + 120) * V, "to": Vector3(C.x + 60, G0 + 20, C.y + 80) * V, "look": Vector3(C.x, GT, C.y) * V, "dur": 6.0, "fade": Color.BLACK,
			"lines": [["NOVA", "方舟星核。整颗星球的心脏。"], ["NOVA", "五道光都汇到它的顶上了——锈蚀的源头也在那里。"]]},
		{"from": Vector3(C.x - 30, GT + 20, C.y - 30) * V, "to": Vector3(C.x - 20, GT + 12, C.y - 20) * V, "look": Vector3(C.x, GT + 4, C.y) * V, "dur": 5.0,
			"lines": [["NOVA", "……它在跳动。"]]},
		{"from": Vector3(SPAWN.x, G0 + 8, SPAWN.z + 14) * V, "to": Vector3(SPAWN.x, G0 + 4, SPAWN.z + 8) * V, "look": Vector3(SPAWN) * V, "dur": 4.0,
			"lines": [["NOVA", "最后一段路了。走吧，PIX。"]]},
	]
