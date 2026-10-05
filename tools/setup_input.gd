extends SceneTree
## 一次性工具：把输入映射写进 project.godot（之后可在 编辑器 > 项目设置 > 输入映射 中修改）
## 运行：godot --headless --path . -s res://tools/setup_input.gd
## 按键约定（PS5 优先）：✕跳跃  □形态能力  ○抓取/投掷  △俯视  R2加速  L1/R1切换形态  十字键直选形态

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mouse(btn: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	return e

func _joy(btn: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.device = -1
	return e

func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e

func _init() -> void:
	var actions := {
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"cam_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"cam_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"cam_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"cam_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"jump": [_key(KEY_SPACE), _joy(JOY_BUTTON_A)],
		"boost": [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"ability": [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_F), _joy(JOY_BUTTON_X)],
		"grab": [_key(KEY_E), _mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_B)],
		"form_next": [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _key(KEY_C), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"form_prev": [_mouse(MOUSE_BUTTON_WHEEL_UP), _key(KEY_Z), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"form_1": [_key(KEY_1), _joy(JOY_BUTTON_DPAD_LEFT)],
		"form_2": [_key(KEY_2), _joy(JOY_BUTTON_DPAD_UP)],
		"form_3": [_key(KEY_3), _joy(JOY_BUTTON_DPAD_RIGHT)],
		"view_toggle": [_key(KEY_V), _joy(JOY_BUTTON_Y)],
		"scan": [_key(KEY_Q), _mouse(MOUSE_BUTTON_MIDDLE), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"respawn": [_key(KEY_R), _joy(JOY_BUTTON_BACK)],
		"pause": [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)],
	}
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": 0.2,
			"events": actions[action_name],
		})
	var err := ProjectSettings.save()
	print("input map saved: ", err == OK)
	quit()
