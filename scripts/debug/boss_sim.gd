extends Node
## Boss 模拟：godot --headless --path . -- --chapter=2 --debugscript=res://scripts/debug/boss_sim.gd
## 主角躲在石柱后面，看熔炉守卫会不会冲锋撞柱、晕眩；再看冲击波、召唤、锈弹。

func _ready() -> void:
	var main := get_parent()
	var P: MorphBall = main.player
	var W: VoxelWorld = main.world
	var L: AreaGearworks = main.level
	P.debug_override = true
	for e in L.enemies:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().create_timer(1.0).timeout
	var boss := L.boss
	# 主角站在西北石柱的后面（石柱在主角和 Boss 之间）
	var pillar := W.voxel_center(L.pillar_cells[0])
	var dir := (pillar - boss.global_position)
	dir.y = 0.0
	var spot := pillar + dir.normalized() * 1.6
	P.teleport(Vector3(spot.x, pillar.y + 0.2, spot.z))
	boss.start()
	var last := -1
	var dizzy := 0
	var hurt := 0
	var sh := GameState.shield
	for k in 600:
		await get_tree().physics_frame
		if boss.state != last:
			last = boss.state
			print("  t=%.1f 状态 %s hp=%d 主角护盾 %d" % [k / 60.0, FurnaceWarden.St.keys()[boss.state], boss.hp, GameState.shield])
			if boss.state == FurnaceWarden.St.DIZZY:
				dizzy += 1
		if GameState.shield < sh:
			hurt += 1
			sh = GameState.shield
			GameState.shield = GameState.max_shield
			sh = GameState.shield
		# 主角一直躲回石柱后面
		if k % 30 == 0 and is_instance_valid(boss):
			var p2 := W.voxel_center(L.pillar_cells[0])
			var d2 := p2 - boss.global_position
			d2.y = 0.0
			var s2 := p2 + d2.normalized() * 1.6
			P.teleport(Vector3(s2.x, p2.y + 0.2, s2.z))
	var missing := 0
	for c in L.pillar_cells:
		if W.get_block(c) == Blocks.AIR:
			missing += 1
	print("===== Boss 模拟：晕眩 %d 次，主角受伤 %d 次，石柱缺 %d 格 =====" % [dizzy, hurt, missing])
	get_tree().quit()
