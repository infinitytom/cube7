extends Node
## 第二章整关测试：godot --headless --path . -- --autotest=gearworks
## 沿设计路线走一遍：烧荆棘 → 烧脚手架放下石板 → 钻断铜线关电网 → 取晶块补管线开门
## → 气泡核心 → 喷火走廊 → 上升气流 → 燃料桶炸墙 → 重构塔。也确认几个“不能跳过”的地方。

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: AreaGearworks
const G := AreaGearworks.G

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
	await wait(0.15)
	P.linear_velocity = vel

func vx(p: Vector3) -> Vector3i:
	return W.world_to_voxel(p)

func face(yaw: float) -> void:
	if GameState.camera:
		GameState.camera.set("yaw", yaw)

## 找场上离某点最近的某种物件
func nearest_item(id: String, near: Vector3) -> UsableItem:
	var best: UsableItem = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("usable_item"):
		var it := n as UsableItem
		if it and it.item_id == id and it.global_position.distance_to(near) < bd:
			bd = it.global_position.distance_to(near)
			best = it
	return best

## 走到物件旁边抓起来
func grab(id: String) -> bool:
	var it := nearest_item(id, P.global_position)
	if it == null:
		return false
	P.teleport(it.global_position + Vector3(-0.8, 0.3, 0))
	await wait(0.3)
	P.toggle_grab()
	await wait(0.3)
	return it.held

func _run() -> void:
	await wait(1.0)
	print("===== 第二章 整关测试 =====")
	check(enemy_count == 3, "关卡里放了 %d 只锈块兽" % enemy_count)
	check(L.seeds.size() == 3 and L.fragments.size() == 3, "3 个种子方块、3 块记忆碎片")
	check(GameState.unlocked_forms[MorphBall.DRILL] and not GameState.unlocked_forms[MorphBall.BUBBLE], "开局：滚球 + 钻头，气泡未解锁")

	# 1. 枯荆棘：撞不开、钻不动
	var bx := AreaGearworks.BARRICADE_X
	await tp(Vector3i(bx - 6, G, 77), Vector3(11, 0, 0))
	await go(Vector2(0, -1), 1.2, false, true)
	check(vx(P.global_position).x < bx, "全速冲撞过不了荆棘（x=%d）" % vx(P.global_position).x)
	P.apply_form(MorphBall.DRILL, false)
	await tp(Vector3i(bx - 2, G, 77))
	await go(Vector2(0, -1), 2.0, true)
	check(W.get_block(Vector3i(bx, G, 77)) == Blocks.BRAMBLE, "钻头钻不动荆棘")
	P.apply_form(MorphBall.BALL, false)
	# 拿火种扔过去
	await tp(Vector3i(24, G, 75))
	await wait(0.5)
	var got := await grab("ember")
	check(got, "从炭火盆抓起火种")
	await tp(Vector3i(bx - 3, G, 77))
	face(-PI / 2.0)
	await wait(0.2)
	P.toggle_grab()
	var cleared := false
	for k in 60:
		await wait(0.25)
		if W.get_block(Vector3i(bx, G, 77)) == Blocks.AIR and W.get_block(Vector3i(bx + 1, G + 1, 77)) == Blocks.AIR and W.get_block(Vector3i(bx, G, 76)) == Blocks.AIR:
			cleared = true
			break
	check(cleared, "火种点着荆棘，烧出一条路")
	await wait(1.0)
	await tp(Vector3i(bx - 3, G, 77))
	await go(Vector2(0, -1), 3.0)
	check(vx(P.global_position).x > bx + 2, "穿过烧开的路障（x=%d）" % vx(P.global_position).x)

	# 2. 断崖：跳不过去
	var cx := AreaGearworks.CHASM
	await tp(Vector3i(36, G, 76), Vector3(11, 0, 0))
	P.debug_boost = true
	P.debug_input = Vector2(0, -1)
	for k in 240:
		await get_tree().physics_frame
		if vx(P.global_position).x >= cx.x - 1:
			break
	P.debug_jump_held = true
	P.debug_jump_pressed = true
	var crossed := false
	for k in 120:
		await get_tree().physics_frame
		var q := vx(P.global_position)
		if q.x > cx.y and q.y >= G:
			crossed = true
	P.debug_jump_held = false
	P.debug_boost = false
	P.debug_input = Vector2.ZERO
	check(not crossed, "加速起跳也跨不过断崖（石板挡在头顶）")
	await wait(1.5)
	# 烧脚手架
	await tp(Vector3i(42, G, 73))
	await wait(0.5)
	got = await grab("ember")
	check(got, "抓起第二个火种")
	await tp(Vector3i(cx.x - 6, G, 76))
	face(-PI / 2.0)
	await wait(0.2)
	P.toggle_grab()
	var down := false
	for k in 100:
		await wait(0.25)
		# 火灭了但石板还挂着（有几根木头没烧到）：像玩家一样再扔一个火种
		if k == 60 and W.get_block(Vector3i(53, G + 2, 76)) != Blocks.AIR and W.fire.burning.is_empty():
			print("    （再扔一个火种）")
			await tp(Vector3i(42, G, 73))
			await wait(0.5)
			if await grab("ember"):
				await tp(Vector3i(cx.x - 6, G, 76))
				face(-PI / 2.0)
				await wait(0.2)
				P.toggle_grab()
		if W.get_block(Vector3i(53, G - 1, 76)) == Blocks.ROCK and W.get_block(Vector3i(53, G + 2, 76)) == Blocks.AIR:
			down = true
			break
	check(down, "烧掉脚手架：石板落下，架在铁轨上")
	await wait(3.5)
	await tp(Vector3i(cx.x - 3, G, 76))
	await go(Vector2(0, -1), 3.0)
	check(vx(P.global_position).x > cx.y and vx(P.global_position).y >= G - 1, "从石板桥滚到对岸（x=%d, y=%d）" % [vx(P.global_position).x, vx(P.global_position).y])

	# 3. 大门：一开始关着；储料场电网通着电
	check(W.get_block(Vector3i(70, G + 1, 67)) == Blocks.DOOR, "厂房大门关着（管线缺一截）")
	var fence: ElectricField = null
	for n in L.get_children():
		if n is ElectricField:
			fence = n
	check(fence != null and fence.is_powered, "储料场门口的电网通着电")
	# 钻断铜线
	P.apply_form(MorphBall.DRILL, false)
	await tp(Vector3i(72, G, 54))
	await go(Vector2.ZERO, 1.5, true)
	await wait(0.4)
	check(fence != null and not fence.is_powered, "往下钻断铜线：电网断电")
	P.apply_form(MorphBall.BALL, false)
	# 进储料场，撞开物资箱
	await tp(Vector3i(87, G, 55), Vector3(0, 0, -6))
	await go(Vector2(-1, 0), 1.5)
	check(vx(P.global_position).z < 52, "穿过关掉的电网进入储料场（z=%d）" % vx(P.global_position).z)
	await tp(Vector3i(92, G, 49), Vector3(0, 0, -7))
	await go(Vector2(-1, 0), 1.2, false, true)
	await wait(0.8)
	var cr := nearest_item("crystal", P.global_position)
	if cr == null:
		W.try_break(Vector3i(92, G, 45), "impact", 20.0)
		await wait(0.8)
		cr = nearest_item("crystal", P.global_position)
	check(cr != null, "撞开物资箱，掉出能量晶块")
	got = await grab("crystal")
	check(got, "抓起晶块")
	await tp(AreaGearworks.GAP + Vector3i(-2, 0, 0))
	await wait(0.3)
	check(P._held != null, "瞬移后仍抱着晶块")
	P.toggle_grab()
	var opened := false
	for k in 30:
		await wait(0.2)
		if W.get_block(Vector3i(70, G + 1, 67)) == Blocks.AIR:
			opened = true
			break
	check(opened, "晶块补上管线缺口：大门通电打开")

	# 4. 气泡核心
	await tp(AreaGearworks.CORE + Vector3i(-4, 0, 0))
	await go(Vector2(0, -1), 1.2)
	await wait(1.0)
	check(GameState.unlocked_forms[MorphBall.BUBBLE], "拿到能量核心：气泡形态解锁")
	# 5. 喷火口：气浪吹熄
	P.apply_form(MorphBall.BUBBLE, false)
	var jet: FlameJet = null
	for n in L.get_children():
		if n is FlameJet:
			jet = n
			break
	await tp(Vector3i(85, G, 72))
	P.debug_ability_pressed = true
	await wait(0.4)
	check(jet != null and jet._snuffed > 0.0, "气浪吹熄喷火口")
	# 6. 上升气流
	await tp(Vector3i(86, G, 64))
	var top := 0.0
	for k in 40:
		await wait(0.1)
		top = maxf(top, P.global_position.y)
	check(top >= (AreaGearworks.WALK_Y + 1) * VoxelWorld.CELL_M, "气泡乘上升气流升到走廊高度（%.1f m）" % top)
	P.debug_input = Vector2(-1, 0)
	await wait(1.2)
	P.debug_input = Vector2.ZERO
	await wait(0.6)
	check(vx(P.global_position).y >= AreaGearworks.WALK_Y + 1, "落到空中走廊上（y=%d）" % vx(P.global_position).y)
	# 7. 加固墙：撞不开；燃料桶炸开
	var bw := AreaGearworks.BLAST_X
	P.apply_form(MorphBall.BALL, false)
	check(not W.try_break(Vector3i(bw, AreaGearworks.WALK_Y + 2, 61), "impact", 12.0), "12 m/s 的冲撞撞不开加固墙")
	await tp(Vector3i(88, AreaGearworks.WALK_Y + 1, 61))
	await wait(0.5)
	got = await grab("ember")
	check(got, "在走廊上抓起火种")
	await tp(Vector3i(bw - 5, AreaGearworks.WALK_Y + 1, 61))
	face(-PI / 2.0)
	await wait(0.2)
	P.toggle_grab()
	await wait(0.3)
	await tp(Vector3i(88, AreaGearworks.WALK_Y + 1, 61))
	var blown := false
	for k in 40:
		await wait(0.25)
		if L.wall_blown:
			blown = true
			break
	check(blown and W.get_block(Vector3i(bw, AreaGearworks.WALK_Y + 2, 61)) == Blocks.AIR, "燃料桶爆炸，炸开加固墙")
	await wait(1.0)
	# 8. 重构塔
	await tp(Vector3i(bw - 2, AreaGearworks.WALK_Y + 1, 61))
	await go(Vector2(0, -1), 3.0)
	await wait(1.0)
	check(GameState.level_complete, "到达第二座重构塔，章节完成（x=%d）" % vx(P.global_position).x)
	print("===== 金币 %d · 碎片 %d/3 · 噗噗 %d/3 =====" % [GameState.coins, GameState.fragments, GameState.seeds])
	if fails.is_empty():
		print("===== 第二章整关测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()
