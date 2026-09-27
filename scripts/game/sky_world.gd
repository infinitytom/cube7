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

func _process(delta: float) -> void:
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _speeds[i] * delta
		if c.position.x > center.x + 190.0:
			c.position.x = center.x - 190.0
