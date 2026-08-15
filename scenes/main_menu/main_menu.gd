extends Control
## 主界面：开始游戏 / 读取游戏 / 配置 API / 设置 / 制作人员 / 退出。
## 背景图（含标题）由 Gemini 生成；按钮叠在背景左侧按钮框上。

const RESOLUTIONS := [
	Vector2i(3840, 2160),
	Vector2i(2560, 1440),
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
]

const AUTOSAVE_OPTIONS := [
	{"key": "monthly", "label": "每月"},
	{"key": "quarterly", "label": "每季"},
	{"key": "yearly", "label": "每年"},
]

const PRESET_OPTIONS := [
	{"key": "gemini", "label": "Gemini"},
	{"key": "deepseek", "label": "DeepSeek"},
	{"key": "custom", "label": "自定义"},
]

# ===== 羊皮纸噪声按钮参数 =====
const PARCHMENT_BASE := Color(0.86, 0.72, 0.46)    # 羊皮纸暖金基色
const PARCHMENT_HOVER := Color(0.98, 0.85, 0.6)    # hover 亮金
const PARCHMENT_STRENGTH := 0.035                   # 斑驳强度（±3.5%，微弱做旧）
const BORDER_COLOR := Color(0.55, 0.38, 0.15)      # 金棕描边
const BORDER_WIDTH := 4                             # 边框像素（烘焙进贴图）
const SHADOW_RING := 5                              # 外圈软阴影像素（烘焙进贴图）
const TEXTURE_SIZE := 256                           # 噪声贴图边长

@onready var _start_button: Button = $MenuButtons/StartGame
@onready var _load_button: Button = $MenuButtons/LoadGame
@onready var _config_button: Button = $MenuButtons/ConfigAPI
@onready var _quit_button: Button = $MenuButtons/Quit
@onready var _settings_button: Button = $MenuButtons/Settings
@onready var _credits_button: Button = $MenuButtons/Credits

@onready var _config_dialog: PanelContainer = $ConfigDialog
@onready var _preset_option: OptionButton = $ConfigDialog/Margin/VBox/PresetOption
@onready var _api_url_input: LineEdit = $ConfigDialog/Margin/VBox/ApiUrlInput
@onready var _api_key_input: LineEdit = $ConfigDialog/Margin/VBox/ApiKeyInput
@onready var _model_input: LineEdit = $ConfigDialog/Margin/VBox/ModelInput
@onready var _temp_input: LineEdit = $ConfigDialog/Margin/VBox/TempInput
@onready var _top_p_input: LineEdit = $ConfigDialog/Margin/VBox/TopPInput
@onready var _save_button: Button = $ConfigDialog/Margin/VBox/Buttons/Save
@onready var _cancel_button: Button = $ConfigDialog/Margin/VBox/Buttons/Cancel

@onready var _settings_dialog: PanelContainer = $SettingsDialog
@onready var _volume_slider: HSlider = $SettingsDialog/Margin/VBox/VolumeBox/VolumeSlider
@onready var _volume_value: Label = $SettingsDialog/Margin/VBox/VolumeBox/VolumeValue
@onready var _resolution_option: OptionButton = $SettingsDialog/Margin/VBox/ResolutionOption
@onready var _autosave_option: OptionButton = $SettingsDialog/Margin/VBox/AutosaveOption
@onready var _settings_save: Button = $SettingsDialog/Margin/VBox/Buttons/Save
@onready var _settings_cancel: Button = $SettingsDialog/Margin/VBox/Buttons/Cancel

@onready var _credits_dialog: PanelContainer = $CreditsDialog
@onready var _credits_text: RichTextLabel = $CreditsDialog/Margin/VBox/CreditsText
@onready var _credits_close: Button = $CreditsDialog/Margin/VBox/Buttons/Close

var _save_panel: CanvasLayer = null   # 引擎⑨ 存档面板（读档模式）


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_config_button.pressed.connect(_on_config_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_save_button.pressed.connect(_on_save_config_pressed)
	_cancel_button.pressed.connect(_on_cancel_config_pressed)
	_settings_save.pressed.connect(_on_settings_save_pressed)
	_settings_cancel.pressed.connect(_on_settings_cancel_pressed)
	_credits_close.pressed.connect(_on_credits_close_pressed)
	_credits_text.meta_clicked.connect(_on_credits_meta_clicked)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_preset_option.item_selected.connect(_on_preset_selected)
	_fill_preset_options()
	_apply_startup_resolution()
	_apply_parchment_buttons()
	AudioManager.play_menu_music()
	# 引擎⑨ 存档面板：主菜单「读档」入口（load 模式：读取/删除）
	_save_panel = load("res://scenes/game/save_panel.gd").new()
	add_child(_save_panel)
	_save_panel.load_completed.connect(_on_save_load_completed)


func _on_start_pressed() -> void:
	EventBus.start_game.emit()
	# 整合场景：MapView + 国家选择层 + 游戏 UI 层（同场景 Tween 切换，地图不重载）
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_load_pressed() -> void:
	# 引擎⑨：打开存档面板（load 模式），选槽读取 → 恢复状态 → 跳转游戏
	_save_panel.show_panel("load")


## 主菜单读档完成（save_panel.load_completed）：恢复状态已由 save_panel 落地 → 跳转整合游戏场景
func _on_save_load_completed(_data: Dictionary) -> void:
	EventBus.load_game.emit()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_config_pressed() -> void:
	_select_preset_option(ConfigManager.active_api)
	_api_url_input.text = ConfigManager.api_url
	_api_key_input.text = ConfigManager.api_key
	_model_input.text = ConfigManager.model
	_temp_input.text = str(ConfigManager.api_temp)
	_top_p_input.text = str(ConfigManager.api_top_p)
	_config_dialog.visible = true


func _fill_preset_options() -> void:
	_preset_option.clear()
	for i in PRESET_OPTIONS.size():
		_preset_option.add_item(PRESET_OPTIONS[i]["label"])
		_preset_option.set_item_metadata(i, PRESET_OPTIONS[i]["key"])


func _select_preset_option(key: String) -> void:
	for i in _preset_option.item_count:
		if _preset_option.get_item_metadata(i) == key:
			_preset_option.select(i)
			return


## 切换预设：应用参考项目的 URL / 模型 / 温度 / TopP（保留已输入的 API Key）
func _on_preset_selected(index: int) -> void:
	var key: String = _preset_option.get_item_metadata(index)
	ConfigManager.apply_preset(key)
	_api_url_input.text = ConfigManager.api_url
	_model_input.text = ConfigManager.model
	_temp_input.text = str(ConfigManager.api_temp)
	_top_p_input.text = str(ConfigManager.api_top_p)


func _on_save_config_pressed() -> void:
	ConfigManager.api_url = _api_url_input.text.strip_edges()
	ConfigManager.api_key = _api_key_input.text.strip_edges()
	ConfigManager.model = _model_input.text.strip_edges()
	ConfigManager.api_temp = _parse_float(_temp_input.text, 1.0)
	ConfigManager.api_top_p = _parse_float(_top_p_input.text, 0.9)
	ConfigManager.save_config()
	_config_dialog.visible = false


static func _parse_float(text: String, fallback: float) -> float:
	var s := text.strip_edges()
	if s.is_empty():
		return fallback
	return s.to_float()


func _on_cancel_config_pressed() -> void:
	_config_dialog.visible = false


## ===== 设置 =====

func _on_settings_pressed() -> void:
	_fill_resolution_options()
	_fill_autosave_options()
	_volume_slider.value = ConfigManager.volume * 100.0
	_volume_value.text = "%d%%" % int(round(ConfigManager.volume * 100.0))
	_settings_dialog.visible = true


func _fill_resolution_options() -> void:
	# 只列出不超出当前屏幕的分辨率
	var screen := DisplayServer.screen_get_size()
	_resolution_option.clear()
	for res in RESOLUTIONS:
		if res.x <= screen.x and res.y <= screen.y:
			_resolution_option.add_item("%d × %d" % [res.x, res.y])
			_resolution_option.set_item_metadata(_resolution_option.item_count - 1, res)
	var cur := ConfigManager.resolution
	var selected := 0
	for i in _resolution_option.item_count:
		if _resolution_option.get_item_metadata(i) == cur:
			selected = i
			break
	_resolution_option.select(selected)


func _fill_autosave_options() -> void:
	_autosave_option.clear()
	for i in AUTOSAVE_OPTIONS.size():
		_autosave_option.add_item(AUTOSAVE_OPTIONS[i]["label"])
		_autosave_option.set_item_metadata(i, AUTOSAVE_OPTIONS[i]["key"])
	var cur := ConfigManager.autosave_interval
	var selected := 0
	for i in _autosave_option.item_count:
		if _autosave_option.get_item_metadata(i) == cur:
			selected = i
			break
	_autosave_option.select(selected)


func _on_volume_changed(value: float) -> void:
	_volume_value.text = "%d%%" % int(value)


func _on_settings_save_pressed() -> void:
	ConfigManager.volume = _volume_slider.value / 100.0
	var res: Variant = _resolution_option.get_item_metadata(_resolution_option.selected)
	if res is Vector2i:
		ConfigManager.resolution = res
	ConfigManager.autosave_interval = _autosave_option.get_item_metadata(_autosave_option.selected)
	ConfigManager.save_config()
	_apply_resolution()
	AudioManager.apply_volume()
	_settings_dialog.visible = false


func _on_settings_cancel_pressed() -> void:
	_settings_dialog.visible = false


func _apply_resolution() -> void:
	if OS.has_feature("headless"):
		return
	# 钳制到屏幕尺寸内，并强制窗口模式（确保标题栏/关闭按钮存在）
	var screen := DisplayServer.screen_get_size()
	var res := Vector2i(mini(ConfigManager.resolution.x, screen.x), mini(ConfigManager.resolution.y, screen.y))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = res


func _apply_startup_resolution() -> void:
	if OS.has_feature("headless"):
		return
	_apply_resolution()


## ===== 羊皮纸噪声按钮（运行时生成贴图） =====

func _apply_parchment_buttons() -> void:
	var normal_tex := _make_plaque_texture(PARCHMENT_BASE, PARCHMENT_STRENGTH)
	var hover_tex := _make_plaque_texture(PARCHMENT_HOVER, PARCHMENT_STRENGTH)
	var buttons: Array[Button] = [
		_start_button, _load_button, _config_button,
		_settings_button, _credits_button, _quit_button,
		_save_button, _cancel_button,
		_settings_save, _settings_cancel,
		_credits_close,
	]
	for b in buttons:
		b.add_theme_stylebox_override("normal", _make_plaque_stylebox(normal_tex))
		b.add_theme_stylebox_override("hover", _make_plaque_stylebox(hover_tex))
		b.add_theme_stylebox_override("pressed", _make_plaque_stylebox(hover_tex))


static func _make_plaque_stylebox(tex: ImageTexture) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := SHADOW_RING + BORDER_WIDTH
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.expand_margin_left = SHADOW_RING
	sb.expand_margin_top = SHADOW_RING
	sb.expand_margin_right = SHADOW_RING
	sb.expand_margin_bottom = SHADOW_RING
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
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			img.set_pixel(x, y, _plaque_pixel(base, strength, noise, x, y))
	return ImageTexture.create_from_image(img)


static func _plaque_pixel(base: Color, strength: float, noise: FastNoiseLite, x: int, y: int) -> Color:
	var d := mini(mini(x, TEXTURE_SIZE - 1 - x), mini(y, TEXTURE_SIZE - 1 - y))
	if d < SHADOW_RING:
		# 外圈软阴影：透明 → 半透明深棕
		var t := float(d) / float(SHADOW_RING)
		return Color(0.25, 0.17, 0.09, 0.0).lerp(Color(0.25, 0.17, 0.09, 0.32), t)
	var dd := d - SHADOW_RING
	if dd < BORDER_WIDTH:
		# 金棕边框（外深内浅，微浮雕）
		var t := float(dd) / float(BORDER_WIDTH)
		return BORDER_COLOR.lerp(base.darkened(0.18), t)
	# 羊皮纸噪声中心：基色 × (1 ± 强度)，轻微斑驳加深减淡
	var n := noise.get_noise_2d(x, y)
	var f := 1.0 + n * strength
	return Color(base.r * f, base.g * f, base.b * f, 1.0)


## ===== 制作人员 =====

## 制作人员对话框（CreditsDialog 预置于 main_menu.tscn，与设置对话框同款结构/样式）：
## 点击「制作人员」→ 直接显示；关闭/超链接由信号回调处理
func _on_credits_pressed() -> void:
	_credits_dialog.visible = true


func _on_credits_close_pressed() -> void:
	_credits_dialog.visible = false


## 制作人员里的超链接（Archaea Studio 主页）→ 用系统浏览器打开
func _on_credits_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _on_quit_pressed() -> void:
	EventBus.quit_game.emit()
	get_tree().quit()
