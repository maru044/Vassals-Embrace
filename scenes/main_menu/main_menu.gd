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

@onready var _start_button: Button = $MenuButtons/StartGame
@onready var _load_button: Button = $MenuButtons/LoadGame
@onready var _config_button: Button = $MenuButtons/ConfigAPI
@onready var _quit_button: Button = $MenuButtons/Quit
@onready var _settings_button: Button = $MenuButtons/Settings
@onready var _credits_button: Button = $MenuButtons/Credits

@onready var _config_dialog: PanelContainer = $ConfigDialog
@onready var _api_url_input: LineEdit = $ConfigDialog/Margin/VBox/ApiUrlInput
@onready var _api_key_input: LineEdit = $ConfigDialog/Margin/VBox/ApiKeyInput
@onready var _model_input: LineEdit = $ConfigDialog/Margin/VBox/ModelInput
@onready var _save_button: Button = $ConfigDialog/Margin/VBox/Buttons/Save
@onready var _cancel_button: Button = $ConfigDialog/Margin/VBox/Buttons/Cancel

@onready var _settings_dialog: PanelContainer = $SettingsDialog
@onready var _volume_slider: HSlider = $SettingsDialog/Margin/VBox/VolumeBox/VolumeSlider
@onready var _volume_value: Label = $SettingsDialog/Margin/VBox/VolumeBox/VolumeValue
@onready var _resolution_option: OptionButton = $SettingsDialog/Margin/VBox/ResolutionOption
@onready var _autosave_option: OptionButton = $SettingsDialog/Margin/VBox/AutosaveOption
@onready var _settings_save: Button = $SettingsDialog/Margin/VBox/Buttons/Save
@onready var _settings_cancel: Button = $SettingsDialog/Margin/VBox/Buttons/Cancel


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
	_volume_slider.value_changed.connect(_on_volume_changed)
	_apply_startup_resolution()


func _on_start_pressed() -> void:
	EventBus.start_game.emit()
	get_tree().change_scene_to_file("res://scenes/country_select/country_select.tscn")


func _on_load_pressed() -> void:
	var data := SaveManager.load_game()
	if data.is_empty():
		# TODO: 无存档提示（后续接 Toast/弹窗）
		push_warning("主界面: 无存档可读取")
		return
	EventBus.load_game.emit()
	# TODO: 用 data 恢复 GameManager / 各系统状态
	get_tree().change_scene_to_file("res://scenes/game_ui/game_ui.tscn")


func _on_config_pressed() -> void:
	_api_url_input.text = ConfigManager.api_url
	_api_key_input.text = ConfigManager.api_key
	_model_input.text = ConfigManager.model
	_config_dialog.visible = true


func _on_save_config_pressed() -> void:
	ConfigManager.api_url = _api_url_input.text.strip_edges()
	ConfigManager.api_key = _api_key_input.text.strip_edges()
	ConfigManager.model = _model_input.text.strip_edges()
	ConfigManager.save_config()
	_config_dialog.visible = false


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


## ===== 制作人员（暂未实现） =====

func _on_credits_pressed() -> void:
	# TODO: 打开制作人员名单弹窗（内容待定）
	EventBus.open_panel.emit("credits")
	push_warning("主界面: 制作人员弹窗待实现")


func _on_quit_pressed() -> void:
	EventBus.quit_game.emit()
	get_tree().quit()
