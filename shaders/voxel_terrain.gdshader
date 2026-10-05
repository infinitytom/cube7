// 平滑地形（Voxel Tools Transvoxel 生成；没有 Voxel Tools 时由 GDScript 的 Surface Nets 生成同样格式）
// 奥德赛 / 喷射战士式的柔和卡通着色 + 多材质混合
//
// CUSTOM1.x = 4 个材质槽位（每个 8 位，打包成 uint 的位）
// CUSTOM1.y = 4 个对应权重（每个 8 位）
// 槽位对应的颜色 / 类别由 TerrainPalette 写进 slot_* 数组
// COLOR.a  = 烘焙遮蔽（只有 GDScript 网格有；Voxel Tools 网格没有 COLOR，默认为 1）
shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_util.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"

uniform vec3 slot_colors[16];
// x = 草 / 苔，y = 树冠，z = 砂，w = 打不坏的岩体
uniform vec4 slot_fam[16];
// 晶点（矿、晶洞）
uniform float slot_spark[16];
uniform vec3 dirt_color : source_color = vec3(0.80, 0.52, 0.36);

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying vec3 v_col;
varying vec4 v_fam;
varying float v_spark;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	uint ii = floatBitsToUint(CUSTOM1.x);
	uint ww = floatBitsToUint(CUSTOM1.y);
	vec4 w = vec4(float(ww & 255u), float((ww >> 8u) & 255u), float((ww >> 16u) & 255u), float((ww >> 24u) & 255u));
	w /= max(w.x + w.y + w.z + w.w, 1.0);
	int i0 = min(int(ii & 255u), 15);
	int i1 = min(int((ii >> 8u) & 255u), 15);
	int i2 = min(int((ii >> 16u) & 255u), 15);
	int i3 = min(int((ii >> 24u) & 255u), 15);
	v_col = slot_colors[i0] * w.x + slot_colors[i1] * w.y + slot_colors[i2] * w.z + slot_colors[i3] * w.w;
	v_fam = slot_fam[i0] * w.x + slot_fam[i1] * w.y + slot_fam[i2] * w.z + slot_fam[i3] * w.w;
	v_spark = slot_spark[i0] * w.x + slot_spark[i1] * w.y + slot_spark[i2] * w.z + slot_spark[i3] * w.w;
}

vec3 terrain_albedo(vec3 n) {
	vec3 col = v_col;
	float up = n.y;
	float grass = v_fam.x;
	float foliage = v_fam.y;
	float sand = v_fam.z;
	float hard = v_fam.w;
	float n1 = vnoise(v_wpos * 0.22);
	float n2 = vnoise(v_wpos * 0.9 + vec3(4.1));
	col *= 0.93 + 0.12 * n1 + 0.04 * n2;
	// 泥土 / 岩石 / 崖壁：柔和的横向地层
	float strata = sin(v_wpos.y * 3.2 + n1 * 3.0);
	col *= mix(1.0, 0.95 + 0.06 * strata, clamp(1.0 - grass - foliage - sand, 0.0, 1.0));
	// 打不坏的岩体：偏冷、偏暗一点（一眼能分辨“这块可以挖”）
	col = mix(col, col * vec3(0.86, 0.9, 1.02), 0.6 * hard);
	// 草 / 苔：顶面是手绘感的草坪；侧面露出泥土，顶上留一圈波浪状的草边
	if (grass > 0.01) {
		float patch = smoothstep(0.5, 0.78, vnoise(v_wpos * 0.45 + 3.1));
		vec3 top = col * mix(vec3(1.0), vec3(1.1, 1.08, 0.8), patch * 0.4);
		float stroke = vnoise(vec3(v_wpos.x * 6.0, v_wpos.y * 2.0, v_wpos.z * 6.0) + vec3(9.7));
		float fine = vnoise(v_wpos * 14.0 + vec3(1.3));
		top *= 0.9 + 0.12 * stroke + 0.06 * fine;
		top = mix(top, top * vec3(0.78, 0.9, 0.72), smoothstep(0.62, 0.75, stroke) * 0.5);
		vec3 dirt = dirt_color * (0.92 + 0.1 * n2) * vec3(0.9, 0.86, 0.84);
		float lip = smoothstep(0.22, 0.55, up + 0.22 * (vnoise(v_wpos * vec3(3.0, 0.5, 3.0)) - 0.5));
		col = mix(col, mix(dirt, top, lip), grass);
	}
	// 树冠：一团一团的体积感，顶上被阳光晒得更亮更暖
	if (foliage > 0.01) {
		vec3 f = col * (0.86 + 0.24 * vnoise(v_wpos * 1.6));
		f = mix(f, f * vec3(1.18, 1.16, 0.85), smoothstep(0.1, 0.9, up) * 0.45);
		col = mix(col, f, foliage);
	}
	// 砂：风吹出来的浅浅波纹
	col *= mix(1.0, 0.95 + 0.06 * sin(v_wpos.x * 2.1 + v_wpos.z * 0.8 + n2 * 4.0) * smoothstep(0.4, 0.9, up), sand);
	// 整体稍微收一点饱和度，避免“荧光绿”
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 0.9);
	// 矿 / 晶洞：零星的亮色晶点
	if (v_spark > 0.01) {
		float g = step(0.86, vnoise(v_wpos * 7.0));
		col = mix(col, col * 1.7 + vec3(0.05), g * v_spark);
	}
	return col;
}

void fragment() {
	if (occluder_cut(v_wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	vec3 n = normalize(v_wnorm);
	ALBEDO = terrain_albedo(n);
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.55;
	ROUGHNESS = mix(0.75, 0.95, clamp(v_fam.y + v_fam.x * 0.6, 0.0, 1.0));
	SPECULAR = 0.3;
}
