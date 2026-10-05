extends Node
## 区域 1 整关测试：godot --headless --path . -- --autotest=greenhouse
## 沿设计路线走一遍，确认每个谜题都能通过、不能被跳过。

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaGreenhouse
const G := AreaGreenhouse.G

func _ready() -> void:
	var main := get_parent()
	P = main.player
	W = main.world
	L = main.level
	P.debug_override = true
	# 路线测试不管敌人（战斗在测试房间里单独测）；先确认两只都放出来了
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

## 调试输入里：前 = +X，右 = +Z
func go(dir: Vector2, secs: float, ability := false, boost := false) -> void:
	P.debug_input = dir
	P.debug_ability = ability
	P.debug_boost = boost
	await wait(secs)
	P.debug_input = Vector2.ZERO
	P.debug_ability = false
	P.debug_boost = false

func tp(v: Vector3i, vel := Vector3.ZERO) -> void:
	P.debug_input = Vector2.ZERO
	P.teleport(W.voxel_top(v + Vector3i.DOWN) + Vector3.UP * 0.5)
	await wait(0.1)
	P.linear_velocity = vel

func vx(p: Vector3) -> Vector3i:
	return W.world_to_voxel(p)

func count(a: Vector3i, b: Vector3i, t: int) -> int:
	var n := 0
	for c in L.cells(a, b):
		if W.get_block(c) == t:
			n += 1
	return n

func _run() -> void:
	print("===== 区域 1 整关测试 =====")
	await wait(1.0)
	check(P.grounded, "出生点：球停在坑底")
	check(GameState.unlocked_forms == [true, false, false], "开局只有滚球形态")
	check(enemy_count >= 7, "关卡里放了 %d 个敌人" % enemy_count)
	check(L.seeds.size() == 4, "关卡里放了 %d 个种子方块" % L.seeds.size())
	for id in L.seeds:
		print("    种子方块 ", id, " 位于体素 ", W.world_to_voxel(L.seeds[id].global_position))
	# 冲撞打开第一个种子方块，救出噗噗
	var sc: Node3D = L.seeds["gh_s1"]
	var sv := W.world_to_voxel(sc.global_position)
	await tp(sv + Vector3i(-4, 0, 0))
	P.debug_input = Vector2(0, -1)
	await wait(0.2)
	P.debug_ability_pressed = true
	await wait(1.0)
	P.debug_input = Vector2.ZERO
	check(GameState.seeds == 1, "冲撞打开种子方块，救出噗噗（%d）" % GameState.seeds)
	P.request_form(MorphBall.DRILL)
	check(P.form == MorphBall.BALL, "未解锁的钻头无法切换")

	# 1. 冲出坑口撞开木箱栅栏
	var crates0 := count(Vector3i(27, G, 71), Vector3i(27, G + 1, 76), Blocks.CRATE)
	await tp(Vector3i(17, G - 2, 74))
	await go(Vector2(0, -1), 3.0)
	var crates1 := count(Vector3i(27, G, 71), Vector3i(27, G + 1, 76), Blocks.CRATE)
	check(crates1 < crates0 and vx(P.global_position).x >= 27, "滚上坡道撞开坑口木箱（%d→%d），到达 x=%d" % [crates0, crates1, vx(P.global_position).x])

	# 2. 深沟：直接冲过去会掉下去
	await tp(Vector3i(46, G, 76), Vector3(12, 0, 0))
	await go(Vector2(0, -1), 1.5, false, true)
	var pv := vx(P.global_position)
	check(pv.x < 62 or pv.y < G, "5 米深沟无法靠全速冲过（x=%d, y=%d）" % [pv.x, pv.y])
	# 2b. 加速助跑再起跳也跨不过去（跳跃不能绕过这个谜题）
	await tp(Vector3i(38, G, 76), Vector3(11, 0, 0))
	P.debug_boost = true
	P.debug_input = Vector2(0, -1)
	for k in 240:
		await get_tree().physics_frame
		if vx(P.global_position).x >= 51:
			break
	P.debug_jump_held = true
	P.debug_jump_pressed = true
	var crossed := false
	var far := 0
	for k in 100:
		await get_tree().physics_frame
		var q := vx(P.global_position)
		far = maxi(far, q.x)
		if q.x >= 62 and q.y >= G:
			crossed = true
	P.debug_jump_held = false
	P.debug_boost = false
	P.debug_input = Vector2.ZERO
	check(not crossed, "加速起跳也跨不过深沟（最远 x=%d）" % far)
	await go(Vector2(0, 1), 0.2)
	# 从逃生坡道回西侧
	await tp(Vector3i(61, G - 3, 79))
	await go(Vector2(0, 1), 2.2)
	check(vx(P.global_position).x <= 52 and vx(P.global_position).y >= G - 1, "掉进沟里能从逃生坡道回到西侧（x=%d）" % vx(P.global_position).x)

	# 3. 撞塌砂塔底座 → 砂子填沟
	await tp(Vector3i(46, G, 71), Vector3(6, 0, 0))
	if OS.has_environment("CUBE7_DBG"):
		for k in 10:
			await wait(0.1)
			print("   sandtower P=", vx(P.global_position), " ", P.global_position, " v=", P.linear_velocity, " post=", W.get_block(Vector3i(51, G, 70)))
	await go(Vector2(0, -1), 1.0)
	await wait(8.0)
	var sand := count(Vector3i(52, G - 4, 55), Vector3i(61, G - 1, 86), Blocks.SAND)
	check(sand > 120, "砂塔坍塌，%d 块砂流进深沟" % sand)
	var best_row := -1
	for z in range(62, 84):
		var ok := true
		for x in range(52, 62):
			if W.get_block(Vector3i(x, G - 2, z)) == Blocks.AIR:
				ok = false
		if ok:
			best_row = z
			break
	check(best_row >= 0, "深沟被填到离地面 1 米以内（第一条可通行的行 z=%d）" % best_row)
	if best_row >= 0:
		# 从砂塔原来的位置（水管在这里断开）滚过去；像玩家一样边滚边修正方向
		var row := clampi(best_row, 63, 69)
		await tp(Vector3i(46, G, row), Vector3(4, 0, 0))
		var zc := (float(row) + 0.5) * VoxelWorld.CELL_M
		P.debug_boost = true
		for k in 240:
			await get_tree().physics_frame
			var dz := zc - P.global_position.z
			P.debug_input = Vector2(clampf(dz * 2.0, -1.0, 1.0), -1.0)
			# 卡在砂堆的小坎上就跳一下（玩家也会这么做）
			P.debug_jump_held = true
			if k > 20 and k % 25 == 0 and Vector2(P.linear_velocity.x, P.linear_velocity.z).length() < 2.0:
				P.debug_jump_pressed = true
			if vx(P.global_position).x >= 63:
				break
		P.debug_jump_held = false
		P.debug_boost = false
		P.debug_input = Vector2.ZERO
		# 砂子没填满时对岸会有一级小台阶——跳一下就上去了
		if vx(P.global_position).x < 62:
			P.debug_input = Vector2(0, -1)
			P.debug_jump_held = true
			P.debug_jump_pressed = true
			await wait(1.2)
			P.debug_jump_held = false
			P.debug_input = Vector2.ZERO
		if vx(P.global_position).x < 62:
			var zz := vx(P.global_position).z
			var cols := []
			for xx in range(56, 66):
				var top := -1
				for yy in range(G + 12, G - 6, -1):
					if W.get_block(Vector3i(xx, yy, zz)) != Blocks.AIR:
						top = yy
						break
				cols.append("%d:%d(%d)" % [xx, top, W.get_block(Vector3i(xx, top, zz))])
			print("    调试：球 ", vx(P.global_position), " 列顶 ", cols)
		check(vx(P.global_position).x >= 62, "从填平处滚过深沟（x=%d）" % vx(P.global_position).x)

	# 4. 坡道登上温室高台
	await tp(Vector3i(64, G, 71))
	await go(Vector2(-1, 0), 5.0)
	check(vx(P.global_position).y >= G + 6 and vx(P.global_position).z <= 58, "沿坡道登上高台（y=%d, z=%d）" % [vx(P.global_position).y, vx(P.global_position).z])

	# 5. 普通速度撞不开温室玻璃，冲刺可以
	var glass0 := count(Vector3i(58, G + 6, 44), Vector3i(70, G + 10, 48), Blocks.GLASS)
	await tp(Vector3i(64, G + 6, 53), Vector3(0, 0, -6))
	await wait(1.5)
	check(count(Vector3i(58, G + 6, 44), Vector3i(70, G + 10, 48), Blocks.GLASS) == glass0, "6 m/s 撞不开温室玻璃")
	await tp(Vector3i(64, G + 6, 56), Vector3(0, 0, -12))
	await go(Vector2(-1, 0), 1.2, false, true)
	check(vx(P.global_position).z < 47, "加速撞穿温室玻璃，进入温室（z=%d）" % vx(P.global_position).z)

	# 6. 钻头核心
	await tp(AreaGreenhouse.DOME_C + Vector3i(0, 0, 3))
	await go(Vector2(-1, 0), 1.5)
	await wait(1.0)
	check(GameState.unlocked_forms[MorphBall.DRILL] and P.form == MorphBall.DRILL, "拾取钻头核心：解锁并自动变身")

	# 7. 滚球撞不开泥土墙，钻头可以
	P.apply_form(MorphBall.BALL, false)
	await tp(Vector3i(72, G + 6, 52), Vector3(10, 0, 0))
	await wait(1.5)
	check(vx(P.global_position).x < 76, "滚球撞不开泥土墙（x=%d）" % vx(P.global_position).x)
	# 普通地面钻不下去
	P.apply_form(MorphBall.DRILL, false)
	await tp(Vector3i(56, G + 6, 52))
	await go(Vector2.ZERO, 1.5, true)
	check(vx(P.global_position).y >= G + 6, "普通地面上往下钻不会把自己困住（y=%d）" % vx(P.global_position).y)
	P.apply_form(MorphBall.DRILL, false)
	await tp(Vector3i(73, G + 6, 52))
	await go(Vector2(0, -1), 6.0, true)
	if vx(P.global_position).x < 79:
		var row := []
		for xx in range(73, 80):
			row.append("%d:%d/%d" % [xx, W.get_block(Vector3i(xx, G + 6, 52)), W.get_block(Vector3i(xx, G + 7, 52))])
		print("    调试：球 ", P.global_position, " 形态 ", P.form, " 着地 ", P.grounded, " 行 ", row)
	check(vx(P.global_position).x >= 79, "钻穿泥土墙（x=%d）" % vx(P.global_position).x)

	# 8. 松土：向下钻掉进洞穴，从悬崖侧面出来
	await tp(Vector3i(91, G + 6, 51))
	await go(Vector2.ZERO, 2.5, true)
	await wait(1.0)
	check(vx(P.global_position).y <= G + 3, "向下钻穿松土，掉进洞穴（y=%d）" % vx(P.global_position).y)
	await go(Vector2(-1, 0), 5.0)
	if vx(P.global_position).z > 42:
		var pv2 := W.to_v(P.global_position)
		var prof := []
		for vz in range(pv2.z - 12, pv2.z + 4):
			var top := -1
			for vy in range((G + 5) * 2, (G - 1) * 2, -1):
				if W.vget(Vector3i(pv2.x, vy, vz)) != Blocks.AIR and W.vget(Vector3i(pv2.x, vy + 1, vz)) == Blocks.AIR and vy < (G + 4) * 2:
					top = vy
					break
			prof.append("%d:%d" % [vz, top])
		print("    调试：洞里 球体素 ", pv2, " 速度 ", P.linear_velocity, " 地面 ", prof)
	check(vx(P.global_position).z <= 42 and vx(P.global_position).y == G + 2, "穿过洞穴到达中枢塔台地（z=%d, y=%d）" % [vx(P.global_position).z, vx(P.global_position).y])

	# 9. 钻开晶洞取出能量晶块
	await tp(Vector3i(99, G + 2, 21))
	await go(Vector2(0, 1), 6.0, true)
	await wait(1.0)
	check(is_instance_valid(L.crystal), "钻开晶洞，掉出能量晶块")

	# 10. 放进塔基插槽 → 光桥展开
	if is_instance_valid(L.crystal):
		L.crystal.global_position = W.voxel_center(AreaGreenhouse.SOCKET) + Vector3(0.6, 1.2, 0.4)
		L.crystal.linear_velocity = Vector3.ZERO
	await wait(4.0)
	check(L.socket.done, "晶块被插槽吸入")
	check(W.get_block(Vector3i(104, G + 9, 72)) == Blocks.CRYSTAL, "光桥展开")

	# 11. 沿光桥滚上终点浮岛
	P.apply_form(MorphBall.BALL, false)
	await tp(Vector3i(104, G + 2, 45))
	await go(Vector2(1, 0), 7.0, false, true)
	await wait(1.0)
	check(GameState.level_complete, "沿光桥到达终点浮岛，关卡完成（最后位置 y=%d, z=%d）" % [vx(P.global_position).y, vx(P.global_position).z])

	# 12. 掉进云海 → 回检查点
	await tp(Vector3i(30, 10, 30))
	await wait(3.0)
	check(P.global_position.y > 8.0, "掉进云海后回到检查点（y=%.1f）" % P.global_position.y)

	print("===== 金币 %d · 碎片 %d/%d · 破坏方块 %d =====" % [GameState.coins, GameState.fragments, GameState.fragments_total, GameState.blocks_broken])
	if fails.is_empty():
		print("===== 区域 1 整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
