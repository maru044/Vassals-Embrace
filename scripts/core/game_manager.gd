extends Node
## 游戏主循环（Autoload 单例）：当前国家、月份 / 年份、过月结算。
## 与 EventBus 交互：end_month → 结算 → month_advanced
## 引擎①：运行态数据（金币/威望/好感度）+ 月末统一结算（数值依据 plan/引擎数值备忘.md）

const MONTHS_IN_YEAR := 12

# ---- 引擎① 数值（plan/引擎数值备忘.md，Master 定稿）----
const BASE_INCOME := 5.0        # 国家基础月收入
const BUILDING_INCOME := 0.3    # 每经济建筑每级月收入（farm/market/brothel）
const ARMY_MAINTENANCE := 0.1   # 军队每队每月维护
const LOAN_RATE := 0.05         # 贷款年利率
const PRESTIGE_DECAY := 0.99    # 威望每月衰减 1%
const FAVOR_DECAY := 0.95       # 好感度每月衰减 5%

var current_country_id: int = -1
var player_country_id := ""     # 玩家国家（string id，与 game.gd / countries.json 一致）
var month: int = 9              # 开局 1400.9
var year: int = 1400
var is_running: bool = false

# ---- 引擎① 运行态数据（string 国家 id 索引）----
var country_gold := {}          # id -> float（金币）
var country_prestige := {}      # id -> float（威望）
var player_favor := {}          # target_id -> float（玩家对各国好感度；交互获取引擎⑨）
var loans := {}                 # id -> float（贷款余额，T4 完善）
var army_count := {}            # id -> int（军队队数，引擎②完善）
# 省份数据（由 game.gd 注入；GDScript 字典按引用共享 → 单一数据源，升级实时反映）
var province_owner := {}
var province_buildings := {}


func _ready() -> void:
	EventBus.end_month.connect(_on_end_month)


func start_new_game(country_id: String) -> void:
	player_country_id = country_id
	current_country_id = -1      # int 索引已弃用，统一走 string id
	month = 9
	year = 1400
	is_running = true
	# 初始化所有国家运行态数据（T2 统一默认值；T5 按国力区分）
	country_gold.clear()
	country_prestige.clear()
	player_favor.clear()
	for cid in _all_country_ids():
		country_gold[cid] = 100.0
		country_prestige[cid] = 100.0
		player_favor[cid] = 50.0   # 玩家对各国初始好感（引擎⑨聊天互动增减）
	EventBus.start_game.emit()


## 从省份归属收集全部国家 id（map_data.province_owner 覆盖 27 国）
func _all_country_ids() -> Array:
	var ids := {}
	for province in province_owner:
		var cid: String = province_owner[province]
		if cid != "":
			ids[cid] = true
	return ids.keys()


func _on_end_month() -> void:
	_settle_month()
	_advance_time()
	EventBus.month_advanced.emit(month, year)


## 月末统一结算（所有国家）：金币 + 威望 + 好感度（玩家侧）
func _settle_month() -> void:
	for cid in country_gold:
		# 金币：收入 - 军队维护 - 贷款利息
		var income := get_country_income(cid)
		var maint: float = ARMY_MAINTENANCE * float(army_count.get(cid, 0))
		var interest: float = loans.get(cid, 0.0) * LOAN_RATE / 12.0
		country_gold[cid] += income - maint - interest
		# 威望衰减 1%
		country_prestige[cid] = country_prestige[cid] * PRESTIGE_DECAY
	# 玩家好感度（玩家 → 各国）衰减 5%
	for target in player_favor:
		player_favor[target] = player_favor[target] * FAVOR_DECAY


## 国家月收入：基础 5 + 该国所有省份经济建筑（farm/market/brothel）每级 0.3（经济面板展示用）
func get_country_income(cid: String) -> float:
	var inc := BASE_INCOME
	for province in province_owner:
		if province_owner[province] != cid:
			continue
		var b: Dictionary = province_buildings.get(province, {})
		inc += float(b.get("farm", 0)) * BUILDING_INCOME
		inc += float(b.get("market", 0)) * BUILDING_INCOME
		inc += float(b.get("brothel", 0)) * BUILDING_INCOME
	return inc


func _advance_time() -> void:
	month += 1
	if month > MONTHS_IN_YEAR:
		month = 1
		year += 1
		EventBus.year_advanced.emit(year)
