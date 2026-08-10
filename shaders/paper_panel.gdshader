shader_type canvas_item;
// 面板纸张材质 shader：
// 1. 世界坐标平铺 —— SCREEN_UV / SCREEN_PIXEL_SIZE 换算成屏幕像素坐标，
//    以固定像素尺寸 tile_size 平铺纸纹；不拉伸、无缝、跨面板连续。
// 2. 颜色混合 —— 面板主体底色与「染色纸」线性混合（mix），纸纹染色成羊皮纸色。
// 3. 只混合主体 —— 用 base 颜色与面板底色（body_color）的接近度做 mask：
//    面板主体应用纸纹，边缘（金色描边/圆角阴影）保持原样不被覆盖。

uniform sampler2D paper_tex;

// 纸纹 tile 尺寸（屏幕像素）：纸纹以该尺寸无缝平铺，与面板大小无关
uniform float tile_size : hint_range(64.0, 1024.0) = 512.0;

// 纸张染色（羊皮纸色）：纸纹 × tint 得到面板本色
uniform vec3 paper_tint : source_color = vec3(0.92, 0.84, 0.65);

// 颜色混合强度：0 = 纯面板底色，1 = 纯染色纸（弱化材质效果就调小它）
uniform float paper_strength : hint_range(0.0, 1.0) = 0.55;

// 面板主体底色（= PANEL_BG）：用于区分「主体」与「描边/阴影」
uniform vec3 body_color : source_color = vec3(0.87, 0.76, 0.54);

// 主体判定敏感度：颜色偏离 body_color 超过上界视为边缘（描边/阴影），不混合
uniform float body_threshold : hint_range(0.03, 0.4) = 0.14;

// 纸纹偏移（可选）
uniform vec2 paper_offset = vec2(0.0, 0.0);

void fragment() {
	// 面板自身结构：stylebox 的羊皮纸底 + 圆角/描边/阴影（含 alpha）
	vec4 base = texture(TEXTURE, UV);

	// 屏幕像素坐标 → 无缝平铺纸纹
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 tile = fract(screen_px / tile_size + paper_offset);
	vec4 paper = texture(paper_tex, tile);

	// 主体混合色：底色与染色纸线性混合
	vec3 mixed = mix(base.rgb, paper.rgb * paper_tint, paper_strength);

	// 主体 mask：base 颜色越接近 body_color（主体底）越混合；描边金色/阴影暗色 → 不混合
	float dist = distance(base.rgb, body_color);
	float body_mask = 1.0 - smoothstep(body_threshold * 0.4, body_threshold, dist);

	COLOR = vec4(mix(base.rgb, mixed, body_mask), base.a);
}
