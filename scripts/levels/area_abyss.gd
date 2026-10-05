class_name AreaAbyss
extends ChapterLevel
## 第三章 · 晶簇深渊：星球的矿层。一座浮岛中间裂开一口 20 米深的天坑，坑壁上长满发光的水晶。
## 第三座重构塔沉在坑底——锈蚀唤醒了守着矿坑的采矿巨像。
##
## 路线（格坐标，1 格 = 0.5 米）：
##   A 西边坑沿的晶矿站（出生）→ 撞碎共鸣晶簇，进入沿坑壁盘旋而下的螺旋栈道（有碎裂石板）
##   B 第一层环台（L1）：光束谜题——撞转两面晶面镜，把发射晶的光引到东边的受光晶上，
##     电顺着金属管线流到下面第二层环台，打开东侧晶洞的门
##   C 升降台下到第二层环台（L2），进晶洞：钻地鼹、共鸣晶簇墙、碎裂石板桥、松土竖井
##   D 竖井下到最底层的隧道 → 坑底：Boss「晶簇巨像」（用镜子把光照到它身上）
##   E 打倒巨像，坑底中央的第三座重构塔升起来，光柱冲出天坑

const SIZE := Vector3i(128, 96, 128)
const C := Vector2i(64, 64)            ## 天坑中心
const TOP := 72                        ## 坑沿地面（第一层空气）
const L1 := 52                         ## 第一层环台
const L2 := 34                         ## 第二层环台
const FLOOR := 16                      ## 坑底
const PIT_R := 21.5                    ## 坑壁半径
const SPAWN := Vector3i(14, TOP, 64)
const SPIRAL_A0 := 210.0               ## 螺旋栈道起点角度（度），逆时针往下
const SPIRAL_A1 := 60.0
const LENS := Vector3i(81, L1, 67)     ## 受光晶（3 格高）
const CAVE_DOOR_X := 87
const TUNNEL_Z := Vector2i(63, 66)     ## 底层隧道
const LIFT_CELL := Vector3i(80, 0, 69) ## 升降台（x, z 起点，4×4 格）

var _n := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var crumbles: CrumbleSystem
var p1_beam: LightBeam
var boss: CrystalColossus
var boss_beams: Array[LightBeam] = []
var boss_done := false
var cave_door: PowerDoor
var grid: PowerGrid
var tower_cells: Array = []
var tower_built := false

func _init() -> void:
	chapter_id = "abyss"
	forms_at_start = [true, true, true] as Array[bool]
	kill_height = 1.0

func spawn_cell() -> Vector3i:
	return SPAWN

func spawn_yaw() -> float:
	return -PI / 2.0

func pit_r(y: int, x := 0, z := 0) -> float:
	return PIT_R + _n.get_noise_3d(x * 0.8, y * 1.6, z * 0.8) * 1.0

# ================================================================ 搭建

func _build_world() -> void:
	world.setup(SIZE)
	rng.seed = 3303
	_n.seed = 33
	_n.frequency = 0.07
	_n2.seed = 34
	_n2.frequency = 0.05
	if not backdrop:
		Atmosphere.apply(self, "abyss")
	_terrain()
	_ledges()
	_spiral()
	_rim()
	_p1_setup()
	_cave()
	_arena()
	_wall_dressing()
	world.naturalize(TOP + 8, [
		AABB(Vector3(40, 0, 40), Vector3(48, 96, 48)),      # 整个天坑（栈道、环台、Boss 场地）
		AABB(Vector3(82, 0, 40), Vector3(36, 96, 50)),      # 晶洞
	])
	world.rebuild_all()
	scatter_decor(Vector3i(0, TOP - 4, 0), Vector3i(SIZE.x - 1, TOP + 6, SIZE.z - 1), 0.3, 0.06, 0.025)
	decor.commit()
	_dress()
	world.flush_dirty()
	vista = Vistas.abyss(self, world, _falls())
	crumbles = CrumbleSystem.new()
	crumbles.world = world
	add_child(crumbles)

func _terrain() -> void:
	var R_ISL := 56.0
	var bulge_c := Vector3(100, 30, 64)
	var bulge_r := Vector3(27, 30, 29)
	for z in SIZE.z:
		for x in SIZE.x:
			var dv := Vector2(x - C.x, z - C.y)
			var d := dv.length()
			var ang := atan2(dv.y, dv.x)
			var rr := R_ISL * (0.9 + 0.12 * _n2.get_noise_2d(cos(ang) * 40.0, sin(ang) * 40.0))
			if x > 84 and z > 40 and z < 88:
				rr = maxf(rr, 55.0)
			if d > rr:
				continue
			var top := TOP
			if d > 32.0:
				top += int(round((0.5 + 0.5 * _n2.get_noise_2d(x * 0.6, z * 0.6)) * 1.4 * clampf((d - 32.0) / 6.0, 0.0, 1.0)))
			# 倒锥形的岛底；东边多一块圆鼓鼓的岩体（晶洞在里面）
			var t := clampf((d - 23.0) / maxf(rr - 23.0, 1.0), 0.0, 1.0)
			var bottom := 8 + int((TOP - 10 - 8) * pow(t, 0.65)) + int(_n.get_noise_2d(x * 2.0, z * 2.0) * 2.0)
			var q := Vector2((x - bulge_c.x) / bulge_r.x, (z - bulge_c.z) / bulge_r.z)
			if q.length() < 1.0:
				bottom = mini(bottom, int(bulge_c.y - bulge_r.y * sqrt(1.0 - q.length_squared()) * 0.85))
			bottom = maxi(bottom, 2)
			_set_h(x, z, top)
			if d < 24.0:
				world.fill_column(x, z, bottom, top - 4, Blocks.DARKROCK)
			else:
				# 外壳的岩层：和第一章一样的悬崖岩色带（按段填，快）
				var off := _n.get_noise_2d(x * 1.3, z * 1.3) * 3.0
				var y := bottom
				while y <= top - 4:
					var band := posmod(int(floor((y + off) / 4.0)), 3)
					var y_end := mini(top - 4, int(floor((floor((y + off) / 4.0) + 1.0) * 4.0 - off - 0.001)))
					world.fill_column(x, z, y, maxi(y_end, y), [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C][band])
					y = maxi(y_end, y) + 1
			world.fill_column(x, z, top - 3, top - 2, Blocks.DIRT)
			world.fill_column(x, z, top - 1, top - 1, Blocks.GRASS)
	# 天坑：坑壁以内全部挖空到坑底
	for z in range(C.y - 26, C.y + 27):
		for x in range(C.x - 26, C.x + 27):
			var d := Vector2(x - C.x, z - C.y).length()
			if d > 25.0:
				continue
			for y in range(FLOOR, TOP + 6):
				if d < pit_r(y, x, z):
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.AIR)
			if d < PIT_R + 1.5:
				_set_h(x, z, FLOOR)
	# 坑壁的岩层：深浅两种深渊岩一层一层
	for z in range(C.y - 27, C.y + 28):
		for x in range(C.x - 27, C.x + 28):
			for y in range(FLOOR - 1, TOP - 3):
				var t := world.get_block(Vector3i(x, y, z))
				if t == Blocks.DARKROCK:
					var band := int(floor((y + _n.get_noise_2d(x * 1.5, z * 1.5) * 2.5) / 4.0)) % 3
					if band == 1:
						world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.DARKROCK_B)
					elif band == 2:
						world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.CLIFF_C)
	# 坑底：深色的碎石地面
	for z in range(C.y - 24, C.y + 25):
		for x in range(C.x - 24, C.x + 25):
			if Vector2(x - C.x, z - C.y).length() < PIT_R + 1.0:
				world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.PAVING if (x + z) % 7 else Blocks.DARKROCK_B)

## 两层环台：沿坑壁一圈的石台（内侧一圈玻璃矮栏，光能穿过，摔不下去——除非你把玻璃撞碎）
func _ledges() -> void:
	for spec in [[L1, 15.0, 6], [L2, 12.0, 6]]:
		var y: int = spec[0]
		var r_in: float = spec[1]
		var th: int = spec[2]
		for z in range(C.y - 24, C.y + 25):
			for x in range(C.x - 24, C.x + 25):
				var d := Vector2(x - C.x, z - C.y).length()
				if d < r_in or d > pit_r(y, x, z) + 0.5:
					continue
				# 越靠坑壁越厚，下沿参差
				var thick := int(th * clampf((d - r_in) / 3.0 + 0.4, 0.4, 1.0)) + int(_n.get_noise_2d(x * 3.0, z * 3.0 + y) * 1.5)
				world.fill_box(Vector3i(x, y - maxi(thick, 2), z), Vector3i(x, y - 2, z), Blocks.DARKROCK_B)
				world.fill_box(Vector3i(x, y - 1, z), Vector3i(x, y - 1, z), Blocks.PAVING if (x * 3 + z) % 11 else Blocks.MOSS)
				if d < r_in + 1.0:
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y + 1, z), Blocks.GLASS)

## 螺旋栈道：从坑沿（西北）逆时针往下，一级一级台阶，到第一层环台（东南）
func _spiral() -> void:
	var steps := TOP - L1
	for z in range(C.y - 24, C.y + 25):
		for x in range(C.x - 24, C.x + 25):
			var dv := Vector2(x - C.x, z - C.y)
			var d := dv.length()
			if d < 16.5 or d > pit_r(TOP, x, z) + 0.5:
				continue
			var a := rad_to_deg(atan2(dv.y, dv.x))
			if a < 0.0:
				a += 360.0
			# 从 210° 逆时针（角度减小）到 60°
			if a > SPIRAL_A0 or a < SPIRAL_A1:
				continue
			var k := (SPIRAL_A0 - a) / (SPIRAL_A0 - SPIRAL_A1)
			var h := TOP - int(round(k * steps))
			world.fill_box(Vector3i(x, h - 4, z), Vector3i(x, h - 2, z), Blocks.DARKROCK)
			world.fill_box(Vector3i(x, h - 1, z), Vector3i(x, h - 1, z), Blocks.PLANK if d > 18.5 else Blocks.DARKROCK_B)
			world.fill_box(Vector3i(x, h, z), Vector3i(x, h + 5, z), Blocks.AIR)
	# 栈道上两段碎裂石板（走快一点！）
	for seg in [[170.0, 178.0], [118.0, 128.0]]:
		for z in range(C.y - 24, C.y + 25):
			for x in range(C.x - 24, C.x + 25):
				var dv := Vector2(x - C.x, z - C.y)
				var d := dv.length()
				if d < 16.5 or d > pit_r(TOP, x, z) + 0.5:
					continue
				var a := rad_to_deg(atan2(dv.y, dv.x))
				if a < 0.0:
					a += 360.0
				if a >= seg[0] and a <= seg[1]:
					var k := (SPIRAL_A0 - a) / (SPIRAL_A0 - SPIRAL_A1)
					var h := TOP - int(round(k * steps))
					world.fill_box(Vector3i(x, h - 4, z), Vector3i(x, h - 2, z), Blocks.AIR)
					world.fill_box(Vector3i(x, h - 1, z), Vector3i(x, h - 1, z), Blocks.CRUMBLE)

func _spiral_cell(a_deg: float, d := 19.0) -> Vector3i:
	var a := deg_to_rad(a_deg)
	var x := int(round(C.x + cos(a) * d))
	var z := int(round(C.y + sin(a) * d))
	var k := (SPIRAL_A0 - a_deg) / (SPIRAL_A0 - SPIRAL_A1)
	return Vector3i(x, TOP - int(round(k * (TOP - L1))), z)

# ================================================================ 坑沿：晶矿站

func _rim() -> void:
	# 坑沿一圈矮石栏，栈道入口被一团共鸣晶簇堵着
	for z in range(C.y - 26, C.y + 27):
		for x in range(C.x - 26, C.x + 27):
			var dv := Vector2(x - C.x, z - C.y)
			var d := dv.length()
			if d < 22.3 or d > 23.4 or h_at(x, z) != TOP:
				continue
			var a := rad_to_deg(atan2(dv.y, dv.x))
			if a < 0.0:
				a += 360.0
			if a > 200.0 and a < 224.0:
				world.fill_box(Vector3i(x, TOP, z), Vector3i(x, TOP + 2, z), Blocks.GEM_CHAIN)
			else:
				world.fill_box(Vector3i(x, TOP, z), Vector3i(x, TOP + 1, z), Blocks.MOSS)
	# 入口里面也堆一点晶簇（从坑沿走上栈道的地方）
	var e := _spiral_cell(214.0, 20.5)
	world.fill_box(Vector3i(e.x - 1, TOP, e.z - 1), Vector3i(e.x + 1, TOP + 2, e.z + 1), Blocks.GEM_CHAIN)
	# 晶矿站：水泥地坪、矿车轨道、断掉的升降井架
	for z in range(54, 76):
		for x in range(8, 36):
			if h_at(x, z) == TOP and (x + z) % 9 != 0:
				world.fill_box(Vector3i(x, TOP - 1, z), Vector3i(x, TOP - 1, z), Blocks.PAVING)
	for x in range(10, 41):
		world.fill_box(Vector3i(x, TOP - 1, 66), Vector3i(x, TOP - 1, 66), Blocks.TRACK)
	# 井架：坑沿西边一座高高的钢架，吊笼的缆绳断了
	var hf := Vector3i(40, TOP, 64)
	for c in [Vector3i(-2, 0, -2), Vector3i(2, 0, -2), Vector3i(-2, 0, 2), Vector3i(2, 0, 2)]:
		world.fill_box(hf + c, hf + c + Vector3i(0, 14, 0), Blocks.HULL_DARK)
	for y in [5, 10, 15]:
		for dz in range(-2, 3):
			if dz == -2 or dz == 2 or y == 15:
				world.fill_box(hf + Vector3i(-2, y, dz), hf + Vector3i(2, y, dz), Blocks.RUST if y < 15 else Blocks.HULL_DARK)
	world.fill_box(hf + Vector3i(-1, 16, 0), hf + Vector3i(1, 17, 0), Blocks.METAL)
	# 伸向天坑的吊臂
	for k in 7:
		world.fill_box(hf + Vector3i(3 + k, 15, 0), hf + Vector3i(3 + k, 15, 0), Blocks.RUST)
	world.fill_box(hf + Vector3i(9, 5, 0), hf + Vector3i(9, 14, 0), Blocks.TRACK)
	# 坑沿上的晶石（地面上冒出来的一簇簇水晶）
	for k in 14:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(28.0, 48.0)
		var x := int(C.x + cos(a) * dist)
		var z := int(C.y + sin(a) * dist)
		if h_at(x, z) < TOP or (x < 38 and z > 50 and z < 80):
			continue
		var hh := rng.randi_range(2, 5)
		var h := h_at(x, z)
		world.fill_box(Vector3i(x, h, z), Vector3i(x, h + hh - 1, z), Blocks.CRYSTAL)
		world.fill_box(Vector3i(x + 1, h, z), Vector3i(x + 1, h + hh / 2, z), Blocks.CRYSTAL)
		world.fill_box(Vector3i(x, h, z + 1), Vector3i(x, h + 1, z + 1), Blocks.GEODE)
	# 北边的小晶洞（藏宝）：一小团共鸣晶簇包着宝箱
	var tc := Vector3i(40, TOP, 26)
	if h_at(tc.x, tc.z) >= TOP:
		for z in range(tc.z - 2, tc.z + 3):
			for x in range(tc.x - 2, tc.x + 3):
				for y in range(TOP, TOP + 4):
					if Vector3(x - tc.x, (y - TOP - 1) * 1.2, z - tc.z).length() < 2.6:
						world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.GEM_CHAIN)
		world.fill_box(tc, tc + Vector3i(0, 1, 0), Blocks.AIR)

# ================================================================ 第一层：光束谜题

## 发射晶在西边环台朝北射光 → 镜 M1（西北）→ 横穿天坑 → 镜 M2（东北）→ 向南照到受光晶
## 受光晶旁边的金属管线一直通到下面第二层，接到晶洞门上
func _p1_setup() -> void:
	# 受光晶：三格高的晶柱
	world.fill_box(LENS, LENS + Vector3i(0, 2, 0), Blocks.LENS)
	world.fill_box(LENS + Vector3i(0, 3, 0), LENS + Vector3i(0, 3, 0), Blocks.HULL_DARK)
	# 管线：从受光晶旁边竖直往下，穿过第一层环台，到第二层地面，再沿地面到晶洞门的接收器
	var px := LENS.x + 1
	world.fill_box(Vector3i(px, L2 - 1, LENS.z), Vector3i(px, L1 + 2, LENS.z), Blocks.METAL)
	world.fill_box(Vector3i(px, L2 - 1, 62), Vector3i(px, L2 - 1, LENS.z), Blocks.METAL)
	world.fill_box(Vector3i(px + 1, L2 - 1, 62), Vector3i(px + 1, L2 - 1, 62), Blocks.RECEIVER)
	# 升降台井道：在第一层环台上开一个洞
	var lc := LIFT_CELL
	world.fill_box(Vector3i(lc.x, L1 - 8, lc.z), Vector3i(lc.x + 3, L1 - 1, lc.z + 3), Blocks.AIR)
	for y in range(L2, L1):
		if y % 3 == 0:
			world.fill_box(Vector3i(lc.x + 4, y, lc.z), Vector3i(lc.x + 4, y, lc.z + 3), Blocks.HULL_DARK)

# ================================================================ 第二层：晶洞

func _cave() -> void:
	var y0 := L2
	# 晶洞入口走廊（门在 x=CAVE_DOOR_X）
	world.fill_box(Vector3i(84, y0, 60), Vector3i(90, y0 + 3, 64), Blocks.AIR)
	# 大厅：起伏的洞顶、泥土地面
	for z in range(47, 82):
		for x in range(88, 114):
			var ceil_h := 9 + int(_n.get_noise_2d(x * 2.0, z * 2.0) * 3.0)
			var rr := Vector2((x - 100) / 13.0, (z - 64) / 16.0).length()
			if rr > 1.0 + _n.get_noise_2d(x * 3.0, z * 3.0) * 0.1:
				continue
			world.fill_box(Vector3i(x, y0, z), Vector3i(x, y0 + ceil_h, z), Blocks.AIR)
			world.fill_box(Vector3i(x, y0 - 1, z), Vector3i(x, y0 - 1, z), Blocks.DIRT if x < 97 else Blocks.DARKROCK_B)
	# 洞顶垂下来的晶簇（发光）和石笋
	for k in 30:
		var x := rng.randi_range(89, 112)
		var z := rng.randi_range(49, 79)
		var y := y0 + 14
		while y > y0 and world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
			y -= 1
		if y <= y0 + 3:
			continue
		var len := rng.randi_range(1, 3)
		world.fill_box(Vector3i(x, y - len + 1, z), Vector3i(x, y, z), Blocks.CRYSTAL if k % 3 == 0 else Blocks.DARKROCK_B)
	# 共鸣晶簇墙：把大厅的东半边隔开
	for z in range(47, 82):
		for y in range(y0, y0 + 8):
			if world.get_block(Vector3i(97, y, z)) == Blocks.AIR:
				world.fill_box(Vector3i(97, y, z), Vector3i(98, y, z), Blocks.GEM_CHAIN)
	# 裂谷：东半边中间裂开一道深沟，一直通到最底层的隧道；上面一座碎裂石板桥
	for z in range(47, 82):
		for x in range(101, 106):
			if world.get_block(Vector3i(x, y0, z)) == Blocks.AIR:
				world.fill_box(Vector3i(x, FLOOR, z), Vector3i(x, y0 - 1, z), Blocks.AIR)
				world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.DARKROCK_B)
	for z in range(62, 66):
		for x in range(101, 106):
			world.fill_box(Vector3i(x, y0 - 1, z), Vector3i(x, y0 - 1, z), Blocks.CRUMBLE)
	# 对岸：松土地面（往下钻进竖井）
	for z in range(70, 74):
		for x in range(107, 111):
			world.fill_box(Vector3i(x, y0 - 1, z), Vector3i(x, y0 - 1, z), Blocks.LOOSE)
			world.fill_box(Vector3i(x, FLOOR, z), Vector3i(x, y0 - 2, z), Blocks.AIR)
			world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.DARKROCK_B)
	# 最底层的隧道：从竖井 / 裂谷底向西通到坑底（Boss 场地东门）
	for z in range(TUNNEL_Z.x, TUNNEL_Z.y + 1):
		for x in range(84, 111):
			world.fill_box(Vector3i(x, FLOOR, z), Vector3i(x, FLOOR + 4, z), Blocks.AIR)
			world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.DARKROCK_B)
	for z in range(TUNNEL_Z.y, 74):
		for x in range(107, 111):
			world.fill_box(Vector3i(x, FLOOR, z), Vector3i(x, FLOOR + 4, z), Blocks.AIR)
			world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.DARKROCK_B)
	# 洞壁换成深渊岩
	for z in range(44, 86):
		for x in range(82, 118):
			for y in range(FLOOR - 2, L2 + 16):
				var tt := world.get_block(Vector3i(x, y, z))
				if tt == Blocks.CLIFF or tt == Blocks.CLIFF_B or tt == Blocks.CLIFF_C:
					world.fill_box(Vector3i(x, y, z), Vector3i(x, y, z), Blocks.DARKROCK if (y / 3) % 2 else Blocks.DARKROCK_B)
	# 荧光菇和晶石（大厅的主要光源）
	for k in 26:
		var x := rng.randi_range(89, 112)
		var z := rng.randi_range(49, 79)
		if world.get_block(Vector3i(x, y0, z)) == Blocks.AIR and world.get_block(Vector3i(x, y0 - 1, z)) != Blocks.AIR and (x < 100 or x > 106):
			world.fill_box(Vector3i(x, y0, z), Vector3i(x, y0 + (k % 2), z), Blocks.GLOWSHROOM)
	for k in 10:
		var x := rng.randi_range(86, 108)
		var z := rng.randi_range(TUNNEL_Z.x, TUNNEL_Z.y)
		if world.get_block(Vector3i(x, FLOOR + 4, z)) == Blocks.AIR:
			world.fill_box(Vector3i(x, FLOOR + 4, z), Vector3i(x, FLOOR + 4, z), Blocks.CRYSTAL)

# ================================================================ 坑底：Boss 场地

func _arena() -> void:
	# 场地边缘一圈发光的晶柱
	for k in 16:
		var a := k * TAU / 16.0
		var x := int(round(C.x + cos(a) * 19.5))
		var z := int(round(C.y + sin(a) * 19.5))
		if z >= TUNNEL_Z.x - 1 and z <= TUNNEL_Z.y + 1 and x > C.x:
			continue
		world.fill_box(Vector3i(x, FLOOR, z), Vector3i(x, FLOOR + 2 + k % 3, z), Blocks.CRYSTAL)
	# 中央的塔基（塔会在巨像倒下后升起来）
	for z in range(C.y - 2, C.y + 3):
		for x in range(C.x - 2, C.x + 3):
			world.fill_box(Vector3i(x, FLOOR - 1, z), Vector3i(x, FLOOR - 1, z), Blocks.HULL_DARK if (x == C.x or z == C.y) else Blocks.HULL)

## 坑壁装饰：嵌在壁上的晶簇、垂下来的草根
func _wall_dressing() -> void:
	for k in 90:
		var a := rng.randf() * TAU
		var y := rng.randi_range(FLOOR + 2, TOP - 4)
		var r := pit_r(y) + 0.8
		var x := int(round(C.x + cos(a) * r))
		var z := int(round(C.y + sin(a) * r))
		var c := Vector3i(x, y, z)
		if world.get_block(c) == Blocks.AIR:
			continue
		# 往坑里长一簇
		var inward := Vector2(C.x - x, C.y - z).normalized()
		var t := Blocks.CRYSTAL if k % 3 != 0 else Blocks.GEODE
		for s in rng.randi_range(1, 3):
			var q := Vector3i(int(round(x + inward.x * s)), y + (s if k % 2 == 0 else 0), int(round(z + inward.y * s)))
			if world.get_block(q) == Blocks.AIR and Vector2(q.x - C.x, q.z - C.y).length() > 12.0:
				world.fill_box(q, q, t)
	# 坑沿垂下来的根须
	for k in 60:
		var a := rng.randf() * TAU
		var x := int(round(C.x + cos(a) * (PIT_R - 0.2)))
		var z := int(round(C.y + sin(a) * (PIT_R - 0.2)))
		var len := rng.randi_range(3, 12)
		for y in range(TOP - 1, TOP - 1 - len, -1):
			var q := Vector3i(x, y, z)
			if world.get_block(q) != Blocks.AIR:
				continue
			world.fill_box(q, q, Blocks.LEAVES if y % 3 else Blocks.PINE)

func _falls() -> Array:
	# 从坑沿流进天坑的瀑布 + 岛边的瀑布
	var out := []
	var a := deg_to_rad(300.0)
	var top := world.voxel_center(Vector3i(int(C.x + cos(a) * (PIT_R + 0.5)), TOP - 2, int(C.y + sin(a) * (PIT_R + 0.5))))
	out.append([top, Vector3(-cos(a), 0, -sin(a)), FLOOR * VoxelWorld.CELL_M])
	for spec in [[64, 64, Vector2i(0, -1)], [64, 64, Vector2i(-1, 1)]]:
		var d: Vector2i = spec[2]
		var last := Vector2i(-1, -1)
		for k in 30:
			var q := Vector2i(64, 64) + d * (30 + k)
			if h_at(q.x, q.y) >= TOP:
				last = q
			elif last.x >= 0:
				break
		if last.x >= 0:
			out.append([world.voxel_center(Vector3i(last.x, TOP - 2, last.y)) + Vector3(d.x, 0, d.y) * 0.3, Vector3(d.x, 0, d.y).normalized(), -30.0])
	return out

# ================================================================ 布景

func _dress() -> void:
	deco("space-station/container-tall", 20, 58, 1.6)
	deco("space-station/container-wide", 26, 72, 1.2)
	deco("factory/hopper-high-round", 32, 58, 1.8)
	deco("factory/conveyor-long", 30, 70, 0.6, "box")
	deco("space-station/computer-system", 16, 72, 1.0)
	deco("factory/crane", 34, 76, 2.4)
	for c in [Vector2i(14, 40), Vector2i(24, 90), Vector2i(60, 16), Vector2i(90, 20), Vector2i(104, 100), Vector2i(64, 110), Vector2i(10, 80), Vector2i(110, 40)]:
		for k in 3:
			var cell := find_flat(c.x + rng.randi_range(-4, 4), c.y + rng.randi_range(-4, 4), 3, 1)
			if cell.y >= 0 and world.get_block(cell) == Blocks.AIR:
				tree(cell, rng.randi_range(4, 7), rng.randf_range(1.6, 2.4), "pine" if rng.randf() < 0.6 else "round")
	# 洞里的光：荧光菇旁边放几盏柔和的灯
	for p in [Vector3i(93, L2 + 3, 56), Vector3i(93, L2 + 3, 72), Vector3i(109, L2 + 3, 64), Vector3i(100, FLOOR + 2, 64), Vector3i(87, L2 + 2, 62)]:
		var l := OmniLight3D.new()
		l.light_color = Color("9ff0ff")
		l.light_energy = 1.2
		l.omni_range = 9.0
		add_child(l)
		l.global_position = world.voxel_center(p)
	var amb := Ambient.new()
	amb.area_lo = Vector3(4, TOP + 1, 30) * VoxelWorld.CELL_M
	amb.area_hi = Vector3(40, TOP + 8, 100) * VoxelWorld.CELL_M
	amb.count = 12
	add_child(amb)

# ================================================================ 机关、敌人、对话

func _logic() -> void:
	# 电网：受光晶 → 管线 → 晶洞门
	grid = PowerGrid.new()
	add_child(grid)
	grid.setup(world, Vector3i(70, L2 - 2, 56), Vector3i(92, L1 + 4, 72))
	cave_door = PowerDoor.new()
	add_child(cave_door)
	var dc: Array[Vector3i] = []
	for z in range(60, 65):
		for y in range(L2, L2 + 4):
			dc.append(Vector3i(CAVE_DOOR_X, y, z))
	cave_door.setup(world, dc, [Vector3i(LENS.x + 2, L2 - 1, 62)] as Array[Vector3i])
	grid.add_device(cave_door)
	# 光束谜题 1
	p1_beam = beam(Vector3i(47, L1, 72), Vector3(0, 0, -1))
	mirror(Vector3i(47, L1, 54), 3)          # 正确朝向 5
	mirror(Vector3i(81, L1, 54), 6)          # 正确朝向 3
	mirror(Vector3i(64, L1, 49), 2)          # 干扰镜（坑北边）
	p1_beam.lens_changed.connect(func(_c: Vector3i, lit: bool) -> void:
		if lit and not SaveGame.flag("ab_lens"):
			SaveGame.set_flag("ab_lens")
			GameState.say("光照到受光晶了！电顺着管线流下去——下面第二层那扇晶洞门开了。")
			GameState.set_objective(4, "坐升降台下到第二层，进入东边的晶洞", _v(Vector3i(CAVE_DOOR_X - 2, L2, 62))))
	# 升降台：一直在第一层和第二层之间往返
	var lift := Lift.new()
	lift.size = Vector3(1.9, 0.3, 1.9)
	lift.always_on = true
	add_child(lift)
	var lc := LIFT_CELL
	lift.a = world.voxel_center(Vector3i(lc.x, L2, lc.z)) + Vector3(0.75, -0.4, 0.75)
	lift.b = world.voxel_center(Vector3i(lc.x, L1, lc.z)) + Vector3(0.75, -0.4, 0.75)
	lift.global_position = lift.b
	# 敌人
	spawn_enemy(Scrapling.new(), Vector3i(26, TOP, 60))
	spawn_enemy(Scrapling.new(), Vector3i(30, TOP, 76))
	spawn_enemy(Burrower.new(), Vector3i(24, TOP, 36))
	spawn_enemy(Rustfly.new(), _spiral_cell(160.0, 18.0), 3.0)
	spawn_enemy(Spikeshell.new(), _spiral_cell(100.0, 19.5))
	var mo := spawn_enemy(Mortar.new(), Vector3i(84, L1, 58)) as Mortar
	mo.reach = 22.0
	mo.interval = 3.6
	spawn_enemy(Rustfly.new(), Vector3i(60, L1, 80), 3.5)
	spawn_enemy(Burrower.new(), Vector3i(92, L2, 58))
	spawn_enemy(Burrower.new(), Vector3i(93, L2, 70))
	spawn_enemy(Rustfly.new(), Vector3i(109, L2, 60), 2.6)
	spawn_enemy(Spikeshell.new(), Vector3i(100, FLOOR, 64))
	# 种子方块
	seed_at("ab_s1", Vector3i(12, TOP, 56), 0)
	seed_at("ab_s2", _spiral_cell(140.0, 20.0) + Vector3i(0, 0, 0), 1)
	seed_at("ab_s3", Vector3i(109, L2, 56), 2)
	# 天坑中间一块漂浮的晶台（从第一层跳下去，气泡滑翔过去）
	var fp := Vector3i(54, L1 - 8, 72)
	world.fill_box(fp + Vector3i(-1, -1, -1), fp + Vector3i(1, -1, 1), Blocks.CRYSTAL)
	world.fill_box(fp + Vector3i(-1, -2, -1), fp + Vector3i(1, -2, 1), Blocks.DARKROCK_B)
	world.fill_box(fp + Vector3i(0, -3, 0), fp + Vector3i(0, -4, 0), Blocks.GEODE)
	seed_at("ab_s4", fp, 3)
	# 记忆碎片
	# 重构点：坑沿上的观测塔、第二层的矿工哨塔
	rebuild_tower("ab_t1", 22, 44, 150)
	rebuild_tower("ab_t2", 34, 90, 300, 14, {"coins": 35, "energy": 5})
	fragment("ab_1", Vector3i(22, TOP, 66), "艾拉·林，研究日志 #77：矿层里的晶体会“记住”光。我想，方块也会记住自己原来的样子吧。")
	fragment("ab_2", Vector3i(47, L1, 76), "艾拉·林，研究日志 #305：我在引擎里留了一个后门——如果重构失败，我可以自己进去修。这件事我没告诉任何人。")
	fragment("ab_3", Vector3i(110, L2, 66), "艾拉·林，研究日志 #410：第十年的风暴模拟跑了一千次。九百次，我们都来不及。……那剩下的一百次呢？")
	zone(TreasureChest, Vector3i(40, TOP, 26), Vector3i(40, TOP + 1, 26), {"chest_id": "ab_rim", "coins": 30, "energy": 4})
	zone(TreasureChest, Vector3i(109, L2, 76), Vector3i(109, L2 + 1, 76), {"chest_id": "ab_cave", "coins": 35, "energy": 5, "line": "晶洞深处的补给箱！矿工们以前把工资藏在这里……？"})
	# 检查点
	checkpoint(SPAWN + Vector3i(-2, 0, -2), SPAWN + Vector3i(2, 3, 2))
	var sp1 := _spiral_cell(200.0, 19.0)
	checkpoint(sp1 + Vector3i(-1, 0, -1), sp1 + Vector3i(1, 3, 1))
	checkpoint(Vector3i(46, L1, 64), Vector3i(49, L1 + 3, 68))
	checkpoint(Vector3i(78, L2, 60), Vector3i(82, L2 + 3, 64))
	checkpoint(Vector3i(89, L2, 60), Vector3i(92, L2 + 3, 64))
	checkpoint(Vector3i(88, FLOOR, TUNNEL_Z.x), Vector3i(91, FLOOR + 3, TUNNEL_Z.y))
	# 对话
	talk(SPAWN + Vector3i(-3, 0, -3), SPAWN + Vector3i(3, 5, 3), [
		"晶簇深渊——星球的矿层。那口天坑有二十米深，第三座重构塔就沉在最底下。",
		"升降井架的缆绳断了……只能走坑壁上的螺旋栈道。",
	])
	var ge := _spiral_cell(214.0, 22.0)
	talk(Vector3i(ge.x - 6, TOP, ge.z - 6), Vector3i(ge.x + 6, TOP + 4, ge.z + 6), [
		"栈道入口被紫色的共鸣晶簇堵住了。这种晶体一碰就会连锁共振——撞碎一块，整团都会碎掉。",
	])
	var cs := _spiral_cell(180.0, 19.0)
	talk(Vector3i(cs.x - 3, cs.y, cs.z - 3), Vector3i(cs.x + 3, cs.y + 4, cs.z + 3), [
		"前面那段石板全是裂纹——滚上去它就会塌。别停下，一口气冲过去！",
	])
	talk(Vector3i(44, L1, 60), Vector3i(52, L1 + 4, 76), [
		"那块会发光的大水晶是发射晶，它一直在朝北射光。看到那两面晶面镜了吗？撞一下镜子，它就转 45°。",
		"把光引到对面东边的受光晶上——受光晶一亮，电就会顺着管线往下流。",
	])
	talk(Vector3i(76, L1, 50), Vector3i(86, L1 + 4, 60), [
		"对面炮台的锈弹能被气浪打回去。它要是炸到镜子旁边……小心别被波及。",
	])
	talk(Vector3i(88, L2, 58), Vector3i(92, L2 + 4, 66), [
		"好暗……地上那些土包在动——下面藏着钻地鼹。等它钻出来喘气的时候再打，或者用钻头下砸把它震出来。",
	])
	talk(Vector3i(94, L2, 48), Vector3i(96, L2 + 4, 80), [
		"又是共鸣晶簇。这一面墙很大，撞一下，看它连着碎下去。",
	])
	talk(Vector3i(84, FLOOR, TUNNEL_Z.x - 1), Vector3i(88, FLOOR + 4, TUNNEL_Z.y + 1), [
		"前面就是坑底了……有什么东西在动。很大。",
	])
	# 目标
	GameState.set_objective(0, "去天坑边，找到下去的路", _v(ge))
	objective(1, "沿螺旋栈道下到第一层环台", _spiral_cell(150.0, 19.0), Vector3i(ge.x - 3, TOP - 3, ge.z - 3), Vector3i(ge.x + 3, TOP + 3, ge.z + 3))
	objective(2, "转动晶面镜，把光引到东边的受光晶上", LENS, Vector3i(44, L1, 60), Vector3i(52, L1 + 4, 76))
	objective(5, "穿过晶洞，找到往下的路", Vector3i(108, L2, 71), Vector3i(88, L2, 58), Vector3i(92, L2 + 4, 66))
	objective(6, "去坑底", Vector3i(86, FLOOR, 64), Vector3i(104, FLOOR, TUNNEL_Z.x - 2), Vector3i(111, FLOOR + 4, 74))
	# Boss
	_setup_boss()
	zone(MusicZone, Vector3i(84, L2 - 2, 46), Vector3i(114, L2 + 12, 82), {"state": "puzzle"})
	coin_line(Vector3i(20, TOP, 64), Vector3i(34, TOP, 64), 6)
	coin_line(Vector3i(88, L2, 62), Vector3i(95, L2, 62), 4)

# ================================================================ Boss

## 三台发射晶（每阶段亮一台），各自对着一面“关键镜”：把那面镜子转到正确的角度，光就会穿过场地中心
const BOSS_SETUPS := [
	# [发射晶格, 发射方向, 关键镜格, 正确朝向]
	[Vector3i(74, FLOOR, 49), Vector3(0, 0, 1), Vector3i(74, FLOOR, 64), 1],
	[Vector3i(54, FLOOR, 79), Vector3(0, 0, -1), Vector3i(54, FLOOR, 64), 5],
	[Vector3i(79, FLOOR, 54), Vector3(-1, 0, 0), Vector3i(64, FLOOR, 54), 5],
]
var boss_mirrors: Array[BeamMirror] = []

func _setup_boss() -> void:
	boss = CrystalColossus.new()
	add_child(boss)
	boss.global_position = world.voxel_top(Vector3i(C.x - 4, FLOOR - 1, C.y))
	boss.arena_center = world.voxel_top(Vector3i(C.x, FLOOR - 1, C.y))
	boss.arena_radius = 8.5
	boss.rotation.y = -PI / 2.0
	boss.defeated.connect(_on_boss_defeated)
	boss.phase_changed.connect(_boss_phase)
	for i in BOSS_SETUPS.size():
		var s: Array = BOSS_SETUPS[i]
		var b := beam(s[0], s[1], Color(0.85, 0.7, 1.0))
		b.active = false
		boss_beams.append(b)
		boss_mirrors.append(mirror(s[2], (int(s[3]) + 3) % 8))
	# 两面干扰镜
	boss_mirrors.append(mirror(Vector3i(64, FLOOR, 74), 0))
	boss_mirrors.append(mirror(Vector3i(56, FLOOR, 56), 2))
	var trig := zone(Zone, Vector3i(C.x - 16, FLOOR, C.y - 16), Vector3i(C.x + 17, FLOOR + 5, C.y + 16))
	trig.player_entered.connect(func() -> void:
		if is_instance_valid(boss) and not boss.active and not boss_done:
			if not ChapterKey.unseal(self, boss, "abyss"):
				return
			boss.start()
			boss_beams[0].active = true
			Music.play_area("boss")
			Music.set_override("explore")
			GameState.say("晶簇巨像！它的晶甲太硬，撞不动……那边的发射晶亮了——转动镜子，把光照到它身上！"))

func _boss_phase(hp: int) -> void:
	var i := clampi(boss.max_hp - hp, 0, boss_beams.size() - 1)
	for k in boss_beams.size():
		boss_beams[k].active = k == i
	# 新一轮：把这一轮的关键镜拨乱
	var m := boss_mirrors[i]
	m.facing = (int(BOSS_SETUPS[i][3]) + 2) % 8
	m._apply(true)
	if hp <= 1:
		Music.set_override("bright")

func _on_boss_defeated(_e: Node) -> void:
	boss_done = true
	for b in boss_beams:
		b.active = false
	SaveGame.set_flag("ab_boss")
	Music.play_area("ab")
	Music.set_override("")
	GameState.say("巨像倒下了……看，坑底中央在震动——第三座重构塔要升起来了！")
	_raise_tower(false)
	reconstruct(world.voxel_center(Vector3i(C.x, FLOOR, C.y)), 100.0)

## 重构塔从坑底中央一层层升起来，光柱冲出天坑
func _raise_tower(instant: bool) -> void:
	if tower_built:
		return
	tower_built = true
	var cells: Array = []
	var H := 44
	for y in H:
		var r := 2 if y < 4 else (1 if y < H - 2 else 0)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := Blocks.HULL
				if y < 4:
					t = Blocks.HULL_DARK
				elif y % 7 == 0:
					t = Blocks.CRYSTAL
				cells.append([Vector3i(C.x + dx, FLOOR + y, C.y + dz), t])
		if y in [14, 26, 36]:
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if maxi(absi(dx), absi(dz)) == 3:
						cells.append([Vector3i(C.x + dx, FLOOR + y, C.y + dz), Blocks.LAMP if absi(dx) == 3 and absi(dz) == 3 else Blocks.HULL])
	var top := Vector3i(C.x, FLOOR + H, C.y)
	cells.append([top, Blocks.RECEIVER_ON])
	if instant:
		for c in cells:
			world.set_block(c[0], c[1])
		tower_beam(top)
		_make_goal()
		return
	# 先把 PIX 推开一点，免得被塔顶起来
	var p := GameState.player as MorphBall
	if p and Vector2(p.global_position.x - world.voxel_center(top).x, p.global_position.z - world.voxel_center(top).z).length() < 3.0:
		p.linear_velocity = Vector3(3, 4, 0)
	Sfx.play("bridge", Vector3.INF, 0.0, 0.0)
	GameState.shake.emit(0.5)
	var i := 0
	for c in cells:
		i += 1
		var cc: Vector3i = c[0]
		var tt: int = c[1]
		get_tree().create_timer(0.8 + (cc.y - FLOOR) * 0.09).timeout.connect(func() -> void:
			world.set_block(cc, tt))
	get_tree().create_timer(0.8 + H * 0.09 + 0.5).timeout.connect(func() -> void:
		tower_beam(top)
		GameState.shake.emit(0.8)
		Sfx.play("level_clear", Vector3.INF, -6.0, 0.0)
		_make_goal())

func _make_goal() -> void:
	var goal := zone(Goal, Vector3i(C.x - 6, FLOOR, C.y - 6), Vector3i(C.x + 6, FLOOR + 4, C.y + 6)) as Goal
	goal.line = "第三座塔……亮了。光从坑底一直打到天上。PIX，还剩两座。"
	GameState.set_objective(10, "走到重构塔下", _v(Vector3i(C.x + 4, FLOOR, C.y)))

func _apply_flags(flags: Dictionary) -> void:
	if bool(flags.get("ab_boss", false)):
		if is_instance_valid(boss):
			boss.queue_free()
		boss_done = true
		_raise_tower(true)

## 从第二章过来时的抵达镜头
func arrival_shots() -> Array:
	var V := VoxelWorld.CELL_M
	return [
		{"from": Vector3(-40, 110, 170) * V, "to": Vector3(-10, 100, 140) * V, "look": Vector3(64, 50, 64) * V, "dur": 6.0, "fade": Color.BLACK,
			"lines": [["NOVA", "第二座塔的光桥把你送到了这里——晶簇深渊，星球的矿层。"], ["NOVA", "以前一半的矿石都从这口天坑里运出来。"]]},
		{"from": Vector3(64, 96, 64) * V, "to": Vector3(64, 80, 66) * V, "look_from": Vector3(64, 40, 64) * V, "look_to": Vector3(64, 16, 64) * V, "dur": 5.0,
			"lines": [["NOVA", "第三座塔……在最底下。"]]},
		{"from": Vector3(4, 80, 76) * V, "to": Vector3(8, 77, 70) * V, "look": Vector3(SPAWN) * V, "dur": 4.0,
			"lines": [["NOVA", "从坑沿的晶矿站出发吧。"]]},
	]
