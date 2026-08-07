// 地图地形 shader：高度图位移（平↔立体）+ 国家/地形着色
// 高度图按【世界 XZ 坐标】采样（非 UV），天然适配不规则网格。
// 对齐常量：x[-15.1,14.8] z[-26.65,13.8]，height.png 1224x1656，40.94px/unit
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

varying float v_height;
varying float v_lat;   // 纬度：0=北（高纬） 1=南（低纬）

void vertex() {
	// 高度图按世界 XZ 采样
	vec2 uv = (VERTEX.xz - hmap_min) / hmap_size;
	float h = texture(heightmap, uv).r;   // 0=海 1=最高
	v_height = h;
	// 纬度（北 z 负 → 0，南 z 正 → 1）
	v_lat = clamp((VERTEX.z - hmap_min.y) / hmap_size.y, 0.0, 1.0);
	// y_offset 不乘 terrain_blend：省份层始终上抬，避免平面模式与陆地基底 z-fighting
	VERTEX.y += h * height_scale * terrain_blend + y_offset;
}

// 地形色带（双要素：高度 + 纬度）：
// - 纬度混合冷暖底色（北冷灰绿/灰褐 → 南暖嫩绿/黄褐）
// - 高度分阶（V3 卡通 banding）
// - 雪线随纬度：北低（低地也雪）→ 南高（只有高山有雪）
vec3 terrain_palette(float h, float lat) {
	vec3 low  = mix(vec3(0.55, 0.62, 0.50), vec3(0.62, 0.78, 0.48), lat);  // 低地 冷/暖
	vec3 hill = mix(vec3(0.60, 0.58, 0.52), vec3(0.76, 0.72, 0.42), lat);  // 丘陵 冷/暖
	vec3 rock = mix(vec3(0.66, 0.63, 0.60), vec3(0.78, 0.64, 0.45), lat);  // 山地 冷/暖
	// 高度分档（窄 smoothstep，卡通感不硬边）
	float b1 = smoothstep(0.28, 0.34, h);   // 低地 → 丘陵
	float b2 = smoothstep(0.58, 0.64, h);   // 丘陵 → 山地
	vec3 c = mix(low, hill, b1);
	c = mix(c, rock, b2);
	// 纬度相关雪线：北（lat=0）0.05 → 南（lat=1）0.65
	float snowline = mix(0.05, 0.65, lat);
	float snow = smoothstep(snowline, snowline + 0.2, h);
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

	// 选中省份高亮闪烁：提亮 + 略泛白
	vec3 hl = c * 1.35 + vec3(0.15);
	c = mix(c, hl, highlight);

	ALBEDO = c;
	ROUGHNESS = 0.9;
}
