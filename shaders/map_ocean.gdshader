// 海洋 shader：覆盖地图范围的大平面
// 深度渐变（深蓝→近岸青绿）+ 近海白浪（foam，随距离场精确贴岸）+ Fresnel 反光 + fbm 波动
// 关键：预计算「海岸距离场」sea_distance.png——每像素存到最近陆地的米制距离，
//       一次采样即得近岸距离，白浪/浅水精确贴岸、无逐像素检测开销。
shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// ---- 对齐（距离场覆盖整个海洋平面，用 ocean 范围非高度图范围）----
uniform sampler2D sea_dist : source_color, filter_linear, repeat_disable;
uniform vec2 ocean_min = vec2(-16.6, -28.15);
uniform vec2 ocean_size = vec2(32.9, 43.45);
uniform float max_dist = 8.0;     // 距离场 clamp 上限（米），与 gen_sea_distance.py 一致
uniform float zoom = 0.5;         // 0=远 1=近（联动白浪/波动强度）
uniform float terrain_blend = 0.0; // 0=平面 1=立体（白浪/波动随近景增强）

varying vec2 v_world;   // 世界 XZ
varying vec3 v_view;    // 片元→相机（世界空间）

// ---- 2D Simplex 噪声（Ashima，三角形网格，无正方形格点方块伪影）----
vec3 permute(vec3 x) {
	return mod(((x * 34.0) + 1.0) * x, 289.0);
}
float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod(i, 289.0);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);   // 大致 [-1, 1]
}
float fbm(vec2 p) {
	const mat2 rot = mat2(vec2(0.877, 0.479), vec2(-0.479, 0.877));   // ~28.6°
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * snoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = VERTEX.xz;
	v_view = normalize(CAMERA_POSITION_WORLD - VERTEX);
}

void fragment() {
	// 世界坐标采样距离场（覆盖整个海洋平面）→ 米制距离
	vec2 uv = (v_world - ocean_min) / ocean_size;
	float dist_m = texture(sea_dist, uv).r * max_dist;

	// 近景系数（白浪/波动随接近增强）
	float near = terrain_blend * smoothstep(0.25, 0.8, zoom);

	// ① 深度渐变：深蓝 → 近岸青绿（0.3~3m 浅水带）
	vec3 deep    = vec3(0.03, 0.16, 0.28);
	vec3 shallow = vec3(0.22, 0.55, 0.55);
	float shallow_w = 1.0 - smoothstep(0.3, 3.0, dist_m);
	vec3 c = mix(deep, shallow, shallow_w);

	// ② fbm 波动：时间流动噪声 → 微调明暗 + 扰动法线（波浪反光）
	vec2 wp = uv * 3.0;
	float t = TIME * 0.4;
	float wave = fbm(wp + vec2(t, t * 0.7));
	c *= 1.0 + wave * 0.07 * near;
	vec3 N = normalize(vec3(wave * 0.05, 1.0, wave * 0.04));

	// ③ 近海白浪（foam）：贴岸 0.05~0.3m 白沫 + fbm 破碎闪烁（边缘参差、若隐若现）
	float foam_mask = 1.0 - smoothstep(0.05, 0.30, dist_m);
	float brk = smoothstep(0.25, 0.7, fbm(uv * 4.0 + vec2(t * 0.6, t * 0.5)));
	foam_mask *= brk * near;
	vec3 foam = mix(c, vec3(0.97, 0.99, 1.0), 0.85);
	c = mix(c, foam, clamp(foam_mask, 0.0, 1.0));

	// ④ Fresnel 反光：掠射角提亮（水面反光感）
	float fres = pow(1.0 - max(dot(N, v_view), 0.0), 4.0);
	vec3 sky = vec3(0.72, 0.84, 0.95);
	c = mix(c, sky, fres * 0.55 * (0.3 + 0.7 * near));

	ALBEDO = c;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
}
