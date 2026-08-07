extends Control
## 国家选择：盾徽 / 推荐 / 简介弹窗（占位，真实盾徽后接）。

const PLACEHOLDER_COUNTRIES: Array = [
	{"id": 0, "name": "England", "desc": "罗莎蒙德·兰开斯特统治的英格兰，闷骚痴女的女王。"},
	{"id": 1, "name": "Scotland", "desc": "玛格丽特·斯图亚特统治的苏格兰，宠物主人气质的女王。"},
	{"id": 2, "name": "Tyrone", "desc": "内芙·奥尼尔统治的蒂龙，爱尔兰最强犬娘。"},
	{"id": 3, "name": "Wales", "desc": "欧文娜·格林杜尔起义的威尔士，反叛犬娘。"},
	{"id": 4, "name": "The Isles", "desc": "芙蕾雅统治的群岛领地，爱吃麦当劳的海盗栖姬。"},
]

@onready var _grid: GridContainer = $Grid
@onready var _info_title: Label = $InfoPanel/Margin/VBox/Title
@onready var _info_desc: Label = $InfoPanel/Margin/VBox/Desc
@onready var _confirm: Button = $InfoPanel/Margin/VBox/Confirm

var _selected_id: int = -1


func _ready() -> void:
	_confirm.pressed.connect(_on_confirm_pressed)
	_confirm.disabled = true
	_populate()


func _populate() -> void:
	for c in PLACEHOLDER_COUNTRIES:
		var btn := Button.new()
		btn.text = c["name"]
		btn.custom_minimum_size = Vector2(160, 90)
		btn.pressed.connect(_on_country_pressed.bind(c["id"]))
		_grid.add_child(btn)


func _on_country_pressed(id: int) -> void:
	_selected_id = id
	for c in PLACEHOLDER_COUNTRIES:
		if c["id"] == id:
			_info_title.text = "1400 年的 %s" % c["name"]
			_info_desc.text = c["desc"]
			break
	_confirm.disabled = false


func _on_confirm_pressed() -> void:
	if _selected_id < 0:
		return
	EventBus.country_selected.emit(_selected_id)
	EventBus.confirm_country.emit()
	GameManager.start_new_game(_selected_id)
	get_tree().change_scene_to_file("res://scenes/game_ui/game_ui.tscn")
