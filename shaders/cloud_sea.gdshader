shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// 云海：缓慢流动的柔和云层，远处淡入天空色
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shadow_color : source_color = vec3(0.86, 0.88, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.87, 1.0);
uniform float scale = 0.045;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale + vec2(TIME * 0.01, TIME * 0.006);
	float n = fbm(p);
	float puff = smoothstep(0.35, 0.75, n);
	vec3 col = mix(shadow_color, cloud_color, puff);
	float d = length(wpos.xz - vec2(32.0, 26.0));
	col = mix(col, horizon_color, smoothstep(60.0, 220.0, d));
	ALBEDO = col;
}
