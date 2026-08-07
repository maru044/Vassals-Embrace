extends Node3D
## 地图场景：加载 map.gltf，按国家着色，EU4 式相机控制，省份拾取。
## 数据依赖：data/map_data.json（省份→国家）、data/country_colors.json（国家颜色）
## 阶段A：只显示 42 省份色块（隐藏 Britain/Ireland 陆地基底与退化层），Phase B 接地形 shader。
## 拾取：Phase A 用射线（平面地图可靠）；地形位移后若不准再换颜色拾取。

signal province_picked(province: String, country: String)

const MAP_DATA_PATH := "res://data/map_data.json"
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"

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


func _ready() -> void:
	_apply_colors()
	_update_camera()


func _process(delta: float) -> void:
	_handle_wasd(delta)


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


## ===== 国家着色 =====

func _apply_colors() -> void:
	_owners = _load_json(MAP_DATA_PATH).get("province_owner", {})
	var colors := _load_country_colors()
	var mats := {}
	_process_node(_map, _owners, colors, mats)


func _process_node(node: Node, owners: Dictionary, colors: Dictionary, mats: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var province := _province_name(child.name)
			if owners.has(province):
				var country: String = owners[province]
				if not mats.has(country):
					mats[country] = _make_country_material(colors.get(country, Color.WHITE))
				child.material_override = mats[country]
				# 拾取碰撞体（射线命中 → StaticBody3D → 省份）
				child.create_trimesh_collision()   # Godot4 返回 void，自动加 StaticBody3D 子节点
				var body := child.get_child(child.get_child_count() - 1) as StaticBody3D
				if body:
					_collider_to_province[body] = province
			else:
				# 非省份网格（Britain/Ireland 陆地基底、退化残留）阶段A先隐藏
				child.visible = false
		_process_node(child, owners, colors, mats)


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


func _make_country_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _province_name(node_name: String) -> String:
	# Godot 给重名节点加数字后缀（The Isles → The Isles2）
	if node_name.begins_with("The Isles"):
		return "The Isles"
	return node_name


func _load_country_colors() -> Dictionary:
	var list: Array = _load_json(COUNTRY_COLORS_PATH).get("countries", [])
	var colors := {}
	for c in list:
		var hex: String = c.get("color", "")
		if not hex.is_empty():
			colors[c["id"]] = Color(hex)
	return colors


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			return data
	return {}
