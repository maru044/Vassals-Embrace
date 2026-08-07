extends Node
## 游戏主循环（Autoload 单例）：当前国家、月份 / 年份、过月结算。
## 与 EventBus 交互：end_month → 结算 → month_advanced

const MONTHS_IN_YEAR := 12

var current_country_id: int = -1
var month: int = 9    # 开局 1400.9
var year: int = 1400
var is_running: bool = false


func _ready() -> void:
	EventBus.end_month.connect(_on_end_month)


func start_new_game(country_id: int) -> void:
	current_country_id = country_id
	month = 9
	year = 1400
	is_running = true
	EventBus.start_game.emit()


func _on_end_month() -> void:
	# 过月结算（业务逻辑逐步替换为各系统）
	_advance_time()
	EventBus.month_advanced.emit(month, year)


func _advance_time() -> void:
	month += 1
	if month > MONTHS_IN_YEAR:
		month = 1
		year += 1
		EventBus.year_advanced.emit(year)
