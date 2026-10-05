class_name ChapterKey
extends RefCounted
## 每一章的主线：探索 → 关键道具「进化芯片」→ Boss。
##   · 芯片埋在地层深处（优先放在有地下洞穴通过去的晶洞里），或者压在一座塌方堆里，回声扫描会标成金色的“关键道具”
##   · 拿到芯片：PIX 立刻进化出本章的新能力（这一章的 Boss 正好要用到它）
##   · Boss 身上有一层锈封印：没有芯片打不开，NOVA 会把目标改成“去找芯片”；带着芯片走近，封印共鸣碎掉，开打

const KEYS := {
	"greenhouse": {"name": "回声芯片", "evo": "echo_range",
		"line": "这是……回声芯片！PIX 的探测器进化了：「深层回声」，扫描能听见更远、更深的东西。终点浮岛上那只大家伙身上的锈封印，现在可以打开了。"},
	"gearworks": {"name": "震荡芯片", "evo": "shock_ram",
		"line": "震荡芯片！滚球进化出「震荡冲撞」——撞击会把岩石震裂成大块，满蓄力能撞开岩石。熔炉守卫的封印挡不住你了。"},
	"abyss": {"name": "螺旋芯片", "evo": "spiral_drill",
		"line": "螺旋芯片！钻头进化出「螺旋钻头」——崖壁、深渊岩、锈岩都钻得动了。去深渊底，打破巨像的封印。"},
	"city": {"name": "共鸣芯片", "evo": "resonance",
		"line": "共鸣芯片！气泡进化出「共鸣气泡」——气浪能震碎晶簇和松动的石板。那艘锈蚀飞艇的封印，现在能打开了。"},
	"rust": {"name": "视界芯片", "evo": "echo_sight",
		"line": "视界芯片！「回声视界」——扫描标出来的东西会亮得更久。……灯塔下面那条锈海吞噬者，该去会会它了。"},
	"core": {"name": "星核钥匙", "evo": "",
		"line": "星核钥匙……是艾拉留下的。PIX，锈蚀之心的封印，交给你了。"},
}

## 自动测试（整关测试）里跳过钥匙
static var test_bypass := false
static var _mem := {}
static var _hint_t := 0.0
static var _saved_obj := {}

static func key_name(ch: String) -> String:
	return str(KEYS.get(ch, {}).get("name", "关键道具"))

static func has(ch: String) -> bool:
	if test_bypass or not KEYS.has(ch):
		return true
	if bool(_mem.get(ch, false)):
		return true
	return _owned_before(ch)

const ORDER := ["greenhouse", "gearworks", "abyss", "city", "rust", "core"]

static func collect(ch: String, pos: Vector3) -> void:
	_mem[ch] = true
	if not SaveGame.data.is_empty():
		SaveGame.set_flag("key_" + ch)
		SaveGame.write()
	var evo: String = KEYS.get(ch, {}).get("evo", "")
	if evo != "" and not Evolutions.has(evo):
		Evolutions.grant(evo)
		if not SaveGame.data.is_empty():
			SaveGame.write()
		GameState.upgrades_changed.emit()
	Sfx.play("echo_core", Vector3.INF, 0.0, 0.0, 0.8)
	Sfx.play("level_clear", Vector3.INF, -6.0, 0.0)
	GameState.rumble(0.6, 0.8, 0.4)
	GameState.shake.emit(0.25)
	GameState.say(str(KEYS.get(ch, {}).get("line", "")))
	# 如果之前在 Boss 门口被拦下，目标改回去
	if not _saved_obj.is_empty():
		GameState.override_objective(str(_saved_obj.text), _saved_obj.pos)
		_saved_obj = {}

## 关卡搭好、晶洞埋好以后调用：放下本章的芯片
static func place(level: Node3D, world: VoxelWorld, ch: String) -> KeyRelic:
	_saved_obj = {}
	if not KEYS.has(ch):
		return null
	if _owned_before(ch):
		# 旧版存档：这一章已经打过了，芯片算拿到，进化补上
		var evo: String = KEYS[ch].get("evo", "")
		if evo != "" and not Evolutions.has(evo):
			Evolutions.grant(evo)
			GameState.upgrades_changed.emit()
		return null
	var pos := Vector3.INF
	# 1. 优先：换掉一颗“钻头钻得动”的回声晶核（之后的地下洞穴会优先挖到它）
	#    选离本章第一座重构点最近的（第一座重构点总在前半段，保证在 Boss 之前就能到）
	var anchor := Vector3.INF
	var sites := level.get_tree().get_nodes_in_group("rebuild_site")
	if not sites.is_empty():
		anchor = (sites[0] as Node3D).global_position
	elif level.has_method("spawn_position"):
		anchor = level.call("spawn_position")
	var best: Node3D = null
	for c in level.get_tree().get_nodes_in_group("scan_target"):
		if c is EchoCore and (c as EchoCore).locked_hint == "" and not c.is_queued_for_deletion():
			var d := (c as Node3D).global_position.distance_to(anchor)
			if d < 40.0 and (best == null or d < best.global_position.distance_to(anchor)):
				best = c
	if best:
		pos = best.global_position
		best.remove_from_group("scan_target")
		best.queue_free()
		GameState.set_echo_total(GameState.echo_found, maxi(GameState.echo_total - 1, 0))
	# 2. 没有合适的晶洞（工厂、城市这种人造的章节）：在第一座重构点附近堆一座塌方堆，芯片埋在里面
	if pos == Vector3.INF:
		pos = _rubble_mound(level, world, ch)
	if pos == Vector3.INF:
		push_warning("[Key] %s：找不到放芯片的地方" % ch)
		return null
	var k := KeyRelic.new()
	k.name = "KeyRelic"
	k.chapter = ch
	level.add_child(k)
	k.global_position = pos
	print("[Key] %s：%s 放在 %s" % [ch, key_name(ch), world.world_to_voxel(pos)])
	return k

static func _owned_before(ch: String) -> bool:
	if SaveGame.data.is_empty():
		return false
	var flags := SaveGame.data.get("flags", {}) as Dictionary
	if bool(flags.get("key_" + ch, false)):
		return true
	# 旧版（没有芯片的版本）存档：这一章已经通关，或者已经在更后面的章节
	var idx := ORDER.find(ch) + 1
	var clear_flag := "gh_clear" if idx == 1 else "ch%d_clear" % idx
	return bool(flags.get(clear_flag, false)) or int(SaveGame.data.get("chapter", 1)) > idx

## 塌方堆：土和碎岩堆成的小丘（平滑地形），顶上长草，芯片埋在正中
static func _rubble_mound(level: Node3D, world: VoxelWorld, ch: String) -> Vector3:
	var anchors: Array[Vector3] = []
	for n in level.get_tree().get_nodes_in_group("rebuild_site"):
		anchors.append((n as Node3D).global_position)
	if level.has_method("spawn_position"):
		anchors.append(level.call("spawn_position"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("key:" + ch)
	for a in anchors:
		var ac := world.world_to_voxel(a)
		for k in 24:
			var ang := rng.randf() * TAU
			var dist := rng.randi_range(8, 16)
			var x := ac.x + int(cos(ang) * dist)
			var z := ac.z + int(sin(ang) * dist)
			if not level.has_method("find_flat"):
				continue
			var f: Vector3i = level.call("find_flat", x, z, 3, 5)
			if f.x < 0 or absi(f.y - ac.y) > 3:
				continue
			# 头顶要空
			var clear := true
			for dy in range(0, 4):
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						if world.get_block(f + Vector3i(dx, dy, dz)) != Blocks.AIR:
							clear = false
			if not clear:
				continue
			var center := Vector3(f * VoxelWorld.CELL) + Vector3(1.0, 0.0, 1.0)
			var r := 6.5
			for vz in range(-8, 9):
				for vy in range(0, 8):
					for vx in range(-8, 9):
						var d := Vector3(vx, vy * 1.35, vz).length()
						if d > r:
							continue
						var t := Blocks.DIRT
						if d > r - 1.2 and vy >= 3:
							t = Blocks.GRASS
						elif rng.randf() < 0.18:
							t = Blocks.ROCK
						world.vset(Vector3i(center) + Vector3i(vx, vy, vz), t)
			# 芯片的小空腔
			for vz in range(-1, 2):
				for vy in range(1, 4):
					for vx in range(-1, 2):
						world.vset(Vector3i(center) + Vector3i(vx, vy, vz), Blocks.AIR)
			world.flush_dirty()
			return world.vcenter(Vector3i(center) + Vector3i(0, 2, 0))
	return Vector3.INF

## Boss 开打前调用：有芯片 → 封印碎掉，返回 true；没有 → 显示封印、把目标指向芯片，返回 false
static func unseal(level: Node, boss: Node3D, ch: String) -> bool:
	if has(ch):
		var seal := boss.get_node_or_null("RustSeal") as Node3D
		if seal:
			_shatter(seal)
			GameState.say("芯片在发热……封印和它共鸣了——碎了！")
		return true
	if boss.get_node_or_null("RustSeal") == null:
		boss.add_child(_make_seal())
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hint_t > 6.0:
		_hint_t = now
		GameState.say("它身上裹着一层厚厚的锈封印，什么都打不进去。……这一章的「%s」能和封印共鸣。按{scan}扫描，金色的标记就是它。" % key_name(ch))
		var kr := level.get_tree().get_first_node_in_group("key_relic") as Node3D
		if _saved_obj.is_empty():
			_saved_obj = {"text": GameState.objective_text, "pos": GameState.objective_pos}
		GameState.override_objective("先找到关键道具「%s」（按{scan}扫描）" % key_name(ch), kr.global_position if kr else Vector3.INF)
	return false

static func _make_seal() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "RustSeal"
	var sp := SphereMesh.new()
	sp.radius = 1.8
	sp.height = 3.6
	mi.mesh = sp
	mi.position.y = 1.2
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.42, 0.22, 0.28)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.4, 0.15)
	m.emission_energy_multiplier = 0.5
	m.rim_enabled = true
	m.rim = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := mi.create_tween().set_loops()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.05, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_SINE)
	return mi

static func _shatter(seal: Node3D) -> void:
	Sfx.play("break_glass", seal.global_position, 2.0, 0.0, 0.7)
	GameState.shake.emit(0.5)
	var w := seal.get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	if w:
		for i in 24:
			var d := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
			w._spawn_debris(seal.global_position + d * 1.6, Blocks.RUST)
	var tw := seal.create_tween()
	tw.tween_property(seal, "scale", Vector3.ONE * 1.6, 0.25)
	tw.parallel().tween_property(seal, "transparency", 1.0, 0.25)
	tw.tween_callback(seal.queue_free)
