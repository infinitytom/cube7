extends Node
## 自动测试：godot --headless --path . -- --autotest
## 用调试输入驱动主角走一遍测试关卡，逐项检查机制是否生效。

var fails: Array[String] = []
var main: Node
var P: MorphBall
var W: VoxelWorld
var L: TestRoom

func _ready() -> void:
	main = get_parent()
	P = main.player
	W = main.world
	L = main.level
	P.debug_override = true
	_run()

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func tp(v: Vector3i, vel := Vector3.ZERO, form := -1) -> void:
	P.debug_input = Vector2.ZERO
	P.debug_ability = false
	P.debug_boost = false
	P.form_locked = false
	if form >= 0 and form != P.form:
		P.apply_form(form, false)
	P.respawn_at(W.voxel_top(v + Vector3i.DOWN) + Vector3.UP * 0.5, -1, false)
	await wait(0.05)
	P.linear_velocity = vel

func count_type(a: Vector3i, b: Vector3i, t: int) -> int:
	var n := 0
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				if W.get_block(Vector3i(x, y, z)) == t:
					n += 1
	return n

func _run() -> void:
	print("===== 自动测试开始 =====")
	await wait(1.0)
	print("  出生点位置 ", P.global_position, "  grounded=", P.grounded)
	check(absf(P.global_position.y - 2.48) < 0.12 and P.grounded, "球稳定停在地面（碰撞与法线方向正确）")

	# 1. 滚动
	var x0 := P.global_position.x
	P.debug_input = Vector2(0, -1)
	await wait(1.5)
	var v := Vector3(P.linear_velocity.x, 0, P.linear_velocity.z).length()
	check(P.global_position.x - x0 > 3.0, "滚动推进 %.1f m，速度 %.1f m/s" % [P.global_position.x - x0, v])
	P.debug_input = Vector2.ZERO

	# 2. 撞碎木箱 + 金币自动吸收
	var coins0 := GameState.coins
	await tp(Vector3i(6, 4, 22), Vector3(5.5, 0, 0))
	await wait(1.6)
	check(count_type(Vector3i(10, 4, 22), Vector3i(11, 5, 23), Blocks.CRATE) < 8, "5.5 m/s 撞碎木箱（剩 %d/8）" % count_type(Vector3i(10, 4, 22), Vector3i(11, 5, 23), Blocks.CRATE))
	check(GameState.coins > coins0, "金币自动飞入：%d → %d" % [coins0, GameState.coins])
	check(get_tree().get_nodes_in_group("usable_item").is_empty(), "普通木箱没有留下物件")

	# 3. 普通速度撞不碎玻璃
	var glass0 := count_type(Vector3i(30, 4, 24), Vector3i(31, 11, 39), Blocks.GLASS)
	await tp(Vector3i(26, 4, 32), Vector3(6.0, 0, 0))
	await wait(1.0)
	check(count_type(Vector3i(30, 4, 24), Vector3i(31, 11, 39), Blocks.GLASS) == glass0, "6 m/s 撞玻璃不破")

	# 4. 加速撞穿玻璃
	await tp(Vector3i(20, 4, 32), Vector3(12.0, 0, 0))
	P.debug_input = Vector2(0, -1)
	P.debug_boost = true
	await wait(1.2)
	var glass1 := count_type(Vector3i(30, 4, 24), Vector3i(31, 11, 39), Blocks.GLASS)
	check(glass1 < glass0 and P.global_position.x > 16.3, "12 m/s 撞穿玻璃：碎 %d 块，球到达 x=%.1f" % [glass0 - glass1, P.global_position.x])

	# 5. 砂块失去支撑会塌落
	W.try_break(Vector3i(17, 4, 37), "drill", 1.0)
	await wait(0.4)
	check(W.get_block(Vector3i(17, 4, 37)) == Blocks.SAND and W.get_block(Vector3i(17, 5, 37)) == Blocks.AIR, "砂块塌落")

	# 6. 钻头钻穿岩壁
	await tp(Vector3i(49, 4, 32), Vector3.ZERO, MorphBall.DRILL)
	P.debug_input = Vector2(0, -1)
	P.debug_ability = true
	await wait(4.0)
	check(P.global_position.x > 28.3, "钻头钻穿 2m 岩壁，到达 x=%.1f" % P.global_position.x)
	P.debug_ability = false
	P.debug_input = Vector2.ZERO

	# 7. 物资箱掉落晶块 → 抓取 → 放进插槽 → 能量门打开
	await tp(Vector3i(60, 4, 22), Vector3(6.0, 0, 0), MorphBall.BALL)
	await wait(1.5)
	check(L.crystal != null and is_instance_valid(L.crystal), "撞开物资箱，掉出能量晶块（只掉一块）")
	check(get_tree().get_nodes_in_group("usable_item").size() == 1, "场上可用物件数量 = %d" % get_tree().get_nodes_in_group("usable_item").size())
	if L.crystal and is_instance_valid(L.crystal):
		await tp(W.world_to_voxel(L.crystal.global_position) + Vector3i(-2, 0, 0))
		await wait(0.3)
		P.toggle_grab()
		check(P.is_holding(), "抓起晶块")
		# 抱着晶块滚到缺口前 1.5 米处，向前轻抛
		P.teleport(W.voxel_top(Vector3i(65, 3, 31)) + Vector3.UP * 0.5)
		await wait(0.3)
		check(P.is_holding(), "瞬移时仍抱着晶块")
		P.toggle_grab()
		await wait(2.0)
	check(L.circuit.opened, "回路接通")
	check(count_type(Vector3i(80, 4, 28), Vector3i(81, 9, 35), Blocks.DOOR) == 0, "能量门打开")
	check(W.get_block(Vector3i(78, 3, 31)) == Blocks.RECEIVER_ON, "接收器变为通电状态")

	# 8. 磁铁攀爬金属墙
	await tp(Vector3i(64, 4, 41), Vector3.ZERO, MorphBall.MAGNET)
	P.debug_ability = true
	P.debug_input = Vector2(1, 0)   # 调试输入中 +Z 为右，即推向墙
	await wait(3.0)
	check(P.global_position.y > 5.0, "磁铁吸附爬墙，高度 %.1f m" % P.global_position.y)
	P.debug_ability = false
	P.debug_input = Vector2.ZERO

	# 9. 气泡被上升气流吹起，滚球不会
	await tp(Vector3i(73, 4, 18), Vector3.ZERO, MorphBall.BALL)
	await wait(1.5)
	var ball_y := P.global_position.y
	await tp(Vector3i(73, 4, 18), Vector3.ZERO, MorphBall.BUBBLE)
	await wait(2.5)
	check(ball_y < 3.0 and P.global_position.y > 5.0, "气流：滚球 %.1f m，气泡 %.1f m" % [ball_y, P.global_position.y])

	# 10. 压力板：滚球压不动，立方压得动
	await tp(Vector3i(85, 4, 31), Vector3.ZERO, MorphBall.BALL)
	await wait(1.0)
	check(not L.plate.done, "滚球压不动压力板")
	await tp(Vector3i(85, 4, 31), Vector3.ZERO, MorphBall.CUBE)
	await wait(1.0)
	check(L.plate.done and count_type(Vector3i(90, 4, 28), Vector3i(91, 9, 35), Blocks.GATE) == 0, "立方压下压力板，闸门打开")

	# 11. 平衡轨道：变形站锁定形态、球能停在轨道上
	await tp(Vector3i(94, 4, 31), Vector3.ZERO, MorphBall.CUBE)
	await wait(0.8)
	check(P.form == MorphBall.BALL and P.form_locked, "变形站切换为滚球并锁定形态")
	await tp(Vector3i(97, 4, 31))
	await wait(1.5)
	check(P.global_position.y > 1.8, "球停在轨道上 y=%.2f" % P.global_position.y)

	# 12. 掉出世界 → 回到检查点
	P.debug_input = Vector2(1, 0)
	await wait(1.0)
	P.debug_input = Vector2.ZERO
	await wait(3.0)
	check(P.global_position.y > 1.5 and P.global_position.x > 45.0, "掉落后回到轨道检查点 (%.1f, %.1f, %.1f)" % [P.global_position.x, P.global_position.y, P.global_position.z])

	print("===== 金币 %d · 能源 %d · 护盾 %d · 破坏方块 %d =====" % [GameState.coins, GameState.energy, GameState.shield, GameState.blocks_broken])
	if fails.is_empty():
		print("===== 自动测试全部通过 =====")
	else:
		print("===== 失败 %d 项：%s =====" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)
