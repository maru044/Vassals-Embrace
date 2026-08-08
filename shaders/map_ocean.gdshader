// 海洋 shader：覆盖地图范围的大平面
// 深度渐变（深蓝→近岸青绿）+ 近海白浪（foam，随距离场精确贴岸）+ Fresnel 反光 + fbm 波动
// 关键：预计算「海岸距离场」sea_distance.png——每像素存到最近陆地的米制距离，
//       一次采样即得近岸距离，白浪/浅水精确贴岸、无逐像素检测开销。
shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// ---- 对齐（距离场覆盖地图+外扩，用 ocean 范围非高度图范围）----
uniform sampler2D sea_dist : source_color, filter_linear, repeat_disable;
uniform vec2 ocean_min = vec2(-19.1, -30.65);
uniform vec2 ocean_size = vec2(37.9, 48.45);
uniform float max_dist = 8.0;     // 距离场 clamp 上限（米），与 gen_sea_distance.py 一致
uniform float zoom = 0.5;         // 0=远 1=近（联动白浪/波动强度）
uniform float terrain_blend = 0.0; // 0=平面 1=立体（白浪/波动随近景增强）

// ---- 水面细节（法线贴图 + 朝阳天空反射）----
uniform sampler2D water_normal : source_color, filter_linear, repeat_enable;
uniform float normal_tile = 4.5;    // 法线贴图世界尺度（米/格，越大波浪越宽、防摩尔纹）
uniform float normal_strength = 0.18; // 法线扰动强度（近景为主，波浪更低缓）
uniform sampler2D sky_panorama : source_color, filter_linear, repeat_disable; // 朝阳 HDRI 反射采样

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
	// 世界坐标采样距离场 → 米制距离
	vec2 uv = (v_world - ocean_min) / ocean_size;
	float dist_m = texture(sea_dist, uv).r * max_dist;

	// ⚠️ 越界裁切（防 Clamp 拉伸十字亮条）：uv 超出 [0,1] 的像素（海洋平面远大于
	// 距离场纹理覆盖范围）强制 = max_dist（深海），彻底杜绝边缘像素无限拉伸。
	vec2 in_b = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float bounds = in_b.x * in_b.y;
	dist_m = mix(dist_m, max_dist, 1.0 - bounds);

	// 近景系数（白浪/波动随接近增强）
	float near = terrain_blend * smoothstep(0.25, 0.8, zoom);

	// ① 海洋色带：近海与远海颜色接近，仅轻微变色（近海略亮一档的蓝青）。
	// 平缓渐变，范围上界 2.5m < 纹理外扩 4.0m，纹理内渐变完成。
	vec3 near_col = vec3(0.14, 0.26, 0.40);  // 近海蓝青（比远海略亮）
	vec3 far_col  = vec3(0.04, 0.12, 0.22);  // 远海深蓝（加深深度）
	// 近岸权重：smoothstep 平缓渐变（0.3~2.5m，纹理内完成）
	float shallow_w = 1.0 - smoothstep(0.3, 2.5, dist_m);
	vec3 c = mix(far_col, near_col, shallow_w);

	// ② fbm 波动：时间流动噪声 → 微调明暗 + 扰动法线（波浪反光）
	vec2 wp = uv * 3.0;
	float t = TIME * 0.4;
	float wave = fbm(wp + vec2(t, t * 0.7));
	c *= 1.0 + wave * 0.07 * near;

	// 法线：fbm 基座 + 水面法线贴图 tile 叠加（近景强、远景弱），波浪细节更真实。
	// 域扭曲（Domain Warping）：低频噪声做 UV 偏移，各区域移动方向/速度不同 → 随机湍流波动，
	// 避免整张贴图沿单一方向平行移动（现代水面标准做法）。
	vec3 N = normalize(vec3(wave * 0.05, 1.0, wave * 0.04));
	if (near > 0.01) {
		vec2 flow = vec2(t * 0.06, t * 0.05);
		vec2 warp = vec2(
			fbm(v_world * 0.12 + flow),
			fbm(v_world * 0.12 + flow + vec2(7.3, 3.1))
		) * 0.2;   // 空间低频噪声 → 轻微湍流偏移（减弱，不喧宾夺主）
		vec2 nuv = v_world / normal_tile + warp + flow * 0.15;
		vec3 nrm = texture(water_normal, nuv).rgb * 2.0 - 1.0;
		float ns = normal_strength * near;
		N = normalize(vec3(N.x + nrm.x * ns, 1.0, N.z + nrm.y * ns));
	}

	// ③ 近海白浪（foam）：范围收窄（0.03~0.4m），自然渐消融入深海。
	// 白浪强度进一步减弱（近海只轻微提亮，不喧宾夺主）。
	float foam_mask = 1.0 - smoothstep(0.03, 0.4, dist_m);  // 岸线 1.0 → 0.4m 处 0.0
	float brk = smoothstep(0.12, 0.6, fbm(uv * 6.0 + vec2(t * 0.6, t * 0.5)));
	float foam_strength = foam_mask * mix(0.2, 0.6, brk) * (0.1 + 0.5 * near);
	vec3 foam = mix(c, vec3(0.90, 0.93, 0.97), 0.7);  // 泡沫柔和、低调
	c = mix(c, foam, clamp(foam_strength, 0.0, 1.0));

	// ④ Fresnel 反光：掠射角采样朝阳 HDRI（等距圆柱 → 反射方向），水面金色反光
	float fres = pow(1.0 - max(dot(N, v_view), 0.0), 4.0);
	vec3 R = reflect(-v_view, N);
	vec2 sky_uv = vec2(atan(R.x, -R.z) / 6.2831853 + 0.5, R.y * 0.5 + 0.5);
	vec3 sky = texture(sky_panorama, sky_uv).rgb;
	sky = mix(vec3(0.72, 0.84, 0.95), sky, 0.75);  // 朝阳反射（略收敛）
	c = mix(c, sky, fres * 0.4 * (0.15 + 0.6 * near));

	ALBEDO = c;
	ROUGHNESS = 0.05;   // 更镜面 → 更反光
	METALLIC = 0.0;
}
