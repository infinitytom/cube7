class_name CameraRig
extends Node3D
## 第三人称环绕镜头。
## 防抖要点：
##   1. 跟随主角的“插值后位置”（配合项目设置里的物理插值），不和物理帧打架
##   2. 自己做球形扫掠求安全距离：被挡住时快速拉近，畅通后缓慢拉远，不会瞬跳
##   3. 被墙挡住时从几个候选俯角里挑一个能看清的，平滑过渡过去，并带滞回，不来回摆
##   4. 所有角度（包括俯视模式切换）都平滑插值

@export var target_path: NodePath
@export var distance := 8.6
@export var model_distance := 15.0
@export var stick_speed := Vector2(2.6, 1.7)
@export var mouse_sensitivity := 0.0025
@export var probe_radius := 0.25

var yaw := -PI / 2.0      ## 初始朝向 +X
var pitch := -0.5         ## 玩家手动控制的俯角
var model_view := false

var _target: Node3D
var _cam: Camera3D
var _pivot := Vector3.ZERO
var _cur_dist := 8.6
var _cur_pitch := -0.5
var _lift_target := 0.0
var _lift := 0.0
var _hide_timer := 0.0
var _shake := 0.0
var _exclude: Array[RID] = []

const LIFT_CANDIDATES := [0.0, 0.3, 0.55, 0.8]

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path)
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.near = 0.05
	_cam.current = true
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam)
	if _target:
		_exclude = [(_target as CollisionObject3D).get_rid()]
		_pivot = _target_pos()
	_cur_pitch = pitch
	_cur_dist = distance
	GameState.camera = self

	GameState.shake.connect(func(a: float) -> void:
		if bool(Settings.get_v("shake")):
			_shake = maxf(_shake, a))

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"occl_target", Vector4.ZERO)

## 设置里的镜头灵敏度（0.25~2 倍）与上下反转
func _sens() -> float:
	return clampf(float(Settings.get_v("cam_sens")), 0.25, 2.0)

func _inv() -> float:
	return -1.0 if bool(Settings.get_v("invert_y")) else 1.0

func _target_pos() -> Vector3:
	# 用插值后的变换，避免 60Hz 物理 vs 高刷屏幕的抖动
	return _target.get_global_transform_interpolated().origin + Vector3.UP * 0.6

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := mouse_sensitivity * _sens()
		yaw -= event.relative.x * k
		pitch -= event.relative.y * k * _inv()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("view_toggle"):
		model_view = not model_view

## 从 pivot 沿方向扫掠球体，返回可用距离
func _probe(dir: Vector3, dist: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = probe_radius
	q.shape = s
	q.transform = Transform3D(Basis(), _pivot)
	q.motion = dir * dist
	q.collision_mask = 1
	q.exclude = _exclude
	var r := space.cast_motion(q)
	return dist * r[0]

func _dir_for(p: float) -> Vector3:
	# 镜头相对 pivot 的方向（镜头看向 -Z，所以镜头在 +Z 方向）
	return Basis.from_euler(Vector3(p, yaw, 0.0)) * Vector3.BACK

func _process(delta: float) -> void:
	var s := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	yaw -= s.x * stick_speed.x * delta * _sens()
	pitch = clampf(pitch - s.y * stick_speed.y * delta * _sens() * _inv(), -1.3, 0.35)
	if _target:
		# 跟随稍微放松一点：节奏放慢后，镜头也更从容
		_pivot = _pivot.lerp(_target_pos(), 1.0 - exp(-10.0 * delta))

	var want := model_distance if model_view else distance * float(Settings.get_v("cam_dist"))
	var base_pitch := -0.95 if model_view else pitch

	# 选一个不被墙挡住的抬升量（从上方越过箱庭的墙）。带滞回：
	#   当前抬升被挡 → 换成最小的可用抬升；当前可用且有抬升 → 只有更低的抬升“明显畅通”才降低
	if model_view:
		_lift_target = 0.0
	elif _probe(_dir_for(base_pitch - _lift_target), want) < want * 0.8:
		# 找最小的畅通抬升；都被挡（比如在室内）就选看得最远的那个
		var best_c := _lift_target
		var best_d := -1.0
		for c in LIFT_CANDIDATES:
			var d := _probe(_dir_for(clampf(base_pitch - c, -1.4, 0.35)), want)
			if d >= want * 0.8:
				best_c = c
				break
			if d > best_d + 0.3:
				best_d = d
				best_c = c
		_lift_target = best_c
	elif _lift_target > 0.0:
		for c in LIFT_CANDIDATES:
			if c >= _lift_target:
				break
			if _probe(_dir_for(clampf(base_pitch - c, -1.4, 0.35)), want) >= want * 0.95:
				_lift_target = c
				break
	_lift = lerpf(_lift, _lift_target, 1.0 - exp(-4.0 * delta))
	_cur_pitch = lerpf(_cur_pitch, clampf(base_pitch - _lift, -1.4, 0.35), 1.0 - exp(-10.0 * delta))

	# 距离：被挡住时快速拉近，畅通后缓慢拉远
	var dir := _dir_for(_cur_pitch)
	var safe := want if model_view else _probe(dir, want)
	var k := 25.0 if safe < _cur_dist else 3.0
	_cur_dist = lerpf(_cur_dist, safe, 1.0 - exp(-k * delta))
	_cur_dist = minf(_cur_dist, safe + 0.05) if not model_view else _cur_dist

	var cam_pos := _pivot + dir * _cur_dist
	global_transform = Transform3D(Basis.from_euler(Vector3(_cur_pitch, yaw, 0.0)), cam_pos)

	# 告诉体素着色器 PIX 在哪：挡在中间的方块镂空
	if _target:
		var tp := _target.get_global_transform_interpolated().origin
		RenderingServer.global_shader_parameter_set(&"occl_target", Vector4(tp.x, tp.y, tp.z, 1.0 if _cam.current and not model_view else 0.0))

	# 镜头贴得太近时隐藏主角（带 0.2 秒滞回，避免闪烁）
	if _target and _target.has_method("set_visual_hidden"):
		var close := not model_view and _cur_dist < 1.2
		_hide_timer = 0.2 if close else maxf(_hide_timer - delta, 0.0)
		_target.set_visual_hidden(_hide_timer > 0.0)

	# 屏幕震动
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.5, 0.0)
		var sk := _shake * _shake
		_cam.h_offset = randf_range(-1, 1) * sk * 0.6
		_cam.v_offset = randf_range(-1, 1) * sk * 0.6
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
