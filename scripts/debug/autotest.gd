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
	# 记下地面层（y=3 格）的原样：战斗测试前把被砸出的坑补平——平滑地形上，球会顺着坑壁滚下去，干扰 AI 测试
	for x in range(1, 91):
		for z in range(16, 48):
			_floor[Vector3i(x, 3, z)] = W.get_block(Vector3i(x, 3, z))
	# 关卡里的锈块兽会干扰前面的路线测试，先移走；战斗测试时再单独放
	if L.scrap and is_instance_valid(L.scrap):
		L.scrap.queue_free()
	_run()

var _floor := {}

func _restore_floor() -> void:
	for c: Vector3i in _floor:
		W.set_block(c, _floor[c])
	W.flush_dirty()
	await wait(0.1)

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
	await tp(Vector3i(8, 4, 22), Vector3(5.5, 0, 0))
	await wait(1.6)
	check(count_type(Vector3i(12, 4, 22), Vector3i(13, 5, 23), Blocks.CRATE) < 8, "5.5 m/s 撞碎木箱（剩 %d/8）" % count_type(Vector3i(12, 4, 22), Vector3i(13, 5, 23), Blocks.CRATE))
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
	var left := 0
	for d in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]:
		if W.vget(Vector3i(17, 5, 37) * VoxelWorld.CELL + d) == Blocks.SAND:
			left += 1
	check(W.get_block(Vector3i(17, 4, 37)) == Blocks.SAND and left < 8, "砂块塌落（上方一格剩 %d/8）" % left)

	# 6. 钻头钻穿岩壁
	await tp(Vector3i(49, 4, 32), Vector3.ZERO, MorphBall.DRILL)
	P.debug_input = Vector2(0, -1)
	P.debug_ability = true
	for _k in 10:
		await wait(0.5)
		if OS.has_environment("CUBE7_DRILL_DEBUG"):
			print("   drill pos=%s vel=%s drilling=%.2f" % [P.global_position, P.linear_velocity, P._drilling_t])
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
		# 用真实的按键事件（键盘 E）来抓，确保输入链路没有被别的节点吞掉
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		ev.keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
		await get_tree().process_frame
		check(P.is_holding(), "按 E 键抓起晶块（真实输入事件）")
		# 抱着晶块滚到缺口前 1.5 米处，向前轻抛
		P.teleport(W.voxel_top(Vector3i(65, 3, 31)) + Vector3.UP * 0.5)
		await wait(0.3)
		check(P.is_holding(), "瞬移时仍抱着晶块")
		P.toggle_grab()
		await wait(2.0)
	check(L.circuit.opened, "回路接通")
	check(count_type(Vector3i(80, 4, 28), Vector3i(81, 9, 35), Blocks.DOOR) == 0, "能量门打开")
	check(W.get_block(Vector3i(78, 3, 31)) == Blocks.RECEIVER_ON, "接收器变为通电状态")

	# 8. 三种形态跳跃高度不同；气泡能用空中再跳登上 3 米高台，滚球不行
	var heights: Array = []
	for fi in [MorphBall.BALL, MorphBall.DRILL, MorphBall.BUBBLE]:
		await tp(Vector3i(71, 4, 40), Vector3.ZERO, fi)
		await wait(0.5)
		var y0 := P.global_position.y
		var top := y0
		P.debug_jump_held = true
		P.debug_jump_pressed = true
		for k in 90:
			await get_tree().physics_frame
			top = maxf(top, P.global_position.y)
		P.debug_jump_held = false
		heights.append(top - y0)
		await wait(1.5)
	check(heights[2] > heights[0] and heights[0] > heights[1] and heights[1] > 0.3, "跳跃高度：滚球 %.2f m，钻头 %.2f m，气泡 %.2f m" % heights)
	await tp(Vector3i(64, 4, 41), Vector3.ZERO, MorphBall.BALL)
	P.debug_input = Vector2(1, 0)
	P.debug_jump_held = true
	P.debug_jump_pressed = true
	await wait(2.0)
	check(P.global_position.y < 3.5, "滚球跳不上 3 米高台（y=%.1f）" % P.global_position.y)
	await tp(Vector3i(64, 4, 41), Vector3.ZERO, MorphBall.BUBBLE)
	P.debug_input = Vector2(1, 0)
	P.debug_jump_held = true
	P.debug_jump_pressed = true
	await wait(0.55)
	P.debug_jump_pressed = true
	await wait(0.5)
	P.debug_jump_pressed = true
	await wait(2.5)
	check(P.global_position.y > 5.2, "气泡空中再跳登上高台（y=%.1f）" % P.global_position.y)
	P.debug_jump_held = false
	P.debug_input = Vector2.ZERO

	# 9. 气泡被上升气流吹起，滚球不会
	await tp(Vector3i(73, 4, 18), Vector3.ZERO, MorphBall.BALL)
	await wait(1.5)
	var ball_y := P.global_position.y
	await tp(Vector3i(73, 4, 18), Vector3.ZERO, MorphBall.BUBBLE)
	await wait(2.5)
	check(ball_y < 3.0 and P.global_position.y > 5.0, "气流：滚球 %.1f m，气泡 %.1f m" % [ball_y, P.global_position.y])

	# 10. 压力板：滚球压不动，钻头压得动
	await tp(Vector3i(85, 4, 31), Vector3.ZERO, MorphBall.BALL)
	await wait(1.0)
	check(not L.plate.done, "滚球压不动压力板")
	await tp(Vector3i(85, 4, 31), Vector3.ZERO, MorphBall.DRILL)
	await wait(1.0)
	check(L.plate.done and count_type(Vector3i(90, 4, 28), Vector3i(91, 9, 35), Blocks.GATE) == 0, "钻头压下压力板，闸门打开")

	# 11. 平衡轨道：变形站锁定形态、球能停在轨道上
	await tp(Vector3i(94, 4, 31), Vector3.ZERO, MorphBall.DRILL)
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

	await _enemy_tests()
	await _combat2_tests()
	await _chunk_test()
	await _systems_test()

	print("===== 金币 %d · 能源 %d · 护盾 %d · 破坏方块 %d =====" % [GameState.coins, GameState.energy, GameState.shield, GameState.blocks_broken])
	if fails.is_empty():
		print("===== 自动测试全部通过 =====")
	else:
		print("===== 失败 %d 项：%s =====" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)


# ================================================================ 战斗

func _enemy(cell: Vector3i, yaw: float, ai := false) -> Scrapling:
	var e := Scrapling.new()
	e.ai = ai
	L.add_child(e)
	e.global_position = W.voxel_top(cell) + Vector3.UP * 0.05
	e.rotation.y = yaw
	await wait(0.3)
	return e

func _enemy_tests() -> void:
	print("  —— 战斗 ——")
	# a. 正面冲撞被盾弹开（敌人面朝 -X，玩家从 -X 方向冲过来）
	var e := await _enemy(Vector3i(44, 3, 26), PI / 2.0)
	await tp(Vector3i(39, 4, 26), Vector3.ZERO, MorphBall.BALL)
	P.debug_input = Vector2(0, -1)
	await wait(0.1)
	P.debug_ability_pressed = true
	await wait(0.25)
	P.debug_input = Vector2.ZERO
	await wait(1.0)
	check(is_instance_valid(e) and P.global_position.x < e.global_position.x, "滚球正面冲撞被盾牌弹开")
	# b. 从侧面冲撞击破
	var c0 := GameState.coins
	await tp(Vector3i(44, 4, 20), Vector3.ZERO, MorphBall.BALL)
	P.debug_input = Vector2(1, 0)
	await wait(0.1)
	P.debug_ability_pressed = true
	await wait(1.2)
	P.debug_input = Vector2.ZERO
	await wait(1.0)
	check(not is_instance_valid(e) and GameState.coins > c0, "从侧面冲撞击破锈块兽，掉出金币（+%d）" % (GameState.coins - c0))
	# c. 钻头空中下砸把它震翻，滚球轻碰即碎
	e = await _enemy(Vector3i(44, 3, 26), PI / 2.0)
	P.apply_form(MorphBall.DRILL, false)
	P.teleport(W.voxel_center(Vector3i(48, 9, 26)))
	await wait(0.15)
	P.debug_ability_pressed = true
	await wait(1.0)
	check(is_instance_valid(e) and e.state == Scrapling.St.FLIPPED, "钻头下砸把附近的锈块兽震翻")
	P.apply_form(MorphBall.BALL, false)
	P.debug_input = Vector2(0, 1)
	await wait(1.5)
	P.debug_input = Vector2.ZERO
	check(not is_instance_valid(e), "翻倒后滚球碰一下就击破")
	# d. 气泡气浪把它推开、掀翻（先把还在滚的球挪开，别一出生就被撞碎）
	await tp(Vector3i(36, 4, 26), Vector3.ZERO, MorphBall.BUBBLE)
	e = await _enemy(Vector3i(44, 3, 26), PI / 2.0)
	await tp(Vector3i(40, 4, 26), Vector3.ZERO, MorphBall.BUBBLE)
	await wait(0.3)
	var ex := e.global_position.x
	P.debug_ability_pressed = true
	await wait(0.8)
	check(is_instance_valid(e) and e.state == Scrapling.St.FLIPPED and e.global_position.x - ex > 1.0, "气浪把锈块兽推开 %.1f m 并掀翻" % (e.global_position.x - ex))
	e.queue_free()
	# e. 发现 → 蓄力 → 冲锋撞到 PIX，扣一格护盾
	await _restore_floor()
	e = await _enemy(Vector3i(46, 3, 26), PI / 2.0, true)
	await tp(Vector3i(40, 4, 26), Vector3.ZERO, MorphBall.BALL)
	var sh := GameState.shield
	var hit := false
	for k in 40:
		await wait(0.1)
		if GameState.shield < sh or P.is_invulnerable():
			hit = true
			break
	check(hit, "锈块兽发现 PIX 后蓄力冲锋，撞到扣护盾")
	if is_instance_valid(e):
		e.queue_free()


func _spawn(e: Node3D, cell: Vector3i, ai := false) -> Node3D:
	e.set("ai", ai)
	L.add_child(e)
	e.global_position = W.voxel_top(cell) + Vector3.UP * 0.05
	await wait(0.3)
	return e

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	for b in get_tree().get_nodes_in_group("projectile"):
		b.queue_free()
	await wait(0.1)

## 新的攻击手段和新敌人
func _combat2_tests() -> void:
	print("  —— 新战斗 ——")
	GameState.shield = GameState.max_shield
	# a. 踩踏：从上面落到锈块兽头上 → 踩翻 + 弹起
	var e := await _enemy(Vector3i(44, 3, 26), PI / 2.0)
	P.apply_form(MorphBall.BALL, false)
	P.teleport(e.global_position + Vector3(0, 2.2, 0))
	var bounced := false
	for k in 60:
		await get_tree().physics_frame
		if is_instance_valid(e) and e.state == Scrapling.St.FLIPPED and P.linear_velocity.y > 2.0:
			bounced = true
			break
	check(bounced, "踩踏：落在锈块兽头上把它踩翻并弹起")
	if is_instance_valid(e):
		e.queue_free()
	# b. 滚球原地蓄力冲刺：满蓄力正面撞碎盾牌
	e = await _enemy(Vector3i(46, 3, 26), PI / 2.0)
	await tp(Vector3i(40, 4, 26), Vector3.ZERO, MorphBall.BALL)
	await wait(0.3)
	P.debug_input = Vector2(0, -0.2)
	await wait(0.05)
	P.debug_ability = true
	P.debug_ability_pressed = true
	await wait(1.1)
	P.debug_input = Vector2.ZERO
	var charged := P._charging
	P.debug_ability = false
	await wait(1.2)
	check(charged and not is_instance_valid(e), "原地蓄力冲刺：满蓄力正面撞碎锈块兽的盾牌")
	await _clear_enemies()
	# c. 锈蜂：发现 PIX → 俯冲；气浪把它打落，落地后撞碎
	var fly := await _spawn(Rustfly.new(), Vector3i(46, 7, 26), false) as Rustfly
	await tp(Vector3i(44, 4, 26), Vector3.ZERO, MorphBall.BUBBLE)
	await wait(0.2)
	P.debug_ability_pressed = true
	await wait(0.6)
	check(is_instance_valid(fly) and fly.stun_t > 0.0, "气浪把锈蜂打落（晕眩 %.1f 秒）" % (fly.stun_t if is_instance_valid(fly) else -1.0))
	P.apply_form(MorphBall.BALL, false)
	if is_instance_valid(fly):
		await tp(W.world_to_voxel(fly.global_position) + Vector3i(-3, 0, 0), Vector3(6, 0, 0), MorphBall.BALL)
		P.debug_input = Vector2(0, -1)
		await wait(1.0)
		P.debug_input = Vector2.ZERO
	check(not is_instance_valid(fly), "晕在地上的锈蜂被滚球撞碎")
	await _clear_enemies()
	# c2. 锈蜂 AI：俯冲后扎在地上
	await _restore_floor()
	fly = await _spawn(Rustfly.new(), Vector3i(48, 7, 26), true) as Rustfly
	await tp(Vector3i(44, 4, 26), Vector3.ZERO, MorphBall.BALL)
	var stuck := false
	# 每个物理帧都看一眼：扎地后 PIX 被撞回来时可能顺手把它撞碎，状态只维持很短
	for k in 360:
		await get_tree().physics_frame
		if OS.has_environment("CUBE7_DRILL_DEBUG") and k % 30 == 0:
			print("   fly ", fly.state if is_instance_valid(fly) else -1, " ", fly.global_position if is_instance_valid(fly) else Vector3.ZERO, " P=", P.global_position)
		if is_instance_valid(fly) and fly.state == Rustfly.St.STUCK:
			stuck = true
			break
	check(stuck, "锈蜂发现 PIX 后俯冲，扎在地上")
	await _clear_enemies()
	GameState.shield = GameState.max_shield
	# d. 刺壳虫：尖刺竖起时冲撞会被扎；钻头直接钻穿
	await wait(1.6)
	var sp := await _spawn(Spikeshell.new(), Vector3i(46, 3, 26), false) as Spikeshell
	await tp(Vector3i(41, 4, 26), Vector3(8, 0, 0), MorphBall.BALL)
	var sh0 := GameState.shield
	P.debug_input = Vector2(0, -1)
	await wait(0.8)
	P.debug_input = Vector2.ZERO
	check(is_instance_valid(sp) and GameState.shield < sh0, "刺壳虫尖刺竖起时撞上去会被扎（护盾 %d→%d）" % [sh0, GameState.shield])
	await wait(1.5)
	P.apply_form(MorphBall.DRILL, false)
	if is_instance_valid(sp):
		await tp(W.world_to_voxel(sp.global_position) + Vector3i(-2, 1, 0), Vector3.ZERO, MorphBall.DRILL)
		P.debug_input = Vector2(0, -1)
		P.debug_ability = true
		await wait(1.5)
		P.debug_input = Vector2.ZERO
		P.debug_ability = false
	check(not is_instance_valid(sp), "钻头无视尖刺，钻穿刺壳虫")
	await _clear_enemies()
	GameState.shield = GameState.max_shield
	# e. 锈炮台：气浪把锈弹打回去炸它自己
	var mo := await _spawn(Mortar.new(), Vector3i(50, 3, 26), true) as Mortar
	await tp(Vector3i(42, 4, 26), Vector3.ZERO, MorphBall.BUBBLE)
	var hp0 := mo.hp
	var reflected := false
	for k in 240:
		await get_tree().physics_frame
		await get_tree().physics_frame
		for b in get_tree().get_nodes_in_group("projectile"):
			if (b as Node3D).global_position.distance_to(P.global_position) < 3.0 and not b.reflected:
				P.debug_ability_pressed = true
				reflected = true
				print("    锈弹距离 %.1f，按下气浪（冷却 %.2f）" % [(b as Node3D).global_position.distance_to(P.global_position), P._ability_cd])
		if reflected:
			break
	await get_tree().physics_frame
	await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group("projectile"):
		print("    锈弹 reflected=", b.reflected, " pos=", b.global_position, " 炮台=", mo.global_position)
	await wait(2.0)
	check(reflected and (not is_instance_valid(mo) or mo.hp < hp0), "气浪把锈弹打回去，炸到炮台（hp %d→%d）" % [hp0, mo.hp if is_instance_valid(mo) else 0])
	await _clear_enemies()
	GameState.shield = GameState.max_shield
	# f. 泡泡弹：困住锈块兽，飘起来
	e = await _enemy(Vector3i(46, 3, 26), PI / 2.0)
	await tp(Vector3i(41, 4, 26), Vector3.ZERO, MorphBall.BUBBLE)
	P.debug_input = Vector2(0, -0.2)
	await wait(0.1)
	P.debug_input = Vector2.ZERO
	P.debug_ability = true
	P.debug_ability_pressed = true
	await wait(0.7)
	P.debug_ability = false
	var y0 := e.global_position.y
	await wait(0.6)
	check(is_instance_valid(e) and e.state == Scrapling.St.FLIPPED and e.global_position.y > y0 - 0.5, "泡泡弹困住锈块兽（翻倒）")
	await _clear_enemies()
	# g. 扔物件砸中敌人
	e = await _enemy(Vector3i(46, 3, 26), PI / 2.0)
	var it := UsableItem.new()
	L.add_child(it)
	it.global_position = e.global_position + Vector3(-2.0, 1.0, 0)
	it.set_held(false)
	it.linear_velocity = Vector3(5.0, 1.5, 0)
	await wait(1.0)
	check(not is_instance_valid(e) or e.state == Scrapling.St.FLIPPED, "扔出的物件砸翻锈块兽")
	it.queue_free()
	await _clear_enemies()
	GameState.shield = GameState.max_shield

func _chunk_test() -> void:
	print("  —— 体素碎块 ——")
	# 地面上立一根土柱，顶上横着伸出两格；打断柱子后，悬空的两格应整块掉落
	W.fill_box(Vector3i(25, 4, 45), Vector3i(25, 5, 45), Blocks.DIRT)
	W.fill_box(Vector3i(26, 5, 45), Vector3i(27, 5, 45), Blocks.DIRT)
	await wait(0.2)
	W.try_break(Vector3i(25, 5, 45), "drill", 1.0)
	var fine: Array[Vector3i] = []
	for d in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]:
		fine.append(Vector3i(25, 5, 45) * VoxelWorld.CELL + d)
	W.detach_floating(fine)
	await get_tree().process_frame   # 断开检测留到下一帧
	await get_tree().process_frame
	var chunks := W.find_children("*", "VoxelChunk", false, false)
	var n := 0
	for c in W.get_children():
		if c is VoxelChunk:
			n += 1
	check(n >= 1 and W.get_block(Vector3i(26, 5, 45)) == Blocks.AIR, "打断支撑后，悬空的方块整块掉落（碎块 %d 个）" % n)
	await wait(2.0)
	var left := 0
	for c in W.get_children():
		if c is VoxelChunk:
			left += 1
	check(left == 0, "碎块落地后碎掉消失")


func _systems_test() -> void:
	print("  —— 物理系统：燃烧 / 爆炸 / 电网 / 坍塌重建 ——")
	# 测试场地：x 60..100, z 48..62 铺一块地
	W.fill_box(Vector3i(60, 0, 48), Vector3i(100, 2, 62), Blocks.BEDROCK)
	W.fill_box(Vector3i(60, 3, 48), Vector3i(100, 12, 62), Blocks.AIR)
	# 1. 木柱撑着一块石板：烧断柱子，石板塌下来并“长回”地上
	W.fill_box(Vector3i(64, 3, 50), Vector3i(64, 6, 50), Blocks.WOOD)
	W.fill_box(Vector3i(63, 7, 49), Vector3i(67, 7, 51), Blocks.ROCK)
	W.flush_dirty()
	await wait(0.2)
	W.fire.ignite_sphere(W.voxel_center(Vector3i(64, 3, 50)), 0.5)
	var burned := false
	for k in 90:
		await wait(0.2)
		if W.get_block(Vector3i(64, 4, 50)) == Blocks.AIR and W.get_block(Vector3i(66, 7, 50)) == Blocks.AIR:
			burned = true
			break
	check(burned, "点燃木柱：柱子烧断，上面的石板失去支撑")
	await wait(2.5)
	var settled := count_type(Vector3i(62, 3, 48), Vector3i(69, 6, 52), Blocks.ROCK)
	check(settled >= 10, "塌下来的石板落地后留在地上（%d 格）" % settled)
	# 2. 气泡气浪吹灭火
	W.fill_box(Vector3i(74, 3, 50), Vector3i(80, 3, 50), Blocks.WOOD)
	W.flush_dirty()
	W.fire.ignite_sphere(W.voxel_center(Vector3i(77, 3, 50)), 1.2)
	await wait(0.4)
	var b0 := W.fire.burning.size()
	await tp(Vector3i(77, 3, 52), Vector3.ZERO, MorphBall.BUBBLE)
	P.debug_ability_pressed = true
	await wait(0.4)
	check(b0 > 0 and W.fire.burning.size() < b0, "气浪吹灭了火（%d → %d）" % [b0, W.fire.burning.size()])
	await tp(Vector3i(70, 3, 60), Vector3.ZERO, MorphBall.BALL)
	await wait(0.3)
	W.fire.extinguish_sphere(W.voxel_center(Vector3i(77, 3, 50)), 5.0)
	# 3. 燃料桶爆炸炸开加固墙
	W.fill_box(Vector3i(86, 3, 49), Vector3i(86, 5, 53), Blocks.REINFORCED)
	W.fill_box(Vector3i(85, 3, 51), Vector3i(85, 3, 51), Blocks.BARREL)
	W.flush_dirty()
	var r0 := count_type(Vector3i(86, 3, 49), Vector3i(86, 5, 53), Blocks.REINFORCED)
	await tp(Vector3i(84, 3, 51), Vector3(-5, 0, 0))
	check(not W.try_break(Vector3i(86, 4, 51), "impact", 12.0), "加固墙 12 m/s 也撞不开")
	await tp(Vector3i(70, 3, 60))
	W.fire.ignite_sphere(W.voxel_center(Vector3i(85, 3, 51)), 0.4)
	await wait(3.0)
	var r1 := count_type(Vector3i(86, 3, 49), Vector3i(86, 5, 53), Blocks.REINFORCED)
	check(r1 < r0, "燃料桶烧完爆炸，炸开加固墙（%d → %d）" % [r0, r1])
	# 4. 电网：能量源 → 铜线 → 电控门；钻断铜线门关上，补上金属块门又开
	W.fill_box(Vector3i(60, 3, 58), Vector3i(100, 12, 62), Blocks.AIR)
	W.fill_box(Vector3i(62, 3, 60), Vector3i(62, 3, 60), Blocks.SOURCE)
	W.fill_box(Vector3i(63, 3, 60), Vector3i(70, 3, 60), Blocks.COPPER)
	W.fill_box(Vector3i(71, 3, 60), Vector3i(71, 3, 60), Blocks.RECEIVER)
	W.flush_dirty()
	var grid := PowerGrid.new()
	L.add_child(grid)
	grid.setup(W, Vector3i(58, 0, 46), Vector3i(102, 14, 64))
	var door := PowerDoor.new()
	L.add_child(door)
	door.setup(W, [Vector3i(72, 3, 61), Vector3i(72, 4, 61), Vector3i(72, 5, 61)] as Array[Vector3i], [Vector3i(71, 3, 60)] as Array[Vector3i])
	grid.add_device(door)
	var lift := Lift.new()
	lift.a = W.voxel_top(Vector3i(80, 2, 60))
	lift.b = lift.a + Vector3.UP * 2.0
	lift.power_cells = [Vector3i(71, 3, 60)] as Array[Vector3i]
	L.add_child(lift)
	grid.add_device(lift)
	await wait(0.5)
	check(W.get_block(Vector3i(72, 4, 61)) == Blocks.AIR and W.get_block(Vector3i(71, 3, 60)) == Blocks.RECEIVER_ON, "通电：接收器亮起，电控门打开")
	await wait(1.2)
	check(lift.global_position.y > lift.a.y + 0.3, "通电的升降台开始上升（%.1f m）" % (lift.global_position.y - lift.a.y))
	W.try_break(Vector3i(66, 3, 60), "drill", 1.0)
	await wait(0.4)
	check(W.get_block(Vector3i(72, 4, 61)) == Blocks.DOOR and W.get_block(Vector3i(71, 3, 60)) == Blocks.RECEIVER, "钻断铜线：断电，门关上")
	W.set_block(Vector3i(66, 3, 60), Blocks.METAL)
	await wait(0.4)
	check(W.get_block(Vector3i(72, 4, 61)) == Blocks.AIR, "补上一块金属：重新接通，门打开")
