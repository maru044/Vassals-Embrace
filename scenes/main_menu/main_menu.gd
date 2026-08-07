extends Control
## 主界面：开始游戏 / 读取游戏 / 配置 API / 退出。
## 背景图（含标题）由 Gemini 生成；按钮叠在背景左侧按钮框上。

@onready var _start_button: Button = $MenuButtons/StartGame
@onready var _load_button: Button = $MenuButtons/LoadGame
@onready var _config_button: Button = $MenuButtons/ConfigAPI
@onready var _quit_button: Button = $MenuButtons/Quit

@onready var _config_dialog: PanelContainer = $ConfigDialog
@onready var _api_url_input: LineEdit = $ConfigDialog/Margin/VBox/ApiUrlInput
@onready var _api_key_input: LineEdit = $ConfigDialog/Margin/VBox/ApiKeyInput
@onready var _model_input: LineEdit = $ConfigDialog/Margin/VBox/ModelInput
@onready var _save_button: Button = $ConfigDialog/Margin/VBox/Buttons/Save
@onready var _cancel_button: Button = $ConfigDialog/Margin/VBox/Buttons/Cancel


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_config_button.pressed.connect(_on_config_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_save_button.pressed.connect(_on_save_config_pressed)
	_cancel_button.pressed.connect(_on_cancel_config_pressed)


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


func _on_quit_pressed() -> void:
	EventBus.quit_game.emit()
	get_tree().quit()
