extends Node
## 探索系统测试：回声晶核埋藏、扫描标记、进化解锁、碎块压伤敌人。
## godot --headless --path . res://scenes/main.tscn -- --chapter=1 --debugscript=res://scripts/debug/test_explore.gd
var fails: Array[String] = []
var P: MorphBall
var W: VoxelWorld

func check(c: bool, m: String) -> void:
	print(("  [PASS] " if c else "  [FAIL] ") + m)
	if not c:
		fails.append(m)

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _ready() -> void:
	P = get_parent().player
	W = get_parent().world
	P.debug_override = true
	_run()

func _run() -> void:
	print("===== 探索系统测试 =====")
	await wait(0.5)
	var cores := get_tree().get_nodes_in_group("scan_target").filter(func(n: Node) -> bool: return n is EchoCore)
	check(GameState.echo_total >= 3 and cores.size() == GameState.echo_total, "第一章埋下 %d 颗回声晶核（节点 %d）" % [GameState.echo_total, cores.size()])
	# 每颗晶核都在实心地层包围的空洞里
	var buried := 0
	for c in cores:
		var v := W.to_v((c as Node3D).global_position)
		# 往上：先穿过晶洞里的空气，再数头顶的实心地层
		var k := 1
		while W.vget(v + Vector3i(0, k, 0)) == Blocks.AIR and k < 12:
			k += 1
		var roof := 0
		while W.vget(v + Vector3i(0, k, 0)) != Blocks.AIR and k < 60:
			roof += 1
			k += 1
		if W.vget(v) == Blocks.AIR and roof >= 3:
			buried += 1
		else:
			print("   core %s v=%s air=%s roof=%d" % [c.name, v, W.vget(v) == Blocks.AIR, roof])
	check(buried == cores.size(), "晶核都埋在地下的晶洞里（%d/%d）" % [buried, cores.size()])
	# 扫描：站到第一颗晶核正上方的地面
	var target := cores[0] as Node3D
	var tv := W.to_v(target.global_position)
	var top := tv
	while W.vget(top) == Blocks.AIR and top.y < W.size.y - 2:
		top += Vector3i.UP
	while (W.vget(top) != Blocks.AIR or W.vget(top + Vector3i.UP) != Blocks.AIR or W.vget(top + Vector3i.UP * 2) != Blocks.AIR) and top.y < W.size.y - 4:
		top += Vector3i.UP
	P.teleport(W.vcenter(top) + Vector3.UP * 0.6)
	await wait(0.6)
	var scan := get_tree().get_first_node_in_group("echo_scan") as EchoScan
	scan.scan()
	await wait(0.2)
	var seen := scan.last_hits.filter(func(h: Dictionary) -> bool: return h.kind == "core")
	check(not seen.is_empty(), "站在地面上扫描，隔着地层标出晶核（标记 %d 个）" % scan.last_hits.size())
	# 钻下去拿晶核：直接把路挖开（模拟钻头），然后碰到它
	var locked := (target as EchoCore).locked_hint != ""
	if locked:
		Evolutions.grant("spiral_drill")
		check(Blocks.can_break(Blocks.CLIFF, "drill", 1.0), "进化「螺旋钻头」后能钻悬崖岩")
	var before := GameState.echo_found
	var tid := (target as EchoCore).core_id
	P.teleport(target.global_position + Vector3.UP * 0.1)
	await wait(0.6)
	check(GameState.echo_found == before + 1 and GameState.has_echo(tid), "拿到晶核（%d/%d），存进进化材料" % [GameState.echo_found, GameState.echo_total])
	# 进化：给够晶核以后解锁“深层回声”，扫描半径变大
	for i in 4:
		GameState.echo_ids().append("test_core_%d" % i)
	var r0 := Evolutions.scan_radius()
	check(Evolutions.unlock("echo_range") and Evolutions.scan_radius() > r0, "用晶核进化「深层回声」：扫描半径 %.0f → %.0f 米" % [r0, Evolutions.scan_radius()])
	# 碎块压伤敌人：在敌人头顶生成一块下落的岩石
	var e := Scrapling.new()
	e.set("ai", false)
	get_parent().level.add_child(e)
	var spot := W.vcenter(top) + Vector3.UP * 0.2
	e.global_position = spot
	await wait(0.4)
	var blocks := []
	for x in 3:
		for y in 3:
			for z in 3:
				blocks.append([Vector3(x - 1, y - 1, z - 1) * VoxelWorld.VOXEL, Blocks.ROCK])
	var ch := VoxelChunk.new()
	ch.world = W
	ch.blocks = blocks
	ch.fragment = true
	W.add_child(ch)
	ch.global_position = e.global_position + Vector3.UP * 3.0
	ch.linear_velocity = Vector3.DOWN * 6.0
	await wait(1.0)
	check(not is_instance_valid(e) or e.state == Scrapling.St.DEAD, "掉下来的岩块砸中锈块兽")
	# 关卡支线：地下洞穴、落石陷阱
	var lv: Node3D = get_parent().level
	var caves: Array = lv.get_meta("spice_caves", [])
	check(caves.size() >= 1, "第一章生成了 %d 条地下洞穴" % caves.size())
	var traps: Array = lv.get_meta("spice_traps", [])
	check(traps.size() >= 1, "第一章生成了 %d 处落石陷阱" % traps.size())
	if not traps.is_empty():
		var tb: Vector3i = traps[0]
		var boulder := tb + Vector3i(1, 9, 1)
		check(W.vget(boulder) == Blocks.ROCK, "木架顶上托着圆石")
		var chunks0 := W.get_children().filter(func(n: Node) -> bool: return n is VoxelChunk).size()
		W.break_sphere(W.vcenter(tb) + Vector3(0.25, 0.3, 0.25), 0.7, "impact", 12.0, Vector3.RIGHT)
		var fell := false
		for k in 20:
			await wait(0.1)
			if W.get_children().any(func(n: Node) -> bool: return n is VoxelChunk and (n as VoxelChunk).blocks.size() > 100):
				fell = true
		await wait(2.0)
		check(fell and W.vget(boulder) != Blocks.ROCK, "撞断木架：木架连锁崩塌，圆石整块掉下来")
	# ---- 主线：关键道具 → Boss
	var key := get_tree().get_first_node_in_group("key_relic") as KeyRelic
	check(key != null, "第一章放下了关键道具「%s」" % ChapterKey.key_name("greenhouse"))
	var lv1 := get_parent().level as AreaGreenhouse
	var hulk := lv1.hulk
	check(hulk != null and not hulk.active, "终点浮岛上有锈根兽，还没开打")
	if key and hulk:
		# 没有芯片：封印挡住
		var ok := ChapterKey.unseal(lv1, hulk, "greenhouse")
		check(not ok and hulk.get_node_or_null("RustSeal") != null and GameState.objective_text.contains("关键道具"), "没有芯片：Boss 有锈封印，目标改成去找芯片")
		# 扫描能标出关键道具
		P.teleport(key.global_position + Vector3.UP * 3.0)
		await wait(0.3)
		var sc := get_tree().get_first_node_in_group("echo_scan") as EchoScan
		sc._cd = 0.0
		sc.scan()
		check(sc.last_hits.any(func(h: Dictionary) -> bool: return h.kind == "key"), "扫描标出金色的关键道具")
		P.teleport(key.global_position)
		await wait(0.8)
		check(ChapterKey.has("greenhouse") and Evolutions.has("echo_range"), "拿到芯片：解锁本章进化「深层回声」")
		check(ChapterKey.unseal(lv1, hulk, "greenhouse"), "带着芯片：封印碎掉")
		hulk.start()
		await wait(0.2)
		# 落石：把锈根兽放到第一处木架旁边，撞断木架
		var tc: Array = lv1._trap_cells[0]
		var pillar: Vector3i = tc[0][0]
		hulk.global_position = W.vcenter(pillar) + Vector3(0.6, 0.0, 0.0)
		hulk.velocity = Vector3.ZERO
		hulk.ai = false
		await wait(0.3)
		W.break_sphere(W.vcenter(pillar) + Vector3(0.1, 0.3, 0.1), 0.6, "impact", 12.0, Vector3.RIGHT)
		var flipped := false
		for k in 40:
			await wait(0.05)
			if hulk.state == Scrapling.St.FLIPPED:
				flipped = true
				break
		check(flipped, "落石砸中锈根兽：岩甲裂开、翻倒")
		var hp0 := hulk.hp
		hulk._hurt(P.global_position)
		check(hulk.hp == hp0 - 1, "翻倒时一击：剩 %d" % hulk.hp)
		hulk.take_hit(hulk.global_position, "crush")
		hulk._hurt(P.global_position)
		hulk.take_hit(hulk.global_position, "crush")
		hulk._hurt(P.global_position)
		await wait(0.5)
		check(lv1.hulk_done and lv1.find_children("*", "Goal", true, false).size() >= 1, "打倒锈根兽：终点出现")
	if fails.is_empty():
		print("===== 探索系统测试全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
	get_tree().quit()
