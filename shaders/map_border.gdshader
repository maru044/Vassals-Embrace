// 省份边界描边 shader：沿边界线网格绘制深色细线，跟随地形位移（高度图世界XZ采样）。
// 与主地形 shader 分离：本 shader 只负责描边，不影响省份颜色。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D heightmap : source_color, filter_linear, repeat_disable;
uniform vec2 hmap_min = vec2(-15.1, -26.65);
uniform vec2 hmap_size = vec2(29.9, 40.45);
uniform float height_scale = 1.0;
uniform float terrain_blend = 1.0;      // 0=平面 1=立体
uniform vec3 border_color : source_color = vec3(0.1, 0.1, 0.12);

void vertex() {
	vec2 uv = (VERTEX.xz - hmap_min) / hmap_size;
	float h = texture(heightmap, uv).r;
	VERTEX.y += h * height_scale * terrain_blend;
}

void fragment() {
	ALBEDO = border_color;
}
