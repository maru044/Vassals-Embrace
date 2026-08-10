shader_type canvas_item;
// 面板纸张材质 shader：面板底色（stylebox 羊皮纸）× 纸张纹理亮度 = 正片叠底，
// 产生真实的纸张纤维/纹理质感。UV 可放大使纸纹更细密（消除单张纹理的边界感）。

// 纸张纹理（灰度/米色纸面，r 通道亮度参与正片叠底）
uniform sampler2D paper_tex;

// UV 放大倍数：>1 时纸纹在面板上平铺更多次，更细密（「稍微大一点」用 1.6）
uniform float paper_scale : hint_range(0.5, 6.0) = 1.6;

// 叠加强度：0=不叠加，1=完全正片叠底
uniform float paper_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// 1. 面板自身内容（stylebox 羊皮纸底色 + 圆角/描边）
	vec4 base = texture(TEXTURE, UV);

	// 2. 采样纸张纹理（UV 放大 → 更细密的纸纹）
	vec4 paper = texture(paper_tex, UV * paper_scale);

	// 3. 正片叠底：final = base * lerp(白, 纸纹, 强度)
	vec3 tint = mix(vec3(1.0), paper.rgb, paper_strength);
	COLOR = vec4(base.rgb * tint, base.a);
}
