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
const LABEL_FONT_PATH := "res://assets/fonts/TimesNewRoman-Bold.ttf"   # V3 古典衬线加粗
const LAND_BASE_COLOR := Color(0.75, 0.72, 0.62)   # 陆地基底中性色
const SUBDIVIDE_MAX_EDGE := 1.0                     # 网格细分最大边长（世界单位），越小地形越细腻

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
var _top_liege_of := {}               # country -> 最上级宗主
var _show_spines := false             # F9：脊线调试可视化开关
var _hmin := Vector2(-15.1, -26.65)   # 高度图采样：左上角世界坐标（可手动微调）
var _hsize := Vector2(29.9, 40.45)    # 高度图采样：覆盖的世界尺寸（可手动微调）
var _height_overlay: MeshInstance3D = null
var _overlay_visible := false         # F10：高度图叠加调试开关


func _ready() -> void:
	_heightmap = load(HEIGHTMAP_PATH)
	_terrain_shader = load(TERRAIN_SHADER_PATH)
	_apply_colors()
	_setup_labels()
	_setup_heightmap_overlay()
	_update_camera()


func _process(delta: float) -> void:
	_handle_wasd(delta)
	_update_shader_uniforms()
	_update_flash(delta)
	_update_labels()


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
				_pick(event.position)
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


func _update_labels() -> void:
	if _labels:
		_labels.set_zoom(_zoom)


## ===== 地图标签（国名/省名，沿脊线弧线） =====

func _setup_labels() -> void:
	_labels = MapLabels.new()
	add_child(_labels)
	_labels.setup(load(LABEL_FONT_PATH) as Font, _heightmap)
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


## ===== 着色 =====

func _apply_colors() -> void:
	_owners = _load_json(MAP_DATA_PATH).get("province_owner", {})
	var country_data := _load_country_data()   # id -> {color, liege}
	var mats := {}
	_process_node(_map, _owners, country_data, mats)


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
		_top_liege_of[id] = top if (not top.is_empty() and by_id.has(top)) else id
	return by_id


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			return data
	return {}
