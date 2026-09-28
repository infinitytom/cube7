extends Node
## 第三章整关测试：godot --headless --path . -- --autotest=abyss

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaAbyss

func _ready() -> void:
	var main := get_parent()
	P = main.player
	W = main.world
	L = main.level
	P.debug_override = true
	enemy_count = L.enemies.size()
	for e in L.enemies:
		if is_instance_valid(e):
			e.queue_free()
	_run()

var enemy_count := 0

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func tp(v: Vector3i, vel := Vector3.ZERO) -> void:
	P.debug_input = Vector2.ZERO
	P.teleport(W.voxel_top(v + Vector3i.DOWN) + Vector3.UP * 0.5)
	await wait(0.15)
	P.linear_velocity = vel

func count(a: Vector3i, b: Vector3i, t: int) -> int:
	var n := 0
	for c in L.cells(a, b):
		if W.get_block(c) == t:
			n += 1
	return n

func _run() -> void:
	await wait(1.0)
	print("===== 第三章 整关测试 =====")
	check(enemy_count >= 10, "关卡里放了 %d 个敌人（另有 Boss）" % enemy_count)
	check(L.seeds.size() == 4 and L.fragments.size() == 3, "4 个种子方块、3 块记忆碎片")
	check(P.grounded, "出生点：站在坑沿地面上")
	# 1. 撞碎共鸣晶簇（连锁）
	var e := L._spiral_cell(214.0, 20.5)
	var g0 := count(Vector3i(e.x - 4, AreaAbyss.TOP, e.z - 4), Vector3i(e.x + 4, AreaAbyss.TOP + 3, e.z + 4), Blocks.GEM_CHAIN)
	var hit := W.try_break(Vector3i(e.x, AreaAbyss.TOP, e.z), "impact", 6.0)
	await wait(2.5)
	var g1 := count(Vector3i(e.x - 4, AreaAbyss.TOP, e.z - 4), Vector3i(e.x + 4, AreaAbyss.TOP + 3, e.z + 4), Blocks.GEM_CHAIN)
	check(hit and g1 < g0 / 3, "撞一下共鸣晶簇，整团连锁碎掉（%d → %d）" % [g0, g1])
	# 2. 螺旋栈道：每一级台阶都不超过一格，一路通到第一层
	var bad := 0
	var prev := -1
	for k in 151:
		var a := AreaAbyss.SPIRAL_A0 - k
		var c := L._spiral_cell(a, 19.0)
		var top := -1
		for y in range(AreaAbyss.TOP + 2, AreaAbyss.L1 - 4, -1):
			if W.get_block(Vector3i(c.x, y, c.z)) != Blocks.AIR:
				top = y + 1
				break
		if prev >= 0 and (top > prev + 1 or top < prev - 3):
			bad += 1
		if top > 0:
			prev = top
	check(bad <= 4 and prev <= AreaAbyss.L1 + 1, "螺旋栈道一级一级往下，到达第一层（异常台阶 %d，终点 y=%d）" % [bad, prev])
	# 3. 碎裂石板：踩上去会塌，过一会儿长回来
	var cr := L._spiral_cell(174.0, 19.0)
	var cr_cell := Vector3i(-1, -1, -1)
	for y in range(AreaAbyss.TOP, AreaAbyss.L1, -1):
		if W.get_block(Vector3i(cr.x, y, cr.z)) == Blocks.CRUMBLE:
			cr_cell = Vector3i(cr.x, y, cr.z)
			break
	check(cr_cell.x >= 0, "栈道上有碎裂石板")
	if cr_cell.x >= 0:
		await tp(cr_cell + Vector3i.UP)
		await wait(1.2)
		check(W.get_block(cr_cell) == Blocks.AIR, "站上碎裂石板，它塌了下去")
		await tp(Vector3i(44, AreaAbyss.L1, 66))
		await wait(8.5)
		check(W.get_block(cr_cell) == Blocks.CRUMBLE, "PIX 走开以后，碎裂石板长了回来")
	# 4. 光束谜题：撞镜子会转；转到正确角度后受光晶亮起，晶洞门打开
	var mirrors := get_tree().get_nodes_in_group("beam_mirror")
	var m1: BeamMirror = null
	var m2: BeamMirror = null
	for m in mirrors:
		var mc := W.world_to_voxel((m as Node3D).global_position + Vector3.UP * 0.1)
		if mc.x == 47 and mc.z == 54:
			m1 = m
		elif mc.x == 81 and mc.z == 54:
			m2 = m
	check(m1 != null and m2 != null, "第一层有两面关键晶面镜")
	check(W.get_block(Vector3i(AreaAbyss.CAVE_DOOR_X, AreaAbyss.L2, 62)) == Blocks.DOOR, "晶洞门一开始关着")
	if m1 and m2:
		var f0 := m1.facing
		await tp(Vector3i(47, AreaAbyss.L1, 58))
		P.debug_input = Vector2(-1, 0)
		await wait(0.2)
		P.debug_ability_pressed = true
		await wait(0.8)
		P.debug_input = Vector2.ZERO
		check(m1.facing != f0, "冲撞晶面镜，它转了 45°（%d → %d）" % [f0, m1.facing])
		while m1.facing != 5:
			m1.turn(1)
		while m2.facing != 3:
			m2.turn(1)
		await tp(Vector3i(56, AreaAbyss.L1, 76))
		await wait(1.5)
		check(L.p1_beam.lenses.size() > 0, "光经过两面镜子照到受光晶")
		check(W.get_block(Vector3i(AreaAbyss.CAVE_DOOR_X, AreaAbyss.L2, 62)) == Blocks.AIR, "电顺着管线流下去，晶洞门打开")
	# 5. 升降台在两层之间往返
	var lifts := L.find_children("*", "Lift", false, false)
	var ys: Array[float] = []
	for k in 12:
		await wait(0.5)
		if not lifts.is_empty():
			ys.append((lifts[0] as Node3D).global_position.y)
	check(not ys.is_empty() and ys.max() - ys.min() > 4.0, "升降台在第一层和第二层之间往返（行程 %.1f m）" % ((ys.max() - ys.min()) if not ys.is_empty() else 0.0))
	# 6. 晶洞：共鸣晶簇墙、碎裂石板桥、松土竖井 → 底层隧道
	var w0 := count(Vector3i(97, AreaAbyss.L2, 47), Vector3i(98, AreaAbyss.L2 + 7, 81), Blocks.GEM_CHAIN)
	await tp(Vector3i(93, AreaAbyss.L2, 64), Vector3(8, 0, 0))
	P.debug_input = Vector2(0, -1)
	await wait(1.0)
	P.debug_input = Vector2.ZERO
	await wait(5.0)
	var w1 := count(Vector3i(97, AreaAbyss.L2, 47), Vector3i(98, AreaAbyss.L2 + 7, 81), Blocks.GEM_CHAIN)
	check(w1 < w0 / 2, "撞碎晶洞里的共鸣晶簇墙（%d → %d）" % [w0, w1])
	P.apply_form(MorphBall.DRILL, false)
	await tp(Vector3i(108, AreaAbyss.L2, 71))
	P.debug_ability = true
	await wait(2.5)
	P.debug_ability = false
	await wait(1.5)
	var pv := W.world_to_voxel(P.global_position)
	check(pv.y <= AreaAbyss.FLOOR + 2, "在松土上往下钻，掉进最底层的隧道（y=%d）" % pv.y)
	P.apply_form(MorphBall.BALL, false)
	await tp(Vector3i(106, AreaAbyss.FLOOR, 64))
	P.debug_input = Vector2(0, 1)
	P.debug_boost = true
	for k in 90:
		await wait(0.1)
		if W.world_to_voxel(P.global_position).x < 84:
			break
	P.debug_input = Vector2.ZERO
	P.debug_boost = false
	check(W.world_to_voxel(P.global_position).x < 86, "沿底层隧道滚到坑底（x=%d）" % W.world_to_voxel(P.global_position).x)
	# 7. Boss：光照碎晶甲 → 撞核心，三轮
	await tp(Vector3i(80, AreaAbyss.FLOOR, 64))
	await wait(0.8)
	check(is_instance_valid(L.boss) and L.boss.active, "进入坑底，晶簇巨像开始战斗")
	var hits := 0
	for round in 3:
		if not is_instance_valid(L.boss):
			break
		var s: Array = AreaAbyss.BOSS_SETUPS[round]
		var km: BeamMirror = L.boss_mirrors[round]
		check(L.boss_beams[round].active, "第 %d 轮：对应的发射晶亮了" % (round + 1))
		while km.facing != int(s[3]):
			km.turn(1)
		# 把巨像放到光路上（场地中心）
		L.boss.ai = false
		L.boss.global_position = W.voxel_top(Vector3i(AreaAbyss.C.x, AreaAbyss.FLOOR - 1, AreaAbyss.C.y))
		P.teleport(W.voxel_top(Vector3i(70, AreaAbyss.FLOOR - 1, 76)) + Vector3.UP * 0.5)
		var knelt := false
		for k in 60:
			await wait(0.1)
			if L.boss.state == CrystalColossus.St.KNEEL:
				knelt = true
				break
		check(knelt, "第 %d 轮：光照到巨像，晶甲碎掉，它跪下了" % (round + 1))
		var bp := L.boss.global_position
		P.teleport(bp + Vector3(0, 0.6, -3.0))
		await wait(0.2)
		P.linear_velocity = Vector3(0, 0, 8.0)
		var hp0: int = L.boss.hp
		for k in 40:
			await get_tree().physics_frame
			if not is_instance_valid(L.boss) or L.boss.hp < hp0:
				hits += 1
				break
		await wait(1.5)
	check(not is_instance_valid(L.boss) and L.boss_done, "三轮之后打倒晶簇巨像（命中 %d）" % hits)
	# 8. 塔升起来，走到塔下完成章节
	await wait(6.5)
	check(W.get_block(Vector3i(AreaAbyss.C.x, AreaAbyss.FLOOR + 20, AreaAbyss.C.y)) != Blocks.AIR, "坑底中央的重构塔升了起来")
	await tp(Vector3i(AreaAbyss.C.x + 6, AreaAbyss.FLOOR, AreaAbyss.C.y))
	P.debug_input = Vector2(0, 1)
	await wait(0.8)
	P.debug_input = Vector2.ZERO
	await wait(1.0)
	check(GameState.level_complete, "到达第三座重构塔，章节完成")
	print("===== 金币 %d · 碎片 %d/3 · 噗噗 %d/%d =====" % [GameState.coins, GameState.fragments, GameState.seeds, GameState.seeds_total])
	if fails.is_empty():
		print("===== 第三章整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()
