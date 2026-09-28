class_name AreaGearworks
extends LevelBase
## 第二章 · 齿轮工坊：以前全星球的零件都在这里生产。现在断电、生锈、长满了枯荆棘。
## 这一章的谜题全部靠“系统”：
##   A 停机坪 → 枯荆棘路障：从炭火盆拿火种，扔过去烧开（火会顺着可燃物蔓延）
##   B 断崖 → 木脚手架撑着一块石板悬在断崖上方：烧掉脚手架，石板落在两边的铁轨上变成桥
##   C 工坊厂区：发电机的两条线——铜线给储料场门口的电网供电（钻断它），
##      金属管线给厂房大门供电但缺了一截（从储料场拿能量晶块补上）
##   D 厂房里拿到气泡形态；穿过有节奏的喷火口（或用气浪吹熄），乘上升气流到空中走廊
##   E 走廊尽头的加固墙：拿火种点燃燃料桶，炸开它 → 第二座重构塔
## 坐标单位为“格”（0.5 米）。

const SIZE := Vector3i(124, 52, 96)
const G := 22

## 浮岛：[中心 x, 中心 z, 半径, 地面高度]
const BLOBS := [
	[14, 76, 11, G],        # A 停机坪
	[27, 76, 6, G],         # A→B 窄道（荆棘路障）
	[38, 76, 8, G],         # B
	[43, 76, 6, G],         # B 断崖边
	[65, 77, 7, G],         # C 断崖东岸
	[66, 62, 8, G],         # C 发电机
	[79, 67, 13, G],        # C 厂房
	[91, 66, 9, G],         # C 厂房东
	[89, 49, 9, G],         # C 储料场
	[76, 50, 8, G],         # C 储料场西
	[109, 61, 8, G + 10],   # D 重构塔浮岛
]

const SPAWN := Vector3i(12, G, 78)
const BARRICADE_X := 30
const CHASM := Vector2i(48, 59)          ## 断崖 x 范围（含），整条 z 都是空的
const SLAB_Z := Vector2i(73, 80)
const SOURCE := Vector3i(65, G, 56)
const GAP := Vector3i(68, G, 60)         ## 大门供电管线缺的那一截
const DOOR_RCV := Vector3i(69, G, 65)
const FENCE_RCV := Vector3i(85, G, 53)
const HALL := Rect2i(70, 58, 19, 19)     ## x 70..88, z 58..76
const CORE := Vector3i(78, G, 68)
const FAN_RCV := Vector3i(84, G, 62)
const WALK_Y := G + 9                    ## 空中走廊地板所在层
const BLAST_X := 97
const TOWER := Vector3i(110, G + 10, 61)

var heights := {}
var backdrop := false
var enemies: Array[Scrapling] = []
var fragments := {}
var seeds: Dictionary = {}
var form_core: Node
var grid: PowerGrid
var socket: ItemSocket
var crystal: UsableItem
var door: PowerDoor
var _noise := FastNoiseLite.new()
var slab_fallen := false
var wall_blown := false

func spawn_yaw() -> float:
	return -PI / 2.0

func spawn_position() -> Vector3:
	return world.voxel_top(SPAWN + Vector3i.DOWN) + Vector3.UP * 0.55

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	world.setup(SIZE)
	GameState.reset_for_level([true, true, false] as Array[bool], true, 2.0, 3)
	decor = Decor.new()
	add_child(decor)
	decor.setup(world)
	rng.seed = 2207
	_noise.seed = 77
	_noise.frequency = 0.09
	_terrain()
	_dock()
	_barricade()
	_chasm()
	_yard()
	_hall()
	_catwalk()
	_tower_island()
	world.naturalize(G + 14, [
		AABB(Vector3(26, 0, 60), Vector3(8, 52, 32)),            # 荆棘路障
		AABB(Vector3(42, 0, 66), Vector3(26, 52, 22)),           # 断崖两岸
		AABB(Vector3(HALL.position.x - 2, 0, 40), Vector3(34, 52, 40)),   # 厂区、储料场
		AABB(Vector3(96, 0, 50), Vector3(24, 52, 22)),           # 塔
	])
	world.rebuild_all()
	scatter_decor(Vector3i(0, G - 3, 0), Vector3i(SIZE.x - 1, G + 14, SIZE.z - 1), 0.22, 0.05, 0.02)
	decor.commit()
	_dress()
	world.flush_dirty()
	world.fire.scan_sources(Vector3i(0, G - 2, 0), Vector3i(SIZE.x - 1, G + 16, SIZE.z - 1))
	if backdrop:
		return
	_logic()
	world.item_dropped.connect(_on_item_dropped)
	Music.set_default("explore")
	Music.set_override("")
	Music.play_area("gw")
	GameState.set_checkpoint(spawn_position())

# ================================================================ 地形

func h_at(x: int, z: int) -> int:
	return heights.get(Vector2i(x, z), -1)

func _set_h(x: int, z: int, h: int) -> void:
	heights[Vector2i(x, z)] = h

func _column(x: int, z: int, h: int, depth: int, top := Blocks.GRASS) -> void:
	world.fill_column(x, z, 0, SIZE.y - 1, Blocks.AIR)
	if h < 0:
		heights.erase(Vector2i(x, z))
		return
	var bottom := maxi(1, h - depth)
	world.fill_column(x, z, bottom, h - 4, Blocks.CLIFF)
	world.fill_column(x, z, maxi(bottom, h - 3), h - 2, Blocks.DIRT)
	world.fill_column(x, z, h - 1, h - 1, top)

func _terrain() -> void:
	for z in SIZE.z:
		for x in SIZE.x:
			if x >= CHASM.x and x <= CHASM.y:
				continue
			var best := -1
			var edge := 0.0
			for b in BLOBS:
				# 断崖两边的地块不越界
				if b[0] < CHASM.x and x >= CHASM.x or b[0] > CHASM.y and x <= CHASM.y:
					continue
				var d := Vector2(x - b[0], z - b[1]).length()
				var r: float = b[2] + _noise.get_noise_2d(x, z) * 2.2
				if d <= r:
					best = maxi(best, b[3])
					edge = maxf(edge, r - d)
			if best < 0:
				continue
			_set_h(x, z, best)
			var depth := 4 + int(clampf(edge * 1.1, 0.0, 14.0)) + int(_noise.get_noise_2d(x * 3, z * 3) * 2.0)
			_column(x, z, best, depth + (best - G))
	# 断崖两岸：直直的崖壁，保证石板两头有地方落
	for z in range(SLAB_Z.x - 3, SLAB_Z.y + 4):
		for x in range(CHASM.x - 4, CHASM.x):
			_set_h(x, z, G)
			_column(x, z, G, 12, Blocks.PAVING)
		for x in range(CHASM.y + 1, CHASM.y + 5):
			_set_h(x, z, G)
			_column(x, z, G, 12, Blocks.PAVING)

func _flatten(x0: int, z0: int, x1: int, z1: int, h: int, top := Blocks.GRASS) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			_set_h(x, z, h)
			_column(x, z, h, 10 + (h - G), top)

## 把地表换成某种铺装（只换最上面一格）
func _pave(x0: int, z0: int, x1: int, z1: int, t: int) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var h := h_at(x, z)
			if h >= 0:
				world.fill_box(Vector3i(x, h - 1, z), Vector3i(x, h - 1, z), t)

# ================================================================ A 停机坪

func _dock() -> void:
	# 停机坪：深色金属地面 + 白色描边 + 四角的灯
	_flatten(6, 70, 18, 86, G, Blocks.HULL_DARK)
	for z in range(70, 87):
		for x in range(6, 19):
			if x == 6 or x == 18 or z == 70 or z == 86:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G - 1, z), Blocks.HULL)
	for c in [Vector3i(6, G, 70), Vector3i(18, G, 70), Vector3i(6, G, 86), Vector3i(18, G, 86)]:
		world.fill_box(c, c, Blocks.LAMP)
	# 通往路障的小路
	_pave(19, 75, BARRICADE_X - 1, 78, Blocks.PAVING)
	# 炭火盆：金属盆里一堆炭火，火种从这里拿
	_brazier(Vector3i(24, G, 72))

func _brazier(c: Vector3i) -> void:
	_pave(c.x - 2, c.z - 2, c.x + 2, c.z + 2, Blocks.PAVING)
	world.fill_box(c + Vector3i(-1, 0, -1), c + Vector3i(1, 0, 1), Blocks.METAL)
	world.fill_box(c, c, Blocks.EMBER)

# ================================================================ A→B 枯荆棘路障

func _barricade() -> void:
	# 窄道整个宽度都长满枯荆棘（撞不开、钻不动，只能烧），两层厚、四层高
	for z in range(60, 92):
		if h_at(BARRICADE_X, z) < 0 and h_at(BARRICADE_X + 1, z) < 0:
			continue
		world.fill_box(Vector3i(BARRICADE_X, G, z), Vector3i(BARRICADE_X + 1, G + 3, z), Blocks.BRAMBLE)
	# 路障前后铺路，免得草地一直烧过去
	_pave(BARRICADE_X - 3, 60, BARRICADE_X + 4, 91, Blocks.PAVING)

# ================================================================ B 断崖与石板桥

func _chasm() -> void:
	var y := G - 2
	# 两边崖壁上的铁轨（石板落下后架在上面），比石板略长一点
	world.fill_box(Vector3i(CHASM.x, y, SLAB_Z.x - 1), Vector3i(CHASM.x + 1, y, SLAB_Z.y + 1), Blocks.METAL)
	world.fill_box(Vector3i(CHASM.y - 2, y, SLAB_Z.x - 1), Vector3i(CHASM.y, y, SLAB_Z.y + 1), Blocks.METAL)
	if SaveGame.flag("gw_slab"):
		_slab_down()
		return
	# 木脚手架塔（立在西边铁轨上，比石板还高）从侧面托着一整块石板，悬在断崖上方——跳不过去，也跳不上去
	world.fill_box(Vector3i(CHASM.x, G - 1, SLAB_Z.x), Vector3i(CHASM.x, G + 4, SLAB_Z.y), Blocks.SCAFFOLD)
	# 脚手架的木板（薄薄一层，0.25 米）一直铺到崖边的地面上：火种放在木板上就能引过去
	var C := VoxelWorld.CELL
	world.vfill(Vector3i((CHASM.x - 3) * C, G * C, (SLAB_Z.x + 1) * C), Vector3i(CHASM.x * C - 1, G * C, SLAB_Z.y * C - 1), Blocks.SCAFFOLD)
	world.fill_box(Vector3i(CHASM.x + 1, G + 2, SLAB_Z.x), Vector3i(CHASM.y, G + 2, SLAB_Z.y), Blocks.ROCK)
	# 断崖西边的第二个炭火盆
	_brazier(Vector3i(42, G, 70))

## 已经塌下来的石板（读档时直接放好）
func _slab_down() -> void:
	slab_fallen = true
	world.fill_box(Vector3i(CHASM.x + 1, G - 1, SLAB_Z.x), Vector3i(CHASM.y, G - 1, SLAB_Z.y), Blocks.ROCK)
	_patch_gap()

## 脚手架塔烧掉后，西头铁轨上方留下一条缝：补一块石头，桥面和崖边齐平
func _patch_gap() -> void:
	for z in range(SLAB_Z.x, SLAB_Z.y + 1):
		if world.get_block(Vector3i(CHASM.x, G - 1, z)) == Blocks.AIR:
			world.set_block(Vector3i(CHASM.x, G - 1, z), Blocks.ROCK)

# ================================================================ C 工坊厂区

func _yard() -> void:
	_pave(60, 44, 99, 86, Blocks.PAVING)
	# 发电机：金属底座 + 能量源
	world.fill_box(SOURCE + Vector3i(-1, -1, -1), SOURCE + Vector3i(1, -1, 1), Blocks.METAL)
	world.fill_box(SOURCE, SOURCE, Blocks.SOURCE)
	world.fill_box(SOURCE + Vector3i(0, 1, 0), SOURCE + Vector3i(0, 1, 0), Blocks.HULL_DARK)
	# 大门供电：地面上的金属管线（打不坏），中间缺一截
	world.fill_box(Vector3i(66, G, 56), Vector3i(68, G, 56), Blocks.METAL)
	world.fill_box(Vector3i(68, G, 57), Vector3i(68, G, 65), Blocks.METAL)
	world.fill_box(GAP, GAP, Blocks.AIR)
	world.fill_box(DOOR_RCV, DOOR_RCV, Blocks.RECEIVER)
	# 电网供电：嵌在地面里的铜线（钻得断），一路通到储料场门口
	world.fill_box(Vector3i(65, G - 1, 56), Vector3i(65, G - 1, 54), Blocks.COPPER)
	world.fill_box(Vector3i(65, G - 1, 54), Vector3i(85, G - 1, 54), Blocks.COPPER)
	world.fill_box(Vector3i(85, G - 1, 53), Vector3i(85, G - 1, 53), Blocks.COPPER)
	world.fill_box(FENCE_RCV, FENCE_RCV, Blocks.RECEIVER)
	# 储料场：三格高的加固墙围起来，南墙中间留一个门（被电网封着）
	var lo := Vector2i(80, 41)
	var hi := Vector2i(97, 52)
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if h_at(x, z) < 0:
				continue
			var edge := x == lo.x or x == hi.x or z == lo.y or z == hi.y
			var gate := z == hi.y and x >= 86 and x <= 88
			if edge and not gate:
				world.fill_box(Vector3i(x, G, z), Vector3i(x, G + 2, z), Blocks.REINFORCED)
	# 岛边缘没有地面的地方也补上墙，免得从外面绕进去
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if h_at(x, z) < 0 and (h_at(x + 1, z) >= 0 or h_at(x - 1, z) >= 0 or h_at(x, z + 1) >= 0 or h_at(x, z - 1) >= 0):
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G + 2, z), Blocks.REINFORCED)
	# 储料场里：物资箱（能量晶块）+ 普通木箱
	world.fill_box(Vector3i(92, G, 45), Vector3i(92, G, 45), Blocks.CRATE_ITEM)
	for c in [Vector3i(84, G, 44), Vector3i(94, G, 48), Vector3i(89, G, 43)]:
		world.fill_box(c, c + Vector3i(1, 1, 0), Blocks.CRATE)
	# 厂区里的灯
	for l in [Vector3i(62, G, 70), Vector3i(62, G, 62), Vector3i(72, G, 54), Vector3i(80, G, 56)]:
		lamp_post(l)
	# 厂区东南的枯荆棘小花园（里面封着一个种子方块）
	var gc := Vector3i(63, G, 81)
	for z in range(gc.z - 2, gc.z + 3):
		for x in range(gc.x - 2, gc.x + 3):
			if absi(x - gc.x) == 2 or absi(z - gc.z) == 2:
				if h_at(x, z) >= 0:
					world.fill_box(Vector3i(x, G, z), Vector3i(x, G + 2, z), Blocks.BRAMBLE)
	_brazier(Vector3i(64, G, 72))

# ================================================================ D 厂房

func _hall() -> void:
	var x0 := HALL.position.x
	var z0 := HALL.position.y
	var x1 := HALL.end.x - 1
	var z1 := HALL.end.y - 1
	_flatten(x0, z0, x1, z1, G, Blocks.TILE)
	# 外墙：深色舱体 + 金属立柱，高 8 格（4 米）；高处一排窗
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if x != x0 and x != x1 and z != z0 and z != z1:
				continue
			var pillar := (x - x0) % 4 == 0 and (z - z0) % 4 == 0
			world.fill_box(Vector3i(x, G, z), Vector3i(x, G + 7, z), Blocks.METAL if pillar else Blocks.HULL_DARK)
			if not pillar and (x + z) % 2 == 0:
				world.fill_box(Vector3i(x, G + 5, z), Vector3i(x, G + 6, z), Blocks.GLASS)
	# 西墙大门（电控门）
	door = PowerDoor.new()
	add_child(door)
	var dc: Array[Vector3i] = []
	for z in range(66, 69):
		for y in range(G, G + 4):
			dc.append(Vector3i(x0, y, z))
	door.setup(world, dc, [DOOR_RCV] as Array[Vector3i])
	# 门口外墙上嵌一块金属，把大门的电接进厂房
	world.fill_box(Vector3i(x0, G, 65), Vector3i(x0, G, 65), Blocks.METAL)
	# 厂房里的管线：沿北墙根走到东北角的风扇
	world.fill_box(Vector3i(x0 + 1, G, 59), Vector3i(x0 + 1, G, 65), Blocks.METAL)
	world.fill_box(Vector3i(x0 + 1, G, 59), Vector3i(84, G, 59), Blocks.METAL)
	world.fill_box(Vector3i(84, G, 60), Vector3i(84, G, 61), Blocks.METAL)
	world.fill_box(FAN_RCV, FAN_RCV, Blocks.RECEIVER)
	# 东侧隔墙：隔出一条南北向的走廊，南头开口；喷火口在走廊里
	for z in range(z0 + 1, z1):
		if z >= 72:
			continue
		world.fill_box(Vector3i(83, G, z), Vector3i(83, G + 4, z), Blocks.HULL_DARK if z != 59 else Blocks.METAL)
	for z in [70, 66]:
		world.fill_box(Vector3i(84, G - 1, z), Vector3i(87, G - 1, z), Blocks.VENT)
	# 中央的能量核心底座
	for z in range(CORE.z - 2, CORE.z + 3):
		for x in range(CORE.x - 2, CORE.x + 3):
			if Vector2(x - CORE.x, z - CORE.z).length() <= 2.3:
				world.fill_box(Vector3i(x, G - 1, z), Vector3i(x, G - 1, z), Blocks.PAVING)
	# 几台旧机器（装饰用的金属块和木箱，木箱可以撞）
	for c in [Vector3i(73, G, 72), Vector3i(73, G, 62), Vector3i(80, G, 73)]:
		world.fill_box(c, c + Vector3i(1, 1, 1), Blocks.CRATE)
	world.fill_box(Vector3i(76, G, 61), Vector3i(79, G + 1, 62), Blocks.METAL)

# ================================================================ E 空中走廊

func _catwalk() -> void:
	var y := WALK_Y
	# 从风扇顶上一直通到重构塔浮岛
	world.fill_box(Vector3i(84, y, 59), Vector3i(101, y, 62), Blocks.METAL)
	# 两侧栏杆（出厂房以后）
	world.fill_box(Vector3i(89, y + 1, 58), Vector3i(101, y + 2, 58), Blocks.METAL)
	world.fill_box(Vector3i(89, y + 1, 63), Vector3i(101, y + 2, 63), Blocks.METAL)
	world.fill_box(Vector3i(84, y + 1, 58), Vector3i(88, y + 1, 58), Blocks.METAL)
	# 支撑柱
	for x in [92, 96, 100]:
		world.fill_box(Vector3i(x, G, 60), Vector3i(x, y - 1, 60), Blocks.HULL_DARK)
		world.fill_box(Vector3i(x, G, 61), Vector3i(x, y - 1, 61), Blocks.HULL_DARK)
	# 加固墙 + 燃料桶
	if not SaveGame.flag("gw_blast"):
		world.fill_box(Vector3i(BLAST_X, y + 1, 58), Vector3i(BLAST_X, y + 4, 63), Blocks.REINFORCED)
		# 一排燃料桶贴着墙根摆满走廊，上面再叠两个
		world.fill_box(Vector3i(BLAST_X - 1, y + 1, 59), Vector3i(BLAST_X - 1, y + 1, 62), Blocks.BARREL)
		world.fill_box(Vector3i(BLAST_X - 1, y + 2, 59), Vector3i(BLAST_X - 1, y + 2, 59), Blocks.BARREL)
		world.fill_box(Vector3i(BLAST_X - 1, y + 2, 62), Vector3i(BLAST_X - 1, y + 2, 62), Blocks.BARREL)
	else:
		wall_blown = true
	# 走廊上的炭火盆（小，一格）
	world.fill_box(Vector3i(90, y + 1, 62), Vector3i(90, y + 1, 62), Blocks.METAL)
	world.fill_box(Vector3i(90, y + 2, 62), Vector3i(90, y + 2, 62), Blocks.EMBER)
	# 走廊边上一座小平台（气泡空中再跳才上得去），上面有种子方块
	world.fill_box(Vector3i(92, y + 2, 66), Vector3i(94, y + 2, 68), Blocks.METAL)

# ================================================================ F 重构塔浮岛

func _tower_island() -> void:
	var t := TOWER
	_pave(t.x - 4, t.z - 4, t.x + 4, t.z + 4, Blocks.PAVING)
	# 塔基
	for z in range(t.z - 2, t.z + 3):
		for x in range(t.x - 2, t.x + 3):
			if Vector2(x - t.x, z - t.z).length() <= 2.4:
				world.fill_box(Vector3i(x, t.y, z), Vector3i(x, t.y, z), Blocks.HULL)
	# 塔身：白色外壳，每隔几层一圈水晶
	for y in range(t.y + 1, t.y + 17):
		var ring := (y - t.y) % 5 == 0
		for z in range(t.z - 1, t.z + 2):
			for x in range(t.x - 1, t.x + 2):
				if x == t.x and z == t.z:
					continue
				world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.CRYSTAL if ring else Blocks.HULL)
	world.fill_box(Vector3i(t.x, t.y + 17, t.z), Vector3i(t.x, t.y + 17, t.z), Blocks.RECEIVER)

# ================================================================ 装点

func _dress() -> void:
	# 停机坪边的货箱和设备
	deco("space-station/container-tall", 9, 72, 1.6)
	deco("space-station/container", 16, 84, 1.2)
	deco("space-station/computer-screen", 8, 83, 0.9)
	# 厂区：机械臂、齿轮、发电设备
	deco("factory/robot-arm-a", 74, 46, 1.8)
	deco("factory/machine", 62, 58, 1.4)
	deco("factory/cog-a", 94, 72, 0.9, "none")
	deco("factory/cog-b", 61, 80, 0.8, "none")
	deco("factory/scanner-high", 86, 80, 1.6)
	deco("factory/screen-wide", 76, 80, 1.2)
	# 岛边缘的树
	for c in [Vector2i(8, 64), Vector2i(20, 88), Vector2i(36, 68), Vector2i(40, 84), Vector2i(10, 90), Vector2i(66, 86), Vector2i(98, 72), Vector2i(72, 44), Vector2i(114, 56)]:
		var cell := find_flat(c.x + rng.randi_range(-2, 2), c.y + rng.randi_range(-2, 2), 3, 1)
		if cell.y >= 0 and world.get_block(cell) == Blocks.AIR:
			tree(cell, rng.randi_range(4, 6), rng.randf_range(1.6, 2.4))
	var amb := Ambient.new()
	amb.area_lo = Vector3(4, G + 1, 60) * VoxelWorld.CELL_M
	amb.area_hi = Vector3(46, G + 8, 92) * VoxelWorld.CELL_M
	amb.count = 12
	add_child(amb)

# ================================================================ 机关、收集品、对话

func _v(c: Vector3i) -> Vector3:
	return world.voxel_top(c + Vector3i.DOWN)

func _objective(i: int, text: String, cell: Vector3i, a: Vector3i, b: Vector3i) -> void:
	zone(ObjectiveZone, a, b, {"index": i, "text": text, "marker": _v(cell)})

func _fragment(id: String, cell: Vector3i, text: String) -> void:
	var f := zone(MemoryFragment, cell, cell + Vector3i(0, 1, 0), {"log_text": text})
	f.set("frag_id", id)
	fragments[id] = f

func _enemy_at(cell: Vector3i) -> void:
	var e := Scrapling.new()
	add_child(e)
	e.global_position = world.voxel_top(cell + Vector3i.DOWN) + Vector3.UP * 0.05
	e.rotation.y = rng.randf() * TAU
	enemies.append(e)

func _seed_at(id: String, cell: Vector3i, line: int) -> void:
	var sc := SeedCube.new()
	sc.seed_id = id
	sc.line_index = line
	add_child(sc)
	sc.global_position = world.voxel_top(cell + Vector3i.DOWN)
	seeds[id] = sc

func _dispenser(cell: Vector3i) -> ItemDispenser:
	var d := ItemDispenser.new()
	add_child(d)
	d.global_position = world.voxel_center(cell) + Vector3.UP * 0.9
	return d

func _logic() -> void:
	var marker := ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	# 电网：整个厂区一张网
	grid = PowerGrid.new()
	add_child(grid)
	grid.setup(world, Vector3i(58, G - 3, 38), Vector3i(102, WALK_Y + 4, 88))
	grid.add_device(door)
	var fence := zone(ElectricField, Vector3i(86, G, 52), Vector3i(88, G + 2, 52)) as ElectricField
	fence.power_cells = [FENCE_RCV] as Array[Vector3i]
	grid.add_device(fence)
	var fan := zone(Fan, Vector3i(85, G, 63), Vector3i(87, WALK_Y + 3, 65), {"strength": 4.2, "max_rise_speed": 3.6}) as Fan
	fan.power_cells = [FAN_RCV] as Array[Vector3i]
	fan.is_powered = false
	grid.add_device(fan)
	# 火种补给点
	_dispenser(Vector3i(24, G, 72))
	_dispenser(Vector3i(42, G, 70))
	_dispenser(Vector3i(64, G, 72))
	_dispenser(Vector3i(90, WALK_Y + 2, 62))
	# 喷火口
	zone(FlameJet, Vector3i(84, G, 70), Vector3i(87, G + 3, 70), {"on_time": 1.3, "off_time": 1.5, "phase": 0.0})
	zone(FlameJet, Vector3i(84, G, 66), Vector3i(87, G + 3, 66), {"on_time": 1.3, "off_time": 1.5, "phase": 1.4})
	# 敌人
	_enemy_at(Vector3i(74, G, 56))
	_enemy_at(Vector3i(94, G, 68))
	_enemy_at(Vector3i(74, G, 79))
	# 种子方块
	_seed_at("gw_s1", Vector3i(9, G, 80), 0)
	_seed_at("gw_s2", Vector3i(63, G, 81), 1)
	_seed_at("gw_s3", Vector3i(93, WALK_Y + 3, 67), 2)
	# 记忆碎片
	_fragment("gw_1", Vector3i(16, G, 72), "艾拉·林，研究日志 #40：齿轮工坊的老师傅们不信“体素态”。我把一台车床拆成方块又拼回去，他们围着它转了一下午。")
	_fragment("gw_2", Vector3i(95, G, 44), "艾拉·林，研究日志 #188：引擎的五个节点要分散建造，一座塔坏了，其他四座还能撑住。我讨厌只有一个备份。")
	_fragment("gw_3", Vector3i(114, G + 10, 64), "艾拉·林，研究日志 #402：模拟又跑了一遍。风暴会在十年后再来一次。重构以后，我们还能再逃一次吗？")
	# 检查点
	zone(Checkpoint, SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	zone(Checkpoint, Vector3i(34, G, 74), Vector3i(38, G + 3, 78))
	zone(Checkpoint, Vector3i(61, G, 74), Vector3i(65, G + 3, 78))
	zone(Checkpoint, Vector3i(74, G, 64), Vector3i(77, G + 3, 67))
	zone(Checkpoint, Vector3i(86, WALK_Y + 1, 59), Vector3i(88, WALK_Y + 3, 62))
	zone(Checkpoint, Vector3i(103, G + 10, 59), Vector3i(106, G + 13, 63))
	# 对话
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"齿轮工坊。以前全星球的零件都在这里生产——现在连一盏灯都点不亮。",
		"第二座重构塔在工坊最东边。先往东走。",
	])
	talk(Vector3i(21, G, 70), Vector3i(29, G + 4, 84), [
		"枯荆棘把路堵死了。撞不开，钻头也会被缠住……但它很干，一点就着。",
		"旁边那个炭火盆里有火种。用{grab}抓起来，走近一点，再按{grab}扔到荆棘上。火会自己蔓延开。",
	])
	talk(Vector3i(33, G, 68), Vector3i(46, G + 4, 84), [
		"断崖对面就是厂区。那块石板本来是桥面——只靠西头那排木脚手架撑着，悬在半空。",
		"脚手架的木板一直铺到崖边。如果脚手架没了，石板会怎么样？看看两边崖壁上的铁轨。",
	])
	talk(Vector3i(60, G, 70), Vector3i(66, G + 4, 80), [
		"石板正好落在铁轨上。不错，PIX——你开始像个工程师了。",
	])
	talk(Vector3i(62, G, 55), Vector3i(70, G + 4, 64), [
		"发电机还在转！它接出去两条线：一条金属管线通往厂房大门，一条铜线埋在地上，往东边去了。",
		"管线中间缺了一截。能导电的东西……能量晶块就可以。储料场里应该有。",
	])
	talk(Vector3i(78, G, 52), Vector3i(86, G + 4, 57), [
		"储料场门口通着电网，碰到会受伤。给它供电的是地上那条铜线——铜线钻得断。",
	])
	talk(Vector3i(84, G, 71), Vector3i(87, G + 4, 76), [
		"喷火口是有节奏的，看准它停下来的时候冲过去。气泡的气浪也能把它吹熄一会儿。",
	])
	talk(Vector3i(86, WALK_Y + 1, 59), Vector3i(92, WALK_Y + 4, 63), [
		"空中走廊通往重构塔……前面有一堵加固墙，普通冲撞撞不开。墙边那几个红色的桶——是燃料桶。",
		"把火种扔过去，然后离远一点。",
	])
	# 目标
	GameState.set_objective(0, "往东走，找到通往厂区的路", _v(Vector3i(27, G, 77)))
	_objective(1, "用炭火盆里的火种烧开枯荆棘", Vector3i(24, G + 1, 72), Vector3i(20, G, 70), Vector3i(24, G + 4, 84))
	_objective(2, "想办法让石板落下来，搭成桥", Vector3i(CHASM.x, G, 76), Vector3i(33, G, 66), Vector3i(40, G + 4, 86))
	_objective(3, "给厂房大门供电（看看发电机）", SOURCE + Vector3i(0, 1, 0), Vector3i(60, G, 68), Vector3i(66, G + 4, 82))
	_objective(4, "去储料场找一块能量晶块", Vector3i(92, G, 46), Vector3i(62, G, 54), Vector3i(70, G + 4, 64))
	_objective(6, "拿到厂房中央的能量核心", CORE + Vector3i(0, 1, 0), Vector3i(71, G, 59), Vector3i(82, G + 4, 75))
	_objective(8, "炸开走廊尽头的加固墙", Vector3i(BLAST_X - 1, WALK_Y + 1, 60), Vector3i(86, WALK_Y + 1, 58), Vector3i(92, WALK_Y + 4, 63))
	_objective(9, "点亮第二座重构塔", TOWER + Vector3i(0, 1, -3), Vector3i(98, WALK_Y + 1, 58), Vector3i(103, WALK_Y + 4, 63))
	# 能量核心：气泡形态
	form_core = zone(FormCore, CORE + Vector3i(-1, 0, -1), CORE + Vector3i(1, 2, 1), {
		"form": MorphBall.BUBBLE,
		"unlock_text": "气泡形态解锁！很轻、跳得最高：空中还能再跳两次，按住{jump}滑翔。按{ability}放出气浪——能把火吹灭、把锈块兽掀翻。",
	})
	GameState.form_unlocked.connect(func(i: int) -> void:
		if i == MorphBall.BUBBLE:
			GameState.set_objective(7, "穿过东边的喷火走廊，乘上升气流到空中走廊", _v(Vector3i(86, G, 64))))
	# 插槽：补上大门的供电管线
	socket = ItemSocket.new()
	add_child(socket)
	socket.fill_block = Blocks.CRYSTAL
	socket.setup(world, GAP)
	socket.filled.connect(func() -> void:
		SaveGame.set_flag("gw_door")
		GameState.say("管线接上了！厂房大门……开了。")
		GameState.set_objective(5, "进入厂房", _v(Vector3i(71, G, 67))))
	world.fire.exploded.connect(_on_exploded)
	world.block_changed.connect(_watch_slab)
	# 终点
	var goal := zone(Goal, TOWER + Vector3i(-5, 0, -5), TOWER + Vector3i(5, 4, 5)) as Goal
	goal.line = "第二个节点接通了。……工坊的灯，一盏一盏亮起来了。PIX，谢谢你。还有三座。"
	_toys()
	zone(MusicZone, Vector3i(26, G - 2, 60), Vector3i(60, G + 6, 92), {"state": "puzzle"})
	zone(MusicZone, Vector3i(60, G - 2, 38), Vector3i(98, G + 6, 60), {"state": "puzzle"})
	coin_line(Vector3i(19, G, 77), Vector3i(27, G, 77), 4)
	coin_line(Vector3i(34, G, 77), Vector3i(44, G, 77), 5)
	coin_line(Vector3i(61, G, 76), Vector3i(61, G, 66), 4)
	coin_line(Vector3i(88, WALK_Y + 1, 61), Vector3i(94, WALK_Y + 1, 61), 4)

func _toys() -> void:
	# 停机坪的弹簧 → 空中的金币环
	var sp := Vector3i(14, G, 82)
	zone(BouncePad, sp + Vector3i(-1, 0, -1), sp + Vector3i(1, 1, 1), {"launch": Vector3(0, 12.6, 0.0)})
	for k in 8:
		var a := k * TAU / 8.0
		coin(Vector3i(sp.x + roundi(cos(a) * 2.0), G + 10, sp.z + roundi(sin(a) * 2.0)))
	# 厂区里的传送带（加速板）
	zone(SpeedPad, Vector3i(66, G, 68), Vector3i(67, G, 74), {"dir": Vector3(0, 0, -1), "speed": 10.0})

## 石板所在的脚手架烧光后，石板会塌下来；落到铁轨上以后记下来
var _slab_check := false

func _watch_slab(_p: Vector3i, _o: int, _n: int) -> void:
	if slab_fallen or _slab_check:
		return
	_slab_check = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		_slab_check = false
		if world.get_block(Vector3i(53, G + 2, 76)) == Blocks.AIR and not slab_fallen:
			slab_fallen = true
			_await_slab(0))

## 等石板落稳：落在铁轨上就补缝；没落好（卡在半空、歪了、掉进云海）就整理成标准的桥，保证不卡关
func _await_slab(tries: int) -> void:
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		var falling := false
		for c in world.get_children():
			if c is VoxelChunk:
				falling = true
		if falling and tries < 8:
			_await_slab(tries + 1)
			return
		var on_rails := 0
		for z in range(SLAB_Z.x, SLAB_Z.y + 1):
			for x in range(CHASM.x + 1, CHASM.y + 1):
				if world.get_block(Vector3i(x, G - 1, z)) == Blocks.ROCK:
					on_rails += 1
		var total := (CHASM.y - CHASM.x) * (SLAB_Z.y - SLAB_Z.x + 1)
		print("[齿轮工坊] 石板落在铁轨上的格数 %d / %d" % [on_rails, total])
		if on_rails < total * 0.9:
			# 清掉歪在上面的石头，重新摆正
			for z in range(SLAB_Z.x - 3, SLAB_Z.y + 4):
				for y in range(G - 3, G + 5):
					for x in range(CHASM.x - 3, CHASM.y + 4):
						if y == G - 1 and x > CHASM.x and x <= CHASM.y and z >= SLAB_Z.x and z <= SLAB_Z.y:
							continue
						if world.get_block(Vector3i(x, y, z)) == Blocks.ROCK:
							world.try_break_any(Vector3i(x, y, z))
			world.fill_box(Vector3i(CHASM.x + 1, G - 1, SLAB_Z.x), Vector3i(CHASM.y, G - 1, SLAB_Z.y), Blocks.ROCK)
		_patch_gap()
		SaveGame.set_flag("gw_slab")
		GameState.say("石板正好落在铁轨上。不错，PIX——你开始像个工程师了。")
		GameState.set_objective(3, "给厂房大门供电（看看发电机）", _v(SOURCE + Vector3i(0, 1, 0))))

func _on_exploded(pos: Vector3) -> void:
	if wall_blown:
		return
	if pos.distance_to(world.voxel_center(Vector3i(BLAST_X, WALK_Y + 2, 60))) < 4.0:
		# 爆炸只炸开了一部分的话，把墙剩下的清掉（保证通路）
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			for z in range(59, 63):
				for y in range(WALK_Y + 1, WALK_Y + 4):
					if world.get_block(Vector3i(BLAST_X, y, z)) == Blocks.REINFORCED:
						world.try_break_any(Vector3i(BLAST_X, y, z)))
		wall_blown = true
		SaveGame.set_flag("gw_blast")
		GameState.say("轰——路通了！……下次离远一点，我的传感器都在嗡嗡响。")

func _on_item_dropped(item_id: String, pos: Vector3) -> void:
	if item_id == "crystal" and not is_instance_valid(crystal) and not socket.done:
		crystal = UsableItem.new()
		crystal.item_id = "crystal"
		add_child(crystal)
		crystal.global_position = pos + Vector3.UP * 0.3
		crystal.home = crystal.global_position
		crystal.linear_velocity = Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1))
		GameState.say("能量晶块！把它带回发电机那边，扔进管线的缺口。")
		GameState.set_objective(5, "把晶块扔进大门管线的缺口", _v(GAP + Vector3i.UP))

## 继续游戏 / 从上一章进入：恢复进度
func apply_save(d: Dictionary) -> void:
	var forms: Array = d.get("forms", [])
	if forms.size() == GameState.unlocked_forms.size():
		for i in forms.size():
			GameState.unlocked_forms[i] = bool(forms[i])
	GameState.unlocked_forms[MorphBall.DRILL] = true
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
	if GameState.unlocked_forms[MorphBall.BUBBLE] and is_instance_valid(form_core):
		form_core.queue_free()
		Music.set_default("bright")
	var flags: Dictionary = d.get("flags", {})
	if bool(flags.get("gw_door", false)) and not socket.done:
		socket.done = true
		world.set_block(GAP, Blocks.CRYSTAL)
	# 荆棘烧过就不再长回来
	if bool(flags.get("gw_barricade", false)):
		for z in range(60, 92):
			for y in range(G, G + 4):
				for x in [BARRICADE_X, BARRICADE_X + 1]:
					if world.get_block(Vector3i(x, y, z)) == Blocks.BRAMBLE:
						world.set_block(Vector3i(x, y, z), Blocks.AIR)
	var obj := int(d.get("objective", -1))
	if obj >= 0:
		GameState.objective_index = -1
		GameState.set_objective(obj, str(d.get("objective_text", "")), AreaGreenhouse._vec(d.get("objective_pos", null)))

func _process(_delta: float) -> void:
	# 荆棘烧开以后记一下（读档不用再烧一遍）
	if not SaveGame.data.is_empty() and not SaveGame.flag("gw_barricade") and Engine.get_process_frames() % 30 == 0:
		if world.get_block(Vector3i(BARRICADE_X, G, 77)) != Blocks.BRAMBLE and world.get_block(Vector3i(BARRICADE_X, G + 1, 77)) != Blocks.BRAMBLE and world.get_block(Vector3i(BARRICADE_X, G, 77)) != Blocks.FIRE:
			SaveGame.set_flag("gw_barricade")
			GameState.say("烧开了！火会顺着能烧的东西蔓延——木头、树叶、荆棘……记住这一点。")

## 从第一章过来时的抵达镜头
func arrival_shots() -> Array:
	var V := VoxelWorld.CELL_M
	return [
		{"from": Vector3(-20, 60, 40) * V, "to": Vector3(10, 50, 50) * V, "look_from": Vector3(60, 22, 70) * V, "look_to": Vector3(80, 22, 64) * V, "dur": 6.0, "fade": Color.BLACK,
			"lines": [["NOVA", "第一座塔接通以后，光桥把你送到了这里——齿轮工坊。"], ["NOVA", "以前全星球的零件都在这里生产。现在……安静得有点吓人。"]]},
		{"from": Vector3(80, 50, 110) * V, "to": Vector3(100, 44, 96) * V, "look": Vector3(TOWER) * V, "dur": 5.0,
			"lines": [["NOVA", "第二座重构塔在工坊的最东边。"]]},
		{"from": Vector3(4, 30, 92) * V, "to": Vector3(8, 27, 88) * V, "look": Vector3(SPAWN) * V, "dur": 4.0,
			"lines": [["NOVA", "从停机坪出发吧。"]]},
	]
