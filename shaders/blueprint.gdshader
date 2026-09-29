shader_type spatial;
// 重构蓝图：只画方块的发光棱线 + 很淡的面，不再一层层叠加成一团白光
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float alpha = 0.24;

void fragment() {
	// BoxMesh 的 UV 是 3×2 的图集，每个面占一格
	vec2 f = fract(UV * vec2(3.0, 2.0));
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float line = 1.0 - smoothstep(0.035, 0.08, e);
	float d = length(VERTEX);
	float near_fade = smoothstep(0.8, 3.5, d);       // 贴着镜头的蓝图淡掉
	ALBEDO = tint.rgb;
	ALPHA = clamp(alpha * (0.1 + line * 1.8) * near_fade, 0.0, 1.0);
}
