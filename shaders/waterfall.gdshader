shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// 体素风瀑布：按“格”量化的流水条纹往下流，顶部白色水花，越往下越散成雾
uniform vec3 water_a : source_color = vec3(0.55, 0.85, 1.0);
uniform vec3 water_b : source_color = vec3(0.85, 0.97, 1.0);
uniform float speed = 0.9;
uniform float cells_x = 8.0;      // 横向分成几条
uniform float length_m = 30.0;
uniform float voxel_m = 0.5;
uniform float alpha = 0.85;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	// UV.y：0 = 顶，1 = 底
	float col_i = floor(UV.x * cells_x);
	float yq = floor(UV.y * length_m / voxel_m) * voxel_m / length_m;
	float ph = hash(vec2(col_i, 3.1));
	float flow = fract(yq * length_m * 0.12 - TIME * speed * (0.8 + 0.4 * ph) + ph * 7.0);
	float streak = step(0.55, flow) * 0.5 + step(0.85, flow) * 0.5;
	vec3 c = mix(water_a, water_b, streak);
	// 顶部的白色水花
	c = mix(c, vec3(1.0), smoothstep(0.06, 0.0, UV.y));
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	float fade = 1.0 - smoothstep(0.55, 1.0, UV.y);
	ALBEDO = c;
	ALPHA = alpha * edge * mix(0.35, 1.0, fade) * (0.75 + 0.25 * streak) * (1.0 - smoothstep(0.7, 1.0, UV.y));
}
