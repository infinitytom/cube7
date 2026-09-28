class_name SkyWorld
extends Node3D
## 浮岛的外部世界：远处一直铺到地平线的云海 + 云海上鼓起的大团积云 + 飘过的云朵 + 鸟群。纯装饰，不参与碰撞。
## 远处的浮岛、山峰、塔由 Vista 负责。

@export var sea_height := -30.0
@export var center := Vector3(32, 0, 26)
@export var cloud_count := 22
@export var bird_flocks := 3

var _clouds: Array[Node3D] = []
var _speeds: Array[float] = []
var _sea_mat: ShaderMaterial

func _ready() -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	pm.subdivide_depth = 0
	pm.subdivide_width = 0
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = load("res://shaders/cloud_sea.gdshader")
	pm.material = _sea_mat
	sea.mesh = pm
	sea.position = Vector3(center.x, sea_height, center.z)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	_sync_colors.call_deferred()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := StandardMaterial3D.new()
	var p := Atmosphere.current if not Atmosphere.current.is_empty() else Atmosphere.preset("greenhouse")
	mat.albedo_color = p.cloud_lit
	mat.roughness = 1.0
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.3
	mat.emission_enabled = true
	mat.emission = p.cloud_shade
	mat.emission_energy_multiplier = 0.35
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 1.6
	sph.radial_segments = 16
	sph.rings = 8
	for i in cloud_count:
		var puff := Node3D.new()
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(90.0, 320.0)
		var low := rng.randf() < 0.55
		var y := sea_height + rng.randf_range(0.0, 6.0) if low else rng.randf_range(10.0, 60.0)
		puff.position = center + Vector3(cos(ang) * dist, y, sin(ang) * dist)
		var n := rng.randi_range(5, 9)
		var big := rng.randf_range(1.0, 2.2) * (1.6 if low else 1.0)
		for k in n:
			var mi := MeshInstance3D.new()
			mi.mesh = sph
			var r := rng.randf_range(3.5, 7.5) * big
			mi.scale = Vector3(r, r, r)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var along := (k - n * 0.5) * 4.5 * big
			mi.position = Vector3(along + rng.randf_range(-1, 1), rng.randf_range(-0.5, 2.5) * big * (1.0 - absf(along) / (n * 3.0 * big)) , rng.randf_range(-2.5, 2.5) * big)
			puff.add_child(mi)
		puff.rotation.y = rng.randf() * TAU
		add_child(puff)
		_clouds.append(puff)
		_speeds.append(rng.randf_range(0.3, 0.9))
	for f in bird_flocks:
		var b := Birds.new()
		var ba := rng.randf() * TAU
		b.center = center + Vector3(cos(ba) * 90.0, rng.randf_range(20.0, 45.0), sin(ba) * 90.0)
		b.radius = rng.randf_range(25.0, 55.0)
		b.count = rng.randi_range(5, 9)
		b.seed_v = f * 13 + 3
		add_child(b)

func _sync_colors() -> void:
	var root: Node = self
	while root and root.get_node_or_null("Sun") == null:
		root = root.get_parent()
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D if root else null
	var sd := Vector3(0.4, 0.7, 0.3)
	if sun:
		sd = sun.global_basis.z
	Atmosphere.sea_params(_sea_mat, sd)

func _process(delta: float) -> void:
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _speeds[i] * delta
		if c.position.x > center.x + 340.0:
			c.position.x = center.x - 340.0
