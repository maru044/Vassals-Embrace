extends Control
## 主界面：开始游戏 / 读取游戏 / 配置 API / 退出（占位，美术后接）。

@onready var _start_button: Button = $MenuButtons/StartGame
@onready var _load_button: Button = $MenuButtons/LoadGame
@onready var _config_button: Button = $MenuButtons/ConfigAPI
@onready var _quit_button: Button = $MenuButtons/Quit


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_config_button.pressed.connect(_on_config_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	EventBus.start_game.emit()
	get_tree().change_scene_to_file("res://scenes/country_select/country_select.tscn")


func _on_load_pressed() -> void:
	EventBus.load_game.emit()
	# TODO: 读取存档后进入游戏


func _on_config_pressed() -> void:
	EventBus.configure_api.emit()
	# TODO: 弹出 API 配置窗口


func _on_quit_pressed() -> void:
	EventBus.quit_game.emit()
	get_tree().quit()
