extends Node3D
## 整合场景：MapView（真 3D 地图，不重载）+ 国家选择层 + 游戏内 UI 层。
## 流程：选国（点盾徽或点地图）→ 确认 → 国家选择层淡出、游戏 UI 从右滑入（Tween），
##       地图视角全程保持，无需 change_scene 重载。

const COUNTRIES_PATH := "res://data/countries.json"     # 国家档案主数据源（27 国全量）
const COUNTRY_COLORS_PATH := "res://data/country_colors.json"   # 补充颜色/宗主色
const SHIELD_DIR := "res://assets/shields/"
const CountryDetailScene := preload("res://scenes/game/country_detail.tscn")   # 详情栏子场景（编辑器里手动对齐）
const UI_SLIDE_SECONDS := 0.6
const UI_FADE_SECONDS := 0.4

const _GOV_CN := {"monarchy": "君主制", "tribal": "部落制", "theocracy": "神权制", "piracy": "海盗制"}
const _CULTURE_CN := {"english": "英格兰文化", "celtic": "凯尔特文化", "norse": "诺斯文化"}

@onready var _map_view: Node = $MapView

var _countries: Array = []          # {id, name, color}
var _country_index := {}            # id -> 数组下标（GameManager 用 int）
var _selected: int = -1             # 当前选中国家下标

# ---- 国家选择层节点（代码构建）----
var _select_root: Control = null
var _grid: GridContainer = null
var _info_title: Label = null
var _info_desc: Label = null
var _confirm: Button = null
var _shield_buttons: Dictionary = {} # id -> TextureButton

# ---- 游戏 UI 层节点（代码构建，占位）----
var _game_root: Control = null
var _top_country: Label = null
var _top_date: Label = null
var _top_gold: Label = null
var _top_prestige: Label = null
var _top_army: Label = null


func _ready() -> void:
	_load_countries()
	_build_select_layer()
	_build_game_layer()
	# 点地图选国：province_picked(province, country) → 定位国家并高亮
	_map_view.province_picked.connect(_on_map_province_picked)


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
	title.text = "选择你的国家"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
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

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_grid = grid

	for c in _countries:
		var id: String = c.get("id", "")
		_shield_buttons[id] = _make_shield_button(id, c.get("recommended", false))

	# 右侧：简介面板——独立子场景 country_detail.tscn（布局/背景/按钮全在编辑器里手动对齐）。
	# 这里只实例化 + 接动态文本，尺寸调整不用再改代码。
	var info := CountryDetailScene.instantiate()
	root.add_child(info)
	_info_title = info.get_node("Margin/VBox/Title")
	_info_desc = info.get_node("Margin/VBox/Desc")
	_confirm = info.get_node("Margin/VBox/Confirm")
	_confirm.pressed.connect(_on_confirm_pressed)


func _make_shield_button(id: String, recommended: bool) -> TextureButton:
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
	_grid.add_child(btn)
	return btn


func _on_shield_pressed(id: String) -> void:
	_select_country(id)


## 点地图选国：province_picked(province, country) → 若为国家则选中
func _on_map_province_picked(_province: String, country: String) -> void:
	if _country_index.has(country):
		_select_country(country)


func _select_country(id: String) -> void:
	if not _country_index.has(id):
		return
	_selected = _country_index[id]
	var c: Dictionary = _countries[_selected]
	_info_title.text = "1400 年的 %s" % c.get("name", id)
	_info_desc.text = _format_country_profile(c)
	_confirm.disabled = false
	# 高亮：复位所有盾徽 → 选中描边（用 modulate 区分）
	for sid in _shield_buttons:
		_shield_buttons[sid].modulate = Color(1, 1, 1, 0.55)
	if _shield_buttons.has(id):
		_shield_buttons[id].modulate = Color.WHITE


## 详情栏文本：统治者（称号）/ 政体 / 文化种族 / 首都 / 宗附庸地位 / 性格简介
func _format_country_profile(c: Dictionary) -> String:
	var lines: Array[String] = []
	var ruler: String = c.get("ruler", "")
	var title: String = c.get("title", "")
	lines.append("%s（%s）" % [ruler, title] if ruler else "")
	var gov: String = c.get("government", "")
	lines.append("政体：%s" % _GOV_CN.get(gov, gov))
	var culture: String = c.get("culture_group", "")
	lines.append("文化：%s（%s）" % [_CULTURE_CN.get(culture, culture), c.get("race", "")])
	lines.append("首都：%s" % c.get("capital", "—"))
	var liege: String = c.get("liege", "")
	if liege and _country_index.has(liege):
		var liege_name: String = _countries[_country_index[liege]].get("name", liege)
		lines.append("地位：%s的附庸" % liege_name)
	else:
		lines.append("地位：独立政权")
	var bio: String = c.get("bio", "")
	if bio:
		lines.append("")
		lines.append(bio)
	return "\n".join(lines)


func _on_confirm_pressed() -> void:
	if _selected < 0:
		return
	var id: String = _countries[_selected].get("id", "")
	EventBus.country_selected.emit(_selected)
	EventBus.confirm_country.emit()
	GameManager.start_new_game(_selected)
	_transition_to_game(id)


## 淡出国家选择层 + 游戏 UI 从右滑入（地图保持）
func _transition_to_game(id: String) -> void:
	_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_select_root, "modulate:a", 0.0, UI_FADE_SECONDS)
	tw.tween_property(_game_root, "position:x", 0.0, UI_SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_select_root.queue_free)
	_top_country.text = "国家 #%d (%s)" % [GameManager.current_country_id, id]


## ===== 游戏内 UI 层（占位：顶部栏 + 左右栏，后续逐块替换）=====

func _build_game_layer() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 初始在屏幕右外，确认后滑入（用实际窗口宽度，防不同分辨率错位）
	root.position.x = get_viewport().get_visible_rect().size.x
	canvas.add_child(root)
	_game_root = root

	# 顶部栏
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 56
	root.add_child(top)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	top.add_child(hbox)
	_top_country = _make_top_label(hbox, "国家")
	_top_date = _make_top_label(hbox, "1400 年 9 月")
	_top_gold = _make_top_label(hbox, "金币 0")
	_top_prestige = _make_top_label(hbox, "威望 0")
	_top_army = _make_top_label(hbox, "军队 0")

	# 左侧分栏（占位按钮）
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 56
	left.offset_right = 200
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	for text in ["经济", "宫廷", "外交", "附庸", "任务", "局势"]:
		var b := Button.new()
		b.text = text
		lv.add_child(b)

	# 右侧占位
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = 56
	right.offset_left = -220
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var chat := Button.new()
	chat.text = "与 Miku 对话（占位）"
	rv.add_child(chat)
	var end := Button.new()
	end.text = "结束本月（占位）"
	end.pressed.connect(func() -> void: EventBus.end_month.emit())
	rv.add_child(end)


func _make_top_label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)
	return l


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			return data
	return {}
