class_name RustWorm
extends Node3D
## 第五章 Boss「锈海吞噬者」：一条盘在锈海底下的巨型锈虫——以前是清理海床的挖掘机器，锈蚀以后疯了。
##   · 它从锈海里弓身跃出，划一道大弧扎回海里，路过的地方连地皮一起啃掉（破坏！）
##   · 跃出几次以后，它会贴着灯塔岛浮上海面“喘口气”：长长的背脊像一座桥一样趴在岛边，背上三颗锈核在发光
##   · 趁它趴着，滚上它的背，撞碎一颗锈核 → 它痛得钻回海里，灯塔岛上被它啃掉的地方一块块飞回来（重构！）
##   · 三颗锈核全碎，它就散架了
## 不在水面上的时候碰到它的头会受伤；它跃到最高处会朝 PIX 吐锈弹。

signal defeated(e: Node)
signal core_broken(left: int)

enum St { IDLE, ARC, SURFACE, REST, DIVE, DEAD }

const N := 16
const SPACING := 1.25
const CORE_SEGS := [4, 8, 12]

var center := Vector3.ZERO      ## 灯塔岛中心（米，海面高度上）
var sea_y := 6.0
var island_r := 8.0             ## 灯塔岛半径（米）
var rest_y := 6.9               ## 趴着时身体中心的高度（背脊顶 = rest_y + 1.25，比岛面低一点点）
var rest_lines: Array = []      ## [[起点, 终点], ...]：趴下的位置（海面上，贴着岛边）
var protect: Array = [Blocks.BEDROCK, Blocks.HULL, Blocks.HULL_DARK, Blocks.METAL, Blocks.CRYSTAL, Blocks.GLASS, Blocks.LAMP,
	Blocks.RECEIVER, Blocks.RECEIVER_ON, Blocks.GOAL]
var active := false
var state: St = St.IDLE
var speed := 10.0
var world: VoxelWorld

var _segs: Array[AnimatableBody3D] = []
var _seg_r: Array[float] = []
var _cores: Array[Node3D] = []
var _core_areas: Array[Area3D] = []
var _trail: Array = []           ## 头走过的点 [位置, 累计距离]
var _trail_len := 0.0
var _path: Callable              ## s(米) -> 位置
var _path_len := 0.0
var _s := 0.0
var _t := 0.0
var _arcs_left := 0
var _rest_i := 0
var _spat := false
var _carve_t := 0.0
var _hit_cd := 0.0
var _warned := false
var _head_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _bar_fill: ColorRect
var _bar_layer: CanvasLayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 55
	world = get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color("a8552f")
	rust.roughness = 0.75
	var rust2 := StandardMaterial3D.new()
	rust2.albedo_color = Color("7a3b24")
	rust2.roughness = 0.8
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color("5a4a48")
	plate.metallic = 0.4
	plate.roughness = 0.5
	_head_mat = rust
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color("ffd166")
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color("ff7a3d")
	_eye_mat.emission_energy_multiplier = 3.0
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color("ff9a5a")
	core_mat.emission_enabled = true
	core_mat.emission = Color("ff6a2a")
	core_mat.emission_energy_multiplier = 2.5
	for i in N:
		var r := 1.5 if i == 0 else lerpf(1.25, 0.6, float(i) / (N - 1))
		var b := AnimatableBody3D.new()
		b.sync_to_physics = true
		b.collision_layer = 1
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = r
		cs.shape = ss
		b.add_child(cs)
		# 体素风的身体：一个大方块 + 背上的甲片
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * r * 1.75
		mi.mesh = bm
		mi.material_override = rust if i % 2 == 0 else rust2
		b.add_child(mi)
		var pl := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(r * 1.3, r * 0.35, r * 1.2)
		pl.mesh = pm
		pl.material_override = plate
		pl.position.y = r * 0.9
		b.add_child(pl)
		if i == 0:
			for sx in [-1.0, 1.0]:
				var eye := MeshInstance3D.new()
				var em := BoxMesh.new()
				em.size = Vector3(0.35, 0.35, 0.2)
				eye.mesh = em
				eye.material_override = _eye_mat
				eye.position = Vector3(sx * 0.6, 0.45, -1.35)
				b.add_child(eye)
			var jaw := MeshInstance3D.new()
			var jm := BoxMesh.new()
			jm.size = Vector3(2.0, 0.5, 1.2)
			jaw.mesh = jm
			jaw.material_override = plate
			jaw.position = Vector3(0, -0.8, -0.9)
			b.add_child(jaw)
		if i in CORE_SEGS:
			var core := Node3D.new()
			core.position.y = r * 1.15
			b.add_child(core)
			for k in 3:
				var c := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3(0.35, 0.8 - k * 0.15, 0.35)
				c.mesh = cm
				c.material_override = core_mat
				c.position = Vector3((k - 1) * 0.3, 0.25, (k % 2) * 0.2 - 0.1)
				c.rotation.z = (k - 1) * 0.35
				core.add_child(c)
			var a := Area3D.new()
			a.collision_layer = 0
			a.collision_mask = 2
			var acs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 0.95
			acs.shape = sph
			a.add_child(acs)
			core.add_child(a)
			_cores.append(core)
			_core_areas.append(a)
		add_child(b)
		b.top_level = true
		b.global_position = center + Vector3(0, -12.0 - i, 0)
		_segs.append(b)
		_seg_r.append(r)

func start() -> void:
	if active:
		return
	active = true
	_make_bar()
	_arcs_left = 2
	_next()

func cores_left() -> int:
	var n := 0
	for c in _cores:
		if c.visible:
			n += 1
	return n

# ================================================================ 路径

func _set_path(f: Callable, length: float) -> void:
	_path = f
	_path_len = length
	_s = 0.0

func _reset_trail(p: Vector3) -> void:
	_trail = [[p, 0.0]]
	_trail_len = 0.0

## 一道弧：从海面下 a 跃出，最高 h 米，扎回 b
func _arc(a: Vector3, b: Vector3, h: float) -> void:
	var L := a.distance_to(b) * 1.35 + h
	_set_path(func(s: float) -> Vector3:
		var t := clampf(s / L, 0.0, 1.0)
		return a.lerp(b, t) + Vector3.UP * sin(t * PI) * h, L)
	_reset_trail(a + (a - b).normalized() * N * SPACING)
	_spat = false

## 浮上来趴在 line 上：从 line 起点前方的海底斜着冒出来，沿 line 滑到终点
func _surface(line: Array) -> void:
	var p0: Vector3 = line[0]
	var p1: Vector3 = line[1]
	var dir := (p1 - p0).normalized()
	var under := p0 - dir * 5.0 + Vector3.DOWN * 4.0
	var L1 := under.distance_to(p0)
	var L2 := p0.distance_to(p1)
	_set_path(func(s: float) -> Vector3:
		if s < L1:
			return under.lerp(p0, s / L1)
		return p0 + dir * minf(s - L1, L2), L1 + L2)
	_reset_trail(under - dir * N * SPACING)

## 钻回海里：头朝前下方扎下去
func _dive() -> void:
	var h: Vector3 = _segs[0].global_position
	var fwd := (_segs[0].global_position - _segs[1].global_position)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var end := h + fwd * 7.0 + Vector3.DOWN * 7.0
	var L := h.distance_to(end) + N * SPACING + 2.0
	_set_path(func(s: float) -> Vector3:
		var t := clampf(s / (L - N * SPACING - 2.0), 0.0, 1.0)
		return h.lerp(end, t) + fwd * maxf(0.0, s - (L - N * SPACING - 2.0)) + Vector3.DOWN * maxf(0.0, s - (L - N * SPACING - 2.0)) * 0.6, L)

func _next() -> void:
	if state == St.DEAD:
		return
	if _arcs_left > 0:
		_arcs_left -= 1
		state = St.ARC
		# 弦不过岛心：偏开一点，正好从岛边啃过去
		var ang := _rng.randf() * TAU
		var off := Vector3(cos(ang + PI / 2.0), 0, sin(ang + PI / 2.0)) * island_r * _rng.randf_range(0.5, 0.8)
		var d := Vector3(cos(ang), 0, sin(ang)) * (island_r + 9.0)
		var a := center - d + off + Vector3.DOWN * 4.0
		var b := center + d + off + Vector3.DOWN * 4.0
		_arc(a, b, 7.0)
		Sfx.play("enemy_windup", a, 4.0, 0.0, 0.5)
	else:
		state = St.SURFACE
		_warned = false
		_surface(rest_lines[_rest_i % rest_lines.size()])
		_rest_i += 1

# ================================================================ 更新

func _physics_process(delta: float) -> void:
	if not active or state == St.DEAD:
		return
	_t += delta
	_hit_cd -= delta
	match state:
		St.ARC, St.SURFACE, St.DIVE:
			_s += delta * speed * (0.7 if state == St.SURFACE else 1.0)
			var head: Vector3 = _path.call(minf(_s, _path_len))
			_push_trail(head)
			if state == St.ARC:
				_carve(delta)
				_spit()
			if _s >= _path_len:
				if state == St.SURFACE:
					state = St.REST
					_t = 0.0
					GameState.say("它趴下来喘气了——快滚上它的背，撞碎发光的锈核！")
				else:
					_next()
		St.REST:
			# 趴着：轻轻起伏；快到时间了会抖一下，然后钻回去
			var bob := sin(_t * 2.0) * 0.08
			for i in N:
				_segs[i].global_position.y = rest_y + bob * (1.0 if i % 2 else -1.0)
			if _t > 4.5 and not _warned:
				_warned = true
				Sfx.play("enemy_windup", _segs[0].global_position, 4.0, 0.0, 0.6)
				FloatText.spawn(get_parent(), _segs[N / 2].global_position + Vector3.UP * 2.0, "它要钻回去了！", Color("ffb347"), 48, 1.2)
			if _t > 6.0:
				_arcs_left = 2 if cores_left() >= 2 else 3
				state = St.DIVE
				_dive()
			_check_cores()
	if state != St.REST:
		_place_segments()
	_check_bite()

func _push_trail(p: Vector3) -> void:
	var last: Vector3 = _trail[_trail.size() - 1][0]
	var d := last.distance_to(p)
	if d < 0.05:
		return
	_trail_len += d
	_trail.append([p, _trail_len])
	# 只保留够用的长度
	while _trail.size() > 2 and _trail_len - float(_trail[1][1]) > N * SPACING + 4.0:
		_trail.pop_front()

func _place_segments() -> void:
	var k := _trail.size() - 1
	for i in N:
		var want := _trail_len - i * SPACING
		while k > 0 and float(_trail[k - 1][1]) > want:
			k -= 1
		var p: Vector3
		if k <= 0:
			p = _trail[0][0]
		else:
			var a: Array = _trail[k - 1]
			var b: Array = _trail[k]
			var t := clampf((want - float(a[1])) / maxf(0.001, float(b[1]) - float(a[1])), 0.0, 1.0)
			p = (a[0] as Vector3).lerp(b[0], t)
		var seg := _segs[i]
		var prev := seg.global_position
		seg.global_position = p
		var mv := p - prev
		if mv.length() > 0.01:
			seg.get_child(1).rotation.y = atan2(-mv.x, -mv.z)

## 头部啃过的地方：连地皮一起挖掉（会记进破坏记录，打中锈核时重构波把它们还原）
func _carve(delta: float) -> void:
	_carve_t -= delta
	if _carve_t > 0.0 or world == null:
		return
	_carve_t = 0.06
	var h := _segs[0].global_position
	if h.y < sea_y - 1.5:
		return
	var n := world.carve_sphere(h, 1.7, protect)
	if n > 20:
		GameState.shake.emit(0.2)

func _spit() -> void:
	if _spat or _s < _path_len * 0.45:
		return
	_spat = true
	var p := GameState.player as Node3D
	if p == null:
		return
	var from := _segs[0].global_position
	for k in (2 if cores_left() >= 2 else 3):
		var tgt := p.global_position + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)) * float(k)
		tgt.y = center.y + 1.5
		RustBomb.launch(get_parent(), from, tgt, 1.3 + k * 0.2, null)
	Sfx.play("throw", from, 4.0, 0.0, 0.5)

func _check_bite() -> void:
	var p := GameState.player as MorphBall
	if p == null or p.is_invulnerable():
		return
	var hd := _segs[0].global_position.distance_to(p.global_position)
	if hd < _seg_r[0] + 0.55 and state != St.REST:
		p.hurt(_segs[0].global_position)
		return
	if state == St.ARC:
		for i in range(1, N):
			if _segs[i].global_position.distance_to(p.global_position) < _seg_r[i] + 0.4:
				p.hurt(_segs[i].global_position)
				return

func _check_cores() -> void:
	var p := GameState.player as MorphBall
	if p == null or _hit_cd > 0.0:
		return
	for k in _cores.size():
		if not _cores[k].visible:
			continue
		if _core_areas[k].overlaps_body(p) and (p.linear_velocity.length() > 3.5 or p.attack != ""):
			_break_core(k, p)
			return

func _break_core(k: int, p: MorphBall) -> void:
	_hit_cd = 1.0
	_cores[k].visible = false
	_core_areas[k].monitoring = false
	var at := _cores[k].global_position
	GameState.shake.emit(0.8)
	GameState.hitstop(0.12)
	Sfx.play("impact_big", at, 6.0, 0.0, 0.6)
	Sfx.play("break_glass", at, 4.0, 0.0, 0.7)
	if world:
		for i in 12:
			world.break_fx_at(at + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1), _rng.randf_range(-1, 1)), Blocks.RUST, false)
	# PIX 被甩回岛上
	var to_c := center - p.global_position
	to_c.y = 0.0
	p.linear_velocity = to_c.normalized() * 6.0 + Vector3.UP * 6.5
	p.launched(0.6)
	var left := cores_left()
	_update_bar()
	core_broken.emit(left)
	if left == 0:
		_die()
		return
	speed += 2.0
	_arcs_left = 2
	state = St.DIVE
	_dive()

func _die() -> void:
	state = St.DEAD
	if _bar_layer:
		_bar_layer.queue_free()
	# 一节节崩成锈块，沉进海里
	for i in N:
		var seg := _segs[i]
		var tw := seg.create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_callback(func() -> void:
			if world:
				for k in 4:
					world.break_fx_at(seg.global_position + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1.5), _rng.randf_range(-1, 1)), Blocks.RUST if k % 2 else Blocks.RUST, false)
			Sfx.play("break_hard", seg.global_position, 2.0, 0.1, 0.7)
			GameState.shake.emit(0.25))
		tw.tween_property(seg, "global_position", seg.global_position + Vector3.DOWN * 5.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(seg.queue_free)
	var p := GameState.player as Node3D
	var parent: Node = world if world else get_parent()
	get_tree().create_timer(N * 0.12 + 0.5).timeout.connect(func() -> void:
		for i in 40:
			PickupScript.spawn(parent, "coin", (p.global_position if p else center) + Vector3(0, 2.0, 0))
		for i in 8:
			PickupScript.spawn(parent, "energy", (p.global_position if p else center) + Vector3(0, 2.0, 0))
		GameState.enemies_defeated += 1
		defeated.emit(self)
		queue_free())

# ================================================================ UI

func _make_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 5
	get_tree().current_scene.add_child(_bar_layer)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-260, 96)
	root.custom_minimum_size = Vector2(520, 0)
	_bar_layer.add_child(root)
	var name_l := UIKit.label("锈海吞噬者", 26, Color("ffd9a8"), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_l)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.2, 0.8)
	bg.custom_minimum_size = Vector2(520, 16)
	root.add_child(bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("ff7a3d")
	_bar_fill.size = Vector2(520, 16)
	bg.add_child(_bar_fill)

func _update_bar() -> void:
	if _bar_fill:
		_bar_fill.size.x = 520.0 * cores_left() / 3.0

## 自动测试：直接进入趴下状态 / 直接撞碎一颗锈核
func debug_rest() -> void:
	_arcs_left = 0
	_next()
	_s = _path_len - 0.01

func debug_break(p: MorphBall) -> void:
	for k in _cores.size():
		if _cores[k].visible:
			_hit_cd = 0.0
			_break_core(k, p)
			return

const PickupScript := preload("res://scripts/voxel/pickup.gd")
