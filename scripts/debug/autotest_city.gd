extends Node
## 第四章整关测试：godot --headless --path . -- --autotest=city

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaCity
var enemy_count := 0

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

func cellp() -> Vector3i:
	return W.world_to_voxel(P.global_position)

## 放到轨道起点附近，顺着轨道方向给一点速度，等它跑完
func ride(r: SkyRail, max_t: float) -> bool:
	var a := r.to_global(r.curve.sample_baked(0.6))
	var b := r.to_global(r.curve.sample_baked(1.4))
	P.teleport(a + Vector3.UP * 0.3)
	await get_tree().physics_frame
	P.linear_velocity = (b - a).normalized() * 3.0
	var got := false
	var t := 0.0
	while t < max_t:
		await wait(0.1)
		t += 0.1
		if P.get_meta("riding", false):
			got = true
		elif got and not P.freeze:
			break
	P.debug_boost = false
	return got

func _run() -> void:
	await wait(1.0)
	print("===== 第四章 整关测试 =====")
	check(enemy_count >= 9, "关卡里放了 %d 个敌人（另有 Boss）" % enemy_count)
	check(L.seeds.size() == 4 and L.fragments.size() == 3, "4 个种子方块、3 块记忆碎片")
	check(P.grounded, "出生点：站在抵达台上")
	# 1. 轨道 1：抵达台 → 集市
	var ok := await ride(L.rails[0], 12.0)
	await wait(1.2)
	var c := cellp()
	check(ok, "滚上车站的轨道，被吸住")
	check(Vector2(c.x - AreaCity.B_C.x, c.z - AreaCity.B_C.y).length() < 17.0 and c.y >= AreaCity.GB - 1, "坐轨道到了集市（%s）" % c)
	# 2. 轨道 2 没电；穹顶里的保险晶
	check(not L.rail2[0].powered, "去公园的轨道一开始没电")
	var hit := W.try_break(AreaCity.DOME_B, "impact", 6.0)
	await wait(0.6)
	check(hit and is_instance_valid(L.fuse), "撞开穹顶里的箱子，掉出保险晶")
	if is_instance_valid(L.fuse):
		L.fuse.global_position = W.voxel_center(AreaCity.FUSE_SOCKET) + Vector3.UP * 1.0
		L.fuse.linear_velocity = Vector3.ZERO
		for k in 40:
			await wait(0.1)
			if L.socket.done:
				break
		await wait(0.5)
	check(L.socket.done, "保险晶放进插槽")
	check(L.rail2[0].powered and L.rail2[1].powered, "两段轨道都通电了")
	# 3. 轨道 2：中间断一截，冲过去接上第二段，到公园
	P.debug_boost = true
	ok = await ride(L.rail2[0], 8.0)
	P.debug_boost = true
	var t := 0.0
	var second := false
	while t < 8.0:
		await wait(0.1)
		t += 0.1
		if L.rail2[1].is_riding():
			second = true
		if second and not P.get_meta("riding", false):
			break
	P.debug_boost = false
	await wait(1.5)
	c = cellp()
	check(ok and second, "第一段轨道尽头飞过缺口，接上第二段")
	check(Vector2(c.x - AreaCity.C_C.x, c.z - AreaCity.C_C.y).length() < 16.0 and c.y >= AreaCity.GC - 1, "到了公园（%s）" % c)
	# 4. 旋转桥：撞转钮，桥转 90° 接上议会广场
	check(L.bridge.dir == 1, "旋转桥一开始朝公园")
	var hub := W.voxel_center(Vector3i(AreaCity.HUB.x, AreaCity.GD, AreaCity.HUB.y))
	P.teleport(hub + Vector3(0, 0.3, 2.6))
	await wait(0.2)
	for k in 6:
		P.linear_velocity = Vector3(0, P.linear_velocity.y, -6.0)
		await wait(0.05)
	await wait(2.2)
	check(P.global_position.y > hub.y - 1.0, "转桥的时候 PIX 还稳稳待在转盘上")
	check(L.bridge.dir == 0, "撞一下转钮，桥转过来接上议会广场（dir=%d flag=%s）" % [L.bridge.dir, SaveGame.flag("cc_bridge")])
	# 桥面能走：从桥东端滚到议会广场
	await tp(Vector3i(AreaCity.HUB.x - 4, AreaCity.GD, AreaCity.HUB.y))
	for k in 60:
		P.linear_velocity.x = -5.0
		P.linear_velocity.z = 0.0
		await wait(0.1)
		if cellp().x < AreaCity.D_C.x + 22:
			break
	c = cellp()
	check(c.x < AreaCity.D_C.x + 24 and c.y >= AreaCity.GD - 1, "沿着桥滚到议会广场（%s）" % c)
	# 5. Boss：锈蚀巡逻艇
	await tp(Vector3i(AreaCity.D_C.x + 6, AreaCity.GD, AreaCity.D_C.y + 4))
	await wait(0.8)
	check(is_instance_valid(L.airship) and L.airship.active, "走进广场，锈蚀巡逻艇开始战斗")
	# 弹射炮能把 PIX 弹到飞艇的高度
	var pads := L.find_children("*", "BouncePad", false, false)
	var best_y := 0.0
	if not pads.is_empty():
		var near: Node3D = null
		for pd in pads:
			var pp := (pd as Node3D).global_position
			if absf(pp.y - AreaCity.GD * VoxelWorld.CELL_M) < 1.5 and pp.distance_to(W.voxel_center(Vector3i(AreaCity.D_C.x, AreaCity.GD, AreaCity.D_C.y + 12))) < 11.0:
				near = pd
				break
		if near:
			P.teleport(near.global_position + Vector3.UP * 0.8)
			var y0 := P.global_position.y
			for k in 30:
				await wait(0.05)
				best_y = maxf(best_y, P.global_position.y - y0)
	check(best_y > L.airship.height - 2.5, "广场角上的弹射炮把 PIX 弹到飞艇的高度（%.1f m / 飞艇 %.1f m）" % [best_y, L.airship.height])
	for k in 3:
		await wait(1.7)
		if is_instance_valid(L.airship):
			L.airship.debug_break(P)
	await wait(5.0)
	check(L.boss_done, "撞坏三台发动机，巡逻艇坠毁")
	check(W.get_block(Vector3i(AreaCity.SPIRE.x, AreaCity.GD + 16 + AreaCity.SPIRE_H, AreaCity.SPIRE.z)) == Blocks.RECEIVER_ON, "议会尖塔亮了")
	# 6. 走到议会大厦门口
	await tp(Vector3i(AreaCity.D_C.x, AreaCity.GD, AreaCity.D_C.y - 6))
	for k in 20:
		P.linear_velocity.z = -3.0
		await wait(0.1)
	await wait(1.0)
	check(GameState.level_complete, "到达议会大厦门口，章节完成")
	print("===== 金币 %d · 碎片 %d/3 · 噗噗 %d/%d =====" % [GameState.coins, GameState.fragments, GameState.seeds, GameState.seeds_total])
	if fails.is_empty():
		print("===== 第四章整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()
