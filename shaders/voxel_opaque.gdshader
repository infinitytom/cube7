shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	if (occluder_cut(v_wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	ALBEDO = voxel_albedo(COLOR.rgb, COLOR.a, UV);
	NORMAL = normalize((VIEW_MATRIX * vec4(voxel_round_normal(UV), 0.0)).xyz);
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
}
