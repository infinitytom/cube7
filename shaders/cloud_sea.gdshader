shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;
// 云海：一团一团鼓起来的积云顶，朝太阳的一面更亮，云缝里透出深一点的蓝紫；
// 离镜头越远越融进地平线的颜色（和天空衔接，看不出边）
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shadow_color : source_color = vec3(0.78, 0.82, 0.98);
uniform vec3 gap_color : source_color = vec3(0.55, 0.62, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.93, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.8);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);
uniform float scale = 0.018;
uniform float fade_start = 120.0;
uniform float fade_end = 900.0;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
float field(vec2 p) {
	vec2 w = vec2(fbm(p * 0.5 + vec2(TIME * 0.004, 0.0)), fbm(p * 0.5 + vec2(5.2, 1.3 - TIME * 0.003)));
	return fbm(p + w * 1.6 + vec2(TIME * 0.006, TIME * 0.004));
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale;
	float h = field(p);
	float e = 0.06;
	float hx = field(p + vec2(e, 0.0));
	float hz = field(p + vec2(0.0, e));
	vec3 n = normalize(vec3((h - hx) * 9.0, 1.0, (h - hz) * 9.0));
	float puff = smoothstep(0.32, 0.72, h);
	vec3 sd = normalize(sun_dir);
	float lit = clamp(dot(n, sd) * 0.6 + 0.55, 0.0, 1.2);
	vec3 col = mix(gap_color, shadow_color, smoothstep(0.2, 0.45, h));
	col = mix(col, cloud_color * lit, puff);
	col += sun_color * 0.15 * pow(max(dot(n, sd), 0.0), 6.0) * puff;
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	col = mix(col, horizon_color, smoothstep(fade_start, fade_end, dist));
	ALBEDO = col;
}
