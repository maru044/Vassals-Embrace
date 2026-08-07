// 地图地形 shader：高度图位移（平↔立体）+ 三层颜色（远宗主/中本宗/近地形）+ 省界描边
// 高度图按【世界 XZ 坐标】采样（非 UV），天然适配不规则网格。
// 对齐常量：x[-15.1,14.8] z[-26.65,13.8]，height.png 1224x1656，40.94px/unit
shader_type spatial;
render_mode cull_disabled;

// ---- 高度图与对齐 ----
uniform sampler2D heightmap : source_color, filter_linear, repeat_disable;
uniform vec2 hmap_min = vec2(-15.1, -26.65);
uniform vec2 hmap_size = vec2(29.9, 40.45);
uniform float height_scale = 1.0;      // 平面约10m → 最高地形约1m
uniform float terrain_blend = 0.0;     // 0=平面 1=立体（相机距离驱动）
uniform float y_offset = 0.0;          // 省份覆盖层微量上抬，避免与陆地基底 z-fight

// ---- 颜色 ----
uniform vec3 own_color : source_color = vec3(0.8, 0.75, 0.7);  // 本宗色（中层）
uniform vec3 far_color : source_color = vec3(0.8, 0.75, 0.7);  // 宗主色（远层，取最上级宗主）
uniform float zoom = 0.5;               // 0=远 1=近

varying float v_height;

void vertex() {
	// 高度图按世界 XZ 采样
	vec2 uv = (VERTEX.xz - hmap_min) / hmap_size;
	float h = texture(heightmap, uv).r;   // 0=海 1=最高
	v_height = h;
	VERTEX.y += h * height_scale * terrain_blend + y_offset * terrain_blend;
}

// 地形色带：低草地绿 → 丘陵黄绿 → 高地岩石 → 雪
vec3 terrain_palette(float h) {
	vec3 grass = vec3(0.45, 0.62, 0.34);
	vec3 hill  = vec3(0.58, 0.62, 0.38);
	vec3 rock  = vec3(0.62, 0.6, 0.52);
	vec3 snow  = vec3(0.93, 0.93, 0.92);
	float h1 = smoothstep(0.08, 0.25, h);
	float h2 = smoothstep(0.45, 0.65, h);
	float h3 = smoothstep(0.85, 0.98, h);
	vec3 c = mix(grass, hill, h1);
	c = mix(c, rock, h2);
	c = mix(c, snow, h3);
	return c;
}

void fragment() {
	float h = v_height;
	vec3 terrain = terrain_palette(h);

	// 远层：宗主色（附庸涂宗主国颜色）｜中层：本宗色｜近层：地形
	float t_far = 1.0 - smoothstep(0.25, 0.6, zoom);
	float t_terrain = smoothstep(0.55, 0.95, zoom);
	vec3 c = mix(own_color, terrain, t_terrain);
	c = mix(c, far_color, t_far);

	ALBEDO = c;
	ROUGHNESS = 0.9;
}
