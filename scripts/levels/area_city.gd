class_name AreaCity
extends ChapterLevel
## 第四章 · 云顶之城：殖民地的首都，一座座白色的浮岛城区，用磁悬浮空中轨道连在一起。
## 被救出来的噗噗们已经回到了这里。第四座重构塔就是议会大厦顶上的尖塔。
##
## 路线（格坐标，1 格 = 0.5 米）：
##   A 抵达台（出生，噗噗镇长）→ 空中轨道 1 → B 集市
##   B 集市：玻璃穹顶、摊位、锈哨兵。通往公园的轨道断电——从穹顶里取出保险晶，插进车站的插槽
##     （集市北边的弹射炮能飞到上空的空中花园：宝箱 + 噗噗）
##   → 空中轨道 2（中间断开一截，跳过去）→ C 公园：风车、侧风、钻地鼹
##   → 旋转桥：从公园滚到桥中间的转盘上，撞转钮，整座桥转 90° 接上议会广场
##   D 议会广场：Boss「锈蚀巡逻艇」——从四角的弹射炮飞上去撞它的发动机
##   → 打下飞艇，议会尖塔亮起来

const SIZE := Vector3i(144, 112, 144)
const GA := 56
const GB := 60
const GC := 72
const GD := 72
const A_C := Vector2i(18, 118)
const B_C := Vector2i(48, 104)
const C_C := Vector2i(96, 72)
const D_C := Vector2i(58, 44)
const E_C := Vector2i(40, 74)            ## 空中花园
const GE := 86
const HUB := Vector2i(96, 44)            ## 旋转桥转盘
const SPAWN := Vector3i(14, GA, 120)
const DOME_B := Vector3i(44, GB, 98)     ## 集市大穹顶
const SPIRE := Vector3i(58, GD, 30)      ## 议会尖塔底部中心
const SPIRE_H := 20
const FUSE_SOCKET := Vector3i(64, GB, 100)

var _n := FastNoiseLite.new()
var rails: Array[SkyRail] = []
var rail2: Array[SkyRail] = []
var bridge: TurnBridge
var airship: RustAirship
var boss_done := false
var grid: PowerGrid
var socket: ItemSocket
var fuse: UsableItem

func _init() -> void:
	chapter_id = "city"
	forms_at_start = [true, true, true] as Array[bool]
	kill_height = 2.0

func spawn_cell() -> Vector3i:
	return SPAWN

func spawn_yaw() -> float:
	return -PI / 2.0 - 0.4

# ================================================================ 搭建

func _build_world() -> void:
	world.setup(SIZE)
	rng.seed = 4404
	_n.seed = 44
	_n.frequency = 0.08
	if not backdrop:
		Atmosphere.apply(self, "city")
	_island(A_C, 13.0, GA, Blocks.GRASS)
	_island(B_C, 17.0, GB, Blocks.GRASS)
	_island(C_C, 15.0, GC, Blocks.GRASS)
	_island(D_C, 25.0, GD, Blocks.GRASS)
	_island(E_C, 7.0, GE, Blocks.GRASS)
	_hub()
	_arrival()
	_market()
	_park()
	_capitol()
	_sky_garden()
	world.naturalize(GD + 10, [
		AABB(Vector3(A_C.x - 10, 0, A_C.y - 10), Vector3(20, 112, 20)),
		AABB(Vector3(B_C.x - 16, 0, B_C.y - 16), Vector3(32, 112, 32)),
		AABB(Vector3(D_C.x - 24, 0, D_C.y - 24), Vector3(48, 112, 48)),
		AABB(Vector3(C_C.x - 10, 0, C_C.y - 16), Vector3(20, 112, 20)),
	])
	world.rebuild_all()
	scatter_decor(Vector3i(0, GA - 2, 0), Vector3i(SIZE.x - 1, GE + 4, SIZE.z - 1), 0.22, 0.08, 0.02)
	decor.commit()
	_dress()
	world.flush_dirty()
	vista = Vistas.city(self, world)
	_rails()

## 一座浮岛：平顶（白色铺装的广场 + 边上一圈草），倒锥形的岛底
func _island(c: Vector2i, r: float, g: int, top: int) -> void:
	for z in range(c.y - int(r) - 4, c.y + int(r) + 5):
		for x in range(c.x - int(r) - 4, c.x + int(r) + 5):
			var dv := Vector2(x - c.x, z - c.y)
			var ang := atan2(dv.y, dv.x)
			var rr := r * (0.92 + 0.1 * _n.get_noise_2d(cos(ang) * 30.0 + c.x, sin(ang) * 30.0 + c.y))
			var d := dv.length()
			if d > rr:
				continue
			var t := d / rr
			var depth := 4 + int((r * 1.1) * pow(1.0 - t, 0.8)) + int(_n.get_noise_2d(x * 3.0, z * 3.0) * 2.0)
			_set_h(x, z, g)
			var bottom := g - depth
			var off := _n.get_noise_2d(x * 1.3, z * 1.3) * 3.0
			var y := bottom
			while y <= g - 4:
				var band := posmod(int(floor((y + off) / 4.0)), 3)
				var y_end := mini(g - 4, int(floor((floor((y + off) / 4.0) + 1.0) * 4.0 - off - 0.001)))
				world.fill_column(x, z, y, maxi(y_end, y), [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C][band])
				y = maxi(y_end, y) + 1
			world.fill_column(x, z, g - 3, g - 2, Blocks.DIRT)
			world.fill_column(x, z, g - 1, g - 1, top if t > 0.82 else Blocks.TILE if (x + z) % 6 else Blocks.PAVING)

## 旋转桥的转盘柱：从云里立起来的一根白色石柱
func _hub() -> void:
	var c := HUB
	for y in range(GD - 30, GD):
		var r := 2.4 if y > GD - 4 else 1.6 + 0.3 * sin(y * 0.6)
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if Vector2(dx, dz).length() <= r:
					world.fill_box(Vector3i(c.x + dx, y, c.y + dz), Vector3i(c.x + dx, y, c.y + dz), Blocks.HULL if y % 6 else Blocks.HULL_DARK)
	# 两端的落脚台：公园北边、议会广场东边
	for z in range(C_C.y - 17, C_C.y - 12):
		for x in range(c.x - 2, c.x + 3):
			if h_at(x, z) < 0:
				world.fill_box(Vector3i(x, GC - 3, z), Vector3i(x, GC - 1, z), Blocks.PAVING)
				_set_h(x, z, GC)
	for z in range(c.y - 2, c.y + 3):
		for x in range(D_C.x + 21, D_C.x + 27):
			if h_at(x, z) < 0:
				world.fill_box(Vector3i(x, GD - 3, z), Vector3i(x, GD - 1, z), Blocks.PAVING)
				_set_h(x, z, GD)

func building(a: Vector3i, b: Vector3i, wall: int, roof: int, windows := true) -> void:
	var lo := Vector3i(mini(a.x, b.x), a.y, mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), b.y, maxi(a.z, b.z))
	world.fill_box(lo, hi, wall)
	if windows:
		for y in range(lo.y + 2, hi.y, 3):
			for x in range(lo.x + 1, hi.x, 2):
				world.fill_box(Vector3i(x, y, lo.z), Vector3i(x, y, lo.z), Blocks.GLASS)
				world.fill_box(Vector3i(x, y, hi.z), Vector3i(x, y, hi.z), Blocks.GLASS)
			for z in range(lo.z + 1, hi.z, 2):
				world.fill_box(Vector3i(lo.x, y, z), Vector3i(lo.x, y, z), Blocks.GLASS)
				world.fill_box(Vector3i(hi.x, y, z), Vector3i(hi.x, y, z), Blocks.GLASS)
	# 斜屋顶（两层台阶）
	world.fill_box(Vector3i(lo.x - 1, hi.y + 1, lo.z - 1), Vector3i(hi.x + 1, hi.y + 1, hi.z + 1), roof)
	world.fill_box(Vector3i(lo.x + 1, hi.y + 2, lo.z + 1), Vector3i(hi.x - 1, hi.y + 2, hi.z - 1), roof)

func dome(c: Vector3i, r: int, frame: int, glass := Blocks.GLASS) -> void:
	for z in range(c.z - r - 1, c.z + r + 2):
		for y in range(c.y, c.y + r + 2):
			for x in range(c.x - r - 1, c.x + r + 2):
				var d := Vector3(x - c.x, y - c.y, z - c.z).length()
				if absf(d - r) <= 0.55:
					var rib := x == c.x or z == c.z or (y - c.y) % 4 == 0
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), frame if rib else glass)

# ================================================================ A 抵达台

func _arrival() -> void:
	var c := A_C
	# 车站：一块白色站台 + 顶棚
	world.fill_box(Vector3i(c.x + 6, GA, c.y - 4), Vector3i(c.x + 6, GA + 4, c.y - 4), Blocks.HULL)
	world.fill_box(Vector3i(c.x + 6, GA, c.y + 1), Vector3i(c.x + 6, GA + 4, c.y + 1), Blocks.HULL)
	world.fill_box(Vector3i(c.x + 3, GA + 5, c.y - 5), Vector3i(c.x + 10, GA + 5, c.y + 2), Blocks.GLASS)
	world.fill_box(Vector3i(c.x + 3, GA + 5, c.y - 5), Vector3i(c.x + 10, GA + 5, c.y - 5), Blocks.HULL_DARK)
	building(Vector3i(c.x - 9, GA, c.y - 9), Vector3i(c.x - 3, GA + 6, c.y - 4), Blocks.HULL, Blocks.TILE)
	for l in [Vector3i(c.x - 2, GA, c.y + 6), Vector3i(c.x + 4, GA, c.y + 6)]:
		lamp_post(l, 4)

# ================================================================ B 集市

func _market() -> void:
	var c := B_C
	# 大穹顶（里面放着保险晶，玻璃要冲刺才撞得开）
	dome(DOME_B, 7, Blocks.HULL)
	world.fill_box(DOME_B + Vector3i(-1, 0, -1), DOME_B + Vector3i(1, 0, 1), Blocks.PAVING)
	world.fill_box(DOME_B + Vector3i(0, 0, 0), DOME_B + Vector3i(0, 0, 0), Blocks.CRATE_ITEM)
	# 小穹顶（噗噗们在里面）
	dome(Vector3i(c.x + 6, GB, c.y + 9), 4, Blocks.HULL_DARK)
	for k in 3:
		world.fill_box(Vector3i(c.x + 5 + k, GB, c.y + 13), Vector3i(c.x + 5 + k, GB + 1, c.y + 13), Blocks.AIR)
	# 摊位和楼
	building(Vector3i(c.x + 4, GB, c.y - 14), Vector3i(c.x + 10, GB + 9, c.y - 9), Blocks.TILE, Blocks.HULL_DARK)
	building(Vector3i(c.x - 14, GB, c.y + 2), Vector3i(c.x - 9, GB + 7, c.y + 8), Blocks.HULL, Blocks.RUST)
	for k in 4:
		var sx := c.x - 6 + k * 4
		world.fill_box(Vector3i(sx, GB, c.y + 3), Vector3i(sx + 2, GB, c.y + 4), Blocks.CRATE)
		world.fill_box(Vector3i(sx, GB + 3, c.y + 2), Vector3i(sx + 2, GB + 3, c.y + 5), Blocks.PLANK if k % 2 else Blocks.RUST)
		world.fill_box(Vector3i(sx, GB, c.y + 2), Vector3i(sx, GB + 2, c.y + 2), Blocks.HULL_DARK)
	# 车站（去公园的轨道起点）+ 发电机与保险插槽
	world.fill_box(Vector3i(c.x + 13, GB, c.y - 3), Vector3i(c.x + 13, GB + 4, c.y - 3), Blocks.HULL)
	world.fill_box(Vector3i(c.x + 13, GB + 5, c.y - 4), Vector3i(c.x + 17, GB + 5, c.y + 2), Blocks.GLASS)
	world.fill_box(Vector3i(c.x + 8, GB - 1, c.y - 6), Vector3i(c.x + 8, GB - 1, c.y - 6), Blocks.SOURCE)
	world.fill_box(Vector3i(c.x + 8, GB, c.y - 6), Vector3i(c.x + 8, GB, c.y - 6), Blocks.HULL_DARK)
	# 金属管线：发电机 → 插槽缺口 → 车站接收器
	world.fill_box(Vector3i(c.x + 9, GB - 1, c.y - 6), Vector3i(FUSE_SOCKET.x - 1, GB - 1, c.y - 6), Blocks.METAL)
	world.fill_box(Vector3i(FUSE_SOCKET.x - 1, GB - 1, c.y - 5), Vector3i(FUSE_SOCKET.x - 1, GB - 1, FUSE_SOCKET.z), Blocks.METAL)
	world.fill_box(Vector3i(FUSE_SOCKET.x, GB - 1, FUSE_SOCKET.z), Vector3i(FUSE_SOCKET.x, GB - 1, FUSE_SOCKET.z), Blocks.AIR)
	world.fill_box(Vector3i(FUSE_SOCKET.x + 1, GB - 1, FUSE_SOCKET.z), Vector3i(FUSE_SOCKET.x + 1, GB - 1, FUSE_SOCKET.z + 2), Blocks.METAL)
	world.fill_box(Vector3i(FUSE_SOCKET.x + 1, GB - 1, FUSE_SOCKET.z + 3), Vector3i(FUSE_SOCKET.x + 1, GB - 1, FUSE_SOCKET.z + 3), Blocks.RECEIVER)
	# 北边的弹射炮底座
	world.fill_box(Vector3i(c.x - 2, GB - 1, c.y - 14), Vector3i(c.x + 2, GB - 1, c.y - 10), Blocks.HULL_DARK)
	# 藏宝：摊位后面一堆木箱
	world.fill_box(Vector3i(c.x - 12, GB, c.y - 8), Vector3i(c.x - 10, GB + 2, c.y - 6), Blocks.CRATE)

# ================================================================ C 公园

func _park() -> void:
	var c := C_C
	# 风车：石头塔身 + 顶上的平台（叶片是转动的网格，装饰）
	var m := Vector3i(c.x + 5, GC, c.y + 4)
	for y in range(GC, GC + 12):
		var r := 2.2 - (y - GC) * 0.08
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if Vector2(dx, dz).length() <= r:
					world.fill_box(Vector3i(m.x + dx, y, m.z + dz), Vector3i(m.x + dx, y, m.z + dz), Blocks.PAVING if y % 4 else Blocks.MOSS)
	world.fill_box(Vector3i(m.x - 2, GC + 12, m.z - 2), Vector3i(m.x + 2, GC + 12, m.z + 2), Blocks.PLANK)
	world.fill_box(Vector3i(m.x, GC, m.z + 2), Vector3i(m.x, GC + 1, m.z + 2), Blocks.AIR)
	# 树和花坛
	for k in 7:
		var a := k * TAU / 7.0
		var cell := Vector3i(int(c.x + cos(a) * 9.0), GC, int(c.y + sin(a) * 9.0))
		if h_at(cell.x, cell.z) == GC:
			tree(cell, rng.randi_range(4, 6), rng.randf_range(1.8, 2.4), "blossom" if k % 3 == 0 else "round")
	# 小池塘（玻璃水面）
	for z in range(c.y - 3, c.y + 1):
		for x in range(c.x - 6, c.x - 1):
			world.fill_box(Vector3i(x, GC - 1, z), Vector3i(x, GC - 1, z), Blocks.GLASS)
			world.fill_box(Vector3i(x, GC - 2, z), Vector3i(x, GC - 2, z), Blocks.CRYSTAL)

# ================================================================ D 议会广场

func _capitol() -> void:
	var c := D_C
	# 议会大厦：北边一座带大穹顶的白楼
	building(Vector3i(c.x - 10, GD, c.y - 20), Vector3i(c.x + 10, GD + 8, c.y - 11), Blocks.HULL, Blocks.TILE)
	dome(Vector3i(SPIRE.x, GD + 10, SPIRE.z), 6, Blocks.HULL_DARK, Blocks.GLASS)
	# 尖塔（第四座重构塔）
	for y in range(GD + 16, GD + 16 + SPIRE_H):
		var r := 1 if y < GD + 16 + SPIRE_H - 6 else 0
		world.fill_box(Vector3i(SPIRE.x - r, y, SPIRE.z - r), Vector3i(SPIRE.x + r, y, SPIRE.z + r), Blocks.HULL if y % 5 else Blocks.CRYSTAL)
	for ry in [GD + 24, GD + 34]:
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dz)) == 3:
					world.fill_box(Vector3i(SPIRE.x + dx, ry, SPIRE.z + dz), Vector3i(SPIRE.x + dx, ry, SPIRE.z + dz), Blocks.LAMP if absi(dx) == 3 and absi(dz) == 3 else Blocks.HULL)
	world.fill_box(Vector3i(SPIRE.x, GD + 16 + SPIRE_H, SPIRE.z), Vector3i(SPIRE.x, GD + 16 + SPIRE_H, SPIRE.z), Blocks.RECEIVER)
	# 大门台阶
	world.fill_box(Vector3i(c.x - 3, GD, c.y - 11), Vector3i(c.x + 3, GD + 3, c.y - 11), Blocks.AIR)
	world.fill_box(Vector3i(c.x - 4, GD + 4, c.y - 11), Vector3i(c.x + 4, GD + 4, c.y - 10), Blocks.HULL_DARK)
	# 广场：一圈矮栏 + 四角的弹射炮底座
	for key in heights.keys():
		if heights[key] != GD:
			continue
		var x: int = key.x
		var z: int = key.y
		if Vector2(x - c.x, z - c.y).length() > 26.0:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if h_at(x + d.x, z + d.y) < 0:
				if absi(z - HUB.y) <= 2 and x > c.x:
					break
				world.fill_box(Vector3i(x, GD, z), Vector3i(x, GD, z), Blocks.HULL if (x + z) % 4 else Blocks.LAMP)
				break
	for a in [0.785, 2.356, 3.927, 5.498]:
		var cx := int(c.x + cos(a) * 17.0)
		var cz := int(c.y + 12 + sin(a) * 17.0 * 0.6)
		world.fill_box(Vector3i(cx - 1, GD - 1, cz - 1), Vector3i(cx + 1, GD - 1, cz + 1), Blocks.HULL_DARK)
	# 广场中央的喷泉（晶石）
	for z in range(c.y + 5, c.y + 12):
		for x in range(c.x - 3, c.x + 4):
			if Vector2(x - c.x, z - c.y - 8).length() < 3.5:
				world.fill_box(Vector3i(x, GD - 1, z), Vector3i(x, GD - 1, z), Blocks.GLASS)
	world.fill_box(Vector3i(c.x, GD, c.y + 8), Vector3i(c.x, GD + 2, c.y + 8), Blocks.CRYSTAL)

func _sky_garden() -> void:
	var c := E_C
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		tree(Vector3i(int(c.x + cos(a) * 4.0), GE, int(c.y + sin(a) * 4.0)), 4, 1.6, "blossom")

# ================================================================ 空中轨道

func _rail(points: Array, powered := true) -> SkyRail:
	var r := SkyRail.new()
	add_child(r)
	for pt in points:
		r.curve.add_point(pt * VoxelWorld.CELL_M)
	# 平滑一点：给每个点自动加切线
	for i in r.curve.point_count:
		var prev: Vector3 = r.curve.get_point_position(maxi(i - 1, 0))
		var nxt: Vector3 = r.curve.get_point_position(mini(i + 1, r.curve.point_count - 1))
		var tng := (nxt - prev) * 0.25
		if i > 0 and i < r.curve.point_count - 1:
			r.curve.set_point_in(i, -tng)
			r.curve.set_point_out(i, tng)
	r.powered = powered
	r.build_visual()
	# 支撑柱
	var L := r.curve.get_baked_length()
	var d := 3.0
	while d < L - 2.0:
		var p := r.curve.sample_baked(d)
		var cell := world.world_to_voxel(p + Vector3.DOWN * 0.6)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.18
		cm.height = 3.0
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("3d4659")
		mi.material_override = m
		add_child(mi)
		mi.global_position = p + Vector3.DOWN * 1.8
		d += 6.0
	rails.append(r)
	return r

func _rails() -> void:
	var y := 0.4
	# 轨道 1：抵达台 → 集市（中间往下俯冲一段）
	_rail([Vector3(24, GA + y, 116.5), Vector3(28, GA - 1, 114), Vector3(31, GA - 2, 110), Vector3(34, GB + y, 105)])
	# 轨道 2：集市 → 公园（一路爬升，中间断开一截）
	rail2.append(_rail([Vector3(63, GB + y, 103), Vector3(70, GB + 1, 100), Vector3(77, GB + 4, 93), Vector3(81, GB + 6, 88)], false))
	rail2.append(_rail([Vector3(84, GB + 7.5, 85), Vector3(86, GB + 10, 82), Vector3(88, GC + y, 79)], false))
	# 轨道 3（回程）：议会广场西边 → 抵达台
	_rail([Vector3(36, GD + y, 52), Vector3(31, GD - 3, 64), Vector3(24, GA + 6, 88), Vector3(20, GA + y, 109)])

# ================================================================ 布景

func _dress() -> void:
	deco("space-station/container-wide", A_C.x - 4, A_C.y + 5, 1.2)
	deco("space-station/table-display-planet", B_C.x - 2, B_C.y - 4, 0.9)
	deco("space-station/computer-wide", B_C.x + 12, B_C.y - 6, 1.0)
	deco("space-station/container", B_C.x - 8, B_C.y - 11, 1.2)
	deco("factory/screen-wide", D_C.x - 8, D_C.y - 9, 1.2)
	deco("space-station/display-wall-wide", D_C.x + 8, D_C.y - 9, 1.2)
	for p in [Vector2i(B_C.x - 4, B_C.y + 12), Vector2i(D_C.x - 14, D_C.y + 14), Vector2i(D_C.x + 14, D_C.y + 14), Vector2i(C_C.x - 6, C_C.y - 8)]:
		var cell := find_flat(p.x, p.y, 3, 1)
		if cell.y >= 0:
			tree(cell, rng.randi_range(4, 6), rng.randf_range(1.6, 2.2), "blossom" if rng.randf() < 0.5 else "round")
	for l in [Vector3i(D_C.x - 6, GD, D_C.y + 2), Vector3i(D_C.x + 6, GD, D_C.y + 2), Vector3i(D_C.x - 6, GD, D_C.y + 16), Vector3i(D_C.x + 6, GD, D_C.y + 16)]:
		lamp_post(l, 5)
	var amb := Ambient.new()
	amb.area_lo = Vector3(C_C.x - 12, GC + 1, C_C.y - 12) * VoxelWorld.CELL_M
	amb.area_hi = Vector3(C_C.x + 12, GC + 6, C_C.y + 12) * VoxelWorld.CELL_M
	amb.count = 14
	add_child(amb)

# ================================================================ 机关、敌人、对话

func _logic() -> void:
	# 风车叶片：转动的网格
	var blades := Node3D.new()
	add_child(blades)
	blades.global_position = world.voxel_center(Vector3i(C_C.x + 5, GC + 10, C_C.y + 1))
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("e9edf2")
	for k in 4:
		var b := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(0.5, 4.2, 0.1)
		b.mesh = bx
		b.material_override = bm
		b.position = Vector3(cos(k * PI / 2.0) * 2.1, sin(k * PI / 2.0) * 2.1, 0)
		b.rotation.z = k * PI / 2.0 + PI / 2.0
		blades.add_child(b)
	_mill = blades
	# 电网：发电机 → 保险插槽 → 轨道 2
	grid = PowerGrid.new()
	add_child(grid)
	grid.setup(world, Vector3i(B_C.x + 4, GB - 2, B_C.y - 10), Vector3i(FUSE_SOCKET.x + 3, GB + 2, FUSE_SOCKET.z + 5))
	for r in rail2:
		r.power_cells = [Vector3i(FUSE_SOCKET.x + 1, GB - 1, FUSE_SOCKET.z + 3)] as Array[Vector3i]
		r.is_powered = false
		grid.add_device(r)
	socket = ItemSocket.new()
	socket.accepts = "crystal"
	socket.fill_block = Blocks.CRYSTAL
	add_child(socket)
	socket.setup(world, Vector3i(FUSE_SOCKET.x, GB - 1, FUSE_SOCKET.z))
	socket.filled.connect(func() -> void:
		SaveGame.set_flag("cc_fuse")
		GameState.say("保险晶插好了——去公园的轨道亮了！")
		GameState.set_objective(3, "坐空中轨道去公园（中间断了一截，看准了跳过去）", _v(Vector3i(B_C.x + 15, GB, B_C.y - 1))))
	world.item_dropped.connect(func(id: String, pos: Vector3) -> void:
		if id == "crystal" and not is_instance_valid(fuse) and not socket.done:
			fuse = UsableItem.new()
			fuse.item_id = "crystal"
			add_child(fuse)
			fuse.global_position = pos + Vector3.UP * 0.3
			fuse.home = fuse.global_position
			GameState.say("这就是保险晶。抓起来，带到东边车站前的插槽里。")
			GameState.set_objective(2, "把保险晶放进东边车站前的插槽", _v(FUSE_SOCKET + Vector3i.UP)))
	# 旋转桥
	bridge = TurnBridge.new()
	bridge.length = 12.4
	bridge.width = 2.4
	bridge.dir = 1
	add_child(bridge)
	bridge.global_position = world.voxel_center(Vector3i(HUB.x, GD - 1, HUB.y)) + Vector3.UP * 0.05
	bridge.turned.connect(func(d: int) -> void:
		if d == 0 and not SaveGame.flag("cc_bridge"):
			SaveGame.set_flag("cc_bridge")
			GameState.say("桥接上议会广场了！"))
	zone(BouncePad, Vector3i(C_C.x + 4, GC, C_C.y + 8), Vector3i(C_C.x + 6, GC + 1, C_C.y + 10), {"launch": Vector3(0, 15.6, -1.5)})
	zone(WindZone, Vector3i(HUB.x - 3, GD, HUB.y - 12), Vector3i(HUB.x + 3, GD + 4, HUB.y + 12), {"dir": Vector3(1, 0, 0), "strength": 2.6})
	zone(WindZone, Vector3i(HUB.x - 12, GD, HUB.y - 3), Vector3i(HUB.x - 3, GD + 4, HUB.y + 3), {"dir": Vector3(0, 0, 1), "strength": 2.2, "on_time": 2.0, "off_time": 2.5})
	# 弹射炮：集市 → 空中花园
	zone(BouncePad, Vector3i(B_C.x - 1, GB, B_C.y - 13), Vector3i(B_C.x + 1, GB + 1, B_C.y - 11), {"launch": Vector3(-2.2, 18.6, -4.8)})
	# 敌人
	spawn_enemy(Sentinel.new(), Vector3i(B_C.x + 2, GB, B_C.y - 6))
	spawn_enemy(Sentinel.new(), Vector3i(B_C.x - 6, GB, B_C.y + 10))
	spawn_enemy(Scrapling.new(), Vector3i(B_C.x + 8, GB, B_C.y + 2))
	spawn_enemy(Rustfly.new(), Vector3i(B_C.x + 30, GB + 6, B_C.y - 8), 2.0)
	spawn_enemy(Burrower.new(), Vector3i(C_C.x - 4, GC, C_C.y + 6))
	spawn_enemy(Spikeshell.new(), Vector3i(C_C.x + 2, GC, C_C.y - 6))
	spawn_enemy(Sentinel.new(), Vector3i(D_C.x - 6, GD, D_C.y - 8))
	spawn_enemy(Sentinel.new(), Vector3i(D_C.x + 6, GD, D_C.y - 8))
	var mo := spawn_enemy(Mortar.new(), Vector3i(D_C.x, GD + 9, D_C.y - 13)) as Mortar
	mo.reach = 16.0
	# 噗噗居民
	_pupu(Vector3i(A_C.x - 2, GA, A_C.y + 2), 0, ["欢迎来到云顶之城！我是镇长噗噗。", "城里的锈块兽太多了，大家只敢躲在穹顶里……", "第四座塔在议会大厦顶上。坐空中轨道过去最快！"])
	_pupu(Vector3i(B_C.x + 6, GB, B_C.y + 9), 1, ["你就是救了我们的圆圆英雄吗！", "大穹顶里有一块保险晶，以前是给轨道供电的。"])
	_pupu(Vector3i(B_C.x + 5, GB, B_C.y + 8), 2, ["噗！噗噗！（在给你鼓掌）"])
	_pupu(Vector3i(B_C.x + 7, GB, B_C.y + 10), 3, ["听说北边的弹射炮能把人弹到天上的花园去！"])
	_pupu(Vector3i(C_C.x - 2, GC, C_C.y + 2), 4, ["风车顶上视野最好了……不过我跳不上去。", "公园北边那座桥老是被风吹得转来转去。"])
	# 种子方块
	seed_at("cc_s1", Vector3i(A_C.x + 3, GA, A_C.y + 7), 0)
	seed_at("cc_s2", Vector3i(E_C.x, GE, E_C.y), 1)
	seed_at("cc_s3", Vector3i(C_C.x + 5, GC + 13, C_C.y + 4), 2)
	seed_at("cc_s4", Vector3i(D_C.x - 9, GD + 11, D_C.y - 16), 3)
	fragment("cc_1", DOME_B + Vector3i(3, 0, 3), "艾拉·林，研究日志 #150：议会问我，重构以后的城市会不会和原来一模一样。我说会。其实我也不知道。")
	fragment("cc_2", Vector3i(C_C.x - 8, GC, C_C.y - 2), "艾拉·林，研究日志 #388：NOVA 的人格模块今天通过了测试。它说话的样子……有点像我。大概是我写的时候太偷懒了。")
	fragment("cc_3", Vector3i(D_C.x - 12, GD, D_C.y + 4), "艾拉·林，最后的备忘：如果我没有回来，让 NOVA 替我看着。它比我勇敢。")
	zone(TreasureChest, Vector3i(E_C.x + 2, GE, E_C.y - 2), Vector3i(E_C.x + 2, GE + 1, E_C.y - 2), {"chest_id": "cc_garden", "coins": 35, "energy": 5, "line": "空中花园的宝箱！这里能看到整座城。"})
	zone(TreasureChest, Vector3i(B_C.x - 11, GB, B_C.y - 7), Vector3i(B_C.x - 11, GB + 1, B_C.y - 7), {"chest_id": "cc_market", "coins": 25, "energy": 3})
	world.fill_box(Vector3i(B_C.x - 11, GB, B_C.y - 7), Vector3i(B_C.x - 11, GB + 1, B_C.y - 7), Blocks.AIR)
	# 检查点
	checkpoint(SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	checkpoint(Vector3i(B_C.x - 14, GB, B_C.y - 1), Vector3i(B_C.x - 11, GB + 3, B_C.y + 2))
	checkpoint(Vector3i(B_C.x + 10, GB, B_C.y - 3), Vector3i(B_C.x + 13, GB + 3, B_C.y))
	checkpoint(Vector3i(C_C.x - 12, GC, C_C.y + 2), Vector3i(C_C.x - 9, GC + 3, C_C.y + 5))
	checkpoint(Vector3i(C_C.x - 2, GC, C_C.y - 14), Vector3i(C_C.x + 2, GC + 3, C_C.y - 11))
	checkpoint(Vector3i(D_C.x + 19, GD, D_C.y - 2), Vector3i(D_C.x + 22, GD + 3, D_C.y + 2))
	# 对话
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"云顶之城——殖民地的首都。你救出来的噗噗们，都回到这里了。",
		"第四座塔就在议会大厦的尖顶上。这里的浮岛之间靠空中轨道连着——滚到车站的轨道上，它会把你吸住带走。",
	])
	talk(Vector3i(A_C.x + 3, GA, A_C.y - 6), Vector3i(A_C.x + 9, GA + 4, A_C.y + 2), [
		"在轨道上按{boost}会更快，按{jump}随时可以跳下来。",
	])
	talk(Vector3i(B_C.x - 16, GB, B_C.y - 4), Vector3i(B_C.x - 10, GB + 4, B_C.y + 6), [
		"小心那些探照灯——锈哨兵。被光照到会拉警报，放出锈蜂。躲开光，从背后撞它。",
	])
	talk(Vector3i(B_C.x + 9, GB, B_C.y - 5), Vector3i(B_C.x + 15, GB + 4, B_C.y + 2), [
		"去公园的轨道断电了。车站前的插槽缺一块保险晶……大穹顶里好像有。穹顶的玻璃要加速才撞得开。",
	])
	talk(Vector3i(C_C.x - 3, GC, C_C.y - 14), Vector3i(C_C.x + 3, GC + 4, C_C.y - 10), [
		"桥被风吹得转偏了。滚到桥中间，撞一下那个发光的转钮，桥会转 90°。",
		"桥上有阵风——气泡形态太轻，小心被吹下去。",
	])
	# 目标
	GameState.set_objective(0, "坐空中轨道去集市", _v(Vector3i(A_C.x + 6, GA, A_C.y - 1)))
	objective(1, "给去公园的轨道找一块保险晶（看看大穹顶里）", DOME_B, Vector3i(B_C.x - 16, GB, B_C.y - 4), Vector3i(B_C.x - 10, GB + 4, B_C.y + 6))
	objective(4, "去公园北边，让旋转桥接上议会广场", Vector3i(HUB.x, GD, HUB.y), Vector3i(C_C.x - 14, GC, C_C.y + 1), Vector3i(C_C.x - 8, GC + 4, C_C.y + 7))
	objective(5, "去议会广场", Vector3i(D_C.x + 10, GD, D_C.y), Vector3i(HUB.x - 3, GD, HUB.y - 3), Vector3i(HUB.x + 3, GD + 4, HUB.y + 3))
	_setup_boss()
	coin_line(Vector3i(A_C.x - 6, GA, A_C.y + 2), Vector3i(A_C.x + 4, GA, A_C.y - 1), 5)
	# 重构点：议会广场上的纪念塔——建好以后，塔顶正好在巡逻艇的航线下面（也能从塔顶跳上去撞它）
	rebuild_tower("cc_t3", D_C.x, D_C.y + 20, 250, 16, {"coins": 60, "energy": 8, "line": "纪念塔顶上的宝箱！整座城都在脚下。"})
	coin_line(Vector3i(C_C.x - 8, GC, C_C.y - 10), Vector3i(C_C.x - 1, GC, C_C.y - 12), 4)

var _mill: Node3D

func _process(delta: float) -> void:
	if is_instance_valid(_mill):
		_mill.rotate_z(delta * 0.8)

func _pupu(cell: Vector3i, i: int, lines: Array) -> void:
	var p := PupuNPC.new()
	p.model_i = i
	p.lines = PackedStringArray(lines)
	add_child(p)
	p.global_position = world.voxel_top(cell + Vector3i.DOWN)

# ================================================================ Boss

func _setup_boss() -> void:
	airship = RustAirship.new()
	add_child(airship)
	airship.center = world.voxel_top(Vector3i(D_C.x, GD - 1, D_C.y + 12))
	airship.radius = 8.0
	airship.height = 9.5
	airship.defeated.connect(_on_boss_defeated)
	# 四个弹射炮：几乎竖直往上，稍微朝场地中心
	for a in [0.785, 2.356, 3.927, 5.498]:
		var cx := int(D_C.x + cos(a) * 17.0)
		var cz := int(D_C.y + 12 + sin(a) * 17.0 * 0.6)
		var to_c := Vector2(D_C.x - cx, D_C.y + 12 - cz).normalized()
		zone(BouncePad, Vector3i(cx - 1, GD, cz - 1), Vector3i(cx + 1, GD + 1, cz + 1), {"launch": Vector3(to_c.x * 1.6, 16.8, to_c.y * 1.6)})
	var trig := zone(Zone, Vector3i(D_C.x - 20, GD, D_C.y - 8), Vector3i(D_C.x + 20, GD + 6, D_C.y + 22))
	trig.player_entered.connect(func() -> void:
		if is_instance_valid(airship) and not airship.active and not boss_done:
			airship.start()
			Music.play_area("boss")
			Music.set_override("explore")
			GameState.say("锈蚀巡逻艇！它在广场上空打转扔炸弹……广场四角有弹射炮。等它飞到头顶的时候弹上去，撞它的发动机！"))

func _on_boss_defeated(_e: Node) -> void:
	boss_done = true
	SaveGame.set_flag("cc_boss")
	Music.play_area("cc")
	Music.set_override("")
	_light_spire(false)

func _light_spire(instant: bool) -> void:
	var top := Vector3i(SPIRE.x, GD + 16 + SPIRE_H, SPIRE.z)
	world.set_block(top, Blocks.RECEIVER_ON)
	tower_beam(top)
	if not instant:
		reconstruct(world.voxel_center(Vector3i(D_C.x, GD, D_C.y)), 130.0, 9.0)
		GameState.say("巡逻艇掉下去了！……议会尖塔亮了。去大厦门口吧。")
		Sfx.play("bridge", Vector3.INF, -2.0, 0.0)
	var goal := zone(Goal, Vector3i(D_C.x - 4, GD, D_C.y - 12), Vector3i(D_C.x + 4, GD + 4, D_C.y - 9)) as Goal
	goal.line = "第四座塔也亮了。整座城都在看着那道光……PIX，只剩最后一座了。"
	GameState.set_objective(10, "走到议会大厦门口", _v(Vector3i(D_C.x, GD, D_C.y - 10)))

func _apply_flags(flags: Dictionary) -> void:
	if bool(flags.get("cc_fuse", false)) and not socket.done:
		socket.done = true
		world.set_block(Vector3i(FUSE_SOCKET.x, GB - 1, FUSE_SOCKET.z), Blocks.CRYSTAL)
	if bool(flags.get("cc_bridge", false)) and bridge.dir == 1:
		bridge.set_dir(0)
	if bool(flags.get("cc_boss", false)):
		if is_instance_valid(airship):
			airship.queue_free()
		boss_done = true
		_light_spire(true)

func arrival_shots() -> Array:
	var V := VoxelWorld.CELL_M
	return [
		{"from": Vector3(-30, 110, 170) * V, "to": Vector3(0, 100, 150) * V, "look": Vector3(60, 70, 60) * V, "dur": 6.0, "fade": Color.BLACK,
			"lines": [["NOVA", "云顶之城。殖民地的首都，也是你救出来的噗噗们的家。"], ["NOVA", "……城还在，只是没有灯。"]]},
		{"from": Vector3(90, 90, 20) * V, "to": Vector3(80, 96, 10) * V, "look": Vector3(SPIRE.x, GD + 30, SPIRE.z) * V, "dur": 5.0,
			"lines": [["NOVA", "第四座塔在议会大厦的尖顶上。"]]},
		{"from": Vector3(4, 64, 128) * V, "to": Vector3(8, 61, 124) * V, "look": Vector3(SPAWN) * V, "dur": 4.0,
			"lines": [["NOVA", "从抵达台出发。"]]},
	]
