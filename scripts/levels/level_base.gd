class_name LevelBase
extends Node3D
## 关卡基类：搭建工具函数（区域、对话、金币、树……）

@export var world_path: NodePath

var world: VoxelWorld
var decor: Decor
var rng := RandomNumberGenerator.new()

func build() -> void:
	pass

func spawn_position() -> Vector3:
	return Vector3.ZERO

func spawn_yaw() -> float:
	return -PI / 2.0

## 用体素包围盒（含两端）放置一个区域
func zone(script: GDScript, a: Vector3i, b: Vector3i, props := {}) -> Node:
	var z: Node3D = script.new()
	z.set("box_size", Vector3((b - a).abs() + Vector3i.ONE) * VoxelWorld.CELL_M)
	for k in props:
		z.set(k, props[k])
	add_child(z)
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	z.global_position = world.to_global(Vector3(lo + hi + Vector3i.ONE) * VoxelWorld.CELL_M * 0.5)
	return z

func talk(a: Vector3i, b: Vector3i, lines: Array) -> void:
	zone(TalkTrigger, a, b, {"lines": PackedStringArray(lines)})

func cells(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				out.append(Vector3i(x, y, z))
	return out

## 在体素 cell（空气格）里放一枚金币，悬浮在格子中间偏下
func coin(cell: Vector3i) -> void:
	var c := StaticCoin.new()
	add_child(c)
	c.global_position = world.voxel_center(cell) + Vector3.UP * 0.25

## 两点之间摆一串金币（引路面包屑）
func coin_line(a: Vector3i, b: Vector3i, n: int) -> void:
	for i in n:
		var t := 0.0 if n == 1 else float(i) / (n - 1)
		var p := Vector3(a).lerp(Vector3(b), t)
		coin(Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)))

## 地表高度：列 (x, z) 最高的实心方块上方那一格的 y（没有地面返回 -1）
func surface_y(x: int, z: int) -> int:
	for y in range(world.csize.y - 2, -1, -1):
		if world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y + 1 if world.get_shape(Vector3i(x, y, z)) == 0 else -1
	return -1

## 在 (x, z) 附近找一块 w×w 的平地，返回地面上方那一格；找不到返回 (-1,-1,-1)
func find_flat(x: int, z: int, rad := 5, w := 3) -> Vector3i:
	for r in range(0, rad + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cx := x + dx
				var cz := z + dz
				var h := surface_y(cx, cz)
				if h < 0:
					continue
				var ok := true
				var half := w / 2
				for oz in range(-half, half + 1):
					for ox in range(-half, half + 1):
						if surface_y(cx + ox, cz + oz) != h:
							ok = false
				if ok:
					return Vector3i(cx, h, cz)
	return Vector3i(-1, -1, -1)

## 一个不会被撞飞的装饰物件（营地的箱子、设备……）
func deco(path: String, x: int, z: int, height_m: float, solid := "box", yaw := INF) -> Prop:
	var c := find_flat(x, z, 4, 3)
	if c.y < 0:
		return null
	var p := prop(path, c, height_m, false, 0, solid)
	if yaw != INF:
		p.rotation.y = yaw
	return p

## 一棵体素树（0.25 米精度，树叶撞得碎、树干要钻）。base = 地面上方那一格；h 为树干高度（格），r 为树冠半径（格）
func tree(base: Vector3i, h: int, r: float, kind := "") -> void:
	if kind == "":
		var roll := rng.randf()
		kind = "pine" if roll < 0.35 else ("blossom" if roll < 0.45 else "round")
	var root := Vector3i(base.x * VoxelWorld.CELL, base.y * VoxelWorld.CELL, base.z * VoxelWorld.CELL)
	# 贴地：往下找到真正的地面体素
	while root.y > 0 and world.vget(root + Vector3i.DOWN) == Blocks.AIR:
		root.y -= 1
	var trunk := int(h * VoxelWorld.CELL * (1.1 if kind == "pine" else 0.85))
	world.put_tree(root, trunk, r * VoxelWorld.CELL_M * (0.85 if kind == "pine" else 0.9), kind, rng)

## 在地面格 base（空气格，下方是地面）上放一个道具
func prop(path: String, base: Vector3i, height_m: float, breakable := true, coins := 1, solid := "trunk", sound := "break_wood") -> Prop:
	var p := Prop.new()
	p.model_path = path
	p.height = height_m
	p.breakable = breakable
	p.coins = coins
	p.solid = solid
	p.pop_sound = sound
	p.ground_cell = base + Vector3i.DOWN
	add_child(p)
	p.global_position = world.voxel_top(base + Vector3i.DOWN)
	return p

## 灯柱
func lamp_post(base: Vector3i, h := 3) -> void:
	world.fill_box(base, base + Vector3i(0, h - 2, 0), Blocks.HULL_DARK)
	world.fill_box(base + Vector3i(0, h - 1, 0), base + Vector3i(0, h - 1, 0), Blocks.LAMP)
	var l := OmniLight3D.new()
	l.light_color = Color("ffe0a0")
	l.light_energy = 0.8
	l.omni_range = 5.0
	add_child(l)
	l.global_position = world.voxel_center(base + Vector3i(0, h - 1, 0))

## 在地面上撒草丛和花
func scatter_decor(region_lo: Vector3i, region_hi: Vector3i, grass_rate: float, flower_rate: float, prop_rate := 0.012) -> void:
	var flowers := ["flower_red", "flower_yellow", "flower_white", "flower_blue"]
	for z in range(region_lo.z, region_hi.z + 1):
		for x in range(region_lo.x, region_hi.x + 1):
			for y in range(region_hi.y, region_lo.y - 1, -1):
				var t := world.get_block(Vector3i(x, y, z))
				if t == Blocks.AIR:
					continue
				if t == Blocks.GRASS and world.get_shape(Vector3i(x, y, z)) == 0 and world.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR:
					var roll := rng.randf()
					if roll < prop_rate:
						# 零星的 Kenney 小道具：花丛、蘑菇、小草、石头（小的可以撞飞）
						var pick := rng.randf()
						if pick < 0.45:
							prop(Kit.FLOWERS[rng.randi() % Kit.FLOWERS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.45, 0.7), true, 0, "none", "break_soft")
						elif pick < 0.8:
							prop(Kit.PLANTS[rng.randi() % Kit.PLANTS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.4, 0.65), true, 1, "none", "break_soft")
						else:
							prop(Kit.ROCKS[rng.randi() % Kit.ROCKS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.3, 0.5), true, 0, "none", "break_hard")
					elif roll < flower_rate:
						decor.add(flowers[rng.randi() % flowers.size()], Vector3i(x, y, z), rng)
					elif roll < flower_rate + grass_rate:
						decor.add("grass", Vector3i(x, y, z), rng)
				break
