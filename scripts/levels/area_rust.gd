class_name AreaRust
extends ChapterLevel
## 第五章 · 锈海：星球上最大的海，整片海都锈成了橙红色的泥。殖民船队当年就停在这里，现在只剩一艘艘锈穿的沉船。
## 第五座重构塔是海中央的旧灯塔——它被“锈海吞噬者”啃得只剩一截塔基。
##
## 这一章的核心是“拆 → 攒物质 → 重建”：
##   A 希望号沉船（出生）：巨大的锈船壳，想拆多少拆多少
##   → B 潮汐浅滩：步道只在低潮时露出来；涨潮前汽笛会响，躲到高处的礁柱上
##   C 沉船墓场：侧翻的货轮、塔吊、集装箱堆——拆出足够的重构物质
##   → 重建栈桥（◆150）→ D 灯塔岛：Boss「锈海吞噬者」
##     它跃出海面啃掉岛边；趴下喘气的时候滚上它的背撞碎锈核，每撞碎一颗，岛就被重构一次
##   → 打倒它以后，灯塔从海里一块块重建起来——第五座塔点亮
##   （选做）E 南边的沉没客轮：低潮时沿着长长的浅滩走过去
## 坐标单位为“格”（0.5 米）。

const SIZE := Vector3i(160, 72, 160)
const SEA_LOW := 6.0                 ## 低潮海面（米）
const SEA_HIGH := 8.2                ## 高潮海面（米）
const G := 18                        ## 陆地（第一层空气）：9 米，高潮也淹不到
const GW := 14                       ## 浅滩步道：7 米，低潮露出、高潮淹没
const A_C := Vector2i(28, 128)       ## 希望号沉船岛
const C_C := Vector2i(86, 100)       ## 沉船墓场
const PIER := Vector2i(100, 64)      ## 墓场东南的码头
const D_C := Vector2i(136, 60)       ## 灯塔岛
const D_R := 15
const E_C := Vector2i(30, 72)        ## 沉没客轮（选做）
const SPAWN := Vector3i(16, G, 140)
const BRIDGE_A := Vector3i(106, G - 1, 64)
const BRIDGE_B := Vector3i(121, G - 1, 64)
const LH_R := 4                      ## 灯塔半径（格）
const LH_H := 40

var sea: RustSea
var _n := FastNoiseLite.new()
var worm: RustWorm
var boss_done := false
var bridge_site: RebuildSite
var lighthouse_built := false

func _init() -> void:
	chapter_id = "rust"
	forms_at_start = [true, true, true] as Array[bool]
	kill_height = SEA_LOW - 0.35

func spawn_cell() -> Vector3i:
	return SPAWN

func spawn_yaw() -> float:
	return -PI / 2.0 + 0.5

# ================================================================ 搭建

func _build_world() -> void:
	world.setup(SIZE)
	rng.seed = 5505
	_n.seed = 55
	_n.frequency = 0.07
	if not backdrop:
		Atmosphere.apply(self, "rust")
	# 陆地
	_land(A_C, 19.0, G)
	_land(C_C, 22.0, G)
	_land(PIER, 7.0, G)
	_land(D_C, float(D_R), G)
	_land(E_C, 11.0, G)
	# 墓场到码头的地峡
	_strip(Vector2i(C_C.x + 4, C_C.y - 18), Vector2i(PIER.x, PIER.y + 4), 4, G)
	# 浅滩：A → C，一路上两根礁柱可以躲潮
	_walkway([Vector2i(46, 126), Vector2i(54, 122), Vector2i(60, 116), Vector2i(66, 112), Vector2i(72, 106)])
	_land(Vector2i(56, 121), 3.2, G + 2)
	_land(Vector2i(67, 111), 3.0, G + 2)
	# 浅滩：A → E（选做，更长）
	_walkway([Vector2i(26, 110), Vector2i(30, 102), Vector2i(28, 94), Vector2i(31, 86)])
	_land(Vector2i(29, 99), 3.0, G + 2)
	_hope_wreck()
	_graveyard()
	_liner()
	_lighthouse_ruin()
	# 出生点脚下垫平一块（平滑地形的沙丘是圆的，球一落地就会顺着坡滚进海里）
	for z in range(SPAWN.z - 2, SPAWN.z + 3):
		for x in range(SPAWN.x - 2, SPAWN.x + 3):
			for y in range(G - 3, G):
				if world.get_block(Vector3i(x, y, z)) == Blocks.AIR:
					world.set_block(Vector3i(x, y, z), Blocks.RUSTDUNE)
			for y in range(G, G + 3):
				world.set_block(Vector3i(x, y, z), Blocks.AIR)
	world.rebuild_all()
	decor.commit()
	world.flush_dirty()
	if not backdrop:
		sea = RustSea.new()
		sea.low_y = SEA_LOW
		sea.high_y = SEA_HIGH
		add_child(sea)
	vista = Vistas.rust(self, world)

## 一块陆地：锈砂丘顶面（带小起伏），下面是锈岩，一直通到海底
func _land(c: Vector2i, r: float, g: int) -> void:
	for z in range(c.y - int(r) - 3, c.y + int(r) + 4):
		for x in range(c.x - int(r) - 3, c.x + int(r) + 4):
			var dv := Vector2(x - c.x, z - c.y)
			var ang := atan2(dv.y, dv.x)
			var rr := r * (0.9 + 0.12 * _n.get_noise_2d(cos(ang) * 20.0 + c.x, sin(ang) * 20.0 + c.y))
			if dv.length() > rr:
				continue
			var top := g
			if g == G and dv.length() < rr - 3.0:
				top = g + (1 if _n.get_noise_2d(x * 2.0, z * 2.0) > 0.35 else 0)
			if h_at(x, z) >= top:
				continue
			world.fill_column(x, z, 0, top - 4, Blocks.RUSTROCK)
			world.fill_column(x, z, top - 3, top - 1, Blocks.RUSTDUNE)
			# 零星的苔藓和草：锈海边上还有一点点绿色
			var gn := _n.get_noise_2d(x * 1.7 + 40.0, z * 1.7)
			if gn > 0.3 and dv.length() < rr - 1.5:
				world.fill_column(x, z, top - 1, top - 1, Blocks.GRASS if gn > 0.45 else Blocks.MOSS)
			_set_h(x, z, top)

## 浅滩步道：3 格宽，折线穿过海面，顶面在 GW（低潮露出）
func _walkway(pts: Array) -> void:
	for i in pts.size() - 1:
		var a: Vector2i = pts[i]
		var b: Vector2i = pts[i + 1]
		var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for k in n + 1:
			var t := float(k) / float(n)
			var cx := roundi(lerpf(a.x, b.x, t))
			var cz := roundi(lerpf(a.y, b.y, t))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var z := cz + dz
					if h_at(x, z) >= GW:
						continue
					world.fill_column(x, z, 0, GW - 2, Blocks.RUSTROCK)
					world.fill_column(x, z, GW - 1, GW - 1, Blocks.PAVING if (x + z) % 3 else Blocks.RUSTDUNE)
					_set_h(x, z, GW)
			# 步道两边偶尔插一根锈桩（涨潮时露出头，标出路线）
			if k % 5 == 2:
				var side := Vector2i(2, 0) if absi(b.y - a.y) > absi(b.x - a.x) else Vector2i(0, 2)
				var s := Vector2i(cx, cz) + side * (1 if (k / 5) % 2 == 0 else -1)
				if h_at(s.x, s.y) < 0:
					world.fill_column(s.x, s.y, 0, G + 1, Blocks.RUST)

func _strip(a: Vector2i, b: Vector2i, w: int, g: int) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in n + 1:
		var t := float(k) / float(n)
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		for dz in range(-w, w + 1):
			for dx in range(-w, w + 1):
				if Vector2(dx, dz).length() <= w + 0.3 and h_at(c.x + dx, c.y + dz) < g:
					world.fill_column(c.x + dx, c.y + dz, 0, g - 4, Blocks.RUSTROCK)
					world.fill_column(c.x + dx, c.y + dz, g - 3, g - 1, Blocks.RUSTDUNE)
					_set_h(c.x + dx, c.y + dz, g)

## 船壳：沿 x 方向，长 L、宽 W、高 H（格）；on_side = 侧翻（龙骨朝一边）。壳是锈铁，每 6 格一道深色肋骨
func _ship(o: Vector3i, L: int, W: int, H: int, on_side := false, deck := true) -> void:
	for i in L:
		var t := float(i) / float(L - 1)
		var taper := clampf(minf(t, 1.0 - t) * 5.0, 0.35, 1.0)
		var w := W * 0.5 * taper
		var h := float(H)
		var rib := i % 6 == 0
		for a in range(0, H + 1):
			for b in range(-int(w) - 1, int(w) + 2):
				# 横截面：U 形船底
				var yy := float(a)
				var zz := float(b)
				var inside := (zz / maxf(w, 0.5)) * (zz / maxf(w, 0.5)) + pow(maxf(0.0, (h * 0.55 - yy) / (h * 0.55)), 2.0) <= 1.0
				var inner := (zz / maxf(w - 1.2, 0.3)) * (zz / maxf(w - 1.2, 0.3)) + pow(maxf(0.0, (h * 0.55 - yy + 1.2) / (h * 0.55)), 2.0) <= 1.0
				if not inside:
					continue
				var shell := not inner or yy < 1.0
				var is_deck := deck and a == H and not on_side
				if not shell and not is_deck:
					continue
				var tp := Blocks.HULL_DARK if rib else (Blocks.RUST if (i + a) % 7 else Blocks.HULL_DARK)
				var c := Vector3i(o.x + i, o.y + a, o.z + b) if not on_side else Vector3i(o.x + i, o.y + b + int(w) + 1, o.z + a)
				if is_deck:
					tp = Blocks.PLANK if (i % 5) else Blocks.RUST
				world.set_block(c, tp)

# ---------------------------------------------------------------- A 希望号

func _hope_wreck() -> void:
	# 殖民船“希望号”：斜插在沙洲上，船头翘起。甲板能走，船壳能拆
	_ship(Vector3i(A_C.x - 16, G - 3, A_C.y - 4), 30, 12, 9)
	# 船头上翘的一截（台阶状）
	for k in 5:
		world.fill_box(Vector3i(A_C.x + 14 + k, G + 6 + k, A_C.y - 6), Vector3i(A_C.x + 14 + k, G + 6 + k, A_C.y - 2), Blocks.RUST)
	# 上甲板的斜坡（从沙滩滚上去）
	for k in 6:
		world.set_ramp(Vector3i(A_C.x - 22 + k, G + k / 2, A_C.y - 5), Blocks.PLANK, 1 if k % 2 == 0 else 5)
		for dz in range(-4, -1):
			world.set_ramp(Vector3i(A_C.x - 22 + k, G + k / 2, A_C.y + dz), Blocks.PLANK, 1 if k % 2 == 0 else 5)
			if k >= 2:
				world.fill_box(Vector3i(A_C.x - 22 + k, G, A_C.y + dz), Vector3i(A_C.x - 22 + k, G + k / 2 - 1, A_C.y + dz), Blocks.RUST)
		if k >= 2:
			world.fill_box(Vector3i(A_C.x - 22 + k, G, A_C.y - 5), Vector3i(A_C.x - 22 + k, G + k / 2 - 1, A_C.y - 5), Blocks.RUST)
	# 舰桥（船尾的小楼）
	world.fill_box(Vector3i(A_C.x - 13, G + 7, A_C.y - 6), Vector3i(A_C.x - 8, G + 11, A_C.y - 2), Blocks.HULL_DARK)
	world.fill_box(Vector3i(A_C.x - 12, G + 7, A_C.y - 5), Vector3i(A_C.x - 9, G + 10, A_C.y - 3), Blocks.AIR)
	world.fill_box(Vector3i(A_C.x - 13, G + 9, A_C.y - 5), Vector3i(A_C.x - 13, G + 10, A_C.y - 3), Blocks.GLASS)
	# 船身上的大破洞：从沙滩直接滚进船舱
	world.fill_box(Vector3i(A_C.x - 2, G, A_C.y + 1), Vector3i(A_C.x + 2, G + 2, A_C.y + 3), Blocks.AIR)
	# 沙滩上散落的补给箱和锈桶
	for p in [Vector2i(A_C.x - 8, A_C.y + 10), Vector2i(A_C.x + 6, A_C.y + 9), Vector2i(A_C.x + 12, A_C.y + 6)]:
		world.fill_box(Vector3i(p.x, G, p.y), Vector3i(p.x + 1, G + 1, p.y + 1), Blocks.CRATE)

# ---------------------------------------------------------------- C 沉船墓场

func _graveyard() -> void:
	var c := C_C
	# 侧翻的货轮（里面藏着一只噗噗）
	_ship(Vector3i(c.x - 16, G, c.y - 10), 26, 12, 10, true)
	# 货轮肚子里的小舱室（噗噗在这里）：侧壁要蓄力冲刺撞开
	world.fill_box(Vector3i(c.x - 6, G + 2, c.y - 6), Vector3i(c.x - 2, G + 4, c.y - 2), Blocks.AIR)
	world.fill_box(Vector3i(c.x - 6, G + 1, c.y - 6), Vector3i(c.x - 2, G + 1, c.y - 2), Blocks.PLANK)
	# 塔吊：镂空的方塔 + 横臂
	var cb := Vector3i(c.x + 10, G, c.y + 10)
	for y in range(G, G + 22):
		for k in 4:
			var dx := 0 if k % 2 == 0 else 2
			var dz := 0 if k < 2 else 2
			world.set_block(Vector3i(cb.x + dx, y, cb.z + dz), Blocks.HULL_DARK if y % 4 else Blocks.RUST)
		if y % 4 == 0:
			world.fill_box(Vector3i(cb.x, y, cb.z), Vector3i(cb.x + 2, y, cb.z + 2), Blocks.RUST)
			world.set_block(Vector3i(cb.x + 1, y, cb.z + 1), Blocks.AIR)
	world.fill_box(Vector3i(cb.x - 10, G + 22, cb.z), Vector3i(cb.x + 6, G + 22, cb.z + 2), Blocks.RUST)
	world.fill_box(Vector3i(cb.x + 4, G + 19, cb.z), Vector3i(cb.x + 6, G + 21, cb.z + 2), Blocks.HULL_DARK)
	world.fill_box(Vector3i(cb.x - 10, G + 23, cb.z + 1), Vector3i(cb.x - 8, G + 23, cb.z + 1), Blocks.LAMP)
	# 集装箱堆：可以当台阶爬上去
	var cs := [[Vector3i(c.x - 12, G, c.y + 12), 0], [Vector3i(c.x - 12, G + 3, c.y + 15), 1], [Vector3i(c.x - 7, G, c.y + 16), 0],
		[Vector3i(c.x - 18, G, c.y + 6), 0], [Vector3i(c.x - 18, G + 3, c.y + 6), 1]]
	for e in cs:
		var o: Vector3i = e[0]
		var col: int = Blocks.RUST if rng.randi() % 2 == 0 else Blocks.HULL_DARK
		if int(e[1]) == 0:
			world.fill_box(o, o + Vector3i(6, 2, 2), col)
			world.fill_box(o + Vector3i(1, 0, 1), o + Vector3i(5, 1, 1), Blocks.CRATE)
		else:
			world.fill_box(o, o + Vector3i(2, 2, 6), col)
			world.fill_box(o + Vector3i(1, 0, 1), o + Vector3i(1, 1, 5), Blocks.CRATE)
	# 码头：灯塔在对面，栈桥断了
	world.fill_box(Vector3i(PIER.x + 3, G - 1, PIER.y - 2), Vector3i(BRIDGE_A.x, G - 1, PIER.y + 2), Blocks.PLANK)
	for k in 3:
		world.fill_column(PIER.x + 3 + k * 3, PIER.y - 3, 0, G, Blocks.RUST)
		world.fill_column(PIER.x + 3 + k * 3, PIER.y + 3, 0, G, Blocks.RUST)
	# 断桥的残桩（露出海面）
	for x in [110, 114, 118]:
		world.fill_column(x, BRIDGE_A.z - 2, 0, G - 3, Blocks.RUST)
		world.fill_column(x, BRIDGE_A.z + 2, 0, G - 4, Blocks.RUST)

# ---------------------------------------------------------------- E 沉没客轮

func _liner() -> void:
	_ship(Vector3i(E_C.x - 12, G - 4, E_C.y - 2), 24, 10, 8)
	world.fill_box(Vector3i(E_C.x - 6, G + 4, E_C.y - 5), Vector3i(E_C.x + 2, G + 7, E_C.y + 1), Blocks.HULL)
	world.fill_box(Vector3i(E_C.x - 5, G + 4, E_C.y - 4), Vector3i(E_C.x + 1, G + 6, E_C.y), Blocks.AIR)
	for k in 3:
		world.fill_box(Vector3i(E_C.x - 5 + k * 3, G + 8, E_C.y - 3), Vector3i(E_C.x - 4 + k * 3, G + 11, E_C.y - 2), Blocks.RUST if k != 1 else Blocks.HULL_DARK)

# ---------------------------------------------------------------- D 灯塔

func _lighthouse_ruin() -> void:
	# 只剩一截参差不齐的塔基
	for y in range(G, G + 9):
		for dz in range(-LH_R, LH_R + 1):
			for dx in range(-LH_R, LH_R + 1):
				var d := Vector2(dx, dz).length()
				if d > LH_R + 0.3 or d < LH_R - 1.2:
					continue
				var broken_h := 3 + int((_n.get_noise_2d(dx * 5.0, dz * 5.0) * 0.5 + 0.5) * 6.0)
				if y - G > broken_h:
					continue
				world.set_block(Vector3i(D_C.x + dx, y, D_C.y + dz), _lh_block(y))
	# 门洞
	world.fill_box(Vector3i(D_C.x - LH_R, G, D_C.y - 1), Vector3i(D_C.x - LH_R + 1, G + 2, D_C.y + 1), Blocks.AIR)
	# 岛上散落的塔身碎块
	for k in 7:
		var a := k * TAU / 7.0 + 0.3
		var p := Vector3i(int(D_C.x + cos(a) * (LH_R + 4 + k % 3)), G, int(D_C.y + sin(a) * (LH_R + 4 + k % 3)))
		world.fill_box(p, p + Vector3i(k % 2, int(k % 3 == 0), 1 - k % 2), _lh_block(G + k * 4))

func _lh_block(y: int) -> int:
	return Blocks.RUST if ((y - G) / 4) % 2 == 1 else Blocks.HULL

## 完整的灯塔蓝图：红白相间的塔身、观景环台、玻璃灯室、塔顶接收器
func _lighthouse_blueprint() -> Array:
	var bp: Array = []
	for y in range(G, G + LH_H):
		var t := float(y - G) / LH_H
		var r := lerpf(LH_R + 0.3, LH_R - 1.0, t)
		for dz in range(-LH_R, LH_R + 1):
			for dx in range(-LH_R, LH_R + 1):
				var d := Vector2(dx, dz).length()
				if d > r or d < r - 1.3:
					continue
				if y < G + 3 and dx <= -LH_R + 1 and absi(dz) <= 1:
					continue      # 门洞
				bp.append([Vector3i(D_C.x + dx, y, D_C.y + dz), _lh_block(y)])
	var top := G + LH_H
	# 观景环台
	for dz in range(-LH_R - 1, LH_R + 2):
		for dx in range(-LH_R - 1, LH_R + 2):
			var d := Vector2(dx, dz).length()
			if d <= LH_R + 1.2 and d > LH_R - 2.0:
				bp.append([Vector3i(D_C.x + dx, top, D_C.y + dz), Blocks.METAL])
			if d <= LH_R + 1.2 and d > LH_R + 0.4:
				bp.append([Vector3i(D_C.x + dx, top + 1, D_C.y + dz), Blocks.HULL_DARK if (dx + dz) % 2 else Blocks.LAMP])
	# 灯室
	for y in range(top + 1, top + 5):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if maxi(absi(dx), absi(dz)) == 2:
					bp.append([Vector3i(D_C.x + dx, y, D_C.y + dz), Blocks.GLASS])
	bp.append([Vector3i(D_C.x, top + 1, D_C.y), Blocks.LAMP])
	bp.append([Vector3i(D_C.x, top + 2, D_C.y), Blocks.LAMP])
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			bp.append([Vector3i(D_C.x + dx, top + 5, D_C.y + dz), Blocks.HULL_DARK])
	bp.append([Vector3i(D_C.x, top + 6, D_C.y), Blocks.HULL_DARK])
	bp.append([Vector3i(D_C.x, top + 7, D_C.y), Blocks.RECEIVER_ON])
	return bp

## 灯塔从锈海里一块块飞回来
func _build_lighthouse(instant: bool) -> void:
	if lighthouse_built:
		return
	lighthouse_built = true
	var bp := _lighthouse_blueprint()
	var top := Vector3i(D_C.x, G + LH_H + 7, D_C.y)
	if instant:
		for b in bp:
			world.set_block(b[0], b[1])
		tower_beam(top)
		_make_goal()
		return
	var rb := VoxelRebuilder.new()
	rb.world = world
	rb.pitch_base = 0.7
	add_child(rb)
	var center := world.voxel_center(Vector3i(D_C.x, G, D_C.y))
	var i := 0
	for b in bp:
		var c: Vector3i = b[0]
		var to := world.voxel_center(c)
		var out := Vector3(to.x - center.x, 0, to.z - center.z)
		out = out.normalized() if out.length() > 0.1 else Vector3.RIGHT
		var from := Vector3(to.x, SEA_LOW - 1.0, to.z) + out * rng.randf_range(6.0, 14.0)
		rb.add_cell(c, int(b[1]), 0, to, from, float(c.y - G) * 0.11 + rng.randf_range(0.0, 0.3), rng.randf_range(0.9, 1.4))
		i += 1
	rb.finished.connect(func() -> void:
		tower_beam(top)
		Sfx.play("rebuild_done", Vector3.INF, 0.0, 0.0, 0.7)
		GameState.shake.emit(0.5)
		GameState.say("……灯塔重新亮了。第五座重构塔——五座，全部点亮了。PIX……看东北方，方舟星核在回应。")
		if sea:
			sea.purify(12.0)
		_make_goal())

func _make_goal() -> void:
	var goal := zone(Goal, Vector3i(D_C.x - LH_R - 3, G, D_C.y - 2), Vector3i(D_C.x - LH_R, G + 3, D_C.y + 2)) as Goal
	goal.line = "五座塔都亮了。锈海的颜色……好像变浅了一点。PIX，最后一站：方舟星核。"
	GameState.set_objective(10, "走进灯塔", _v(Vector3i(D_C.x - LH_R - 1, G, D_C.y)))

# ================================================================ 机关、敌人、对话

func _logic() -> void:
	sea.tide_changed.connect(func(rising: bool) -> void:
		if rising and not boss_started:
			var p := GameState.player as Node3D
			if p and p.global_position.y < GW * VoxelWorld.CELL_M + 1.2:
				GameState.say("汽笛响了——要涨潮了！快上高处！"))
	# 重建栈桥（必经）
	bridge_site = rebuild_bridge("rs_bridge", BRIDGE_A, BRIDGE_B, 150, Vector3i(PIER.x + 1, G, PIER.y), "栈桥")
	bridge_site.rebuilt.connect(func() -> void:
		if not boss_done:
			GameState.say("栈桥重建好了！对面就是灯塔岛——小心，海里有东西在动。")
			GameState.set_objective(3, "去灯塔岛", _v(Vector3i(D_C.x - 8, G, D_C.y))))
	# 选做的重构点
	# 塔吊旁边的瞭望台：建好以后从塔顶用气泡形态跳上塔吊横臂（噗噗在上面）
	rebuild_tower_at("rs_t1", Vector3i(C_C.x + 2, G, C_C.y + 15), 200, 20)
	rebuild_tower("rs_t2", E_C.x + 2, E_C.y + 6, 250, 14, {"coins": 40, "energy": 6})
	# 敌人
	spawn_enemy(Spikeshell.new(), Vector3i(A_C.x - 6, G, A_C.y + 12))
	spawn_enemy(Spikeshell.new(), Vector3i(A_C.x + 10, G, A_C.y + 10))
	spawn_enemy(Rustfly.new(), Vector3i(A_C.x + 4, G + 6, A_C.y + 6), 2.0)
	spawn_enemy(Burrower.new(), Vector3i(56, G + 2, 121))
	spawn_enemy(Scrapling.new(), Vector3i(C_C.x - 8, G, C_C.y + 4))
	spawn_enemy(Scrapling.new(), Vector3i(C_C.x + 6, G, C_C.y - 2))
	spawn_enemy(Sentinel.new(), Vector3i(C_C.x + 8, G, C_C.y + 6))
	spawn_enemy(Rustfly.new(), Vector3i(C_C.x, G + 8, C_C.y), 2.0)
	spawn_enemy(Rustfly.new(), Vector3i(C_C.x + 12, G + 10, C_C.y - 6), 2.0)
	var mo := spawn_enemy(Mortar.new(), Vector3i(C_C.x - 6, G + 13, C_C.y - 4)) as Mortar
	if mo:
		mo.reach = 15.0
	spawn_enemy(Spikeshell.new(), Vector3i(E_C.x - 4, G, E_C.y + 8))
	spawn_enemy(Burrower.new(), Vector3i(E_C.x + 6, G, E_C.y - 6))
	# 收集品
	seed_at("rs_s1", Vector3i(A_C.x, G, A_C.y + 1), 0)                 # 希望号船舱里
	seed_at("rs_s2", Vector3i(C_C.x - 4, G + 2, C_C.y - 4), 1)         # 侧翻货轮的肚子里
	seed_at("rs_s3", Vector3i(E_C.x - 2, G + 4, E_C.y - 2), 2)         # 沉没客轮的客舱
	seed_at("rs_s4", Vector3i(C_C.x + 1, G + 23, C_C.y + 11), 3)       # 塔吊横臂上
	fragment("rs_1", Vector3i(A_C.x - 10, G + 7, A_C.y - 4), "艾拉·林，研究日志 #12：船队抵达锈海的第一天。海是蓝的。大家在甲板上唱歌。")
	fragment("rs_2", Vector3i(C_C.x - 14, G, C_C.y + 12), "艾拉·林，研究日志 #301：锈蚀是从海里开始的。它会“吃掉”结构，也会吃掉结构原来的样子——除非有人记得。")
	fragment("rs_3", Vector3i(E_C.x + 6, G, E_C.y + 2), "艾拉·林，最后的日志：重构需要一个记得一切的人。NOVA 记得。我把我自己也放进去了。")
	zone(TreasureChest, Vector3i(A_C.x - 11, G + 7, A_C.y - 4), Vector3i(A_C.x - 11, G + 8, A_C.y - 4), {"chest_id": "rs_bridge_room", "coins": 25, "energy": 3, "line": "舰桥里的宝箱！"})
	zone(TreasureChest, Vector3i(E_C.x - 4, G + 4, E_C.y - 2), Vector3i(E_C.x - 4, G + 5, E_C.y - 2), {"chest_id": "rs_liner", "coins": 40, "energy": 5})
	coin_line(Vector3i(48, GW, 125), Vector3i(70, GW, 107), 8)
	coin_line(Vector3i(27, GW, 106), Vector3i(30, GW, 90), 6)
	# 检查点
	checkpoint(SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	checkpoint(Vector3i(55, G + 2, 120), Vector3i(58, G + 5, 123))
	checkpoint(Vector3i(66, G + 2, 110), Vector3i(68, G + 5, 112))
	checkpoint(Vector3i(C_C.x - 20, G, C_C.y + 2), Vector3i(C_C.x - 16, G + 3, C_C.y + 6))
	checkpoint(Vector3i(PIER.x - 2, G, PIER.y - 2), Vector3i(PIER.x + 2, G + 3, PIER.y + 2))
	checkpoint(Vector3i(28, G + 2, 98), Vector3i(31, G + 5, 101))
	checkpoint(Vector3i(D_C.x - D_R + 1, G, D_C.y - 2), Vector3i(D_C.x - D_R + 4, G + 3, D_C.y + 2))
	# 对话
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"锈海。……以前这里是一片蓝色的海，殖民船队就停在这儿。",
		"最后一座重构塔是海中央的旧灯塔。你看——只剩一截塔基了。",
		"这艘是“希望号”，当年的旗舰。它已经锈透了——想拆就拆吧，拆下来的都会变成重构物质。",
	])
	talk(Vector3i(44, GW, 122), Vector3i(50, GW + 4, 130), [
		"前面是潮汐浅滩。步道只在低潮时露出来——汽笛一响就要涨潮了，赶紧躲到礁柱上。",
	])
	talk(Vector3i(C_C.x - 22, G, C_C.y - 4), Vector3i(C_C.x - 16, G + 4, C_C.y + 8), [
		"沉船墓场。这里的锈铁比别处的都厚——普通冲刺撞不开，要原地蓄力再冲。",
		"去灯塔的栈桥断了。在这儿多拆点东西，攒够物质就能把它重建起来。",
	])
	talk(Vector3i(PIER.x - 3, G, PIER.y - 3), Vector3i(PIER.x + 3, G + 4, PIER.y + 3), [
		"栈桥的蓝图在这儿。滚进光圈就能重建——需要 150 个重构物质。",
	])
	# 目标
	GameState.set_objective(0, "穿过潮汐浅滩去沉船墓场（汽笛响了就躲到礁柱上）", _v(Vector3i(C_C.x - 18, G, C_C.y + 4)))
	objective(1, "攒够重构物质，重建去灯塔岛的栈桥（◆150）", Vector3i(PIER.x + 1, G, PIER.y), Vector3i(C_C.x - 22, G, C_C.y - 4), Vector3i(C_C.x - 16, G + 4, C_C.y + 8))
	_setup_boss()

var boss_started := false

func _setup_boss() -> void:
	worm = RustWorm.new()
	worm.center = world.voxel_center(Vector3i(D_C.x, 0, D_C.y))
	worm.center.y = SEA_LOW
	worm.sea_y = SEA_LOW
	worm.island_r = D_R * VoxelWorld.CELL_M
	worm.rest_y = SEA_LOW + 0.9
	var R := D_R * VoxelWorld.CELL_M + 1.3
	var c := worm.center
	for deg in [205.0, 320.0, 85.0]:
		var a := deg_to_rad(deg)
		var tp := c + Vector3(cos(a), 0, sin(a)) * R
		var tan := Vector3(-sin(a), 0, cos(a))
		tp.y = SEA_LOW + 0.9
		worm.rest_lines.append([tp - tan * 10.0, tp + tan * 10.0])
	add_child(worm)
	worm.defeated.connect(_on_boss_defeated)
	worm.core_broken.connect(func(left: int) -> void:
		reconstruct(worm.center + Vector3.UP * 3.0, 20.0, 2.5)
		if left == 2:
			GameState.say("碎了一颗！它钻回去了——看，岛上被啃掉的地方又长回来了。")
		elif left == 1:
			GameState.say("还剩最后一颗锈核！"))
	var trig := zone(Zone, Vector3i(D_C.x - D_R + 2, G, D_C.y - D_R), Vector3i(D_C.x + D_R, G + 6, D_C.y + D_R))
	trig.player_entered.connect(func() -> void:
		if is_instance_valid(worm) and not worm.active and not boss_done:
			if not ChapterKey.unseal(self, worm, "rust"):
				return
			boss_started = true
			sea.set_calm(SEA_LOW)
			worm.start()
			Music.play_area("boss")
			Music.set_override("explore")
			GameState.say("海在翻——是锈海吞噬者！它会跃出来啃掉岛边。等它趴下喘气的时候，滚上它的背，撞碎发光的锈核！"))

func _on_boss_defeated(_e: Node) -> void:
	boss_done = true
	SaveGame.set_flag("rs_boss")
	Music.play_area("rs")
	Music.set_override("bright")
	reconstruct(world.voxel_center(Vector3i(D_C.x, G, D_C.y)), 120.0, 8.0)
	GameState.say("它散架了……锈海安静下来了。现在——把灯塔建回去！")
	get_tree().create_timer(2.5).timeout.connect(func() -> void: _build_lighthouse(false))

func _apply_flags(flags: Dictionary) -> void:
	if bool(flags.get("rs_boss", false)):
		if is_instance_valid(worm):
			worm.queue_free()
		boss_done = true
		boss_started = true
		if sea:
			sea.set_calm(SEA_LOW)
		_build_lighthouse(true)
		if sea:
			sea.purify(0.0, true)

func arrival_shots() -> Array:
	var V := VoxelWorld.CELL_M
	return [
		{"from": Vector3(-40, 60, 200) * V, "to": Vector3(-10, 50, 170) * V, "look": Vector3(80, 20, 90) * V, "dur": 6.0, "fade": Color.BLACK,
			"lines": [["NOVA", "锈海。星球上最大的海。"], ["NOVA", "……以前它是蓝色的。"]]},
		{"from": Vector3(170, 50, 30) * V, "to": Vector3(165, 45, 45) * V, "look": Vector3(D_C.x, G + 8, D_C.y) * V, "dur": 5.0,
			"lines": [["NOVA", "最后一座重构塔：海中央的旧灯塔。它被什么东西啃坏了。"]]},
		{"from": Vector3(4, 30, 152) * V, "to": Vector3(8, 26, 148) * V, "look": Vector3(SPAWN) * V, "dur": 4.0,
			"lines": [["NOVA", "从希望号的残骸出发。"]]},
	]
