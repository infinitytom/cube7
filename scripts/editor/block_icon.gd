class_name BlockIcon
extends Control
## 编辑器里的物块图标：一眼看出“这是什么、能怎么用”
##   · 普通方块：等轴测的小立方体（顶面亮、两侧暗）
##   · 自然地形（平滑网格）：圆润的土丘
##   · 玻璃：半透明带高光；发光方块：带光晕
##   · 右下角小角标：撞得碎（星形）/ 只能钻（钻头）/ 会塌（波浪）/ 打不坏（锁）
##   · 物件：圆形徽章 + 名字的第一个字

var cat := 0
var index := 0
var selected := false

static func make(c: int, i: int, s := 52.0) -> BlockIcon:
	var b := BlockIcon.new()
	b.cat = c
	b.index = i
	b.custom_minimum_size = Vector2(s, s)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.4
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UIKit.ACCENT, 0.22))
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), UIKit.ACCENT, false, 2.5)
	if cat == 1:
		var o: Array = LevelData.OBJECTS[index]
		var col: Color = o[2]
		draw_circle(c, r * 0.95, col.darkened(0.35))
		draw_circle(c + Vector2(-1, -1.5), r * 0.82, col)
		var f := UIKit.font(true)
		var txt := str(o[1]).substr(0, 1)
		var fs := int(r * 1.05)
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, c + Vector2(-tw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.1, 0.22))
		return
	var t: int = LevelData.BLOCKS[index][0]
	var col2: Color = Blocks.colors[t]
	var rnd: int = Blocks.render[t]
	if rnd == Blocks.Render.GLOW:
		draw_circle(c, r * 1.15, Color(col2, 0.25))
	if Blocks.smooth[t] == 1:
		# 圆润的小土丘
		var pts := PackedVector2Array()
		for k in 20:
			var a := PI + k * PI / 19.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.85 + r * 0.35))
		pts.append(c + Vector2(r, r * 0.55))
		pts.append(c + Vector2(-r, r * 0.55))
		draw_colored_polygon(pts, col2.darkened(0.15))
		var hi := PackedVector2Array()
		for k in 14:
			var a2 := PI + 0.25 + k * (PI - 0.5) / 13.0
			hi.append(c + Vector2(cos(a2) * r * 0.78, sin(a2) * r * 0.62 + r * 0.2))
		draw_colored_polygon(hi, col2.lightened(0.18))
	else:
		var top := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.87, -r * 0.5), c, c + Vector2(-r * 0.87, -r * 0.5)])
		var lf := PackedVector2Array([c + Vector2(-r * 0.87, -r * 0.5), c, c + Vector2(0, r), c + Vector2(-r * 0.87, r * 0.5)])
		var rt := PackedVector2Array([c, c + Vector2(r * 0.87, -r * 0.5), c + Vector2(r * 0.87, r * 0.5), c + Vector2(0, r)])
		var a3 := 0.45 if rnd == Blocks.Render.GLASS else 1.0
		draw_colored_polygon(top, Color(col2.lightened(0.3), a3))
		draw_colored_polygon(lf, Color(col2, a3))
		draw_colored_polygon(rt, Color(col2.darkened(0.28), a3))
		if rnd == Blocks.Render.GLASS:
			draw_line(c + Vector2(-r * 0.5, -r * 0.1), c + Vector2(-r * 0.2, -r * 0.6), Color(1, 1, 1, 0.8), 2.0)
	# 角标
	var b := c + Vector2(r * 0.72, r * 0.72)
	var br := r * 0.32
	if Blocks.impact[t] >= 0.0 and Blocks.impact[t] <= 11.0:
		_badge_star(b, br, Color("ffd769"))
	elif Blocks.falls[t] == 1:
		draw_circle(b, br, Color(0.1, 0.12, 0.25, 0.85))
		draw_arc(b + Vector2(-br * 0.4, 0), br * 0.35, PI, TAU, 6, Color("ffe2a0"), 2.0)
		draw_arc(b + Vector2(br * 0.3, 0), br * 0.35, 0, PI, 6, Color("ffe2a0"), 2.0)
	elif Blocks.drill[t] == 1:
		draw_circle(b, br, Color(0.1, 0.12, 0.25, 0.85))
		draw_colored_polygon(PackedVector2Array([b + Vector2(0, -br * 0.7), b + Vector2(br * 0.5, br * 0.5), b + Vector2(-br * 0.5, br * 0.5)]), Color("ffb03b"))
	elif Blocks.impact[t] < 0.0 and Blocks.drill[t] == 0:
		draw_circle(b, br, Color(0.1, 0.12, 0.25, 0.85))
		draw_arc(b + Vector2(0, -br * 0.15), br * 0.32, PI, TAU, 8, Color(1, 1, 1, 0.8), 2.0)
		draw_rect(Rect2(b + Vector2(-br * 0.42, -br * 0.15), Vector2(br * 0.84, br * 0.6)), Color(1, 1, 1, 0.8))

func _badge_star(b: Vector2, br: float, col: Color) -> void:
	draw_circle(b, br, Color(0.1, 0.12, 0.25, 0.85))
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		var rr := br * (0.75 if k % 2 == 0 else 0.32)
		pts.append(b + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)

## 物块的说明（名字下面那一行）
static func describe(c: int, i: int) -> String:
	if c == 1:
		return {
			"spawn": "PIX 从这里出发", "goal": "碰到就过关", "checkpoint": "掉下去从这里重来", "coin": "一枚金币",
			"coin_ring": "一圈 8 枚金币", "chest": "打开得到金币", "seed": "救出一只噗噗", "bounce": "踩上去弹得很高",
			"fan": "气泡形态能乘着它飘上去", "scrapling": "正面有盾，绕到侧后撞", "rustfly": "会俯冲，扎地时撞它",
			"spikeshell": "背上有刺，收刺时撞", "sentinel": "站岗巡视", "mortar": "抛射锈弹，用气浪打回去", "burrower": "从地下钻出来",
		}.get(LevelData.OBJECTS[i][0], "")
	var t: int = LevelData.BLOCKS[i][0]
	var tags: Array[String] = []
	if Blocks.smooth[t] == 1:
		tags.append("自然地形（圆润）")
	if Blocks.impact[t] >= 0.0:
		tags.append("撞碎需要 %.0f m/s" % Blocks.impact[t])
	if Blocks.drill[t] == 1:
		tags.append("钻头可钻")
	if Blocks.impact[t] < 0.0 and Blocks.drill[t] == 0:
		tags.append("打不坏")
	if Blocks.falls[t] == 1:
		tags.append("失去支撑会塌")
	if Blocks.burn[t] > 0.0:
		tags.append("可燃")
	if Blocks.conductive[t] == 1:
		tags.append("导电")
	if Blocks.explodes[t] == 1:
		tags.append("会爆炸")
	if Blocks.chain[t] == 1:
		tags.append("连锁崩塌")
	if Blocks.render[t] == Blocks.Render.GLOW:
		tags.append("发光")
	return " · ".join(tags)
