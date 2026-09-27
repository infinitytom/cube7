class_name ObjectivePointer
extends Control
## 目标指引：目标在画面里时，在目标上方画一个跳动的菱形 + 距离；
## 目标在画面外（或身后）时，在屏幕边缘画一个指向它的箭头。永远知道该往哪走。

var _t := 0.0
var _pos := Vector2.ZERO
var _on_screen := false
var _angle := 0.0
var _dist := 0.0
var _show := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	_show = false
	var target := GameState.objective_pos
	var cam := get_viewport().get_camera_3d()
	var pl := GameState.player as Node3D
	if target == Vector3.INF or cam == null or pl == null or GameState.level_complete:
		queue_redraw()
		return
	_dist = pl.global_position.distance_to(target)
	if _dist < 4.0:
		queue_redraw()
		return
	_show = true
	var aim := target + Vector3.UP * 1.2
	var vs := get_viewport_rect().size
	var behind := cam.is_position_behind(aim)
	var sp := cam.unproject_position(aim)
	var margin := 70.0
	_on_screen = not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
	if _on_screen:
		_pos = sp
	else:
		var c := vs * 0.5
		var d := sp - c
		if behind:
			d = -d
		if d.length() < 1.0:
			d = Vector2(0, -1)
		_angle = d.angle()
		# 从屏幕中心沿方向射到边缘
		var half := c - Vector2(margin, margin)
		var k := minf(absf(half.x / d.x) if absf(d.x) > 0.001 else 1e9, absf(half.y / d.y) if absf(d.y) > 0.001 else 1e9)
		_pos = c + d * k
	queue_redraw()

func _draw() -> void:
	if not _show:
		return
	var col := UIKit.ACCENT2
	var bob := sin(_t * 4.0) * 5.0
	var font := UIKit.font(true)
	var txt := "%d m" % int(_dist)
	if _on_screen:
		var p := _pos + Vector2(0, bob)
		var s := 13.0
		var dia := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.75, 0), p + Vector2(0, s), p + Vector2(-s * 0.75, 0)])
		draw_colored_polygon(dia, Color(0.1, 0.1, 0.3, 0.5))
		var inner := PackedVector2Array()
		for q in dia:
			inner.append(p + (q - p) * 0.78)
		draw_colored_polygon(inner, col)
		draw_string_outline(font, p + Vector2(-28, 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 56, 18, 6, Color(0.1, 0.1, 0.3, 0.8))
		draw_string(font, p + Vector2(-28, 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 56, 18, Color.WHITE)
	else:
		var p := _pos + Vector2.from_angle(_angle) * bob
		var dir := Vector2.from_angle(_angle)
		var side := dir.orthogonal()
		var tip := p + dir * 20.0
		var tri := PackedVector2Array([tip, p - dir * 8.0 + side * 16.0, p - dir * 8.0 - side * 16.0])
		draw_colored_polygon(tri, Color(0.1, 0.1, 0.3, 0.55))
		var tri2 := PackedVector2Array()
		for q in tri:
			tri2.append(p + (q - p) * 0.78)
		draw_colored_polygon(tri2, col)
		var tp := p - dir * 36.0 + Vector2(-28, 6)
		draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 56, 17, 6, Color(0.1, 0.1, 0.3, 0.8))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 56, 17, Color.WHITE)
