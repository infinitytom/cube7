shader_type sky;
// 立方-7 的天空：分层渐变 + 太阳光晕 + 地平线上的积云带 + 高空卷云 + 带光环的巨型行星 + 卫星 + 星星
// 每一章用不同的配色（见 scripts/game/atmosphere.gd）

uniform vec3 top_color : source_color = vec3(0.28, 0.52, 0.95);
uniform vec3 mid_color : source_color = vec3(0.55, 0.75, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.93, 1.0);
uniform vec3 bottom_color : source_color = vec3(0.70, 0.82, 0.98);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.78);
uniform float sun_disc = 0.9994;
uniform float sun_glow = 0.35;
uniform float horizon_glow = 0.35;

uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.78, 0.95);
uniform float bank_height = 0.16;     // 积云带能长多高（仰角的正弦）
uniform float bank_cover = 0.55;
uniform float cirrus_cover = 0.45;

uniform vec3 planet_dir = vec3(-0.55, 0.42, -0.72);
uniform float planet_radius = 0.16;   // 弧度
uniform vec3 planet_color : source_color = vec3(0.86, 0.78, 0.98);
uniform vec3 planet_band : source_color = vec3(0.66, 0.60, 0.92);
uniform vec3 ring_color : source_color = vec3(1.0, 0.95, 0.9);
uniform float planet_alpha = 0.85;

uniform vec3 moon_dir = vec3(0.62, 0.30, -0.55);
uniform float moon_radius = 0.035;
uniform float star_amount = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}
float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return v;
}
// 周期的噪声（绕地平线一圈无缝）
float bank_noise(float az, float s, float o) {
	vec2 p = vec2(cos(az), sin(az)) * s + vec2(o);
	return fbm2(p);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	// ---- 渐变
	vec3 col;
	if (e >= 0.0) {
		float t1 = smoothstep(0.0, 0.22, e);
		float t2 = smoothstep(0.12, 0.85, e);
		col = mix(horizon_color, mid_color, t1);
		col = mix(col, top_color, t2);
	} else {
		col = mix(horizon_color, bottom_color, smoothstep(0.0, 0.25, -e));
	}
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, 1.0, 0.0);
	float sdot = max(dot(d, sd), 0.0);
	// 太阳一侧的地平线更暖更亮
	float side = pow(max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), normalize(vec3(sd.x, 0.0, sd.z) + 1e-4)), 0.0), 3.0);
	col += sun_tint * horizon_glow * side * (1.0 - smoothstep(0.0, 0.45, abs(e)));

	if (!AT_CUBEMAP_PASS) {
		// ---- 星星（天色暗时）
		if (star_amount > 0.001 && e > 0.0) {
			vec2 sp = floor(d.xz / (d.y + 0.6) * 260.0);
			float h = hash12(sp);
			float star = step(0.9965, h) * (0.5 + 0.5 * sin(TIME * 2.0 + h * 90.0));
			col += vec3(star) * star_amount * smoothstep(0.05, 0.4, e);
		}
		// ---- 巨型行星 + 光环
		vec3 pd = normalize(planet_dir);
		vec3 pu = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
		vec3 pv = cross(pu, pd);
		float fwd = dot(d, pd);
		if (fwd > 0.0) {
			vec2 q = vec2(dot(d, pu), dot(d, pv)) / fwd;     // 切平面坐标
			float r = length(q) / tan(planet_radius);
			// 光环：倾斜的椭圆环（在行星前面的半边挡住行星）
			float tilt = 0.33;
			mat2 rot = mat2(vec2(cos(0.35), sin(0.35)), vec2(-sin(0.35), cos(0.35)));
			vec2 rq = rot * q / tan(planet_radius);
			float rr = length(vec2(rq.x, rq.y / tilt));
			float ring = smoothstep(1.35, 1.42, rr) * (1.0 - smoothstep(2.15, 2.25, rr));
			ring *= 0.55 + 0.45 * sin(rr * 38.0) * sin(rr * 11.0 + 1.3);
			bool ring_front = rq.y < 0.0;
			vec3 air = horizon_color;
			if (r < 1.0) {
				// 行星本体：条纹 + 背光一侧暗
				vec3 n = normalize(vec3(q / tan(planet_radius), sqrt(max(1.0 - r * r, 0.0))));
				float bands = 0.5 + 0.5 * sin((q.y / tan(planet_radius)) * 9.0 + fbm2(q * 18.0) * 3.0);
				vec3 pc = mix(planet_color, planet_band, bands * 0.7);
				vec3 ls = normalize(vec3(dot(sd, pu), dot(sd, pv), max(dot(sd, pd), 0.0) * -1.0 + 0.6));
				float lit = clamp(dot(n, ls) * 0.8 + 0.35, 0.18, 1.0);
				pc *= lit;
				pc += vec3(0.25, 0.3, 0.5) * pow(1.0 - n.z, 3.0);   // 大气边缘光
				float edge = smoothstep(1.0, 0.985, r);
				float a = planet_alpha * edge * (0.55 + 0.45 * smoothstep(0.0, 0.25, e));
				col = mix(col, mix(pc, air, 0.25), a);
			} else {
				col += vec3(0.4, 0.45, 0.7) * 0.12 * planet_alpha * exp(-(r - 1.0) * 14.0);
			}
			if (ring > 0.0 && (ring_front || r >= 1.0)) {
				col = mix(col, ring_color, ring * 0.55 * planet_alpha);
			}
		}
		// ---- 卫星
		vec3 md = normalize(moon_dir);
		float ma = acos(clamp(dot(d, md), -1.0, 1.0));
		if (ma < moon_radius) {
			float mr = ma / moon_radius;
			float crater = fbm2(d.xy * 400.0);
			vec3 mc = vec3(0.95, 0.96, 1.0) * (0.82 + 0.18 * crater);
			col = mix(col, mc, smoothstep(1.0, 0.92, mr) * 0.8);
		}
		// ---- 高空卷云
		if (e > 0.02) {
			vec2 cp = d.xz / (e + 0.08) * 1.1 + vec2(TIME * 0.004, TIME * 0.002);
			float c = fbm2(cp * vec2(1.0, 2.6));
			float cm = smoothstep(1.0 - cirrus_cover, 1.05 - cirrus_cover * 0.5, c) * smoothstep(0.02, 0.2, e);
			col = mix(col, cloud_lit * (0.95 + 0.1 * sdot), cm * 0.45);
		}
		// ---- 地平线积云带（一团一团往上鼓）
		float az = atan(d.x, d.z);
		float hprof = bank_noise(az, 3.2, 1.7) * 0.7 + bank_noise(az, 9.0, 5.1) * 0.3;
		float top = bank_height * smoothstep(1.0 - bank_cover - 0.15, 1.0 - bank_cover + 0.35, hprof);
		float puff = fbm2(vec2(az * 14.0, e * 38.0) + vec2(TIME * 0.01, 0.0));
		float edge_y = top * (0.75 + 0.5 * puff);
		if (e > -0.08 && e < edge_y) {
			float h01 = clamp((e + 0.02) / max(edge_y + 0.02, 0.001), 0.0, 1.0);
			vec3 cc = mix(cloud_shade, cloud_lit, smoothstep(0.1, 0.95, h01));
			cc += sun_tint * 0.35 * side * smoothstep(0.6, 1.0, h01);
			float a = smoothstep(edge_y, edge_y - 0.012, e) * (0.85 + 0.15 * puff);
			// 越靠近地平线越融进大气
			cc = mix(cc, horizon_color, 0.35 * (1.0 - smoothstep(0.0, 0.08, e)));
			col = mix(col, cc, a);
		}
	}
	// ---- 太阳
	float disc = smoothstep(sun_disc, sun_disc + 0.0003, sdot);
	float glow = pow(sdot, 16.0) * sun_glow + pow(sdot, 400.0) * sun_glow * 2.0;
	col += sun_tint * glow;
	if (!AT_CUBEMAP_PASS) {
		col = mix(col, vec3(1.0, 0.98, 0.92) * 1.6, disc);
	}
	COLOR = col;
}
