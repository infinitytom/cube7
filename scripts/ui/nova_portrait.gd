class_name NovaPortrait
extends Control
## NOVA 的全息头像：一个会眨眼的“眼睛”，说话时下方的声波跳动

var talking := false
var _t := 0.0
var _blink := 0.0

func _process(delta: float) -> void:
	_t += delta
	_blink -= delta
	if _blink < -3.0:
		_blink = 0.15
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_circle(c, r, Color(0.31, 0.82, 1.0, 0.12))
	draw_arc(c, r, 0, TAU, 48, Color(0.31, 0.82, 1.0, 0.8), 2.0, true)
	draw_arc(c, r * 0.8, _t * 0.8, _t * 0.8 + PI * 1.2, 32, Color(0.31, 0.82, 1.0, 0.35), 1.5, true)
	# 眼睛
	var open := 0.15 if _blink > 0.0 else 1.0
	var eye := Rect2(c + Vector2(-r * 0.35, -r * 0.35 * open - r * 0.1), Vector2(r * 0.7, r * 0.7 * open))
	draw_rect(eye, Color("bff0ff"))
	draw_circle(eye.get_center() + Vector2(sin(_t * 0.7) * r * 0.08, 0), r * 0.12 * open, Color("0d2a3f"))
	# 声波
	for k in 5:
		var h := r * 0.08
		if talking:
			h = r * (0.08 + 0.18 * absf(sin(_t * 14.0 + k * 1.3)))
		var x := c.x - r * 0.4 + k * r * 0.2
		draw_line(Vector2(x, c.y + r * 0.55 - h), Vector2(x, c.y + r * 0.55 + h), Color(0.31, 0.82, 1.0, 0.9), 2.5)
