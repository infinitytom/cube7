class_name UIIcon
extends Control
## 矢量小图标（不依赖图片资源）：金币、能源、护盾、碎片、目标、锁、存档

@export var kind := "coin"
@export var color := Color.WHITE
var filled := true
var t := 0.0

static func make(k: String, c: Color, s := 26.0) -> UIIcon:
	var i := UIIcon.new()
	i.kind = k
	i.color = c
	i.custom_minimum_size = Vector2(s, s)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

func _process(delta: float) -> void:
	if kind == "save" or kind == "objective":
		t += delta
		queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.45
	match kind:
		"coin":
			draw_circle(c, r, color.darkened(0.25))
			draw_circle(c + Vector2(-1, -1), r * 0.82, color)
			draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.45), Vector2(r * 0.24, r * 0.9)), color.darkened(0.35))
		"energy":
			var pts := PackedVector2Array([c + Vector2(r * 0.15, -r), c + Vector2(-r * 0.55, r * 0.1), c + Vector2(-r * 0.02, r * 0.1),
				c + Vector2(-r * 0.2, r), c + Vector2(r * 0.6, -r * 0.15), c + Vector2(r * 0.05, -r * 0.15)])
			draw_colored_polygon(pts, color)
		"shield":
			var hex := PackedVector2Array()
			for k in 6:
				var a := PI / 6.0 + k * PI / 3.0
				hex.append(c + Vector2(cos(a), sin(a)) * r)
			if filled:
				draw_colored_polygon(hex, color)
			hex.append(hex[0])
			draw_polyline(hex, color.lightened(0.3) if filled else Color(color, 0.5), 2.0, true)
		"matter":
			# 小体素块（等轴测的立方体）
			var top := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.87, -r * 0.5), c + Vector2(0, 0), c + Vector2(-r * 0.87, -r * 0.5)])
			var lf := PackedVector2Array([c + Vector2(-r * 0.87, -r * 0.5), c, c + Vector2(0, r), c + Vector2(-r * 0.87, r * 0.5)])
			var rt := PackedVector2Array([c, c + Vector2(r * 0.87, -r * 0.5), c + Vector2(r * 0.87, r * 0.5), c + Vector2(0, r)])
			draw_colored_polygon(top, color.lightened(0.35))
			draw_colored_polygon(lf, color)
			draw_colored_polygon(rt, color.darkened(0.3))
		"fragment":
			var dia := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.7, 0), c + Vector2(0, r), c + Vector2(-r * 0.7, 0)])
			draw_colored_polygon(dia, color)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), color.lightened(0.5), 1.5)
		"pupu":
			# 噗噗：圆脑袋 + 两只小眼睛
			draw_circle(c + Vector2(0, r * 0.1), r * 0.9, color)
			draw_circle(c + Vector2(-r * 0.32, 0), r * 0.14, Color("1b1f3b"))
			draw_circle(c + Vector2(r * 0.32, 0), r * 0.14, Color("1b1f3b"))
			draw_arc(c + Vector2(0, r * 0.25), r * 0.22, 0.3, PI - 0.3, 8, Color("1b1f3b"), 1.5, true)
		"objective":
			var pulse := 0.85 + 0.15 * sin(t * 3.0)
			draw_arc(c, r * pulse, 0, TAU, 32, color, 2.5, true)
			draw_circle(c, r * 0.35, color)
		"lock":
			draw_arc(c + Vector2(0, -r * 0.15), r * 0.4, PI, TAU, 16, color, 3.0, true)
			draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.15), Vector2(r * 1.1, r * 0.95)), color)
		"form_ball":
			draw_circle(c, r * 0.85, Color(color, 0.25))
			draw_arc(c, r * 0.85, 0, TAU, 32, color, 2.5, true)
			draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), color, 2.0, true)
		"form_drill":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.6, r * 0.5), c + Vector2(-r * 0.6, r * 0.5)]), color)
			for k in 3:
				var yy := -r * 0.3 + k * r * 0.3
				draw_line(c + Vector2(-r * 0.3 - k * 0.1 * r, yy), c + Vector2(r * 0.3 + k * 0.1 * r, yy + r * 0.12), color.darkened(0.4), 2.0)
		"form_cube":
			draw_rect(Rect2(c - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), Color(color, 0.3))
			draw_rect(Rect2(c - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), color, false, 2.5)
		"form_magnet":
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.6, 0, PI, 16, color, r * 0.35)
			draw_rect(Rect2(c + Vector2(-r * 0.78, -r * 0.8), Vector2(r * 0.35, r * 0.7)), Color("e0364f"))
			draw_rect(Rect2(c + Vector2(r * 0.43, -r * 0.8), Vector2(r * 0.35, r * 0.7)), Color("3a6dff"))
		"form_bubble":
			draw_arc(c, r * 0.85, 0, TAU, 32, color, 2.0, true)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.8))
		"save":
			for k in 8:
				var a := t * 6.0 + k * TAU / 8.0
				var alpha := float(k) / 8.0
				draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.7, r * 0.14, Color(color, alpha))
