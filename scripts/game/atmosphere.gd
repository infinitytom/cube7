class_name Atmosphere
extends RefCounted
## 每一章的“天气”：天空配色、太阳角度、雾、云海颜色。关卡 build() 时调用 Atmosphere.apply(self, "greenhouse")。
## 天空用 shaders/sky.gdshader（渐变 + 积云带 + 带光环的巨型行星 + 卫星），云海颜色和地平线自动对齐。

const PRESETS := {
	# 第一章：晴朗的上午，清透的蓝，远处是一圈白色积云
	"greenhouse": {
		"top": Color(0.20, 0.45, 0.93), "mid": Color(0.47, 0.71, 1.0), "horizon": Color(0.88, 0.94, 1.0), "bottom": Color(0.62, 0.74, 0.97),
		"sun_rot": Vector3(-40, -140, 0), "sun_color": Color(1.0, 0.95, 0.86), "sun_energy": 1.5, "sun_tint": Color(1.0, 0.93, 0.8),
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.74, 0.80, 0.96), "gap": Color(0.52, 0.62, 0.92),
		"fog": Color(0.80, 0.88, 1.0), "fog_density": 0.0011, "fog_height": -6.0, "fog_height_density": 0.035,
		"planet": Vector3(-0.2, 0.42, -0.88), "planet_radius": 0.1, "planet_color": Color(0.88, 0.80, 1.0), "planet_band": Color(0.66, 0.62, 0.95),
		"moon": Vector3(0.95, 0.22, 0.2), "stars": 0.0, "horizon_glow": 0.25, "ambient": 1.0,
	},
	# 第二章：工坊的黄昏——低低的橙色太阳，紫色的天，烟囱的剪影
	"gearworks": {
		"top": Color(0.20, 0.25, 0.62), "mid": Color(0.62, 0.52, 0.78), "horizon": Color(1.0, 0.78, 0.58), "bottom": Color(0.78, 0.6, 0.66),
		"sun_rot": Vector3(-17, -118, 0), "sun_color": Color(1.0, 0.78, 0.55), "sun_energy": 1.65, "sun_tint": Color(1.0, 0.62, 0.35),
		"cloud_lit": Color(1.0, 0.88, 0.76), "cloud_shade": Color(0.86, 0.7, 0.78), "gap": Color(0.62, 0.52, 0.74),
		"fog": Color(0.98, 0.8, 0.7), "fog_density": 0.001, "fog_height": -8.0, "fog_height_density": 0.02,
		"planet": Vector3(-0.35, 0.33, -0.88), "planet_radius": 0.12, "planet_color": Color(0.98, 0.78, 0.86), "planet_band": Color(0.8, 0.56, 0.78),
		"moon": Vector3(0.2, 0.45, -0.85), "stars": 0.25, "horizon_glow": 0.55, "ambient": 0.95,
	},
	# 标题画面：暖黄昏
	"title": {
		"top": Color(0.22, 0.42, 0.92), "mid": Color(0.62, 0.66, 0.95), "horizon": Color(1.0, 0.86, 0.74), "bottom": Color(0.72, 0.72, 0.9),
		"sun_rot": Vector3(-32, 0, 0), "sun_color": Color(1.0, 0.9, 0.78), "sun_energy": 1.55, "sun_tint": Color(1.0, 0.75, 0.5),
		"cloud_lit": Color(1.0, 0.95, 0.9), "cloud_shade": Color(0.74, 0.72, 0.9), "gap": Color(0.5, 0.52, 0.85),
		"fog": Color(1.0, 0.9, 0.8), "fog_density": 0.0012, "fog_height": -6.0, "fog_height_density": 0.03,
		"planet": Vector3(-0.5, 0.3, -0.8), "planet_radius": 0.11, "planet_color": Color(0.9, 0.82, 1.0), "planet_band": Color(0.72, 0.64, 0.95),
		"moon": Vector3(0.4, 0.4, -0.8), "stars": 0.1, "horizon_glow": 0.45, "ambient": 1.0,
	},
}

static var current := {}

static func preset(name: String) -> Dictionary:
	return PRESETS.get(name, PRESETS["greenhouse"])

## 把预设套到场景里的 WorldEnvironment 和 Sun 上。keep_sun_yaw：标题画面自己控制太阳朝向
static func apply(node: Node, name: String, keep_sun_yaw := false) -> Dictionary:
	var p := preset(name)
	current = p
	var root := node
	while root and root.get_node_or_null("WorldEnvironment") == null:
		root = root.get_parent()
	if root == null:
		return p
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		var env := we.environment.duplicate() as Environment
		var sky := Sky.new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/sky.gdshader")
		mat.set_shader_parameter("top_color", p.top)
		mat.set_shader_parameter("mid_color", p.mid)
		mat.set_shader_parameter("horizon_color", p.horizon)
		mat.set_shader_parameter("bottom_color", p.bottom)
		mat.set_shader_parameter("sun_tint", p.sun_tint)
		mat.set_shader_parameter("cloud_lit", p.cloud_lit)
		mat.set_shader_parameter("cloud_shade", p.cloud_shade)
		mat.set_shader_parameter("planet_dir", p.planet)
		mat.set_shader_parameter("planet_radius", p.planet_radius)
		mat.set_shader_parameter("planet_color", p.planet_color)
		mat.set_shader_parameter("planet_band", p.planet_band)
		mat.set_shader_parameter("moon_dir", p.moon)
		mat.set_shader_parameter("star_amount", p.stars)
		mat.set_shader_parameter("horizon_glow", p.horizon_glow)
		sky.sky_material = mat
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = p.ambient
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = p.fog
		env.fog_density = p.fog_density
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.35
		env.fog_height = p.fog_height
		env.fog_height_density = p.fog_height_density
		env.glow_enabled = true
		env.glow_intensity = 0.75
		env.glow_bloom = 0.06
		env.glow_hdr_threshold = 1.1
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.08
		env.adjustment_contrast = 1.03
		we.environment = env
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		if keep_sun_yaw:
			sun.rotation_degrees.x = (p.sun_rot as Vector3).x
		else:
			sun.rotation_degrees = p.sun_rot
		sun.light_color = p.sun_color
		sun.light_energy = p.sun_energy
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 70.0
	return p

## 云海材质参数（和天空地平线对齐）
static func sea_params(mat: ShaderMaterial, sun_dir: Vector3) -> void:
	var p := current if not current.is_empty() else preset("greenhouse")
	mat.set_shader_parameter("horizon_color", p.horizon)
	mat.set_shader_parameter("cloud_color", p.cloud_lit)
	mat.set_shader_parameter("shadow_color", p.cloud_shade)
	mat.set_shader_parameter("gap_color", p.gap)
	mat.set_shader_parameter("sun_color", p.sun_tint)
	mat.set_shader_parameter("sun_dir", sun_dir)
