class_name CubeEmblem
extends Control
## 标题徽记：一个缓慢旋转的发光立方体（纯 2D 绘制的 3D 投影）。

var t := 0.0
var spin := 0.35
var glow := Color("4fd1ff")

const V := [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
const FACES := [
	[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
]

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _proj(p: Vector3, b: Basis) -> Vector3:
	var q := b * p
	var k := 3.4 / (3.4 + q.z * 0.35)
	var r := minf(size.x, size.y) * 0.27
	return Vector3(size.x * 0.5 + q.x * r * k, size.y * 0.5 - q.y * r * k, q.z)

func _draw() -> void:
	var b := Basis(Vector3.RIGHT, -0.52) * Basis(Vector3.UP, t * spin + 0.6)
	var light := Vector3(-0.4, 0.8, -0.45).normalized()
	var pts: Array[Vector3] = []
	for v in V:
		pts.append(_proj(v, b))
	# 背后的光晕
	var c := size * 0.5
	for i in 6:
		draw_circle(c, minf(size.x, size.y) * (0.52 - i * 0.06), Color(glow, 0.035 + i * 0.012))
	var order: Array = []
	for f in FACES:
		var n: Vector3 = (b * (V[f[1]] - V[f[0]])).cross(b * (V[f[3]] - V[f[0]]))
		var z := 0.0
		for i in f:
			z += pts[i].z
		order.append({"f": f, "z": z, "n": n.normalized()})
	order.sort_custom(func(a: Dictionary, bb: Dictionary) -> bool: return a.z > bb.z)
	for o in order:
		var n: Vector3 = o.n
		if n.z < -0.02:
			continue   # 背面
		var poly := PackedVector2Array()
		for i in o.f:
			poly.append(Vector2(pts[i].x, pts[i].y))
		var lit := clampf(-n.dot(light) * 0.5 + 0.5, 0.0, 1.0)
		var col := Color("3b3f9a").lerp(Color("8fa8ff"), lit)
		draw_colored_polygon(poly, col)
		# 面上的“7”网格纹：细分线，暗示体素
		for s in [1.0 / 3.0, 2.0 / 3.0]:
			draw_line(poly[0].lerp(poly[1], s), poly[3].lerp(poly[2], s), Color(1, 1, 1, 0.08), 1.0, true)
			draw_line(poly[0].lerp(poly[3], s), poly[1].lerp(poly[2], s), Color(1, 1, 1, 0.08), 1.0, true)
		poly.append(poly[0])
		draw_polyline(poly, Color(glow, 0.9), 2.0, true)
	# 中心的能量核
	var pulse := 0.5 + 0.5 * sin(t * 2.4)
	draw_circle(c, 5.0 + pulse * 1.5, Color(1, 1, 1, 0.9))
	draw_circle(c, 11.0 + pulse * 3.0, Color(glow, 0.25))
