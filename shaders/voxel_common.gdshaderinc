// 体素通用着色（圆角积木风）
// 顶点色：rgb = 方块本色（线性空间），a = 光照系数（面朝向 × 烘焙 AO）
// UV = 面内坐标 0..1（x 沿切线 u，y 沿切线 v）
// UV2.x = 方块类型 id / 255
// UV2.y = (露边掩码 + 类别 × 16) / 255
//   露边掩码 bit0 = -u 边，bit1 = +u，bit2 = -v，bit3 = +v —— 只有“露在外面”的边才做圆角，平地上看不到方格
//   类别：0 打不坏 / 1 撞得碎 / 2 只能钻 / 3 松软

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying float v_type;
varying flat float v_code;

uniform vec3 dirt_color : source_color = vec3(0.925, 0.604, 0.455);
uniform float bevel_width = 0.16;
uniform float bevel_dark = 0.16;
uniform float round_strength = 0.9;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// 平滑的值噪声（大尺度的颜色起伏，代替逐格的颗粒）
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_type = UV2.x * 255.0;
	v_code = floor(UV2.y * 255.0 + 0.5);
}

float edge_bit(float code, float bit) {
	return mod(floor(code / bit), 2.0);
}

// 到“露出来的边”的最近距离（没露的边视为很远）
float exposed_edge_dist(vec2 uv) {
	float m = mod(v_code, 16.0);
	float d = 1.0;
	if (edge_bit(m, 1.0) > 0.5) d = min(d, uv.x);
	if (edge_bit(m, 2.0) > 0.5) d = min(d, 1.0 - uv.x);
	if (edge_bit(m, 4.0) > 0.5) d = min(d, uv.y);
	if (edge_bit(m, 8.0) > 0.5) d = min(d, 1.0 - uv.y);
	return d;
}

float voxel_category() {
	return floor(v_code / 16.0);
}

// 面的两条切线（和网格生成里的 TANGENTS 对应）
void face_axes(vec3 n, out vec3 u, out vec3 v) {
	vec3 an = abs(n);
	if (an.x > 0.5) { u = vec3(0, 1, 0); v = vec3(0, 0, 1); }
	else if (an.y > 0.5) { u = vec3(1, 0, 0); v = vec3(0, 0, 1); }
	else { u = vec3(1, 0, 0); v = vec3(0, 1, 0); }
}

vec3 voxel_albedo(vec3 base, float light, vec2 uv) {
	vec3 col = base;
	float cat = voxel_category();
	// 大尺度的柔和色彩起伏（不按格子走，所以平地看不出方格）
	float n1 = vnoise(v_wpos * 0.35);
	float n2 = vnoise(v_wpos * 1.3);
	float n3 = vnoise(v_wpos * 5.0);
	col *= 0.9 + 0.14 * n1 + 0.06 * n2;
	// 草：顶面带黄绿的斑驳；侧面（垂下的草皮）更深一点
	if (abs(v_type - 2.0) < 0.5) {
		col = mix(col, col * vec3(1.18, 1.12, 0.72), smoothstep(0.55, 0.8, vnoise(v_wpos * 0.6 + 3.1)) * 0.6);
		if (abs(v_wnorm.y) < 0.5) col *= 0.82;
	}
	// 天然岩石/泥土：细碎的颗粒和横向纹理
	if (v_type > 2.5 && v_type < 3.5 || v_type > 24.5 && v_type < 25.5 || v_type > 31.5 && v_type < 33.5) {
		col *= 0.94 + 0.1 * n3;
		if (abs(v_wnorm.y) < 0.5) col *= 0.96 + 0.06 * sin(v_wpos.y * 26.0 + n2 * 4.0);
	}
	// 圆角积木：只有露出来的边才压暗
	float e = exposed_edge_dist(uv);
	float b = smoothstep(0.0, bevel_width, e);
	col *= mix(1.0 - bevel_dark, 1.0, b);
	if (v_wnorm.y > 0.5) {
		col *= 1.0 + 0.1 * (1.0 - smoothstep(bevel_width, bevel_width * 2.0, e)) * b;
	}
	// 强度的视觉语言：
	//   撞得碎（木箱、玻璃、支撑架……）：亮色内框 + 角钉，像马里奥的问号砖，一看就“可以撞”
	//   松软（砂、松土）：细碎的颗粒点
	//   打不坏：更暗一点、边缘更硬朗
	float ei = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	bool foliage = abs(v_type - 22.0) < 0.5 || v_type > 33.5 && v_type < 35.5;
	if (foliage) {
		// 树叶：一簇一簇的明暗，不画箱板
		col *= 0.82 + 0.3 * vnoise(v_wpos * 3.3) + 0.08 * n3;
		col = mix(col, col * vec3(1.15, 1.2, 0.8), smoothstep(0.3, 0.9, v_wnorm.y) * 0.35);
	} else if (cat > 0.5 && cat < 1.5) {
		// 可撞碎：按 0.5 米的格在世界空间画“箱板”——四周一圈亮边框 + 中间木纹横条，一看就是箱子/可拆的构件
		vec3 fu;
		vec3 fv;
		face_axes(v_wnorm, fu, fv);
		vec2 cuv = vec2(fract(dot(v_wpos, fu) * 2.0 + 0.0001), fract(dot(v_wpos, fv) * 2.0 + 0.0001));
		float ce = min(min(cuv.x, 1.0 - cuv.x), min(cuv.y, 1.0 - cuv.y));
		float frame = 1.0 - smoothstep(0.07, 0.09, ce);
		bool is_glass = abs(v_type - 5.0) < 0.5;
		if (!is_glass) {
			col *= 0.93 + 0.07 * step(0.5, fract(cuv.y * 3.0));
			col = mix(col, col * 1.35 + vec3(0.04), frame * 0.7);
			float bolt = 1.0 - smoothstep(0.025, 0.04, length(abs(cuv - 0.5) - vec2(0.39)));
			col = mix(col, vec3(0.82, 0.84, 0.88), bolt);
		} else {
			col = mix(col, vec3(1.0), frame * 0.35);
		}
	} else if (cat > 2.5) {
		float g = step(0.82, hash13(floor(v_wpos * 16.0 + v_wnorm * 0.1)));
		col *= 1.0 - 0.12 * g;
	} else if (cat < 0.5) {
		col *= 0.92;
	}
	return col * light;
}

// 圆角法线：在露出来的边附近把法线往外掰，光照下每一格都像被磨圆的积木
vec3 voxel_round_normal(vec2 uv) {
	vec3 n = normalize(v_wnorm);
	vec3 an = abs(n);
	if (max(an.x, max(an.y, an.z)) < 0.95) {
		return n;   // 斜坡面不处理
	}
	vec3 u;
	vec3 v;
	face_axes(n, u, v);
	float m = mod(v_code, 16.0);
	float w = bevel_width * 1.3;
	vec3 bend = vec3(0.0);
	if (edge_bit(m, 1.0) > 0.5) bend -= u * (1.0 - smoothstep(0.0, w, uv.x));
	if (edge_bit(m, 2.0) > 0.5) bend += u * (1.0 - smoothstep(0.0, w, 1.0 - uv.x));
	if (edge_bit(m, 4.0) > 0.5) bend -= v * (1.0 - smoothstep(0.0, w, uv.y));
	if (edge_bit(m, 8.0) > 0.5) bend += v * (1.0 - smoothstep(0.0, w, 1.0 - uv.y));
	return normalize(n + bend * round_strength);
}
