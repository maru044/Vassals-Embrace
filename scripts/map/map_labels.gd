class_name MapLabels
extends Node3D
## 地图标签：为区域生成沿脊线的弧线文字标签（逐字 Label3D，贴地形）。
## 缩放层级：远=宗主名、中/近=国名+省名。字号随脊线长度动态。

enum Kind { LIEGE, COUNTRY, PROVINCE }

const HMAP_MIN := Vector2(-15.1, -26.65)
const HMAP_SIZE := Vector2(29.9, 40.45)
const PIXEL_SIZE := 0.015    # 文字像素→世界单位（偏大便于阅读）

var _font: Font
var _height_img: Image = null
var _height_scale := 1.0
var _labels: Array = []      # { root, kind }


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
	var fs := int(clampf(len * 2.5, 26.0, 110.0))
	if kind == Kind.PROVINCE:
		fs = int(clampf(len * 1.5, 16.0, 52.0))
	# 文字总宽（用于居中）
	var text_width := 0.0
	for i in text.length():
		text_width += _font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * PIXEL_SIZE
	# 从脊线中点开始排版（居中，不顶满）
	var t := maxf((len - text_width) * 0.5, 0.0)
	var root := Node3D.new()
	root.name = text
	for i in text.length():
		var ch := text[i]
		var adv: float = _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * PIXEL_SIZE
		var pos := _point_on(pts, t)
		var tan := _tangent_on(pts, t)
		var y := _sample_height(pos.x, pos.z)
		var lb := Label3D.new()
		lb.text = ch
		lb.font = _font
		lb.font_size = fs
		lb.pixel_size = PIXEL_SIZE
		lb.modulate = Color(0.97, 0.93, 0.8)      # 奶油白字（彩色地图上可读）
		lb.outline_size = maxi(fs / 8, 2)          # 深色描边
		lb.outline_modulate = Color(0.2, 0.15, 0.1)
		# 贴地（法线朝上）+ 沿切线
		var X := Vector3(tan.x, 0.0, tan.z)
		var Z := Vector3.UP
		var Y := Z.cross(X)
		lb.basis = Basis(X, Y, Z)
		lb.position = Vector3(pos.x, y + 0.08, pos.z)
		root.add_child(lb)
		t += adv
	root.visible = false
	add_child(root)
	_labels.append({"root": root, "kind": kind})


func set_zoom(zoom: float) -> void:
	# 远=宗主；中/近=国+省
	for l in _labels:
		match int(l["kind"]):
			Kind.LIEGE:
				l["root"].visible = zoom < 0.45
			Kind.COUNTRY:
				l["root"].visible = zoom >= 0.2
			Kind.PROVINCE:
				l["root"].visible = zoom >= 0.45


func _sample_height(x: float, z: float) -> float:
	if _height_img == null:
		return 0.0
	var uv := (Vector2(x, z) - HMAP_MIN) / HMAP_SIZE
	var px := clampi(int(uv.x * _height_img.get_width()), 0, _height_img.get_width() - 1)
	var py := clampi(int(uv.y * _height_img.get_height()), 0, _height_img.get_height() - 1)
	var g := _height_img.get_pixel(px, py).r
	return g * _height_scale


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
