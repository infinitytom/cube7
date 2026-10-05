class_name AreaGreenhouse
extends LevelBase
## 区域 1「翠绿温室」——漂浮在云海上的浮岛。只教两件事：滚球（速度 = 力量）和钻头。
##
## 路线（体素坐标，1 格 = 0.5 m，地面基准高度 G）：
##   A 坠毁坑 → 冲出坑口撞开木箱栅栏
##   B 花园（金币引路）
##   C 砂塔深坑：撞碎砂塔底座，砂塔坍塌填平 4 米宽的深沟
##   ↗ 坡道登上 D 高台（G+6，围有石栏）
##   D 玻璃温室：加速撞穿穹顶 → 钻头核心
##   → 泥土墙（钻穿）→ E 高台
##   E 松土：向下钻，掉进洞穴 → 从悬崖侧面出来到 F 台地（G+2）
##   F 中枢塔：钻开晶洞取出能量晶块，放进塔基 → 光桥升起通往终点浮岛（G+10）

const SIZE := Vector3i(128, 72, 128)
const G := 20

## 浮岛由若干圆形地块拼成：[中心 x, 中心 z, 半径, 地面高度]
const BLOBS := [
	[18, 72, 14, G],        # A 坠毁坑一带
	[40, 72, 12, G],        # B 花园
	[50, 68, 8, G],         # B→C 砂塔所在地
	[56, 76, 9, G],         # C 深坑一带
	[64, 76, 11, G],        # C 砂塔深坑
	[68, 64, 6, G],         # C→D 坡道底部
	[58, 38, 20, G + 6],    # D 温室高台
	[92, 56, 10, G + 6],    # E 松土高台
	[100, 26, 13, G + 2],   # F 中枢塔台地
	[94, 42, 7, G + 2],     # F 洞口前（和 E 高台下的洞穴相接）
	[104, 44, 6, G + 2],    # F 光桥起点
	[104, 80, 7, G + 10],   # 终点浮岛
	[10, 52, 10, G],        # 古树（西北角）
	[34, 110, 12, G],       # 锈蚀营地（南边的小岛）
	[26, 104, 6, G],
]

const SPAWN := Vector3i(19, G - 2, 74)
const PIT_X := Vector2i(52, 61)
const RAMP_CD := Rect2i(63, 59, 4, 12)      # x, z, 宽, 长（沿 -Z 升高）
const DOME_C := Vector3i(64, G + 6, 36)
const DOME_R := 11
const SOCKET := Vector3i(100, G + 1, 29)
const TREE_C := Vector2i(10, 52)         ## 古树树干中心（格）
const CAMP := Vector3i(34, G, 110)       ## 锈蚀营地的笼子
const TOWER_H := 36                      ## 重构塔高度（格）
const TOWER_TOP := Vector3i(100, G + 2 + TOWER_H, 24)

var heights := {}          # Vector2i -> 地面高度（第一个空气层的 y）
var backdrop := false      ## 只当标题画面背景：不放机关、不放音乐
var socket: ItemSocket
var enemies: Array[Node3D] = []
var form_core: Node
var fragments := {}        # id -> 节点
var crystal: UsableItem
var bridge_cells: Array = []
var bridge_built := false
var _noise := FastNoiseLite.new()
var vista: Vista
var camp_enemies: Array = []
var cage_cells: Array[Vector3i] = []
var deck_cell := Vector3i.ZERO
var _beam: Node3D

## 出生时的镜头朝向：从西南方看过去，避开坠毁的飞船，东边的出口在画面右侧
func spawn_yaw() -> float:
	return -0.75

func spawn_position() -> Vector3:
	return world.voxel_top(SPAWN + Vector3i.DOWN) + Vector3.UP * 0.55

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	if not backdrop:
		GameState.reset_for_level([true, false, false] as Array[bool], true, 1.0, 3)
	if not backdrop:
		Atmosphere.apply(self, "greenhouse")
	rng.seed = 20260927
	_noise.seed = 7
	_noise.frequency = 0.08
	world.setup(SIZE)
	decor = Decor.new()
	add_child(decor)
	decor.setup(world)
	_terrain()
	_crater_and_pod()
	_garden()
	_sand_pit()
	_plateau_and_dome()
	_mud_wall_and_cave()
	_pylon_and_bridge()
	_fences()
	_great_tree()
	_rust_camp()
	_ruins()
	_outcrops()
	# 体素精度上的自然化（崩边、岩层、垂草）；谜题关键处不动
	world.naturalize(G + 20, [
		AABB(Vector3(20, 0, 69), Vector3(9, 44, 9)),          # 出坑坡道和木箱
		AABB(Vector3(44, 0, 56), Vector3(30, 44, 30)),        # 砂塔、深沟、坡道
		AABB(Vector3(DOME_C.x - DOME_R - 2, 0, DOME_C.z - DOME_R - 2), Vector3(DOME_R * 2 + 5, 44, DOME_R * 2 + 5)),
		AABB(Vector3(94, 0, 18), Vector3(16, 72, 34)),        # 插槽、重构塔和光桥
		AABB(Vector3(0, 0, 40), Vector3(24, 72, 26)),         # 古树
		AABB(Vector3(22, 0, 96), Vector3(26, 72, 26)),        # 锈蚀营地
		AABB(Vector3(34, 0, 80), Vector3(9, 72, 20)),         # 木桥
	])
	world.rebuild_all()
	scatter_decor(Vector3i(0, G - 3, 0), Vector3i(SIZE.x - 1, G + 12, SIZE.z - 1), 0.28, 0.07, 0.03)
	decor.commit()
	_dress()
	world.flush_dirty()
	vista = Vistas.greenhouse(self, world, _island_falls())
	if backdrop:
		return
	_logic()
	world.item_dropped.connect(_on_item_dropped)
	Music.set_default("explore")
	Music.set_override("")
	Music.play_area("gh")
	GameState.set_checkpoint(spawn_position())

# ================================================================ 布景：让浮岛“有人住过”

func _dress() -> void:
	# 坠毁坑边上的考察营地：集装箱、控制台、全息星图桌
	deco("space-station/container-tall", 24, 63, 1.6)
	deco("space-station/container", 28, 62, 1.2)
	deco("space-station/computer-screen", 21, 64, 0.9)
	deco("space-station/table-display-planet", 30, 66, 0.9)
	deco("space-station/chair", 22, 67, 0.7, "none")
	# 温室高台：机械臂和扫描仪（以前的研究设备）
	deco("factory/robot-arm-a", 56, 46, 1.8)
	deco("factory/scanner-high", 72, 44, 1.6)
	deco("factory/screen-wide", 60, 58, 1.2)
	# 重构塔台地：发电机、齿轮
	deco("factory/machine", 101, 40, 1.4)
	deco("factory/cog-a", 90, 38, 0.8, "none")
	deco("space-station/container-wide", 104, 30, 1.2)
	# 成片的树林（边缘和角落），让岛看起来是“长满了”的
	for c in [Vector2i(30, 61), Vector2i(48, 85), Vector2i(35, 86), Vector2i(70, 80), Vector2i(80, 70),
			Vector2i(58, 38), Vector2i(86, 62), Vector2i(20, 88), Vector2i(76, 36), Vector2i(110, 50)]:
		for k in 2:
			var cell := find_flat(c.x + rng.randi_range(-3, 3), c.y + rng.randi_range(-3, 3), 3, 1)
			if cell.y >= 0 and world.get_block(cell) == Blocks.AIR:
				tree(cell, rng.randi_range(4, 7), rng.randf_range(1.6, 2.4))
	# 花丛边的蝴蝶
	var amb := Ambient.new()
	amb.area_lo = Vector3(20, G + 1, 58) * VoxelWorld.CELL_M
	amb.area_hi = Vector3(110, G + 10, 88) * VoxelWorld.CELL_M
	amb.count = 22
	add_child(amb)

## 玩具：加速板、弹簧与空中小岛、限时蓝币挑战
func _toys() -> void:
	# 坡道底下的加速板：借着速度冲上高台、撞碎温室玻璃
	zone(SpeedPad, Vector3i(63, G, 72), Vector3i(66, G + 1, 73), {"dir": Vector3(0, 0, -1), "speed": 14.0})
	# 花园里的弹簧 → 空中小岛（上面有一圈金币）
	var sp := find_flat(40, 80, 5, 3)
	if sp.y >= 0:
		zone(BouncePad, sp + Vector3i(-1, 0, -1), sp + Vector3i(1, 1, 1), {"launch": Vector3(0, 12.6, 2.2)})
		var top := sp.y + 9
		world.fill_box(Vector3i(sp.x - 3, top - 2, sp.z + 3), Vector3i(sp.x + 3, top - 1, sp.z + 9), Blocks.DIRT)
		world.fill_box(Vector3i(sp.x - 3, top, sp.z + 3), Vector3i(sp.x + 3, top, sp.z + 9), Blocks.GRASS)
		world.fill_box(Vector3i(sp.x - 2, top - 3, sp.z + 4), Vector3i(sp.x + 2, top - 3, sp.z + 8), Blocks.DIRT)
		for k in 8:
			var a := k * TAU / 8.0
			coin(Vector3i(sp.x + roundi(cos(a) * 2.0), top + 1, sp.z + 6 + roundi(sin(a) * 2.0)))
		prop("platformer/flowers-tall", Vector3i(sp.x, top + 1, sp.z + 6), 0.7, true, 3, "none", "break_soft")
		talk(sp + Vector3i(-2, 0, -2), sp + Vector3i(2, 3, 2), ["弹簧！滚上去试试——上面那座小岛好像藏着什么。"])
	# 限时蓝币挑战
	var bt := find_flat(33, 69, 5, 3)
	if bt.y >= 0:
		var ch := zone(CoinChallenge, bt + Vector3i(-1, 0, -1), bt + Vector3i(1, 1, 1), {"time_limit": 16.0}) as CoinChallenge
		var offs := [Vector2i(6, 0), Vector2i(9, 5), Vector2i(6, 10), Vector2i(0, 13), Vector2i(-5, 10), Vector2i(-7, 4), Vector2i(-4, -4), Vector2i(3, -6)]
		for o in offs:
			var cx: int = bt.x + o.x
			var cz: int = bt.z + o.y
			var h := surface_y(cx, cz)
			if h > 0:
				ch.coin_positions.append(world.voxel_center(Vector3i(cx, h, cz)) + Vector3.UP * 0.3)
		ch.chest_position = world.voxel_top(bt + Vector3i(0, -1, -3))

# ================================================================ 地形

func h_at(x: int, z: int) -> int:
	return heights.get(Vector2i(x, z), -1)

func _set_h(x: int, z: int, h: int) -> void:
	heights[Vector2i(x, z)] = h

## 按高度表重建一列：顶层草、两层土、下面悬崖岩，底部收成倒锥形
func _column(x: int, z: int, h: int, depth: int, top := Blocks.GRASS) -> void:
	world.fill_column(x, z, 0, SIZE.y - 1, Blocks.AIR)
	if h < 0:
		return
	var bottom := maxi(1, h - depth)
	world.fill_column(x, z, bottom, h - 4, Blocks.CLIFF)
	world.fill_column(x, z, maxi(bottom, h - 3), h - 2, Blocks.DIRT)
	world.fill_column(x, z, h - 1, h - 1, top)

func _terrain() -> void:
	for z in SIZE.z:
		for x in SIZE.x:
			var best := -1
			var edge := 0.0
			for b in BLOBS:
				var d := Vector2(x - b[0], z - b[1]).length()
				var r: float = b[2] + _noise.get_noise_2d(x, z) * 2.2
				if d <= r:
					best = maxi(best, b[3])
					edge = maxf(edge, r - d)
			if best < 0:
				continue
			_set_h(x, z, best)
			var depth := 4 + int(clampf(edge * 1.1, 0.0, 15.0)) + int(_noise.get_noise_2d(x * 3, z * 3) * 2.0)
			_column(x, z, best, depth + (best - G))

## 把一块矩形区域的地面改成指定高度（保留底部形状）
func _flatten(x0: int, z0: int, x1: int, z1: int, h: int, top := Blocks.GRASS) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			_set_h(x, z, h)
			_column(x, z, h, 10 + (h - G), top)

# ================================================================ A 坠毁坑

func _crater_and_pod() -> void:
	var c := Vector2(15, 74)
	for z in range(64, 85):
		for x in range(5, 26):
			var d := Vector2(x, z).distance_to(c)
			if d <= 7.2 and h_at(x, z) >= 0:
				_set_h(x, z, G - 2)
				_column(x, z, G - 2, 12, Blocks.DIRT if d > 6.2 else Blocks.GRASS)
	# 出坑坡道（朝 +X 升两层）
	_flatten(22, 72, 25, 75, G - 2)
	world.fill_ramp(Vector3i(22, G - 2, 72), Vector3i(25, G - 2, 75), VoxelWorld.Ramp.PX, Blocks.DIRT, true)
	# 坑口的木箱栅栏：冲上来撞开它
	world.fill_box(Vector3i(27, G, 71), Vector3i(27, G + 1, 76), Blocks.CRATE)
	# 坠毁的飞船：新游戏第一次进入时，等开场演出里坠落后再出现
	if not _ship_deferred():
		_place_ship()
	# 坑边的树
	for t in [Vector3i(8, G, 64), Vector3i(24, G, 64), Vector3i(6, G, 83), Vector3i(25, G, 84)]:
		if h_at(t.x, t.z) == G:
			tree(t, 5 + rng.randi() % 2, 2.3)

func _ship_deferred() -> bool:
	return not backdrop and Flow.mode == "new" and not bool(SaveGame.data.get("intro_seen", false))

## 坠毁的飞船（半埋在坑的西侧）+ 冒烟
func _place_ship() -> void:
	var pc := Vector3(11.0, G - 1.0, 74.0)
	for z in range(69, 80):
		for y in range(G - 3, G + 3):
			for x in range(5, 18):
				var q := (Vector3(x, y, z) - pc) / Vector3(5.2, 2.6, 3.0)
				if q.length() <= 1.0:
					var t := Blocks.HULL
					if absf(q.y - 0.25) < 0.18 and q.x > -0.2:
						t = Blocks.HULL_DARK        # 舷窗带
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), t)
	world.fill_box(Vector3i(11, G + 2, 74), Vector3i(11, G + 2, 74), Blocks.LAMP)
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 4.0
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.gravity = Vector3(-0.15, 0.7, 0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.8
	smoke.scale_amount_min = 0.3
	smoke.scale_amount_max = 0.8
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.8, 0.8, 0.85, 0.22)
	smat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA   # 靠近镜头的烟淡出，不糊屏幕
	smat.distance_fade_min_distance = 1.5
	smat.distance_fade_max_distance = 6.0
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	smoke.mesh = sm
	add_child(smoke)
	smoke.global_position = world.voxel_center(Vector3i(9, G + 2, 74))

# ================================================================ B 花园

func _garden() -> void:
	# 铺路石小径：从坑口通往深坑
	for z in range(72, 76):
		for x in range(28, 51):
			if h_at(x, z) == G:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G - 1, z), Blocks.PAVING)
	# 花坛与木箱
	for c in [Vector3i(33, G, 66), Vector3i(44, G, 80), Vector3i(38, G, 81)]:
		world.fill_box(c, c + Vector3i(1, 1, 1), Blocks.CRATE)
	for c in [Vector3i(31, G, 79), Vector3i(47, G, 66), Vector3i(36, G, 68)]:
		world.fill_box(c, c, Blocks.CRATE)
	for t in [Vector3i(34, G, 62), Vector3i(46, G, 83), Vector3i(30, G, 84), Vector3i(42, G, 62)]:
		if h_at(t.x, t.z) == G:
			tree(t, 5 + rng.randi() % 3, 2.5)
	for l in [Vector3i(29, G, 71), Vector3i(37, G, 71), Vector3i(45, G, 71)]:
		lamp_post(l)

# ================================================================ C 砂塔深坑

func _sand_pit() -> void:
	# 深沟：宽 10 格（5 米），深 4 格——全速冲过去也会撞在对岸崖壁上掉下去
	for z in range(50, SIZE.z):
		for x in range(PIT_X.x, PIT_X.y + 1):
			if h_at(x, z) == G:
				_set_h(x, z, G - 4)
				_column(x, z, G - 4, 8, Blocks.CLIFF)
	# 沟两端的挡土墙：比地面低半格——挡住砂子不漏进云海
	for z in [58, 59, 60, 61, 86, 87, 88]:
		for x in range(PIT_X.x, PIT_X.y + 1):
			if h_at(x, z) < 0 or h_at(x, z) == G - 4:
				_set_h(x, z, G - 1)
				_column(x, z, G - 1, 8, Blocks.CLIFF)
		# 挡土墙东端立一道金属护栏：不能沿着墙顶滚过去再跳上对岸
		if h_at(PIT_X.y + 1, z) >= G - 1:
			world.fill_box(Vector3i(PIT_X.y + 1, G, z), Vector3i(PIT_X.y + 1, G + 2, z), Blocks.METAL)
	# 掉进沟里的逃生坡道：只能回到西侧
	_flatten(PIT_X.x, 78, PIT_X.x + 1, 81, G, Blocks.CLIFF)
	world.fill_ramp(Vector3i(PIT_X.x + 2, G - 4, 78), Vector3i(PIT_X.y, G - 4, 81), VoxelWorld.Ramp.NX, Blocks.CLIFF, true)
	# 砂塔：6×6×10，立在一层木箱底座上
	# 砂塔一半悬在沟的上方，由一层支撑木架托着；路边那根橙色支撑桩连着木架
	world.fill_box(Vector3i(PIT_X.x, G - 1, 63), Vector3i(PIT_X.y, G - 1, 70), Blocks.SUPPORT)
	# 支撑桩两格宽（平滑地形上滚动轨迹会有点弧度，太细的桩容易擦边而过）
	world.fill_box(Vector3i(51, G - 1, 70), Vector3i(51, G + 1, 71), Blocks.SUPPORT)
	world.fill_box(Vector3i(PIT_X.x, G, 63), Vector3i(PIT_X.y, G + 11, 69), Blocks.SAND)
	# 沟上方横着一根打不坏的旧灌溉管：想直接跳过去会撞上管子掉进沟里——得先把沟填平再滚过去
	var zs: Array[int] = []
	for z in range(50, SIZE.z):
		var h := h_at(56, z)
		if h == G - 4 or h == G - 1:
			zs.append(z)
	if not zs.is_empty():
		var z0: int = zs.min() - 1
		var z1: int = zs.max() + 1
		for z in range(z0, z1 + 1):
			if z < 62 or z > 70:
				world.fill_box(Vector3i(56, G + 2, z), Vector3i(57, G + 4, z), Blocks.METAL)
				# 管子下沿再加一层体素（离地 0.75 米）：主角变小后也跳不过去
				var C := VoxelWorld.CELL
				world.vfill(Vector3i(56 * C, (G + 2) * C - 1, z * C), Vector3i(57 * C + 1, (G + 2) * C - 1, z * C + 1), Blocks.METAL)
		for z in [z0, z1]:
			if h_at(56, z) >= G - 1:
				world.fill_box(Vector3i(56, G, z), Vector3i(57, G + 1, z), Blocks.METAL)
		# 管子上每隔几格一个接口环，看起来更像管道
		for z in range(z0 + 3, z1, 6):
			if z < 61 or z > 71:
				world.fill_box(Vector3i(55, G + 2, z), Vector3i(58, G + 3, z), Blocks.HULL_DARK)
	# 沟东侧的小平台和石头
	world.fill_box(Vector3i(71, G, 80), Vector3i(72, G + 1, 81), Blocks.ROCK)
	tree(Vector3i(73, G, 72), 6, 2.4)

# ================================================================ D 温室高台

func _plateau_and_dome() -> void:
	# 坡道：C 层（G）→ 高台（G+6），沿 -Z 升高
	_flatten(RAMP_CD.position.x, RAMP_CD.position.y, RAMP_CD.end.x - 1, RAMP_CD.end.y - 1, G)
	_flatten(RAMP_CD.position.x, 50, RAMP_CD.end.x - 1, RAMP_CD.position.y - 1, G + 6)
	world.fill_ramp(Vector3i(RAMP_CD.position.x, G, RAMP_CD.position.y), Vector3i(RAMP_CD.end.x - 1, G, RAMP_CD.end.y - 1), VoxelWorld.Ramp.NZ, Blocks.PAVING, true, Blocks.CLIFF)
	# 高台上的铺路石：坡顶 → 温室南门
	for z in range(47, 59):
		for x in range(RAMP_CD.position.x - 1, RAMP_CD.end.x + 1):
			if h_at(x, z) == G + 6:
				world.fill_box(Vector3i(x, G + 5, z), Vector3i(x, G + 5, z), Blocks.PAVING)
	# 玻璃穹顶：半球壳 + 白色钢架（经线 4 根、纬线 2 圈）
	var c := DOME_C
	for z in range(c.z - DOME_R - 1, c.z + DOME_R + 2):
		for y in range(c.y, c.y + DOME_R + 2):
			for x in range(c.x - DOME_R - 1, c.x + DOME_R + 2):
				var d := Vector3(x - c.x, (y - c.y) * 1.0, z - c.z).length()
				if absf(d - DOME_R) <= 0.55:
					var rib := x == c.x or z == c.z or y == c.y or y == c.y + 5
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.HULL if rib else Blocks.GLASS)
	# 南门：钢架在门口断开，留一整片玻璃
	for y in range(c.y, c.y + 4):
		for z in range(c.z + DOME_R - 2, c.z + DOME_R + 2):
			if world.get_block(Vector3i(c.x, y, z)) == Blocks.HULL:
				world.fill_box(Vector3i(c.x, y, z), Vector3i(c.x, y, z), Blocks.GLASS)
		if world.get_block(Vector3i(c.x - 1, c.y, c.z + DOME_R)) == Blocks.HULL:
			pass
	for x in range(c.x - 3, c.x + 4):
		for z in range(c.z + DOME_R - 2, c.z + DOME_R + 2):
			if world.get_block(Vector3i(x, c.y, z)) == Blocks.HULL:
				world.fill_box(Vector3i(x, c.y, z), Vector3i(x, c.y, z), Blocks.GLASS)
	# 东门同理
	for y in range(c.y, c.y + 4):
		for x in range(c.x + DOME_R - 2, c.x + DOME_R + 2):
			if world.get_block(Vector3i(x, y, c.z)) == Blocks.HULL:
				world.fill_box(Vector3i(x, y, c.z), Vector3i(x, y, c.z), Blocks.GLASS)
	for z in range(c.z - 3, c.z + 4):
		for x in range(c.x + DOME_R - 2, c.x + DOME_R + 2):
			if world.get_block(Vector3i(x, c.y, z)) == Blocks.HULL:
				world.fill_box(Vector3i(x, c.y, z), Vector3i(x, c.y, z), Blocks.GLASS)
	# 温室内部：中央圆形花坛（钻头核心的底座）+ 四角小树 + 泥土花坛
	for z in range(c.z - 2, c.z + 3):
		for x in range(c.x - 2, c.x + 3):
			if Vector2(x - c.x, z - c.z).length() <= 2.3:
				world.fill_box(Vector3i(x, c.y - 1, z), Vector3i(x, c.y - 1, z), Blocks.PAVING)
	for t in [Vector3i(c.x - 6, c.y, c.z - 6), Vector3i(c.x + 6, c.y, c.z - 6), Vector3i(c.x - 6, c.y, c.z + 5)]:
		tree(t, 4, 1.8)
	# 泥土花坛里藏着记忆碎片（拿到钻头后才能挖出来）
	world.fill_box(Vector3i(c.x + 4, c.y, c.z + 4), Vector3i(c.x + 6, c.y + 2, c.z + 6), Blocks.DIRT)
	world.fill_box(Vector3i(c.x + 5, c.y, c.z + 5), Vector3i(c.x + 5, c.y + 1, c.z + 5), Blocks.AIR)
	# 温室外的装饰
	for t in [Vector3i(44, G + 6, 26), Vector3i(48, G + 6, 48), Vector3i(76, G + 6, 26)]:
		if h_at(t.x, t.z) == G + 6:
			tree(t, 6, 2.6)
	for l in [Vector3i(62, G + 6, 50), Vector3i(67, G + 6, 50)]:
		lamp_post(l)

# ================================================================ 泥土墙、E 高台、洞穴

func _mud_wall_and_cave() -> void:
	# D 与 E 之间的窄桥（G+6），被一堵泥土墙堵住
	_flatten(68, 50, 86, 54, G + 6)
	world.fill_box(Vector3i(76, G + 6, 50), Vector3i(78, G + 9, 54), Blocks.DIRT)
	world.fill_box(Vector3i(77, G + 7, 51), Vector3i(77, G + 7, 51), Blocks.ORE)
	# E 高台上的松土（没有草皮的一片褐色土地）
	for z in range(50, 54):
		for x in range(90, 94):
			if h_at(x, z) == G + 6:
				world.fill_box(Vector3i(x, G + 5, z), Vector3i(x, G + 5, z), Blocks.LOOSE)
	# 洞穴：从松土下方一直通到南侧悬崖
	for z in range(40, 55):
		for x in range(88, 97):
			if h_at(x, z) >= G + 2:
				world.fill_box(Vector3i(x, G + 2, z), Vector3i(x, G + 4, z), Blocks.AIR)
				world.fill_box(Vector3i(x, G + 1, z), Vector3i(x, G + 1, z), Blocks.CLIFF)
	# 洞里的发光蘑菇（晶石）照明
	for p in [Vector3i(88, G + 4, 50), Vector3i(94, G + 4, 47), Vector3i(89, G + 2, 54)]:
		world.fill_box(p, p, Blocks.CRYSTAL)
	for t in [Vector3i(95, G + 6, 62), Vector3i(88, G + 6, 61)]:
		if h_at(t.x, t.z) == G + 6:
			tree(t, 5, 2.2)

# ================================================================ F 中枢塔与光桥

func _pylon_and_bridge() -> void:
	var pc := Vector3i(100, G + 2, 24)
	# 重构塔：18 米高的白色高塔，三层悬浮环，塔顶的接收器点亮后会向天空打出光柱
	world.fill_box(pc + Vector3i(-3, 0, -3), pc + Vector3i(3, 1, 3), Blocks.HULL_DARK)
	world.fill_box(pc + Vector3i(-2, 2, -2), pc + Vector3i(2, 9, 2), Blocks.HULL)
	world.fill_box(pc + Vector3i(-2, 2, -2), pc + Vector3i(-2, 9, -2), Blocks.HULL_DARK)
	world.fill_box(pc + Vector3i(2, 2, -2), pc + Vector3i(2, 9, -2), Blocks.HULL_DARK)
	world.fill_box(pc + Vector3i(-2, 2, 2), pc + Vector3i(-2, 9, 2), Blocks.HULL_DARK)
	world.fill_box(pc + Vector3i(2, 2, 2), pc + Vector3i(2, 9, 2), Blocks.HULL_DARK)
	world.fill_box(pc + Vector3i(-1, 10, -1), pc + Vector3i(1, TOWER_H - 1, 1), Blocks.HULL)
	for y in range(6, TOWER_H - 2, 6):
		world.fill_box(pc + Vector3i(-1, y, -1), pc + Vector3i(1, y, 1), Blocks.LAMP if y < 10 else Blocks.HULL_DARK)
	# 悬浮环（和塔身之间留一格空）
	for ring in [[14, 3], [23, 3], [30, 2]]:
		var ry: int = ring[0]
		var rr: int = ring[1] + 1
		for dz in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if maxi(absi(dx), absi(dz)) == rr:
					var corner := absi(dx) == rr and absi(dz) == rr
					world.fill_box(pc + Vector3i(dx, ry, dz), pc + Vector3i(dx, ry, dz), Blocks.LAMP if corner else Blocks.HULL)
	world.fill_box(pc + Vector3i(0, TOWER_H, 0), pc + Vector3i(0, TOWER_H, 0), Blocks.RECEIVER)
	world.fill_box(pc + Vector3i(-1, TOWER_H - 1, -1), pc + Vector3i(1, TOWER_H - 1, 1), Blocks.HULL_DARK)
	# 塔基前的插槽凹位
	world.fill_box(SOCKET, SOCKET, Blocks.AIR)
	# 晶洞：岩石小丘里包着紫色晶洞
	var gc := Vector3(92.5, G + 1.5, 21.5)
	for z in range(17, 27):
		for y in range(G + 2, G + 7):
			for x in range(88, 98):
				var q := (Vector3(x, y, z) - gc) / Vector3(4.2, 3.6, 4.2)
				if q.length() + _noise.get_noise_3d(x * 4, y * 4, z * 4) * 0.15 <= 1.0:
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.ROCK)
	world.fill_box(Vector3i(92, G + 2, 21), Vector3i(93, G + 3, 22), Blocks.GEODE)
	# 岩丘表面露出几颗紫色晶体，提示里面有东西
	for p in [Vector3i(90, G + 3, 20), Vector3i(95, G + 2, 23), Vector3i(92, G + 4, 24)]:
		world.fill_box(p, p, Blocks.GEODE)
	world.fill_box(Vector3i(90, G + 2, 24), Vector3i(90, G + 2, 24), Blocks.ORE)
	world.fill_box(Vector3i(95, G + 3, 19), Vector3i(95, G + 3, 19), Blocks.ORE)
	for t in [Vector3i(108, G + 2, 18), Vector3i(106, G + 2, 32)]:
		if h_at(t.x, t.z) == G + 2:
			tree(t, 5, 2.2)
	# 光桥（接通能源后逐格出现）：从 F（G+2）沿 +Z 升到终点浮岛（G+10）
	var z0 := 49
	for k in 16:
		var y := G + 2 + k / 2
		var shape := (1 if k % 2 == 0 else 5) + VoxelWorld.Ramp.PZ
		for x in range(103, 106):
			bridge_cells.append([Vector3i(x, y, z0 + k), shape])
			if k >= 2:
				bridge_cells.append([Vector3i(x, y - 1, z0 + k), 0])
	for k in range(16, 26):
		for x in range(103, 106):
			bridge_cells.append([Vector3i(x, G + 9, z0 + k), 0])
	# 终点浮岛：能量核心奖杯
	world.fill_box(Vector3i(103, G + 10, 80), Vector3i(105, G + 10, 82), Blocks.HULL)
	# 终点浮岛一圈矮石栏（光桥入口留空），防止滚过头
	for key in heights.keys():
		if heights[key] != G + 10:
			continue
		var x: int = key.x
		var z: int = key.y
		if x >= 102 and x <= 106 and z <= 76:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if h_at(x + d.x, z + d.y) < G + 10:
				world.fill_box(Vector3i(x, G + 10, z), Vector3i(x, G + 10, z), Blocks.MOSS)
				break
	world.fill_box(Vector3i(104, G + 11, 81), Vector3i(104, G + 12, 81), Blocks.GOAL)
	for t in [Vector3i(99, G + 10, 84), Vector3i(109, G + 10, 78)]:
		if h_at(t.x, t.z) == G + 10:
			tree(t, 4, 2.0)

# ================================================================ 高台石栏

## 高台（G+6）边缘自动加一圈 1 米高的石栏，防止直接滚下去跳过关卡；坡道顶留出入口
func _fences() -> void:
	for key in heights.keys():
		var h: int = heights[key]
		if h != G + 6:
			continue
		var x: int = key.x
		var z: int = key.y
		if x >= RAMP_CD.position.x and x < RAMP_CD.end.x and z >= 50 and z <= 60:
			continue
		var edge := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if h_at(x + d.x, z + d.y) < G + 6:
				edge = true
		if edge:
			var top := Blocks.LAMP if (x * 7 + z * 13) % 23 == 0 else Blocks.MOSS
			world.fill_box(Vector3i(x, G + 6, z), Vector3i(x, G + 7, z), Blocks.MOSS)
			if top == Blocks.LAMP:
				world.fill_box(Vector3i(x, G + 8, z), Vector3i(x, G + 8, z), Blocks.LAMP)

# ================================================================ 古树：温室群岛最老的居民

## 一棵十几米高的粉色古树。树干周围盘着一圈圈树枝平台，跳上去能到树屋（宝箱 + 记忆碎片 + 眺望星核塔）
func _great_tree() -> void:
	var C := VoxelWorld.CELL
	var base_y := G * C
	var cx := TREE_C.x * C + 1.0
	var cz := TREE_C.y * C + 1.0
	var trunk_h := 26 * C
	var n := FastNoiseLite.new()
	n.seed = 31
	n.frequency = 0.18
	# 地面整平一圈
	for z in range(TREE_C.y - 7, TREE_C.y + 8):
		for x in range(TREE_C.x - 7, TREE_C.x + 8):
			if h_at(x, z) >= 0 and Vector2(x - TREE_C.x, z - TREE_C.y).length() < 7.5:
				_set_h(x, z, G)
				_column(x, z, G, 12 + int(Vector2(x - TREE_C.x, z - TREE_C.y).length() < 4.0) * 6)
	# 树干：粗壮、微微扭转，根部外扩
	for y in range(base_y - 6, base_y + trunk_h):
		var t := clampf(float(y - base_y) / trunk_h, 0.0, 1.0)
		var flare := maxf(0.0, 1.0 - float(y - base_y) / 12.0)
		var r := 5.0 * (1.0 - 0.3 * t) + 5.0 * flare * flare
		var ox := sin(t * 2.4) * 2.0
		var oz := cos(t * 1.7) * 1.5 - 1.5
		var ir := int(ceil(r)) + 2
		for dz in range(-ir, ir + 1):
			for dx in range(-ir, ir + 1):
				var q := Vector2(dx + 0.5 - ox, dz + 0.5 - oz)
				var ang := atan2(q.y, q.x)
				if q.length() <= r + n.get_noise_3d(cos(ang) * 6.0, y * 0.35, sin(ang) * 6.0) * 1.1:
					world.vset_raw(Vector3i(int(cx) + dx, y, int(cz) + dz), Blocks.WOOD)
	# 地面上的大树根
	for k in 7:
		var a := k * TAU / 7.0 + 0.3
		var d := Vector2(cos(a), sin(a))
		for st in range(0, 18):
			var rr := 2.6 - st * 0.12
			var p := Vector2(cx, cz) + d * (8.0 + st)
			var yy := base_y - 1 + (1 if st < 6 else 0)
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					for dy in range(-2, 3):
						if Vector3(dx, dy * 1.4, dz).length() <= rr:
							world.vset_raw(Vector3i(int(p.x) + dx, yy + dy, int(p.y) + dz), Blocks.WOOD)
	# 螺旋上升的树枝平台（每级 0.75 米，滚球跳得上去）
	var top_c := Vector2(cx, cz)
	for i in 10:
		var a := i * deg_to_rad(60.0) + 0.9
		var pr := 10.5
		var pcx := int(cx + cos(a) * pr)
		var pcz := int(cz + sin(a) * pr)
		var yt := base_y + 3 * (i + 1) - 1
		world.vfill(Vector3i(pcx - 4, yt - 1, pcz - 4), Vector3i(pcx + 3, yt, pcz + 3), Blocks.PLANK)
		# 枝干：从树干伸过来托住平台
		for st in 8:
			var bp := Vector2(cx, cz).lerp(Vector2(pcx, pcz), float(st) / 8.0)
			world.vfill(Vector3i(int(bp.x) - 1, yt - 3, int(bp.y) - 1), Vector3i(int(bp.x) + 1, yt - 1, int(bp.y) + 1), Blocks.WOOD)
		# 平台边上一小簇叶子
		_leaf_blob(Vector3(pcx + cos(a) * 4.0, yt + 2, pcz + sin(a) * 4.0), 2.2, Blocks.LEAVES)
	# 树屋平台：一圈木板 + 栏杆
	var dy := base_y + 33
	for dz in range(-15, 16):
		for dx in range(-15, 16):
			var d := Vector2(dx, dz).length()
			var p := Vector3i(int(cx) + dx, dy, int(cz) + dz)
			if d <= 14.5 and world.vget(p) == Blocks.AIR:
				world.vset_raw(p, Blocks.PLANK)
				world.vset_raw(p + Vector3i.DOWN, Blocks.WOOD)
			if d > 13.5 and d <= 14.5 and (absi(dx) + absi(dz)) % 2 == 0:
				world.vset_raw(p + Vector3i.UP, Blocks.WOOD)
				world.vset_raw(p + Vector3i.UP * 2, Blocks.WOOD)
	# 从最后一个平台上树屋的入口：栏杆留个缺口
	var last_a := 9 * deg_to_rad(60.0) + 0.9
	for k in range(-5, 6):
		for dy2 in [1, 2]:
			var ea := last_a + k * 0.04
			var p2 := Vector3i(int(cx + cos(ea) * 14.0), dy + dy2, int(cz + sin(ea) * 14.0))
			if world.vget(p2) == Blocks.WOOD:
				world.vset_raw(p2, Blocks.AIR)
	deck_cell = Vector3i(int(cx + cos(last_a + PI) * 9.5) / C, (dy + 1) / C, int(cz + sin(last_a + PI) * 9.5) / C)
	# 大树枝和树冠：伞形的粉色花冠（扁椭球）+ 枝头的花团 + 垂下来的花串
	var crown_y := base_y + trunk_h
	var top := Vector3(cx + sin(2.4) * 2.0, crown_y, cz + cos(1.7) * 1.5 - 1.5)
	var ends: Array[Vector3] = []
	for k in 7:
		var a := k * TAU / 7.0 + 0.5
		var from := Vector3(top.x, crown_y - 10 + (k % 3) * 3, top.z)
		var reach := 16.0 + (k % 3) * 3.0
		var to := from + Vector3(cos(a) * reach, 6.0 + (k % 2) * 4.0, sin(a) * reach)
		for st in 21:
			var q := from.lerp(to, st / 20.0) + Vector3(0, sin(st / 20.0 * PI) * 2.5, 0)
			var rr := 2.4 - st * 0.07
			for ddz in range(-3, 4):
				for ddy in range(-3, 4):
					for ddx in range(-3, 4):
						if Vector3(ddx, ddy, ddz).length() <= rr:
							world.vset_raw(Vector3i(q) + Vector3i(ddx, ddy, ddz), Blocks.WOOD)
		ends.append(to)
	# 伞形主冠
	_leaf_ellipsoid(top + Vector3(0, 9, 0), Vector3(21.0, 8.0, 21.0), Blocks.BLOSSOM)
	for e in ends:
		_leaf_ellipsoid(e + Vector3(0, 1, 0), Vector3(8.5, 5.5, 8.5) * rng.randf_range(0.85, 1.15), Blocks.BLOSSOM if rng.randf() < 0.8 else Blocks.LEAVES)
	# 垂下来的花串
	for k in 70:
		var a := rng.randf() * TAU
		var rr2 := rng.randf_range(8.0, 26.0)
		var x := int(top.x + cos(a) * rr2)
		var z := int(top.z + sin(a) * rr2)
		var y := crown_y + 24
		while y > crown_y - 12 and world.vget(Vector3i(x, y, z)) == Blocks.AIR:
			y -= 1
		if y <= crown_y - 12 or world.vget(Vector3i(x, y, z)) == Blocks.WOOD:
			continue
		# 找到花冠底面
		while y > crown_y - 12 and world.vget(Vector3i(x, y - 1, z)) != Blocks.AIR:
			y -= 1
		for d in rng.randi_range(2, 7):
			world.vset_raw(Vector3i(x, y - 1 - d, z), Blocks.BLOSSOM)
	# 树屋底下挂的小灯笼
	for k in 6:
		var a := k * TAU / 6.0 + 0.2
		var lp := Vector3i(int(cx + cos(a) * 12.0), dy - 3, int(cz + sin(a) * 12.0))
		world.vset_raw(lp + Vector3i.UP, Blocks.WOOD)
		world.vset_raw(lp, Blocks.LAMP)
	world._mark_dirty_box(Vector3i(int(cx) - 40, base_y - 8, int(cz) - 40), Vector3i(int(cx) + 40, base_y + trunk_h + 30, int(cz) + 40))

func _leaf_ellipsoid(c: Vector3, r: Vector3, t: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = int(c.x * 7 + c.z * 13)
	n.frequency = 0.22
	for dz in range(-int(r.z) - 2, int(r.z) + 3):
		for dy in range(-int(r.y) - 2, int(r.y) + 3):
			for dx in range(-int(r.x) - 2, int(r.x) + 3):
				var q := Vector3(dx / r.x, dy / r.y, dz / r.z)
				# 底面稍微平一点
				if dy < -r.y * 0.5:
					continue
				if q.length() <= 1.0 + n.get_noise_3d(dx, dy, dz) * 0.22:
					var p := Vector3i(c) + Vector3i(dx, dy, dz)
					if world.vget(p) == Blocks.AIR:
						world.vset_raw(p, t)

func _leaf_blob(c: Vector3, r: float, t: int) -> void:
	var ir := int(ceil(r)) + 1
	var n := FastNoiseLite.new()
	n.seed = int(c.x * 7 + c.z * 13)
	n.frequency = 0.3
	for dz in range(-ir, ir + 1):
		for dy in range(-ir, ir + 1):
			for dx in range(-ir, ir + 1):
				var q := Vector3(dx, dy * 1.25, dz)
				if q.length() <= r + n.get_noise_3d(dx, dy, dz) * 1.4 and dy > -r * 0.6:
					var p := Vector3i(c) + Vector3i(dx, dy, dz)
					if world.vget(p) == Blocks.AIR:
						world.vset_raw(p, t)

# ================================================================ 锈蚀营地：南边小岛上，锈块兽们围着一个笼子

func _rust_camp() -> void:
	# 木桥：花园南端 → 营地小岛
	for z in range(76, 104):
		for x in range(36, 41):
			var edge := x == 36 or x == 40
			if h_at(x, z) >= 0:
				continue
			if edge:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G, z), Blocks.WOOD)
				if z % 4 == 0:
					world.fill_box(Vector3i(x, G + 1, z), Vector3i(x, G + 1, z), Blocks.WOOD)
			else:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G - 1, z), Blocks.PLANK)
	for x in range(37, 40):
		for z in range(76, 104):
			if h_at(x, z) < 0:
				world.fill_box(Vector3i(x, G, z), Vector3i(x, G + 3, z), Blocks.AIR)
	var c := CAMP
	# 营地地面：铺路石 + 松散的废料
	for z in range(c.z - 6, c.z + 7):
		for x in range(c.x - 6, c.x + 7):
			if h_at(x, z) == G and Vector2(x - c.x, z - c.z).length() < 6.5:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G - 1, z), Blocks.PAVING if (x + z) % 5 else Blocks.TILE)
	# 笼子：金属栏杆 + 顶棚，里面是种子方块
	for z in range(c.z - 1, c.z + 2):
		for x in range(c.x - 1, c.x + 2):
			if x == c.x and z == c.z:
				continue
			for y in range(G, G + 3):
				var cell := Vector3i(x, y, z)
				if (x + z) % 2 == 0 or y == G + 2:
					world.fill_box(cell, cell, Blocks.METAL)
					cage_cells.append(cell)
	for z in range(c.z - 1, c.z + 2):
		for x in range(c.x - 1, c.x + 2):
			var roof := Vector3i(x, G + 3, z)
			world.fill_box(roof, roof, Blocks.HULL_DARK)
			cage_cells.append(roof)
	# 一圈残破的废铁墙（锈块兽搭的）
	for k in 14:
		var a := k * TAU / 14.0
		if k % 4 == 1:
			continue
		var x := int(c.x + cos(a) * 8.5)
		var z := int(c.z + sin(a) * 8.5)
		if h_at(x, z) != G:
			continue
		var hh := 1 + (k * 7) % 3
		world.fill_box(Vector3i(x, G, z), Vector3i(x, G + hh - 1, z), Blocks.HULL_DARK if k % 2 else Blocks.METAL)
	# 木箱堆：炮台躲在后面
	world.fill_box(Vector3i(c.x - 2, G, c.z + 6), Vector3i(c.x + 2, G + 1, c.z + 6), Blocks.CRATE)
	world.fill_box(Vector3i(c.x - 6, G, c.z - 3), Vector3i(c.x - 5, G + 1, c.z - 2), Blocks.CRATE)
	world.fill_box(Vector3i(c.x + 5, G, c.z + 2), Vector3i(c.x + 5, G, c.z + 3), Blocks.CRATE)
	# 瞭望塔
	var tw := Vector3i(c.x + 7, G, c.z - 5)
	if h_at(tw.x, tw.z) == G:
		world.fill_box(tw, tw + Vector3i(0, 5, 0), Blocks.HULL_DARK)
		world.fill_box(tw + Vector3i(-1, 6, -1), tw + Vector3i(1, 6, 1), Blocks.PLANK)
		world.fill_box(tw + Vector3i(0, 7, 0), tw + Vector3i(0, 7, 0), Blocks.LAMP)
	for l in [Vector3i(c.x - 4, G, c.z - 6), Vector3i(c.x + 4, G, c.z + 5)]:
		if h_at(l.x, l.z) == G:
			lamp_post(l)

# ================================================================ 殖民地遗迹：断掉的环形天线和单轨

func _ruins() -> void:
	# E 高台南侧：半埋在土里的巨大环形天线（竖着的半圆拱，顶上断了一截）
	var ac := Vector3(97.0, G + 5.0, 61.0)
	for z in range(51, 72):
		for y in range(G + 6, G + 16):
			var d := Vector2(z - ac.z, (y - ac.y) * 1.0).length()
			if absf(d - 8.0) <= 0.75 and not (y > G + 12 and z > 60 and z < 64):
				for x in [96, 97]:
					if h_at(x, z) >= G + 6 or y > G + 6:
						world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.HULL if (y + z) % 4 else Blocks.HULL_DARK)
	# 散落的碎片
	for p in [Vector3i(99, G + 6, 58), Vector3i(94, G + 6, 64), Vector3i(100, G + 6, 63)]:
		if h_at(p.x, p.z) == G + 6:
			world.fill_box(p, p + Vector3i(1, 0, 0), Blocks.HULL)
	# 旧单轨：从 E 高台东边伸向虚空，在半空断掉
	for x in range(99, 121):
		world.fill_box(Vector3i(x, G + 10, 55), Vector3i(x, G + 10, 56), Blocks.HULL_DARK)
		if x % 2 == 0:
			world.fill_box(Vector3i(x, G + 11, 55), Vector3i(x, G + 11, 55), Blocks.TRACK)
	for x in [100, 110]:
		var h := h_at(x, 55)
		var y0 := h if h >= 0 else G + 2
		world.fill_box(Vector3i(x, y0, 55), Vector3i(x, G + 9, 56), Blocks.HULL)
	# 断口处垂下来的一截
	for k in 5:
		world.fill_box(Vector3i(121 + k / 2, G + 9 - k, 55), Vector3i(121 + k / 2, G + 9 - k, 56), Blocks.HULL_DARK)

# ================================================================ 岛边的岩石：让岛的轮廓更丰富，也挡一挡别滚下去

const OUTCROP_KEEP := [
	Rect2i(10, 62, 22, 22),     # 坠毁坑、坑口
	Rect2i(40, 48, 38, 46),     # 砂塔深沟、坡道
	Rect2i(60, 42, 12, 32),     # 温室入口
	Rect2i(66, 46, 26, 12),     # 通往 E 的小桥
	Rect2i(84, 36, 18, 22),     # 松土和洞口
	Rect2i(92, 16, 20, 66),     # 重构塔、光桥
	Rect2i(0, 40, 24, 26),      # 古树
	Rect2i(32, 76, 12, 30),     # 木桥
]

func _outcrops() -> void:
	var n := FastNoiseLite.new()
	n.seed = 44
	n.frequency = 0.21
	for key in heights.keys():
		var x: int = key.x
		var z: int = key.y
		var h: int = heights[key]
		var keep := false
		for r in OUTCROP_KEEP:
			if (r as Rect2i).has_point(Vector2i(x, z)):
				keep = true
				break
		if keep:
			continue
		# 离岛边 2 格以内
		var near_edge := false
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if h_at(x + dx, z + dz) < 0:
					near_edge = true
		if not near_edge:
			continue
		var v := n.get_noise_2d(x, z)
		if v < 0.12 or world.get_block(Vector3i(x, h, z)) != Blocks.AIR:
			continue
		var hh := 1 + int((v - 0.12) * 9.0)
		hh = mini(hh, 4)
		for y in range(h, h + hh):
			var t := Blocks.ROCK if (y - h) < hh - 1 else Blocks.MOSS
			if (x * 3 + z) % 5 == 0:
				t = Blocks.CLIFF_B
			world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), t)

## 从玩法浮岛边缘流下去的瀑布（米）
func _island_falls() -> Array:
	var out := []
	for spec in [[58, 30, Vector2i(0, -1)], [30, 60, Vector2i(-1, 0)], [100, 30, Vector2i(1, 0)], [60, 80, Vector2i(0, 1)]]:
		var x: int = spec[0]
		var z: int = spec[1]
		var d: Vector2i = spec[2]
		# 沿方向走到岛边
		var last := Vector2i(-1, -1)
		for k in 80:
			var q := Vector2i(x, z) + d * k
			if h_at(q.x, q.y) >= 0:
				last = q
			elif last.x >= 0:
				break
		if last.x < 0:
			continue
		var h := h_at(last.x, last.y)
		var top := world.voxel_center(Vector3i(last.x, h - 2, last.y)) + Vector3(d.x, 0, d.y) * 0.3
		out.append([top, Vector3(d.x, 0, d.y)])
	return out

func _tower_on() -> void:
	world.set_block(TOWER_TOP, Blocks.RECEIVER_ON)
	if vista and not is_instance_valid(_beam):
		_beam = vista.add_beam(world.voxel_center(TOWER_TOP) + Vector3.UP * 0.3, Color(0.45, 1.0, 0.8), 500.0, 0.9)

# ================================================================ 机关、收集品、对话

func _v(c: Vector3i) -> Vector3:
	return world.voxel_top(c + Vector3i.DOWN)

func _objective(i: int, text: String, cell: Vector3i, a: Vector3i, b: Vector3i) -> void:
	zone(ObjectiveZone, a, b, {"index": i, "text": text, "marker": _v(cell)})

func _fragment(id: String, cell: Vector3i, props: Dictionary) -> void:
	var f := zone(MemoryFragment, cell, cell + Vector3i(0, 1, 0), props)
	f.set("frag_id", id)
	fragments[id] = f

## 在目标附近找一块 3×3 平地放一只锈块兽
func _enemy_near(x: int, z: int) -> void:
	for r in range(0, 5):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cx := x + dx
				var cz := z + dz
				var h := h_at(cx, cz)
				if h < 0:
					continue
				var flat := true
				for oz in range(-1, 2):
					for ox in range(-1, 2):
						if h_at(cx + ox, cz + oz) != h:
							flat = false
				if flat and world.get_block(Vector3i(cx, h, cz)) == Blocks.AIR:
					var e := Scrapling.new()
					add_child(e)
					e.global_position = world.voxel_top(Vector3i(cx, h - 1, cz)) + Vector3.UP * 0.05
					e.rotation.y = randf() * TAU
					enemies.append(e)
					return

var seeds: Dictionary = {}

func _spawn_enemy(e: Node3D, cell: Vector3i, lift := 0.0) -> Node3D:
	add_child(e)
	e.global_position = world.voxel_top(cell + Vector3i.DOWN) + Vector3.UP * (0.05 + lift)
	e.rotation.y = randf() * TAU
	enemies.append(e)
	return e

func _camp_logic() -> void:
	var c := CAMP
	camp_enemies = [
		_spawn_enemy(Scrapling.new(), Vector3i(c.x - 5, G, c.z - 4)),
		_spawn_enemy(Scrapling.new(), Vector3i(c.x + 4, G, c.z + 3)),
		_spawn_enemy(Spikeshell.new(), Vector3i(c.x - 4, G, c.z + 4)),
		_spawn_enemy(Rustfly.new(), Vector3i(c.x + 3, G, c.z - 3), 2.6),
		_spawn_enemy(Mortar.new(), Vector3i(c.x, G, c.z + 8)),
	]
	for e in camp_enemies:
		e.connect("defeated", _on_camp_enemy_defeated)
	# 笼子里的种子方块
	var sc := SeedCube.new()
	sc.seed_id = "gh_s4"
	sc.line_index = 3
	add_child(sc)
	sc.global_position = world.voxel_top(c + Vector3i.DOWN)
	seeds["gh_s4"] = sc
	talk(Vector3i(34, G, 80), Vector3i(42, G + 4, 88), [
		"南边那座小岛……是锈块兽的营地？它们把一个种子方块关在笼子里！",
		"打倒营地里所有的锈蚀机器，笼子就会打开。那只刺壳虫背上全是刺——等它把刺收起来再撞。",
	])
	talk(Vector3i(c.x - 9, G, c.z - 12), Vector3i(c.x + 9, G + 4, c.z - 8), [
		"后面木箱堆后面还有一门锈炮台。看地上的红圈躲开炮弹，冲过去撞它！",
	])

func _on_camp_enemy_defeated(e: Node) -> void:
	camp_enemies.erase(e)
	var alive := 0
	for x in camp_enemies:
		if is_instance_valid(x) and not x.is_queued_for_deletion():
			alive += 1
	if alive > 0:
		FloatText.spawn(self, world.voxel_center(CAMP + Vector3i(0, 4, 0)), "还剩 %d 个" % alive, Color("ffd166"), 56, 1.4)
		return
	# 全部打倒：笼子崩开
	Sfx.play("unlock", Vector3.INF, 0.0, 0.0)
	Sfx.play("success", Vector3.INF, -4.0, 0.0)
	GameState.say("营地清理干净了！笼子的锁也坏了——去打开种子方块吧。")
	var i := 0
	for cell in cage_cells:
		i += 1
		get_tree().create_timer(0.2 + i * 0.05).timeout.connect(func() -> void:
			if world.get_block(cell) != Blocks.AIR:
				world.break_fx_at(world.voxel_center(cell), world.get_block(cell), false)
				world.set_block(cell, Blocks.AIR))
	SaveGame.set_flag("gh_camp")

## 在 (x, z) 附近找一块平地放种子方块
func _seed(id: String, x: int, z: int, line: int) -> void:
	for r in range(0, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var h := h_at(x + dx, z + dz)
				if h < 0 or world.get_block(Vector3i(x + dx, h, z + dz)) != Blocks.AIR:
					continue
				var sc := SeedCube.new()
				sc.seed_id = id
				sc.line_index = line
				add_child(sc)
				sc.global_position = world.voxel_top(Vector3i(x + dx, h - 1, z + dz))
				seeds[id] = sc
				return

func _logic() -> void:
	var marker := ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	# 敌人：花园里一只（先学会绕侧面撞），中枢塔台地一只（有了钻头可以无视盾牌）
	_enemy_near(38, 64)
	_enemy_near(96, 36)
	talk(Vector3i(30, G, 58), Vector3i(44, G + 4, 70), [
		"小心，那是锈块兽——被异变侵蚀的维护机器。它正面有盾，正面撞会被弹开。",
		"等它冲锋撞空、晕头转向的时候，或者绕到侧面、背后，再按{ability}冲撞！跳起来踩它的头也行。",
		"还有个办法：停下来按住{ability}原地蓄力，松开就冲出去——蓄满了连盾牌都能撞碎。",
	])
	# E 高台上空的锈蜂
	var fly := _spawn_enemy(Rustfly.new(), Vector3i(92, G + 6, 60), 2.8)
	talk(Vector3i(84, G + 6, 54), Vector3i(96, G + 10, 66), [
		"天上嗡嗡响的是锈蜂。它会先盯住你，地上出现红圈就是它要俯冲了——快躲开！",
		"扎进地里的锈蜂会卡住一会儿，这时候撞它。跳起来撞它、踩它也可以。",
	])
	fly.set("sight", 7.0)
	# 古树
	GameState.seeds_total = 4
	talk(Vector3i(TREE_C.x - 9, G, TREE_C.y + 3), Vector3i(TREE_C.x + 9, G + 4, TREE_C.y + 10), [
		"这棵古树比殖民地还老——艾拉博士说，方舟引擎第一次试验就是在它的树荫下做的。",
		"树枝一圈一圈往上长……按{jump}跳上去看看？掉下来也没关系。",
	])
	zone(TreasureChest, deck_cell + Vector3i(1, 0, 1), deck_cell + Vector3i(1, 1, 1), {"chest_id": "gh_tree", "coins": 30, "energy": 4})
	talk(deck_cell + Vector3i(-4, 0, -4), deck_cell + Vector3i(4, 3, 4), [
		"好高！……看东北边，云海尽头那座高塔——那是方舟星核塔，整颗星球的心脏。",
		"五座重构塔都亮起来的时候，它才会醒。……艾拉，你在那里吗？",
	])
	# 锈蚀营地
	_camp_logic()
	GameState.set_objective(0, "离开坠毁坑（东边有坡道）", _v(Vector3i(26, G, 74)))
	GameState.form_unlocked.connect(func(i: int) -> void:
		if i == MorphBall.DRILL:
			GameState.set_objective(5, "用钻头打通东边小桥上的泥土墙", _v(Vector3i(77, G + 7, 52))))
	_objective(1, "前往远处的玻璃温室（跟着金币走）", Vector3i(47, G, 72), Vector3i(27, G - 1, 68), Vector3i(31, G + 4, 80))
	_objective(2, "想办法越过深沟——看看那座砂塔", Vector3i(51, G + 2, 70), Vector3i(42, G, 62), Vector3i(51, G + 4, 80))
	_objective(3, "登上高台，进入玻璃温室", Vector3i(64, G + 6, 49), Vector3i(62, G, 64), Vector3i(68, G + 4, 76))
	_objective(4, "拿到温室中央的能量核心", DOME_C + Vector3i(0, 1, 0), Vector3i(55, G + 6, 27), Vector3i(73, G + 12, 45))
	_objective(6, "找到通往重构塔的路（试试往下钻）", Vector3i(91, G + 6, 51), Vector3i(83, G + 6, 50), Vector3i(86, G + 9, 54))
	_objective(7, "为重构塔找一块能量晶块（西边的岩丘）", Vector3i(92, G + 5, 21), Vector3i(90, G + 2, 30), Vector3i(100, G + 6, 42))
	_toys()
	# 种子方块（被封存的噗噗）：一个在显眼处教学，两个藏在需要探索的地方
	_seed("gh_s1", 30, 80, 0)
	_seed("gh_s2", 72, 30, 1)
	_seed("gh_s3", 104, 44, 2)
	# A
	zone(Checkpoint, SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"……PIX？PIX！能听到吗？我是站点 AI NOVA。你的着陆……呃，算是着陆吧。",
		"用{move}滚动，{camera}转镜头，{jump}跳。先滚出这个坑——坡道在东边。",
	])
	talk(Vector3i(21, G - 2, 70), Vector3i(26, G + 3, 78), [
		"坑口被木箱堵住了。别减速，直接撞上去——速度就是力量。",
	])
	_fragment("gh_1", deck_cell + Vector3i(-2, 0, 0), {"log_text": "艾拉·林，研究日志 #12：方舟引擎第一次成功——一块岩石被拆成方块，又被原样拼了回来。它摸起来还是暖的。"})
	coin_line(Vector3i(20, G - 2, 74), Vector3i(24, G - 1, 74), 3)
	# 重构点：花园里的旧瞭望台、锈蚀营地边的哨塔
	rebuild_tower("gh_t1", 38, 66, 120)
	rebuild_tower("gh_t2", 28, 112, 240, 14, {"coins": 30, "energy": 5})
	coin_line(Vector3i(29, G, 74), Vector3i(44, G, 74), 6)
	coin_line(Vector3i(33, G, 64), Vector3i(33, G, 67), 2)
	# C
	zone(Checkpoint, Vector3i(40, G, 71), Vector3i(44, G + 3, 76))
	talk(Vector3i(42, G, 62), Vector3i(51, G + 4, 80), [
		"这道沟太宽，冲过去、跳过去都不行——沟上还横着一根旧水管。……看那座砂塔，一半悬在沟上，全靠底下的木架撑着。",
		"路边那根橙色的支撑桩连着整片木架。撞断它会发生什么呢？",
	])
	coin_line(Vector3i(45, G, 70), Vector3i(45, G, 72), 2)
	zone(Checkpoint, Vector3i(63, G, 71), Vector3i(67, G + 3, 75))
	talk(Vector3i(62, G, 66), Vector3i(68, G + 4, 76), [
		"漂亮！砂子把沟填平了。坡道上去就是温室——艾拉博士以前的研究所。",
	])
	coin_line(Vector3i(64, G + 1, 68), Vector3i(64, G + 5, 60), 5)
	# D
	zone(Checkpoint, Vector3i(62, G + 6, 51), Vector3i(67, G + 9, 56))
	talk(Vector3i(58, G + 6, 49), Vector3i(68, G + 10, 56), [
		"温室的玻璃很结实，普通速度撞不开。按住{boost}加速，或者按{ability}冲刺！",
	])
	form_core = zone(FormCore, DOME_C + Vector3i(-1, 0, -1), DOME_C + Vector3i(1, 2, 1), {
		"form": MorphBall.DRILL,
		"unlock_text": "钻头形态解锁！按住{ability}往前钻，静止时往下钻。用{form}或{form_direct}随时切换形态。",
	})
	_fragment("gh_2", DOME_C + Vector3i(5, 0, 5), {"log_text": "艾拉·林，研究日志 #231：日冕潮的预测值又上调了。议会还在讨论撤离预算。我已经没有时间等他们了。"})
	talk(Vector3i(68, G + 6, 50), Vector3i(75, G + 10, 54), [
		"通往东边的小桥被泥土堵死了。现在你有钻头了——挖过去！",
	])
	# E
	zone(Checkpoint, Vector3i(83, G + 6, 51), Vector3i(86, G + 9, 53))
	talk(Vector3i(87, G + 6, 48), Vector3i(96, G + 10, 56), [
		"这片深色的松土……下面好像是空的。停下来按住{ability}往下钻试试。普通地面是钻不下去的，只有松土可以。",
	])
	_fragment("gh_3", Vector3i(89, G + 2, 53), {"log_text": "艾拉·林，最后一条：引擎已经启动。对不起，没来得及问你们愿不愿意。等你们醒来的时候，我会在这里。"})
	# F
	zone(Checkpoint, Vector3i(92, G + 2, 36), Vector3i(97, G + 5, 40))
	talk(Vector3i(90, G + 2, 30), Vector3i(100, G + 6, 42), [
		"这就是第一座重构塔——断电了。塔基前那个发光的凹槽需要一块能量晶块。",
		"西边那座岩丘里有紫色的晶洞——钻开它，用{grab}抓起晶块，再按{grab}扔进凹槽。",
	])
	socket = ItemSocket.new()
	add_child(socket)
	socket.setup(world, SOCKET)
	socket.filled.connect(_build_bridge)
	coin_line(Vector3i(96, G + 2, 31), Vector3i(94, G + 2, 26), 3)
	# 终点
	zone(Goal, Vector3i(100, G + 10, 76), Vector3i(108, G + 14, 86))
	# 解谜区域：旋律淡出，帮助专注
	zone(MusicZone, Vector3i(42, G - 4, 58), Vector3i(62, G + 6, 88), {"state": "puzzle"})
	zone(MusicZone, Vector3i(84, G + 2, 14), Vector3i(106, G + 8, 34), {"state": "puzzle"})

## 继续游戏：恢复存档里的进度
func apply_save(d: Dictionary) -> void:
	var forms: Array = d.get("forms", [])
	if forms.size() == 5:
		forms = [forms[0], forms[1], forms[4]]   # 旧存档（五形态）→ 滚球 / 钻头 / 气泡
	if forms.size() == GameState.unlocked_forms.size():
		for i in forms.size():
			GameState.unlocked_forms[i] = bool(forms[i])
	GameState.coins = int(d.get("coins", 0))
	GameState.coins_changed.emit(GameState.coins)
	for id in (d.get("fragments", []) as Array):
		if fragments.has(id) and is_instance_valid(fragments[id]):
			fragments[id].queue_free()
			GameState.fragments += 1
	GameState.fragments_changed.emit(GameState.fragments)
	for id in (d.get("seeds", []) as Array):
		if seeds.has(id) and is_instance_valid(seeds[id]):
			seeds[id].queue_free()
			GameState.seeds += 1
	GameState.seeds_changed.emit(GameState.seeds)
	if bool((d.get("flags", {}) as Dictionary).get("gh_camp", false)):
		for e in camp_enemies:
			if is_instance_valid(e):
				e.queue_free()
		camp_enemies.clear()
		for cell in cage_cells:
			world.set_block(cell, Blocks.AIR)
	if GameState.unlocked_forms[MorphBall.DRILL] and is_instance_valid(form_core):
		form_core.queue_free()
		Music.set_default("bright")
	if bool((d.get("flags", {}) as Dictionary).get("gh_bridge", false)):
		socket.done = true
		_build_bridge(true)
	var obj := int(d.get("objective", -1))
	if obj >= 0:
		GameState.objective_index = -1
		GameState.set_objective(obj, str(d.get("objective_text", "")), _vec(d.get("objective_pos", null)))

static func _vec(a) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() == 3 else Vector3.INF

## 开场演出：太空里的伊甸-7 → 日冕潮 → 方舟引擎把星球拆成方块 → 云海上的浮岛 → 熄灭的重构塔 → 坠落 → NOVA 苏醒
const STAGE_POS := Vector3(40.0, 160.0, -320.0)
var _stage: IntroStage

func cutscene_event(n: String) -> void:
	match n:
		"space":
			_stage = IntroStage.new()
			add_child(_stage)
			_stage.global_position = STAGE_POS
			_stage.play()
		"land", "end":
			if is_instance_valid(_stage):
				_stage.queue_free()
		"crash":
			crash_fx()

func intro_shots() -> Array:
	var V := VoxelWorld.CELL_M
	var c := Vector3(64, G, 50) * V
	var S := STAGE_POS
	return [
		{"from": S + Vector3(5, 3, 24), "to": S + Vector3(-2, 4, 19), "look": S, "dur": 7.0, "event": "space", "fade": Color.BLACK,
			"lines": [["", "星历 3124 年，殖民星球「伊甸-7」。"], ["", "一万两千个居民，一片安静的森林和海。"]]},
		{"from": S + Vector3(15, 2, 16), "to": S + Vector3(11, 3, 12), "look_from": S, "look_to": S + Vector3(-4, 0.5, -3), "dur": 6.0,
			"lines": [["", "那一年，恒星爆发了百年一遇的日冕潮。"], ["", "撤离，已经来不及了。"]]},
		{"from": S + Vector3(0, 5, 17), "to": S + Vector3(2, 12, 33), "look": S, "dur": 8.0,
			"lines": [["", "最后一小时，艾拉·林博士启动了「方舟引擎」。"], ["", "整颗星球——陆地、森林、城市和所有居民——被拆成了方块。"]]},
		{"from": Vector3(-30, 60, 150) * V, "to": Vector3(20, 45, 140) * V, "look": c, "dur": 7.0, "event": "land", "fade": Color(1, 1, 1),
			"lines": [["", "方块们被托上云海，躲过了那场风暴。"], ["", "按照计划，三年后五座重构塔会一同点亮，把星球重新拼回来。"]]},
		{"from": Vector3(40, 34, 70) * V, "to": Vector3(52, 32, 62) * V, "look_from": Vector3(64, 28, 36) * V, "look_to": Vector3(100, 30, 24) * V, "dur": 7.0,
			"lines": [["", "三年过去了。"], ["", "一座塔也没有亮。"]]},
		{"from": Vector3(40, 30, 110) * V, "to": Vector3(32, 26, 100) * V, "look_from": Vector3(10, 70, 60) * V, "look_to": Vector3(15, 18, 74) * V, "dur": 3.4, "event": "crash",
			"lines": [["", "直到今天——"]]},
		{"from": Vector3(31, 28, 90) * V, "to": Vector3(26, 25.5, 85) * V, "look": Vector3(16, 18.5, 74) * V, "dur": 10.0,
			"lines": [["NOVA", "……信号确认。维护单元 PIX，启动。"], ["NOVA", "我是 NOVA。你是「摇篮号」上最后一台维护球——三年了，终于有人来了。"], ["NOVA", "东边那座熄灭的塔，就是第一座重构塔。先离开这个坑。"]]},
	]

## 飞船坠落特效
func crash_fx() -> void:
	var V := VoxelWorld.CELL_M
	var target := Vector3(14, G - 1, 74) * V
	var start := target + Vector3(-30, 45, -40)
	var pod := Node3D.new()
	add_child(pod)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ffd9a0")
	m.emission_enabled = true
	m.emission = Color("ff9a3c")
	m.emission_energy_multiplier = 6.0
	sm.material = m
	mi.mesh = sm
	pod.add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 80
	trail.lifetime = 1.2
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 1.0
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.6
	var tm := SphereMesh.new()
	tm.radius = 0.4
	tm.height = 0.8
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(1.0, 0.7, 0.4, 0.5)
	tm.material = tmat
	trail.mesh = tm
	pod.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb060")
	light.light_energy = 4.0
	light.omni_range = 12.0
	pod.add_child(light)
	pod.global_position = start
	Sfx.play("meteor", Vector3.INF, -2.0, 0.0)
	var tw := create_tween()
	tw.tween_property(pod, "global_position", target, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	Sfx.play("impact_big", Vector3.INF, 0.0, 0.0)
	GameState.shake.emit(0.9)
	_place_ship()
	light.light_energy = 16.0
	light.omni_range = 30.0
	mi.visible = false
	trail.emitting = false
	var tw2 := create_tween()
	tw2.tween_property(light, "light_energy", 0.0, 1.2)
	tw2.tween_callback(pod.queue_free)

func _on_item_dropped(item_id: String, pos: Vector3) -> void:
	if item_id == "crystal" and not is_instance_valid(crystal) and not socket.done:
		crystal = UsableItem.new()
		crystal.item_id = "crystal"
		add_child(crystal)
		crystal.global_position = pos + Vector3.UP * 0.3
		crystal.home = crystal.global_position
		crystal.linear_velocity = Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1))
		GameState.say("能量晶块！它有发光描边——有用的东西会留在场上。按{grab}抓起来。")
		GameState.set_objective(8, "把晶块扔进重构塔前的发光凹槽", _v(SOCKET + Vector3i.UP))

## 光桥：一格一格亮起来
func _build_bridge(instant := false) -> void:
	if bridge_built:
		return
	bridge_built = true
	if instant:
		for cell in bridge_cells:
			if cell[1] == 0:
				world.set_block(cell[0], Blocks.CRYSTAL)
			else:
				world.set_ramp(cell[0], Blocks.CRYSTAL, cell[1])
		_tower_on()
		return
	_tower_on()
	reconstruct(world.voxel_center(Vector3i(TOWER_TOP.x, G + 2, TOWER_TOP.z)), 90.0)
	GameState.say("第一座重构塔……重新上线了！光桥正在展开——终点浮岛上是这片群岛的引擎节点。")
	GameState.set_objective(9, "沿光桥登上终点浮岛", _v(Vector3i(104, G + 11, 81)))
	SaveGame.set_flag("gh_bridge")
	SaveGame.write()
	Sfx.play("bridge", Vector3.INF, -2.0, 0.0)
	var i := 0
	for cell in bridge_cells:
		i += 1
		var p: Vector3i = cell[0]
		var shape: int = cell[1]
		get_tree().create_timer(0.3 + i * 0.012).timeout.connect(func() -> void:
			if shape == 0:
				world.set_block(p, Blocks.CRYSTAL)
			else:
				world.set_ramp(p, Blocks.CRYSTAL, shape))
