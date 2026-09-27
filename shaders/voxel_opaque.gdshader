shader_type spatial;
render_mode cull_back;
// 顶点色 = 方块颜色 × 面朝向明暗 × 烘焙 AO（已在 GDScript 中转为线性空间）
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
