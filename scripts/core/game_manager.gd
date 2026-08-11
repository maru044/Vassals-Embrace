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
const START_GOLD := 20.0        # 初始金币
const START_PRESTIGE := 50.0    # 初始威望
const LOAN_AMOUNT := 10.0       # 每笔贷款金额（偿还也是一笔）
const BUILDING_MAX_LEVEL := 4   # 建筑等级上限（初始 lv.1 可升 3 次）

# ---- 引擎②-B1 军队（源 游戏规则.md §第六章）----
const BASE_ARMY_CAP := 5          # 军队基础上限（队）
const ARMY_PER_PROVINCE := 2      # 每直接统治地块 +2 队
const VASSAL_ARMY_PENALTY := 3    # 附庸税：附庸国上限 -3 队（受保护国不算）
const RECRUIT_COST := 20.0        # 招募一队军队 20 金
const INIT_ARMY_RATIO := 0.5      # 初始军队 = 上限 50%（向上取整；无战损，招募为领土扩张后补兵保底）

# ---- 引擎②-B3-2 行军 ----
const ADJACENCY_PATH := "res://data/province_adjacency.json"   # 省份导航图（land/sea）
const ARMY_MOVE_STEPS := 2        # 每月最多移动 2 格

const COUNTRIES_PATH := "res://data/countries.json"

# 特例初始好感：宗主视角对特定附庸（威尔士=叛乱低、曼岛=乖受保护国高）
const _SPECIAL_FAVOR := {
	"England": {"Wales": 10.0, "Isle of Man": 80.0},
}

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
var recruited_this_month := {}  # id -> bool（本月是否已招募；每月限 1 队，月末重置）
var army_position := {}         # id -> 所在省（引擎②-B3-2 行军）
var army_order := {}            # id -> 目标省（""=待命；月中可改，月末推进）
var return_province := {}       # id -> 返回省份（ZoC 用，非战时随移动更新）
var _adjacency := {}            # 省 -> {邻接省: land/sea}（懒加载）
# 省份数据（由 game.gd 注入；GDScript 字典按引用共享 → 单一数据源，升级实时反映）
var province_owner := {}
var province_buildings := {}

var _country_list: Array = []   # countries.json（读 liege 关系，用于初始好感）


func _ready() -> void:
	EventBus.end_month.connect(_on_end_month)


func start_new_game(country_id: String) -> void:
	player_country_id = country_id
	current_country_id = -1      # int 索引已弃用，统一走 string id
	month = 9
	year = 1400
	is_running = true
	_load_countries()
	# 初始化所有国家运行态数据（Master 2026-08-11 定：初始金币 20 / 威望 50）
	country_gold.clear()
	country_prestige.clear()
	player_favor.clear()
	army_count.clear()
	recruited_this_month.clear()
	army_position.clear()
	army_order.clear()
	return_province.clear()
	for cid in _all_country_ids():
		country_gold[cid] = START_GOLD
		country_prestige[cid] = START_PRESTIGE
		army_count[cid] = _initial_army(cid)   # 引擎②-B1：初始军队 = 上限 50%
		if cid != player_country_id:
			player_favor[cid] = _initial_favor(cid)
	EventBus.start_game.emit()


## 从省份归属收集全部国家 id（map_data.province_owner 覆盖 27 国）
func _all_country_ids() -> Array:
	var ids := {}
	for province in province_owner:
		var cid: String = province_owner[province]
		if cid != "":
			ids[cid] = true
	return ids.keys()


## 加载 countries.json（读 liege 关系）
func _load_countries() -> void:
	if not _country_list.is_empty():
		return
	var f := FileAccess.open(COUNTRIES_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_country_list = data.get("countries", [])


## 国家宗主（countries.json liege）
func _country_liege(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("liege", ""))
	return ""


## 附庸类型（countries.json vassal_type；受保护国不算附庸）
func _country_vassal_type(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("vassal_type", ""))
	return ""


## 是否附庸（有宗主且非受保护国）——附庸税 -3 队规则用
func _is_vassal(cid: String) -> bool:
	return _country_liege(cid) != "" and _country_vassal_type(cid) != "protectorate"


## 直辖地块数（该国王朝直领的省份；附庸不算宗主的地块）
func _direct_provinces(cid: String) -> int:
	var n := 0
	for province in province_owner:
		if province_owner[province] == cid:
			n += 1
	return n


## 军队上限（引擎②-B1，源 游戏规则.md：5 + 2×直辖地块，附庸 -3 队）
func get_army_cap(cid: String) -> int:
	var cap := BASE_ARMY_CAP + ARMY_PER_PROVINCE * _direct_provinces(cid)
	if _is_vassal(cid):
		cap -= VASSAL_ARMY_PENALTY
	return maxi(cap, 1)


## 初始军队 = 上限 50%（向上取整）。无战损：军队只增不减，招募用于领土扩张后补到新上限
func _initial_army(cid: String) -> int:
	return ceili(float(get_army_cap(cid)) * INIT_ARMY_RATIO)


## 招募一队军队（引擎②-B2）：20 金/队；每月限 1 队；上限拦截；扣款 + 军队 +1
func recruit_army() -> Dictionary:
	var pid := player_country_id
	var cur: int = army_count.get(pid, 0)
	var cap := get_army_cap(pid)
	if recruited_this_month.get(pid, false):
		return {"ok": false, "error": "本月已招募过一队，下月再来"}
	if cur >= cap:
		return {"ok": false, "error": "已达军队上限（%d/%d）" % [cur, cap]}
	if country_gold.get(pid, 0.0) < RECRUIT_COST:
		return {"ok": false, "error": "金币不足（需要 %d 金）" % int(RECRUIT_COST)}
	country_gold[pid] -= RECRUIT_COST
	army_count[pid] = cur + 1
	recruited_this_month[pid] = true
	return {"ok": true, "army": cur + 1, "cap": cap, "gold": country_gold[pid]}


## 玩家对某国初始好感：默认 20；直接附庸/宗主 +40（60）；特例覆盖（英格兰视角：威尔士 10 / 曼岛 80）
func _initial_favor(cid: String) -> float:
	var base := 20.0
	if _country_liege(cid) == player_country_id:
		base += 40.0   # 玩家是宗主 → 对附庸好感高
	elif _country_liege(player_country_id) == cid:
		base += 40.0   # 玩家是附庸 → 对宗主好感高
	var special: Dictionary = _SPECIAL_FAVOR.get(player_country_id, {})
	if special.has(cid):
		base = special[cid]
	return base


## 玩家对某国好感增减（LLM modify_favor 工具落地；clamp 0-100，即时生效并广播刷新）
func change_favor(target_id: String, delta: float) -> void:
	if not player_favor.has(target_id):
		player_favor[target_id] = 0.0
	player_favor[target_id] = clampf(player_favor[target_id] + delta, 0.0, 100.0)
	EventBus.favor_changed.emit(target_id, player_favor[target_id])


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
	# 招募次数每月重置（每月限 1 队）
	recruited_this_month.clear()
	# 引擎①-AI经营：AI 主动花钱（优先补兵到上限，然后升级经济建筑）
	_ai_economy()
	# 行军推进（每月最多 2 格，沿命令 BFS 最短路径；非战时无 ZoC）
	_advance_army()


## 引擎①-AI经营（Master 定：AI 也花钱）：对每个 AI 国家——
## 1) 优先补兵到军队上限（每队 20 金；AI 不受「每月限 1 队」按钮限制）
## 2) 补满后，把剩余金币用于升级经济建筑（farm/market/brothel，上限 LV4）
## 自限：补满即停、建筑满级即停、金币不足即停 → AI 不会无限膨胀
func _ai_economy() -> void:
	for cid in army_count:
		if cid == player_country_id:
			continue
		var gold: float = country_gold.get(cid, 0.0)
		# 1) 优先补兵到军队上限
		var cap := get_army_cap(cid)
		var cur: int = army_count.get(cid, 0)
		while cur < cap and gold >= RECRUIT_COST:
			gold -= RECRUIT_COST
			cur += 1
		army_count[cid] = cur
		# 2) 升级经济建筑（遍历本国省份，farm/market/brothel 逐个升到 LV4 或金币不足）
		for province in province_owner:
			if province_owner[province] != cid:
				continue
			var b: Dictionary = province_buildings.get(province, {})
			if not province_buildings.has(province):
				province_buildings[province] = b   # 写回新建字典（引用传递）
			for bname in ["farm", "market", "brothel"]:
				while true:
					var lv: int = int(b.get(bname, 0))
					if lv >= BUILDING_MAX_LEVEL:
						break
					var cost := building_upgrade_cost(bname, lv)
					if gold < cost:
						break
					gold -= cost
					b[bname] = lv + 1
		country_gold[cid] = gold


## 建筑升级费用：初始 100，每级 ×1.5（lv1→2 100 / 2→3 150 / 3→4 225）
func building_upgrade_cost(building: String, current_level: int) -> float:
	return 100.0 * pow(1.5, float(maxi(current_level, 1) - 1))


## 尝试升级玩家国家某省建筑：扣款 + 等级+1（上限 LV4）
func upgrade_building(province: String, building: String) -> Dictionary:
	if building == "fort":
		return {"ok": false, "error": "要塞不可建造/升级"}   # Master：关闭要塞升级（玩家+AI 均不可）
	if province_owner.get(province, "") != player_country_id:
		return {"ok": false, "error": "非本国省份"}
	var b: Dictionary = province_buildings.get(province, {})
	var lv: int = int(b.get(building, 0))
	if lv >= BUILDING_MAX_LEVEL:
		return {"ok": false, "error": "已达最高等级"}
	var cost := building_upgrade_cost(building, lv)
	if country_gold[player_country_id] < cost:
		return {"ok": false, "error": "金币不足（需要 %d）" % int(cost)}
	country_gold[player_country_id] -= cost
	b[building] = lv + 1
	return {"ok": true, "cost": cost, "level": lv + 1}


## 贷款一笔（+10 金，贷款总额 +10；保留到主动偿还）
func take_loan() -> Dictionary:
	country_gold[player_country_id] += LOAN_AMOUNT
	loans[player_country_id] = loans.get(player_country_id, 0.0) + LOAN_AMOUNT
	return {"ok": true, "loan": loans[player_country_id], "gold": country_gold[player_country_id]}


## 偿还一笔贷款（-10 金，贷款总额 -10）
func repay_loan() -> Dictionary:
	var cur: float = loans.get(player_country_id, 0.0)
	if cur < LOAN_AMOUNT:
		return {"ok": false, "error": "无贷款可还"}
	if country_gold[player_country_id] < LOAN_AMOUNT:
		return {"ok": false, "error": "金币不足"}
	country_gold[player_country_id] -= LOAN_AMOUNT
	loans[player_country_id] = cur - LOAN_AMOUNT
	return {"ok": true, "loan": loans[player_country_id], "gold": country_gold[player_country_id]}


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


# ===== 引擎②-B3-2 行军引擎（核心）=====

## 懒加载省份邻接图
func _ensure_adjacency() -> bool:
	if not _adjacency.is_empty():
		return true
	var f := FileAccess.open(ADJACENCY_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_adjacency = data.get("adjacency", {})
	return not _adjacency.is_empty()


## 初始化军队起始位置（game.gd 提供 {cid: 首都省}）；返回省份同步
func init_army_positions(positions: Dictionary) -> void:
	army_position.clear()
	army_order.clear()
	return_province.clear()
	for cid in positions:
		army_position[cid] = positions[cid]
		return_province[cid] = positions[cid]


## 某国军队在 max_steps 步可达的省份（不含自身；陆/海不区分——Master 定：邻接线即道路，海峡可通行）。
## ZoC 非战时未启用（引擎④战争后补）
func get_reachable_provinces(cid: String, max_steps: int = ARMY_MOVE_STEPS) -> Array:
	if not _ensure_adjacency():
		return []
	var from: String = army_position.get(cid, "")
	if from.is_empty() or from == "":
		return []
	var reached := {}
	var visited := {from: true}
	var frontier := [[from, 0]]
	while not frontier.is_empty():
		var cur: Array = frontier.pop_front()
		var prov: String = cur[0]
		var d: int = cur[1]
		if d >= max_steps:
			continue
		for nxt in _adjacency.get(prov, {}):
			if visited.has(nxt):
				continue
			visited[nxt] = true
			reached[nxt] = true
			frontier.append([nxt, d + 1])
	return reached.keys()


## BFS 可达树：{可达省: 父省}（含 1 步邻居 parent=起点），用于地图画合法移动线（沿邻接线条）。
## 陆/海不区分；ZoC 非战时未启用（引擎④战争后补）。
func get_reachable_tree(cid: String, max_steps: int = ARMY_MOVE_STEPS) -> Dictionary:
	if not _ensure_adjacency():
		return {}
	var from: String = army_position.get(cid, "")
	if from.is_empty():
		return {}
	var tree := {}
	var visited := {from: true}
	var frontier := [[from, 0]]
	while not frontier.is_empty():
		var cur: Array = frontier.pop_front()
		var prov: String = cur[0]
		var d: int = cur[1]
		if d >= max_steps:
			continue
		for nxt in _adjacency.get(prov, {}):
			if visited.has(nxt):
				continue
			visited[nxt] = true
			tree[nxt] = prov
			frontier.append([nxt, d + 1])
	return tree


## 移动合法性（非战时：目标在 2 格陆地可达内即合法；ZoC 战争限制引擎④补）
func can_move_to(cid: String, target: String) -> Dictionary:
	if target == army_position.get(cid, ""):
		return {"ok": true, "reason": "原地"}
	if not get_reachable_provinces(cid, ARMY_MOVE_STEPS).has(target):
		return {"ok": false, "reason": "超出可移动范围（每月 2 格）"}
	return {"ok": true, "reason": ""}


## 下移动令（玩家只能控制自己的军队；月中随时可改，月末推进）
func issue_order(cid: String, target: String) -> Dictionary:
	if cid != player_country_id:
		return {"ok": false, "error": "只能控制自己的军队"}
	var chk := can_move_to(cid, target)
	if not chk.get("ok", false):
		return {"ok": false, "error": chk.get("reason", "")}
	army_order[cid] = target
	return {"ok": true, "order": target}


## 公开路径查询（沿陆地的 BFS 最短路径），供地图画命令路线。
## 注意：勿命名 get_path_to（与 Node 内置方法冲突，签名不匹配会编译报错）
func get_army_path(cid: String, target: String) -> Array:
	var from: String = army_position.get(cid, "")
	if from.is_empty():
		return []
	return _shortest_path(from, target)


## BFS 最短路径（陆/海不区分）；无路径返回 []
func _shortest_path(from: String, to: String) -> Array:
	if not _ensure_adjacency():
		return []
	if from == to:
		return [from]
	var visited := {from: true}
	var frontier := [[from]]
	while not frontier.is_empty():
		var path: Array = frontier.pop_front()
		var cur: String = path[-1]
		for nxt in _adjacency.get(cur, {}):
			if visited.has(nxt):
				continue
			var np: Array = path.duplicate()
			np.append(nxt)
			if nxt == to:
				return np
			visited[nxt] = true
			frontier.append(np)
	return []


## 月末推进：各国沿命令朝目标走最多 2 格；到达后清除命令；返回省份更新为旧位置（非战时简化）
func _advance_army() -> void:
	for cid in army_position:
		var target: String = army_order.get(cid, "")
		if target.is_empty():
			continue
		var from: String = army_position[cid]
		if target == from:
			army_order[cid] = ""
			continue
		var path := _shortest_path(from, target)
		if path.size() < 2:
			continue
		var steps := mini(path.size() - 1, ARMY_MOVE_STEPS)
		var new_pos: String = path[steps]
		return_province[cid] = from
		army_position[cid] = new_pos
		if new_pos == target:
			army_order[cid] = ""
