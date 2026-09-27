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

const SIZE := Vector3i(128, 44, 100)
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
]

const SPAWN := Vector3i(19, G - 2, 74)
const PIT_X := Vector2i(52, 61)
const RAMP_CD := Rect2i(63, 59, 4, 12)      # x, z, 宽, 长（沿 -Z 升高）
const DOME_C := Vector3i(64, G + 6, 36)
const DOME_R := 11
const SOCKET := Vector3i(100, G + 1, 29)

var heights := {}          # Vector2i -> 地面高度（第一个空气层的 y）
var backdrop := false      ## 只当标题画面背景：不放机关、不放音乐
var socket: ItemSocket
var enemies: Array[Scrapling] = []
var form_core: Node
var fragments := {}        # id -> 节点
var crystal: UsableItem
var bridge_cells: Array = []
var bridge_built := false
var _noise := FastNoiseLite.new()

## 出生时的镜头朝向：从西南方看过去，避开坠毁的飞船，东边的出口在画面右侧
func spawn_yaw() -> float:
	return -0.75

func spawn_position() -> Vector3:
	return world.voxel_top(SPAWN + Vector3i.DOWN) + Vector3.UP * 0.55

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	if not backdrop:
		GameState.reset_for_level([true, false, false] as Array[bool], true, 1.0, 3)
	var sky := SkyWorld.new()
	sky.center = Vector3(SIZE.x * 0.25, 0, SIZE.z * 0.25)
	add_child(sky)
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
	world.rebuild_all()
	scatter_decor(Vector3i(0, G - 3, 0), Vector3i(SIZE.x - 1, G + 12, SIZE.z - 1), 0.28, 0.07)
	decor.commit()
	if backdrop:
		return
	_logic()
	world.item_dropped.connect(_on_item_dropped)
	Music.set_default("explore")
	Music.set_override("")
	Music.play_area("gh")
	GameState.set_checkpoint(spawn_position())

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
	world.fill_box(Vector3i(51, G - 1, 70), Vector3i(51, G + 1, 70), Blocks.SUPPORT)
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
				world.fill_box(Vector3i(56, G + 2, z), Vector3i(57, G + 3, z), Blocks.METAL)
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
	# 塔身
	world.fill_box(pc + Vector3i(-1, 0, -1), pc + Vector3i(1, 12, 1), Blocks.HULL)
	world.fill_box(pc + Vector3i(-2, 0, -2), pc + Vector3i(2, 1, 2), Blocks.HULL_DARK)
	for y in [4, 8]:
		world.fill_box(pc + Vector3i(-1, y, -1), pc + Vector3i(1, y, 1), Blocks.LAMP)
	world.fill_box(pc + Vector3i(0, 13, 0), pc + Vector3i(0, 14, 0), Blocks.RECEIVER)
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

func _logic() -> void:
	var marker := ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	# 敌人：花园里一只（先学会绕侧面撞），中枢塔台地一只（有了钻头可以无视盾牌）
	_enemy_near(38, 64)
	_enemy_near(96, 36)
	talk(Vector3i(30, G, 58), Vector3i(44, G + 4, 70), [
		"小心，那是锈块兽——被异变侵蚀的维护机器。它正面有盾，正面撞会被弹开。",
		"等它冲锋撞空、晕头转向的时候，或者绕到侧面、背后，再按{ability}冲撞！",
	])
	GameState.set_objective(0, "离开坠毁坑（东边有坡道）", _v(Vector3i(26, G, 74)))
	GameState.form_unlocked.connect(func(i: int) -> void:
		if i == MorphBall.DRILL:
			GameState.set_objective(5, "用钻头打通东边小桥上的泥土墙", _v(Vector3i(77, G + 7, 52))))
	_objective(1, "前往远处的玻璃温室（跟着金币走）", Vector3i(47, G, 72), Vector3i(27, G - 1, 68), Vector3i(31, G + 4, 80))
	_objective(2, "想办法越过深沟——看看那座砂塔", Vector3i(51, G + 2, 70), Vector3i(42, G, 62), Vector3i(51, G + 4, 80))
	_objective(3, "登上高台，进入玻璃温室", Vector3i(64, G + 6, 49), Vector3i(62, G, 64), Vector3i(68, G + 4, 76))
	_objective(4, "拿到温室中央的能量核心", DOME_C + Vector3i(0, 1, 0), Vector3i(55, G + 6, 27), Vector3i(73, G + 12, 45))
	_objective(6, "找到通往中枢塔的路（试试往下钻）", Vector3i(91, G + 6, 51), Vector3i(83, G + 6, 50), Vector3i(86, G + 9, 54))
	_objective(7, "为中枢塔找一块能量晶块（西边的岩丘）", Vector3i(92, G + 5, 21), Vector3i(90, G + 2, 30), Vector3i(100, G + 6, 42))
	# A
	zone(Checkpoint, SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"……PIX？PIX！能听到吗？我是站点 AI NOVA。你的着陆……呃，算是着陆吧。",
		"用{move}滚动，{camera}转镜头，{jump}跳。先滚出这个坑——坡道在东边。",
	])
	talk(Vector3i(21, G - 2, 70), Vector3i(26, G + 3, 78), [
		"坑口被木箱堵住了。别减速，直接撞上去——速度就是力量。",
	])
	_fragment("gh_1", Vector3i(12, G - 2, 79), {"log_text": "艾拉博士，第 12 天：引擎能把一块岩石变成可以随意拆装的方块。整颗星球都能这样就好了。"})
	coin_line(Vector3i(20, G - 2, 74), Vector3i(24, G - 1, 74), 3)
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
		"漂亮！砂子把沟填平了。坡道上去就是温室——整座站点的心脏。",
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
	_fragment("gh_2", DOME_C + Vector3i(5, 0, 5), {"log_text": "艾拉博士，第 40 天：星核的读数越来越不稳定。他们说我太紧张了。"})
	talk(Vector3i(68, G + 6, 50), Vector3i(75, G + 10, 54), [
		"通往东边的小桥被泥土堵死了。现在你有钻头了——挖过去！",
	])
	# E
	zone(Checkpoint, Vector3i(83, G + 6, 51), Vector3i(86, G + 9, 53))
	talk(Vector3i(87, G + 6, 48), Vector3i(96, G + 10, 56), [
		"这片深色的松土……下面好像是空的。停下来按住{ability}往下钻试试。普通地面是钻不下去的，只有松土可以。",
	])
	_fragment("gh_3", Vector3i(89, G + 2, 53), {"log_text": "艾拉博士，最后一天：我启动了引擎。对不起，这是唯一能保住所有人的办法。"})
	# F
	zone(Checkpoint, Vector3i(92, G + 2, 36), Vector3i(97, G + 5, 40))
	talk(Vector3i(90, G + 2, 30), Vector3i(100, G + 6, 42), [
		"中枢塔断电了。塔基前那个发光的凹槽需要一块能量晶块。",
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

## 开场演出：云海全景 → 熄灭的温室与中枢塔 → 飞船坠落 → NOVA 苏醒
func intro_shots() -> Array:
	var V := VoxelWorld.VOXEL
	var c := Vector3(64, G, 50) * V
	return [
		{"black": true, "from": Vector3(-40, 40, 140) * V, "to": Vector3(-20, 38, 130) * V, "look": c, "dur": 4.5,
			"lines": [["", "星历 3127 年。"], ["", "殖民星球「立方-7」的最后一条通讯，停在三年前。"]]},
		{"from": Vector3(-30, 60, 150) * V, "to": Vector3(20, 45, 140) * V, "look": c, "dur": 6.0,
			"lines": [["", "那一天，整颗星球像被某种力量拆开、又重新拼起——"], ["", "变成了漂浮在云海之上的方块。"]]},
		{"from": Vector3(40, 34, 70) * V, "to": Vector3(52, 32, 62) * V, "look_from": Vector3(64, 28, 36) * V, "look_to": Vector3(100, 30, 24) * V, "dur": 6.0,
			"lines": [["", "研究站的灯一盏接一盏熄灭。没有人知道科学家们去了哪里。"], ["", "直到今天。"]]},
		{"from": Vector3(40, 30, 110) * V, "to": Vector3(32, 26, 100) * V, "look_from": Vector3(10, 70, 60) * V, "look_to": Vector3(15, 18, 74) * V, "dur": 3.2, "event": "crash"},
		{"from": Vector3(31, 28, 90) * V, "to": Vector3(26, 25.5, 85) * V, "look": Vector3(16, 18.5, 74) * V, "dur": 7.5,
			"lines": [["NOVA", "……信号确认。维护单元 PIX，启动。"], ["NOVA", "我是站点 AI「NOVA」。三年了……终于有人来了。"], ["NOVA", "先离开这个坑。温室和中枢塔都在东边——我得弄清楚，这里到底发生了什么。"]]},
	]

## 飞船坠落特效
func crash_fx() -> void:
	var V := VoxelWorld.VOXEL
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
	Sfx.play("dash", Vector3.INF, 4.0, 0.0)
	var tw := create_tween()
	tw.tween_property(pod, "global_position", target, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	Sfx.play("break_hard", Vector3.INF, 6.0, 0.0)
	Sfx.play("thud", Vector3.INF, 6.0, 0.0)
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
		GameState.set_objective(8, "把晶块扔进中枢塔前的发光凹槽", _v(SOCKET + Vector3i.UP))

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
		world.set_block(Vector3i(100, G + 2 + 13, 24), Blocks.RECEIVER_ON)
		return
	world.set_block(Vector3i(100, G + 2 + 13, 24), Blocks.RECEIVER_ON)
	GameState.say("中枢塔重新上线！……光桥正在展开。终点浮岛上就是温室的能量核心。")
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
