extends Node3D
## 整合场景：MapView（真 3D 地图，不重载）+ 国家选择层 + 游戏内 UI 层。
## 流程：选国（点盾徽或点地图）→ 确认 → 国家选择层淡出、游戏 UI 从右滑入（Tween），
##       地图视角全程保持，无需 change_scene 重载。

const COUNTRIES_PATH := "res://data/countries.json"     # 国家档案主数据源（27 国全量）
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"   # 补充颜色/宗主色
const MAP_DATA_PATH := "res://data/map_data.json"       # 省份→国家映射
const BUILDINGS_PATH := "res://data/buildings.json"     # 建筑表（农场/市场/妓院/要塞 等级→产出）
const SHIELD_DIR := "res://assets/shields/"
const BUILDING_ORDER := ["farm", "market", "brothel", "fort"]   # 省份面板建筑展示顺序
const BUILDING_CN := {"farm": "农场", "market": "市场", "brothel": "妓院", "fort": "要塞"}
const CountryDetailScene := preload("res://scenes/game/country_detail.tscn")   # 详情栏子场景（编辑器里手动对齐）
const UI_SLIDE_SECONDS := 0.6
const UI_FADE_SECONDS := 0.4

const _GOV_CN := {"monarchy": "君主制", "tribal": "部落制", "theocracy": "神权制", "piracy": "海盗制"}
const _CULTURE_CN := {"english": "英格兰文化", "celtic": "凯尔特文化", "norse": "诺斯文化"}
# 附庸类型中文名（countries.json vassal_type；protectorate=受保护国，附庸面板独立一栏）
const VASSAL_TYPE_CN := {
	"feudal": "封臣附庸", "autonomous": "自治藩属", "tributary": "进贡国",
	"protectorate": "受保护国", "prince_bishopric": "采邑主教区",
}
# 省份英文 id → 中文名（依据 plan/历史环境.md；42 省全量）
const _PROVINCE_CN := {
	"Southwest": "英格兰西南", "Wessex": "韦塞克斯", "London": "伦敦",
	"East Anglia": "东盎格利亚", "Home Counties": "家乡郡", "Severn Valley": "塞文河谷",
	"Lincolnshire": "林肯郡", "Midlands": "米德兰", "Lancashire": "兰开夏", "Pale": "英国人界",
	"Northumberland": "诺森伯兰", "Westmorland": "威斯特摩兰", "Yorkshire": "约克郡", "Durham": "达勒姆",
	"Wales": "威尔士", "Isle of Man": "曼岛",
	"Lothian": "洛锡安", "Central": "苏格兰中部", "Aberdeen": "阿伯丁",
	"Highlands": "高地", "Southern Uplands": "南部高地", "Sutherland": "萨瑟兰",
	"The Isles": "群岛领地", "Orkney": "奥克尼", "Shetland": "设得兰",
	"Ulster": "阿尔斯特", "Munster": "芒斯特", "Tyrconnell": "蒂尔康奈尔",
	"Breifne": "布雷夫尼", "Westmeath": "西米斯", "Kildare": "基尔代尔",
	"Tyrone": "蒂龙", "Sligo": "斯莱戈", "Leinster": "莱斯特",
	"Wexford": "韦克斯福德", "Ormond": "奥蒙德", "Clanricarde": "克兰里卡德",
	"Offaly": "奥法利", "Mayo": "梅奥", "Desmond": "德斯蒙德", "Thomond": "托蒙德",
}

# ===== 羊皮纸噪声按钮参数（复用主菜单同款：运行时烘焙斑驳贴图） =====
const _PARCHMENT_BASE := Color(0.86, 0.72, 0.46)      # 羊皮纸暖金基色
const _PARCHMENT_HOVER := Color(0.98, 0.85, 0.6)      # hover 亮金
const _PARCHMENT_STRENGTH := 0.035                     # 斑驳强度（±3.5%）
const _BORDER_COLOR := Color(0.55, 0.38, 0.15)        # 金棕描边
const _BORDER_WIDTH := 4                               # 边框像素
const _SHADOW_RING := 5                                # 外圈软阴影像素
const _TEXTURE_SIZE := 256                             # 噪声贴图边长

@onready var _map_view: Node = $MapView

var _countries: Array = []          # {id, name, color}
var _country_index := {}            # id -> 数组下标（GameManager 用 int）
var _province_owner := {}           # province -> country（map_data.json）
var _province_buildings := {}       # province -> {farm, market, brothel, fort} 等级（初始 lv.1/lv.1/lv.1/lv.0）
var _selected: int = -1             # 当前选中国家下标
var _in_game: bool = false          # 已进入游戏（区分选国阶段 / 游戏内省份点击）
var _active_province: String = ""   # 当前左栏显示的省份（升级后刷新用）
var _player_country_id: String = "" # 玩家所选国家 id（判断省份是否归自己，可升级建筑）

# ---- 国家选择层节点（代码构建）----
var _select_root: Control = null
var _info_title: Label = null
var _info_ruler: Label = null    # 统治者（称号）独立行
var _info_stats: GridContainer = null   # 政体/文化/首都/地位 2×2 资料栏（GridContainer）
var _info_desc: Label = null     # 性格简介（独立标签）
var _confirm: Button = null
var _shield_buttons: Dictionary = {} # id -> TextureButton

# ---- 游戏 UI 层节点（代码构建，占位）----
var _game_root: Control = null
var _top_country: Label = null
var _top_date: Label = null
var _top_gold: Label = null
var _top_prestige: Label = null
var _top_army: Label = null
var _top_shield: TextureRect = null
var _left_slide: Control = null
var _left_open: bool = false
var _active_panel: String = ""
var _left_title: Label = null
var _left_body: Control = null
var _bottom_slide: Control = null
var _bottom_panel: Control = null   # 中央弹窗面板（隐藏时须 IGNORE 穿透，否则挡住地图点击）
var _bottom_open: bool = false
var _active_bottom: String = ""
var _bottom_title: Label = null
var _bottom_body: Control = null


func _ready() -> void:
	_load_countries()
	_build_select_layer()
	_build_game_layer()
	# 点地图选国：province_picked(province, country) → 定位国家并高亮
	_map_view.province_picked.connect(_on_map_province_picked)
	# 国家选择阶段：主旋律 BGM
	AudioManager.play_menu_music()


func _load_countries() -> void:
	# 主数据源 = countries.json（27 国全量档案：统治者/政体/文化/首都/宗附庸/简介/推荐）
	# 颜色从 country_colors.json 合并（地图色 + 宗主映射），id 两文件已对齐（string）。
	var data := _load_json(COUNTRIES_PATH)
	_countries = data.get("countries", [])
	var color_by_id := {}
	for c in _load_json(COUNTRY_COLORS_PATH).get("countries", []):
		color_by_id[c.get("id", "")] = c
	for i in _countries.size():
		var id: String = _countries[i].get("id", "")
		var col: Dictionary = color_by_id.get(id, {})
		_countries[i]["color"] = col.get("color", "#888888")
		_country_index[id] = i
	# 省份→国家映射（游戏内点省份 → 左栏省份详情）
	_province_owner = _load_json(MAP_DATA_PATH).get("province_owner", {})
	_init_province_buildings()


func _build_select_layer() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 关键：根不拦截鼠标 → 地图可点击选国（EU4 式透明浮现，无灰色滤镜）
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	_select_root = root

	var title := Label.new()
	title.text = "公元 1400 年的世界"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	# 做旧暖金 + 金棕描边（贴合金边羊皮纸主题，年代感而非亮金）
	title.add_theme_color_override("font_color", Color(0.85, 0.71, 0.45))
	title.add_theme_color_override("font_outline_color", Color(0.32, 0.2, 0.07))
	title.add_theme_constant_override("outline_size", 6)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 24
	title.offset_bottom = 80
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	# 左侧：盾徽滚动网格（27 国），透明浮在地图上。
	# 用明确 anchor 百分比（避免 LEFT_WIDE+offset 产生负宽度），PASS 穿透让地图可点。
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_right = 0.62
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 40
	scroll.offset_top = 100
	scroll.offset_right = -20
	scroll.offset_bottom = -90
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(scroll)

	# 上下分栏：上=推荐国家，下=所有国家（盾徽不再混排）
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var rec_label := Label.new()
	rec_label.text = "推荐国家"
	rec_label.add_theme_font_size_override("font_size", 22)
	rec_label.add_theme_color_override("font_color", Color(0.85, 0.71, 0.45))
	rec_label.add_theme_color_override("font_outline_color", Color(0.32, 0.2, 0.07))
	rec_label.add_theme_constant_override("outline_size", 4)
	rec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rec_label)

	var rec_grid := GridContainer.new()
	rec_grid.columns = 5
	rec_grid.add_theme_constant_override("h_separation", 14)
	rec_grid.add_theme_constant_override("v_separation", 14)
	rec_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rec_grid)

	var all_label := Label.new()
	all_label.text = "所有国家"
	all_label.add_theme_font_size_override("font_size", 22)
	all_label.add_theme_color_override("font_color", Color(0.85, 0.71, 0.45))
	all_label.add_theme_color_override("font_outline_color", Color(0.32, 0.2, 0.07))
	all_label.add_theme_constant_override("outline_size", 4)
	all_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(all_label)

	var all_grid := GridContainer.new()
	all_grid.columns = 5
	all_grid.add_theme_constant_override("h_separation", 14)
	all_grid.add_theme_constant_override("v_separation", 14)
	all_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(all_grid)

	for c in _countries:
		var id: String = c.get("id", "")
		var rec: bool = c.get("recommended", false)
		_shield_buttons[id] = _make_shield_button(id, rec, rec_grid if rec else all_grid)

	# 右侧：简介面板——独立子场景 country_detail.tscn（布局/背景/按钮全在编辑器里手动对齐）。
	# 这里只实例化 + 接动态文本，尺寸调整不用再改代码。
	var info := CountryDetailScene.instantiate()
	root.add_child(info)
	_info_title = info.get_node("Title")
	_info_ruler = info.get_node("Ruler")
	_info_stats = info.get_node("Stats")
	_info_desc = info.get_node("Desc")
	_confirm = info.get_node("Confirm")
	_confirm.pressed.connect(_on_confirm_pressed)
	_style_detail_confirm()


func _make_shield_button(id: String, recommended: bool, grid: GridContainer) -> TextureButton:
	var path := SHIELD_DIR + id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	# EU4 式：纯盾徽、无文字、无默认灰底、统一尺寸（名字只在右侧详情显示）。
	# 关键：ignore_texture_size=true——否则纹理原始尺寸(256×320)覆盖按钮大小，盾徽超出容器。
	var btn := TextureButton.new()
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.custom_minimum_size = Vector2(88, 110)
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.pressed.connect(_on_shield_pressed.bind(id))
	if recommended:
		# 推荐国：右上角金色 ★ 徽记（EU4 式推荐高亮）
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 20)
		star.modulate = Color(1, 0.85, 0.25)
		star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		star.offset_top = -6
		star.offset_right = 4
		btn.add_child(star)
	grid.add_child(btn)
	return btn


## ===== 详情栏「开始游戏」按钮：金边羊皮纸噪声（与主菜单同款） =====
func _style_detail_confirm() -> void:
	var normal_tex := _make_plaque_texture(_PARCHMENT_BASE, _PARCHMENT_STRENGTH)
	var hover_tex := _make_plaque_texture(_PARCHMENT_HOVER, _PARCHMENT_STRENGTH)
	_confirm.add_theme_stylebox_override("normal", _make_plaque_stylebox(normal_tex))
	_confirm.add_theme_stylebox_override("hover", _make_plaque_stylebox(hover_tex))
	_confirm.add_theme_stylebox_override("pressed", _make_plaque_stylebox(hover_tex))
	var disabled_sb := StyleBoxFlat.new()
	disabled_sb.bg_color = Color(0.8, 0.76, 0.66, 0.85)       # 灰羊皮纸（禁用态）
	disabled_sb.border_width_left = 2
	disabled_sb.border_width_top = 2
	disabled_sb.border_width_right = 2
	disabled_sb.border_width_bottom = 2
	disabled_sb.border_color = Color(0.62, 0.58, 0.48, 0.8)
	disabled_sb.set_corner_radius_all(12)
	_confirm.add_theme_stylebox_override("disabled", disabled_sb)


static func _make_plaque_stylebox(tex: ImageTexture) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := _SHADOW_RING + _BORDER_WIDTH
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.expand_margin_left = _SHADOW_RING
	sb.expand_margin_top = _SHADOW_RING
	sb.expand_margin_right = _SHADOW_RING
	sb.expand_margin_bottom = _SHADOW_RING
	sb.content_margin_left = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 8.0
	return sb


static func _make_plaque_texture(base: Color, strength: float) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.09
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.5
	var img := Image.create(_TEXTURE_SIZE, _TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in _TEXTURE_SIZE:
		for x in _TEXTURE_SIZE:
			img.set_pixel(x, y, _plaque_pixel(base, strength, noise, x, y))
	return ImageTexture.create_from_image(img)


static func _plaque_pixel(base: Color, strength: float, noise: FastNoiseLite, x: int, y: int) -> Color:
	var d := mini(mini(x, _TEXTURE_SIZE - 1 - x), mini(y, _TEXTURE_SIZE - 1 - y))
	if d < _SHADOW_RING:
		# 外圈软阴影：透明 → 半透明深棕
		var t := float(d) / float(_SHADOW_RING)
		return Color(0.25, 0.17, 0.09, 0.0).lerp(Color(0.25, 0.17, 0.09, 0.32), t)
	var dd := d - _SHADOW_RING
	if dd < _BORDER_WIDTH:
		# 金棕边框（外深内浅，微浮雕）
		var t := float(dd) / float(_BORDER_WIDTH)
		return _BORDER_COLOR.lerp(base.darkened(0.18), t)
	# 羊皮纸噪声中心：基色 × (1 ± 强度)，轻微斑驳加深减淡
	var n := noise.get_noise_2d(x, y)
	var f := 1.0 + n * strength
	return Color(base.r * f, base.g * f, base.b * f, 1.0)


func _on_shield_pressed(id: String) -> void:
	_select_country(id)


## 点地图：
## - 选国阶段：province_picked(province, country) → 若为国家则选中
## - 游戏内：滑入左栏省份详情（与经济/宫廷/外交共享同一滑入栏）
func _on_map_province_picked(province: String, country: String) -> void:
	if not _in_game:
		if _country_index.has(country):
			_select_country(country)
		return
	# 游戏内：省份详情走左栏滑入（toggle：同省份再点收起）
	var pid := "province:" + province
	if _left_open and _active_panel == pid:
		_close_left_slide()
		return
	_active_panel = pid
	_left_title.text = "省份 · %s" % _province_cn(province)
	for c in _left_body.get_children():
		c.queue_free()
	_build_province_content(province, country)
	_open_left_slide()


## 省份英文 id → 中文名（缺失时回退英文）
func _province_cn(id: String) -> String:
	return _PROVINCE_CN.get(id, id)


## 省份建筑等级初始化（计划：农场/市场/妓院 lv.1，要塞 lv.0，首都默认 1 级要塞由引擎①细化）
func _init_province_buildings() -> void:
	for province in _province_owner:
		_province_buildings[province] = {"farm": 1, "market": 1, "brothel": 1, "fort": 0}


## 省份详情：所属国家 + 四类建筑等级（农场/市场/妓院/要塞）。
## 仅当省份归属玩家所选国家时才显示升级按钮（别国省份只读）。
func _build_province_content(province: String, country: String) -> void:
	_active_province = province
	var owner_name: String = _country_name(country) if _country_index.has(country) else (country if country else "未知")
	var owner := Label.new()
	owner.text = "所属国家：%s" % owner_name
	owner.add_theme_font_size_override("font_size", 16)
	owner.add_theme_color_override("font_color", INK)
	_left_body.add_child(owner)

	var is_own: bool = country == _player_country_id
	var blds: Dictionary = _province_buildings.get(province, {"farm": 1, "market": 1, "brothel": 1, "fort": 0})
	for b in BUILDING_ORDER:
		var lv: int = blds.get(b, 0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_left_body.add_child(row)

		var lbl := Label.new()
		lbl.text = "%s  Lv.%d" % [BUILDING_CN.get(b, b), lv]
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", INK)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		if is_own:
			var up := Button.new()
			up.text = "升级"
			up.custom_minimum_size = Vector2(64, 32)
			up.add_theme_font_size_override("font_size", 14)
			up.add_theme_color_override("font_color", INK)
			up.add_theme_stylebox_override("normal", _make_panel_stylebox())
			up.add_theme_stylebox_override("hover", _make_panel_stylebox(true))
			up.add_theme_stylebox_override("pressed", _make_panel_stylebox(true))
			up.disabled = lv >= 3   # 建筑上限 lv.3（buildings.json levels 定义）
			up.pressed.connect(_on_upgrade_building.bind(province, b))
			row.add_child(up)


## 升级建筑：等级 +1，刷新省份面板（真实花费/EventBus 引擎①接入）
func _on_upgrade_building(province: String, building: String) -> void:
	# 仅玩家本国省份可升级
	if _province_owner.get(province, "") != _player_country_id:
		return
	var blds: Dictionary = _province_buildings.get(province, {})
	var lv: int = blds.get(building, 0)
	if lv >= 3:
		return
	blds[building] = lv + 1
	# 引擎①接入前：仅本地更新 + 面板刷新（EventBus.building_changed 待信号类型与 province id 对齐后 emit）
	# 刷新当前省份面板
	for c in _left_body.get_children():
		c.queue_free()
	_build_province_content(province, _province_owner.get(province, ""))


func _select_country(id: String) -> void:
	if not _country_index.has(id):
		return
	_selected = _country_index[id]
	var c: Dictionary = _countries[_selected]
	_info_title.text = "1400 年的 %s" % c.get("name", id)
	_info_ruler.text = _format_ruler(c)
	_update_stats(c)
	_info_desc.text = c.get("bio", "")
	_confirm.disabled = false
	# 高亮：复位所有盾徽 → 选中描边（用 modulate 区分）
	for sid in _shield_buttons:
		_shield_buttons[sid].modulate = Color(1, 1, 1, 0.55)
	if _shield_buttons.has(id):
		_shield_buttons[id].modulate = Color.WHITE


## 统治者行：名字（称号），独立 Label（country_detail.tscn 的 Ruler）
func _format_ruler(c: Dictionary) -> String:
	var ruler: String = c.get("ruler", "")
	var title: String = c.get("title", "")
	return "%s（%s）" % [ruler, title] if ruler else ""


## 资料栏：政体 / 文化 / 首都 / 地位 —— 写入 2 列 GridContainer（每行两个，自动对齐）
func _update_stats(c: Dictionary) -> void:
	var gov: String = _GOV_CN.get(c.get("government", ""), c.get("government", ""))
	var culture: String = _CULTURE_CN.get(c.get("culture_group", ""), c.get("culture_group", ""))
	var race: String = c.get("race", "")
	var capital: String = c.get("capital", "—")
	var liege: String = c.get("liege", "")
	var status: String = "独立政权"
	if liege and _country_index.has(liege):
		status = "%s的附庸" % _countries[_country_index[liege]].get("name", liege)
	_info_stats.get_node("Stat1").text = "政体：%s" % gov
	_info_stats.get_node("Stat2").text = "文化：%s（%s）" % [culture, race]
	_info_stats.get_node("Stat3").text = "首都：%s" % capital
	_info_stats.get_node("Stat4").text = "地位：%s" % status


func _on_confirm_pressed() -> void:
	if _selected < 0:
		return
	var id: String = _countries[_selected].get("id", "")
	EventBus.country_selected.emit(_selected)
	EventBus.confirm_country.emit()
	GameManager.start_new_game(_selected)
	AudioManager.play_game_music()
	_transition_to_game(id)


## 淡出国家选择层 + 游戏 UI 从右滑入（地图保持）
func _transition_to_game(id: String) -> void:
	_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_in_game = true   # 此后点省份 → 左栏省份详情，不再走选国
	_player_country_id = id   # 记录玩家国家，仅本国省份可升级建筑
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_select_root, "modulate:a", 0.0, UI_FADE_SECONDS)
	tw.tween_property(_game_root, "position:x", 0.0, UI_SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_select_root.queue_free)
	tw.chain().tween_callback(func() -> void: _left_slide.visible = true)  # root 滑入到位后再显示左栏（避免选国阶段从右侧露出）
	_top_country.text = _country_name(id)
	var shield_path := SHIELD_DIR + id + ".png"
	if ResourceLoader.exists(shield_path):
		_top_shield.texture = load(shield_path)


## ===== 游戏内 UI 层（四栏：顶栏 / 左栏滑入 / 右栏 / 下栏，金边羊皮纸主题）=====

const TOP_BAR_H := 100
const GOLD := Color(0.85, 0.71, 0.45)        # 做旧暖金（标题/强调）
const GOLD_OUTLINE := Color(0.32, 0.2, 0.07)  # 金棕描边
const INK := Color(0.36, 0.26, 0.14)         # 羊皮纸上墨色
const PANEL_BG := Color(0.87, 0.76, 0.54, 0.92)  # 羊皮纸面板底
const UI_ICON_DIR := "res://assets/ui/"
const PORTRAIT_DIR := "res://assets/portraits/"   # 立绘资产库（rulers/<id>.png 384×720、harem/*.png 384×720）
const ICON_ORDER := [
	["economy", "经济"], ["court", "内政"], ["diplomacy", "外交"],
	["vassal", "附庸"], ["mission", "任务"], ["situation", "局势"],
]
const PANEL_CN := {"economy": "经济", "court": "宫廷", "diplomacy": "外交", "vassal": "附庸·宗主", "mission": "任务", "situation": "局势"}
const BOTTOM_ICONS := [
	["org", "国际组织", "盟"], ["diplomacy_game", "外交博弈", "博"], ["war", "战争", "战"],
]
const BOTTOM_CN := {"org": "国际组织", "diplomacy_game": "外交博弈", "war": "战争"}
# 下栏状态图标英文 id → 中文名（tooltip / 弹窗标题）
const STATUS_CN := {
	"diplomacy_play": "外交博弈", "war": "战争",
	"org_pirate_league": "海盗联盟", "org_high_kingdom": "爱尔兰至高王国", "org_union": "联合统治",
}


func _build_game_layer() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 关键：根不拦截鼠标 → 地图可点省份/中键拖拽（选国层同款做法，防游戏内 UI 挡住 3D）
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 初始在屏幕右外，确认后滑入（用实际窗口宽度，防不同分辨率错位）
	root.position.x = get_viewport().get_visible_rect().size.x
	canvas.add_child(root)
	_game_root = root

	_build_top_bar(root)
	_build_left_slide(root)
	_build_right_bar(root)
	_build_bottom_bar(root)
	_build_bottom_slide(root)   # 最后构建 → 模态弹窗层级最高


## ===== 顶栏（两行：左盾徽通高；上栏 国名/月/金币/威望/军队；下栏 六图标）=====
func _build_top_bar(parent: Control) -> void:
	# 顶栏面板（盾徽作为独立节点叠放其上，实现「出边悬垂」效果，不放进容器）
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_BAR_H
	parent.add_child(top)
	top.add_theme_stylebox_override("panel", _make_panel_stylebox())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	top.add_child(hbox)

	# 左侧占位（与盾徽区块同宽，避免国名文字被盾徽压住）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(224, TOP_BAR_H - 8)
	hbox.add_child(spacer)

	# 右区：两行（垂直居中排版）
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	hbox.add_child(right)

	# 上栏：中文国名（暖金标题）+ 月份 + 金币 + 威望 + 军队
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 24)
	right.add_child(row1)
	_top_country = _make_top_label(row1, "—")
	_top_country.add_theme_font_size_override("font_size", 24)
	_top_country.add_theme_color_override("font_color", GOLD)
	_top_country.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	_top_country.add_theme_constant_override("outline_size", 3)
	_top_date = _make_top_label(row1, "1400 年 9 月")
	_top_gold = _make_top_label(row1, "金币 0")
	_top_prestige = _make_top_label(row1, "威望 0")
	_top_army = _make_top_label(row1, "军队 0")

	# 下栏：六个功能图标钮（盾形金边；真实图标素材后续 Gemini 补，先用单字）
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	right.add_child(row2)
	for entry in ICON_ORDER:
		row2.add_child(_make_icon_button(entry[0], entry[1], _on_icon_pressed))

	# 国家盾徽：独立节点绝对定位叠在顶栏之上，尺寸大、下沿超出顶栏底部
	# （出边悬垂美术效果；EXPAND_IGNORE_SIZE 忽略纹理原生 256×320，KEEP_ASPECT 保比例居中）
	_top_shield = TextureRect.new()
	_top_shield.position = Vector2(28, 4)
	_top_shield.size = Vector2(164, 184)
	_top_shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_top_shield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_top_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_top_shield)  # 顶栏之后添加 → 层级盖在顶栏面板之上


## ===== 左栏滑入容器（点击顶栏图标滑入对应子界面；面板内容 #33 起填充）=====
func _build_left_slide(parent: Control) -> void:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	wrap.offset_top = TOP_BAR_H
	wrap.offset_right = 640   # 左栏宽 640（旧 320 的 2 倍）
	wrap.offset_bottom = -64
	wrap.position.x = -660   # 初始在左外，点击图标滑入
	wrap.visible = false      # 选国阶段隐藏：防止 root 在屏幕右外时左栏从右侧露出
	parent.add_child(wrap)
	_left_slide = wrap

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	wrap.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_left_title = Label.new()
	_left_title.add_theme_font_size_override("font_size", 20)
	_left_title.add_theme_color_override("font_color", GOLD)
	_left_title.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	_left_title.add_theme_constant_override("outline_size", 3)
	vbox.add_child(_left_title)

	# 用 VBoxContainer 承载面板内容（Control 不会自动布局子节点，会导致文字叠在一起）
	_left_body = VBoxContainer.new()
	_left_body.add_theme_constant_override("separation", 8)
	_left_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_left_body)


## 顶栏六图标：点击滑出左栏子界面；再次点击同一图标收起（toggle）
func _on_icon_pressed(panel_id: String) -> void:
	if _left_open and _active_panel == panel_id:
		_close_left_slide()
		return
	_active_panel = panel_id
	EventBus.open_panel.emit(panel_id)
	_left_title.text = PANEL_CN[panel_id]
	for c in _left_body.get_children():
		c.queue_free()
	_build_panel_content(panel_id)
	_open_left_slide()


func _open_left_slide() -> void:
	if _left_open:
		return
	_left_open = true
	var tw := create_tween()
	tw.tween_property(_left_slide, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _close_left_slide() -> void:
	if not _left_open:
		return
	_left_open = false
	var tw := create_tween()
	tw.tween_property(_left_slide, "position:x", -660.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## ===== 左栏各子界面占位 UI（#33；数据引擎接入后填真实值）=====
func _build_panel_content(panel_id: String) -> void:
	match panel_id:
		"economy":
			_build_economy_panel()
		"court":
			_build_court_panel()
		"diplomacy":
			_build_diplomacy_panel()
		"vassal":
			_build_vassal_panel()
		"mission":
			_build_mission_panel()
		"situation":
			_build_situation_panel()
		_:
			_left_body.add_child(_panel_label("「%s」面板建设中…" % PANEL_CN.get(panel_id, panel_id)))


## 面板正文 Label（16 号墨色衬线）
func _panel_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", INK)
	return l


## 经济：收入/支出/结余 + 招募 / 贷款（年5%）/ 还贷（#33 占位，引擎①接真实数值）
func _build_economy_panel() -> void:
	_left_body.add_child(_panel_label("收入：—（引擎①接入）"))
	_left_body.add_child(_panel_label("支出：—（引擎①接入）"))
	_left_body.add_child(_panel_label("结余：—（引擎①接入）"))
	_left_body.add_child(_panel_label("军队维护费：每队 100 人 = 0.1 金币/月"))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_left_body.add_child(spacer)
	_build_gold_button(_left_body, "招募一队军队", func() -> void: print("经济: 招募（占位）"))
	_build_gold_button(_left_body, "贷款（10 金币，年利率 5%）", func() -> void: print("经济: 贷款（占位）"))
	_build_gold_button(_left_body, "偿还贷款", func() -> void: print("经济: 还贷（占位）"))


## 宫廷：统治者立绘（固定显示）+ 下方后宫按钮容器（独立可滚动）
## 立绘与按钮容器分开：立绘不滚，按钮区用 ScrollContainer（与外交列表同款结构）滚动（#33 占位；对话 #35）
func _build_court_panel() -> void:
	# 顶部：统治者立绘固定显示（不滚动，显示高 500，资产 720 清晰度足够）
	_left_body.add_child(_panel_label("统治者：%s" % _country_name(_player_country_id)))
	var portrait_path := PORTRAIT_DIR + "rulers/" + _player_country_id + ".png"
	if ResourceLoader.exists(portrait_path):
		var pr := TextureRect.new()
		pr.texture = load(portrait_path)
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.custom_minimum_size = Vector2(384, 600)
		_left_body.add_child(pr)
	else:
		_left_body.add_child(_panel_label("　（立绘缺失）"))

	# 下方：后宫按钮独立容器，固定高 200（非 EXPAND，勿吃满剩余空间）→ 5 按钮内容超出必出滚动条
	_left_body.add_child(_panel_label("后宫（容量 5 / 五役）："))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)   # 固定按钮区高度，内容超出即可滚动
	_left_body.add_child(scroll)
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	btn_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(btn_col)
	for i in 5:
		_build_gold_button(btn_col, "后宫成员 %d（点击对话）" % (i + 1), func() -> void: print("宫廷: 对话成员 ", i + 1, "（占位 #35）"))


## 外交：二级结构——先点国家（列表），再在该国子面板显示 对话/联统/受保护国（#33 占位）
func _build_diplomacy_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(_panel_label("选择国家："))
	for c in _countries:
		var cid: String = c.get("id", "")
		if cid == _player_country_id:
			continue
		# 每行一个「选择」按钮进入该国子面板（未来在此追加该国的外交功能）
		_build_gold_button(list, "◇ %s" % c.get("name", cid), _open_diplomacy_country.bind(cid))


## 进入某国外交子面板：显示该国 对话/联统/受保护国 按钮 + 返回（#33 占位）
## 海盗（塞壬）国家可直接要求附庸他国（通用 CB），故按钮显示为「要求附庸」；其余国家为「要求成为受保护国」
func _open_diplomacy_country(country: String) -> void:
	_left_title.text = "外交 · %s" % _country_name(country)
	for c in _left_body.get_children():
		c.queue_free()
	_left_body.add_child(_panel_label("与「%s」的外交：" % _country_name(country)))
	_build_gold_button(_left_body, "对话", _on_diplomacy_action.bind(country, "chat"))
	_build_gold_button(_left_body, "提议联合统治", _on_diplomacy_action.bind(country, "union"))
	if _country_government(_player_country_id) == "piracy":
		_build_gold_button(_left_body, "要求附庸", _on_diplomacy_action.bind(country, "make_vassal"))
	else:
		_build_gold_button(_left_body, "要求成为受保护国", _on_diplomacy_action.bind(country, "protect"))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_left_body.add_child(spacer)
	_build_gold_button(_left_body, "← 返回国家列表", _back_to_diplomacy_list)


## 返回外交国家列表（恢复左栏标题 + 重建列表）
func _back_to_diplomacy_list() -> void:
	_left_title.text = PANEL_CN["diplomacy"]
	for c in _left_body.get_children():
		c.queue_free()
	_build_diplomacy_panel()


## 外交动作占位（#34 起接真实博弈 / CB）
func _on_diplomacy_action(country: String, action: String) -> void:
	print("外交: ", action, " → ", country, "（占位）")


## 附庸/宗主：直接宗主 + 【直接附庸】与【受保护国】分开展示（#33 占位；vassal_type 区分）
## 嵌套超一层的附庸不显示；受保护国（vassal_type=protectorate）独立一栏，附「要求成为附庸」按钮
func _build_vassal_panel() -> void:
	var my_liege := ""
	for c in _countries:
		if c.get("id", "") == _player_country_id:
			my_liege = c.get("liege", "")
			break
	if my_liege != "" and _country_index.has(my_liege):
		_left_body.add_child(_panel_label("直接宗主：%s" % _country_name(my_liege)))
	else:
		_left_body.add_child(_panel_label("直接宗主：无（独立政权）"))

	# —— 直接附庸（受保护国另列一栏）——
	_left_body.add_child(_panel_label("直接附庸："))
	var vassal_found := false
	for c in _countries:
		if c.get("liege", "") != _player_country_id:
			continue
		if _vassal_type(c.get("id", "")) == "protectorate":
			continue
		vassal_found = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_left_body.add_child(row)
		var name := _panel_label("%s（%s）" % [c.get("name", c.get("id", "")), _vassal_type_cn(c.get("id", ""))])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		_build_gold_button(row, "对话", _on_diplomacy_action.bind(c.get("id", ""), "vassal_chat"))
	if not vassal_found:
		_left_body.add_child(_panel_label("　（无直接附庸）"))

	# —— 受保护国（独立一栏 + 要求成为附庸按钮）——
	_left_body.add_child(_panel_label("受保护国："))
	var prot_found := false
	for c in _countries:
		if c.get("liege", "") != _player_country_id:
			continue
		if _vassal_type(c.get("id", "")) != "protectorate":
			continue
		prot_found = true
		var prows := HBoxContainer.new()
		prows.add_theme_constant_override("separation", 8)
		_left_body.add_child(prows)
		var pname := _panel_label(c.get("name", c.get("id", "")))
		pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prows.add_child(pname)
		_build_gold_button(prows, "对话", _on_diplomacy_action.bind(c.get("id", ""), "vassal_chat"))
		_build_gold_button(prows, "要求成为附庸", _on_diplomacy_action.bind(c.get("id", ""), "make_vassal"))
	if not prot_found:
		_left_body.add_child(_panel_label("　（无受保护国）"))


## 任务：占位（#33；引擎⑦任务树接入）
func _build_mission_panel() -> void:
	_left_body.add_child(_panel_label("任务树建设中…（引擎⑦接入）"))


## 局势：占位（#33；引擎⑥局势进度条接入）
func _build_situation_panel() -> void:
	_left_body.add_child(_panel_label("局势建设中…（引擎⑥接入）"))


## ===== 右栏（Miku 对话 / 过月 / 保存）：无背景悬浮，图标浮在地图上 =====
func _build_right_bar(parent: Control) -> void:
	var right := Control.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = TOP_BAR_H
	right.offset_left = -150
	right.offset_bottom = -64
	parent.add_child(right)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	right.add_child(vbox)

	# 无背景悬浮按钮（透明 + 金色描边文字，与底栏同款，浮在地图上）
	_build_float_right_button(vbox, "与 Miku 对话", func() -> void: _on_chat_pressed())
	_build_float_right_button(vbox, "结束本月", func() -> void: EventBus.end_month.emit())
	_build_float_right_button(vbox, "保存", func() -> void: _on_save_pressed())


## 右栏悬浮钮：有自身羊皮纸按钮边框，但无大块背景，浮在地图右上
func _build_float_right_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_stylebox_override("normal", _make_panel_stylebox())
	b.add_theme_stylebox_override("hover", _make_panel_stylebox(true))
	b.add_theme_stylebox_override("pressed", _make_panel_stylebox(true))
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## ===== 居中模态弹窗（点击下栏图标在屏幕正中央弹出；EU4 同款做法）=====
func _build_bottom_slide(parent: Control) -> void:
	# 全屏容器仅用于定位 + 淡入淡出；IGNORE 穿透让弹窗外仍可点地图
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.modulate.a = 0.0      # 初始隐藏，打开时淡入
	parent.add_child(wrap)
	_bottom_slide = wrap

	# 中央面板：720×460，锚点居中。
	# 关键：隐藏时 panel 必须 IGNORE 穿透——否则即使 modulate.a=0，
	# 中央 720×460 区域仍会拦截鼠标（PanelContainer 默认 STOP），挡住地图点击。
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_top = -230
	panel.offset_right = 360
	panel.offset_bottom = 230
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 默认隐藏：穿透
	wrap.add_child(panel)
	_bottom_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示容器：穿透（内部按钮默认 STOP 仍可点）
	panel.add_child(vbox)

	_bottom_title = Label.new()
	_bottom_title.add_theme_font_size_override("font_size", 20)
	_bottom_title.add_theme_color_override("font_color", GOLD)
	_bottom_title.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	_bottom_title.add_theme_constant_override("outline_size", 3)
	vbox.add_child(_bottom_title)

	_bottom_body = Control.new()
	_bottom_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bottom_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bottom_body)


## ===== 下栏（EU5 式：居中大图标，有状态就显示、无则隐藏）=====
## 业务逻辑：按玩家国家实际状态显示下栏图标（国际组织成员 / 战争 / 博弈 / 联统）
func _bottom_icon_slots() -> Array:
	var slots: Array = []
	var gov := _country_government(_player_country_id)
	if gov == "piracy":
		slots.append("org_pirate_league")   # 塞壬三栖姬（群岛/奥克尼/设得兰）→ 海盗联盟
	elif gov == "tribal":
		slots.append("org_high_kingdom")    # 爱尔兰犬娘诸部（蒂龙等）→ 爱尔兰至高王国
	# 战争 / 外交博弈 / 联合统治：引擎③④⑧接入后按运行态增补
	return slots


func _build_bottom_bar(parent: Control) -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -132
	bar.offset_bottom = 0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 底栏空白区穿透：不挡左栏/地图，仅图标按钮可点
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER   # EU5 式：居中排布大图标
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 容器穿透，内部按钮默认 STOP 仍可点
	bar.add_child(hbox)

	# 业务逻辑：实际有什么状态才显示对应图标
	for s in _bottom_icon_slots():
		hbox.add_child(_make_bottom_status_icon(s, STATUS_CN.get(s, s)))


## 下栏状态大图标：透明无背景，128×128 归一化大图，悬停注明名称。
## modulate 调淡：alpha 0.6（更透明不抢眼）+ RGB 1.35 提亮（更亮）
func _make_bottom_status_icon(icon_id: String, label: String) -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(120, 120)
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	var icon_path := UI_ICON_DIR + icon_id + ".png"
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		b.text = label
	b.modulate = Color(1.35, 1.35, 1.35, 0.6)   # 提亮 + 半透明（不抢眼）
	b.tooltip_text = label
	b.pressed.connect(_on_bottom_icon_pressed.bind(icon_id))
	return b


## 下栏图标：点击滑出底部子菜单；再次点击同一图标收起（toggle）
func _on_bottom_icon_pressed(icon_id: String) -> void:
	if _bottom_open and _active_bottom == icon_id:
		_close_bottom_slide()
		return
	_active_bottom = icon_id
	_bottom_title.text = STATUS_CN.get(icon_id, BOTTOM_CN.get(icon_id, icon_id))
	for c in _bottom_body.get_children():
		c.queue_free()
	_build_bottom_content(icon_id)
	_open_bottom_slide()


func _open_bottom_slide() -> void:
	if _bottom_open:
		return
	_bottom_open = true
	_bottom_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 弹窗打开：接收点击
	var tw := create_tween()
	tw.tween_property(_bottom_slide, "modulate:a", 1.0, 0.18)


func _close_bottom_slide() -> void:
	if not _bottom_open:
		return
	_bottom_open = false
	_bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 弹窗关闭：穿透（不挡地图）
	var tw := create_tween()
	tw.tween_property(_bottom_slide, "modulate:a", 0.0, 0.18)


func _build_bottom_content(icon_id: String) -> void:
	# 国际组织/外交博弈/战争界面内容 #34 起实现；当前占位
	var lbl := Label.new()
	lbl.text = "「%s」界面建设中…" % STATUS_CN.get(icon_id, BOTTOM_CN.get(icon_id, icon_id))
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", INK)
	_bottom_body.add_child(lbl)


## ===== 主题样式 =====
func _make_panel_stylebox(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG.lightened(0.06) if hover else PANEL_BG
	sb.set_corner_radius_all(8)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = GOLD_OUTLINE
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _make_icon_button(panel_id: String, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(56, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", INK)
	# 图标自带金色边框 → 按钮本身完全透明无边框，避免双重边框；图标铺满填满
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	# 真实图标（Gemini 绘制，64×64 透明画布归一化）：用 Button.icon + expand 铺满按钮
	var icon_path := UI_ICON_DIR + icon_name + ".png"
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	# 兜底：图标缺失时显示汉字，避免空白
	else:
		b.text = icon_name
	b.tooltip_text = PANEL_CN.get(panel_id, icon_name)
	b.pressed.connect(cb.bind(panel_id))
	return b


## 无背景图标钮（底栏用）：透明悬空浮在地图上，仅金色描边文字
func _make_float_button(icon_id: String, sym: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = sym
	b.custom_minimum_size = Vector2(48, 36)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	b.add_theme_constant_override("outline_size", 2)
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.pressed.connect(cb.bind(icon_id))
	return b


func _build_gold_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_stylebox_override("normal", _make_panel_stylebox())
	b.add_theme_stylebox_override("hover", _make_panel_stylebox(true))
	b.add_theme_stylebox_override("pressed", _make_panel_stylebox(true))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _make_top_label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", INK)
	parent.add_child(l)
	return l


func _country_name(id: String) -> String:
	var idx: int = _country_index.get(id, -1)
	if idx >= 0:
		return _countries[idx].get("name", id)
	return id


## 附庸类型：countries.json vassal_type（无字段时默认 "feudal" 封臣附庸）
func _vassal_type(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("vassal_type", "feudal"))
	return "feudal"


## 附庸类型中文名
func _vassal_type_cn(cid: String) -> String:
	return VASSAL_TYPE_CN.get(_vassal_type(cid), _vassal_type(cid))


## 政体：countries.json government（"piracy" = 海盗/塞壬，可直接要求附庸他国）
func _country_government(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("government", ""))
	return ""


func _on_chat_pressed() -> void:
	# #35 接入 chat_dialog + LLMClient；当前占位
	print("Chat pressed (placeholder)")


func _on_save_pressed() -> void:
	# 存档待引擎⑨接入；当前占位
	print("Save pressed (placeholder)")


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			return data
	return {}
