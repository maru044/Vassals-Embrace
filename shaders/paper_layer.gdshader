shader_type canvas_item;
// 面板纸纹层 shader：纸纹以屏幕像素固定密度无缝平铺（不随面板长宽比拉伸），
// 只输出纸纹「暗部」的黑色半透明层，叠加在纯色 StyleBoxFlat 面板上 ——
// 面板底色保持不变，仅纤维纹路处轻微压暗，形成「几乎纯色 + 弱纸纹」的质感。

// 纸纹 tile 尺寸（屏幕像素）：固定像素密度平铺，与面板大小/长宽比无关
uniform float tile_px : hint_range(32.0, 1024.0) = 320.0;

// 纸纹强度：0 = 无纹理，越大纹路越明显
uniform float strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	// 屏幕像素坐标：SCREEN_UV(0~1) / SCREEN_PIXEL_SIZE(1/px) = 像素坐标
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;

	// 无缝平铺：像素坐标 / tile_px，fract 周期重复
	vec2 tile = fract(screen_px / tile_px);
	vec4 paper = texture(TEXTURE, tile);

	// 纸纹暗部：纸面≈0（透明），纤维纹路>0（压暗）
	float shade = 1.0 - paper.r;

	// 输出纯黑 + 纹路 alpha：最终 = 底色 × (1 - shade*strength)
	COLOR = vec4(0.0, 0.0, 0.0, clamp(shade * strength, 0.0, 1.0));
}
