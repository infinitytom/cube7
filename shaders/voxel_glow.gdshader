shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_common.gdshaderinc"
uniform float strength = 2.0;

void fragment() {
	vec3 c = voxel_albedo(COLOR.rgb, COLOR.a, UV);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0 + v_wpos.x * 0.7 + v_wpos.z * 0.5);
	// 燃烧中 / 炭火 / 熔炉口：暗红底色上流动的亮黄裂纹，随时间闪烁（而不是一块发白的亮方块）
	bool fire = abs(v_type - 36.0) < 0.5 || abs(v_type - 37.0) < 0.5 || abs(v_type - 42.0) < 0.5;
	if (fire) {
		float n = vnoise(v_wpos * 7.0 + vec3(0.0, -TIME * 2.5, TIME * 0.7));
		float n2 = vnoise(v_wpos * 15.0 + vec3(TIME * 1.3, -TIME * 4.0, 0.0));
		float heat = smoothstep(0.35, 0.8, n * 0.7 + n2 * 0.4);
		vec3 hot = mix(vec3(0.35, 0.04, 0.02), vec3(1.0, 0.62, 0.15), heat);
		float flick = 0.8 + 0.25 * sin(TIME * 11.0 + v_wpos.x * 3.0 + v_wpos.y * 2.0);
		ALBEDO = hot * 0.25;
		ROUGHNESS = 0.9;
		EMISSION = hot * (0.7 + 1.3 * heat) * flick;
	} else {
		ALBEDO = c;
		ROUGHNESS = 0.4;
		EMISSION = COLOR.rgb * strength * pulse;
	}
}
