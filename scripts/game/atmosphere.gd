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
		"fog": Color(0.80, 0.88, 1.0), "fog_density": 0.00077, "fog_height": -6.0, "fog_height_density": 0.0140,
		"planet": Vector3(-0.2, 0.42, -0.88), "planet_radius": 0.1, "planet_color": Color(0.88, 0.80, 1.0), "planet_band": Color(0.66, 0.62, 0.95),
		"moon": Vector3(0.95, 0.22, 0.2), "stars": 0.0, "horizon_glow": 0.25, "ambient": 1.0,
	},
	# 第二章：工坊的黄昏——低低的橙色太阳，紫色的天，烟囱的剪影
	"gearworks": {
		"top": Color(0.20, 0.25, 0.62), "mid": Color(0.62, 0.52, 0.78), "horizon": Color(1.0, 0.78, 0.58), "bottom": Color(0.78, 0.6, 0.66),
		"sun_rot": Vector3(-17, -118, 0), "sun_color": Color(1.0, 0.78, 0.55), "sun_energy": 1.65, "sun_tint": Color(1.0, 0.62, 0.35),
		"cloud_lit": Color(1.0, 0.88, 0.76), "cloud_shade": Color(0.86, 0.7, 0.78), "gap": Color(0.62, 0.52, 0.74),
		"fog": Color(0.98, 0.8, 0.7), "fog_density": 0.00070, "fog_height": -8.0, "fog_height_density": 0.0080,
		"planet": Vector3(-0.35, 0.33, -0.88), "planet_radius": 0.12, "planet_color": Color(0.98, 0.78, 0.86), "planet_band": Color(0.8, 0.56, 0.78),
		"moon": Vector3(0.2, 0.45, -0.85), "stars": 0.25, "horizon_glow": 0.55, "ambient": 0.95,
	},
	# 第三章：晶簇深渊——清冷的蓝紫色午后，远处漂着巨大的晶体
	"abyss": {
		"top": Color(0.16, 0.26, 0.62), "mid": Color(0.42, 0.52, 0.92), "horizon": Color(0.78, 0.84, 1.0), "bottom": Color(0.55, 0.6, 0.9),
		"sun_rot": Vector3(-48, 150, 0), "sun_color": Color(0.92, 0.94, 1.0), "sun_energy": 1.35, "sun_tint": Color(0.85, 0.8, 1.0),
		"cloud_lit": Color(0.96, 0.96, 1.0), "cloud_shade": Color(0.7, 0.72, 0.95), "gap": Color(0.48, 0.5, 0.88),
		"fog": Color(0.72, 0.78, 1.0), "fog_density": 0.00084, "fog_height": 2.0, "fog_height_density": 0.0120,
		"planet": Vector3(0.5, 0.4, -0.75), "planet_radius": 0.13, "planet_color": Color(0.8, 0.9, 1.0), "planet_band": Color(0.6, 0.7, 0.98),
		"moon": Vector3(-0.6, 0.5, -0.6), "stars": 0.15, "horizon_glow": 0.3, "ambient": 1.05,
	},
	# 第四章：云顶之城——高空的正午，天很蓝，云海在很远的下面
	"city": {
		"top": Color(0.14, 0.4, 0.95), "mid": Color(0.4, 0.66, 1.0), "horizon": Color(0.9, 0.95, 1.0), "bottom": Color(0.7, 0.8, 1.0),
		"sun_rot": Vector3(-58, -60, 0), "sun_color": Color(1.0, 0.97, 0.9), "sun_energy": 1.6, "sun_tint": Color(1.0, 0.95, 0.85),
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.78, 0.84, 0.98), "gap": Color(0.55, 0.66, 0.95),
		"fog": Color(0.84, 0.9, 1.0), "fog_density": 0.00063, "fog_height": -10.0, "fog_height_density": 0.0120,
		"planet": Vector3(0.3, 0.5, -0.8), "planet_radius": 0.12, "planet_color": Color(0.9, 0.86, 1.0), "planet_band": Color(0.7, 0.66, 0.95),
		"moon": Vector3(-0.7, 0.45, -0.4), "stars": 0.0, "horizon_glow": 0.2, "ambient": 1.05,
	},
	# 第五章：锈海——尘土飞扬的橙色午后，天边一层锈色的雾
	"rust": {
		"top": Color(0.30, 0.38, 0.62), "mid": Color(0.74, 0.58, 0.52), "horizon": Color(1.0, 0.76, 0.54), "bottom": Color(0.72, 0.5, 0.38),
		"sun_rot": Vector3(-24, -135, 0), "sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 1.55, "sun_tint": Color(1.0, 0.66, 0.4),
		"cloud_lit": Color(1.0, 0.88, 0.74), "cloud_shade": Color(0.84, 0.64, 0.56), "gap": Color(0.66, 0.5, 0.52),
		"fog": Color(0.94, 0.78, 0.64), "fog_density": 0.00091, "fog_height": 4.0, "fog_height_density": 0.0060,
		"planet": Vector3(0.45, 0.35, -0.82), "planet_radius": 0.14, "planet_color": Color(1.0, 0.84, 0.76), "planet_band": Color(0.86, 0.6, 0.56),
		"moon": Vector3(-0.5, 0.5, -0.7), "stars": 0.1, "horizon_glow": 0.6, "ambient": 1.0,
	},
	# 终章：星核——高空，天很深，星星都看得见；云海在很远的下面
	"core": {
		"top": Color(0.06, 0.08, 0.3), "mid": Color(0.2, 0.26, 0.62), "horizon": Color(0.62, 0.66, 0.95), "bottom": Color(0.4, 0.44, 0.8),
		"sun_rot": Vector3(-30, 40, 0), "sun_color": Color(1.0, 0.95, 0.9), "sun_energy": 1.5, "sun_tint": Color(1.0, 0.9, 0.8),
		"cloud_lit": Color(0.95, 0.95, 1.0), "cloud_shade": Color(0.6, 0.62, 0.9), "gap": Color(0.3, 0.34, 0.7),
		"fog": Color(0.55, 0.6, 0.95), "fog_density": 0.0005, "fog_height": -60.0, "fog_height_density": 0.004,
		"planet": Vector3(-0.4, 0.45, -0.8), "planet_radius": 0.2, "planet_color": Color(0.9, 0.84, 1.0), "planet_band": Color(0.7, 0.62, 0.95),
		"moon": Vector3(0.6, 0.55, -0.5), "stars": 0.8, "horizon_glow": 0.35, "ambient": 1.0,
	},
	# 结局：星球重构完成的黎明
	"dawn": {
		"top": Color(0.2, 0.4, 0.9), "mid": Color(0.6, 0.72, 1.0), "horizon": Color(1.0, 0.88, 0.72), "bottom": Color(0.7, 0.78, 0.98),
		"sun_rot": Vector3(-20, 40, 0), "sun_color": Color(1.0, 0.9, 0.78), "sun_energy": 1.7, "sun_tint": Color(1.0, 0.8, 0.6),
		"cloud_lit": Color(1.0, 0.97, 0.92), "cloud_shade": Color(0.8, 0.8, 0.96), "gap": Color(0.55, 0.62, 0.95),
		"fog": Color(0.95, 0.9, 0.85), "fog_density": 0.0005, "fog_height": -60.0, "fog_height_density": 0.004,
		"planet": Vector3(-0.4, 0.45, -0.8), "planet_radius": 0.2, "planet_color": Color(0.95, 0.9, 1.0), "planet_band": Color(0.75, 0.7, 0.98),
		"moon": Vector3(0.6, 0.55, -0.5), "stars": 0.2, "horizon_glow": 0.6, "ambient": 1.1,
	},
	# 标题画面：暖黄昏
	"title": {
		"top": Color(0.22, 0.42, 0.92), "mid": Color(0.62, 0.66, 0.95), "horizon": Color(1.0, 0.86, 0.74), "bottom": Color(0.72, 0.72, 0.9),
		"sun_rot": Vector3(-32, 0, 0), "sun_color": Color(1.0, 0.9, 0.78), "sun_energy": 1.55, "sun_tint": Color(1.0, 0.75, 0.5),
		"cloud_lit": Color(1.0, 0.95, 0.9), "cloud_shade": Color(0.74, 0.72, 0.9), "gap": Color(0.5, 0.52, 0.85),
		"fog": Color(1.0, 0.9, 0.8), "fog_density": 0.00084, "fog_height": -6.0, "fog_height_density": 0.0120,
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
		env.ambient_light_energy = p.ambient * 0.85
		env.fog_enabled = bool(Settings.get_v("fog"))
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = p.fog
		env.fog_density = p.fog_density
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.35
		env.fog_height = p.fog_height
		env.fog_height_density = p.fog_height_density
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_bloom = 0.06
		env.glow_hdr_threshold = 1.1
		# 柔和的环境光遮蔽：平滑地形的坑底、缝里自然变暗（奥德赛那种“软”的体积感）
		env.ssao_enabled = bool(Settings.get_v("ssao"))
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.ssao_power = 1.3
		env.ssao_light_affect = 0.15
		env.adjustment_enabled = true
		env.adjustment_saturation = 0.98
		env.adjustment_contrast = 1.08
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
