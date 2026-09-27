shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_common.gdshaderinc"
uniform float strength = 2.0;

void fragment() {
	vec3 c = voxel_albedo(COLOR.rgb, COLOR.a, UV);
	ALBEDO = c;
	ROUGHNESS = 0.4;
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0 + v_wpos.x * 0.7 + v_wpos.z * 0.5);
	EMISSION = COLOR.rgb * strength * pulse;
}
