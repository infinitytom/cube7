shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_common.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"

void fragment() {
	if (occluder_cut(v_wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	vec3 c = voxel_albedo(COLOR.rgb, COLOR.a, UV);
	// 和平滑地形同一套调子：收一点饱和度和亮度
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, 0.85) * 0.9;
	// 细颗粒法线：木纹、金属拉丝、石面颗粒，统一的“实物”质感
	vec3 rn = voxel_round_normal(UV);
	vec3 dn = detail_normal(rn, v_wpos, 10.0, 0.22, vec3(1.0));
	ALBEDO = c * mix(0.88, 1.0, clamp(dot(dn, rn), 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(dn, 0.0)).xyz);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
