class_name Ambient
extends Node3D
## 环境里的小生命：成群的蝴蝶在花丛附近绕圈飞，让浮岛不再“空落落”。

var area_lo := Vector3.ZERO
var area_hi := Vector3(60, 12, 50)
var count := 18

const COLORS := [Color("ff9ad5"), Color("ffd769"), Color("9aa8ff"), Color("7dffc8"), Color("ffffff")]

class Fly:
	var node: Node3D
	var wings: Array[MeshInstance3D] = []
	var home := Vector3.ZERO
	var phase := 0.0
	var speed := 1.0
	var radius := 1.5

var _flies: Array = []
var _t := 0.0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.12)
	for i in count:
		var f := Fly.new()
		f.node = Node3D.new()
		add_child(f.node)
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[rng.randi() % COLORS.size()]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for sgn in [-1.0, 1.0]:
			var pivot := Node3D.new()
			f.node.add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = quad
			w.material_override = m
			w.position = Vector3(0.08 * sgn, 0, 0)
			w.rotation_degrees.x = -90.0
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(w)
			f.wings.append(w)
		f.home = Vector3(rng.randf_range(area_lo.x, area_hi.x), rng.randf_range(area_lo.y, area_hi.y), rng.randf_range(area_lo.z, area_hi.z))
		f.phase = rng.randf() * TAU
		f.speed = rng.randf_range(0.5, 1.1)
		f.radius = rng.randf_range(0.8, 2.2)
		_flies.append(f)

func _process(delta: float) -> void:
	_t += delta
	for f in _flies:
		var a: float = _t * f.speed + f.phase
		var p: Vector3 = f.home + Vector3(cos(a) * f.radius, sin(a * 2.3) * 0.35 + sin(a * 0.7) * 0.3, sin(a * 1.3) * f.radius)
		var nxt: Vector3 = f.home + Vector3(cos(a + 0.1) * f.radius, 0, sin((a + 0.1) * 1.3) * f.radius)
		f.node.position = p
		var d: Vector3 = nxt - Vector3(p.x, f.home.y, p.z)
		if d.length() > 0.001:
			f.node.rotation.y = atan2(d.x, d.z)
		var flap := sin(_t * 18.0 + f.phase) * 1.1
		(f.wings[0].get_parent() as Node3D).rotation.z = flap
		(f.wings[1].get_parent() as Node3D).rotation.z = -flap
