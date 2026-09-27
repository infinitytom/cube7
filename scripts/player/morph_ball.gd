class_name MorphBall
extends RigidBody3D
## 主角 PIX：可变形的维护探测球。
## 滚动手感致敬《平衡球》：真实惯性，形态不同重量不同，同一段路换形态就是另一种走法。

enum { BALL, DRILL, CUBE, MAGNET, BUBBLE }

## 每个形态的物理参数。roll = 是否靠滚动（施加扭矩）移动；false 则锁定旋转、靠推力移动
const FORMS: Array[Dictionary] = [
	{"id": "ball", "name": "滚球", "ability": "冲刺", "color": Color("46c3ff"),
		"mass": 1.0, "shape": "sphere", "radius": 0.48, "roll": true,
		"torque": 8.0, "ground_force": 2.5, "air_force": 5.0, "max_speed": 7.0, "boost_speed": 12.0,
		"jump": 5.2, "gravity": 1.0, "friction": 0.9, "bounce": 0.12, "lin_damp": 0.08, "ang_damp": 0.6},
	{"id": "drill", "name": "钻头", "ability": "钻掘（静止时向下）", "color": Color("ffb03b"),
		"mass": 2.5, "shape": "sphere", "radius": 0.46, "roll": false,
		"torque": 0.0, "ground_force": 9.0, "air_force": 3.0, "max_speed": 4.0, "boost_speed": 6.0,
		"jump": 3.8, "gravity": 1.0, "friction": 0.5, "bounce": 0.0, "lin_damp": 1.2, "ang_damp": 3.0},
	{"id": "cube", "name": "立方", "ability": "空中重压", "color": Color("8cff6b"),
		"mass": 3.0, "shape": "box", "radius": 0.45, "roll": true,
		"torque": 16.0, "ground_force": 1.5, "air_force": 3.0, "max_speed": 4.0, "boost_speed": 6.0,
		"jump": 4.2, "gravity": 1.2, "friction": 1.0, "bounce": 0.0, "lin_damp": 0.3, "ang_damp": 1.5},
	{"id": "magnet", "name": "磁铁", "ability": "吸附攀爬（按住）", "color": Color("ff5a6e"),
		"mass": 1.4, "shape": "sphere", "radius": 0.48, "roll": true,
		"torque": 7.0, "ground_force": 2.5, "air_force": 4.0, "max_speed": 6.0, "boost_speed": 9.0,
		"jump": 4.8, "gravity": 1.0, "friction": 0.9, "bounce": 0.05, "lin_damp": 0.1, "ang_damp": 0.8},
	{"id": "bubble", "name": "气泡", "ability": "喷气上浮", "color": Color("c9a6ff"),
		"mass": 0.3, "shape": "sphere", "radius": 0.5, "roll": true,
		"torque": 3.0, "ground_force": 4.0, "air_force": 5.0, "max_speed": 4.5, "boost_speed": 6.0,
		"jump": 3.2, "gravity": 0.25, "friction": 0.6, "bounce": 0.5, "lin_damp": 1.0, "ang_damp": 1.0},
]

const IMPACT_MIN := 1.8
const DASH_SPEED := 11.5
const GRAB_RANGE := 2.2

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
	collision_mask = 1 | 4 | 8
	physics_material_override = PhysicsMaterial.new()
	_shape_node = get_node_or_null("CollisionShape3D")
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)
	_build_visuals()
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
	for i in 5:
		if event.is_action_pressed("form_%d" % (i + 1)):
			request_form(i)
	if event.is_action_pressed("grab"):
		toggle_grab()
	if event.is_action_pressed("respawn"):
		GameState.respawn()

# ---------------------------------------------------------------- 形态

func cycle_form(step: int) -> void:
	var i := form
	for n in 5:
		i = posmod(i + step, 5)
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
		s.radius = f.radius
		_shape_node.shape = s
	for k in _visuals.size():
		_visuals[k].visible = k == i
	_magnet_stuck = false
	_pounding = false
	if fx:
		_visual_root.scale = Vector3.ONE * 0.45
		var tw := create_tween()
		tw.tween_property(_visual_root, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_burst(f.color)
		Sfx.play("morph", Vector3.INF, -4.0)
		Sfx.play("pix_morph", Vector3.INF, -9.0, 0.12)
	GameState.form_changed.emit(i)

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
	var best_impact := {}
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		if n.y > 0.55:
			on_ground = true
		var col := state.get_contact_collider_object(i)
		if col is Node and (col as Node).is_in_group("voxel_body"):
			var speed := -_prev_vel.dot(n)
			if speed > IMPACT_MIN and speed > float(best_impact.get("speed", 0.0)):
				best_impact = {"point": state.get_contact_collider_position(i), "normal": n, "speed": speed, "vel": _prev_vel}
	if not best_impact.is_empty():
		_impacts.append(best_impact)
	if on_ground:
		_ground_timer = 0.12
	grounded = on_ground
	_prev_vel = state.linear_velocity

func _physics_process(delta: float) -> void:
	_ground_timer -= delta
	_ability_cd -= delta
	if not _impacts.is_empty():
		_handle_impacts()
	if global_position.y < GameState.kill_y:
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
	if dir.length() > 0.05 and not _magnet_stuck:
		var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
		var d := dir.normalized() * minf(dir.length(), 1.0)
		if vh.dot(d.normalized()) < max_s:
			if f.roll:
				apply_torque(Vector3.UP.cross(d) * float(f.torque) * mass * mul)
			var a: float = f.ground_force if _ground_timer > 0.0 else f.air_force
			apply_central_force(d * a * mass * mul)

	# 跳跃
	var jump := Input.is_action_just_pressed("jump") and not debug_override and GameState.allow_jump
	if jump and _ground_timer > 0.0:
		_ground_timer = 0.0
		linear_velocity.y = maxf(linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * float(f.jump) * mass)

	if _ground_timer > 0.0:
		_puffs = 0
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
		_visuals[form].basis = _visuals[form].basis.slerp(target, 1.0 - exp(-12.0 * delta))

## 贴地：刚离开地面（坡顶、小台阶）时，如果正下方很近处还有地面，就压回去，
## 避免高速过坡顶时整个飞出去。真正的断崖（下方没有地面）不受影响。
func _snap_to_ground() -> void:
	if grounded or _no_snap > 0.0 or _magnet_stuck or form == BUBBLE:
		return
	if _ground_timer <= 0.0:
		return
	if linear_velocity.y <= 0.0:
		return
	var r: float = FORMS[form].radius
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

func _update_ability(delta: float, f: Dictionary, dir: Vector3) -> void:
	var pressed := _ability_pressed()
	var held := _ability_held()
	match form:
		BALL:
			if pressed and _ability_cd <= 0.0:
				_ability_cd = 0.9
				var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
				apply_central_impulse((_move_dir * DASH_SPEED - vh) * mass)
				_burst(f.color)
				Sfx.play("dash", global_position, -2.0)
		DRILL:
			if held:
				_drill_timer -= delta
				if _drill_bit:
					_drill_bit.rotate_object_local(Vector3.UP, delta * 30.0)
				if _drill_timer <= 0.0:
					_drill_timer = 0.09
					_drill(dir)
		CUBE:
			if pressed and _ground_timer <= 0.0 and not _pounding:
				_pounding = true
				linear_velocity = Vector3(0, -15.0, 0)
			if _ground_timer > 0.0:
				_pounding = false
		MAGNET:
			_update_magnet(held, dir, f)
		BUBBLE:
			if pressed and _puffs < 3:
				_puffs += 1
				linear_velocity.y = 3.6
				_burst(f.color)

func _drill(dir: Vector3) -> void:
	if world == null:
		return
	var pts: Array[Vector3] = []
	if dir.length() < 0.15:
		# 静止时向下钻：以球心为中心钻 3×3 格（1.5 米见方），保证球能掉下去
		for ox in [-0.45, 0.0, 0.45]:
			for oz in [-0.45, 0.0, 0.45]:
				pts.append(global_position + Vector3(ox, -0.7, oz))
	else:
		# 钻出约 1.5m 宽、2m 高的隧道：球能通过，镜头也有空间
		var side := Vector3.UP.cross(_move_dir).normalized()
		for oy in [-0.25, 0.2, 0.6, 1.05]:
			for os in [-0.45, 0.0, 0.45]:
				pts.append(global_position + _move_dir * 0.75 + Vector3.UP * oy + side * os)
	var down := dir.length() < 0.15
	var broke := false
	for p in pts:
		var v := world.world_to_voxel(p)
		# 往下只能钻松土/砂：普通地面钻不下去，避免把自己困在坑里
		if down and Blocks.soft[world.get_block(v)] == 0:
			continue
		if world.try_break(v, "drill", 1.0):
			broke = true
	if broke:
		GameState.shake.emit(0.06)
		Sfx.play("drill", global_position, -6.0, 0.1)

func _update_magnet(held: bool, dir: Vector3, f: Dictionary) -> void:
	var was := _magnet_stuck
	_magnet_stuck = false
	if held and world:
		var c := world.world_to_voxel(global_position)
		var best := 1.2 * 1.2
		var best_pos := Vector3.ZERO
		var found := false
		for dz in range(-2, 3):
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var p := c + Vector3i(dx, dy, dz)
					if world.get_block(p) == Blocks.METAL:
						var d2 := world.voxel_center(p).distance_squared_to(global_position)
						if d2 < best:
							best = d2
							best_pos = world.voxel_center(p)
							found = true
		if found:
			_magnet_stuck = true
			var to_wall := (best_pos - global_position).normalized()
			var wall_n := -to_wall
			apply_central_force(to_wall * 22.0 * mass)
			# 推向墙 = 向上爬；其他方向沿墙面移动
			var tangent := dir - wall_n * dir.dot(wall_n)
			if absf(wall_n.y) < 0.5:
				tangent += Vector3.UP * maxf(0.0, -dir.dot(wall_n)) * 1.2
			apply_central_force(tangent * 14.0 * mass)
	if _magnet_stuck:
		gravity_scale = 0.0
		linear_damp = 4.0
	elif was:
		gravity_scale = f.gravity
		linear_damp = f.lin_damp

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
		var count := world.break_sphere(center, radius, "impact", speed)
		if count == 0 and speed > 4.0:
			Sfx.play("thud", global_position, linear_to_db(clampf(speed / 12.0, 0.2, 1.0)), 0.1)
		if count >= 2:
			# 撞穿：保留大部分速度继续前进
			linear_velocity = (imp.vel as Vector3) * 0.8

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
	var best: Node3D = null
	var best_d := GRAB_RANGE
	for n in get_tree().get_nodes_in_group("usable_item"):
		var d := (n as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		_held = best
		best.call("set_held", true)
		Sfx.play("grab", global_position, -4.0)

func _release_held(vel: Vector3) -> void:
	if _held and is_instance_valid(_held):
		_held.call("set_held", false)
		(_held as RigidBody3D).linear_velocity = vel
	_held = null

func set_visual_hidden(v: bool) -> void:
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
	var shell := Color("2b3450")
	for i in FORMS.size():
		var root := Node3D.new()
		root.name = FORMS[i].id
		_visual_root.add_child(root)
		_visuals.append(root)
		var c: Color = FORMS[i].color
		match i:
			BALL:
				_mesh(_sphere(0.48), _mat(shell), root)
				_ring(c, root)
				var r2 := _ring(c, root, 0.49)
				r2.rotation_degrees.x = 90.0
				r2.scale = Vector3(1, 1, 1) * 0.999
			DRILL:
				_mesh(_sphere(0.44), _mat(Color("4a3a2a")), root)
				var bit := Node3D.new()
				bit.rotation_degrees.x = -90.0
				bit.position = Vector3(0, 0, -0.5)
				root.add_child(bit)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.3
				cone.height = 0.6
				cone.radial_segments = 8
				_mesh(cone, _mat(c, 1.2), bit)
				_drill_bit = bit
				var ring := _ring(c, root, 0.45)
				ring.rotation_degrees.x = 90.0
			CUBE:
				var b := BoxMesh.new()
				b.size = Vector3.ONE * 0.9
				_mesh(b, _mat(shell), root)
				var band := BoxMesh.new()
				band.size = Vector3(0.93, 0.14, 0.93)
				_mesh(band, _mat(c, 2.5), root)
			MAGNET:
				var top := _sphere(0.48)
				top.is_hemisphere = true
				top.height = 0.48
				_mesh(top, _mat(Color("e0364f")), root)
				var bot := _mesh(top, _mat(Color("3a6dff")), root)
				bot.rotation_degrees.x = 180.0
				_ring(Color.WHITE, root, 0.49)
			BUBBLE:
				_mesh(_sphere(0.5), _mat(c, 0.4, 0.35), root)
				_mesh(_sphere(0.16), _mat(c, 3.0), root)

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
