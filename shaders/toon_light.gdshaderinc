// 柔和卡通光照（奥德赛 / 喷射战士的感觉）：
//   · 明暗交界线柔和但清楚（不是写实的渐变，也不是硬切的赛璐璐）
//   · 背光面不发黑，带一点冷色的天光
//   · 迎光的轮廓上一道暖色边缘光，形体更“圆”
//   · 小而柔的高光，像涂了一层清漆的玩具
uniform float toon_soft = 0.55;
uniform vec3 shadow_tint : source_color = vec3(0.55, 0.64, 1.0);
uniform float shadow_fill = 0.16;
uniform float rim_strength = 0.22;
uniform float gloss = 0.12;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.2) / 1.2, 0.0, 1.0);
	float band = smoothstep(0.02, toon_soft, wrap);
	float lit = band * ATTENUATION;
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * mix(shadow_tint * shadow_fill, vec3(1.0), lit);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// 视空间里“朝上”的面（地面）不加边缘光，否则斜看大片草地会整片发亮
	float up_ws = dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float rim = pow(1.0 - nv, 4.0) * smoothstep(-0.25, 0.45, ndl) * ATTENUATION * (1.0 - smoothstep(0.55, 0.9, up_ws));
	SPECULAR_LIGHT += lc * rim * rim_strength * vec3(1.0, 0.95, 0.85);
	vec3 h = normalize(LIGHT + VIEW);
	float sp = pow(clamp(dot(NORMAL, h), 0.0, 1.0), 48.0);
	SPECULAR_LIGHT += lc * smoothstep(0.35, 0.6, sp) * gloss * lit * clamp((1.0 - ROUGHNESS) * 3.0, 0.0, 1.0);
}
