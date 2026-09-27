shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 0.42;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = COLOR.rgb * rim * 0.6;
}
