shader_type spatial;
render_mode cull_back;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	ALBEDO = voxel_albedo(COLOR.rgb, COLOR.a, UV);
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
}
