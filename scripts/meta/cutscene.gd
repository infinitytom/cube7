class_name Cutscene
extends CanvasLayer
## 引擎内过场演出：镜头运动 + 电影黑边 + 字幕 + 事件。按住 ○ / B / Esc 跳过。
## 每个镜头：{"from": 位置, "to": 位置, "look": 看向（或 look_from/look_to）, "dur": 秒, "lines": [[说话人, 台词], ...], "event": 名称}

signal finished
signal event(name: String)

var shots: Array = []
var _cam: Camera3D
var _prev_cam: Camera3D
var _top: ColorRect
var _bottom: ColorRect
var _sub_box: VBoxContainer
var _speaker: Label
var _line: Label
var _skip: HBoxContainer
var _skip_bar: ProgressBar
var _black: ColorRect
var _hold := 0.0
var _done := false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.modulate.a = 0.0
	root.add_child(_black)
	_top = ColorRect.new()
	_top.color = Color.BLACK
	UIKit.place(_top, Vector4(0, 0, 1, 0), Vector4(0, -110, 0, 0))
	root.add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	UIKit.place(_bottom, Vector4(0, 1, 1, 1), Vector4(0, 0, 0, 110))
	root.add_child(_bottom)
	_sub_box = VBoxContainer.new()
	_sub_box.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(_sub_box, Vector4(0.5, 1, 0.5, 1), Vector4(-620, -104, 620, -8))
	root.add_child(_sub_box)
	_speaker = UIKit.label("", 20, UIKit.ACCENT, true)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_box.add_child(_speaker)
	_line = UIKit.label("", 28, Color.WHITE)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_box.add_child(_line)
	_skip = HBoxContainer.new()
	_skip.add_theme_constant_override("separation", 8)
	UIKit.place(_skip, Vector4(1, 0, 1, 0), Vector4(-300, 34, -40, 70))
	_skip.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_skip)
	_skip.add_child(UIKit.label("按住", 18, UIKit.DIM))
	_skip.add_child(UIKit.glyph("grab", 18))
	_skip.add_child(UIKit.label("跳过", 18, UIKit.DIM))
	_skip_bar = ProgressBar.new()
	_skip_bar.custom_minimum_size = Vector2(60, 6)
	_skip_bar.show_percentage = false
	_skip_bar.max_value = 1.0
	_skip.add_child(_skip_bar)

func play() -> void:
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(_cam)
	_cam.current = true
	# 黑边滑入
	var tw := create_tween().set_parallel()
	tw.tween_property(_top, "offset_bottom", 110.0, 0.6)
	tw.tween_property(_bottom, "offset_top", -110.0, 0.6)
	for shot in shots:
		if _done:
			break
		await _play_shot(shot)
	_finish()

func _play_shot(shot: Dictionary) -> void:
	var dur: float = shot.get("dur", 4.0)
	var from: Vector3 = shot.get("from", Vector3.ZERO)
	var to: Vector3 = shot.get("to", from)
	var look_from: Vector3 = shot.get("look_from", shot.get("look", Vector3.ZERO))
	var look_to: Vector3 = shot.get("look_to", shot.get("look", look_from))
	if shot.has("fade"):
		# 这一镜从纯色淡入（黑场开篇、白光转场）
		_black.color = shot["fade"]
		_black.modulate.a = 1.0
		create_tween().tween_property(_black, "modulate:a", 0.0, 1.2)
	elif shot.get("black", false):
		_black.modulate.a = 1.0
	elif _black.modulate.a > 0.0:
		create_tween().tween_property(_black, "modulate:a", 0.0, 1.0)
	if shot.has("event"):
		event.emit(shot["event"])
	var lines: Array = shot.get("lines", [])
	var t := 0.0
	var line_i := -1
	while t < dur and not _done:
		var k := t / dur
		var e := k * k * (3.0 - 2.0 * k)   # smoothstep 缓动
		_cam.global_position = from.lerp(to, e)
		_cam.look_at(look_from.lerp(look_to, e))
		# 台词按时间平均分配
		if lines.size() > 0:
			var li := mini(int(k * lines.size()), lines.size() - 1)
			if li != line_i:
				line_i = li
				_show_line(lines[li][0], lines[li][1])
		await get_tree().process_frame
		t += get_process_delta_time()
	if lines.is_empty():
		_show_line("", "")

func _show_line(who: String, text: String) -> void:
	_speaker.text = who
	_line.text = text
	_line.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(_line, "visible_ratio", 1.0, clampf(text.length() * 0.035, 0.2, 1.4))

func _process(delta: float) -> void:
	if _done:
		return
	if Input.is_action_pressed("grab") or Input.is_action_pressed("pause"):
		_hold += delta
		if _hold >= 1.0:
			_done = true
	else:
		_hold = maxf(_hold - delta * 2.0, 0.0)
	_skip_bar.value = _hold

func _finish() -> void:
	_done = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_top, "offset_bottom", 0.0, 0.5)
	tw.tween_property(_bottom, "offset_top", 0.0, 0.5)
	tw.tween_property(_sub_box, "modulate:a", 0.0, 0.3)
	tw.tween_property(_black, "modulate:a", 0.0, 0.3)
	await tw.finished
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	_cam.queue_free()
	finished.emit()
	queue_free()
