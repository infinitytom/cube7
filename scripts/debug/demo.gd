extends Node
## 实机演示录制（配合 Movie Maker）：
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 --write-movie out.avi --fixed-fps 30 \
##     res://scenes/main.tscn -- --chapter=N --debugscript=res://scripts/debug/demo.gd --demo=<段落>
## 段落：gh（破坏与重构）/ gw（战斗）/ city（城市）/ rust（灯塔重建）/ core（终章 Boss）/ editor（关卡编辑器）

var main: Node
var P: MorphBall
var W: VoxelWorld
var L: Node
var cam: CameraRig
var seg := ""
var _follow := false
var _fdir := Vector3.FORWARD

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			seg = a.substr(7)
	main = get_parent()
	P = main.player
	W = main.world
	L = main.level
	cam = GameState.camera
	_run.call_deferred()

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

var _dbg_t := 0.0
func _process(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--demodbg"):
		_dbg_t += delta
		if _dbg_t > 0.5:
			_dbg_t = 0.0
			print("DBG t=%.1f P=%s v=%.1f camdist=%.2f yaw=%.2f pitch=%.2f hidden=%s" % [Time.get_ticks_msec() / 1000.0, W.to_v(P.global_position) / 2, P.linear_velocity.length(), cam._cur_dist, cam.yaw, cam._cur_pitch, str(P.get("_visual_hidden"))])
	# 演示里不显示 NOVA 对话框
	var hud = main.get("hud") if main else null
	if hud and hud.get("_nova"):
		(hud._nova as Control).modulate.a = 0.0
	# 跟拍：镜头慢慢转到 PIX 前进方向的后面
	if _follow and cam:
		var want := atan2(-_fdir.x, -_fdir.z)
		cam.yaw = lerp_angle(cam.yaw, want, 1.0 - exp(-3.0 * delta))

## 世界方向 → debug 输入（debug 模式下输入是世界坐标：x → +Z，-y → +X）
func steer(d: Vector3) -> void:
	d.y = 0.0
	if d.length() < 0.01:
		P.debug_input = Vector2.ZERO
		return
	d = d.normalized()
	_fdir = d
	P.debug_input = Vector2(d.z, -d.x)

func face(d: Vector3, pitch := -0.42) -> void:
	_fdir = Vector3(d.x, 0, d.z).normalized()
	cam.yaw = atan2(-_fdir.x, -_fdir.z)
	cam.pitch = pitch

func put(cell: Vector3i, lift := 0.5) -> void:
	P.teleport(W.voxel_top(cell + Vector3i.DOWN) + Vector3.UP * lift)
	await get_tree().physics_frame
	await get_tree().physics_frame

## 原地蓄力 secs 秒，朝 d 冲出去
func charge_ram(d: Vector3, secs := 1.0) -> void:
	steer(Vector3.ZERO)
	P.linear_velocity = Vector3.ZERO
	await wait(0.1)
	P.debug_ability_pressed = true
	P.debug_ability = true
	await wait(secs)
	steer(d)
	await get_tree().physics_frame
	P.debug_ability = false
	await wait(0.2)

## 空中下砸
func pound() -> void:
	P.apply_form(MorphBall.DRILL, false)
	await wait(0.25)
	P.debug_ability_pressed = true
	await wait(0.9)
	P.apply_form(MorphBall.BALL, false)

## 环绕航拍：center 为世界坐标，secs 秒内转 arc 弧度
func orbit(center: Vector3, radius: float, height: float, secs: float, a0 := 0.0, arc := 1.2) -> void:
	var c := Camera3D.new()
	c.fov = 60.0
	c.far = 3000.0
	add_child(c)
	c.current = true
	var t := 0.0
	while t < secs:
		var a := a0 + arc * (t / secs)
		var want := center + Vector3(cos(a) * radius, height, sin(a) * radius)
		# 别钻进墙里：从中心往机位打一条射线，被挡住就停在挡住的地方前面
		var from := center + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, want, 1)
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = (hit.position as Vector3) - (want - from).normalized() * 0.6
		c.global_position = c.global_position.lerp(want, 0.25) if t > 0.0 else want
		c.look_at(center + Vector3.UP * height * 0.25)
		await get_tree().process_frame
		t += get_process_delta_time()
	c.queue_free()
	(cam.get_child(0) as Camera3D).current = true

func _run() -> void:
	P.debug_override = true
	for e in get_tree().get_nodes_in_group("enemy"):
		if seg in ["gh", "city"]:
			e.queue_free()
	await wait(1.0)
	match seg:
		"gh":
			await _seg_gh()
		"ghsite":
			await _seg_ghsite()
		"gw":
			await _seg_gw()
		"city":
			await _seg_city()
		"rust":
			await _seg_rust()
		"core":
			await _seg_core()
		"editor":
			await _seg_editor()
	get_tree().quit()

# ---------------------------------------------------------------- 第一章：破坏与重构

func _seg_gh() -> void:
	const G := AreaGreenhouse.G
	# 花园小路上蓄力，撞穿一面木箱墙
	W.fill_box(Vector3i(37, G, 71), Vector3i(37, G + 2, 76), Blocks.CRATE)
	W.fill_box(Vector3i(38, G, 72), Vector3i(38, G + 1, 75), Blocks.CRATE)
	await put(Vector3i(29, G, 73))
	face(Vector3.RIGHT, -0.38)
	await wait(1.2)
	await charge_ram(Vector3.RIGHT, 1.0)
	steer(Vector3.ZERO)
	# 撞穿木箱墙以后刹住（别一路滚进深坑）
	var stop_x := W.voxel_center(Vector3i(41, G, 73)).x
	for k in 90:
		if P.global_position.x > stop_x:
			break
		await get_tree().physics_frame
	P.linear_velocity *= 0.15
	if OS.get_cmdline_user_args().has("--demodbg"):
		var left := 0
		for z in range(71, 77):
			for y in range(G, G + 3):
				if W.get_block(Vector3i(37, y, z)) != Blocks.AIR: left += 1
		print("DBG crates left in wall: ", left)
	await wait(0.8)
	# 跳起来下砸两次，砸出一个坑
	var here := W.voxel_top(Vector3i(43, G - 1, 73))
	P.teleport(here + Vector3.UP * 5.0)
	await wait(0.35)
	await pound()
	await wait(0.5)
	P.teleport(here + Vector3(0.8, 5.0, 0.4))
	await wait(0.35)
	await pound()
	await wait(0.8)
	# 退后几步看：重构波让坑一块块飞回来
	P.teleport(here + Vector3(-4.0, 0.6, 0))
	face(Vector3.RIGHT, -0.6)
	await wait(0.8)
	L.call("reconstruct", here, 10.0, 1.6)
	await wait(3.2)

## 重构点：瞭望台一块块建起来（单独一段）
func _seg_ghsite() -> void:
	var sites := get_tree().get_nodes_in_group("rebuild_site")
	if sites.is_empty():
		return
	var s: RebuildSite = sites[0]
	GameState.add_matter(s.cost + 20)
	P.teleport(s.global_position + Vector3(0, 0.6, 3.0))
	await wait(0.4)
	P.teleport(s.global_position + Vector3.UP * 0.6)
	await wait(0.2)
	await orbit(s.global_position, 12.0, 8.0, 7.5, 0.6, 1.3)

# ---------------------------------------------------------------- 第二章：战斗

func _seg_gw() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var start := W.voxel_top(AreaGearworks.SPAWN + Vector3i.DOWN) + Vector3.UP * 0.5
	P.teleport(start)
	cam.distance = 5.2
	face(Vector3.RIGHT, -0.3)
	await wait(0.5)
	var foes: Array = []
	for k in 3:
		var e := Scrapling.new()
		L.add_child(e)
		e.global_position = start + Vector3(3.6 + k * 0.5, 0.2, -1.4 + k * 1.4)
		e.rotation.y = -PI / 2.0
		foes.append(e)
	await wait(1.0)
	for k in 3:
		var alive: Array = foes.filter(func(x) -> bool: return is_instance_valid(x) and x.state != Scrapling.St.DEAD)
		if alive.is_empty():
			break
		var tgt: Node3D = alive[0]
		var d := tgt.global_position - P.global_position
		face(d)
		await charge_ram(d, 0.95)
		steer(d)
		await wait(0.9)
		steer(Vector3.ZERO)
		await wait(0.6)
	await wait(1.2)

# ---------------------------------------------------------------- 第四章：城市

func _seg_city() -> void:
	# 天空城市：先绕着集市穹顶航拍，再看议会尖塔
	var dome := W.voxel_center(AreaCity.DOME_B)
	P.teleport(W.voxel_top(AreaCity.SPAWN + Vector3i.DOWN) + Vector3.UP * 0.5)
	P.freeze = true
	await orbit(dome, 30.0, 14.0, 4.5, 2.4, 0.8)
	var spire := W.voxel_center(AreaCity.SPIRE)
	await orbit(spire + Vector3.UP * 6.0, 28.0, 8.0, 4.0, 0.6, 0.7)

# ---------------------------------------------------------------- 第五章：灯塔从锈海里重建

func _seg_rust() -> void:
	var c := W.voxel_center(Vector3i(AreaRust.D_C.x, AreaRust.G, AreaRust.D_C.y))
	P.teleport(c + Vector3(-7.0, 1.0, 0))
	P.freeze = true
	L.call("_build_lighthouse", false)
	await orbit(c, 26.0, 9.0, 11.0, 2.6, 1.4)

# ---------------------------------------------------------------- 终章：锈蚀之心

func _seg_core() -> void:
	const K := preload("res://scripts/levels/area_core.gd")
	var top := W.voxel_center(Vector3i(K.C.x, K.GT, K.C.y + 14)) + Vector3.UP * 0.2
	P.teleport(top)
	face(Vector3.FORWARD, -0.25)
	await wait(2.5)
	var h: RustHeart = L.heart
	h.waves_on = false
	P.teleport(h.global_position + Vector3(0, -0.9, 6.0))
	face(Vector3.FORWARD, -0.22)
	await wait(0.6)
	await charge_ram(Vector3.FORWARD, 1.0)
	await wait(1.2)
	if h.phase == 1:
		h.debug_hit()
	P.teleport(top)
	P.linear_velocity = Vector3.ZERO
	await orbit(h.global_position + Vector3.UP * 2.0, 13.0, 3.0, 4.5, 1.2, 1.0)

# ---------------------------------------------------------------- 关卡编辑器

func _seg_editor() -> void:
	var ed: LevelEditor = main.find_children("*", "LevelEditor", false, false)[0]
	await wait(0.6)
	# 搭一段台阶和一面墙
	for i in 6:
		for h in i / 2 + 1:
			ed.cursor = Vector3i(28 + i, LevelData.BASE_Y + h, 34)
			ed._place()
			await wait(0.05)
	ed.sel[0] = 20
	ed._refresh_bar()
	for z in range(31, 38):
		for y in 3:
			ed.cursor = Vector3i(40, LevelData.BASE_Y + y, z)
			ed._place()
		await wait(0.08)
	ed._toggle_cat()
	ed.sel[1] = 9
	ed._refresh_bar()
	ed.cursor = Vector3i(44, LevelData.BASE_Y, 36)
	ed._place()
	await wait(0.8)
	ed._start_test()
	await wait(3.0)
