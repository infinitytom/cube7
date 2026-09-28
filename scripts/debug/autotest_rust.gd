extends Node
## 第五章整关测试：godot --headless --path . -- --autotest=rust

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaRust
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
	await wait(0.2)
	P.linear_velocity = vel

func cellp() -> Vector3i:
	return W.world_to_voxel(P.global_position)

func _run() -> void:
	await wait(1.0)
	print("===== 第五章 整关测试 =====")
	check(enemy_count >= 10, "关卡里放了 %d 个敌人（另有 Boss）" % enemy_count)
	check(L.seeds.size() == 4 and L.fragments.size() == 3, "4 个种子方块、3 块记忆碎片")
	check(P.grounded, "出生点：站在沙滩上")
	# 1. 潮汐：低潮时步道露出，高潮时淹没；陆地一直安全
	var walk_y := AreaRust.GW * VoxelWorld.CELL_M
	var land_y := AreaRust.G * VoxelWorld.CELL_M
	check(GameState.kill_y < walk_y, "低潮：浅滩步道露在海面上（海面 %.1f m，步道 %.1f m）" % [L.sea.level_y, walk_y])
	L.sea._t = RustSea.LOW + RustSea.RISE + 1.0
	await wait(0.3)
	check(GameState.kill_y > walk_y + 0.3 and GameState.kill_y < land_y, "高潮：步道被淹，陆地和礁柱还在海面上（淹没线 %.2f m）" % GameState.kill_y)
	L.sea._t = 0.0
	await wait(0.3)
	# 浅滩连续：A → C 的步道每隔几格都有落脚处
	var gaps := 0
	var pts := [Vector2i(46, 126), Vector2i(54, 122), Vector2i(60, 116), Vector2i(66, 112), Vector2i(72, 106)]
	for i in pts.size() - 1:
		for k in 11:
			var t := k / 10.0
			var x := roundi(lerpf(pts[i].x, pts[i + 1].x, t))
			var z := roundi(lerpf(pts[i].y, pts[i + 1].y, t))
			if L.h_at(x, z) < AreaRust.GW:
				gaps += 1
	check(gaps == 0, "浅滩步道从希望号一路连到沉船墓场（断口 %d）" % gaps)
	# 真的滚过去：沿步道推着走
	await tp(Vector3i(46, AreaRust.GW, 126))
	var ok := true
	for i in range(1, pts.size()):
		var target := W.voxel_top(Vector3i(pts[i].x, AreaRust.GW - 1, pts[i].y)) + Vector3.UP * 0.4
		for f in 200:
			var to := target - P.global_position
			to.y = 0.0
			if to.length() < 0.4:
				break
			P.apply_central_force(to.normalized() * 14.0 * P.mass)
			if Vector3(P.linear_velocity.x, 0, P.linear_velocity.z).length() > 4.0:
				P.linear_velocity *= Vector3(0.9, 1, 0.9)
			await get_tree().physics_frame
		if P.global_position.y < walk_y - 0.5:
			ok = false
			break
	check(ok and P.global_position.y > walk_y - 0.2, "沿浅滩步道滚到了沉船墓场（%s）" % cellp())
	# 2. 锈铁：普通冲刺撞不开，蓄力冲刺撞得开
	check(not Blocks.can_break(Blocks.RUST, "impact", 11.5) and Blocks.can_break(Blocks.RUST, "impact", 15.0), "锈铁要蓄力冲刺（15 m/s）才撞得开")
	# 3. 重建栈桥
	var site := L.bridge_site
	GameState.matter = 0
	var pad := site.global_position
	P.teleport(pad + Vector3.UP * 0.6)
	await wait(0.8)
	check(not site.done, "物质不够：栈桥蓝图没有动")
	GameState.add_matter(160)
	P.teleport(pad + Vector3(0, 0.6, 3.0))
	await wait(0.3)
	P.teleport(pad + Vector3.UP * 0.6)
	await wait(0.6)
	check(site.done, "攒够 150 物质，滚进光圈开始重建栈桥")
	await wait(5.0)
	var miss := 0
	for b in site.blueprint:
		if W.get_block(b[0]) == Blocks.AIR:
			miss += 1
	check(miss == 0, "栈桥建好了（缺 %d / %d 格）" % [miss, site.blueprint.size()])
	await tp(Vector3i(AreaRust.BRIDGE_A.x - 1, AreaRust.G, AreaRust.BRIDGE_A.z))
	for f in 200:
		P.apply_central_force(Vector3(14.0, 0, (W.voxel_center(AreaRust.BRIDGE_A).z - P.global_position.z) * 20.0) * P.mass)
		if P.linear_velocity.x > 4.0:
			P.linear_velocity.x = 4.0
		await get_tree().physics_frame
		if cellp().x > AreaRust.BRIDGE_B.x + 2:
			break
	check(cellp().x > AreaRust.BRIDGE_B.x and P.global_position.y > land_y - 0.3, "沿栈桥滚到灯塔岛（%s）" % cellp())
	# 4. Boss
	await tp(Vector3i(AreaRust.D_C.x - 8, AreaRust.G, AreaRust.D_C.y))
	await wait(0.8)
	var worm := L.worm
	check(is_instance_valid(worm) and worm.active, "登上灯塔岛，锈海吞噬者出现")
	check(not L.sea.tide, "Boss 战时潮水停了")
	# 先看它跃出来啃岛边
	var dmg0 := W.damage.size()
	await wait(6.0)
	check(W.damage.size() > dmg0, "它跃出海面，啃掉了岛边的地形（%d 体素）" % (W.damage.size() - dmg0))
	# 直接让它趴下
	worm.debug_rest()
	for k in 60:
		await wait(0.1)
		if worm.state == RustWorm.St.REST:
			break
	check(worm.state == RustWorm.St.REST, "它浮上来趴在岛边喘气")
	# 背脊和岛边的高度差不大，能滚上去
	var mid: Node3D = worm._segs[8]
	var top_y := mid.global_position.y + worm._seg_r[8]
	check(absf(top_y - land_y) < 1.3, "趴着的背脊比岛面低 %.2f 米，能直接滚上去" % (land_y - top_y))
	# 滚上它的背撞锈核
	var core: Node3D = worm._cores[1]
	P.teleport(core.global_position + Vector3(0, 0.3, 0) - (worm._segs[9].global_position - worm._segs[8].global_position).normalized() * 2.0)
	await wait(0.2)
	var dir := (core.global_position - P.global_position)
	dir.y = 0.0
	P.linear_velocity = dir.normalized() * 6.0
	var left0 := worm.cores_left()
	for k in 40:
		await get_tree().physics_frame
		if worm.cores_left() < left0:
			break
	check(worm.cores_left() == left0 - 1, "滚上它的背撞碎一颗锈核（剩 %d）" % worm.cores_left())
	await wait(3.5)
	check(W.damage.size() < 40, "撞碎锈核的瞬间，岛上被啃掉的地方重构回来了（剩 %d 体素）" % W.damage.size())
	for k in 2:
		await wait(1.2)
		if is_instance_valid(worm):
			worm.debug_break(P)
	await wait(4.0)
	check(L.boss_done, "三颗锈核都碎了，锈海吞噬者散架")
	# 5. 灯塔从海里建起来
	await wait(16.0)
	var top := Vector3i(AreaRust.D_C.x, AreaRust.G + AreaRust.LH_H + 7, AreaRust.D_C.y)
	var rbs := L.find_children("*", "VoxelRebuilder", true, false)
	print("   灯塔：built=%s 顶=%d 还在飞的重构器=%d" % [L.lighthouse_built, W.get_block(top), rbs.size()])
	if not rbs.is_empty():
		print("   剩余 ", (rbs[0] as VoxelRebuilder)._items.size(), " 已落 ", (rbs[0] as VoxelRebuilder)._landed, " / ", (rbs[0] as VoxelRebuilder)._total)
	check(W.get_block(top) == Blocks.RECEIVER_ON, "灯塔一块块重建起来，塔顶亮了")
	await tp(Vector3i(AreaRust.D_C.x - AreaRust.LH_R - 2, AreaRust.G, AreaRust.D_C.y))
	await wait(1.5)
	check(GameState.level_complete, "走进灯塔，章节完成")
	print("===== 金币 %d · 碎片 %d/3 · 噗噗 %d/%d =====" % [GameState.coins, GameState.fragments, GameState.seeds, GameState.seeds_total])
	if fails.is_empty():
		print("===== 第五章整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()
