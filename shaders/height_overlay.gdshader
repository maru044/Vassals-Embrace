// 高度图叠加调试 shader：把高度图灰度映射为醒目伪彩色，
// 海（≈0）半透明蓝，陆地绿→黄→白，便于在地图上人工对齐。
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color;

void fragment() {
	float h = texture(tex, UV).r;
	vec3 sea  = vec3(0.05, 0.3, 0.6);
	vec3 low  = vec3(0.15, 0.75, 0.25);
	vec3 mid  = vec3(1.0, 0.78, 0.18);
	vec3 high = vec3(0.95, 0.95, 0.9);
	vec3 c = mix(sea, low, smoothstep(0.02, 0.18, h));
	c = mix(c, mid, smoothstep(0.32, 0.62, h));
	c = mix(c, high, smoothstep(0.75, 1.0, h));
	ALBEDO = c;
	// 海透明、陆地高不透明度，轮廓清晰
	ALPHA = mix(0.3, 0.92, smoothstep(0.02, 0.2, h));
}
