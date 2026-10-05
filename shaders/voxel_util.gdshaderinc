// 体素着色器共用的小工具：噪声、镜头遮挡镂空

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// 平滑的值噪声（大尺度的颜色起伏，代替逐格的颗粒）
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}


// 挡在镜头和 PIX 之间的方块：做成网点镂空，能透过去看到 PIX（树冠、墙角不再糊住画面）
global uniform vec4 occl_target;   // xyz = PIX 位置，w = 1 启用
float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}
bool occluder_cut(vec3 wpos, vec3 cam, vec2 fragcoord) {
	if (occl_target.w < 0.5) return false;
	vec3 seg = occl_target.xyz - cam;
	float L = length(seg);
	if (L < 1.0) return false;
	vec3 dir = seg / L;
	float t = dot(wpos - cam, dir);
	if (t < 0.05 || t > L - 0.9) return false;
	float r = length(wpos - cam - dir * t);
	float rad = mix(0.7, 1.5, clamp(t / L * 1.6, 0.0, 1.0));
	if (r > rad) return false;
	float k = 1.0 - r / rad;                      // 越靠近视线越透
	k *= smoothstep(L - 0.9, L - 2.0, t);         // PIX 脚边的方块不镂空
	return bayer4(fragcoord) < k * 0.85;
}

