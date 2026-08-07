class_name MapLabels
extends Node3D
## 地图标签：为区域生成沿脊线的弧线文字标签（逐字 Label3D，贴地形）。
## 缩放层级：远=只宗主名、中=只国名、近=只省名（三档互斥）。字号随脊线长度动态，含字距。

enum Kind { LIEGE, COUNTRY, PROVINCE }

const HMAP_MIN := Vector2(-15.1, -26.65)
const HMAP_SIZE := Vector2(29.9, 40.45)
const PIXEL_SIZE := 0.015    # 文字像素→世界单位
const SPACING_RATIO := 0.25  # 字距 = 字号的 25%（汉字留白，防过密）

var _font: Font
var _height_img: Image = null
var _height_scale := 1.0
var _labels: Array = []      # { root, kind }
var _spine_lines: Array = [] # 调试：脊线/控制点 MeshInstance3D（F9 显示）


func setup(font: Font, heightmap: Texture2D) -> void:
	_font = font
	if heightmap:
		_height_img = heightmap.get_image()


func add_label(text: String, verts: PackedVector3Array, kind: int) -> void:
	if _font == null or text.is_empty() or verts.size() < 3:
		return
	var spine: Dictionary = LabelPath.compute_spine(verts)
	var pts: PackedVector3Array = spine["points"]
	var len: float = spine["length"]
	if pts.size() < 2 or len <= 0.0:
		return
	# 字号随脊线长度（国家大、省份小）
	var fs := int(clampf(len * 3.2, 30.0, 130.0))
	var min_fs := 18
	if kind == Kind.PROVINCE:
		fs = int(clampf(len * 1.9, 18.0, 64.0))
		min_fs = 12
	# 单字符步进 = 字符宽 + 字距（闭包按引用捕获 fs）
	var step := func(ch: String) -> float:
		return (_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * SPACING_RATIO) * PIXEL_SIZE
	# 文字总宽（含字距，用于居中）
	var text_width := 0.0
	for i in text.length():
		text_width += step.call(text[i])
	# 防超长：文字宽 > 脊线长时按比例缩小字号，避免字符堆在脊线末端/弯曲处挤成一团
	if text_width > len:
		var s := len / text_width
		fs = maxi(int(fs * s), min_fs)
		text_width = 0.0
		for i in text.length():
			text_width += step.call(text[i])
	# 从脊线中点开始排版（居中，不顶满）
	var t := maxf((len - text_width) * 0.5, 0.0)
	var root := Node3D.new()
	root.name = text
	for i in text.length():
		var ch := text[i]
		var adv: float = step.call(ch)
		var pos := _point_on(pts, t)
		var tan := _tangent_on(pts, t)
		var lb := Label3D.new()
		lb.text = ch
		lb.font = _font
		lb.font_size = fs
		lb.pixel_size = PIXEL_SIZE
		lb.modulate = Color(0.97, 0.93, 0.8)      # 奶油白字（彩色地图上可读）
		lb.outline_size = maxi(fs / 8, 2)          # 深色描边
		lb.outline_modulate = Color(0.2, 0.15, 0.1)
		# 平铺在地面上（EU4 式）：关闭 billboard，文本平面躺平（法线朝 +Y），
		# 绕 Y 轴对齐脊线切线在地面的投影，保持横向弧线感。
		lb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lb.rotation.x = -PI / 2.0
		lb.rotation.y = atan2(-tan.z, tan.x)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# 位置沿脊线（弧线感）；高度取字符覆盖区域最大值（防山坡穿模），加小偏移防 z-fighting
		var radius := clampf(adv * 0.55, 0.25, 1.2)
		lb.position = Vector3(pos.x, _sample_height_max(pos.x, pos.z, radius) + 0.06, pos.z)
		root.add_child(lb)
		t += adv
	root.visible = false
	add_child(root)
	_labels.append({"root": root, "kind": kind, "pts": pts, "ctrl": spine.get("ctrl", [])})
	_build_spine_lines(pts, spine.get("ctrl", []))


func set_zoom(zoom: float) -> void:
	# 三档互斥（Master 规则）：远=只宗主名；中=只国名；近=只省名
	for l in _labels:
		var vis := false
		match int(l["kind"]):
			Kind.LIEGE:
				vis = zoom < 0.35
			Kind.COUNTRY:
				vis = zoom >= 0.35 and zoom < 0.6
			Kind.PROVINCE:
				vis = zoom >= 0.6
		l["root"].visible = vis


## 调试可视化：显示/隐藏所有脊线（红）与控制点（黄十字），供 Master 检查曲线形状。
func debug_show_spines(show: bool) -> void:
	for mi in _spine_lines:
		mi.visible = show


func _build_spine_lines(pts: PackedVector3Array, ctrl: Array) -> void:
	# 脊线（红色实线）
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		im.surface_add_vertex(Vector3(p.x, _dbg_y(p) + 0.3, p.z))
	im.surface_end()
	_spine_lines.append(_add_line_mesh(im, Color(1.0, 0.25, 0.25)))
	# 控制点（黄色十字，方便看出 B 样条控制点分布）
	if ctrl.size() > 0:
		var imc := ImmediateMesh.new()
		imc.surface_begin(Mesh.PRIMITIVE_LINES)
		var cs := 0.35
		for c in ctrl:
			var v: Vector3 = c
			var y := _dbg_y(v) + 0.3
			imc.surface_add_vertex(Vector3(v.x - cs, y, v.z))
			imc.surface_add_vertex(Vector3(v.x + cs, y, v.z))
			imc.surface_add_vertex(Vector3(v.x, y, v.z - cs))
			imc.surface_add_vertex(Vector3(v.x, y, v.z + cs))
		imc.surface_end()
		_spine_lines.append(_add_line_mesh(imc, Color(1.0, 0.85, 0.2)))


func _add_line_mesh(im: ImmediateMesh, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true   # 始终可见，便于检查（穿过地形）
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return mi


func _dbg_y(p: Vector3) -> float:
	# 脊线 y 采样高度图（与文字一致贴合），便于和文字位置对比
	return _sample_height_max(p.x, p.z, 0.3)


func _sample_height(x: float, z: float) -> float:
	if _height_img == null:
		return 0.0
	var uv := (Vector2(x, z) - HMAP_MIN) / HMAP_SIZE
	var px := clampi(int(uv.x * _height_img.get_width()), 0, _height_img.get_width() - 1)
	var py := clampi(int(uv.y * _height_img.get_height()), 0, _height_img.get_height() - 1)
	var g := _height_img.get_pixel(px, py).r
	return g * _height_scale


## 采样字符覆盖区域内的最大高度（中心 + 四角），避免平铺文字在坡面穿模。
func _sample_height_max(x: float, z: float, radius: float) -> float:
	if _height_img == null:
		return 0.0
	var h := -INF
	for o in [
		Vector2(0, 0), Vector2(-radius, 0), Vector2(radius, 0),
		Vector2(0, -radius), Vector2(0, radius),
	]:
		h = maxf(h, _sample_height(x + o.x, z + o.y))
	return h if h != -INF else 0.0


static func _point_on(p: PackedVector3Array, d: float) -> Vector3:
	var acc := 0.0
	for i in p.size() - 1:
		var seg := p[i].distance_to(p[i + 1])
		if acc + seg >= d:
			var tt := (d - acc) / maxf(seg, 0.0001)
			return p[i].lerp(p[i + 1], tt)
		acc += seg
	return p[p.size() - 1]


static func _tangent_on(p: PackedVector3Array, d: float) -> Vector3:
	var acc := 0.0
	for i in p.size() - 1:
		var seg := p[i].distance_to(p[i + 1])
		if acc + seg >= d:
			return (p[i + 1] - p[i]).normalized()
		acc += seg
	return (p[p.size() - 1] - p[p.size() - 2]).normalized()
