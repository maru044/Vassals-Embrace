shader_type canvas_item;
// 聊天立绘视差 shader（参考 ChatUI 案例；深度图驱动鼠标视差，产生伪 3D）

// 深度图纹理（灰度，r 通道：近亮远暗）
uniform sampler2D depth_map;

// 视差强度：控制移动幅度
uniform float depth_strength : hint_range(0.0, 0.2) = 0.05;

// 鼠标/视口偏移（-1.0 ~ 1.0，由脚本传入）
uniform vec2 mouse_offset = vec2(0.0, 0.0);

// 缩放系数：裁边防穿帮
uniform float scale : hint_range(1.0, 1.5) = 1.05;

void fragment() {
	// 1. 缩放 UV 避免边缘穿帮
	vec2 scaled_uv = (UV - 0.5) / scale + 0.5;

	// 2. 读取深度
	float depth = texture(depth_map, scaled_uv).r;

	// 3. 线性深度映射：深度 0.5 为视觉支点，[-0.50, +0.50]
	float depth_factor = depth - 0.50;

	// 4. 视差位移：近处（深）随鼠标移动大，远处小
	vec2 final_offset = mouse_offset * depth_strength * depth_factor;
	vec2 final_uv = scaled_uv + final_offset;

	// 5. 采样主纹理
	COLOR = texture(TEXTURE, final_uv);
}
