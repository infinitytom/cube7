class_name SkyWorld
extends Node3D
## 浮岛的外部世界：云海 + 漂浮的蓬松云朵。纯装饰，不参与碰撞。

@export var sea_height := 1.0
@export var center := Vector3(32, 0, 26)
@export var cloud_count := 14

var _clouds: Array[Node3D] = []
var _speeds: Array[float] = []

func _ready() -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	pm.subdivide_depth = 1
	pm.subdivide_width = 1
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/cloud_sea.gdshader")
	pm.material = sm
	sea.mesh = pm
	sea.position = Vector3(center.x, sea_height, center.z)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	_build_far_islands()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 1.0
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.92, 1.0)
	mat.emission_energy_multiplier = 0.15
	for i in cloud_count:
		var puff := Node3D.new()
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(100.0, 170.0)
		puff.position = center + Vector3(cos(ang) * dist, rng.randf_range(-4.0, 26.0), sin(ang) * dist)
		var n := rng.randi_range(4, 7)
		for k in n:
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			var r := rng.randf_range(3.5, 7.0)
			s.radius = r
			s.height = r * 1.6
			s.radial_segments = 16
			s.rings = 8
			mi.mesh = s
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(k * 5.0 - n * 2.5 + rng.randf_range(-1, 1), rng.randf_range(-0.5, 1.5), rng.randf_range(-1.5, 1.5))
			puff.add_child(mi)
		puff.rotation.y = rng.randf() * TAU
		add_child(puff)
		_clouds.append(puff)
		_speeds.append(rng.randf_range(0.3, 0.8))

## 远处的小浮岛：草顶 + 倒锥形的土台 + 几棵树，缓缓上下浮动，给天空加上纵深
var _islands: Array[Node3D] = []

func _build_far_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("66daa3")
	grass.roughness = 0.9
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("d88a6c")
	dirt.roughness = 0.9
	for i in 9:
		var root := Node3D.new()
		add_child(root)
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(75.0, 150.0)
		var r := rng.randf_range(3.0, 8.0)
		root.position = center + Vector3(cos(ang) * dist, rng.randf_range(4.0, 26.0), sin(ang) * dist)
		var top := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = r
		tm.bottom_radius = r * 1.02
		tm.height = r * 0.25
		tm.radial_segments = 7
		tm.rings = 1
		top.mesh = tm
		top.material_override = grass
		root.add_child(top)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * 1.0
		cm.bottom_radius = r * 0.12
		cm.height = r * 1.6
		cm.radial_segments = 7
		cm.rings = 2
		cone.mesh = cm
		cone.material_override = dirt
		cone.position.y = -r * 0.92
		root.add_child(cone)
		for k in rng.randi_range(1, 4):
			var tree := Kit.model(Kit.TREES[rng.randi() % Kit.TREES.size()])
			var b := Kit.bounds(tree)
			var s := rng.randf_range(2.5, 4.5) / maxf(b.size.y, 0.01)
			tree.scale = Vector3.ONE * s
			var ta := rng.randf() * TAU
			var td := rng.randf_range(0.0, r * 0.6)
			tree.position = Vector3(cos(ta) * td, r * 0.125 - b.position.y * s, sin(ta) * td)
			root.add_child(tree)
		root.rotation.y = rng.randf() * TAU
		root.set_meta("base_y", root.position.y)
		root.set_meta("phase", rng.randf() * TAU)
		_islands.append(root)

func _process(delta: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for isl in _islands:
		isl.position.y = float(isl.get_meta("base_y")) + sin(tt * 0.3 + float(isl.get_meta("phase"))) * 0.8
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _speeds[i] * delta
		if c.position.x > center.x + 190.0:
			c.position.x = center.x - 190.0
