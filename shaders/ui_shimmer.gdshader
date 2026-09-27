shader_type canvas_item;
// 标题字的流光：一道斜向的暖金色高光定期扫过文字

uniform float sweep = -1000.0;   // 高光中心的屏幕 x（像素），由脚本驱动
uniform float width = 60.0;
uniform vec4 tint_top : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint_bottom : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform float top_y = 0.0;
uniform float bottom_y = 200.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float k = clamp((FRAGCOORD.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
	// 只给亮色（字体本体）上渐变，描边保持原色
	float body = step(0.5, dot(COLOR.rgb, vec3(0.333)));
	vec3 grad = mix(tint_top.rgb, tint_bottom.rgb, k);
	c.rgb = mix(c.rgb, c.rgb * grad, body);
	float d = (FRAGCOORD.x + FRAGCOORD.y * 0.45) - sweep;
	float band = exp(-d * d / (width * width));
	c.rgb += vec3(1.0, 0.86, 0.55) * band * 0.9 * body;
	COLOR = c;
}
