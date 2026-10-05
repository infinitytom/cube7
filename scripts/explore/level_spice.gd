class_name LevelSpice
extends RefCounted
## 给每一章加上“体素探索”的支线内容（在关卡搭好、晶核埋好之后调用）：
##
## 1. 地下洞穴：从地表某个不起眼的地方（一圈荧光菇、一块松土）往下蜿蜒的天然隧道，
##    一路长着荧光菇，通往某颗回声晶核附近——最后一两米被松土堵着：扫描能看到墙后的晶核，钻开就到。
## 2. 落石陷阱：敌人营地旁边立着一根橙色的支撑木架，顶上托着一块大石头。
##    撞断木架，石头砸下来能把附近的锈块兽压扁（扫描会把木架标成“承重点”）。
##
## 都用固定种子，每次进同一章都一样。

const CAVES := 2
## 隧道只挖这些“普通地层”；碰到别的东西（晶洞、矿、建筑、机关）就换一条路——不破坏关卡原有的谜题
const PLAIN := [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.ROCK, Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C,
	Blocks.MOSS, Blocks.LOOSE, Blocks.DARKROCK, Blocks.DARKROCK_B, Blocks.RUSTDUNE, Blocks.RUSTROCK]
const TRAPS := 2

static func apply(level: Node3D, world: VoxelWorld, chapter_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("spice:" + chapter_id)
	var caves := 0
	_avoid = _designed_points(level)
	var cores := level.get_tree().get_nodes_in_group("scan_target")
	# 优先给“钻头钻得动”的晶核挖洞（需要进化的那些留给后面再来）
	# 关键道具排第一：保证有一条洞穴通向它
	var sorted: Array = cores.filter(func(c: Node) -> bool: return c is KeyRelic)
	sorted.append_array(cores.filter(func(c: Node) -> bool: return c is EchoCore and (c as EchoCore).locked_hint == "" and not c.is_queued_for_deletion()))
	for c in sorted:
		if caves >= CAVES:
			break
		for attempt in 4:
			var e := _cave_to(world, (c as Node3D).global_position, rng)
			if e.x >= 0:
				caves += 1
				level.set_meta("spice_caves", level.get_meta("spice_caves", []) + [e])
				break
	var traps := 0
	var enemies := level.get_tree().get_nodes_in_group("enemy")
	enemies.shuffle()
	for e in enemies:
		if traps >= TRAPS:
			break
		var sc: Variant = (e as Node).get_script()
		if sc == null or not str(sc.resource_path).ends_with("scrapling.gd"):
			continue
		var b := _boulder_trap(world, (e as Node3D).global_position, rng)
		if b.x >= 0:
			traps += 1
			level.set_meta("spice_traps", level.get_meta("spice_traps", []) + [b])
	world.flush_dirty()
	print("[Spice] %s：地下洞穴 %d 条，落石陷阱 %d 处" % [chapter_id, caves, traps])

## 从晶核旁边往地表找一条蜿蜒的通道：先找附近合适的地表入口，再从入口往晶核走（随机游走 + 朝目标偏）
## 返回入口的体素坐标（失败返回 x = -1）
static func _cave_to(world: VoxelWorld, target: Vector3, rng: RandomNumberGenerator) -> Vector3i:
	var tv := world.to_v(target)
	# 入口：晶核水平 6～10 米外的地表（平滑材质的地面）
	var entry := Vector3i(-1, -1, -1)
	for k in 80:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(6.0, 10.0) / VoxelWorld.VOXEL
		var ex := tv.x + int(cos(a) * dist)
		var ez := tv.z + int(sin(a) * dist)
		if ex < 8 or ez < 8 or ex >= world.size.x - 8 or ez >= world.size.z - 8:
			continue
		var top := _surface_v(world, ex, ez)
		if top < 0 or top <= tv.y + 6:
			continue
		var t := world.vget(Vector3i(ex, top, ez))
		if Blocks.drill[t] == 0 or Blocks.smooth[t] == 0:
			continue
		var ewp := world.vcenter(Vector3i(ex, top, ez))
		var near := false
		for av in _avoid:
			if av.distance_to(ewp) < 8.0:
				near = true
				break
		if near:
			continue
		entry = Vector3i(ex, top, ez)
		break
	if entry.x < 0:
		if OS.has_environment("CUBE7_SPICE_DBG"):
			print("  cave: no entry near ", tv)
		return Vector3i(-1, -1, -1)
	# 走一条隧道：每步 1 个体素，朝目标偏，左右晃动；半径 3～4 体素（PIX 滚得进去）
	var p := Vector3(entry) + Vector3(0.5, 0.5, 0.5)
	var goal := Vector3(tv) + Vector3(0.5, 0.5, 0.5)
	var wobble := Vector3.ZERO
	var path: Array[Vector3] = []
	for step in 400:
		var to_goal := goal - p
		var d := to_goal.length()
		# 离晶洞 1.5 米时停下：剩下的一段用松土堵上
		if d < 6.0:
			break
		wobble = (wobble + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * 0.35).limit_length(0.8)
		var dir := (to_goal.normalized() + wobble).normalized()
		# 坡度别太陡：滚球也爬得上来
		dir.y = clampf(dir.y, -0.55, 0.35)
		p += dir.normalized()
		path.append(p)
	if path.size() < 10:
		if OS.has_environment("CUBE7_SPICE_DBG"):
			print("  cave: path too short ", path.size())
		return Vector3i(-1, -1, -1)
	# 隧道离关卡里设计过的地方（出生点、检查点……）至少 5 米：不能把它们脚下挖空
	for c in path:
		var cw := world.to_global(c * VoxelWorld.VOXEL)
		for av3 in _avoid:
			if av3.distance_to(cw) < 5.0:
				return Vector3i(-1, -1, -1)
	# 整条隧道（含洞壁外 2 体素）只能碰到普通地层或空气
	for c in path:
		for z in range(-4, 5, 2):
			for y in range(-4, 5, 2):
				for x in range(-4, 5, 2):
					var t0 := world.vget(Vector3i((c + Vector3(x, y, z)).floor()))
					if t0 != Blocks.AIR and not t0 in PLAIN and not t0 in [Blocks.WOOD, Blocks.LEAVES, Blocks.PINE, Blocks.BLOSSOM, Blocks.GEM_CHAIN, Blocks.ORE]:
						if OS.has_environment("CUBE7_SPICE_DBG"):
							print("  cave: blocked by ", Blocks.DEFS[t0].name, " at ", c, " entry ", entry)
						return Vector3i(-1, -1, -1)
	var placed := 0
	for i in path.size():
		var c := path[i]
		var r := 3.2 + 0.8 * sin(i * 0.21)
		var ir := int(ceil(r))
		for z in range(-ir, ir + 1):
			for y in range(-ir, ir + 1):
				for x in range(-ir, ir + 1):
					var off := Vector3(x, y * 1.15, z)
					if off.length() > r:
						continue
					var v := Vector3i((c + Vector3(x, y, z)).floor())
					var t := world.vget(v)
					if t == Blocks.AIR or not t in PLAIN:
						continue
					world.vset(v, Blocks.AIR)
		# 洞壁上零星的荧光菇（照亮隧道，也是“这里有东西”的提示）
		if i % 9 == 4:
			var side := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.2), rng.randf_range(-1, 1)).normalized()
			for k in range(3, 7):
				var q := Vector3i((c + side * k).floor())
				if world.vget(q) != Blocks.AIR:
					world.vset(q, Blocks.GLOWSHROOM)
					placed += 1
					break
	# 入口一圈荧光菇 + 洞底到晶洞之间的松土塞子
	for k in 6:
		var a := k * TAU / 6.0
		var q := Vector3i(entry.x + int(cos(a) * 5.0), entry.y, entry.z + int(sin(a) * 5.0))
		var top := _surface_v(world, q.x, q.z)
		if top > 0 and top + 1 < world.size.y:
			world.vset(Vector3i(q.x, top + 1, q.z), Blocks.GLOWSHROOM)
	var last := path[path.size() - 1]
	var dir2 := (goal - last).normalized()
	for s in range(1, 6):
		var cc := last + dir2 * s
		for z in range(-2, 3):
			for y in range(-2, 3):
				for x in range(-2, 3):
					var v := Vector3i((cc + Vector3(x, y, z)).floor())
					var t := world.vget(v)
					if t != Blocks.AIR and Blocks.smooth[t] == 1 and Blocks.drill[t] == 0:
						world.vset(v, Blocks.LOOSE)
	return entry

static var _avoid: Array[Vector3] = []

## 关卡里“设计过的地方”：触发区、检查点、重构点、宝箱、种子方块、出生点……洞口和陷阱都离它们远一点
static func _designed_points(level: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in level.find_children("*", "Node3D", true, false):
		if n is Checkpoint or n is ObjectiveZone or n is Goal or n is TreasureChest or n is MemoryFragment \
				or n is ItemSocket or n is PressurePlate or n is MorphStation or n is FormCore or n is CoinChallenge:
			out.append((n as Node3D).global_position)
	for grp in ["rebuild_site", "seed_cube", "usable_item"]:
		for n in level.get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				out.append((n as Node3D).global_position)
	if level.has_method("spawn_position"):
		out.append(level.call("spawn_position"))
	return out

static func _surface_v(world: VoxelWorld, x: int, z: int) -> int:
	for y in range(world.size.y - 1, -1, -1):
		if world.vget(Vector3i(x, y, z)) != Blocks.AIR:
			return y
	return -1

## 敌人旁边立一根支撑木架，顶上托一块圆石：撞断木架，石头砸下来
## 返回木架底部的体素坐标（失败返回 x = -1）
static func _boulder_trap(world: VoxelWorld, at: Vector3, rng: RandomNumberGenerator) -> Vector3i:
	var ev := world.to_v(at)
	for k in 32:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(1.6, 2.4) / VoxelWorld.VOXEL
		var bx := ev.x + int(cos(a) * dist)
		var bz := ev.z + int(sin(a) * dist)
		var top := _surface_v(world, bx, bz)
		if top < 0 or absi(top - (ev.y - 1)) > 3:
			continue
		var bwp := world.vcenter(Vector3i(bx, top, bz))
		var near2 := false
		for av2 in _avoid:
			if av2.distance_to(bwp) < 3.0:
				near2 = true
				break
		if near2:
			continue
		# 头顶要有 4 米空间
		var clear := true
		for y in range(top + 1, top + 18):
			for o in [Vector3i.ZERO, Vector3i(3, 0, 0), Vector3i(-3, 0, 0), Vector3i(0, 0, 3), Vector3i(0, 0, -3)]:
				if world.vget(Vector3i(bx, y, bz) + o) != Blocks.AIR:
					clear = false
		if not clear:
			continue
		# 木架：2×2 体素粗、6 体素高（1.5 米）
		for y in range(top + 1, top + 7):
			for o in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
				world.vset(Vector3i(bx, y, bz) + o, Blocks.SUPPORT)
		# 圆石：半径 3.5 体素（约 0.9 米）
		var cc := Vector3(bx + 1.0, top + 7.0 + 3.2, bz + 1.0)
		for z in range(-4, 5):
			for y in range(-4, 5):
				for x in range(-4, 5):
					if Vector3(x, y, z).length() <= 3.6:
						world.vset(Vector3i((cc + Vector3(x, y, z)).floor()), Blocks.ROCK)
		return Vector3i(bx, top + 1, bz)
	return Vector3i(-1, -1, -1)
