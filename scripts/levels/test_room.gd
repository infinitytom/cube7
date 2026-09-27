class_name TestRoom
extends Node3D
## 测试关卡（对应计划书路线图第一个关口“拆得好玩吗”）。
## 全部用代码搭建，坐标单位为体素（1 体素 = 0.5 米）。沿 +X 方向依次是：
##   A 草地广场（撞木箱、砂堆）→ 玻璃墙（加速/冲刺撞碎）
##   B 岩石区（钻头钻穿）
##   C 回路实验室（物资箱掉落晶块 → 放进缺口 → 能量门；磁铁墙；上升气流）
##   D 压力板房（立方形态压开闸门）
##   E 悬空平衡轨道 → 终点

const SPAWN := Vector3i(5, 4, 32)
const WALL_TOP := 13

@export var world_path: NodePath

var world: VoxelWorld
var circuit: EnergyCircuit
var plate: PressurePlate
var socket: ItemSocket
var crystal: UsableItem

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	_build_terrain()
	world.rebuild_all()
	_build_logic()
	world.item_dropped.connect(_on_item_dropped)
	GameState.set_checkpoint(spawn_position())

func spawn_position() -> Vector3:
	return world.voxel_top(SPAWN + Vector3i.DOWN) + Vector3.UP * 0.55

# ---------------------------------------------------------------- 地形

func _box(a: Vector3i, b: Vector3i, t: int) -> void:
	world.fill_box(a, b, t)

func _build_terrain() -> void:
	# 外墙（z=15 / z=48 两侧 + 后墙），x 0..91
	_box(Vector3i(0, 0, 15), Vector3i(91, 2, 48), Blocks.BEDROCK)
	_box(Vector3i(0, 3, 15), Vector3i(91, WALL_TOP, 15), Blocks.BEDROCK)
	_box(Vector3i(0, 3, 48), Vector3i(91, WALL_TOP, 48), Blocks.BEDROCK)
	_box(Vector3i(0, 3, 15), Vector3i(0, WALL_TOP, 48), Blocks.BEDROCK)

	# ---- A 草地广场 x1..29
	_box(Vector3i(1, 3, 16), Vector3i(29, 3, 47), Blocks.GRASS)
	for c in [Vector3i(10, 4, 22), Vector3i(14, 4, 40), Vector3i(20, 4, 26), Vector3i(24, 4, 34), Vector3i(8, 4, 38)]:
		_box(c, c + Vector3i(1, 1, 1), Blocks.CRATE)
	# 砂堆（撞掉底部，上面会塌下来），里面埋着金矿
	for i in 4:
		_box(Vector3i(16 + i, 4 + i, 36 + i), Vector3i(22 - i, 4 + i, 42 - i), Blocks.SAND)
	_box(Vector3i(19, 4, 39), Vector3i(19, 4, 39), Blocks.ORE)
	_box(Vector3i(2, 4, 16), Vector3i(6, 5, 19), Blocks.DIRT)
	_box(Vector3i(2, 6, 16), Vector3i(4, 6, 17), Blocks.DIRT)

	# ---- 玻璃墙 x30..31（中间是玻璃，两边是不可破坏的合金骨架）
	_box(Vector3i(30, 3, 16), Vector3i(31, WALL_TOP, 47), Blocks.BEDROCK)
	_box(Vector3i(30, 4, 24), Vector3i(31, 11, 39), Blocks.GLASS)

	# ---- B 岩石区 x32..51
	_box(Vector3i(32, 3, 16), Vector3i(51, 3, 47), Blocks.GRASS)
	_box(Vector3i(36, 4, 18), Vector3i(40, 5, 21), Blocks.DIRT)
	for i in 3:
		_box(Vector3i(40 + i, 4 + i, 38 + i), Vector3i(46 - i, 4 + i, 44 - i), Blocks.SAND)
	_box(Vector3i(43, 7, 41), Vector3i(43, 7, 41), Blocks.CRATE)
	_box(Vector3i(46, 4, 22), Vector3i(47, 5, 23), Blocks.CRATE)
	# 岩壁 x52..55（中段是岩石，可钻穿）
	_box(Vector3i(52, 3, 16), Vector3i(55, WALL_TOP, 47), Blocks.BEDROCK)
	_box(Vector3i(52, 4, 25), Vector3i(55, 9, 38), Blocks.ROCK)
	for p in [Vector3i(53, 5, 28), Vector3i(54, 7, 33), Vector3i(52, 4, 36), Vector3i(55, 6, 30), Vector3i(53, 4, 32)]:
		_box(p, p, Blocks.ORE)

	# ---- C 回路实验室 x56..79
	_box(Vector3i(56, 3, 16), Vector3i(79, 3, 47), Blocks.TILE)
	# 能量门墙 x80..81
	_box(Vector3i(80, 3, 16), Vector3i(81, WALL_TOP, 47), Blocks.BEDROCK)
	_box(Vector3i(80, 4, 28), Vector3i(81, 9, 35), Blocks.DOOR)
	# 能量源 → 地面水晶线（x=68 缺一格）→ 接收器
	_box(Vector3i(58, 3, 31), Vector3i(59, 6, 32), Blocks.SOURCE)
	_box(Vector3i(60, 3, 31), Vector3i(77, 3, 32), Blocks.CRYSTAL)
	_box(Vector3i(68, 3, 31), Vector3i(68, 3, 31), Blocks.AIR)
	_box(Vector3i(68, 3, 32), Vector3i(68, 3, 32), Blocks.TILE)
	_box(Vector3i(78, 3, 31), Vector3i(79, 6, 32), Blocks.RECEIVER)
	# 物资箱（撞开后掉出能量晶块）
	_box(Vector3i(64, 4, 21), Vector3i(65, 5, 22), Blocks.CRATE_ITEM)
	# 磁铁攀爬墙 + 顶部平台
	_box(Vector3i(60, 4, 43), Vector3i(67, 12, 43), Blocks.METAL)
	_box(Vector3i(60, 4, 44), Vector3i(67, 12, 47), Blocks.BEDROCK)
	_box(Vector3i(62, 13, 45), Vector3i(63, 14, 46), Blocks.CRATE)
	_box(Vector3i(65, 13, 45), Vector3i(65, 13, 45), Blocks.CRATE)
	# 上升气流出风口 + 高处平台
	_box(Vector3i(73, 3, 18), Vector3i(74, 3, 19), Blocks.METAL)
	_box(Vector3i(70, 4, 16), Vector3i(77, 9, 17), Blocks.BEDROCK)
	_box(Vector3i(71, 10, 16), Vector3i(72, 11, 17), Blocks.CRATE)
	_box(Vector3i(75, 10, 16), Vector3i(75, 10, 16), Blocks.CRATE)

	# ---- D 压力板房 x82..89
	_box(Vector3i(82, 3, 16), Vector3i(89, 3, 47), Blocks.TILE)
	_box(Vector3i(84, 3, 30), Vector3i(86, 3, 33), Blocks.PLATE)
	_box(Vector3i(90, 3, 16), Vector3i(91, WALL_TOP, 47), Blocks.BEDROCK)
	_box(Vector3i(90, 4, 28), Vector3i(91, 9, 35), Blocks.GATE)

	# ---- E 悬空平衡轨道 x92..111（下方是虚空）
	_box(Vector3i(92, 0, 27), Vector3i(95, 3, 36), Blocks.BEDROCK)
	_box(Vector3i(96, 2, 30), Vector3i(101, 3, 32), Blocks.TRACK)
	_box(Vector3i(99, 2, 33), Vector3i(101, 3, 41), Blocks.TRACK)
	_box(Vector3i(102, 2, 39), Vector3i(107, 3, 41), Blocks.TRACK)
	_box(Vector3i(105, 2, 22), Vector3i(107, 3, 38), Blocks.TRACK)
	_box(Vector3i(104, 0, 14), Vector3i(111, 3, 21), Blocks.BEDROCK)
	_box(Vector3i(109, 4, 16), Vector3i(110, 7, 17), Blocks.GOAL)

# ---------------------------------------------------------------- 机关与触发

## 用体素包围盒（含两端）放置一个区域
func _zone(script: GDScript, a: Vector3i, b: Vector3i, props := {}) -> Node:
	var z: Node3D = script.new()
	z.set("box_size", Vector3(b - a + Vector3i.ONE) * VoxelWorld.VOXEL)
	for k in props:
		z.set(k, props[k])
	add_child(z)
	z.global_position = world.to_global(Vector3(a + b + Vector3i.ONE) * VoxelWorld.VOXEL * 0.5)
	return z

func _talk(a: Vector3i, b: Vector3i, lines: Array) -> void:
	_zone(TalkTrigger, a, b, {"lines": PackedStringArray(lines)})

func _build_logic() -> void:
	# A
	_zone(Checkpoint, Vector3i(3, 4, 29), Vector3i(7, 7, 35))
	_talk(Vector3i(1, 4, 16), Vector3i(9, 12, 47), [
		"PIX，醒醒！我是站点 AI NOVA。坏消息：整颗星球……好像被变成了方块。",
		"用{move}滚动，{camera}转镜头，{jump}跳跃。先撞开那些木箱试试——碎屑会消失，金币会自己飞进你肚子里。",
	])
	_talk(Vector3i(22, 4, 16), Vector3i(29, 12, 47), [
		"前面是玻璃墙，普通速度撞不碎。按住{boost}加速冲过去，或者按{ability}冲刺！",
	])
	# B
	_zone(Checkpoint, Vector3i(33, 4, 28), Vector3i(36, 7, 35))
	_talk(Vector3i(44, 4, 16), Vector3i(51, 12, 47), [
		"岩石撞不碎。用{form}切换形态（或{form_direct}直选），换成钻头，按住{ability}往前钻。",
		"小提示：站着不动按住{ability}会往下钻。金矿里有金币。",
	])
	# C
	_zone(Checkpoint, Vector3i(57, 4, 36), Vector3i(60, 7, 40))
	_talk(Vector3i(56, 4, 24), Vector3i(62, 12, 41), [
		"回路实验室。地上的水晶线从能量源通到门口的接收器，可中间断了一格。",
		"那个蓝色物资箱里有能量晶块。撞开它，按{grab}抓起来，再按{grab}扔进发光的缺口。",
	])
	_talk(Vector3i(60, 4, 38), Vector3i(67, 8, 42), [
		"金属墙！换成磁铁形态，按住{ability}吸在墙上，推向墙就能往上爬。上面有补给。",
	])
	_talk(Vector3i(70, 4, 18), Vector3i(77, 8, 24), [
		"出风口有上升气流。太重的形态吹不动——换成气泡试试，{ability}还能喷气上浮。",
	])
	socket = ItemSocket.new()
	add_child(socket)
	socket.setup(world, Vector3i(68, 3, 31))
	circuit = EnergyCircuit.new()
	add_child(circuit)
	var doors: Array[Vector3i] = _cells(Vector3i(80, 4, 28), Vector3i(81, 9, 35))
	circuit.setup(world, Vector3i(58, 3, 31), Vector3i(78, 3, 31), doors)
	_zone(Fan, Vector3i(73, 4, 18), Vector3i(74, 12, 19), {"strength": 3.2})
	# D
	_zone(Checkpoint, Vector3i(82, 4, 36), Vector3i(85, 7, 40))
	_talk(Vector3i(82, 4, 22), Vector3i(89, 10, 29), [
		"压力板。滚球太轻压不动，换成立方形态压上去。",
	])
	plate = _zone(PressurePlate, Vector3i(84, 4, 30), Vector3i(86, 5, 33), {"mass_threshold": 2.8}) as PressurePlate
	plate.world = world
	plate.gate_blocks = _cells(Vector3i(90, 4, 28), Vector3i(91, 9, 35))
	# E
	_zone(Checkpoint, Vector3i(92, 4, 28), Vector3i(95, 7, 35), {"lock_form": MorphBall.BALL, "locks": true})
	_zone(MorphStation, Vector3i(93, 4, 29), Vector3i(95, 7, 34), {"set_form": MorphBall.BALL, "lock": true})
	_talk(Vector3i(92, 4, 27), Vector3i(95, 10, 36), [
		"平衡轨道——向《平衡球》致敬。掉下去会回到这里，慢慢来，别急着加速。",
	])
	_zone(MorphStation, Vector3i(104, 4, 18), Vector3i(111, 7, 21), {"set_form": MorphBall.BALL, "lock": false})
	_zone(Goal, Vector3i(106, 4, 14), Vector3i(111, 8, 21))

func _cells(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				out.append(Vector3i(x, y, z))
	return out

func _on_item_dropped(item_id: String, pos: Vector3) -> void:
	# 物资箱由多个方块组成，只掉一个晶块
	if item_id == "crystal" and crystal == null and not circuit.opened:
		crystal = UsableItem.new()
		crystal.item_id = "crystal"
		add_child(crystal)
		crystal.global_position = pos + Vector3.UP * 0.3
		crystal.home = crystal.global_position
		crystal.linear_velocity = Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1))
		GameState.say("掉出来一块能量晶块！它带发光描边——这种有用的东西会留在场上。")
