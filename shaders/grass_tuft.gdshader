shader_type spatial;
render_mode cull_disabled;
// 草丛 / 花：随风轻轻摆动（越往上摆得越多）
uniform vec3 tip_color : source_color = vec3(0.62, 0.9, 0.38);
uniform vec3 base_color : source_color = vec3(0.30, 0.62, 0.22);
uniform float sway = 0.05;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.25, 0.0, 1.0);
	VERTEX.x += sin(TIME * 1.8 + w.x * 0.9 + w.z * 0.7) * sway * h;
	VERTEX.z += cos(TIME * 1.5 + w.z * 0.8) * sway * 0.6 * h;
}
void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	ALBEDO = mix(base_color, tip_color, 1.0 - h) * COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.08);
}
