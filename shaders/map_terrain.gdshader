// 地图地形 shader：高度图位移（平↔立体）+ 国家/地形着色
// + V3 卡通：Toon 明暗（冷深蓝阴影，不用黑色）、草地风摆（明显）、云阴影（噪声慢移冷蓝暗化）
// 高度图按【世界 XZ 坐标】采样（非 UV），天然适配不规则网格。
shader_type spatial;
render_mode cull_disabled;

// ---- 高度图与对齐 ----
uniform sampler2D heightmap : source_color, filter_linear, repeat_disable;
uniform vec2 hmap_min = vec2(-15.1, -26.65);
uniform vec2 hmap_size = vec2(29.9, 40.45);
uniform float height_scale = 0.5;      // 地形最大高度（减小以减轻细分边界破面）
uniform float terrain_blend = 0.0;     // 0=平面 1=立体（相机距离驱动）
uniform float y_offset = 0.0;          // 省份覆盖层微量上抬，避免与陆地基底 z-fight

// ---- 颜色 ----
uniform vec3 own_color : source_color = vec3(0.8, 0.75, 0.7);  // 本宗色（中层）
uniform vec3 far_color : source_color = vec3(0.8, 0.75, 0.7);  // 宗主色（远层）
uniform float zoom = 0.5;               // 0=远 1=近
uniform float highlight = 0.0;          // 选中高亮闪烁（0-1，脉冲）

// ---- 卡通增强强度 ----
uniform float cloud_strength = 0.35;    // 云阴影强度
uniform float grass_sway = 0.18;        // 草地风摆幅度（明显）

varying float v_height;
varying float v_lat;   // 纬度：0=北（高纬） 1=南（低纬）
varying vec3 v_normal; // 地形法线（高度梯度）
varying vec2 v_world;  // 世界 XZ

// ---- 简单噪声（Godot 4 无内置 noise）----
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.0 + vec2(3.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec2 uv = (VERTEX.xz - hmap_min) / hmap_size;
	float h = texture(heightmap, uv).r;   // 0=海 1=最高
	v_height = h;
	// 纬度（北 z 负 → 0，南 z 正 → 1）
	v_lat = clamp((VERTEX.z - hmap_min.y) / hmap_size.y, 0.0, 1.0);
	v_world = VERTEX.xz;

	// 地形法线（高度梯度；y 分量控制坡度强度——越小法线越平、明暗越强）
	float eps = 0.015;
	float hl = texture(heightmap, uv + vec2(-eps, 0.0)).r;
	float hr = texture(heightmap, uv + vec2( eps, 0.0)).r;
	float hd = texture(heightmap, uv + vec2(0.0, -eps)).r;
	float hu = texture(heightmap, uv + vec2(0.0,  eps)).r;
	v_normal = normalize(vec3(hl - hr, 1.2 * terrain_blend + 0.2, hd - hu));

	// 草地效果用噪声变色（fragment），不做顶点位移——避免整个网格抖动
	VERTEX.y += h * height_scale * terrain_blend + y_offset;
}

// 地形色带（双要素：高度 + 纬度）：
// - 纬度混合冷暖底色（北冷灰绿/灰褐 → 南暖嫩绿/黄褐）
// - 连续渐变（h=0 纯绿，h 一有变化立即渐变）
// - 雪线随纬度：北低（低地也雪）→ 南高（只有高山有雪）
vec3 terrain_palette(float h, float lat) {
	vec3 base = mix(vec3(0.42, 0.57, 0.36), vec3(0.50, 0.72, 0.40), lat);
	vec3 hill = mix(vec3(0.62, 0.60, 0.52), vec3(0.78, 0.70, 0.42), lat);
	vec3 rock = mix(vec3(0.68, 0.64, 0.60), vec3(0.80, 0.62, 0.44), lat);
	float t1 = smoothstep(0.0, 0.3, h);     // 绿 → 丘陵
	float t2 = smoothstep(0.3, 0.65, h);    // 丘陵 → 山地
	vec3 c = mix(base, hill, t1);
	c = mix(c, rock, t2);
	float snowline = mix(0.05, 0.65, lat);
	float snow = smoothstep(snowline, snowline + 0.25, h);
	c = mix(c, vec3(0.96, 0.95, 0.93), snow);
	return c;
}

void fragment() {
	float h = v_height;
	vec3 terrain = terrain_palette(h, v_lat);

	// 远层：宗主色（附庸涂宗主国颜色）｜中层：本宗色｜近层：地形
	float t_far = 1.0 - smoothstep(0.25, 0.6, zoom);
	float t_terrain = smoothstep(0.55, 0.95, zoom);
	vec3 c = mix(own_color, terrain, t_terrain);
	c = mix(c, far_color, t_far);

	// Toon 明暗（冷深蓝阴影，不用黑色）：仅立体地形（terrain_blend）
	vec3 light_dir = normalize(vec3(0.55, 0.72, 0.35));
	float diff = max(dot(normalize(v_normal), light_dir), 0.0);
	float shade = smoothstep(0.3, 0.5, diff);        // 2 档 toon
	vec3 shadow_col = vec3(0.10, 0.18, 0.42);        // 冷深蓝（加强）
	float shadow = (1.0 - shade) * 0.8 * terrain_blend;
	c = mix(c, c * 0.4 + shadow_col * 0.6, shadow);

	// 麦浪/云（合并）：噪声流动明暗，时间变化类似水波/麦浪，草地更明显
	vec2 wuv = (v_world - hmap_min) / hmap_size;
	float wave = fbm(wuv * 3.0 + vec2(TIME * 0.05, TIME * 0.035));
	float grass_mask = smoothstep(0.0, 0.15, h) * (1.0 - smoothstep(0.2, 0.5, h));
	float wave_strength = mix(cloud_strength * 0.35, cloud_strength * 1.1, grass_mask);
	float wv = smoothstep(0.45, 0.75, wave);
	c = mix(c, c * vec3(0.74, 0.83, 0.96) + vec3(0.02, 0.06, 0.14), wv * wave_strength);

	// 选中省份高亮闪烁：提亮 + 略泛白
	vec3 hl = c * 1.35 + vec3(0.15);
	c = mix(c, hl, highlight);

	ALBEDO = c;
	ROUGHNESS = 0.9;
}
