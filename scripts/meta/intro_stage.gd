class_name IntroStage
extends Node3D
## 开场 CG 的太空舞台：伊甸-7 星球 → 日冕潮扑来 → 方舟引擎把整颗星球“拆成方块” → 云海护盾合拢。
## 放在远离浮岛的地方，外面包一层星空球，镜头在里面拍。时间轴从 play() 开始计：
##   0–7 星球自转 · 7–13 日冕潮逼近 · 13–15.5 由朝阳面开始逐块方块化 · 15.5–21 方块向外散开、护盾形成

const R := 6.0
const STAR_DIR := Vector3(-0.8, 0.15, -0.55)
const STAR_DIST := 70.0

var _t := -1.0
var _planet: MeshInstance3D
var _clouds: MeshInstance3D
var _planet_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _mm: MultiMesh
var _cubes: MultiMeshInstance3D
var _base: Array[Transform3D] = []
var _delay: PackedFloat32Array = PackedFloat32Array()
var _drift: PackedFloat32Array = PackedFloat32Array()
var _star_light: OmniLight3D
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _noise := FastNoiseLite.new()

func _ready() -> void:
	_noise.seed = 3
	_noise.frequency = 0.28
	_build_space()
	_build_planet()
	_build_cubes()
	_build_fx()

func planet_center() -> Vector3:
	return global_position

func _nofog(m: BaseMaterial3D) -> void:
	m.disable_fog = true

func _build_space() -> void:
	# 星空球：从里面看，深靛蓝渐变 + 星点
	var sky := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 120.0
	sm.height = 240.0
	sm.radial_segments = 32
	sm.rings = 16
	sky.mesh = sm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
float h(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.yzx + 33.33); return fract((p.x + p.y) * p.z); }
void fragment() {
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 col = mix(vec3(0.03, 0.03, 0.12), vec3(0.12, 0.08, 0.28), smoothstep(-0.6, 0.8, d.y));
	vec3 g = floor(d * 260.0);
	float s = step(0.9965, h(g));
	col += vec3(0.9, 0.95, 1.0) * s * (0.5 + 0.5 * h(g + 7.0));
	// 远处的淡紫色星云
	col += vec3(0.35, 0.2, 0.5) * 0.25 * smoothstep(0.55, 1.0, dot(d, normalize(vec3(0.6, 0.3, 0.7))));
	ALBEDO = col;
}
"""
	mat.shader = sh
	sky.material_override = mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)
	# 恒星：发光球 + 点光源
	var star := MeshInstance3D.new()
	var stm := SphereMesh.new()
	stm.radius = 7.0
	stm.height = 14.0
	star.mesh = stm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.85, 0.55)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.7, 0.35)
	smat.emission_energy_multiplier = 6.0
	_nofog(smat)
	star.material_override = smat
	star.position = STAR_DIR.normalized() * STAR_DIST
	add_child(star)
	_star_light = OmniLight3D.new()
	_star_light.light_color = Color(1.0, 0.85, 0.65)
	_star_light.light_energy = 6.0
	_star_light.omni_range = 140.0
	_star_light.omni_attenuation = 0.4
	_star_light.position = star.position * 0.7
	add_child(_star_light)

func _build_planet() -> void:
	_planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	_planet.mesh = sm
	_planet_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode fog_disabled;
uniform float dissolve = 0.0;
varying vec3 opos;
float h(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.yzx + 33.33); return fract((p.x + p.y) * p.z); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { opos = VERTEX; }
void fragment() {
	vec3 p = normalize(opos);
	float n = vn(p * 3.0) * 0.6 + vn(p * 7.0) * 0.3 + vn(p * 15.0) * 0.1;
	vec3 ocean = mix(vec3(0.18, 0.4, 0.9), vec3(0.3, 0.62, 1.0), vn(p * 5.0));
	vec3 land = mix(vec3(0.4, 0.85, 0.64), vec3(0.93, 0.6, 0.45), smoothstep(0.62, 0.75, n));
	vec3 col = n > 0.52 ? land : ocean;
	col = mix(col, vec3(0.95, 0.97, 1.0), smoothstep(0.82, 0.9, abs(p.y)));
	ALBEDO = col;
	ROUGHNESS = n > 0.52 ? 0.85 : 0.3;
	// 方块化：像素格子状的溶解
	float cell = h(floor(p * 18.0));
	if (cell < dissolve) { discard; }
	RIM = 0.4;
}
"""
	_planet_mat.shader = sh
	_planet.material_override = _planet_mat
	add_child(_planet)
	_clouds = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = R * 1.035
	cm.height = R * 2.07
	cm.radial_segments = 48
	cm.rings = 24
	_clouds.mesh = cm
	_cloud_mat = ShaderMaterial.new()
	var csh := Shader.new()
	csh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, fog_disabled;
uniform float fade = 1.0;
varying vec3 opos;
float h(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.yzx + 33.33); return fract((p.x + p.y) * p.z); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { opos = VERTEX; }
void fragment() {
	vec3 p = normalize(opos);
	float n = vn(p * 4.0 + vec3(TIME * 0.05, 0.0, 0.0)) * 0.7 + vn(p * 9.0) * 0.3;
	ALBEDO = vec3(1.0);
	ALPHA = smoothstep(0.55, 0.75, n) * 0.85 * fade;
}
"""
	_cloud_mat.shader = csh
	_clouds.material_override = _cloud_mat
	add_child(_clouds)

func _land_color(n: Vector3) -> Color:
	var v := (_noise.get_noise_3dv(n * 3.0) + 1.0) * 0.5
	if absf(n.y) > 0.86:
		return Color("f4f6ff")
	if v > 0.55:
		return Color("66daa3") if v < 0.68 else Color("ec9a74")
	return Color("5a9dff")

func _build_cubes() -> void:
	# 斐波那契球面均匀撒点，每个点一块方块，颜色取自同一块大陆
	var count := 1500
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.62
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.6
	_nofog(bm)
	box.material = bm
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = count
	var ga := PI * (3.0 - sqrt(5.0))
	var to_star := STAR_DIR.normalized()
	_delay.resize(count)
	_drift.resize(count)
	for i in count:
		var y := 1.0 - (i / float(count - 1)) * 2.0
		var rr := sqrt(1.0 - y * y)
		var th := ga * i
		var n := Vector3(cos(th) * rr, y, sin(th) * rr)
		var b := Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT)
		var t := Transform3D(b, n * (R - 0.15))
		_base.append(t)
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), t.origin))
		_mm.set_instance_color(i, _land_color(n))
		# 朝向恒星的一面先方块化，然后像波一样扫到背面
		_delay[i] = (1.0 - n.dot(to_star)) * 0.5 * 2.2 + randf() * 0.25
		_drift[i] = randf_range(0.5, 1.6)
	_cubes = MultiMeshInstance3D.new()
	_cubes.multimesh = _mm
	add_child(_cubes)

func _build_fx() -> void:
	# 日冕潮：从恒星扩散过来的橙色光壳
	_flare = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	_flare.mesh = sm
	_flare_mat = _rim_mat(Color(1.0, 0.6, 0.3), 3.0)
	_flare.material_override = _flare_mat
	_flare.position = STAR_DIR.normalized() * STAR_DIST
	_flare.visible = false
	add_child(_flare)
	# 云海护盾：方块化之后在外面合拢的一层柔光
	_shield = MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 1.0
	shm.height = 2.0
	shm.radial_segments = 48
	shm.rings = 24
	_shield.mesh = shm
	_shield_mat = _rim_mat(Color(0.8, 0.93, 1.0), 2.2)
	_shield.material_override = _shield_mat
	_shield.scale = Vector3.ONE * (R * 1.6)
	add_child(_shield)

## 只有边缘发光的透明球壳（菲涅尔）：看起来像光的波前 / 能量护盾，而不是一个实心球
func _rim_mat(c: Color, power: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform float power = 3.0;
uniform float strength = 0.0;
void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), power);
	ALBEDO = tint * (f * 1.6 + 0.04) * strength;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("power", power)
	return m

func play() -> void:
	_t = 0.0

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var spin := _t * 0.06
	_planet.rotation.y = spin
	_clouds.rotation.y = spin * 1.3
	_cubes.rotation.y = spin
	# 日冕潮：7 秒起从恒星扩散，13 秒扫过星球，16 秒后散去
	if _t > 7.0 and _t < 18.0:
		_flare.visible = true
		var k := clampf((_t - 7.0) / 6.0, 0.0, 1.4)
		_flare.scale = Vector3.ONE * lerpf(8.0, STAR_DIST * 1.05, k)
		var a := smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(1.05, 1.4, k))
		_flare_mat.set_shader_parameter("strength", a)
		_star_light.light_energy = 6.0 + 10.0 * smoothstep(0.5, 1.0, k) * (1.0 - smoothstep(1.1, 1.4, k))
	else:
		_flare.visible = false
	# 13 秒：方舟引擎启动，逐块方块化
	var c := _t - 13.0
	if c > -0.1:
		_planet_mat.set_shader_parameter("dissolve", clampf(c / 2.4, 0.0, 1.0))
		_cloud_mat.set_shader_parameter("fade", 1.0 - clampf(c / 1.2, 0.0, 1.0))
		for i in _base.size():
			var local := c - _delay[i]
			if local < 0.0:
				continue
			var s := clampf(local / 0.25, 0.0, 1.0)
			s = 1.0 + (s - 1.0) * (1.0 - s) * 1.8 if s < 1.0 else 1.0   # 带一点弹性的出现
			var base := _base[i]
			var out := maxf(c - 2.6, 0.0)
			var push := out * 0.35 * _drift[i]
			var o := base.origin + base.origin.normalized() * push + Vector3(0, sin(_t * 0.7 + i) * 0.05 * out, 0)
			var rot := base.basis.rotated(base.origin.normalized(), out * 0.2 * _drift[i])
			_mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3.ONE * clampf(s, 0.0, 1.2)), o))
	# 16 秒起云海护盾合拢
	var sh := clampf((_t - 16.0) / 3.0, 0.0, 1.0)
	_shield_mat.set_shader_parameter("strength", 0.8 * sh)
	_shield.scale = Vector3.ONE * lerpf(R * 3.0, R * 1.9, sh)
