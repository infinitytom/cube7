// 体素通用着色：积木倒角 + 像素颗粒 + 草方块侧面露土
// 顶点色：rgb = 方块本色（线性空间），a = 光照系数（面朝向 × 烘焙 AO）
// UV = 面内坐标 0..1，UV2.x = 方块类型 id / 255

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying float v_type;

uniform vec3 dirt_color : source_color = vec3(0.925, 0.604, 0.455);
uniform float bevel_width = 0.075;
uniform float bevel_dark = 0.14;
uniform float speckle = 0.035;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_type = UV2.x * 255.0;
}

vec3 voxel_albedo(vec3 base, float light, vec2 uv) {
	vec3 col = base;
	// 草方块侧面：下部是泥土，上沿一圈不规则的草边
	if (abs(v_type - 2.0) < 0.5 && abs(v_wnorm.y) < 0.5) {
		float h = fract(v_wpos.y * 2.0 + 0.0001);
		vec3 cell = floor(v_wpos * 8.0 + v_wnorm * 0.1);
		float lip = 0.62 + 0.18 * hash13(vec3(cell.x + cell.z, 0.0, cell.z - cell.x));
		col = h > lip ? base : dirt_color;
	}
	// 像素颗粒：每个方块面 4×4 格的轻微明暗变化
	vec3 px = floor(v_wpos * 8.0 + v_wnorm * 0.1);
	col *= 1.0 - speckle + 2.0 * speckle * hash13(px);
	// 倒角：边缘压暗，顶面内沿提亮，形成玩具积木的圆润感
	float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float b = smoothstep(0.0, bevel_width, e);
	col *= mix(1.0 - bevel_dark, 1.0, b);
	if (v_wnorm.y > 0.5) {
		col *= 1.0 + 0.08 * (1.0 - smoothstep(bevel_width, bevel_width * 2.2, e)) * b;
	}
	return col * light;
}
