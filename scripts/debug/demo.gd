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

func _process(delta: float) -> void:
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
		c.global_position = center + Vector3(cos(a) * radius, height, sin(a) * radius)
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
	# 坑底蓄力，冲上坡道撞开木箱栅栏
	await put(Vector3i(17, G - 2, 73))
	face(Vector3.RIGHT)
	await wait(0.8)
	await charge_ram(Vector3.RIGHT, 1.0)
	steer(Vector3.RIGHT)
	await wait(1.6)
	steer(Vector3(1, 0, 0.3))
	await wait(1.2)
	steer(Vector3.ZERO)
	# 跳起来下砸，砸出一个坑
	var here := P.global_position
	P.teleport(here + Vector3.UP * 5.0)
	await wait(0.35)
	await pound()
	await wait(0.6)
	P.teleport(here + Vector3(0, 5.0, 2.5))
	await wait(0.35)
	await pound()
	await wait(1.0)
	# 重构波：坑一块块飞回来
	P.teleport(here + Vector3(-3.0, 1.0, -3.0))
	face(here - (here + Vector3(-3.0, 0, -3.0)), -0.55)
	await wait(0.4)
	L.call("reconstruct", here, 12.0, 1.6)
	await wait(3.0)
	# 重构点：瞭望台一块块建起来
	var sites := get_tree().get_nodes_in_group("rebuild_site")
	if not sites.is_empty():
		var s: RebuildSite = sites[0]
		GameState.add_matter(s.cost + 20)
		P.teleport(s.global_position + Vector3.UP * 0.6)
		await wait(0.3)
		await orbit(s.global_position, 11.0, 5.0, 7.0, 0.6, 1.3)

# ---------------------------------------------------------------- 第二章：战斗

func _seg_gw() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var start := W.voxel_top(AreaGearworks.SPAWN + Vector3i.DOWN) + Vector3.UP * 0.5
	P.teleport(start)
	face(Vector3.RIGHT)
	await wait(0.5)
	var foes: Array = []
	for k in 3:
		var e := Scrapling.new()
		L.add_child(e)
		e.global_position = start + Vector3(3.2 + k * 0.4, 0.2, -1.6 + k * 1.6)
		e.rotation.y = PI / 2.0
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
	var s := W.voxel_top(AreaCity.SPAWN + Vector3i.DOWN)
	await orbit(s + Vector3(10, 0, -10), 34.0, 16.0, 4.5, 2.2, 0.9)
	P.teleport(s + Vector3.UP * 0.5)
	face(Vector3.RIGHT)
	await wait(0.4)
	P.debug_boost = true
	steer(Vector3.RIGHT)
	await wait(2.5)
	steer(Vector3(1, 0, -0.5))
	await wait(1.5)
	P.debug_boost = false
	steer(Vector3.ZERO)
	await wait(0.5)

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
	P.teleport(W.voxel_center(Vector3i(K.C.x, K.GT, K.C.y + 14)) + Vector3.UP * 0.2)
	face(Vector3.FORWARD, -0.3)
	await wait(2.5)
	var h: RustHeart = L.heart
	h.waves_on = false
	for tries in 3:
		if h.phase != 1:
			break
		P.teleport(h.global_position + Vector3(0, -0.9, 6.0))
		face(Vector3.FORWARD, -0.25)
		await wait(0.5)
		await charge_ram(Vector3.FORWARD, 1.0)
		await wait(1.2)
	if h.phase == 1:
		h.debug_hit()
	await wait(3.0)

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
