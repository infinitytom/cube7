shader_type spatial;
render_mode cull_back;
uniform float strength = 2.2;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.4;
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	EMISSION = COLOR.rgb * strength * pulse;
}
