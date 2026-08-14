extends Node3D
## 整合场景：MapView（真 3D 地图，不重载）+ 国家选择层 + 游戏内 UI 层。
## 流程：选国（点盾徽或点地图）→ 确认 → 国家选择层淡出、游戏 UI 从右滑入（Tween），
##       地图视角全程保持，无需 change_scene 重载。

const COUNTRIES_PATH := "res://data/countries.json"     # 国家档案主数据源（27 国全量）
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"   # 补充颜色/宗主色
const MAP_DATA_PATH := "res://data/map_data.json"       # 省份→国家映射
const BUILDINGS_PATH := "res://data/buildings.json"     # 建筑表（农场/市场/妓院/要塞 等级→产出）
const MISSIONS_PATH := "res://data/missions.json"       # 任务树（仅玩家生效；数据驱动渲染壳）
const MISSION_NODE_W := 120                             # 任务节点宽
const MISSION_NODE_H := 60                              # 任务节点高
# 各国任务树分组标题（Master 8/14：按国家配置，对齐任务线；无则只显示节点不分组）
const MISSION_GROUPS := {
	"Scotland": [["群岛线", Vector2(25, 50)], ["征服与百年战争线", Vector2(285, 50)]],
	"England": [["内政·繁华", Vector2(25, 50)], ["平叛·战争", Vector2(365, 50)]],
	"Wales": [["独立·武装", Vector2(25, 50)], ["内政·复仇", Vector2(365, 50)]],
}
const SHIELD_DIR := "res://assets/shields/"
const BUILDING_ORDER := ["farm", "market", "brothel", "fort"]   # 省份面板建筑展示顺序
const BUILDING_CN := {"farm": "农场", "market": "市场", "brothel": "妓院", "fort": "要塞"}
# 省份风景图（省→图片文件名，源 参考图/图标 13 张；7 类按地理地貌，详见 refer/prompts/province_landscape.md）
const LANDSCAPE_DIR := "res://assets/province_landscape/"
const _PROVINCE_LANDSCAPE := {
	# —— 爱尔兰：沿海→02(海岸) / 内陆→01(中部平原) ——
	"Ulster": "ireland_02.png", "Tyrconnell": "ireland_02.png", "Sligo": "ireland_02.png",
	"Mayo": "ireland_02.png", "Thomond": "ireland_02.png", "Desmond": "ireland_02.png",
	"Munster": "ireland_02.png", "Wexford": "ireland_02.png", "Ormond": "ireland_02.png",
	"Tyrone": "ireland_01.png", "Breifne": "ireland_01.png", "Westmeath": "ireland_01.png",
	"Offaly": "ireland_01.png", "Clanricarde": "ireland_01.png", "Kildare": "ireland_01.png",
	"Leinster": "ireland_01.png", "Pale": "dublin.png",   # 都柏林（英租界 Pale）
	# —— 英格兰低地：东南田园麦田→01 / 东安格利亚平坦原野→02（伦敦=专属图）——
	"London": "london.png", "Home Counties": "england_lowland_01.png",
	"Wessex": "england_lowland_01.png", "Severn Valley": "england_lowland_01.png",
	"East Anglia": "england_lowland_02.png", "Lincolnshire": "england_lowland_02.png",
	# —— 威尔士 ——
	"Wales": "wales.png",
	# —— 英格兰丘陵：北部·湖区山谷→01 / 米德兰·西南→02（约克=专属图）——
	"Yorkshire": "york.png", "Northumberland": "england_hills_01.png",
	"Durham": "england_hills_01.png", "Westmorland": "england_hills_01.png",
	"Lancashire": "england_hills_01.png",
	"Midlands": "england_hills_02.png", "Southwest": "england_hills_02.png",
	# —— 苏格兰低地（洛锡安=爱丁堡、阿伯丁=专属图）——
	"Lothian": "edinburgh.png", "Southern Uplands": "scotland.png",
	"Central": "scotland.png", "Aberdeen": "aberdeen.png",
	# —— 苏格兰高地：尼斯湖湖湾→01 / 山口山脊→02 ——
	"Highlands": "scotland_highland_01.png", "Sutherland": "scotland_highland_02.png",
	# —— 群岛：赫布里底峡湾→02 / 海蚀悬崖→01 ——
	"The Isles": "isles_02.png", "Orkney": "isles_01.png",
	"Shetland": "isles_01.png", "Isle of Man": "isles_01.png",
}
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
# 初始要塞表（引擎①计划 §二）：7 省初始 LV2；首都默认 +1（读 countries.json capital → _PROVINCE_CN 反查英文省）
const INITIAL_FORTS := {
	"Lothian": 2, "Northumberland": 2, "Yorkshire": 2, "Wales": 2, "Tyrone": 2, "Offaly": 2, "Desmond": 2,
}

# 三文化后宫模板（容量固定 5；role=役名，name=职业名，portrait=harem 资产文件名，不带 .png）
# A 人类宫廷（英格兰/苏格兰 english） / B 凯尔特犬娘（爱尔兰/威尔士 celtic） / C 诺斯塞壬（群岛/奥克尼/设得兰 norse）
# 对应资产：assets/portraits/harem/<portrait>.png + depth/harem/<portrait>_depth.png（已生成，见 refer/img/README.md）
const _HAREM_ROLES := {
	"english": [
		{"role": "武", "name": "重装骑士", "portrait": "A_knight"},
		{"role": "侍", "name": "宫廷女仆", "portrait": "A_maid"},
		{"role": "圣", "name": "修女", "portrait": "A_nun"},
		{"role": "艺", "name": "宫廷舞娘", "portrait": "A_dancer"},
		{"role": "秘", "name": "草药女巫", "portrait": "A_witch"},
	],
	"celtic": [
		{"role": "武", "name": "猎犬武士", "portrait": "B_hound_warrior"},
		{"role": "侍", "name": "犬仆", "portrait": "B_hound_maid"},
		{"role": "圣", "name": "德鲁伊修女", "portrait": "B_druid"},
		{"role": "艺", "name": "火舞娘", "portrait": "B_fire_dancer"},
		{"role": "秘", "name": "凯尔特巫女", "portrait": "B_celtic_witch"},
	],
	"norse": [
		{"role": "武", "name": "盾女", "portrait": "C_shieldmaiden"},
		{"role": "侍", "name": "船舱女仆", "portrait": "C_cabin_maid"},
		{"role": "圣", "name": "祭坛歌姬", "portrait": "C_altar_singer"},
		{"role": "艺", "name": "歌姬", "portrait": "C_singer"},
		{"role": "秘", "name": "符文海巫", "portrait": "C_rune_witch"},
	],
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
var _missions: Array = []           # missions.json 任务树（id/pos/parents/requirements…）
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
var _court_portrait_mat: ShaderMaterial = null   # 宫廷统治者立绘视差材质（无立绘/未启用时为 null）
var _court_parallax_smooth := Vector2.ZERO       # 宫廷统治者立绘视差平滑偏移
var _info_stats: GridContainer = null   # 政体/文化/首都/地位 2×2 资料栏（GridContainer）
var _info_desc: Label = null     # 性格简介（独立标签）
var _confirm: Button = null
var _shield_buttons: Dictionary = {} # id -> TextureButton

# ---- 游戏 UI 层节点（代码构建，占位）----
var _game_root: Control = null
var _top_country: Label = null
var _thinking_overlay: ColorRect = null   # 过月世界 AI 思考全屏遮挡（Master 8/13）
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
var _bottom_notice: Label = null   # 下栏弹窗内占位按钮的反馈文本
var _bottom_hbox: HBoxContainer = null   # 下栏图标容器（选国后重建，因为 _player_country_id 此时才确定）
var _play_notice_msg: String = ""           # 外交博弈面板：动作反馈（站队/退缩/改目标）
var _play_goal_edit: LineEdit = null        # 外交博弈面板：修改我方目标输入框
var _diplo_cb_opt: OptionButton = null      # 外交国家视图：宣战 CB 子菜单（引擎④-CB）
var _diplo_notice_msg: String = ""          # 外交国家视图：发起博弈反馈
var _chat_ui: ChatUI = null   # 全局聊天面板（羊皮纸 + 立绘视差；Miku 无立绘）
# 引擎⑥ 事件面板（居中弹窗）
var _event_layer: CanvasLayer = null
var _event_overlay: ColorRect = null
var _event_image: TextureRect = null
var _event_title: Label = null
var _event_body: Label = null
var _event_opts_box: VBoxContainer = null


func _ready() -> void:
	_load_countries()
	_build_select_layer()
	_build_game_layer()
	# 点地图选国：province_picked(province, country) → 定位国家并高亮
	_map_view.province_picked.connect(_on_map_province_picked)
	# 国家选择阶段：主旋律 BGM
	AudioManager.play_menu_music()
	# 下栏图标动态刷新：引擎状态变化（宣战/博弈/联统/组织成员）时随时重建
	EventBus.war_started.connect(func(_w: int) -> void: _refresh_bottom_bar())
	EventBus.war_ended.connect(func(w: int) -> void:
		_refresh_bottom_bar()
		# 当前打开的战/博弈面板已结束 → 自动关闭（Master 8/13：退缩后图标消失导致无法退出）
		if _bottom_open and _active_bottom == "war_%d" % w:
			_close_bottom_slide())
	EventBus.diplomatic_play_started.connect(func(_p: int) -> void: _refresh_bottom_bar())
	EventBus.diplomatic_play_resolved.connect(func(p: int) -> void:
		_refresh_bottom_bar()
		# 当前打开的博弈面板已结束 → 自动关闭（Master 8/13：退缩后图标消失导致无法退出）
		if _bottom_open and _active_bottom == "play_%d" % p:
			_close_bottom_slide())
	EventBus.union_changed.connect(func(_l: int, _m: int, _a: bool) -> void: _refresh_bottom_bar())
	EventBus.organization_changed.connect(func(_o: int) -> void: _refresh_bottom_bar())
	# 引擎①：过月后顶栏 + 左栏当前面板热更新（金币/威望/好感/经济即时刷新，无需关开面板）
	EventBus.month_advanced.connect(func(_m: int, _y: int) -> void:
		_refresh_top_bar()
		_refresh_left_panel()
		_map_view.apply_ownership(GameManager.province_owner)                       # 引擎③-T4：破城后地图颜色/标签刷新
		_map_view.refresh_forts(GameManager.province_buildings)                     # 引擎③-T4：破城后要塞图标刷新
		_map_view.refresh_army(GameManager.army_position, GameManager.army_count))  # 引擎②-B3-2b：军队移动后兵牌跟随
	# 引擎⑨雏形：对话好感即时变化 → 外交面板即时刷新
	EventBus.favor_changed.connect(func(_t: String, _v: float) -> void: _refresh_left_panel())
	# 引擎⑥-局势（Master 8/14）：局势数值变化 → 左栏当前面板即时刷新（局势进度条实时更新）
	EventBus.situation_changed.connect(func(_sid: String, _v: int) -> void: _refresh_left_panel())
	# 引擎④-CB：要求附庸/受保护国/联合统治关系建立 → 左栏 + 底栏即时刷新
	EventBus.diplomatic_relation_changed.connect(func(_a: String, _t: String, _r: String) -> void:
		_refresh_left_panel()
		_refresh_bottom_bar())
	# 聊天界面（参考 ChatUI 案例：左立绘+深度图视差，右对话区）
	_chat_ui = ChatUI.new()
	add_child(_chat_ui)
	# 引擎⑥ 事件面板（居中弹窗）+ 事件通知
	_build_event_ui()
	EventBus.event_pending.connect(_show_event_panel)
	# 引擎⑦ 任务（Master 8/14）：任务完成 → 若任务面板开着则重建（三态刷新）+ 顶栏金币/威望刷新
	EventBus.mission_completed.connect(func(_mid: String) -> void:
		if _left_open and _active_panel == "mission":
			_refresh_left_panel()
		_refresh_top_bar())
	# 过月世界 AI（LLM）思考 → 全屏遮挡「战略思考中」，思考期间拦截操作（Master 8/13）
	EventBus.world_ai_thinking_started.connect(func() -> void: _set_thinking_overlay(true))
	EventBus.world_ai_thinking_finished.connect(func() -> void: _set_thinking_overlay(false))


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
	_missions = _load_json(MISSIONS_PATH).get("missions", [])
	_init_province_buildings()
	# 引擎①：省份数据注入 GameManager（GDScript 字典按引用共享 → 单一数据源，建筑升级实时反映到结算）
	GameManager.province_owner = _province_owner
	GameManager.province_buildings = _province_buildings
	# 要塞图标不在 _ready 显示（选国界面不显示），进入游戏时再 refresh_forts


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


## 省份建筑等级初始化（引擎②-B3-0）：农场/市场/妓院 lv.1；要塞 = 初始表(7 省 LV2) + 首都 +1
## 规则（源 引擎①计划）：读 countries.json capital（中文）→ _PROVINCE_CN 反查英文省；7 省若是首都则 LV2+1=LV3
func _init_province_buildings() -> void:
	var cn_to_province := {}
	for prov in _PROVINCE_CN:
		cn_to_province[_PROVINCE_CN[prov]] = prov
	cn_to_province["约克"] = "Yorkshire"   # 别名：约克国首都「约克」→ 约克郡省（_PROVINCE_CN 里是「约克郡」）
	for province in _province_owner:
		_province_buildings[province] = {"farm": 1, "market": 1, "brothel": 1, "fort": INITIAL_FORTS.get(province, 0)}
	for c in _countries:
		var cap_prov: String = cn_to_province.get(str(c.get("capital", "")), "")
		if cap_prov != "" and _province_buildings.has(cap_prov):
			_province_buildings[cap_prov]["fort"] += 1


## 各国军队起始位置 = 首都省（引擎②-B3-2；capital 中文 → _PROVINCE_CN 反查英文省）
func _capital_positions() -> Dictionary:
	var cn_to_province := {}
	for prov in _PROVINCE_CN:
		cn_to_province[_PROVINCE_CN[prov]] = prov
	cn_to_province["约克"] = "Yorkshire"
	var pos := {}
	for c in _countries:
		var cap_prov: String = cn_to_province.get(str(c.get("capital", "")), "")
		if cap_prov != "":
			pos[c.get("id", "")] = cap_prov
	return pos


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

		if is_own and b != "fort":   # 要塞不可建造/升级（Master：关闭要塞升级，仅显示等级只读）
			var up_cost := int(GameManager.building_upgrade_cost(b, lv))
			var up := Button.new()
			up.text = "升级(%dg)" % up_cost
			up.custom_minimum_size = Vector2(64, 32)
			up.add_theme_font_size_override("font_size", 14)
			up.add_theme_color_override("font_color", INK)
			up.add_theme_stylebox_override("normal", _make_panel_stylebox())
			up.add_theme_stylebox_override("hover", _make_panel_stylebox(true))
			up.add_theme_stylebox_override("pressed", _make_panel_stylebox(true))
			up.disabled = lv >= 4   # 建筑上限 lv.4（初始 lv.1，可升 3 次；buildings.json levels 定义）
			up.pressed.connect(_on_upgrade_building.bind(province, b))
			row.add_child(up)

	# 省份风景图（测试：爱尔兰 17 省显示 爱尔兰1.png；宽度≈面板内容宽、3:4 等比、底部避让未来边框）
	var ls_path := LANDSCAPE_DIR + str(_PROVINCE_LANDSCAPE.get(province, ""))
	if _PROVINCE_LANDSCAPE.has(province) and ResourceLoader.exists(ls_path):
		var tex: Texture2D = load(ls_path)
		var tw := 600.0   # 接近左栏内容宽（640 - 两侧边框预留）
		var th := tw * float(tex.get_size().y) / float(tex.get_size().x)   # 按纹理比例（3:4）
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(tw, th)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_left_body.add_child(tr)
		var bottom_pad := Control.new()   # 底部避让 16px（VBox 布局；Godot4 无 margin_bottom 属性）
		bottom_pad.custom_minimum_size = Vector2(0, 16)
		_left_body.add_child(bottom_pad)


## 升级建筑：扣款 + 等级+1（引擎①真实逻辑）
func _on_upgrade_building(province: String, building: String) -> void:
	var res: Dictionary = GameManager.upgrade_building(province, building)
	# 刷新当前省份面板（显示新等级/新费用）
	for c in _left_body.get_children():
		c.queue_free()
	_build_province_content(province, _province_owner.get(province, ""))
	if res.get("ok", false):
		_refresh_top_bar()


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
	GameManager.start_new_game(id)   # 引擎①：string 国家 id 初始化运行态数据
	GameManager.capital_province = _capital_positions()      # 引擎③：首都英文省（撤退/投降判定用）
	GameManager.init_army_positions(_capital_positions())   # 引擎②-B3-2：军队起始位置 = 各国首都
	AudioManager.play_game_music()
	_transition_to_game(id)


## 淡出国家选择层 + 游戏 UI 从右滑入（地图保持）
func _transition_to_game(id: String) -> void:
	_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_in_game = true   # 此后点省份 → 左栏省份详情，不再走选国
	_player_country_id = id   # 记录玩家国家，仅本国省份可升级建筑
	_refresh_bottom_bar()     # 玩家确定后重建下栏图标（业务逻辑依赖玩家国家）
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
	_refresh_top_bar()   # 引擎①：进入游戏即显示真实金币/威望/日期/军队
	_map_view.refresh_forts(GameManager.province_buildings)   # 引擎②-B3-2：要塞图标仅游戏内显示（fort≥2）
	_map_view.refresh_army(GameManager.army_position, GameManager.army_count)   # 引擎②-B3-2b：军队兵牌（盾徽+方框+数字k）


## 顶栏接真值（引擎①）：日期 / 金币 / 威望 / 军队 从 GameManager 读取
func _refresh_top_bar() -> void:
	_top_date.text = "%d 年 %d 月" % [GameManager.year, GameManager.month]
	var pid := _player_country_id
	_top_gold.text = "金币 %d" % int(GameManager.country_gold.get(pid, 0.0))
	_top_prestige.text = "威望 %d" % int(GameManager.country_prestige.get(pid, 0.0))
	# 引擎②-B1：军队显示「当前/上限」，上限 = 5 + 2×直辖地块（附庸 -3）
	_top_army.text = "军队 %d/%d" % [GameManager.army_count.get(pid, 0), GameManager.get_army_cap(pid)]


## 过月热更新：左栏当前面板重建（经济/外交等动态数字即时刷新；外交二级子面板过月回到列表）
func _refresh_left_panel() -> void:
	if not _left_open or _active_panel == "":
		return
	_left_title.text = PANEL_CN.get(_active_panel, _active_panel)
	for c in _left_body.get_children():
		c.queue_free()
	_build_panel_content(_active_panel)


## 好感度色阶（玩家对某国）：80-100 绿 / 60-80 黄绿 / 40-60 黄 / 20-40 橙 / 0-20 红
func _favor_color(v: float) -> Color:
	if v >= 80.0:
		return Color(0.20, 0.75, 0.25)
	if v >= 60.0:
		return Color(0.60, 0.80, 0.20)
	if v >= 40.0:
		return Color(0.88, 0.80, 0.15)
	if v >= 20.0:
		return Color(0.92, 0.55, 0.10)
	return Color(0.85, 0.22, 0.22)


## ===== 游戏内 UI 层（四栏：顶栏 / 左栏滑入 / 右栏 / 下栏，金边羊皮纸主题）=====

const TOP_BAR_H := 100
const GOLD := Color(0.85, 0.71, 0.45)        # 做旧暖金（标题/强调）
const GOLD_OUTLINE := Color(0.32, 0.2, 0.07)  # 金棕描边
const INK := Color(0.36, 0.26, 0.14)         # 羊皮纸上墨色
const PANEL_BG := Color(0.87, 0.76, 0.54, 0.92)  # 羊皮纸面板底
const UI_ICON_DIR := "res://assets/ui/"
const SITUATION_BAR_DIR := "res://assets/ui/situation_bars/"
# 局势进度条画框（Master 8/14）：每张画框图统一缩放到宽 600（保持各自原比例），
# 内框（进度轨道）与偏移按局势 id 查表——源图统一 2928 宽，内框参考：
#   百年战争 2192x158 → frame 600x69  track 449x32  off(76,18)
#   统一爱尔兰 2238x151 → frame 600x72  track 459x31  off(71,21)
#   圣女堕落度 2272x163 → frame 600x72  track 466x33  off(67,19)
const SITUATION_BAR_CFG := {
	"hundred_years_war": {"fw": 600, "fh": 69, "tw": 449, "th": 32, "ox": 76, "oy": 18},
	"unify_ireland":     {"fw": 600, "fh": 72, "tw": 459, "th": 31, "ox": 71, "oy": 21},
	# 达勒姆内框偏下（Master 8/14 实测）：加宽 + 下移
	"corruption_durham": {"fw": 600, "fh": 72, "tw": 482, "th": 33, "ox": 59, "oy": 25},
}
const SITUATION_FRAME_W := 600   # 兼容：默认画框宽（未配置局势的兜底宽度）
const PORTRAIT_DIR := "res://assets/portraits/"   # 立绘资产库（rulers/<id>.png 384×720、harem/*.png 384×720）
const PARALLAX_SHADER_PATH := "res://shaders/chat_ui_parallax.gdshader"   # 深度图视差 shader（聊天立绘同款）
const PAPER_TEX_PATH := "res://assets/ui/paper_texture.jpg"   # 纸张材质（Texturelabs 纸面，弱纸纹层用）
const PAPER_SHADER_PATH := "res://shaders/paper_layer.gdshader"   # 纸纹层平铺 shader（屏幕坐标无缝平铺）
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
	# 引擎⑥-主题（Master 8/13）：统一 tooltip 为羊皮纸面板（向子节点传播，替代默认黑底 tooltip）
	_game_root.theme = _make_tooltip_theme()

	_build_top_bar(root)
	_build_left_slide(root)
	_build_right_bar(root)
	_build_bottom_bar(root)
	_build_bottom_slide(root)   # 最后构建 → 模态弹窗层级最高
	_build_thinking_overlay()   # 过月「战略思考中」全屏遮挡（CanvasLayer 200，盖住一切）


## 过月「战略思考中」全屏遮挡（参考 Synthetica MainHUD loading_overlay）：LLM 思考期间拦截所有输入
func _build_thinking_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.05, 0.03, 0.01, 0.82)
	rect.visible = false
	layer.add_child(rect)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.add_child(center)
	var lbl := Label.new()
	lbl.text = "战略思考中…\nMiku 正在裁定各国局势"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	lbl.add_theme_constant_override("outline_size", 4)
	center.add_child(lbl)
	_thinking_overlay = rect


## 显示/隐藏过月思考遮挡
func _set_thinking_overlay(show: bool) -> void:
	if _thinking_overlay != null:
		_thinking_overlay.visible = show


## ===== 顶栏（两行：左盾徽通高；上栏 国名/月/金币/威望/军队；下栏 六图标）=====
func _build_top_bar(parent: Control) -> void:
	# 顶栏面板（盾徽作为独立节点叠放其上，实现「出边悬垂」效果，不放进容器）
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_BAR_H
	parent.add_child(top)
	top.add_theme_stylebox_override("panel", _make_panel_stylebox())
	_apply_paper_layer(top)   # 弱纸纹层（保留纯色主体与金边）

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
	wrap.offset_bottom = -64
	# Master 8/14：LEFT_WIDE 右边缘固定 anchor 0 + offset_right，关闭只改 position 会拉宽 wrap 右边缘留屏。
	# 用 offset_left/offset_right 双控：初始右边缘 -60（连 panel 阴影 5px 一起完全出屏），打开时右边缘回 640。
	wrap.offset_left = -700
	wrap.offset_right = -60
	wrap.visible = false      # 选国阶段隐藏：防止 root 在屏幕右外时左栏从右侧露出
	parent.add_child(wrap)
	_left_slide = wrap

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	wrap.add_child(panel)
	_apply_paper_layer(panel)   # 弱纸纹层（保留纯色主体与金边）

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
	_left_slide.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_left_slide, "offset_left", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_left_slide, "offset_right", 640.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _close_left_slide() -> void:
	if not _left_open:
		return
	_left_open = false
	var tw := create_tween()
	tw.set_parallel(true)
	# Master 8/14：只 tween position 会让 LEFT_WIDE 锚定的右边缘固定留屏；需同时把 offset_right 移到屏外（-60，
	# 连 panel 阴影 5px 一起彻底出屏）。动画结束后 visible=false 兜底确保绝不残留。
	tw.tween_property(_left_slide, "offset_left", -700.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_left_slide, "offset_right", -60.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _left_slide.visible = false)


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


## 经济：收入/支出/结余（引擎①接真值）+ 招募 / 贷款 / 还贷（T4 完善扣款）
func _build_economy_panel() -> void:
	var pid := _player_country_id
	var income: float = GameManager.get_country_income(pid)
	var maint: float = GameManager.ARMY_MAINTENANCE * float(GameManager.army_count.get(pid, 0))
	var interest: float = GameManager.loans.get(pid, 0.0) * GameManager.LOAN_RATE / 12.0
	var spend := maint + interest
	_left_body.add_child(_panel_label("收入：%.1f（基础 5 + 建筑 %.1f）" % [income, income - GameManager.BASE_INCOME]))
	_left_body.add_child(_panel_label("支出：%.1f（军队维护 %.1f + 贷款利息 %.1f）" % [spend, maint, interest]))
	_left_body.add_child(_panel_label("结余：%.1f / 金币 %d" % [income - spend, int(GameManager.country_gold.get(pid, 0.0))]))
	# 引擎②-B2：军队 当前/上限 + 维护/招募费用
	_left_body.add_child(_panel_label("军队：%d/%d（维护 0.1 金/队/月）" % [GameManager.army_count.get(pid, 0), GameManager.get_army_cap(pid)]))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_left_body.add_child(spacer)
	_left_body.add_child(_panel_label("贷款总额：%.0f 金币（年利率 5%%）" % GameManager.loans.get(pid, 0.0)))
	# 招募每月限 1 队：本月已招募 → 按钮灰掉（过月重建面板自动恢复）
	var recruit_btn := _build_gold_button(_left_body, "招募一队军队（20 金·每月限 1 队）", _on_recruit_pressed)
	if GameManager.recruited_this_month.get(pid, false):
		recruit_btn.disabled = true
		recruit_btn.text = "本月已招募（下月再来）"
	_build_gold_button(_left_body, "贷款一笔（+10 金币）", _on_loan_pressed)
	_build_gold_button(_left_body, "偿还一笔贷款（-10 金币）", _on_repay_pressed)


## 招募一队军队（GameManager.recruit_army；成功刷新，失败警告到控制台）
func _on_recruit_pressed() -> void:
	var res: Dictionary = GameManager.recruit_army()
	if not res.get("ok", false):
		push_warning("招募失败: %s" % res.get("error", ""))
	_refresh_left_panel()
	_refresh_top_bar()
	# 招募成功 → 地图兵牌数字立即更新（如 0.2k → 0.3k），无需等过月
	if res.get("ok", false):
		_map_view.refresh_army(GameManager.army_position, GameManager.army_count)


## 贷款一笔（GameManager.take_loan；刷新经济面板 + 顶栏）
func _on_loan_pressed() -> void:
	var res: Dictionary = GameManager.take_loan()
	_refresh_left_panel()
	_refresh_top_bar()


## 偿还一笔贷款（GameManager.repay_loan）
func _on_repay_pressed() -> void:
	var res: Dictionary = GameManager.repay_loan()
	_refresh_left_panel()
	_refresh_top_bar()


## 宫廷：统治者立绘（固定显示）+ 下方后宫按钮容器（独立可滚动）
## 立绘与按钮容器分开：立绘不滚，按钮区用 ScrollContainer（与外交列表同款结构）滚动（#33 占位；对话 #35）
func _build_court_panel() -> void:
	# 顶部：统治者立绘固定显示（不滚动，显示高 500，资产 720 清晰度足够）
	# 标题显示统治者公主名字（ruler）+ 称号，缺失回退国家名
	var ruler_txt := _country_ruler(_player_country_id)
	if ruler_txt == "":
		ruler_txt = _country_name(_player_country_id)
	var ruler_title := _country_title(_player_country_id)
	if ruler_title != "":
		ruler_txt += "（%s）" % ruler_title
	_left_body.add_child(_panel_label("统治者：%s" % ruler_txt))
	_court_portrait_mat = null   # 重建面板时先清除旧视差引用
	var portrait_path := PORTRAIT_DIR + "rulers/" + _player_country_id + ".png"
	if ResourceLoader.exists(portrait_path):
		var pr := TextureRect.new()
		pr.texture = load(portrait_path)
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.custom_minimum_size = Vector2(384, 600)
		# 统治者立绘同样应用深度图视差（与聊天立绘同款 shader + 深度图）
		var depth_path := PORTRAIT_DIR + "depth/rulers/" + _player_country_id + "_depth.png"
		if ResourceLoader.exists(depth_path) and ResourceLoader.exists(PARALLAX_SHADER_PATH):
			var sh := load(PARALLAX_SHADER_PATH) as Shader
			if sh:
				var mat := ShaderMaterial.new()
				mat.shader = sh
				mat.set_shader_parameter("depth_map", load(depth_path))
				mat.set_shader_parameter("depth_strength", 0.05)
				mat.set_shader_parameter("scale", 1.05)
				pr.material = mat
				_court_portrait_mat = mat
				_court_parallax_smooth = Vector2.ZERO
		_left_body.add_child(pr)
	else:
		_left_body.add_child(_panel_label("　（立绘缺失）"))

	# 下方：后宫按钮独立容器，固定高 200（非 EXPAND，勿吃满剩余空间）→ 5 按钮内容超出必出滚动条
	_left_body.add_child(_panel_label("后宫（容量 5）："))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)   # 固定按钮区高度，内容超出即可滚动
	_left_body.add_child(scroll)
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	btn_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(btn_col)
	# 按玩家国家文化组取后宫模板（english/celtic/norse），职业名 + 对应立绘资产文件名
	var roles: Array = _HAREM_ROLES.get(_country_culture_group(_player_country_id), _HAREM_ROLES["english"])
	for r in roles:
		var role: String = r["role"]
		var rname: String = r["name"]
		var portrait: String = r["portrait"]
		_build_gold_button(btn_col, "【%s】%s（点击对话）" % [role, rname], func() -> void:
			if _chat_ui:
				_chat_ui.open_chat("harem", portrait, rname))


## 宫廷统治者立绘视差：随鼠标平滑移动（复用聊天立绘 shader），无立绘材质时零开销
func _process(delta: float) -> void:
	if not _court_portrait_mat:
		return
	var vp := get_viewport().get_visible_rect().size
	var center := vp / 2.0
	var target := (get_viewport().get_mouse_position() - center) / center
	target.x = clampf(target.x, -1.0, 1.0)
	target.y = clampf(target.y, -1.0, 1.0)
	_court_parallax_smooth = _court_parallax_smooth.lerp(target, delta * 5.0)
	_court_portrait_mat.set_shader_parameter("mouse_offset", _court_parallax_smooth)


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
		# 每行：选择按钮 + 好感度（玩家对该国，带色阶）
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var btn := _build_gold_button(row, "◇ %s" % c.get("name", cid), _open_diplomacy_country.bind(cid))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fv: float = GameManager.player_favor.get(cid, 0.0)
		var fl := _panel_label("好感 %d" % int(fv))
		fl.add_theme_color_override("font_color", _favor_color(fv))
		row.add_child(fl)


## 进入某国外交子面板：对话 / 要求X（按文化：诺斯=附庸、英格兰=受保护国、凯尔特=联合统治，好感>80 可用）
## + 宣战（选 CB 子菜单，程序判定可用性）→ 发起博弈（引擎④-CB）
func _open_diplomacy_country(country: String) -> void:
	_left_title.text = "外交 · %s" % _country_name(country)
	for c in _left_body.get_children():
		c.queue_free()
	_left_body.add_child(_panel_label("与「%s」的外交：" % _country_name(country)))
	_build_gold_button(_left_body, "对话", _on_diplomacy_action.bind(country, "chat"))
	# 引擎④-CB：要求附庸/受保护国/联合统治（按玩家文化显示；好感>80 才可用，AI 不受限）
	var pcult := GameManager.country_culture(_player_country_id)
	var req_label := ""
	var req_action := ""
	if pcult == "norse":
		req_label = "要求附庸"
		req_action = "require_vassal"
	elif pcult == "english":
		req_label = "要求成为受保护国"
		req_action = "require_protect"
	elif pcult == "celtic":
		req_label = "提议联合统治"
		req_action = "require_union"
	if req_label != "":
		var req_btn := _build_gold_button(_left_body, req_label, _on_diplomacy_action.bind(country, req_action))
		if not GameManager.can_require_favor(country):
			req_btn.disabled = true
			req_btn.tooltip_text = "好感度需高于 80"
	# 引擎④-CB：宣战 = 选可用 CB（子菜单）→ 发起博弈（2 个月）
	var cbs: Array = GameManager.get_available_cbs(_player_country_id, country)
	if cbs.is_empty():
		_left_body.add_child(_panel_label("对「%s」无可用的战争理由（CB）" % _country_name(country)))
	else:
		var cb_row := HBoxContainer.new()
		cb_row.add_theme_constant_override("separation", 8)
		cb_row.add_child(_panel_label("战争理由："))
		_diplo_cb_opt = OptionButton.new()
		_diplo_cb_opt.custom_minimum_size = Vector2(300, 40)
		for c in cbs:
			_diplo_cb_opt.add_item(str(c.get("name", c.get("id", ""))))
			_diplo_cb_opt.set_item_metadata(_diplo_cb_opt.item_count - 1, str(c.get("id", "")))
		cb_row.add_child(_diplo_cb_opt)
		_left_body.add_child(cb_row)
		_build_gold_button(_left_body, "发起博弈（宣战）", _on_diplo_declare_war.bind(country))
	if not _diplo_notice_msg.is_empty():
		_left_body.add_child(_panel_label(_diplo_notice_msg))
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


## 外交动作（chat/vassal_chat 打开聊天；require_* 打开要求对话 → LLM 同意/拒绝 → 引擎落地）
func _on_diplomacy_action(country: String, action: String) -> void:
	if action == "chat" or action == "vassal_chat":
		if _chat_ui:
			_chat_ui.open_chat("country", country, _country_name(country))
		return
	if action == "require_vassal":
		_open_requirement_chat(country, "vassalize", "要求附庸")
		return
	if action == "require_protect":
		_open_requirement_chat(country, "protectorate", "要求成为受保护国")
		return
	if action == "require_union":
		_open_requirement_chat(country, "personal_union", "提议联合统治")
		return
	print("外交: ", action, " → ", country, "（占位）")


## 打开要求对话（引擎④-CB：LLM 同意→建立关系 / 拒绝→获得 1 年 CB）
func _open_requirement_chat(country: String, cb_id: String, label: String) -> void:
	if _chat_ui:
		_chat_ui.open_chat("country", country, _country_name(country), cb_id, label)


## 发起博弈（宣战）：用选中的 CB 名作为战争目标发起 2 个月博弈（引擎④-CB）
func _on_diplo_declare_war(country: String) -> void:
	if _diplo_cb_opt == null:
		return
	var sel := _diplo_cb_opt.selected
	if sel < 0:
		_diplo_notice_msg = "请选择战争理由（CB）"
		_refresh_diplo_country(country)
		return
	var cb_id: String = str(_diplo_cb_opt.get_item_metadata(sel))
	var cb := GameManager.get_cb(cb_id)
	var goal: String = str(cb.get("name", cb_id))
	# Master 8/14：cb_id 一并传入博弈（退缩落地时按 CB 类型实现对方战争目标）
	var res := GameManager.start_play(_player_country_id, country, goal, cb_id)
	_diplo_notice_msg = "发起博弈：%s" % ("成功" if res.get("ok", false) else str(res.get("error", "失败")))
	_refresh_diplo_country(country)


## 重建外交国家视图（发起博弈动作后刷新）
func _refresh_diplo_country(country: String) -> void:
	_open_diplomacy_country(country)


## 附庸/宗主：直接宗主 + 【直接附庸】与【受保护国】分开展示
## 引擎⑤：运行时附庸关系（要求X同意建立）也计入；受保护国独立一栏，附「要求成为附庸」按钮
func _build_vassal_panel() -> void:
	var my_liege := GameManager.effective_liege(_player_country_id)
	if my_liege != "" and _country_index.has(my_liege):
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		_left_body.add_child(lrow)
		var lname := _panel_label("直接宗主：%s" % _country_name(my_liege))
		lname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(lname)
		_build_gold_button(lrow, "对话", _on_diplomacy_action.bind(my_liege, "chat"))
	else:
		_left_body.add_child(_panel_label("直接宗主：无（独立政权）"))

	# —— 直接附庸（受保护国另列一栏）——
	_left_body.add_child(_panel_label("直接附庸："))
	var vassal_found := false
	for c in _countries:
		var vcid: String = c.get("id", "")
		if GameManager.effective_liege(vcid) != _player_country_id:
			continue
		if GameManager.effective_vassal_type(vcid) == "protectorate":
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
		var pcid: String = c.get("id", "")
		if GameManager.effective_liege(pcid) != _player_country_id:
			continue
		if GameManager.effective_vassal_type(pcid) != "protectorate":
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


## 任务：任务树渲染（引擎⑦ 数据驱动 + 三态染色）。按 missions.json 国家数据通用渲染，各国任务树皆可用。
func _build_mission_panel() -> void:
	var missions := _missions_for_country(_player_country_id)
	if missions.is_empty():
		_left_body.add_child(_panel_label("该国家暂无任务树"))
		return

	# 可滚动画布（纵向/横向均可用滚轮）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_body.add_child(scroll)

	var canvas := MissionTreeCanvas.new()
	canvas.custom_minimum_size = _mission_canvas_size(missions)
	scroll.add_child(canvas)

	# 分组标题（按国家配置，对齐任务线）
	for g in MISSION_GROUPS.get(_player_country_id, []):
		_add_mission_group_label(canvas, str(g[0]), g[1])

	# 连线：父节点中心 → 子节点中心（画在按钮下层）
	var by_id := {}
	for m in missions:
		by_id[m.get("id", "")] = m
	for m in missions:
		var pos: Array = m.get("pos", [0, 0])
		for p in m.get("parents", []):
			var pp: Dictionary = by_id.get(p, {})
			if pp.is_empty():
				continue
			var pp_pos: Array = pp.get("pos", [0, 0])
			canvas.edges.append([float(pp_pos[0]), float(pp_pos[1]), float(pos[0]), float(pos[1])])
	canvas.queue_redraw()

	# 任务节点（可点击，图标先占位 = 任务名文字）
	for m in missions:
		var pos: Array = m.get("pos", [0, 0])
		var b := _build_mission_node(m)
		b.position = Vector2(float(pos[0]) - MISSION_NODE_W / 2.0, float(pos[1]) - MISSION_NODE_H / 2.0)
		canvas.add_child(b)


## 任务树连线画布：在节点之间画连线
class MissionTreeCanvas:
	extends Control
	var edges: Array = []   # [[x1,y1,x2,y2], ...]
	func _draw() -> void:
		for e in edges:
			draw_line(Vector2(e[0], e[1]), Vector2(e[2], e[3]), Color(0.55, 0.38, 0.15, 0.75), 3.0)


## 本国家任务列表
func _missions_for_country(cid: String) -> Array:
	var out: Array = []
	for m in _missions:
		if m.get("country", "") == cid:
			out.append(m)
	return out


## 画布尺寸：按任务坐标 + 底部留白（保证滚轮可滚动）
func _mission_canvas_size(missions: Array) -> Vector2:
	var max_x := 0.0
	var max_y := 0.0
	for m in missions:
		var pos: Array = m.get("pos", [0, 0])
		max_x = maxf(max_x, float(pos[0]))
		max_y = maxf(max_y, float(pos[1]))
	return Vector2(max_x + MISSION_NODE_W / 2.0 + 30.0, max_y + MISSION_NODE_H / 2.0 + 260.0)


## 分组标题 Label
func _add_mission_group_label(canvas: Control, text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	l.add_theme_constant_override("outline_size", 2)
	canvas.add_child(l)


## 任务节点按钮（引擎⑦：三态染色——已完成暗 / 可完成金光 / 锁定灰；点击弹详情）
func _build_mission_node(m: Dictionary) -> Button:
	var b := Button.new()
	var st: String = GameManager.mission_state(str(m.get("id", "")))
	var label := str(m.get("name", m.get("id", "")))
	if st == "completed":
		label = "✓ " + label
	elif st == "available":
		label = "✦ " + label
	else:
		label = "🔒 " + label
	b.text = label
	b.custom_minimum_size = Vector2(MISSION_NODE_W, MISSION_NODE_H)
	b.add_theme_font_size_override("font_size", 13)
	match st:
		"completed":
			b.add_theme_color_override("font_color", Color(0.5, 0.47, 0.4))
			var sb := _make_mission_stylebox(Color(0.62, 0.58, 0.5, 0.85), false)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_stylebox_override("pressed", sb)
		"available":
			b.add_theme_color_override("font_color", INK)
			b.add_theme_stylebox_override("normal", _make_mission_stylebox(Color(0.96, 0.84, 0.55, 0.98), true))
			b.add_theme_stylebox_override("hover", _make_mission_stylebox(Color(1.0, 0.9, 0.66, 1.0), true))
			b.add_theme_stylebox_override("pressed", _make_mission_stylebox(Color(0.9, 0.78, 0.5, 1.0), true))
		_:
			b.add_theme_color_override("font_color", Color(0.5, 0.47, 0.4))
			var sb := _make_mission_stylebox(Color(0.68, 0.63, 0.52, 0.82), false)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_stylebox_override("pressed", sb)
	var tip := str(m.get("desc", ""))
	if st == "completed":
		tip += "\n（已完成）"
	elif st == "available":
		tip += "\n（✦ 可完成，点击领取奖励）"
	else:
		tip += "\n（未满足完成条件）"
	b.tooltip_text = tip
	b.pressed.connect(_open_mission_detail.bind(m))
	return b


## 点击任务节点 → 居中弹详情（名称/描述/条件/奖励 + 关闭）
func _open_mission_detail(m: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.5)
	overlay.add_child(shade)
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			overlay.queue_free())
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -180
	panel.offset_right = 300
	panel.offset_bottom = 180
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = str(m.get("name", "任务"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", GOLD_OUTLINE)
	title.add_theme_constant_override("outline_size", 2)
	vbox.add_child(title)

	vbox.add_child(_mission_detail_line("描述", str(m.get("desc", "—"))))
	vbox.add_child(_mission_detail_line("完成条件", _mission_req_text(m)))
	vbox.add_child(_mission_detail_line("奖励", str(m.get("reward", "—"))))

	# 引擎⑦：可完成任务 → 金光「完成任务」按钮（领奖 + 置完成 + 刷新）
	if GameManager.mission_state(str(m.get("id", ""))) == "available":
		var claim := Button.new()
		claim.text = "✦ 完成任务"
		claim.custom_minimum_size = Vector2(220, 42)
		claim.add_theme_font_size_override("font_size", 17)
		claim.add_theme_color_override("font_color", INK)
		claim.add_theme_stylebox_override("normal", _make_mission_stylebox(Color(0.96, 0.84, 0.55, 0.98), true))
		claim.add_theme_stylebox_override("hover", _make_mission_stylebox(Color(1.0, 0.9, 0.66, 1.0), true))
		claim.add_theme_stylebox_override("pressed", _make_mission_stylebox(Color(0.9, 0.78, 0.5, 1.0), true))
		claim.pressed.connect(func() -> void:
			GameManager.complete_mission(str(m.get("id", "")))
			overlay.queue_free())
		vbox.add_child(claim)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(140, 40)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", INK)
	close.add_theme_stylebox_override("normal", _make_panel_stylebox())
	close.add_theme_stylebox_override("hover", _make_panel_stylebox(true))
	close.add_theme_stylebox_override("pressed", _make_panel_stylebox(true))
	close.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(close)


## 详情行 Label（换行，普通字体）
func _mission_detail_line(name: String, text: String) -> Label:
	var l := Label.new()
	l.text = "%s：%s" % [name, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", INK)
	return l


## 完成条件文本（引擎⑦接入前：直接展示原始条件 JSON）
func _mission_req_text(m: Dictionary) -> String:
	var reqs: Variant = m.get("requirements", {})
	if not reqs is Dictionary:
		return "—"
	var parts: Array = []
	if reqs.has("all"):
		parts.append("全部满足：" + str(reqs["all"]))
	if reqs.has("any"):
		parts.append("任一满足：" + str(reqs["any"]))
	if reqs.has("not"):
		parts.append("不可满足：" + str(reqs["not"]))
	if parts.is_empty():
		return "—"
	return "\n".join(parts)


## 局势：玩家拥有的局势列表（引擎⑥：进度条 + 阶段名 + 0/100 端标签；Master 8/14）
func _build_situation_panel() -> void:
	var list: Array = GameManager.get_player_situations()
	if list.is_empty():
		_left_body.add_child(_panel_label("你当前没有局势。"))
		return
	for s in list:
		var sid: String = str(s.get("id", ""))
		var val: int = GameManager.get_situation_value(sid)
		var stage: int = GameManager.get_situation_stage(sid)
		var stage_names: Array = s.get("stage_names", [])
		var stage_name: String = str(stage_names[stage]) if stage < stage_names.size() else "%s" % (stage + 1)
		_left_body.add_child(_panel_label("◆ %s（%s）" % [str(s.get("name", sid)), stage_name]))
		_left_body.add_child(_situation_bar(sid, val))
		# 局势两端标签：两个 label 左右对齐，宽度与进度条画框一致，贴合两端（Master 8/14）
		var ends := HBoxContainer.new()
		ends.custom_minimum_size = Vector2(_situation_frame_w(sid), 0)
		ends.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ends.add_child(_panel_label(str(s.get("value_0", "0"))))
		var ends_spacer := Control.new()
		ends_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ends.add_child(ends_spacer)
		ends.add_child(_panel_label(str(s.get("value_100", "100"))))
		_left_body.add_child(ends)
		var desc := str(s.get("desc", ""))
		if not desc.is_empty():
			_left_body.add_child(_panel_label("　%s" % desc))


## 局势进度条（0~100）：文艺复兴画框图叠加（situation_bars/<id>.png，Master 8/14 定稿）
## 比例铁律：画框图保持原比例（8.69:1，600×69）一点不变；wrap 高 = 画框全高（69），画框从 (0,0) 开始
## 不向上溢出 → 不盖住上方标题行。填充色与数值在内框区域（偏移 TRACK_OFF，尺寸 TRACK）内。
## 固定尺寸（SHRINK_CENTER，不左右塞满），数值留在进度条内框居中。
## 取局势画框配置（查表；未配置局势用默认 600×69 / 449×32 / off 76,18 兜底）
func _situation_cfg(situation_id: String) -> Dictionary:
	var c: Dictionary = SITUATION_BAR_CFG.get(situation_id, {})
	return {
		"fw": int(c.get("fw", 600)), "fh": int(c.get("fh", 69)),
		"tw": int(c.get("tw", 449)), "th": int(c.get("th", 32)),
		"ox": int(c.get("ox", 76)), "oy": int(c.get("oy", 18)),
	}


func _situation_frame_w(situation_id: String) -> int:
	return int(_situation_cfg(situation_id)["fw"])


func _situation_bar(situation_id: String, value: int) -> Control:
	var cfg := _situation_cfg(situation_id)
	var fw: int = int(cfg["fw"]); var fh: int = int(cfg["fh"])
	var tw: int = int(cfg["tw"]); var th: int = int(cfg["th"])
	var ox: int = int(cfg["ox"]); var oy: int = int(cfg["oy"])
	var pct := clampf(float(value) / 100.0, 0.0, 1.0)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(fw, fh)   # 容纳完整画框，不被拉伸
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# 轨道暗底（未填充区域底色，让渐变填充更突出，web 进度条 track 思维）
	var track := ColorRect.new()
	track.color = Color(0.1, 0.07, 0.04, 0.65)
	track.position = Vector2(ox, oy)
	track.size = Vector2(tw, th)
	wrap.add_child(track)
	# 进度填充（内框区域，按 value 比例）：暖金渐变（深琥珀→亮金→暖白高光），金属锦缎质感，非纯色（Master 8/14）
	var fill := TextureRect.new()
	fill.texture = _situation_fill_texture()
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.position = Vector2(ox, oy)
	fill.size = Vector2(tw * pct, th)
	wrap.add_child(fill)
	# 顶部高光细条（增强立体感，web 渐变思维）
	var gloss := ColorRect.new()
	gloss.color = Color(1.0, 1.0, 1.0, 0.18)
	gloss.position = Vector2(ox, oy)
	gloss.size = Vector2(tw * pct, 3)
	wrap.add_child(gloss)
	# 文艺复兴画框图（宽 600 原比例，从 (0,0) 开始；端帽/边框在 wrap 内完整显示）
	var frame_path := SITUATION_BAR_DIR + "%s.png" % situation_id
	if ResourceLoader.exists(frame_path):
		var frame := TextureRect.new()
		frame.texture = load(frame_path)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE   # 纹理本身已是最终尺寸，直接 1:1
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.position = Vector2.ZERO
		frame.size = Vector2(fw, fh)
		wrap.add_child(frame)
	# 数值 label（内框区域居中，不重叠画框边框）
	var lbl := Label.new()
	lbl.text = "%d / 100" % value
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.75))
	lbl.position = Vector2(ox, oy)
	lbl.size = Vector2(tw, th)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)
	return wrap


## 局势进度填充纹理：暖金水平渐变（深琥珀→亮金→暖白高光），金属锦缎质感，非纯色（Master 8/14）
func _situation_fill_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.55, 0.3, 0.06),      # 深琥珀（左，暗部）
		Color(0.95, 0.75, 0.3),      # 亮金（中）
		Color(1.0, 0.85, 0.45),      # 暖金
		Color(1.0, 0.93, 0.65),      # 暖白高光（右）
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)   # 水平渐变
	tex.width = 128
	tex.height = 64
	return tex


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
	_apply_paper_layer(panel)   # 弱纸纹层（保留纯色主体与金边）
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
## 业务逻辑：每个进行中的外交博弈 / 战争各一个独立图标（互不干扰，Master 8/13）
func _bottom_icon_slots() -> Array:
	var slots: Array = []
	var gov := _country_government(_player_country_id)
	if gov == "piracy":
		slots.append("org_pirate_league")   # 塞壬三栖姬（群岛/奥克尼/设得兰）→ 海盗联盟
	elif gov == "tribal":
		slots.append("org_high_kingdom")    # 爱尔兰犬娘诸部（蒂龙等）→ 爱尔兰至高王国
	# 引擎④：每个进行中的外交博弈一个独立图标
	for p in GameManager.get_active_plays():
		slots.append("play_%d" % int(p.get("id", 0)))
	# 引擎③：每个进行中的战争一个独立图标
	for w in GameManager.wars:
		slots.append("war_%d" % int(w.get("id", 0)))
	return slots


## 下栏图标标签（动态：博弈/战争按实例显示双方；静态走 STATUS_CN）
func _bottom_icon_label(icon_id: String) -> String:
	if icon_id.begins_with("play_"):
		var pid := int(icon_id.trim_prefix("play_"))
		for p in GameManager.get_active_plays():
			if int(p.get("id", 0)) == pid:
				return "博弈#%d：%s vs %s" % [pid, _country_name(str(p.get("initiator", ""))), _country_name(str(p.get("target", "")))]
		return "外交博弈"
	if icon_id.begins_with("war_"):
		var wid := int(icon_id.trim_prefix("war_"))
		for w in GameManager.wars:
			if int(w.get("id", 0)) == wid:
				return "战争#%d：%s vs %s" % [wid, _side_names(w.get("attacker", [])), _side_names(w.get("defender", []))]
		return "战争"
	return STATUS_CN.get(icon_id, BOTTOM_CN.get(icon_id, icon_id))


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
	_bottom_hbox = hbox
	# 此时 _player_country_id 未定（UI 一次性构建），图标由选国后 _refresh_bottom_bar 填充
	_refresh_bottom_bar()


## 重建下栏图标：按玩家国家实际状态显示（选国/状态变化时调用）
func _refresh_bottom_bar() -> void:
	if _bottom_hbox == null:
		return
	for c in _bottom_hbox.get_children():
		c.queue_free()
	for s in _bottom_icon_slots():
		_bottom_hbox.add_child(_make_bottom_status_icon(s, _bottom_icon_label(s)))


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
	# 动态实例（play_<id>/war_<id>）映射到通用静态图（diplomacy_play/war）；org_* 直接同名资源
	var icon_name := icon_id
	if icon_id.begins_with("play_"):
		icon_name = "diplomacy_play"
	elif icon_id.begins_with("war_"):
		icon_name = "war"
	var icon_path := UI_ICON_DIR + icon_name + ".png"
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
	_bottom_title.text = _bottom_icon_label(icon_id)
	for c in _bottom_body.get_children():
		c.queue_free()
	_build_bottom_content(icon_id)
	_open_bottom_slide()


func _open_bottom_slide() -> void:
	if _bottom_open:
		return
	_bottom_open = true
	_bottom_slide.visible = true   # Master 8/14：重新可见（关闭时已 hidden，否则透明控件仍捕获鼠标 I-beam）
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
	# Master 8/14 修复：父面板 IGNORE 不影响子控件(LineEdit 仍 STOP)，透明控件仍参与鼠标命中 →
	# 淡出完成后彻底隐藏，避免鼠标停留在博弈目标输入框位置仍显示文字输入 I-beam
	tw.tween_callback(func() -> void: _bottom_slide.visible = false)


## 下栏弹窗内容：play_<id> / war_<id> 单实例面板（互不干扰）；org_* 组织占位
func _build_bottom_content(icon_id: String) -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_body.add_child(vbox)
	if icon_id.begins_with("play_"):
		_build_single_play_content(vbox, int(icon_id.trim_prefix("play_")))
		return
	if icon_id.begins_with("war_"):
		_build_single_war_content(vbox, int(icon_id.trim_prefix("war_")))
		return
	match icon_id:
		"org_pirate_league":
			_build_org_content(vbox, "海盗联盟", ["群岛领地", "奥克尼", "设得兰"],
				"塞壬三栖姬 · 按功勋分赃的战利品共享（引擎⑧）")
		"org_high_kingdom":
			_build_org_content(vbox, "爱尔兰至高王国", [],
				"犬娘诸部 · 至高王选举 + 凝聚力，联盟之仪 / 淫乱火节提升（引擎⑧）")
		"org_union":
			_build_org_content(vbox, "联合统治", [],
				"多成员共享后宫 · 主导国可变更，关系松散（引擎⑧）")
		_:
			vbox.add_child(_panel_label("「%s」建设中…" % _bottom_icon_label(icon_id)))


## 国际组织通用占位：标题 + 成员列表 + 说明（引擎⑧接入凝聚力/成员/主导国）
func _build_org_content(vbox: VBoxContainer, title: String, members: Array, note: String) -> void:
	vbox.add_child(_panel_label(title))
	for m in members:
		vbox.add_child(_panel_label("· %s" % m))
	if members.is_empty():
		vbox.add_child(_panel_label("　（成员生成中，引擎⑧接入）"))
	vbox.add_child(_panel_label(note))
	vbox.add_child(_panel_label("—— 引擎⑧接入凝聚力 / 成员管理 ——"))


## 按 id 找进行中的博弈（无则 {}）
func _find_play(play_id: int) -> Dictionary:
	for p in GameManager.get_active_plays():
		if int(p.get("id", 0)) == play_id:
			return p
	return {}


## 按 id 找进行中的战争（无则 {}）
func _find_war(war_id: int) -> Dictionary:
	for w in GameManager.wars:
		if int(w.get("id", 0)) == war_id:
			return w
	return {}


## 单个外交博弈面板（引擎④）：该博弈详情 + 站队/退缩/改目标（Master 8/13：一实例一图标，互不干扰）
func _build_single_play_content(vbox: VBoxContainer, play_id: int) -> void:
	var p: Dictionary = _find_play(play_id)
	if p.is_empty():
		vbox.add_child(_panel_label("博弈 #%d 已结束" % play_id))
		return
	vbox.add_child(_panel_label("外交博弈 #%d（单阶段 · 持续 2 个月）" % play_id))
	vbox.add_child(_panel_label("%s(%s) vs %s(%s) · 剩 %d 月" % [
		_country_name(str(p.get("initiator", ""))), str(p.get("init_goal", "")),
		_country_name(str(p.get("target", ""))), str(p.get("targ_goal", "")),
		int(p.get("deadline", 0))]))
	vbox.add_child(_panel_label("站队：%s / %s" % [
		_side_names(p.get("sides", {}).get("A", [])), _side_names(p.get("sides", {}).get("B", []))]))
	var my_side := _my_play_side(p)
	# 战争目标只有「战争盟主」（发起方/防守方 initiator/target）能提；站队/旁观玩家只能选边（Master 8/14）
	var is_principal := str(p.get("initiator", "")) == _player_country_id or str(p.get("target", "")) == _player_country_id
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	if my_side == "":
		_build_gold_button(actions, "加入发起方", _on_join_play.bind(play_id, "A"))
		_build_gold_button(actions, "加入防守方", _on_join_play.bind(play_id, "B"))
	else:
		_build_gold_button(actions, "退缩（失威望）", _on_back_down.bind(play_id, my_side))
		if is_principal:
			_build_gold_button(actions, "修改我方目标", _on_edit_my_goal.bind(play_id))
	vbox.add_child(actions)
	# 修改我方目标输入框（仅博弈方 initiator/target 可见，Master 8/14：非盟主不能提战争目标）
	if is_principal:
		var edit_row := HBoxContainer.new()
		edit_row.add_theme_constant_override("separation", 8)
		edit_row.add_child(_panel_label("修改我方目标："))
		_play_goal_edit = LineEdit.new()
		_play_goal_edit.placeholder_text = "新目标（如：附庸化 / 吞并 洛锡安）"
		_play_goal_edit.custom_minimum_size = Vector2(320, 40)
		edit_row.add_child(_play_goal_edit)
		vbox.add_child(edit_row)
	_bottom_notice = _panel_label(_play_notice_msg)
	vbox.add_child(_bottom_notice)


## 玩家在某博弈中的阵营（"" = 未站队）
func _my_play_side(p: Dictionary) -> String:
	if (p.get("sides", {}).get("A", []) as Array).has(_player_country_id):
		return "A"
	if (p.get("sides", {}).get("B", []) as Array).has(_player_country_id):
		return "B"
	return ""


## 站队成员中文名列表（"、" 连接）
func _side_names(list: Array) -> String:
	var names: Array[String] = []
	for cid in list:
		names.append(_country_name(str(cid)))
	return "、".join(names)


## 该国是否在战争中（引擎④：博弈面板可用性）
func _country_in_war(cid: String) -> bool:
	for w in GameManager.wars:
		if (w.get("attacker", []) as Array).has(cid) or (w.get("defender", []) as Array).has(cid):
			return true
	return false


## 该国是否已在进行中的博弈
func _country_in_play(cid: String) -> bool:
	for p in GameManager.get_active_plays():
		if str(p.get("initiator", "")) == cid or str(p.get("target", "")) == cid:
			return true
		if (p.get("sides", {}).get("A", []) as Array).has(cid) or (p.get("sides", {}).get("B", []) as Array).has(cid):
			return true
	return false


## 站队
func _on_join_play(play_id: int, side: String) -> void:
	var res := GameManager.join_play(play_id, _player_country_id, side)
	var msg: String = "成功" if res.get("ok", false) else str(res.get("error", "失败"))
	_play_notice_msg = "站队：%s" % msg
	_refresh_diplomacy_panel()


## 退缩
func _on_back_down(play_id: int, side: String) -> void:
	var res := GameManager.back_down(play_id, side)
	var msg: String = "成功" if res.get("ok", false) else str(res.get("error", "失败"))
	_play_notice_msg = "退缩：%s" % msg
	_refresh_diplomacy_panel()


## 修改我方目标（发起方/防守方；用共享目标输入框填写新目标）
func _on_edit_my_goal(play_id: int) -> void:
	if _play_goal_edit == null:
		return
	var goal: String = _play_goal_edit.text.strip_edges()
	if goal.is_empty():
		_play_notice_msg = "请先在上方目标框填写新目标"
		_refresh_diplomacy_panel()
		return
	var res := GameManager.set_play_goal(play_id, _player_country_id, goal)
	var msg: String = "成功" if res.get("ok", false) else str(res.get("error", "失败"))
	_play_notice_msg = "修改目标：%s" % msg
	_refresh_diplomacy_panel()


## 重建当前外交博弈面板（动作后刷新；_play_notice_msg 回填到新 notice）
func _refresh_diplomacy_panel() -> void:
	if not _bottom_open or not str(_active_bottom).begins_with("play_"):
		return
	for c in _bottom_body.get_children():
		c.queue_free()
	_build_bottom_content(_active_bottom)


## 单个战争面板（引擎③④，Master 8/13：一战争一图标互不干扰）：双方 + 议和聊天入口
func _build_single_war_content(vbox: VBoxContainer, war_id: int) -> void:
	var w: Dictionary = _find_war(war_id)
	if w.is_empty():
		vbox.add_child(_panel_label("战争 #%d 已结束" % war_id))
		return
	vbox.add_child(_panel_label("战争 #%d（Battle Fuck）" % war_id))
	vbox.add_child(_panel_label("A方（进攻）：%s" % _side_names(w.get("attacker", []))))
	vbox.add_child(_panel_label("B方（防守）：%s" % _side_names(w.get("defender", []))))
	vbox.add_child(_panel_label("议和规则：攻破对方首都 → 无条件投降；其余 → 与敌国公主聊天提条件，同意即和平"))
	_build_gold_button(vbox, "与敌国公主议和", _on_peace_treaty_pressed.bind(war_id))
	_bottom_notice = _panel_label("")
	vbox.add_child(_bottom_notice)


## 议和：提示从外交面板找对方公主聊天（LLM 谈条件，同意即和平）
func _on_peace_treaty_pressed(war_id: int = 0) -> void:
	if _bottom_notice:
		var w := _find_war(war_id)
		if w.is_empty():
			_bottom_notice.text = "当前无战争可议和（有战争时从外交面板找对方公主聊天提条件）"
		else:
			_bottom_notice.text = "战争 #%d：请从左栏外交面板点对方公主「对话」议和（LLM 谈条件）" % war_id


## ===== 主题样式 =====
## 面板弱纸纹层：纯色 StyleBoxFlat 主体（羊皮纸底+金边+圆角+阴影）保留原样，
## 叠加 TextureRect + 纸纹 shader（屏幕坐标固定像素密度无缝平铺、只压暗纹路保持底色），内缩避开边框圆角。
func _apply_paper_layer(panel: PanelContainer) -> void:
	if not ResourceLoader.exists(PAPER_TEX_PATH) or not ResourceLoader.exists(PAPER_SHADER_PATH):
		return
	var bg := TextureRect.new()
	bg.texture = load(PAPER_TEX_PATH)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(PAPER_SHADER_PATH)
	mat.set_shader_parameter("tile_px", 320.0)      # 纸纹固定像素密度（不随面板长宽比）
	mat.set_shader_parameter("strength", 0.25)      # 纸纹强度（材质强弱）
	bg.material = mat
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 10; bg.offset_top = 10; bg.offset_right = -10; bg.offset_bottom = -10   # 避开金边/圆角
	panel.add_child(bg)
	panel.move_child(bg, 0)   # 置于内容之下、stylebox 之上


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


## 任务节点三态样式（引擎⑦）：glow=金光（可完成）/ 否则灰暗（已完成或锁定）
func _make_mission_stylebox(bg: Color, glow: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.85, 0.71, 0.45) if glow else Color(0.55, 0.45, 0.28, 0.8)
	if glow:
		sb.shadow_color = Color(0.95, 0.8, 0.45, 0.55)
		sb.shadow_size = 8
	else:
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## 统一主题 tooltip（Master 8/13）：把 Godot 默认黑底 tooltip → 羊皮纸面板 + 墨色字
## 作用域：全局 fallback_theme → 左栏图标（经济等）、底栏国际组织、任务、要求X 等所有 tooltip_text 统一
func _make_tooltip_theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("panel", "TooltipPanel", _make_panel_stylebox())
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 15)
	return t


## 主题 label（墨色字 + 自动换行，用于羊皮纸面板上；替代默认黑底 Label）
func _make_themed_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ===== 引擎⑥ 事件面板（居中弹窗：左图容错 + 金色按钮 + EU4 悬停 tooltip + 主题 label）=====

## 构建事件面板（CanvasLayer 遮罩 + 居中羊皮纸面板）
func _build_event_ui() -> void:
	_event_layer = CanvasLayer.new()
	_event_layer.layer = 150
	add_child(_event_layer)
	_event_overlay = ColorRect.new()
	_event_overlay.color = Color(0, 0, 0, 0.55)
	_event_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_event_layer.add_child(_event_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_event_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	panel.custom_minimum_size = Vector2(780, 500)
	center.add_child(panel)
	panel.theme = _make_tooltip_theme()   # 事件面板选项 tooltip 同样羊皮纸化
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 14)
	panel.add_child(root_v)
	# 左图 + 右内容
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	root_v.add_child(top)
	_event_image = TextureRect.new()
	_event_image.custom_minimum_size = Vector2(250, 300)
	_event_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_event_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_event_image)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	_event_title = _make_themed_label("")
	_event_title.add_theme_font_size_override("font_size", 26)
	right.add_child(_event_title)
	_event_body = _make_themed_label("")
	_event_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_event_body)
	# 选项（金色羊皮纸按钮）
	_event_opts_box = VBoxContainer.new()
	_event_opts_box.add_theme_constant_override("separation", 8)
	root_v.add_child(_event_opts_box)
	_event_layer.visible = false


## 事件通知 → 渲染队首事件（无则忽略）
func _show_event_panel() -> void:
	if GameManager.peek_player_event().is_empty():
		return
	_render_event_panel()


## 渲染当前事件（标题/正文/左图容错/选项金色按钮 + EU4 effects tooltip）
func _render_event_panel() -> void:
	var ev: Dictionary = GameManager.peek_player_event()
	if ev.is_empty():
		return
	var e: Dictionary = GameManager.get_event(str(ev.get("event_id", "")))
	var root: String = str(ev.get("root", ""))
	var from: String = str(ev.get("from", ""))
	for c in _event_opts_box.get_children():
		c.queue_free()
	_event_title.text = str(e.get("name", "事件"))
	_event_body.text = GameManager.resolve_event_vars(str(e.get("text", "")), root, from)
	# 左图容错：res://assets/events/<id>.png 存在才显示，否则不显示（不报错）
	var img := "res://assets/events/%s.png" % str(ev.get("event_id", ""))
	if ResourceLoader.exists(img):
		_event_image.texture = load(img)
		_event_image.visible = true
	else:
		_event_image.visible = false
	var opts: Array = e.get("options", [])
	# 阵营局势（如百年战争 England/Scotland 都拥有、两边期望相反）：按当前玩家国家识别「我方阵营」，
	# 给我方有利选项加〔我方〕前缀，让玩家一眼看清该推哪边（Master 8/14；AI 无局势，纯玩家 UI 识别）
	var my_side: String = ""
	var ev_sides: Dictionary = e.get("sides", {})
	if ev_sides.has(GameManager.player_country_id):
		my_side = str(ev_sides[GameManager.player_country_id])
	for i in opts.size():
		var o: Dictionary = opts[i]
		var label: String = str(o.get("text", "…"))
		if my_side != "" and str(o.get("side", "")) == my_side:
			label = "〔我方〕" + label
		var b := _build_gold_button(_event_opts_box, label, _on_event_option.bind(i))
		b.tooltip_text = _event_effects_text(o.get("effects", {}))
	_event_layer.visible = true


## 选项点击：落地 effects → 立即刷新顶栏/左栏/地图兵牌 → 有下个事件继续显示，否则关闭
func _on_event_option(idx: int) -> void:
	GameManager.resolve_player_event(idx)
	# 即时反馈（Master 8/13）：金币/威望/军队/好感落地后马上刷新 HUD，不等过月
	_refresh_left_panel()
	_refresh_top_bar()
	_map_view.refresh_army(GameManager.army_position, GameManager.army_count)   # 事件加军队 → 地图兵牌数字即时更新
	if GameManager.peek_player_event().is_empty():
		_event_layer.visible = false
	else:
		_render_event_panel()


## 效果字典 → 可读文本（EU4 式 tooltip 内容）
func _event_effects_text(fx: Dictionary) -> String:
	if fx.is_empty():
		return "（无特殊效果）"
	var lines: Array[String] = []
	if fx.has("gold"):
		lines.append("金币 %+d" % int(fx["gold"]))
	if fx.has("prestige"):
		lines.append("威望 %+d" % int(fx["prestige"]))
	if fx.has("army"):
		lines.append("军队 +%d" % int(fx["army"]))
	if fx.has("favor"):
		var fv: Dictionary = fx["favor"]
		lines.append("%s 好感 %+d" % [_country_name(str(fv.get("target", ""))), int(fv.get("delta", 0))])
	if fx.has("start_play"):
		lines.append("发起外交博弈：%s" % str(fx["start_play"].get("goal", "")))
	for m in fx.get("modifiers", []):
		var mt: String = {"army_cap": "最大军队上限", "morale": "士气", "income": "月收入"}.get(str(m.get("type", "")), str(m.get("type", "")))
		var mts: String = str(m.get("target", ""))
		var who: String = ("%s " % _country_name(mts)) if mts != "" else ""
		lines.append("%s%s %+d%% × %d月" % [who, mt, int(roundf(float(m.get("value", 0.0)) * 100.0)), int(m.get("months", 1))])
	return "\n".join(lines)


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


## 附庸类型：运行时（要求X同意建立的附庸类型优先）；无则静态 countries.json（默认 "feudal"）
func _vassal_type(cid: String) -> String:
	return GameManager.effective_vassal_type(cid)


## 附庸类型中文名
func _vassal_type_cn(cid: String) -> String:
	return VASSAL_TYPE_CN.get(_vassal_type(cid), _vassal_type(cid))


## 政体：countries.json government（"piracy" = 海盗/塞壬，可直接要求附庸他国）
func _country_government(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("government", ""))
	return ""


## 统治者姓名：countries.json ruler（中文名，如内芙·奥尼尔）
func _country_ruler(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("ruler", ""))
	return ""


## 统治者称号：countries.json title（如公主/犬姬）
func _country_title(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("title", ""))
	return ""


## 文化组：countries.json culture_group（english/celtic/norse，决定后宫模板）
func _country_culture_group(cid: String) -> String:
	var idx: int = _country_index.get(cid, -1)
	if idx >= 0:
		return str(_countries[idx].get("culture_group", "english"))
	return "english"


func _on_chat_pressed() -> void:
	if _chat_ui:
		_chat_ui.open_chat("miku", "", "Miku")


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
