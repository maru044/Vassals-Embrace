extends Node3D
## 地图场景：加载 map.gltf，按国家着色（远=宗主色/中=本宗色/近=地形），EU4 相机，省份拾取，平↔立体位移。
## 数据：data/map_data.json（省份→国家）、data/country_colors.json（颜色+宗主）、assets/map/height.png（高度图）
## 图层：Britain/Ireland = 陆地基底（地形色）；42 省份 = 覆盖层（国家色 + 微量上抬）。

signal province_picked(province: String, country: String)

const MAP_DATA_PATH := "res://data/map_data.json"
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"
const TERRAIN_SHADER_PATH := "res://shaders/map_terrain.gdshader"
const HEIGHTMAP_PATH := "res://assets/map/height.png"
const HEIGHT_OVERLAY_SHADER := "res://shaders/height_overlay.gdshader"
const OCEAN_SHADER_PATH := "res://shaders/map_ocean.gdshader"
const SEA_DISTANCE_PATH := "res://assets/map/sea_distance.png"
const WATER_NORMAL_PATH := "res://assets/map/water_normal.png"
const SKY_HDRI_PATH := "res://assets/sky/venice_sunset_2k.exr"
const LABEL_FONT_PATH := "res://assets/fonts/TimesNewRoman-Bold.ttf"   # V3 古典衬线加粗
const LAND_BASE_COLOR := Color(0.75, 0.72, 0.62)   # 陆地基底中性色
const SUBDIVIDE_MAX_EDGE := 1.0                     # 网格细分最大边长（世界单位），越小地形越细腻
const OCEAN_MARGIN := 4.0                           # 距离场/海洋平面外扩（须覆盖近海渐变上界 2.5m，与 gen_sea_distance.py 一致）
const OCEAN_Y := -0.03                              # 海洋平面 y（略低于陆地基底 y=0，陆地遮挡海洋）
const FORT_ICON_PATH := "res://assets/map/fort_icon.png"   # 要塞图标（堡垒.png，Master 提供；本身已是透明背景）
const FORT_ICON_SIZE := 0.5                         # 要塞图标世界宽度（立牌，Master：缩小）
const FORT_ICON_ALPHA := 0.65                       # 图标主体透明度（Master：图标本身也透明，半透明）
const FORT_ICON_LIFT := 0.35                        # 要塞图标浮起高度（相对省份地表）
const SHIELD_DIR := "res://assets/shields/"
const ARMY_BANNER_LIFT := 1.1          # 兵牌浮起高度（相对省份地表，高于要塞图标）
const ARMY_BANNER_ALPHA := 0.75        # 军队盾徽透明度（Master：半透明；数字保持不透明）
const ARMY_BANNER_STACK_GAP := 0.85    # 同省多军队兵牌垂直堆叠间距（Master：上下放置）
# 引擎③ 士气条（盾徽右侧竖条，满士气绿色；随士气降低从顶端变短并渐变为黄→红；Master：EU4 血条式，无黑色背景）
const MORALE_BAR_W := 0.07             # 士气条宽度
const MORALE_BAR_H := 0.5              # 士气条满值高度（与盾徽高度一致）
const MORALE_BAR_X := 0.36             # 士气条 X 偏移（盾徽右缘外侧）
const MORALE_COL_FULL := Color(0.3, 0.95, 0.35, 0.95)   # 满士气：绿
const MORALE_COL_MID := Color(0.98, 0.82, 0.15, 0.95)   # 半士气：黄
const MORALE_COL_LOW := Color(0.95, 0.25, 0.15, 0.95)   # 低士气：红
const SIEGE_LABEL_X := 0.66            # 围城破城概率文字 X 偏移（兵牌最右侧）
const ICON_SHOW_ZOOM := 0.35           # 镜头远景（zoom 低于此）隐藏要塞/军队图标（Master：远景更美观）

# ---- 引擎②-B3-2c 兵牌交互 ----
const SEL_RING_RADIUS := 0.4           # 选中兵牌脚下金色圆环半径
const SEL_RING_LIFT := 0.12            # 选中圆环浮起高度（贴近地表）
const REACH_LINE_RADIUS := 0.035       # 合法移动线半径（细圆柱）
const REACH_LINE_COLOR := Color(0.45, 1.0, 0.55, 0.9)   # 合法目标线（亮绿）
const ORDER_LINE_COLOR := Color(1.0, 0.8, 0.3, 1.0)     # 命令路线线（金黄）
const ORDER_MARK_RADIUS := 0.3         # 命令目标省标记半径
const BANNER_HIT_PIXELS := 40.0        # 兵牌点击命中像素半径（屏幕空间）
const FEEDBACK_LIFT := 1.9             # 浮空操作提示高度（相对兵牌地表）
const FEEDBACK_SECONDS := 2.2          # 浮空提示持续/淡出秒数

# 相机（EU4 式）：俯角随缩放变化，yaw 固定从南看北（南在屏幕下，北退远）
const PITCH_FAR := deg_to_rad(85.0)
const PITCH_NEAR := deg_to_rad(45.0)
const DIST_FAR := 55.0
const DIST_NEAR := 9.0
const MAP_CENTER := Vector3(0.0, 0.0, -6.0)   # 地图中心（x≈0, z≈-6）
const ZOOM_MIN := 0.15                          # 最远缩放下限（保留余量防 Z 闪烁）

@onready var _camera: Camera3D = $Camera3D
@onready var _map: Node3D = $Map

var _zoom := 0.5
var _target := MAP_CENTER
var _owners := {}                     # province -> country
var _collider_to_province := {}       # StaticBody3D -> province
var _province_mesh := {}              # province -> MeshInstance3D（高亮用）
var _heightmap: Texture2D = null
var _terrain_shader: Shader = null
var _shader_mats: Array = []          # 需每帧更新 zoom/terrain_blend 的材质
var _flash_name := ""                 # 当前选中省份（持续高亮呼吸）
var _flash_time := 0.0                # 呼吸计时
var _labels: MapLabels = null
var _country_data := {}               # id -> {color, liege, liege_color}
var _top_liege_of := {}               # country -> 最上级宗主
var _show_spines := false             # F9：脊线调试可视化开关
var _hmin := Vector2(-15.1, -26.65)   # 高度图采样：左上角世界坐标（可手动微调）
var _hsize := Vector2(29.9, 40.45)    # 高度图采样：覆盖的世界尺寸（可手动微调）
var _height_overlay: MeshInstance3D = null
var _overlay_visible := false         # F10：高度图叠加调试开关
var _ocean: MeshInstance3D = null
var _ocean_mat: ShaderMaterial = null
var _fort_texture: Texture2D = null   # 要塞图标纹理
var _fort_icons := {}                 # province -> Sprite3D（fort≥2 才创建）
var _army_banners := {}               # cid -> Node3D（军队兵牌容器，显示盾徽+方框+数字k）
var _selected_army := ""              # 当前选中军队国家 id（""=未选中）
var _sel_root: Node3D = null          # 选中指示容器（金色圆环 + 合法移动线）
var _order_root: Node3D = null        # 命令指示容器（目标省标记 + 命令路线）
var _feedback: Label3D = null         # 浮空操作提示（成功/非法）
var _feedback_timer := 0.0            # 剩余显示秒数


func _ready() -> void:
	_heightmap = load(HEIGHTMAP_PATH)
	_terrain_shader = load(TERRAIN_SHADER_PATH)
	_fort_texture = load(FORT_ICON_PATH)
	_apply_colors()
	_setup_labels()
	_setup_heightmap_overlay()
	_setup_ocean()
	_update_camera()


func _process(delta: float) -> void:
	_handle_wasd(delta)
	_update_shader_uniforms()
	_update_flash(delta)
	_update_labels()
	_update_feedback(delta)
	_update_icon_visibility()


## ===== 相机控制 =====

func _handle_wasd(delta: float) -> void:
	var speed := 12.0 * lerpf(0.6, 2.5, _zoom) * delta
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1.0   # 北（屏幕上方）
	if Input.is_key_pressed(KEY_S): dir.z += 1.0   # 南
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0   # 西
	if Input.is_key_pressed(KEY_D): dir.x += 1.0   # 东
	if dir != Vector3.ZERO:
		_target += dir.normalized() * speed
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom + 0.12, ZOOM_MIN, 1.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - 0.12, ZOOM_MIN, 1.0)
				_update_camera()
			MOUSE_BUTTON_LEFT:
				_handle_left_click(event.position)
			MOUSE_BUTTON_RIGHT:
				_handle_right_click(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_toggle_spines()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_toggle_overlay()
	elif event is InputEventKey and event.pressed and not event.echo and _overlay_visible:
		_handle_overlay_keys(event)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		# 中键拖拽平移（左键留给拾取）
		_target.x -= event.relative.x * 0.03
		_target.z -= event.relative.y * 0.03
		_update_camera()


## 调试：F9 切换显示/隐藏所有标签的脊线（红）与控制点（黄十字），检查曲线形状。
func _toggle_spines() -> void:
	_show_spines = not _show_spines
	if _labels:
		_labels.debug_show_spines(_show_spines)
	print("map_view: 脊线可视化 ", "ON" if _show_spines else "OFF")


## 调试：F10 显示/隐藏高度图半透明叠加，用于手动对齐采样常量。
func _toggle_overlay() -> void:
	_overlay_visible = not _overlay_visible
	if _height_overlay:
		_height_overlay.visible = _overlay_visible
	print("map_view: 高度图叠加 ", "ON" if _overlay_visible else "OFF")


func _setup_heightmap_overlay() -> void:
	if _heightmap == null:
		print("map_view: 高度图叠加未创建（heightmap 为空）")
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _make_ground_quad(_hsize.x, _hsize.y)
	var shader := load(HEIGHT_OVERLAY_SHADER) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex", _heightmap)
	mi.material_override = mat
	mi.position = Vector3(_hmin.x, 3.0, _hmin.y)
	mi.visible = false
	add_child(mi)
	_height_overlay = mi
	print("map_view: 高度图叠加已创建（伪彩色）")


## 手动构建 XZ 平面四边形（直接躺平，法线朝上），避免 PlaneMesh 旋转朝向歧义。
## 顶点 (0,0,0)→左上(uv 0,0)，(w,0,h)→右下(uv 1,1)。
func _make_ground_quad(w: float, h: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, h), Vector3(0, 0, h),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## 海洋平面：复用场景里已有的 Ocean 节点（PlaneMesh 124×144 大平面，中心在地图中心，
## 覆盖镜头最远视野不露边界），给它换上海洋 shader 材质驱动深度渐变与近海白浪。
## 距离场纹理覆盖地图范围 + OCEAN_MARGIN 外扩（ocean_min/ocean_size 采样），
## 平面超出部分采样到距离场 clamp 边缘 = 深水（MAX_M），无硬交界。
func _setup_ocean() -> void:
	if _ocean:
		return
	var ocean_min := Vector2(_hmin.x - OCEAN_MARGIN, _hmin.y - OCEAN_MARGIN)
	var ocean_size := Vector2(_hsize.x + OCEAN_MARGIN * 2.0, _hsize.y + OCEAN_MARGIN * 2.0)
	var mi := get_node_or_null("Ocean") as MeshInstance3D
	if mi == null:
		# 兜底：场景无 Ocean 节点时新建（XZ 大平面，中心对齐地图中心）
		mi = MeshInstance3D.new()
		mi.name = "Ocean"
		mi.position = Vector3(0.0, OCEAN_Y, -6.0)
		add_child(mi)
	var mat := ShaderMaterial.new()
	mat.shader = load(OCEAN_SHADER_PATH) as Shader
	if _heightmap:
		var sea_dist := load(SEA_DISTANCE_PATH) as Texture2D
		mat.set_shader_parameter("sea_dist", sea_dist)
		# 水面法线贴图（无缝平铺，近景波浪细节）
		var water_normal := load(WATER_NORMAL_PATH) as Texture2D
		mat.set_shader_parameter("water_normal", water_normal)
		# 朝阳 HDRI：Fresnel 反射采样（金色反光）——用 load 走导入管线，导出后仍可加载
		var sky_hdr := load(SKY_HDRI_PATH) as Texture2D
		mat.set_shader_parameter("sky_panorama", sky_hdr)
	mat.set_shader_parameter("ocean_min", ocean_min)
	mat.set_shader_parameter("ocean_size", ocean_size)
	mat.set_shader_parameter("max_dist", 8.0)
	mat.set_shader_parameter("terrain_blend", 0.0)
	mat.set_shader_parameter("zoom", _zoom)
	mi.material_override = mat
	_ocean = mi
	_ocean_mat = mat
	print("map_view: 海洋平面已复用场景 Ocean 节点（深度渐变 + 近海白浪 + Fresnel + 法线贴图 + 朝阳反射）")


## 叠加可见时：方向键平移 hmin，Q/E 缩放 hsize（Shift 细调），实时写回 shader。
func _handle_overlay_keys(event: InputEventKey) -> void:
	var step := 0.01 if event.shift_pressed else 0.1
	match event.keycode:
		KEY_LEFT: _hmin.x -= step
		KEY_RIGHT: _hmin.x += step
		KEY_UP: _hmin.y -= step      # 北（z 负方向）
		KEY_DOWN: _hmin.y += step    # 南（z 正方向）
		KEY_Q: _hsize *= 1.02
		KEY_E: _hsize *= 0.98
		_:
			return
	_apply_hmap()


func _apply_hmap() -> void:
	for mat in _shader_mats:
		mat.set_shader_parameter("hmap_min", _hmin)
		mat.set_shader_parameter("hmap_size", _hsize)
	if _height_overlay:
		_height_overlay.mesh = _make_ground_quad(_hsize.x, _hsize.y)
		_height_overlay.position = Vector3(_hmin.x, 3.0, _hmin.y)
	print("map_view: hmap_min=", _hmin, " hmap_size=", _hsize)


func _update_camera() -> void:
	var pitch := lerpf(PITCH_FAR, PITCH_NEAR, _zoom)
	var dist := lerpf(DIST_FAR, DIST_NEAR, _zoom)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * dist
	_camera.global_position = _target + offset
	_camera.look_at(_target, Vector3.UP)


func _update_shader_uniforms() -> void:
	if _shader_mats.is_empty():
		return
	# 远=0 完全平面（避免细分后边界破面）/ 近=1 立体
	var blend := smoothstep(0.25, 0.8, _zoom)
	for mat in _shader_mats:
		mat.set_shader_parameter("terrain_blend", blend)
		mat.set_shader_parameter("zoom", _zoom)
	# 海洋材质联动 zoom / terrain_blend（白浪/波动随近景增强）
	if _ocean_mat:
		_ocean_mat.set_shader_parameter("terrain_blend", blend)
		_ocean_mat.set_shader_parameter("zoom", _zoom)


func _update_labels() -> void:
	if _labels:
		_labels.set_zoom(_zoom)


## ===== 地图标签（国名/省名，沿脊线弧线） =====

func _setup_labels() -> void:
	_labels = MapLabels.new()
	add_child(_labels)
	_labels.setup(load(LABEL_FONT_PATH) as Font, _heightmap)
	_build_labels()


## 统一刷新入口：省份归属 / 颜色 / 标签全量更新（领土变化后调用一次）。
## 例：威尔士独立后传新的 province_owner / country_colors，英格兰的色块、字号/范围/宗主名自动适配。
func apply_ownership(new_owners: Dictionary = {}, new_country_data: Dictionary = {}) -> void:
	if not new_owners.is_empty():
		_owners = new_owners
	if not new_country_data.is_empty():
		_country_data = new_country_data
	_update_liege_map()
	_apply_province_colors()
	if _labels == null:
		return
	_labels.clear()
	_build_labels()


## 兼容入口：只重建标签（内部仍走 apply_ownership，颜色同步刷新）
func refresh_labels(new_owners: Dictionary = {}, new_country_data: Dictionary = {}) -> void:
	apply_ownership(new_owners, new_country_data)


## 按最新 _owners / _country_data 刷新每个省份材质的本宗色 own_color 与宗主色 far_color。
## （每省独立 ShaderMaterial，直接改 uniform 即可，无需重建材质。）
func _apply_province_colors() -> void:
	for province in _province_mesh:
		var mi: MeshInstance3D = _province_mesh[province]
		var mat: ShaderMaterial = mi.material_override as ShaderMaterial
		if mat == null:
			continue
		var cdata: Dictionary = _country_data.get(_owners.get(province, ""), {})
		mat.set_shader_parameter("own_color", cdata.get("color", Color.WHITE))
		mat.set_shader_parameter("far_color", cdata.get("liege_color", cdata.get("color", Color.WHITE)))


## 从 _country_data 重算最上级宗主映射（附庸套附庸）
func _update_liege_map() -> void:
	_top_liege_of.clear()
	for id in _country_data:
		var top: String = _country_data[id].get("liege", "") as String
		var guard := 0
		while not top.is_empty() and _country_data.has(top) and not (_country_data[top].get("liege", "") as String).is_empty() and guard < 16:
			top = _country_data[top].get("liege", "") as String
			guard += 1
		_top_liege_of[id] = top if (not top.is_empty() and _country_data.has(top)) else id


func _build_labels() -> void:
	if _labels == null:
		return
	# 收集省份顶点
	var province_verts := {}
	var country_verts := {}
	for province in _province_mesh:
		var mi: MeshInstance3D = _province_mesh[province]
		var verts := _mesh_verts(mi.mesh)
		if verts.is_empty():
			continue
		province_verts[province] = verts
		var country: String = _owners.get(province, "")
		if country.is_empty():
			continue
		if not country_verts.has(country):
			country_verts[country] = PackedVector3Array()
		country_verts[country].append_array(verts)
	# 宗主分组（最上级宗主的领域）
	var liege_verts := {}
	for country in country_verts:
		var top: String = _top_liege_of.get(country, country)
		if not liege_verts.has(top):
			liege_verts[top] = PackedVector3Array()
		liege_verts[top].append_array(country_verts[country])
	# 省名 / 国名 / 宗主名
	for province in province_verts:
		_labels.add_label(province, province_verts[province], MapLabels.Kind.PROVINCE)
	for country in country_verts:
		_labels.add_label(country, country_verts[country], MapLabels.Kind.COUNTRY)
	for liege in liege_verts:
		_labels.add_label(liege, liege_verts[liege], MapLabels.Kind.LIEGE)


func _mesh_verts(mesh: Mesh) -> PackedVector3Array:
	if not (mesh is ArrayMesh):
		return PackedVector3Array()
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts


## 省份锚点 = 网格顶点质心（x,z 居中；y 取地表均值，图标由此浮起）
func _province_anchor(mi: MeshInstance3D) -> Vector3:
	var verts := _mesh_verts(mi.mesh)
	if verts.is_empty():
		return mi.global_position
	var acc := Vector3.ZERO
	for v in verts:
		acc += v
	return acc / float(verts.size())


## 要塞图标（引擎②-B3-2）：只显示 fort ≥ 2 的省份（1 级无 ZoC，不显示）。
## 立牌（billboard）浮于省份地表上方，宽度 FORT_ICON_SIZE 世界单位。
func refresh_forts(buildings: Dictionary) -> void:
	for prov in _fort_icons:
		_fort_icons[prov].queue_free()
	_fort_icons.clear()
	if _fort_texture == null:
		return
	for province in _province_mesh:
		var fort: int = int(buildings.get(province, {}).get("fort", 0))
		if fort < 2:
			continue
		var anchor := _province_anchor(_province_mesh[province])
		var spr := Sprite3D.new()
		spr.texture = _fort_texture
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # 始终面向相机，清晰可见
		# 注意：Sprite3D 没有 transparency 属性（那是 BaseMaterial3D 的）——图标透明度由 modulate 的 alpha 控制
		spr.modulate = Color(1.0, 1.0, 1.0, FORT_ICON_ALPHA)   # 图标整体半透明（含主体）
		var tex_w: float = _fort_texture.get_size().x
		spr.pixel_size = FORT_ICON_SIZE / maxf(tex_w, 1.0)
		spr.position = Vector3(anchor.x, anchor.y + FORT_ICON_LIFT, anchor.z)
		spr.name = "Fort_" + province
		add_child(spr)
		_fort_icons[province] = spr


## 军队兵牌（引擎②-B3-2b 显示）：每国兵牌 = 盾徽 + 数字（k 单位），无背景（Master：去黑色底）。
## positions: cid -> 所在省；counts: cid -> 队数（1队=100人=0.1k）。只在游戏内调用（选国界面不显示）。
func refresh_army(positions: Dictionary, counts: Dictionary) -> void:
	for cid in _army_banners:
		_army_banners[cid].queue_free()
	_army_banners.clear()
	var font: Font = load(LABEL_FONT_PATH)
	# 按省份分组：同省多支军队沿 Y 上下堆叠（billboard Y = 屏幕上下），避免完全重叠
	var by_province := {}
	for cid in positions:
		var province: String = positions[cid]
		if not by_province.has(province):
			by_province[province] = []
		by_province[province].append(cid)
	for province in by_province:
		var mi: MeshInstance3D = _province_mesh.get(province, null)
		if mi == null:
			continue
		var anchor := _province_anchor(mi)
		var stack: Array = by_province[province]
		for i in stack.size():
			var cid: String = stack[i]
			var root := Node3D.new()
			root.name = "Army_" + str(cid)
			root.position = Vector3(anchor.x, anchor.y + ARMY_BANNER_LIFT + float(i) * ARMY_BANNER_STACK_GAP, anchor.z)
			# 盾徽（居中）
			var shield_path := SHIELD_DIR + str(cid) + ".png"
			if ResourceLoader.exists(shield_path):
				var shield_tex: Texture2D = load(shield_path)
				var sh := Sprite3D.new()
				sh.texture = shield_tex
				sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sh.pixel_size = 0.42 / maxf(shield_tex.get_size().x, 1.0)
				sh.modulate = Color(1.0, 1.0, 1.0, ARMY_BANNER_ALPHA)   # 盾徽半透明（Master）
				root.add_child(sh)
			# 数字（k 单位，盾徽右下方，小字号避免重叠）
			var lbl := Label3D.new()
			lbl.text = "%0.1fk" % (float(counts.get(cid, 0)) * 0.1)
			lbl.font = font
			lbl.font_size = 32
			lbl.pixel_size = 0.009
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.modulate = Color(0.97, 0.93, 0.8)
			lbl.outline_modulate = Color(0.1, 0.08, 0.06)
			lbl.outline_size = 6
			lbl.position = Vector3(0.52, -0.06, 0.0)   # 右移，给右侧士气条让位
			root.add_child(lbl)
			# 士气条（引擎③）：盾徽右侧竖条，满士气绿色，随士气降低从顶端变短并渐变黄→红（EU4 血条式，无黑色背景）
			# 直接用网格高度控制长度（不用 scale.y：billboard 材质下节点缩放失效，会导致整条下滑而非变短）
			var m_max_m: float = GameManager.get_total_morale(cid)
			var m_cur_m: float = GameManager.get_morale(cid)
			var m_ratio: float = 1.0 if m_max_m <= 0.0 else clampf(m_cur_m / m_max_m, 0.0, 1.0)
			var bar_h: float = MORALE_BAR_H * m_ratio
			var bar_fill := _make_morale_bar(MORALE_BAR_W, bar_h, _morale_color(m_ratio))
			# 底部固定在 -H/2、顶端随比例下降（从上面变短）：中心 = 底 + 半高
			bar_fill.position = Vector3(MORALE_BAR_X, -MORALE_BAR_H * 0.5 + bar_h * 0.5, 0.0)
			root.add_child(bar_fill)
			# 围城下城概率（引擎③-T4）：军队图标最右侧显示「破城X%」（仅围城中，金色小字）
			var siege_chance: float = GameManager.get_siege_chance(cid)
			if siege_chance > 0.0:
				var slbl := Label3D.new()
				slbl.text = "破城%d%%" % int(round(siege_chance * 100.0))
				slbl.font = font
				slbl.font_size = 24
				slbl.pixel_size = 0.009
				slbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				slbl.modulate = Color(1.0, 0.85, 0.3)
				slbl.outline_modulate = Color(0.1, 0.08, 0.06)
				slbl.outline_size = 6
				slbl.position = Vector3(SIEGE_LABEL_X, -0.02, 0.0)
				root.add_child(slbl)
			add_child(root)
			_army_banners[cid] = root
	# 兵牌重建后重绘选中/命令指示（月末军队移动后跟随）
	_refresh_selection_gfx()
	_refresh_order_gfx()
	_hide_feedback()   # 过月即清浮空提示（Master：下令提示不残留）


## ===== 引擎②-B3-2c 兵牌交互 =====

## 左键：先测兵牌命中 → 自己军队选中/取消（点别国兵牌无反应，Master 定）；未命中则回落省份拾取。
func _handle_left_click(screen_pos: Vector2) -> void:
	var hit := _hit_banner(screen_pos)
	if not hit.is_empty():
		if hit == GameManager.player_country_id:
			if _selected_army == hit:
				_deselect_army()
			else:
				_select_army(hit)
		# 点别国兵牌 → 无反应（保持当前选中不变）
		return
	_pick(screen_pos)


## 右键：有选中军队时，把点击解析为省份并下达移动令（合法/非法提示）
func _handle_right_click(screen_pos: Vector2) -> void:
	if _selected_army.is_empty():
		return
	var target := _pick_province(screen_pos)
	if target.is_empty():
		_show_feedback("未命中省份", false)
		return
	if target == GameManager.army_position.get(_selected_army, ""):
		_show_feedback("军队已在该省驻守", true)
		return
	var res := GameManager.issue_order(_selected_army, target)
	if res.get("ok", false):
		_refresh_order_gfx()
		_show_feedback("已下令 → %s" % target, true)
	else:
		_show_feedback(str(res.get("error", "无法移动")), false)


## 屏幕坐标 → 省份（纯射线拾取，不闪不广播）
func _pick_province(screen_pos: Vector2) -> String:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 2000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return ""
	var collider: Object = result.get("collider", null)
	if collider != null and _collider_to_province.has(collider):
		return _collider_to_province[collider]
	return ""


## 兵牌命中测试：投影兵牌位置到屏幕，点选像素距离 < BANNER_HIT_PIXELS 视为命中；返回最近命中国家 id（""=未命中）
func _hit_banner(screen_pos: Vector2) -> String:
	var best := ""
	var best_d := BANNER_HIT_PIXELS
	for cid in _army_banners:
		var root: Node3D = _army_banners[cid]
		if root == null or not is_instance_valid(root) or not root.visible:
			continue
		var sp := _camera.unproject_position(root.global_position)
		var d := screen_pos.distance_to(sp)
		if d <= best_d:
			best_d = d
			best = cid
	return best


func _select_army(cid: String) -> void:
	_selected_army = cid
	_refresh_selection_gfx()
	_show_feedback("已选中军队", true)


func _deselect_army() -> void:
	_selected_army = ""
	_clear_node(_sel_root)
	_sel_root = null
	_refresh_order_gfx()   # 取消选中不影响待执行命令指示


## 重建选中指示（金色圆环 + 合法移动线，沿邻接线条）
func _refresh_selection_gfx() -> void:
	_clear_node(_sel_root)
	_sel_root = null
	if _selected_army.is_empty():
		return
	_sel_root = Node3D.new()
	_sel_root.name = "ArmySelGfx"
	add_child(_sel_root)
	var from: String = GameManager.army_position.get(_selected_army, "")
	var mi: MeshInstance3D = _province_mesh.get(from, null)
	if mi == null:
		return
	var anchor := _province_anchor(mi)
	var torus := _make_ring(anchor, SEL_RING_RADIUS, Color(1.0, 0.85, 0.3, 0.95))
	if torus:
		_sel_root.add_child(torus)
	# 合法移动线：沿 BFS 可达树边（父省→子省）画细圆柱，即复用邻接图线条
	var tree: Dictionary = GameManager.get_reachable_tree(_selected_army)
	for child in tree:
		var parent: String = tree[child]
		if not _province_mesh.has(child) or not _province_mesh.has(parent):
			continue
		var seg := _make_segment(_province_center(parent), _province_center(child), REACH_LINE_COLOR, REACH_LINE_RADIUS)
		if seg:
			_sel_root.add_child(seg)


## 命令指示：玩家军队有待执行命令时，在目标省画金黄标记 + 沿 BFS 最短路径画路线
func _refresh_order_gfx() -> void:
	_clear_node(_order_root)
	_order_root = null
	var pid := GameManager.player_country_id
	var target: String = GameManager.army_order.get(pid, "")
	var from: String = GameManager.army_position.get(pid, "")
	if target.is_empty() or from.is_empty():
		return
	_order_root = Node3D.new()
	_order_root.name = "ArmyOrderGfx"
	add_child(_order_root)
	if _province_mesh.has(target):
		var ring := _make_ring(_province_center(target), ORDER_MARK_RADIUS, Color(1.0, 0.7, 0.2, 1.0))
		if ring:
			_order_root.add_child(ring)
	var path := GameManager.get_army_path(pid, target)
	for i in path.size() - 1:
		var a: String = path[i]
		var b: String = path[i + 1]
		if not _province_mesh.has(a) or not _province_mesh.has(b):
			continue
		var seg := _make_segment(_province_center(a), _province_center(b), ORDER_LINE_COLOR, REACH_LINE_RADIUS * 1.2)
		if seg:
			_order_root.add_child(seg)


func _province_center(province: String) -> Vector3:
	var mi: MeshInstance3D = _province_mesh.get(province, null)
	if mi == null:
		return Vector3.ZERO
	return _province_anchor(mi)


func _clear_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()


## 细圆柱线段（无光照 + 关闭深度测试，可透过地形/海洋显示），本地 Y 轴对齐 a→b
func _make_segment(a: Vector3, b: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var len := a.distance_to(b)
	if len < 0.01:
		return null
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = len
	mesh.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	var dir := (b - a).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var xa := up.cross(dir).normalized()
	if xa.length() < 0.001:
		xa = Vector3.RIGHT
	var za := xa.cross(dir).normalized()
	mi.transform = Transform3D(Basis(xa, dir, za), (a + b) * 0.5)
	return mi


## 士气条单元（BoxMesh 竖条；billboard FIXED_Y 始终面向相机且保持竖直，像 EU4 血条）
func _make_morale_bar(width: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.no_depth_test = true
	mi.material_override = mat
	return mi


## 士气条颜色（EU4 血条渐变）：满=绿，50%=黄，0%=红，随比例平滑过渡
func _morale_color(ratio: float) -> Color:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r >= 0.5:
		return MORALE_COL_FULL.lerp(MORALE_COL_MID, (1.0 - r) * 2.0)
	return MORALE_COL_MID.lerp(MORALE_COL_LOW, (0.5 - r) * 2.0)


## 平躺地表圆环标记（TorusMesh，XZ 平面）
func _make_ring(at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.75
	mesh.outer_radius = radius
	mesh.rings = 48
	mesh.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = Vector3(at.x, at.y + SEL_RING_LIFT, at.z)
	return mi


## 浮空操作提示：兵牌上方 Label3D，自动淡出
func _show_feedback(text: String, ok: bool) -> void:
	if _feedback == null:
		_feedback = Label3D.new()
		_feedback.name = "ArmyFeedback"
		_feedback.font = load(LABEL_FONT_PATH)
		_feedback.font_size = 40
		_feedback.pixel_size = 0.012
		_feedback.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_feedback.outline_modulate = Color(0.05, 0.04, 0.03)
		_feedback.outline_size = 8
		add_child(_feedback)
	_feedback.visible = true
	_feedback.text = ("✓ " if ok else "✗ ") + text
	_feedback.modulate = Color(0.9, 1.0, 0.75) if ok else Color(1.0, 0.62, 0.55)
	_feedback_timer = FEEDBACK_SECONDS
	var pid := GameManager.player_country_id
	var pos: String = GameManager.army_position.get(pid, "")
	var mi: MeshInstance3D = _province_mesh.get(pos, null)
	if mi:
		var anc := _province_anchor(mi)
		_feedback.global_position = Vector3(anc.x, anc.y + FEEDBACK_LIFT, anc.z)
	else:
		_feedback.global_position = Vector3(MAP_CENTER.x, 3.0, MAP_CENTER.z)


func _update_feedback(delta: float) -> void:
	if _feedback == null or _feedback_timer <= 0.0:
		return
	_feedback_timer -= delta
	if _feedback_timer <= 0.0:
		_hide_feedback()
	else:
		_feedback.modulate.a = clampf(_feedback_timer / FEEDBACK_SECONDS, 0.0, 1.0)


func _hide_feedback() -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.visible = false
	_feedback_timer = 0.0


## 镜头远近：远景（zoom < ICON_SHOW_ZOOM）隐藏要塞/军队图标（及选中/命令指示），避免远景杂乱。
## 每帧统一修正，任何重建/新创建图标都会在下一帧被校正，保证可见性与 zoom 一致。
func _update_icon_visibility() -> void:
	var show := _zoom >= ICON_SHOW_ZOOM
	for prov in _fort_icons:
		_fort_icons[prov].visible = show
	for cid in _army_banners:
		_army_banners[cid].visible = show
	if _sel_root != null and is_instance_valid(_sel_root):
		_sel_root.visible = show
	if _order_root != null and is_instance_valid(_order_root):
		_order_root.visible = show


## ===== 着色 =====

func _apply_colors() -> void:
	_owners = _load_json(MAP_DATA_PATH).get("province_owner", {})
	_country_data = _load_country_data()   # id -> {color, liege}
	_update_liege_map()
	var mats := {}
	_process_node(_map, _owners, _country_data, mats)


func _process_node(node: Node, owners: Dictionary, country_data: Dictionary, mats: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var province := _province_name(child.name)
			# 细分网格：让高度图位移能按顶点表现地形起伏（否则粗网格"铁板一块"）
			if owners.has(province) or child.name == "Britain" or child.name == "Ireland":
				child.mesh = _subdivide_mesh(child.mesh, SUBDIVIDE_MAX_EDGE)
			if owners.has(province):
				# 每省独立材质（才能单独高亮闪烁）
				child.material_override = _make_province_material(country_data.get(owners[province], {}))
				_province_mesh[province] = child
				# 拾取碰撞体（射线命中 → StaticBody3D → 省份）
				child.create_trimesh_collision()
				var body := child.get_child(child.get_child_count() - 1) as StaticBody3D
				if body:
					_collider_to_province[body] = province
			elif child.name == "Britain" or child.name == "Ireland":
				# 陆地基底：地形色，无上抬（省份层覆盖其上）
				child.material_override = _make_land_material()
				child.visible = true
			else:
				child.visible = false   # 退化残留隐藏
		_process_node(child, owners, country_data, mats)


## 中点细分网格：把超长边的三角形切成 4 个（取三边中点），直到所有边 ≤ max_edge。
## 顶点各自按世界坐标采样高度图 → 地形能真实起伏（解决"铁板一块"）。
func _subdivide_mesh(mesh: Mesh, max_edge: float) -> Mesh:
	if not (mesh is ArrayMesh):
		return mesh
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or idx.is_empty():
		return mesh
	var out_verts := PackedVector3Array(verts)
	var mid_cache := {}
	for _iter in 8:
		var out_idx := PackedInt32Array()
		var done := true
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			var ab := out_verts[a].distance_to(out_verts[b])
			var bc := out_verts[b].distance_to(out_verts[c])
			var ca := out_verts[c].distance_to(out_verts[a])
			if ab > max_edge or bc > max_edge or ca > max_edge:
				done = false
				var mab := _edge_mid(out_verts, mid_cache, a, b)
				var mbc := _edge_mid(out_verts, mid_cache, b, c)
				var mca := _edge_mid(out_verts, mid_cache, c, a)
				out_idx.append_array([a, mab, mca])
				out_idx.append_array([b, mbc, mab])
				out_idx.append_array([c, mca, mbc])
				out_idx.append_array([mab, mbc, mca])
			else:
				out_idx.append_array([a, b, c])
		idx = out_idx
		if done:
			break
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in out_verts:
		st.add_vertex(v)
	for ii in idx:
		st.add_index(ii)
	st.generate_normals()
	return st.commit()


static func _edge_mid(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var ia := a
	var ib := b
	if ia > ib:
		ia = b
		ib = a
	var key := str(ia) + "_" + str(ib)
	if cache.has(key):
		return cache[key]
	var m := (verts[a] + verts[b]) * 0.5
	verts.append(m)
	var new_idx := verts.size() - 1
	cache[key] = new_idx
	return new_idx


func _make_province_material(cdata: Dictionary) -> Material:
	if _terrain_shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = cdata.get("color", Color.WHITE)
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = _terrain_shader
	if _heightmap:
		mat.set_shader_parameter("heightmap", _heightmap)
	mat.set_shader_parameter("own_color", cdata.get("color", Color.WHITE))
	mat.set_shader_parameter("far_color", cdata.get("liege_color", cdata.get("color", Color.WHITE)))
	mat.set_shader_parameter("y_offset", 0.06)
	_shader_mats.append(mat)
	return mat


func _make_land_material() -> Material:
	if _terrain_shader == null:
		return StandardMaterial3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = _terrain_shader
	if _heightmap:
		mat.set_shader_parameter("heightmap", _heightmap)
	mat.set_shader_parameter("own_color", LAND_BASE_COLOR)
	mat.set_shader_parameter("far_color", LAND_BASE_COLOR)
	mat.set_shader_parameter("y_offset", 0.0)
	_shader_mats.append(mat)
	return mat


## ===== 省份拾取（射线） =====

func _pick(screen_pos: Vector2) -> void:
	print("map_view: 点击 @ ", screen_pos)
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 2000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		print("map_view: 射线未命中")
		return
	var collider: Object = result.get("collider", null)
	if collider == null or not _collider_to_province.has(collider):
		print("map_view: 命中但非省份碰撞体: ", collider)
		return
	var province: String = _collider_to_province[collider]
	var country: String = _owners.get(province, "")
	province_picked.emit(province, country)
	print("map_view: 拾取 ", province, " -> ", country)
	_flash_province(province)


## ===== 选中省份持续高亮呼吸（EU4 式：2s 周期正弦脉动，不恢复） =====

const BREATH_PERIOD := 2.0    # 呼吸周期（秒）

func _flash_province(province: String) -> void:
	if _flash_name == province:
		return
	_set_flash(_flash_name, 0.0)   # 复位旧选中
	_flash_name = province
	_flash_time = 0.0


func _update_flash(delta: float) -> void:
	if _flash_name.is_empty():
		return
	_flash_time += delta
	# 呼吸感：正弦 2s 周期，highlight 0.35~1.0 持续脉动
	var v := 0.5 + 0.5 * sin(_flash_time / BREATH_PERIOD * TAU)
	v = 0.35 + 0.65 * v
	_set_flash(_flash_name, v)


func _set_flash(province: String, v: float) -> void:
	var mi: MeshInstance3D = _province_mesh.get(province, null)
	if mi == null:
		return
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("highlight", v)


func _province_name(node_name: String) -> String:
	# Godot 给重名节点加数字后缀（The Isles → The Isles2）
	if node_name.begins_with("The Isles"):
		return "The Isles"
	return node_name


func _load_country_data() -> Dictionary:
	# id -> {"color": Color, "liege": String, "liege_color": Color}
	var list: Array = _load_json(COUNTRY_COLORS_PATH).get("countries", [])
	var by_id := {}
	for c in list:
		var id: String = c.get("id", "")
		var hex: String = c.get("color", "")
		by_id[id] = {"color": Color(hex) if not hex.is_empty() else Color.WHITE, "liege": c.get("liege", "")}
	# 递归解析最上级宗主色（附庸套附庸：far_color = 最上级宗主色）
	for id in by_id:
		var top: String = by_id[id]["liege"] as String
		var guard := 0
		while not top.is_empty() and by_id.has(top) and not (by_id[top]["liege"] as String).is_empty() and guard < 16:
			top = by_id[top]["liege"]
			guard += 1
		if not top.is_empty() and by_id.has(top):
			by_id[id]["liege_color"] = by_id[top]["color"]
		else:
			by_id[id]["liege_color"] = by_id[id]["color"]
	return by_id


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			return data
	return {}
