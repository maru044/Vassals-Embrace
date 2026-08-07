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

// ---- 2D 梯度噪声（Perlin 风格，无值噪声的方块伪影）----
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
vec2 grad2(vec2 p) {
	float a = hash21(p) * 6.2831853;   // 伪随机梯度角
	return vec2(cos(a), sin(a));
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	// 四角梯度点乘（-1~1，平滑无格点方块）
	float n00 = dot(grad2(i), f);
	float n10 = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n01 = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n11 = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}
// 固定旋转矩阵（打乱各层网格对齐，摧毁正交方块感——参考 Master 解法）
mat2 rot = mat2(vec2(0.877, 0.479), vec2(-0.479, 0.877));   // 旋转 ~28.6°
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.0;
		p = rot * p;   // 每层旋转坐标系，各层格点不再正交对齐 → 无方块伪影
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

	// 麦浪/云（借鉴恒星等离子流动）：双层 fbm 噪声，草地颜色在暗/亮间随时间自然变色（亮度+色相）
	vec2 wuv = (v_world - hmap_min) / hmap_size;
	vec2 wp = wuv * 9.0;   // 高密度（麦浪对国家尺度是小而密的）
	float n1 = fbm(wp + vec2(TIME * 0.18, TIME * 0.14));
	float n2 = fbm(wp * 1.7 + vec2(-TIME * 0.14, TIME * 0.1));
	float wave = clamp((n1 + n2) * 0.25 + 0.5, 0.0, 1.0);  // 梯度噪声 -1~1 → 归一到 0~1
	// 草地（低地）区域：h=0 平地也是草地（地形 shader 只渲染陆地，0 高度即平原）
	float grass_mask = 1.0 - smoothstep(0.15, 0.45, h);
	// 草地颜色层次：暗草（偏蓝降亮）↔ 亮草（泛黄提亮），差异大、随 wave 流动（麦浪）
	vec3 dark_g = vec3(0.58, 0.72, 1.10);
	vec3 bright_g = vec3(1.38, 1.20, 0.76);
	vec3 gcol = mix(c * dark_g, c * bright_g, smoothstep(0.3, 0.7, wave));
	c = mix(c, gcol, grass_mask);
	// 非草地（山/雪）轻度云影
	float cloud = smoothstep(0.55, 0.8, fbm(wuv * 2.0 + vec2(TIME * 0.08, TIME * 0.06)) * 0.5 + 0.5);
	c = mix(c, c * vec3(0.78, 0.85, 0.96) + vec3(0.02, 0.05, 0.12), (1.0 - grass_mask) * cloud_strength * 0.3 * cloud);

	// 选中省份高亮闪烁：提亮 + 略泛白
	vec3 hl = c * 1.35 + vec3(0.15);
	c = mix(c, hl, highlight);

	ALBEDO = c;
	ROUGHNESS = 0.9;
}
