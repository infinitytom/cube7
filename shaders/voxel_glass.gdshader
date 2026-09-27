shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	float e = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float frame = 1.0 - smoothstep(0.03, 0.09, e);
	ALBEDO = mix(COLOR.rgb * COLOR.a, vec3(0.95, 1.0, 1.0), frame * 0.6);
	ALPHA = mix(0.28, 0.85, frame);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = COLOR.rgb * rim * 0.5;
}
