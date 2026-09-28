shader_type spatial;
// 锈海：一片缓慢起伏的锈色“液体”（其实是被风吹动的锈泥）。深色的沟、亮色的锈沫、太阳下油亮的反光。

uniform vec3 deep_color : source_color = vec3(0.26, 0.10, 0.07);
uniform vec3 mid_color : source_color = vec3(0.52, 0.22, 0.12);
uniform vec3 foam_color : source_color = vec3(0.86, 0.52, 0.32);
uniform float flow_speed = 0.035;
uniform float scale = 0.08;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * flow_speed;
	vec2 p = wpos.xz * scale;
	float h1 = fbm(p + vec2(t, t * 0.6));
	float h2 = fbm(p * 2.3 - vec2(t * 1.4, -t * 0.8) + h1);
	float h = h1 * 0.6 + h2 * 0.4;
	// 颜色：沟里深，脊上亮，最亮的地方是锈沫
	vec3 col = mix(deep_color, mid_color, smoothstep(0.3, 0.62, h));
	col = mix(col, foam_color, smoothstep(0.66, 0.78, h2) * 0.55);
	// 细碎的颗粒
	col *= 0.92 + 0.16 * noise(wpos.xz * 3.0 + vec2(t * 8.0));
	ALBEDO = col;
	// 法线：用高度场在屏幕空间的梯度（不用再多算几次噪声）
	vec3 dpx = dFdx(wpos);
	vec3 dpz = dFdy(wpos);
	float dhx = dFdx(h);
	float dhz = dFdy(h);
	vec3 n = normalize(cross(dpz + vec3(0.0, dhz * 1.6, 0.0), dpx + vec3(0.0, dhx * 1.6, 0.0)));
	if (n.y < 0.0) n = -n;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.28, 0.6, smoothstep(0.4, 0.75, h));
	METALLIC = 0.25;
	SPECULAR = 0.6;
}
