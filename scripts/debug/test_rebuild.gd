extends Node
## 破坏与重构测试：godot --headless --path . res://scenes/main.tscn -- --chapter=N --debugscript=res://scripts/debug/test_rebuild.gd

var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld
var L: Node

func _ready() -> void:
	var main := get_parent()
	P = main.player
	W = main.world
	L = main.level
	P.debug_override = true
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	_run()

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _run() -> void:
	await wait(1.0)
	print("===== 破坏与重构（第 %d 章） =====" % GameState.chapter)
	var sites := get_tree().get_nodes_in_group("rebuild_site")
	check(sites.size() >= 1, "关卡里有 %d 个重构点" % sites.size())
	# 1. 冲刺能撞碎泥土地形；落地不会把地面砸穿
	var start := P.global_position
	var dirt_ok := Blocks.can_break(Blocks.DIRT, "impact", 11.5) and not Blocks.can_break(Blocks.DIRT, "impact", 7.0)
	check(dirt_ok, "泥土：冲刺（11.5 m/s）撞得碎，普通滚（7 m/s）撞不碎")
	check(not Blocks.can_break(Blocks.CLIFF, "impact", 20.0) and Blocks.can_break(Blocks.PAVING, "impact", 15.0), "崖壁是地基打不碎；铺路石蓄力冲刺能撞碎")
	# 2. 砸一个坑，记录破坏
	var hit := W.to_v(start + Vector3.DOWN * 1.0)
	var n := W.break_sphere(W.vcenter(hit), 1.2, "impact", 16.0, Vector3.DOWN)
	await wait(0.2)
	check(n > 0 and W.damage.size() >= n / 2, "砸出一个坑（%d 体素），记进了破坏记录（%d）" % [n, W.damage.size()])
	check(GameState.matter > 0, "拆掉的东西变成了重构物质（%d）" % GameState.matter)
	# 3. 重构波：坑一块块飞回来
	P.teleport(start + Vector3(4, 2, 0))
	await wait(0.3)
	var before := W.damage.size()
	var flying: int = L.call("reconstruct", start, 20.0, 1.5)
	await wait(4.0)
	check(flying > 0 and W.damage.size() < before / 4, "重构波：%d 格飞回原位（剩 %d / %d）" % [flying, W.damage.size(), before])
	# 4. 重构点：物质不够不建，够了滚进光圈就建
	if not sites.is_empty():
		var s: RebuildSite = sites[0]
		GameState.matter = 0
		P.teleport(s.global_position + Vector3.UP * 0.6)
		await wait(0.6)
		check(not s.done, "物质不够：重构点没有动")
		GameState.add_matter(s.cost + 5)
		P.teleport(s.global_position + Vector3(0, 0.6, 3.0))
		await wait(0.3)
		P.teleport(s.global_position + Vector3.UP * 0.6)
		await wait(0.5)
		check(s.done and GameState.matter == 5, "物质够了：滚进光圈开始重建，扣掉 %d 物质" % s.cost)
		await wait(6.0)
		var missing := 0
		for b in s.blueprint:
			if W.get_block(b[0]) == Blocks.AIR:
				missing += 1
		check(missing == 0, "瞭望台一块块建好了（缺 %d / %d 格）" % [missing, s.blueprint.size()])
		var chests := L.find_children("*", "TreasureChest", true, false)
		var top_chest := false
		for c in chests:
			if (c as Node3D).global_position.y > s.global_position.y + 4.0:
				top_chest = true
		check(top_chest, "瞭望台顶上出现了宝箱")
		# 爬上去：从台阶一路滚到顶（沿螺旋推着走）
		var base: Vector3i = s.get_meta("base")
		var ok := await _climb(base, s)
		check(ok, "沿着螺旋台阶能爬到平台上")
	if fails.is_empty():
		print("===== 全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
		for f in fails:
			print("   - " + f)
	get_tree().quit()

## 沿着坡道中线推着 PIX 往上滚（模拟玩家推摇杆）
func _climb(base: Vector3i, s: RebuildSite) -> bool:
	var h := 0
	for b in s.blueprint:
		var c: Vector3i = b[0]
		if c.x == base.x + 1 and c.z == base.z + 1 and b[1] == Blocks.HULL:
			h = maxi(h, c.y - base.y + 1)
	var sides := [[Vector2(0, -3), Vector2(1, 0), Vector2(0, 1)], [Vector2(6, 0), Vector2(0, 1), Vector2(-1, 0)], [Vector2(3, 6), Vector2(-1, 0), Vector2(0, -1)], [Vector2(-3, 3), Vector2(0, -1), Vector2(1, 0)]]
	var pts: Array[Vector3] = []
	var corner0 := Vector2(-1.0, -1.0)
	pts.append(Vector3(corner0.x, 0, corner0.y))
	var f := 0
	var k := 0
	while f < h:
		var sd: Array = sides[k % 4]
		var o: Vector2 = sd[0]
		var fw: Vector2 = sd[1]
		var side: Vector2 = sd[2]
		var mid0 := o + side * 1.5
		var mid1 := o + side * 1.5 + fw * 3.0
		pts.append(Vector3(mid0.x + 0.5, f, mid0.y + 0.5))
		pts.append(Vector3(mid1.x + 0.5, f + 2, mid1.y + 0.5))
		f += 2
		var cns := [Vector2(-3, -3), Vector2(4, -3), Vector2(4, 4), Vector2(-3, 4)]
		var cn: Vector2 = cns[(k + 1) % 4]
		pts.append(Vector3(cn.x + 1.5, f, cn.y + 1.5))
		k += 1
	P.teleport(W.voxel_top(Vector3i(base.x - 1, base.y - 1, base.z - 1)) + Vector3.UP * 0.5)
	await wait(0.5)
	var origin := W.to_global(Vector3(base) * VoxelWorld.CELL_M)
	for wp in pts:
		var target := origin + Vector3(wp.x, wp.y, wp.z) * VoxelWorld.CELL_M + Vector3.UP * 0.4
		for t in 120:
			var to := target - P.global_position
			var hv := Vector3(to.x, 0, to.z)
			if hv.length() < 0.25:
				break
			P.apply_central_force(hv.normalized() * 18.0 * P.mass)
			var v := Vector3(P.linear_velocity.x, 0, P.linear_velocity.z)
			if v.length() > 3.5:
				P.linear_velocity.x *= 0.9
				P.linear_velocity.z *= 0.9
			await get_tree().physics_frame
		if P.global_position.y < origin.y + wp.y * VoxelWorld.CELL_M - 0.8:
			print("   掉下去了：航点 %s，PIX %s" % [wp, P.global_position - origin])
			break
	await wait(0.6)
	var top_y := origin.y + h * VoxelWorld.CELL_M
	print("   PIX y=%.2f 塔顶 y=%.2f" % [P.global_position.y, top_y])
	return P.global_position.y > top_y - 0.2
