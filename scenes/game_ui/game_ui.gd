extends Control
## 游戏主界面：顶部栏 + 左侧分栏 + 地图占位 + 右侧（聊天 / 过月）。

@onready var _country_label: Label = $TopBar/HBox/CountryName
@onready var _date_label: Label = $TopBar/HBox/Date
@onready var _gold_label: Label = $TopBar/HBox/Gold
@onready var _prestige_label: Label = $TopBar/HBox/Prestige
@onready var _army_label: Label = $TopBar/HBox/Army
@onready var _chat_button: Button = $RightBar/VBox/Chat
@onready var _end_month_button: Button = $RightBar/VBox/EndMonth

const PANELS := {"economy": "经济", "court": "宫廷", "diplomacy": "外交", "vassal": "附庸", "mission": "任务", "situation": "局势"}


func _ready() -> void:
	_chat_button.pressed.connect(_on_chat_pressed)
	_end_month_button.pressed.connect(_on_end_month_pressed)
	for panel_id in PANELS.keys():
		var btn := get_node_or_null("LeftBar/VBox/%s" % panel_id.capitalize())
		if btn:
			btn.pressed.connect(_on_panel_pressed.bind(panel_id))
	EventBus.month_advanced.connect(func(_m: int, _y: int) -> void: _refresh_top_bar())
	_refresh_top_bar()


func _refresh_top_bar() -> void:
	_country_label.text = "国家 #%d" % GameManager.current_country_id
	_date_label.text = "%d 年 %d 月" % [GameManager.year, GameManager.month]
	_gold_label.text = "金币 0"
	_prestige_label.text = "威望 0"
	_army_label.text = "军队 0"


func _on_panel_pressed(panel_id: String) -> void:
	EventBus.open_panel.emit(panel_id)


func _on_chat_pressed() -> void:
	var chat := get_node_or_null("ChatDialog")
	if chat:
		chat.visible = not chat.visible


func _on_end_month_pressed() -> void:
	EventBus.end_month.emit()
