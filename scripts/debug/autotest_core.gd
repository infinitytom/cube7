extends Node
## 终章整关测试：godot --headless --path . -- --autotest=core

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaCore
var enemy_count := 0
const K = preload("res://scripts/levels/area_core.gd")

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

func cellp() -> Vector3i:
	return W.world_to_voxel(P.global_position)

## 坡道上的路线点：每条边从起点拐角走到终点拐角（中间车道）
func path_pts(k0: int, k1: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for k in range(k0, k1):
		for along in range(-K.S1 + 2, K.S1 - 1, 2):
			var c: Vector3i = L.side_cell(k, along, K.S0 + 2, L.side_h(k, along))
			pts.append(W.voxel_top(c + Vector3i.DOWN) + Vector3.UP * 0.45)
	return pts

## 沿路线点推着 PIX 往前滚；返回走到了第几个点
func roll_path(pts: Array[Vector3], stop_before := Vector3.INF) -> int:
	for i in pts.size():
		var target: Vector3 = pts[i]
		if stop_before != Vector3.INF and target.distance_to(stop_before) < 2.0:
			return i
		for k in 150:
			var to := target - P.global_position
			var h := Vector3(to.x, 0, to.z)
			if h.length() < 0.4:
				break
			P.apply_central_force(h.normalized() * 16.0 * P.mass)
			if Vector3(P.linear_velocity.x, 0, P.linear_velocity.z).length() > 4.0:
				P.linear_velocity *= Vector3(0.9, 1, 0.9)
			await get_tree().physics_frame
		if P.global_position.y < target.y - 1.2:
			print("   掉下去了：第 %d 个点 %s，PIX %s" % [i, target, P.global_position])
			return i
	return pts.size()

func _run() -> void:
	await wait(1.0)
	print("===== 终章 整关测试 =====")
	check(enemy_count >= 8, "关卡里放了 %d 个敌人（另有 Boss）" % enemy_count)
	check(L.seeds.size() == 4 and L.fragments.size() == 3, "4 个种子方块、3 块记忆碎片")
	check(P.grounded, "出生点：站在星核平台上")
	# 1. 坡道入口被锈墙封住：普通冲刺撞不开，蓄力冲刺撞得开
	var wc: Vector3i = L.side_cell(0, -K.S0 + 1, K.S0 + 2, K.G0 + 1)
	check(W.get_block(wc) == Blocks.RUST, "坡道入口被锈墙封住")
	var n1 := W.break_sphere(W.voxel_center(wc + Vector3i.UP), 0.6, "impact", 11.5)
	var n2 := W.break_sphere(W.voxel_center(wc), 1.6, "impact", 15.0)
	check(n1 == 0 and n2 > 0, "普通冲刺撞不开锈墙，蓄力冲刺撞开了（%d 体素）" % n2)
	# 把整面锈墙拆干净（只拆锈铁体素）
	var v0 := (wc - Vector3i(6, 2, 4)) * VoxelWorld.CELL
	var v1 := (wc + Vector3i(6, 6, 4)) * VoxelWorld.CELL
	for z in range(v0.z, v1.z):
		for y in range(v0.y, v1.y):
			for x in range(v0.x, v1.x):
				if W.vget(Vector3i(x, y, z)) == Blocks.RUST:
					W.vset(Vector3i(x, y, z), Blocks.AIR)
	await wait(0.3)
	# 2. 绕塔坡道：第一条边 → 第二条边的断口前
	var s0: RebuildSite = L.gap_sites[0]
	var s1: RebuildSite = L.gap_sites[1]
	P.teleport(W.voxel_top(L.side_cell(0, -K.S1 + 2, K.S0 + 2, K.G0) + Vector3i.DOWN) + Vector3.UP * 0.5)
	await wait(0.4)
	var pts := path_pts(0, 2)
	var n := await roll_path(pts, s0.global_position + Vector3(0, 0, 0))
	check(P.global_position.distance_to(s0.global_position) < 4.0, "沿坡道滚到第一个断口前（%d/%d 个点，离光圈 %.1f m）" % [n, pts.size(), P.global_position.distance_to(s0.global_position)])
	check(not s0.done and s0.blueprint.size() > 5, "断口有重构蓝图（%d 格）" % s0.blueprint.size())
	GameState.matter = 0
	GameState.add_matter(s0.cost + 5)
	P.teleport(s0.global_position + Vector3.UP * 0.6)
	await wait(0.4)
	check(s0.done, "攒够物质，重建第一段坡道")
	await wait(4.5)
	pts = path_pts(1, 3)
	var start := 0
	for i in pts.size():
		if pts[i].distance_to(s0.global_position) < 2.0:
			start = i
	P.teleport(pts[start])
	await wait(0.3)
	var rest: Array[Vector3] = []
	for i in range(start, pts.size()):
		rest.append(pts[i])
	n = await roll_path(rest, s1.global_position)
	check(P.global_position.distance_to(s1.global_position) < 4.0, "过了第一个断口，滚到第二个断口前（离光圈 %.1f m）" % P.global_position.distance_to(s1.global_position))
	GameState.add_matter(s1.cost + 5)
	P.teleport(s1.global_position + Vector3.UP * 0.6)
	await wait(4.5)
	pts = path_pts(2, 4)
	start = 0
	for i in pts.size():
		if pts[i].distance_to(s1.global_position) < 2.0:
			start = i
	P.teleport(pts[start])
	await wait(0.3)
	rest = []
	for i in range(start, pts.size()):
		rest.append(pts[i])
	n = await roll_path(rest)
	check(n == rest.size() and P.global_position.y > (K.G1 - 1) * VoxelWorld.CELL_M, "一整圈坡道爬完，到了反应堆回廊（y=%.1f）" % P.global_position.y)
	# 3. 反应堆井：气泡形态乘上升气流
	P.apply_form(MorphBall.BUBBLE, false)
	P.teleport(W.voxel_center(Vector3i(K.C.x, K.G1, K.C.y)) + Vector3.UP * 0.3)
	var top_y := 0.0
	for k in 120:
		await wait(0.1)
		top_y = maxf(top_y, P.global_position.y)
		# 往北边飘，落在出口歇脚台上
		if P.global_position.y > (K.G2 + 1) * VoxelWorld.CELL_M:
			P.apply_central_force(Vector3(0, 0, -6.0) * P.mass)
	check(top_y > K.G2 * VoxelWorld.CELL_M, "气泡乘上升气流飘到井顶（最高 %.1f m，井顶 %.1f m）" % [top_y, K.G2 * VoxelWorld.CELL_M])
	P.apply_form(MorphBall.BALL, false)
	# 4. 空中轨道：T2 → 塔顶
	var rails := L.find_children("*", "SkyRail", false, false)
	check(rails.size() >= 1, "有通往塔顶的空中轨道")
	if not rails.is_empty():
		var r: SkyRail = rails[0]
		P.teleport(r.to_global(r.curve.sample_baked(0.6)) + Vector3.UP * 0.3)
		await get_tree().physics_frame
		P.linear_velocity = (r.to_global(r.curve.sample_baked(1.4)) - r.to_global(r.curve.sample_baked(0.6))).normalized() * 3.0
		var rode := false
		for k in 200:
			await wait(0.1)
			if P.get_meta("riding", false):
				rode = true
			elif rode:
				break
		await wait(1.0)
		check(rode and P.global_position.y > (K.GT - 1) * VoxelWorld.CELL_M, "坐轨道到了塔顶（y=%.1f）" % P.global_position.y)
	# 5. Boss
	P.teleport(W.voxel_center(Vector3i(K.C.x, K.GT, K.C.y + 14)) + Vector3.UP * 0.2)
	await wait(2.5)
	var h := L.heart
	h.waves_on = false
	check(is_instance_valid(h) and h.active and h.phase == 1, "走进塔顶，锈蚀之心苏醒（第一阶段）")
	check(h.shell_intact() > 0.9, "它裹着一层锈铁壳（完整度 %.0f%%）" % (h.shell_intact() * 100.0))
	# 第一阶段：蓄力冲刺撞出洞，再撞核心
	var ph := h.phase
	for tries in 4:
		if h.phase != ph:
			break
		P.teleport(h.global_position + Vector3(0, -0.9, 6.0))
		await wait(0.3)
		P.linear_velocity = Vector3(0, 0, -15.0)
		P._dash_t = 0.55
		P.charged_ram = true
		var minr := 99.0
		for k in 60:
			await get_tree().physics_frame
			minr = minf(minr, P.global_position.distance_to(h.global_position))
			if h.phase != ph:
				break
		print("   冲撞第 %d 次：最近 %.2f m，锈壳 %.0f%%" % [tries, minr, h.shell_intact() * 100])
		await wait(0.5)
	check(h.phase == 2, "撞穿锈壳、撞到核心——进入第二阶段（shell %.0f%%）" % (h.shell_intact() * 100.0))
	if h.phase == 1:
		h.debug_hit()
	await wait(2.5)
	check(h.global_position.y > h.floor_y + 6.0, "它升到了高处（%.1f m）" % (h.global_position.y - h.floor_y))
	# 第二阶段：弹射炮飞上去，钻头下砸
	var pads := L.find_children("*", "BouncePad", false, false)
	var apex := 0.0
	if not pads.is_empty():
		P.teleport((pads[0] as Node3D).global_position + Vector3.UP * 0.8)
		for k in 40:
			await wait(0.05)
			apex = maxf(apex, P.global_position.y - h.floor_y)
	check(apex > h.global_position.y - h.floor_y + 2.0, "弹射炮把 PIX 弹到它上方（%.1f m）" % apex)
	P.apply_form(MorphBall.DRILL, false)
	ph = h.phase
	P.teleport(h.global_position + Vector3.UP * (RustHeart.SHELL_R + 2.5))
	await wait(0.2)
	for k in 20:
		if P._pounding:
			break
		P.debug_ability_pressed = true
		await get_tree().physics_frame
	for k in 90:
		await get_tree().physics_frame
		if k % 10 == 0:
			print("   下砸 k=%d 相对=%s 速度=%.1f attack=%s shell=%.0f%%" % [k, P.global_position - h.global_position, P.linear_velocity.length(), P.attack, h.shell_intact() * 100])
		if h.phase != ph:
			break
	check(h.phase == 3, "从上面下砸，砸穿锈壳砸到核心——第三阶段")
	if h.phase == 2:
		h.debug_hit()
	P.apply_form(MorphBall.BUBBLE, false)
	await wait(3.5)
	# 第三阶段：气浪把锈弹打回去
	check(h.shell_intact() > 0.8, "锈壳换成了合金")
	var bomb: RustBomb = null
	P.teleport(h.global_position + Vector3(0, 0, 7.0))
	for k in 120:
		await wait(0.1)
		if P.global_position.distance_to(h.global_position + Vector3(0, 0, 7.0)) > 2.0:
			P.teleport(h.global_position + Vector3(0, -0.9, 7.0))
		for b in get_tree().get_nodes_in_group("projectile"):
			if b is RustBomb and (b as Node3D).global_position.distance_to(P.global_position) < 3.0:
				bomb = b
		if bomb:
			break
	check(bomb != null, "它朝 PIX 吐锈弹")
	if bomb:
		P.debug_ability_pressed = true
		await wait(0.1)
		for k in 30:
			await wait(0.1)
			if h.phase == 4:
				break
	check(h.phase == 4, "气浪把锈弹打回去，炸碎了合金壳——核心掉下来")
	if h.phase == 3:
		h.debug_hit()
	await wait(2.0)
	# 最后一击
	var hc := W.world_to_voxel(h.global_position)
	var solid := {}
	for z in range(-8, 9):
		for y in range(-3, 9):
			for x in range(-8, 9):
				var t := W.get_block(hc + Vector3i(x, y, z))
				if t != Blocks.AIR and y >= 0:
					solid[t] = int(solid.get(t, 0)) + 1
	print("   核心周围的方块：", solid, " 核心格 ", hc, " 地面 y=", h.floor_y)
	P.apply_form(MorphBall.BALL, false)
	P.teleport(h.global_position + Vector3(0, 0, 4.0))
	await wait(0.3)
	P.linear_velocity = Vector3(0, 0, -8.0)
	for k in 60:
		await get_tree().physics_frame
		if k % 10 == 0:
			print("   最后一击 k=%d 相对=%s 速度=%.1f phase=%d dead=%s" % [k, P.global_position - h.global_position, P.linear_velocity.length(), h.phase, h.dead])
		if L.boss_done:
			break
	await wait(2.5)
	check(L.boss_done, "撞碎核心，锈蚀之心被打倒")
	# 6. 星核重构 → 结局
	await wait(10.0)
	var cc := Vector3i(K.C.x, K.GT + 10, K.C.y)
	check(W.get_block(cc + Vector3i(0, 9, 0)) == Blocks.CRYSTAL or W.get_block(cc + Vector3i(0, -9, 0)) == Blocks.CRYSTAL, "星核水晶一块块拼了起来")
	await wait(4.0)
	check(GameState.level_complete, "通关：进入结局演出")
	var cs := get_tree().current_scene.find_children("*", "Cutscene", true, false)
	check(not cs.is_empty(), "结局过场在播放")
	if fails.is_empty():
		print("===== 终章整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()
