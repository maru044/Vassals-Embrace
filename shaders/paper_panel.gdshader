shader_type canvas_item;
// 面板纸张材质 shader（标准 2D 美术做法）：
// 1. 世界坐标平铺 —— 用 SCREEN_UV / SCREEN_PIXEL_SIZE 换算成屏幕像素坐标，
//    以固定像素尺寸 tile_size 平铺纸纹；所有面板共享同一屏幕坐标 → 无缝、不拉伸、跨面板连续。
// 2. 颜色混合 —— 面板底色（stylebox 羊皮纸底/描边结构）与「染色纸」线性混合（mix），
//    纸纹染色成羊皮纸色（paper_tint），而非正片叠底叠加花纹。
// 3. 无缝拼贴 —— fract() 保证周期重复，纸纹在任意大小面板上均匀平铺。

// 纸张纹理
uniform sampler2D paper_tex;

// 纸纹 tile 尺寸（屏幕像素）：纸纹以该尺寸无缝平铺，与面板大小无关
uniform float tile_size : hint_range(64.0, 1024.0) = 512.0;

// 纸张染色（羊皮纸色）：纸纹 × tint 得到面板本色
uniform vec3 paper_tint : source_color = vec3(0.92, 0.84, 0.65);

// 颜色混合强度：0 = 纯面板底色，1 = 纯染色纸
uniform float paper_strength : hint_range(0.0, 1.0) = 0.85;

// 纸纹偏移（可选，微调接缝/对齐）
uniform vec2 paper_offset = vec2(0.0, 0.0);

void fragment() {
	// 面板自身结构：stylebox 的羊皮纸底 + 圆角/描边/阴影（含 alpha）
	vec4 base = texture(TEXTURE, UV);

	// 屏幕像素坐标：SCREEN_UV(0~1) / SCREEN_PIXEL_SIZE(1/px) = 像素坐标
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;

	// 无缝平铺：像素坐标 / tile_size，fract 周期重复
	vec2 tile = fract(screen_px / tile_size + paper_offset);
	vec4 paper = texture(paper_tex, tile);

	// 颜色混合：base（结构）与染色纸（paper × tint）线性混合
	vec3 mixed = mix(base.rgb, paper.rgb * paper_tint, paper_strength);
	COLOR = vec4(mixed, base.a);
}
