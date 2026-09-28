class_name MorphBall
extends RigidBody3D
## 主角 PIX：可变形的维护探测球。
## 滚动手感致敬《平衡球》：真实惯性，形态不同重量不同，同一段路换形态就是另一种走法。

enum { BALL, DRILL, BUBBLE }

## 三种形态，各自有不同的跳法和打法（参考马里奥：跳跃就是动词，每种形态换一套动词）
##   滚球：快、中等跳跃（按住跳得更高），冲撞攻击——正面有盾的敌人要绕到侧后撞
##   钻头：重、只能小跳，地面按住钻掘、空中按下砸地（震翻周围敌人、压得动压力板）
##   气泡：轻、跳得最高，空中还能再喷两次、按住跳滑翔，气浪攻击把敌人推开掀翻
## jump = 起跳速度（米/秒）；air_jumps = 空中额外跳跃次数；glide = 按住跳时的最大下落速度
const FORMS: Array[Dictionary] = [
	{"id": "ball", "name": "滚球", "ability": "冲撞", "jump_name": "跳跃（按住更高）", "color": Color("46c3ff"),
		"mass": 1.0, "shape": "sphere", "radius": 0.48, "roll": true,
		"torque": 8.0, "ground_force": 2.5, "air_force": 3.0, "max_speed": 7.0, "boost_speed": 11.0,
		"jump": 5.6, "air_jumps": 0, "glide": 0.0, "gravity": 1.25,
		"friction": 0.9, "bounce": 0.12, "lin_damp": 0.08, "ang_damp": 0.6},
	{"id": "drill", "name": "钻头", "ability": "钻掘 · 空中下砸", "jump_name": "小跳", "color": Color("ffb03b"),
		"mass": 3.0, "shape": "sphere", "radius": 0.46, "roll": false,
		"torque": 0.0, "ground_force": 9.0, "air_force": 3.0, "max_speed": 4.0, "boost_speed": 5.5,
		"jump": 3.8, "air_jumps": 0, "glide": 0.0, "gravity": 1.0,
		"friction": 0.5, "bounce": 0.0, "lin_damp": 1.2, "ang_damp": 3.0},
	{"id": "bubble", "name": "气泡", "ability": "气浪", "jump_name": "跳跃 · 空中再跳 · 按住滑翔", "color": Color("c9a6ff"),
		"mass": 0.3, "shape": "sphere", "radius": 0.5, "roll": true,
		"torque": 3.0, "ground_force": 4.0, "air_force": 4.5, "max_speed": 4.5, "boost_speed": 6.0,
		"jump": 5.2, "air_jumps": 2, "glide": 1.1, "gravity": 0.45,
		"friction": 0.6, "bounce": 0.5, "lin_damp": 1.0, "ang_damp": 1.0},
]

const IMPACT_MIN := 1.8
## 主角整体缩放：体素改成 0.25 米后，主角相对世界显得更小巧
const BODY := 0.78
const DASH_SPEED := 11.5
const GRAB_RANGE := 2.8

var form: int = BALL
var form_locked := false
var grounded := false
var world: VoxelWorld

## 自动测试 / 调试用的输入覆盖
var debug_override := false
var debug_input := Vector2.ZERO
var debug_ability := false
var debug_ability_pressed := false
var debug_boost := false
var debug_jump_pressed := false
var debug_jump_held := false

## 攻击状态（敌人读取）："" / "ram" 冲撞 / "drill" 钻 / "pound" 下砸
var attack := ""
var _dash_t := 0.0
var _air_jumps := 0
var _jump_rising := false
var _invuln := 0.0
const POUND_RADIUS := 3.0
const WAVE_RADIUS := 3.6

var _ground_timer := 0.0
var _prev_vel := Vector3.ZERO
var _impacts: Array = []
var _ability_cd := 0.0
var _drill_timer := 0.0
var _puffs := 0
var _pounding := false
var _held: Node = null
var _move_dir := Vector3(1, 0, 0)
var _visual_root: Node3D
var _visuals: Array[Node3D] = []
var _drill_bit: Node3D
var _drilling_t := 0.0
var _drill_fx: CPUParticles3D
var _bit_spin := 0.0
var _drill_down := false
var _magnet_stuck := false
var _teleport := false
var _teleport_pos := Vector3.ZERO
var _reset_rot := false
var _shape_node: CollisionShape3D
var _no_snap := 0.0          ## 被弹跳垫等发射后的一小段时间内不贴地
var _roll_sound: AudioStreamPlayer3D

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	can_sleep = false
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16
	physics_material_override = PhysicsMaterial.new()
	_shape_node = get_node_or_null("CollisionShape3D")
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	_visual_root.scale = Vector3.ONE * BODY
	add_child(_visual_root)
	_build_visuals()
	_build_face()
	_roll_sound = AudioStreamPlayer3D.new()
	var rs := load("res://audio/sfx/roll.ogg") as AudioStreamOggVorbis
	if rs:
		rs.loop = true
		_roll_sound.stream = rs
		_roll_sound.bus = "SFX"
		_roll_sound.volume_db = -80.0
		add_child(_roll_sound)
		_roll_sound.play()
	GameState.player = self
	world = get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	apply_form(BALL, false)

# ---------------------------------------------------------------- 输入

func _move_input() -> Vector2:
	if debug_override:
		return debug_input
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")

func _ability_held() -> bool:
	return debug_ability if debug_override else Input.is_action_pressed("ability")

func _ability_pressed() -> bool:
	if debug_override:
		var p := debug_ability_pressed
		debug_ability_pressed = false
		return p
	return Input.is_action_just_pressed("ability")

func _jump_pressed() -> bool:
	if debug_override:
		var p := debug_jump_pressed
		debug_jump_pressed = false
		return p
	return Input.is_action_just_pressed("jump")

func _jump_held() -> bool:
	return debug_jump_held if debug_override else Input.is_action_pressed("jump")

func _boost_held() -> bool:
	return debug_boost if debug_override else Input.is_action_pressed("boost")

## 把摇杆输入转换到镜头朝向（只取水平方向）
func _camera_dir(inp: Vector2) -> Vector3:
	var forward := Vector3(1, 0, 0)
	var right := Vector3(0, 0, 1)
	var cam := GameState.camera
	if cam and not debug_override:
		var yaw: float = cam.get("yaw")
		forward = Vector3(-sin(yaw), 0, -cos(yaw))
		right = Vector3(cos(yaw), 0, -sin(yaw))
	return right * inp.x + forward * (-inp.y)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("form_next"):
		cycle_form(1)
	elif event.is_action_pressed("form_prev"):
		cycle_form(-1)
	for i in FORMS.size():
		if event.is_action_pressed("form_%d" % (i + 1)):
			request_form(i)
	if event.is_action_pressed("grab"):
		toggle_grab()
	if event.is_action_pressed("respawn"):
		GameState.respawn()

# ---------------------------------------------------------------- 形态

func cycle_form(step: int) -> void:
	var i := form
	for n in FORMS.size():
		i = posmod(i + step, FORMS.size())
		if GameState.unlocked_forms[i]:
			request_form(i)
			return

func request_form(i: int) -> void:
	if form_locked:
		GameState.say("这段轨道要求保持当前形态，只能在变形站切换。")
		return
	if not GameState.unlocked_forms[i] or i == form:
		return
	apply_form(i, true)

func apply_form(i: int, fx: bool) -> void:
	var f: Dictionary = FORMS[i]
	form = i
	mass = f.mass
	gravity_scale = f.gravity
	linear_damp = f.lin_damp
	angular_damp = f.ang_damp
	physics_material_override.friction = f.friction
	physics_material_override.bounce = f.bounce
	lock_rotation = not f.roll
	if lock_rotation:
		_reset_rot = true
	if f.shape == "box":
		var b := BoxShape3D.new()
		b.size = Vector3.ONE * 0.9
		_shape_node.shape = b
	else:
		var s := SphereShape3D.new()
		s.radius = f.radius * BODY
		_shape_node.shape = s
	for k in _visuals.size():
		_visuals[k].visible = k == i
	_pounding = false
	attack = ""
	if fx:
		_visual_root.scale = Vector3.ONE * 0.45
		var tw := create_tween()
		tw.tween_property(_visual_root, "scale", Vector3.ONE * BODY, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_burst(f.color)
		Sfx.play("morph", Vector3.INF, -4.0)
		Sfx.play("pix_morph", Vector3.INF, -9.0, 0.12)
	GameState.form_changed.emit(i)
	if _face:
		_set_eye_color(f.color)

# ---------------------------------------------------------------- 物理

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _teleport:
		_teleport = false
		state.transform = Transform3D(Basis(), _teleport_pos)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_prev_vel = Vector3.ZERO
		reset_physics_interpolation.call_deferred()
		return
	if _reset_rot:
		_reset_rot = false
		state.transform = Transform3D(Basis(), state.transform.origin)
		state.angular_velocity = Vector3.ZERO
	var on_ground := false
	var wall := false
	var best_impact := {}
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		if n.y > 0.55:
			on_ground = true
		elif n.y < 0.3:
			wall = true
		var col := state.get_contact_collider_object(i)
		if col is Node and (col as Node).is_in_group("voxel_body"):
			var speed := -_prev_vel.dot(n)
			if speed > IMPACT_MIN and speed > float(best_impact.get("speed", 0.0)):
				best_impact = {"point": state.get_contact_collider_position(i), "normal": n, "speed": speed, "vel": _prev_vel}
	if not best_impact.is_empty():
		_impacts.append(best_impact)
	# 空中撞墙：滚动的旋转会被墙面摩擦转成向上的速度（“爬墙”），球越小越明显——撞墙时去掉旋转
	if wall and not on_ground:
		state.angular_velocity *= 0.2
		if state.linear_velocity.y > _prev_vel.y + 0.5 and not _jumped_now:
			state.linear_velocity.y = _prev_vel.y
	_jumped_now = false
	if on_ground:
		_ground_timer = 0.12
	grounded = on_ground
	_prev_vel = state.linear_velocity

## 小台阶辅助：体素只有 0.25 米，地上难免有一两格的小坎（树根、崩边、坑）。
## 往前推却被矮坎挡住时，轻轻把球托上去，不用专门跳。
var _step_cd := 0.0

func _step_assist(dir: Vector3, delta: float) -> void:
	_step_cd -= delta
	if _step_cd > 0.0 or dir.length() < 0.3 or not grounded or _jump_rising or not allow_step:
		return
	var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var d := dir.normalized()
	if vh.dot(d) > 1.2:
		return
	var r: float = FORMS[form].radius * BODY
	var space := get_world_3d().direct_space_state
	var base := global_position + Vector3.DOWN * (r - 0.06)
	var low := PhysicsRayQueryParameters3D.create(base, base + d * (r + 0.2), 1 | 8, [get_rid()])
	if space.intersect_ray(low).is_empty():
		return
	var hi_o := global_position + Vector3.DOWN * r + Vector3.UP * 0.34
	var high := PhysicsRayQueryParameters3D.create(hi_o, hi_o + d * (r + 0.3), 1 | 8, [get_rid()])
	if not space.intersect_ray(high).is_empty():
		return
	# 坎的上方要有地方站
	linear_velocity = Vector3(d.x * maxf(vh.length(), 1.6), 3.0, d.z * maxf(vh.length(), 1.6))
	_no_snap = 0.15
	_step_cd = 0.25
	_jumped_now = true

var allow_step := true

func _physics_process(delta: float) -> void:
	_ground_timer -= delta
	_ability_cd -= delta
	if not _impacts.is_empty():
		_handle_impacts()
	# 冻结时（过场动画）物理不跑，传送也不会生效——这时不能判定掉落，否则会每帧“复活”一次
	if global_position.y < GameState.kill_y and not freeze:
		GameState.respawn()
		return

	var f: Dictionary = FORMS[form]
	var inp := _move_input()
	var dir := _camera_dir(inp)
	if dir.length() > 0.15:
		_move_dir = dir.normalized()

	# 形态能力（可能改变重力/阻尼，所以先处理）
	_update_ability(delta, f, dir)

	var boosting := _boost_held()
	var max_s: float = f.boost_speed if boosting else f.max_speed
	var mul := 1.6 if boosting else 1.0
	if dir.length() > 0.05:
		var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
		var d := dir.normalized() * minf(dir.length(), 1.0)
		if vh.dot(d.normalized()) < max_s:
			if f.roll:
				apply_torque(Vector3.UP.cross(d) * float(f.torque) * mass * mul)
			var a: float = f.ground_force if _ground_timer > 0.0 else f.air_force
			apply_central_force(d * a * mass * mul)

	_update_jump(delta, f)
	_update_attack_state(delta)
	_step_assist(dir, delta)

	if _ground_timer > 0.0:
		_puffs = 0
		_air_jumps = int(f.air_jumps)
	_no_snap -= delta
	_snap_to_ground()
	# 滚动声：贴地时随速度变大、变尖
	if _roll_sound and _roll_sound.stream:
		var sp := linear_velocity.length() if _ground_timer > 0.0 and not lock_rotation else 0.0
		var vol := clampf(sp / 9.0, 0.0, 1.0)
		_roll_sound.volume_db = linear_to_db(maxf(vol * 0.8, 0.0001))
		_roll_sound.pitch_scale = 0.7 + vol * 0.7

	# 抓着的物件跟随头顶
	if _held and is_instance_valid(_held):
		(_held as Node3D).global_position = global_position + Vector3.UP * 0.95
	elif _held:
		_held = null

	# 锁定旋转的形态：让外观朝向移动方向
	if lock_rotation and _visuals[form].visible:
		var target := Basis.looking_at(_move_dir, Vector3.UP)
		if form == DRILL and _drill_down:
			target = target * Basis(Vector3.RIGHT, -1.35)   # 往下钻：钻头转向地面
		_visuals[form].basis = _visuals[form].basis.slerp(target, 1.0 - exp(-12.0 * delta))

## 贴地：刚离开地面（坡顶、小台阶）时，如果正下方很近处还有地面，就压回去，
## 避免高速过坡顶时整个飞出去。真正的断崖（下方没有地面）不受影响。
func _snap_to_ground() -> void:
	if grounded or _no_snap > 0.0 or _jump_rising or form == BUBBLE:
		return
	if _ground_timer <= 0.0:
		return
	if linear_velocity.y <= 0.0:
		return
	var r: float = FORMS[form].radius * BODY
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * (r + 0.45), 1 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		# 去掉离开地面方向的速度分量
		var away := linear_velocity.dot(n)
		if away > 0.0:
			linear_velocity -= n * away

## 被弹跳垫、光桥发射器等主动发射时调用
func launched(secs := 0.5) -> void:
	_no_snap = secs

## 跳跃：起跳 / 可变高度（松开跳跃键时截短上升）/ 气泡的空中再跳与滑翔
func _update_jump(delta: float, f: Dictionary) -> void:
	if not GameState.allow_jump:
		return
	var pressed := _jump_pressed()
	var held := _jump_held()
	if pressed:
		if _ground_timer > 0.0:
			_do_jump(float(f.jump))
			Sfx.play("jump_" + str(f.id), global_position, -6.0, 0.06)
		elif _air_jumps > 0:
			_air_jumps -= 1
			_do_jump(float(f.jump) * 0.8)
			_burst(f.color)
			Sfx.play("jump_bubble", global_position, -4.0, 0.1)
	if _jump_rising:
		if linear_velocity.y <= 0.0:
			_jump_rising = false
		elif not held:
			# 马里奥式可变跳：提前松开就少跳一点
			linear_velocity.y *= 0.5
			_jump_rising = false
	# 滑翔：按住跳下落时限速
	var glide: float = f.glide
	if glide > 0.0 and held and linear_velocity.y < -glide and _ground_timer <= 0.0:
		linear_velocity.y = move_toward(linear_velocity.y, -glide, 30.0 * delta)

var _jumped_now := false

func _do_jump(v: float) -> void:
	_jumped_now = true
	_ground_timer = 0.0
	_jump_rising = true
	_no_snap = 0.25
	linear_velocity.y = v

## 攻击判定窗口：冲撞持续 0.35 秒；滚得够快本身也算冲撞
func _update_attack_state(delta: float) -> void:
	_dash_t -= delta
	_invuln -= delta
	if _invuln > 0.0:
		_visual_root.visible = fmod(_invuln, 0.16) > 0.08
	elif not _visual_root.visible and _hidden_by == "":
		_visual_root.visible = true
	match form:
		BALL:
			var fast := Vector3(linear_velocity.x, 0, linear_velocity.z).length() > 6.0
			attack = "ram" if _dash_t > 0.0 or fast else ""
		DRILL:
			attack = "pound" if _pounding else ("drill" if _ability_held() and _ground_timer > 0.0 else "")
		BUBBLE:
			attack = ""

func _update_ability(delta: float, f: Dictionary, dir: Vector3) -> void:
	var pressed := _ability_pressed()
	var held := _ability_held()
	match form:
		BALL:
			if pressed and _ability_cd <= 0.0:
				_ability_cd = 0.8
				_dash_t = 0.35
				var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
				apply_central_impulse((_move_dir * DASH_SPEED - vh) * mass)
				_burst(f.color)
				Sfx.play("dash", global_position, -2.0)
		DRILL:
			if _ground_timer <= 0.0 and pressed and not _pounding:
				# 空中下砸
				_pounding = true
				linear_velocity = Vector3(0, -16.0, 0)
				Sfx.play("dash", global_position, -4.0, 0.0)
			elif _pounding and _ground_timer > 0.0:
				_pounding = false
				_pound_land()
			elif held and _ground_timer > 0.0:
				_drill_timer -= delta
				_drilling_t = 0.15
				if _drill_timer <= 0.0:
					_drill_timer = 0.09
					_drill(dir)
		BUBBLE:
			if pressed and _ability_cd <= 0.0:
				_ability_cd = 0.7
				_wave()

## 下砸落地：砸碎脚下的可破坏方块，震翻周围的敌人
func _pound_land() -> void:
	GameState.shake.emit(0.45)
	Sfx.play("thud", global_position, 2.0, 0.05)
	Sfx.play("break_hard", global_position, -2.0, 0.1)
	_ring_fx(FORMS[DRILL].color, POUND_RADIUS)
	if world:
		world.break_sphere(global_position + Vector3.DOWN * 0.6, 1.0, "impact", 10.0, Vector3.DOWN)
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := (e as Node3D).global_position.distance_to(global_position)
		if d < POUND_RADIUS:
			e.call("on_pound", global_position)

## 气浪：把周围的敌人、物件推开
func _wave() -> void:
	_ring_fx(FORMS[BUBBLE].color, WAVE_RADIUS)
	Sfx.play("wave", global_position, -2.0, 0.05)
	# 气浪能把附近的火吹灭
	if world and world.fire and world.fire.extinguish_sphere(global_position, WAVE_RADIUS) > 0:
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 0.8, "火吹灭了", Color("9fe8ff"), 40, 1.2)
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := (e as Node3D).global_position.distance_to(global_position)
		if d < WAVE_RADIUS:
			e.call("on_wave", global_position)
	for sc in get_tree().get_nodes_in_group("seed_cube"):
		if (sc as Node3D).global_position.distance_to(global_position) < WAVE_RADIUS:
			sc.call("on_wave", global_position)
	for n in get_tree().get_nodes_in_group("usable_item"):
		var rb := n as RigidBody3D
		if rb and rb.global_position.distance_to(global_position) < WAVE_RADIUS and not rb.get("held"):
			var away := (rb.global_position - global_position)
			away.y = 0.0
			rb.apply_central_impulse((away.normalized() * 4.0 + Vector3.UP * 2.0) * rb.mass)

## 受伤：扣一格护盾、击退、短暂无敌闪烁
func hurt(from: Vector3, n := 1) -> void:
	if _invuln > 0.0:
		return
	_invuln = 1.4
	var away := global_position - from
	away.y = 0.0
	linear_velocity = away.normalized() * 6.0 + Vector3.UP * 4.0
	_no_snap = 0.4
	Sfx.play("hurt", Vector3.INF, -2.0, 0.05)
	Sfx.play("pix_hurt", Vector3.INF, -8.0, 0.1)
	GameState.shake.emit(0.35)
	GameState.damage(n)

func is_invulnerable() -> bool:
	return _invuln > 0.0

## 地面上扩散的一圈光环
func _ring_fx(color: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 24
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.8)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = global_position + Vector3.DOWN * 0.35
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)

func _drill(dir: Vector3) -> void:
	if world == null:
		return
	var n := 0
	if dir.length() < 0.15:
		# 静止时向下钻：只钻得动松土/砂，普通地面钻不下去（避免把自己困在坑里）
		n = world.break_sphere(global_position + Vector3.DOWN * 0.5, 0.62, "drill", 1.0, Vector3.DOWN, true)
	else:
		# 往前钻出一条不规则的隧道：比主角宽一圈，洞壁参差不齐
		var d := _move_dir.normalized()
		n = world.break_sphere(global_position + d * 0.6 + Vector3.UP * 0.08, 0.64, "drill", 1.0, d)
	if n > 0:
		GameState.shake.emit(0.05)
		Sfx.play("drill", global_position, -6.0, 0.1)

func _handle_impacts() -> void:
	var list := _impacts.duplicate()
	_impacts.clear()
	if world == null:
		return
	for imp in list:
		var speed: float = imp.speed
		var n: Vector3 = imp.normal
		var radius := clampf(0.45 + speed * 0.065, 0.5, 1.3)
		var center: Vector3 = imp.point - n * 0.25
		var count := world.break_sphere(center, radius, "impact", speed, imp.vel)
		if count == 0 and speed > 4.0:
			Sfx.play("thud", global_position, linear_to_db(clampf(speed / 12.0, 0.2, 1.0)), 0.1)
			_hardness_hint(center, speed)
		if count >= 2:
			# 撞穿：保留大部分速度继续前进
			linear_velocity = (imp.vel as Vector3) * 0.8

## 撞上撞不开的方块时，在撞击处飘一句提示，让玩家明白“这块为什么没碎”
var _hint_t := 0.0

func _hardness_hint(at: Vector3, speed: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hint_t < 1.6:
		return
	var t := world.get_block(world.world_to_voxel(at))
	if t == Blocks.AIR:
		return
	_hint_t = now
	var text := ""
	var col := Color.WHITE
	if Blocks.impact[t] >= 0.0:
		text = "再快一点！%d%%" % mini(int(speed / Blocks.impact[t] * 100.0), 99)
		col = UIKit.ACCENT2
	elif Blocks.drill[t] == 1:
		text = "要用钻头" if not GameState.unlocked_forms[DRILL] else "换钻头钻开"
		col = Color("ffb03b")
	else:
		text = "打不坏"
		col = Color("c4c8ee")
	FloatText.spawn(get_parent(), at + Vector3.UP * 0.6, text, col, 48)
	set_mood("hurt", 0.4)

## 复活（由 GameState.respawn 调用）
func respawn_at(pos: Vector3, form_idx: int, locks: bool) -> void:
	if _held:
		_release_held(Vector3.ZERO)
	teleport(pos)
	if form_idx >= 0 and form_idx != form:
		apply_form(form_idx, false)
	form_locked = locks

## 瞬移（不放下手里的物件）
func teleport(pos: Vector3) -> void:
	_teleport_pos = pos
	_teleport = true
	if freeze:
		global_position = pos

# ---------------------------------------------------------------- 抓取 / 投掷

func toggle_grab() -> void:
	if _held:
		var throw_dir := _move_dir
		var cam := GameState.camera
		if cam:
			var yaw: float = cam.get("yaw")
			throw_dir = Vector3(-sin(yaw), 0, -cos(yaw))
		# 轻抛：约 2~3 米远，配合插槽吸附更容易放准
		_release_held(throw_dir * 3.5 + Vector3.UP * 3.0 + linear_velocity * 0.4)
		Sfx.play("throw", global_position, -4.0)
		return
	# 牵引光束：4.5 米内最近的物件会被“吸”过来，不用精确贴上去
	var best: Node3D = null
	var best_d := GRAB_RANGE + 1.7
	for n in get_tree().get_nodes_in_group("usable_item"):
		var d := (n as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		_held = best
		best.call("set_held", true)
		Sfx.play("grab", global_position, -4.0)
		set_mood("happy", 0.6)
		var from := best.global_position
		var tw := create_tween()
		tw.tween_method(func(k: float) -> void:
			if is_instance_valid(best) and _held == best:
				best.global_position = from.lerp(global_position + Vector3.UP * 0.95, k), 0.0, 1.0, 0.18)
	else:
		Sfx.play("pix_curious", Vector3.INF, -10.0, 0.05)
		var now := Time.get_ticks_msec() / 1000.0
		if now - _no_grab_said > 30.0:
			_no_grab_said = now
			GameState.say("附近没有能抓的东西。只有带发光描边的物件可以抓起来。")

func _release_held(vel: Vector3) -> void:
	if _held and is_instance_valid(_held):
		_held.call("set_held", false)
		(_held as RigidBody3D).linear_velocity = vel
	_held = null

var _hidden_by := ""
var _no_grab_said := -100.0

func set_visual_hidden(v: bool) -> void:
	_hidden_by = "camera" if v else ""
	_visual_root.visible = not v

func is_holding() -> bool:
	return _held != null

# ---------------------------------------------------------------- 外观

func _mat(color: Color, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.35
	m.metallic = 0.3
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.rim_enabled = true
		m.rim = 0.8
	return m

func _mesh(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s

func _ring(color: Color, parent: Node3D, r := 0.49) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - 0.035
	t.outer_radius = r + 0.035
	return _mesh(t, _mat(color, 3.0), parent)

func _build_visuals() -> void:
	# 可爱的“小机器人”配色：珍珠白外壳 + 形态色的发光饰条 + 深色屏幕脸（脸在 _build_face 里）
	var pearl := Color("f3f5ff")
	for i in FORMS.size():
		var root := Node3D.new()
		root.name = FORMS[i].id
		_visual_root.add_child(root)
		_visuals.append(root)
		var c: Color = FORMS[i].color
		match i:
			BALL:
				_mesh(_sphere(0.48), _shell_mat(pearl), root)
				# 上下两片彩色面板 + 一圈发光赤道环，滚起来能看清旋转
				for sy in [1.0, -1.0]:
					var cap := MeshInstance3D.new()
					var cm := SphereMesh.new()
					cm.radius = 0.485
					cm.height = 0.97
					cm.is_hemisphere = true
					cap.mesh = cm
					cap.material_override = _shell_mat(c.darkened(0.15))
					cap.scale = Vector3(0.62, 0.35, 0.62)
					cap.position.y = 0.335 * sy
					if sy < 0.0:
						cap.rotation_degrees.x = 180.0
					root.add_child(cap)
				_ring(c, root, 0.49)
				var r2 := _ring(Color.WHITE, root, 0.492)
				r2.rotation_degrees.x = 90.0
				r2.scale = Vector3.ONE * 0.999
			DRILL:
				# 橙黄色厚重机身 + 金属钻头（带螺旋刃），尾部两片小鳍
				_mesh(_sphere(0.44), _shell_mat(Color("ffcf6b")), root)
				var band := _ring(Color("3b3f9a"), root, 0.445)
				band.rotation_degrees.x = 90.0
				for sx in [-1.0, 1.0]:
					var fin := MeshInstance3D.new()
					var fm := BoxMesh.new()
					fm.size = Vector3(0.06, 0.22, 0.26)
					fin.mesh = fm
					fin.material_override = _shell_mat(Color("3b3f9a"))
					fin.position = Vector3(0.42 * sx, 0.12, 0.2)
					fin.rotation_degrees.z = -20.0 * sx
					root.add_child(fin)
				var bit := Node3D.new()
				bit.rotation_degrees.x = -90.0
				bit.position = Vector3(0, 0, -0.52)
				root.add_child(bit)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.3
				cone.height = 0.62
				cone.radial_segments = 16
				var steel := StandardMaterial3D.new()
				steel.albedo_color = Color("dfe4f5")
				steel.metallic = 0.85
				steel.roughness = 0.25
				_mesh(cone, steel, bit)
				# 螺旋刃：几片斜着的薄板，转起来一眼就是“钻头”
				for k in 3:
					var blade := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(0.05, 0.42, 0.14)
					blade.mesh = bm
					blade.material_override = _shell_mat(c)
					var ang := k * TAU / 3.0
					blade.position = Vector3(cos(ang) * 0.13, -0.05, sin(ang) * 0.13)
					blade.rotation = Vector3(0.0, -ang, 0.45)
					bit.add_child(blade)
				var collar := _ring(c, bit, 0.3)
				collar.position.y = -0.3
				_drill_bit = bit
			BUBBLE:
				var bub := StandardMaterial3D.new()
				bub.albedo_color = Color(c, 0.3)
				bub.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bub.roughness = 0.05
				bub.metallic = 0.2
				bub.rim_enabled = true
				bub.rim = 1.0
				bub.rim_tint = 0.2
				bub.emission_enabled = true
				bub.emission = c
				bub.emission_energy_multiplier = 0.25
				_mesh(_sphere(0.5), bub, root)
				# 泡泡里漂着一颗珍珠白的小核心 + 两个小气泡
				var core := _mesh(_sphere(0.2), _shell_mat(pearl), root)
				core.name = "Core"
				for k in 2:
					var sb := _mesh(_sphere(0.06 + k * 0.03), _mat(Color.WHITE, 1.5, 0.6), root)
					sb.position = Vector3(0.22 - k * 0.4, 0.18 + k * 0.1, 0.1)

func _shell_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.28
	m.metallic = 0.05
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.2
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.5
	return m

func _burst(color: Color) -> void:
	var ps := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	m.material = mat
	ps.mesh = m
	ps.amount = 16
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 0.35
	ps.spread = 180.0
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 3.5
	ps.gravity = Vector3.ZERO
	get_parent().add_child(ps)
	ps.global_position = global_position
	ps.emitting = true
	get_tree().create_timer(0.6).timeout.connect(ps.queue_free)


# ---------------------------------------------------------------- 表情（屏幕脸）
## PIX 不会说话，但有一张小屏幕脸：两只发光的眼睛永远朝着前进方向，会眨眼、会笑、会难过。
## 屏幕脸不跟着球体一起滚，而是“浮”在球面上（像 BB-8 的脑袋），这样滚得再快也看得清表情。

var _face: Node3D
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _blink_t := 2.0
var _mood := ""
var _mood_t := 0.0
var _face_dir := Vector3(1, 0, 0)
var _idle_t := 0.0
var _antenna: Node3D
var _antenna_sway := Vector2.ZERO

func _build_face() -> void:
	_face = Node3D.new()
	_face.top_level = true
	add_child(_face)
	# 深色的屏幕面罩
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.2
	vm.height = 0.24
	vm.radial_segments = 20
	vm.rings = 8
	visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color("1b1f3b")
	vmat.roughness = 0.15
	vmat.metallic = 0.3
	visor.material_override = vmat
	visor.scale = Vector3(1.35, 0.95, 0.35)
	visor.position = Vector3(0, 0.1, -0.43)
	visor.rotation_degrees.x = -12.0
	_face.add_child(visor)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color("7ff5ff")
	for x in [-0.085, 0.085]:
		var e := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.034
		cm.height = 0.13
		cm.radial_segments = 10
		cm.rings = 3
		e.mesh = cm
		e.material_override = _eye_mat
		e.position = Vector3(x, 0.115, -0.505)
		e.rotation_degrees.x = -12.0
		_face.add_child(e)
		_eyes.append(e)
	# 头顶的小天线：会随着运动晃来晃去
	_antenna = Node3D.new()
	_antenna.position = Vector3(0, 0.47, 0.06)
	_face.add_child(_antenna)
	var stalk := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.018
	sm.height = 0.2
	stalk.mesh = sm
	stalk.position.y = 0.1
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color("3b3f9a")
	stalk.material_override = smat
	_antenna.add_child(stalk)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.045
	tm.height = 0.09
	tip.mesh = tm
	tip.material_override = _eye_mat
	tip.position.y = 0.22
	_antenna.add_child(tip)
	GameState.coins_changed.connect(func(_v: int) -> void: set_mood("happy", 0.5))
	GameState.shield_changed.connect(func(_v: int) -> void:
		if _invuln > 0.0:
			set_mood("hurt", 1.2))

func _set_eye_color(c: Color) -> void:
	_eye_mat.albedo_color = c.lightened(0.45)

## 心情："happy" 眯眼笑 / "hurt" 眼睛变成 > < / "" 正常
func set_mood(m: String, secs: float) -> void:
	_mood = m
	_mood_t = secs

func _process(delta: float) -> void:
	_update_drill_visual(delta)
	if _face == null:
		return
	# 面朝前进方向（慢慢转过去），停下时也保持最后的朝向
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if hv.length() > 0.6:
		_idle_t = 0.0
		_face_dir = _face_dir.slerp(hv.normalized(), 1.0 - exp(-8.0 * delta)).normalized()
	else:
		# 停下来一会儿，就转过头看看镜头（看着玩家）
		_idle_t += delta
		var cam := get_viewport().get_camera_3d()
		if _idle_t > 1.2 and cam:
			var to_cam := cam.global_position - global_position
			to_cam.y = 0.0
			if to_cam.length() > 0.1:
				_face_dir = _face_dir.slerp(to_cam.normalized(), 1.0 - exp(-3.0 * delta)).normalized()
	var origin := get_global_transform_interpolated().origin
	var r: float = FORMS[form].radius / 0.48 * BODY
	var fb := Basis.looking_at(_face_dir, Vector3.UP)
	if form == DRILL:
		fb = fb * Basis(Vector3.RIGHT, 0.65)   # 钻头朝前，脸往上挪一点
	_face.global_transform = Transform3D(fb.scaled(Vector3.ONE * r), origin)
	_face.visible = _visual_root.visible
	# 天线：被加速度甩向后方，再弹回来
	if _antenna:
		var local_v := fb.inverse() * linear_velocity
		var want := Vector2(clampf(-local_v.z * 0.06, -0.6, 0.6), clampf(local_v.x * 0.06, -0.6, 0.6))
		_antenna_sway = _antenna_sway.lerp(want, 1.0 - exp(-6.0 * delta))
		_antenna.rotation = Vector3(-_antenna_sway.x, 0.0, -_antenna_sway.y + sin(Time.get_ticks_msec() * 0.004) * 0.05)
	# 眨眼
	_blink_t -= delta
	var open := 1.0
	if _blink_t < 0.12:
		open = 0.12
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.0, 4.5)
	_mood_t -= delta
	if _mood_t <= 0.0:
		_mood = ""
	for i in _eyes.size():
		var e := _eyes[i]
		match _mood:
			"happy":
				# 眯成两道弯弯的缝
				e.scale = Vector3(1.3, 0.28, 1.0)
				e.rotation_degrees.z = 18.0 if i == 0 else -18.0
			"hurt":
				e.scale = Vector3(1.0, 0.7, 1.0)
				e.rotation_degrees.z = -35.0 if i == 0 else 35.0
			_:
				e.scale = Vector3(1.0, open, 1.0)
				e.rotation_degrees.z = 0.0


# ---------------------------------------------------------------- 钻头动作
## 钻的时候：钻头高速旋转、机身嗡嗡震动、钻尖喷火花和碎土；静止往下钻时钻头朝下

func _update_drill_visual(delta: float) -> void:
	if _drill_bit == null:
		return
	_drilling_t -= delta
	var drilling := form == DRILL and _drilling_t > 0.0
	var moving := Vector3(linear_velocity.x, 0, linear_velocity.z).length()
	var target_spin := 40.0 if drilling else (moving * 3.0 + 1.5)
	_bit_spin = lerpf(_bit_spin, target_spin, 1.0 - exp(-8.0 * delta))
	_drill_bit.rotate_object_local(Vector3.UP, _bit_spin * delta)
	# 往下钻：钻头慢慢转到下方
	var down := drilling and _move_input().length() < 0.15
	var droot := _visuals[DRILL]
	_drill_down = down
	# 机身震动
	if drilling:
		droot.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.025
	else:
		droot.position = droot.position.lerp(Vector3.ZERO, 0.3)
	# 火花与碎土
	if _drill_fx == null:
		_drill_fx = CPUParticles3D.new()
		var m := BoxMesh.new()
		m.size = Vector3.ONE * 0.06
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.emission_enabled = true
		mat.emission = Color("ffb03b")
		mat.emission_energy_multiplier = 1.5
		m.material = mat
		_drill_fx.mesh = m
		_drill_fx.amount = 24
		_drill_fx.lifetime = 0.35
		_drill_fx.spread = 50.0
		_drill_fx.initial_velocity_min = 2.5
		_drill_fx.initial_velocity_max = 5.0
		_drill_fx.gravity = Vector3(0, -12, 0)
		_drill_fx.scale_amount_min = 0.5
		_drill_fx.scale_amount_max = 1.3
		var g := Gradient.new()
		g.set_color(0, Color("fff2a8"))
		g.set_color(1, Color("c97b5a"))
		_drill_fx.color_ramp = g
		_drill_fx.local_coords = false
		_drill_fx.emitting = false
		add_child(_drill_fx)
	_drill_fx.emitting = drilling
	if drilling:
		var tip := _drill_bit.global_transform * Vector3(0, 0.35, 0)
		_drill_fx.global_position = tip
		_drill_fx.direction = (global_position - tip).normalized() + Vector3.UP * 0.6
