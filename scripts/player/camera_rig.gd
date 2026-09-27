class_name CameraRig
extends Node3D
## 第三人称环绕镜头：右摇杆 / 鼠标旋转，△ / V 切换 45° 俯视“模型模式”

@export var target_path: NodePath
@export var distance := 6.5
@export var model_distance := 15.0
@export var stick_speed := Vector2(2.8, 1.8)
@export var mouse_sensitivity := 0.0025

var yaw := -PI / 2.0      ## 初始朝向 +X（关卡推进方向）
var pitch := -0.38
var model_view := false

var _target: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _shake := 0.0

func _ready() -> void:
	top_level = true
	_target = get_node_or_null(target_path)
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.collision_mask = 1
	_arm.margin = 0.2
	var s := SphereShape3D.new()
	s.radius = 0.3
	_arm.shape = s
	add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.current = true
	_arm.add_child(_cam)
	if _target:
		_arm.add_excluded_object((_target as CollisionObject3D).get_rid())
		global_position = _target.global_position
	GameState.camera = self
	GameState.shake.connect(func(a: float) -> void: _shake = maxf(_shake, a))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("view_toggle"):
		model_view = not model_view

func _process(delta: float) -> void:
	var s := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	yaw -= s.x * stick_speed.x * delta
	pitch -= s.y * stick_speed.y * delta
	pitch = clampf(pitch, -1.35, 0.4)
	if _target:
		var goal := _target.global_position + Vector3.UP * 0.6
		global_position = global_position.lerp(goal, 1.0 - exp(-12.0 * delta))
	var p := -0.95 if model_view else pitch
	rotation = Vector3(p, yaw, 0.0)
	var want := model_distance if model_view else distance
	_arm.spring_length = lerpf(_arm.spring_length, want, 1.0 - exp(-6.0 * delta))
	# 屏幕震动
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.5, 0.0)
		var k := _shake * _shake
		_cam.h_offset = randf_range(-1, 1) * k * 0.6
		_cam.v_offset = randf_range(-1, 1) * k * 0.6
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
