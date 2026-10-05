// 回声扫描的波前：一个包住镜头的大球，按深度图还原每个像素的世界坐标，
// 在“到扫描中心的距离 ≈ 当前半径”的地方画一圈发光的环（扫过地形、墙壁、敌人）。
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, blend_add, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 origin;
uniform float radius = 0.0;
uniform float max_radius = 14.0;
uniform float width = 0.9;
uniform vec4 color : source_color = vec4(0.45, 0.95, 1.0, 1.0);

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 wp = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float dist = length(wp - origin);
	float front = radius - dist;
	// 波前：亮的细线 + 后面拖一段渐暗的余晖
	float ring = smoothstep(width, 0.0, abs(front)) * 1.4;
	float trail = (front > 0.0 ? exp(-front * 0.6) * 0.25 : 0.0);
	// 余晖里的等高网格线（像声呐扫过的回波）
	float grid = smoothstep(0.08, 0.0, abs(fract(dist * 1.2) - 0.5) - 0.42) * trail * 1.5;
	float fade = 1.0 - smoothstep(max_radius * 0.75, max_radius, radius);
	float a = (ring + trail + grid) * fade;
	ALBEDO = color.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
