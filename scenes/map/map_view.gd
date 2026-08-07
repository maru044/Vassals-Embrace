extends Node3D
## 地图场景：加载 map.gltf，按国家着色（远=宗主色/中=本宗色/近=地形），EU4 相机，省份拾取，平↔立体位移。
## 数据：data/map_data.json（省份→国家）、data/country_colors.json（颜色+宗主）、assets/map/height.png（高度图）
## 图层：Britain/Ireland = 陆地基底（地形色）；42 省份 = 覆盖层（国家色 + 微量上抬）。

signal province_picked(province: String, country: String)

const MAP_DATA_PATH := "res://data/map_data.json"
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"
const TERRAIN_SHADER_PATH := "res://shaders/map_terrain.gdshader"
const BORDER_SHADER_PATH := "res://shaders/map_border.gdshader"
const HEIGHTMAP_PATH := "res://assets/map/height.png"
const LAND_BASE_COLOR := Color(0.75, 0.72, 0.62)   # 陆地基底中性色
const BORDER_THICKNESS := 0.06                      # 省界线半宽

# 相机（EU4 式）：俯角随缩放变化，yaw 固定从南看北（南在屏幕下，北退远）
const PITCH_FAR := deg_to_rad(85.0)
const PITCH_NEAR := deg_to_rad(45.0)
const DIST_FAR := 55.0
const DIST_NEAR := 9.0
const MAP_CENTER := Vector3(0.0, 0.0, -6.0)   # 地图中心（x≈0, z≈-6）

@onready var _camera: Camera3D = $Camera3D
@onready var _map: Node3D = $Map

var _zoom := 0.5
var _target := MAP_CENTER
var _owners := {}                     # province -> country
var _collider_to_province := {}       # StaticBody3D -> province
var _heightmap: Texture2D = null
var _terrain_shader: Shader = null
var _border_shader: Shader = null
var _shader_mats: Array = []          # 需每帧更新 zoom/terrain_blend 的材质
var _province_meshes: Array = []      # 省份原始网格（描边用）


func _ready() -> void:
	_heightmap = load(HEIGHTMAP_PATH)
	_terrain_shader = load(TERRAIN_SHADER_PATH)
	_border_shader = load(BORDER_SHADER_PATH)
	_apply_colors()
	_update_camera()


func _process(delta: float) -> void:
	_handle_wasd(delta)
	_update_shader_uniforms()


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
				_zoom = clampf(_zoom + 0.12, 0.0, 1.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - 0.12, 0.0, 1.0)
				_update_camera()
			MOUSE_BUTTON_LEFT:
				_pick(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		# 中键拖拽平移（左键留给拾取）
		_target.x -= event.relative.x * 0.03
		_target.z -= event.relative.y * 0.03
		_update_camera()


func _update_camera() -> void:
	var pitch := lerpf(PITCH_FAR, PITCH_NEAR, _zoom)
	var dist := lerpf(DIST_FAR, DIST_NEAR, _zoom)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * dist
	_camera.global_position = _target + offset
	_camera.look_at(_target, Vector3.UP)


func _update_shader_uniforms() -> void:
	if _shader_mats.is_empty():
		return
	var blend := _zoom   # 远=0 平面 / 近=1 立体（可调 smoothstep）
	var mid := 1.0 - absf(_zoom - 0.5) * 2.0   # 中层最强
	for mat in _shader_mats:
		mat.set_shader_parameter("terrain_blend", blend)
		mat.set_shader_parameter("zoom", _zoom)
		mat.set_shader_parameter("border_intensity", mid * 0.85)


## ===== 着色 =====

func _apply_colors() -> void:
	_owners = _load_json(MAP_DATA_PATH).get("province_owner", {})
	var country_data := _load_country_data()   # id -> {color, liege}
	var mats := {}
	_process_node(_map, _owners, country_data, mats)
	_build_border_mesh()


func _process_node(node: Node, owners: Dictionary, country_data: Dictionary, mats: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var province := _province_name(child.name)
			if owners.has(province):
				var country: String = owners[province]
				if not mats.has(country):
					mats[country] = _make_province_material(country_data.get(country, {}))
				child.material_override = mats[country]
				_province_meshes.append(child.mesh)   # 收集省份网格（描边）
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
	mat.set_shader_parameter("y_offset", 0.02)
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
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 2000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.get("collider", null)
	if collider == null or not _collider_to_province.has(collider):
		return
	var province: String = _collider_to_province[collider]
	var country: String = _owners.get(province, "")
	province_picked.emit(province, country)


func _province_name(node_name: String) -> String:
	# Godot 给重名节点加数字后缀（The Isles → The Isles2）
	if node_name.begins_with("The Isles"):
		return "The Isles"
	return node_name


## ===== 省界（独立边界线网格） =====

func _build_border_mesh() -> void:
	if _border_shader == null or _province_meshes.is_empty():
		return
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for pm in _province_meshes:
		if not (pm is ArrayMesh):
			continue
		var arrays := (pm as ArrayMesh).surface_get_arrays(0)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if pos.is_empty() or idx.size() < 3:
			continue
		for e in _boundary_edges(idx):
			_add_edge_quad(verts, indices, pos[e[0]], pos[e[1]])
	if indices.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _border_shader
	if _heightmap:
		mat.set_shader_parameter("heightmap", _heightmap)
	_shader_mats.append(mat)
	mi.material_override = mat
	_map.add_child(mi)


func _boundary_edges(indices: PackedInt32Array) -> Array:
	# 返回只被一个三角形共享的边（[a, b] 顶点索引对）
	var edges := []
	var edge_count := {}
	var n := indices.size()
	for i in range(0, n, 3):
		for k in 3:
			var a := indices[i + k]
			var b := indices[i + (k + 1) % 3]
			var key: int = mini(a, b) * 100000 + maxi(a, b)
			if not edge_count.has(key):
				edge_count[key] = [a, b, 0]
			edge_count[key][2] += 1
	for key in edge_count:
		if edge_count[key][2] == 1:
			edges.append([edge_count[key][0], edge_count[key][1]])
	return edges


func _add_edge_quad(verts: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3) -> void:
	# 沿边建细长四边形（描边），y 略高于平面，shader 随地形位移
	var dir := (b - a).normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x) * BORDER_THICKNESS
	var h := 0.01
	var v0 := a + perp + Vector3(0, h, 0)
	var v1 := a - perp + Vector3(0, h, 0)
	var v2 := b + perp + Vector3(0, h, 0)
	var v3 := b - perp + Vector3(0, h, 0)
	var base := verts.size()
	verts.append(v0)
	verts.append(v1)
	verts.append(v2)
	verts.append(v3)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base + 3)
	indices.append(base + 2)


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
