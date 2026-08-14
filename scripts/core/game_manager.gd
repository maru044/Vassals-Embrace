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

# ---- 引擎③ 战斗（源 引擎数值备忘.md §六，Master 8/12 定）----
const BASE_MORALE := 10.0            # 基础士气/队（默认 10）
const MORALE_RECOVER := 0.2          # 战后每月恢复 20% 最大士气
const BATTLE_FACTOR := 0.2           # 士气伤害系数（公式 0.2）
const DICE_MORALE := 0.1             # 骰子修正系数（公式 0.1）
const CAPITAL_LOST_SURRENDER := 6    # 首都连续沦陷 6 个月 → 自动投降（Master 定）

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
var retreating := {}            # id -> bool（战败强制撤退回首都中，命令锁定不可改）
var return_province := {}       # id -> 返回省份（ZoC 用，非战时随移动更新）
var _adjacency := {}            # 省 -> {邻接省: land/sea}（懒加载）
# 省份数据（由 game.gd 注入；GDScript 字典按引用共享 → 单一数据源，升级实时反映）
var province_owner := {}
var province_buildings := {}
# ---- 引擎③ 战斗运行态 ----
var capital_province := {}       # cid -> 首都英文省（game.gd 注入）
var army_morale := {}            # cid -> 当前士气（上限 = 基础士气×队数）
var surrender_flag := {}         # cid -> bool（首都被打败 / 沦陷≥6月 → 自动投降）
var capital_lost_months := {}    # cid -> 首都沦陷连续月数
var siege_target := {}           # cid -> 围城目标省（引擎③-T4 驻留判定）
# ---- 引擎④-T5 AI 军队状态机（Master 8/12：AI 军队行动走状态机，非 LLM）----
var ai_army_state := {}          # cid -> FREE/MARCH_SIEGE/SIEGING/MARCH_RELIEF/REINFORCE
# ---- 引擎④-战争前置（Master 8/12：战斗只在战争状态发生，盟友同侧不互打）----
var wars := []                   # 每项 {id:int, attacker:[cid...], defender:[cid...]}
var _next_war_id := 1
# ---- 引擎④ 外交博弈（Master 8/13 过家家模式：AI 决策交 LLM，引擎只结算）----
const PLAY_DURATION := 2         # 博弈持续 2 个月（单阶段，经两次月末结算）
const PRESTIGE_BACKDOWN := 10.0  # 退缩方失威望
var plays := []                  # 每项 {id, initiator, target, init_goal, targ_goal, deadline, sides:{A,B}, state}
var _next_play_id := 1
# ---- 引擎④-CB 战争理由（Master 8/13：先做通用 CB；特殊/事件 CB 待事件/国际组织/任务树）----
const CB_PATH := "res://data/cb.json"
const REQUIRE_CB_DURATION := 12      # 要求被拒 → 获得 1 年（12 回合）CB
const REQUIRE_FAVOR_MIN := 80.0      # 要求附庸/受保护国/联合统治需好感度 >80
var _cb_list := []                   # cb.json（懒加载）
var cb_timers := {}                  # "actor:target:cb_id" -> 剩余月数（1年CB）
var runtime_liege := {}              # target -> liege（要求X同意后运行时附庸关系；完整机制引擎⑤）
var runtime_union := {}              # target -> lead（要求联合统治同意后运行时联统；引擎⑧完整）
var runtime_vassal_type := {}        # target -> vassal_type（要求X同意后运行时附庸类型：feudal/protectorate）
# ---- 引擎⑥ 事件 + 临时修正（Master 8/13：历史/脉冲/随机三类 + [Root.*] 变量 + effects/modifiers）----
const EVENTS_PATH := "res://data/events.json"
var _event_list := []                  # events.json（懒加载）
# ---- 引擎⑥ 局势（Master 8/14：进度条 0~100 + 5 阶段；玩家专属，事件增减，任务解锁条件）----
const SITUATIONS_PATH := "res://data/situations.json"
var _situation_list := []              # situations.json（懒加载）
var situation_value := {}              # id -> int（0~100），玩家拥有局势的当前值
# 动态拥有者（Master 8/14）：爱尔兰至高王——初始蒂龙 Tyrone，诸部可夺取（引擎⑧ 完整机制，局势系统先用）
var high_king_id := ""
var _fired_historical := {}            # event_id -> true（历史事件一次性）
var _pulse_last := {}                  # event_id -> "年.月"（脉冲上次触发）
var modifiers := {}                    # 受影响国 cid -> [{type, value, months}] 临时修正
var player_event_queue := []           # 玩家待处理事件 [{event_id, root, from}]（逐个弹出）
# ---- 引擎⑦ 任务树（Master 8/14：玩家专属；程序判定 + LLM flag 兜底；三态：完成/可做/锁定）----
const MISSIONS_PATH := "res://data/missions.json"
var _mission_list := []                # missions.json（懒加载）
var completed_missions := {}           # mission_id -> true（已完成并领奖）
var mission_flags := {}                # flag -> true（事件 effects.flags 置位，如老同盟缔结）

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
	retreating.clear()           # 引擎③：新档无撤退
	return_province.clear()
	army_morale.clear()          # 引擎③：初始士气 = 总士气
	surrender_flag.clear()
	capital_lost_months.clear()
	siege_target.clear()         # 引擎③-T4：新档无围城
	ai_army_state.clear()        # 引擎④-T5：新档 AI 军队全部 FREE
	wars.clear()                 # 引擎④-战争前置：新档无战争
	_next_war_id = 1
	plays.clear()                # 引擎④：新档无外交博弈
	_next_play_id = 1
	_fired_historical.clear()    # 引擎⑥：新档历史事件未触发
	_pulse_last.clear()          # 引擎⑥：新档脉冲未触发
	modifiers.clear()            # 引擎⑥：新档无临时修正
	player_event_queue.clear()   # 引擎⑥：新档无待处理事件
	cb_timers.clear()            # 引擎④-CB：新档无 1 年要求 CB
	runtime_liege.clear()        # 引擎④-CB：新档无运行时附庸关系
	runtime_union.clear()        # 引擎④-CB：新档无运行时联统关系
	runtime_vassal_type.clear()  # 引擎④-CB：新档无运行时附庸类型
	situation_value.clear()      # 引擎⑥-局势：新档按 initial_stage 重置
	high_king_id = "Tyrone"      # 引擎⑥-局势：初始爱尔兰至高王 = 蒂龙（Master 8/14）
	_init_situations()           # 引擎⑥-局势：新档初始化所有局势值
	completed_missions.clear()   # 引擎⑦-任务：新档无已完成任务
	mission_flags.clear()        # 引擎⑦-任务：新档无任务 flag
	for cid in _all_country_ids():
		country_gold[cid] = START_GOLD
		country_prestige[cid] = START_PRESTIGE
		army_count[cid] = _initial_army(cid)   # 引擎②-B1：初始军队 = 上限 50%
		army_morale[cid] = get_total_morale(cid)   # 引擎③：士气满值
		if cid != player_country_id:
			player_favor[cid] = _initial_favor(cid)
	# 引擎⑥（Master 8/13：事件在「回合开始」触发）→ 开局 1400.9 立即触发开局月事件
	_tick_events()
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


## 运行时附庸类型（runtime_vassal_type 覆盖静态；要求X同意后生效）
func _effective_vassal_type(cid: String) -> String:
	return str(runtime_vassal_type.get(cid, _country_vassal_type(cid)))


## 是否附庸（有宗主且非受保护国）——附庸税 -3 队规则用（Master 8/13：运行时附庸关系也算）
func _is_vassal(cid: String) -> bool:
	return _effective_liege(cid) != "" and _effective_vassal_type(cid) != "protectorate"


## 附庸税落地（Master 8/13）：军队超上限 → 直接降到上限（附庸税 -3 队后可能超上限）
func _clamp_army_to_cap(cid: String) -> void:
	var cap := get_army_cap(cid)
	if army_count.get(cid, 0) > cap:
		army_count[cid] = cap


## 直辖地块数（该国王朝直领的省份；附庸不算宗主的地块）
func _direct_provinces(cid: String) -> int:
	var n := 0
	for province in province_owner:
		if province_owner[province] == cid:
			n += 1
	return n


## 军队上限（引擎②-B1：5 + 2×直辖地块，附庸 -3 队）+ 引擎⑥ 临时 army_cap 修正
func get_army_cap(cid: String) -> int:
	var cap := BASE_ARMY_CAP + ARMY_PER_PROVINCE * _direct_provinces(cid)
	if _is_vassal(cid):
		cap -= VASSAL_ARMY_PENALTY
	cap += int(country_event_modifier(cid, "army_cap"))
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
	# 引擎⑥（Master 8/13：事件在「回合开始」触发）→ 新月份开始即触发该月事件（历史/脉冲/随机）
	_tick_events()
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
	# 附庸税/上限（Master 8/13）：所有国家军队超上限 → 直接降到上限
	for cid in army_count:
		_clamp_army_to_cap(cid)
	# 引擎③：交战结算（同省相遇）→ 围城破城 → 士气恢复 → 首都沦陷计时
	_resolve_battles()
	_resolve_sieges()
	_apply_morale_recovery()
	_update_capital_occupation()
	# 引擎③-返回省份（Master 8/13 补全规则）：返回省份落入敌方 ZoC → 自动清除
	_refresh_return_provinces()
	# 引擎④：外交博弈推进（deadline -1，到期开战）
	_tick_plays()
	# 引擎④-CB：1 年要求 CB 计时 -1
	_tick_cbs()
	# 引擎⑥-事件触发已移至「回合开始」（_on_end_month 内 _advance_time 后 + start_new_game 开局），此处不再触发
	# 引擎④-T5：AI 军队状态机决策（停战回 FREE / 首都沦陷解围 / 友军激战增援 / 默认围敌方首都，ZoC 阻挡先攻要塞）
	_tick_ai_armies()
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


# ===== 引擎③ 战斗结算器（源 引擎数值备忘.md §六，无减员）=====

## 总士气 = 基础士气 × 部队总数 ×（1 + 临时 morale 修正，引擎⑥）
func get_total_morale(cid: String) -> float:
	return BASE_MORALE * float(army_count.get(cid, 0)) * (1.0 + country_event_modifier(cid, "morale"))


## 当前士气（clamp 到 0..总士气；上限随军队数变化）
func get_morale(cid: String) -> float:
	return clampf(army_morale.get(cid, 0.0), 0.0, get_total_morale(cid))


## ---- 战争判定（引擎④前置）----

## 某国所属战争与阵营；未参战返回 {}（简化：一国同时只在一场战争）
func _war_affiliation(cid: String) -> Dictionary:
	for w in wars:
		if w["attacker"].has(cid):
			return {"war_id": int(w["id"]), "side": "A"}
		if w["defender"].has(cid):
			return {"war_id": int(w["id"]), "side": "B"}
	return {}


## a、b 是否在同一场战争的敌对阵营（同一战争的 A 对 B）
func _are_at_war(a: String, b: String) -> bool:
	if a == b:
		return false
	var wa := _war_affiliation(a)
	var wb := _war_affiliation(b)
	if wa.is_empty() or wb.is_empty():
		return false
	return int(wa["war_id"]) == int(wb["war_id"]) and wa["side"] != wb["side"]


## a、b 是否为盟友（同一战争的同侧；或同一国家）
func _are_allies(a: String, b: String) -> bool:
	if a == b:
		return true
	var wa := _war_affiliation(a)
	var wb := _war_affiliation(b)
	if wa.is_empty() or wb.is_empty():
		return false
	return int(wa["war_id"]) == int(wb["war_id"]) and wa["side"] == wb["side"]


## 宣战：attacker 对 defender 开战（cb=战争理由，AI 可自由选通用 CB，玩家走博弈/宣战 UI）
func declare_war(attacker: String, defender: String, cb := "") -> Dictionary:
	if attacker == defender:
		return {"ok": false, "error": "不能对自己宣战"}
	if _are_at_war(attacker, defender):
		return {"ok": false, "error": "双方已处于战争状态"}
	wars.append({"id": _next_war_id, "attacker": [attacker], "defender": [defender], "cb": cb})
	var wid := _next_war_id
	_next_war_id += 1
	EventBus.war_started.emit(wid)
	return {"ok": true, "war_id": wid}


## 加入战争某侧（盟友/附庸入战；side: "A" 进攻方 / "B" 防守方）
func add_war_participant(cid: String, war_id: int, side: String) -> Dictionary:
	if not _war_affiliation(cid).is_empty():
		return {"ok": false, "error": "该国家已参与其他战争"}
	for w in wars:
		if int(w["id"]) != war_id:
			continue
		var list: Array = w["attacker"] if side == "A" else w["defender"]
		if list.has(cid):
			return {"ok": false, "error": "已在该阵营"}
		list.append(cid)
		return {"ok": true}
	return {"ok": false, "error": "战争不存在"}


## 结束战争（议和/投降后移除参战关系）
func end_war(war_id: int) -> Dictionary:
	for i in wars.size():
		if int(wars[i]["id"]) == war_id:
			wars.remove_at(i)
			EventBus.war_ended.emit(war_id)
			return {"ok": true}
	return {"ok": false, "error": "战争不存在"}


## ---- 引擎④ 外交博弈（Master 8/13：AI 决策交 LLM「过家家」，引擎只结算）----

## 该国是否已在战争中（任一战争任一侧）
func _in_war(cid: String) -> bool:
	for w in wars:
		if w["attacker"].has(cid) or w["defender"].has(cid):
			return true
	return false


## 该国是否已在进行中的博弈
func _in_play(cid: String) -> bool:
	for p in plays:
		if p["state"] != "playing":
			continue
		if p["initiator"] == cid or p["target"] == cid:
			return true
		if p["sides"]["A"].has(cid) or p["sides"]["B"].has(cid):
			return true
	return false


## 发起外交博弈：initiator 对 target 提进攻目标（如 "附庸化" / "吞并 Lothian" / "独立" / "联合统治"）
## cb=战争理由（AI 自由选通用 CB；init_goal 为空时用 cb 名作目标）
func start_play(initiator: String, target: String, init_goal: String, cb := "") -> Dictionary:
	if initiator == target:
		return {"ok": false, "error": "不能对自己发起博弈"}
	if _in_war(initiator) or _in_war(target):
		return {"ok": false, "error": "不能对已在战争中的国家发起博弈"}
	if _in_play(initiator) or _in_play(target):
		return {"ok": false, "error": "已有进行中的博弈"}
	var goal := init_goal
	if goal.is_empty() and not cb.is_empty():
		goal = str(get_cb(cb).get("name", cb))
	plays.append({
		"id": _next_play_id, "initiator": initiator, "target": target,
		"init_goal": goal, "targ_goal": "保持现状", "cb": cb,
		"deadline": PLAY_DURATION, "sides": {"A": [initiator], "B": [target]}, "state": "playing",
	})
	var pid := _next_play_id
	_next_play_id += 1
	EventBus.diplomatic_play_started.emit(pid)
	return {"ok": true, "play_id": pid}


## 站队：cid 加入进行中博弈的 side（A 发起方 / B 防守方），即战前立场
func join_play(play_id: int, cid: String, side: String) -> Dictionary:
	if side != "A" and side != "B":
		return {"ok": false, "error": "阵营必须为 A/B"}
	if _in_war(cid) or _in_play(cid):
		return {"ok": false, "error": "该国已在战争或博弈中"}
	for p in plays:
		if int(p["id"]) != play_id or p["state"] != "playing":
			continue
		var list: Array = p["sides"][side]
		if list.has(cid):
			return {"ok": false, "error": "已在该阵营"}
		list.append(cid)
		EventBus.diplomatic_play_started.emit(play_id)
		return {"ok": true, "play_id": play_id, "side": side}
	return {"ok": false, "error": "博弈不存在或已结束"}


## 改目标：博弈方（发起方/防守方）改自己的战争目标
func set_play_goal(play_id: int, cid: String, goal: String) -> Dictionary:
	for p in plays:
		if int(p["id"]) != play_id or p["state"] != "playing":
			continue
		if p["initiator"] == cid:
			p["init_goal"] = goal
		elif p["target"] == cid:
			p["targ_goal"] = goal
		else:
			return {"ok": false, "error": "非博弈方"}
		return {"ok": true, "play_id": play_id, "goal": goal}
	return {"ok": false, "error": "博弈不存在或已结束"}


## 退缩：side 侧退缩 → 对方不战而获目标 + 退缩方失威望 → 博弈和平解决
func back_down(play_id: int, side: String) -> Dictionary:
	if side != "A" and side != "B":
		return {"ok": false, "error": "阵营必须为 A/B"}
	for p in plays:
		if int(p["id"]) != play_id or p["state"] != "playing":
			continue
		p["state"] = "resolved"
		var winner_side: String = "B" if side == "A" else "A"
		for cid in p["sides"][side]:
			country_prestige[cid] = maxf(0.0, country_prestige.get(cid, 0.0) - PRESTIGE_BACKDOWN)
		_apply_play_goal(p, winner_side)
		EventBus.diplomatic_play_resolved.emit(play_id)
		return {"ok": true, "play_id": play_id, "retreated": side, "winner_side": winner_side}
	return {"ok": false, "error": "博弈不存在或已结束"}


## 退缩后目标落地（Master 8/14 修正：V3 规则，一方退缩自动实现对方战争目标）
## 按 CB 类型落地：vassalize→附庸 / protectorate→受保护国 / personal_union→联统 /
## independence→附庸独立（解除宗主）；吞并/夺至高王/未知仅记录 winner_goal（数据就绪后补）
func _apply_play_goal(p: Dictionary, winner_side: String) -> void:
	p["winner_goal"] = p["init_goal"] if winner_side == "A" else p["targ_goal"]
	var winner: String = p["initiator"] if winner_side == "A" else p["target"]
	var loser: String = p["target"] if winner_side == "A" else p["initiator"]
	var cb: String = str(p.get("cb", ""))
	match cb:
		"vassalize", "protectorate":
			# winner 使 loser 成为附庸 / 受保护国（走既有建立流程，含 DAG 防环 + 附庸税）
			var rel: Dictionary = establish_requirement(winner, loser, cb)
			p["goal_applied"] = rel.get("ok", false)
		"personal_union":
			# winner 与 loser 建立联合统治（引擎⑧ 数据层已支持）
			var rel_u: Dictionary = establish_requirement(winner, loser, "personal_union")
			p["goal_applied"] = rel_u.get("ok", false)
		"independence":
			# 独立：附庸（winner）从宗主（loser）脱离
			if _effective_liege(winner) == loser:
				runtime_liege.erase(winner)
				runtime_vassal_type.erase(winner)
				EventBus.diplomatic_relation_changed.emit(winner, loser, "independence")
				p["goal_applied"] = true
		_:
			p["goal_applied"] = false   # 吞并/夺取至高王：记录 winner_goal，数据就绪后补落地


## 每月博弈推进：deadline -1；到期仍未退缩 → 开战（主国宣战 + 站队国入战）
func _tick_plays() -> void:
	for p in plays:
		if p["state"] != "playing":
			continue
		p["deadline"] = int(p["deadline"]) - 1
		if int(p["deadline"]) > 0:
			continue
		var attacker: String = p["initiator"]
		var defender: String = p["target"]
		if not _are_at_war(attacker, defender):
			var wres := declare_war(attacker, defender)
			if wres.get("ok", false):
				var wid: int = int(wres.get("war_id", 0))
				for cid in p["sides"]["A"]:
					if cid != attacker:
						add_war_participant(cid, wid, "A")
				for cid in p["sides"]["B"]:
					if cid != defender:
						add_war_participant(cid, wid, "B")
		p["state"] = "resolved"
		EventBus.diplomatic_play_resolved.emit(int(p["id"]))


## 进行中的博弈列表（面板 / LLM 世界状态用，深拷贝防篡改）
func get_active_plays() -> Array:
	var out := []
	for p in plays:
		if p["state"] == "playing":
			out.append(p.duplicate(true))
	return out


# ===== 引擎④-CB 战争理由（Master 8/13：先做通用 CB；特殊/事件 CB 待事件/国际组织/任务树）=====

## 懒加载 CB 表（cb.json）
func _ensure_cbs() -> bool:
	if not _cb_list.is_empty():
		return true
	var f := FileAccess.open(CB_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_cb_list = data.get("cb", [])
	return not _cb_list.is_empty()


## 取 CB 定义（无则 {}）
func get_cb(cb_id: String) -> Dictionary:
	if not _ensure_cbs():
		return {}
	for c in _cb_list:
		if str(c.get("id", "")) == cb_id:
			return c
	return {}


## 国家文化（Master 8/13 判定：piracy=诺斯 / tribal=凯尔特(爱尔兰) / 其余=英格兰）
## 注：countries.json 无 culture 字段，按政体推导（统治者档案：海盗3=塞壬诺斯、爱尔兰16=犬娘凯尔特、其余=英格兰系）
func country_culture(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return _culture_from_government(str(c.get("government", "")))
	return "english"


func _culture_from_government(gov: String) -> String:
	if gov == "piracy":
		return "norse"
	if gov == "tribal":
		return "celtic"
	return "english"


## 运行时宗主（runtime_liege 覆盖静态 countries.json liege；要求X同意后生效）
func _effective_liege(cid: String) -> String:
	return str(runtime_liege.get(cid, _country_liege(cid)))


## 公开：运行时宗主（UI 附庸面板用）
func effective_liege(cid: String) -> String:
	return _effective_liege(cid)


## 公开：运行时附庸类型（UI 附庸面板用）
func effective_vassal_type(cid: String) -> String:
	return _effective_vassal_type(cid)


## cid 是否为 liege 的附庸（运行时；受保护国不算附庸）
func _is_vassal_of(cid: String, liege: String) -> bool:
	return _effective_liege(cid) == liege and _effective_vassal_type(cid) != "protectorate"


## 玩家对某国是否可发起要求（好感度 >80，仅玩家侧判定）
func can_require_favor(target: String) -> bool:
	return player_favor.get(target, 0.0) > REQUIRE_FAVOR_MIN


## 玩家（或 AI）对 target 当前可用的通用 CB 列表（引擎只判 CB 条件；战争状态由 start_play 兜底）
func get_available_cbs(actor: String, target: String) -> Array:
	var out: Array = []
	if not _ensure_cbs():
		return out
	var cult := country_culture(actor)
	for c in _cb_list:
		var cid: String = str(c.get("id", ""))
		# 联合统治（事件 CB）：仅「要求联合统治」被拒获得 1 年 CB 后可用（Master 8/13）
		if cid == "personal_union":
			if has_cb(actor, target, "personal_union"):
				out.append(c)
			continue
		if str(c.get("type", "general")) != "general":
			continue   # 其余特殊/事件 CB（威尔士起义/珀西叛乱）待事件系统
		match cid:
			"vassalize":
				# Master 8/14 修正：附庸化不是无条件可发——需好感>80「要求附庸」→ LLM 拒绝后获 1 年 CB 才可用
				if has_cb(actor, target, "vassalize"):
					out.append(c)
			"protectorate":
				# Master 8/14 修正：受保护国同理，需好感>80「要求成为受保护国」→ LLM 拒绝后获 1 年 CB 才可用
				if has_cb(actor, target, "protectorate"):
					out.append(c)
			"seize_leadership":
				if cult == "celtic" and country_culture(target) == "celtic":
					out.append(c)
			"independence":
				if _is_vassal_of(actor, target):
					out.append(c)   # Master 8/13：独立 CB 通用，附庸随时可独立；叛乱与否由 LLM 按好感度判断
			_:
				pass   # 收复失地/领土宣称/解放同族：需核心/宣称数据，数据就绪后补
	return out


## 授予 1 年要求 CB（要求被拒后）：vassalize / protectorate / personal_union
func grant_requirement_cb(actor: String, target: String, cb_id: String) -> Dictionary:
	cb_timers["%s:%s:%s" % [actor, target, cb_id]] = REQUIRE_CB_DURATION
	EventBus.tool_executed.emit("grant_requirement_cb", {"actor": actor, "target": target, "cb_id": cb_id, "months": REQUIRE_CB_DURATION})
	return {"ok": true, "actor": actor, "target": target, "cb_id": cb_id, "months": REQUIRE_CB_DURATION}


## 是否持有某 CB（计时 >0）
func has_cb(actor: String, target: String, cb_id: String) -> bool:
	return int(cb_timers.get("%s:%s:%s" % [actor, target, cb_id], 0)) > 0


## 每月 CB 计时 -1（_settle_month 调用）；归零清除
func _tick_cbs() -> void:
	var expired: Array[String] = []
	for key in cb_timers:
		cb_timers[key] = int(cb_timers[key]) - 1
		if int(cb_timers[key]) <= 0:
			expired.append(key)
	for key in expired:
		cb_timers.erase(key)


# ===== 引擎⑥ 局势（Master 8/14：进度条 0~100 + 5 阶段；玩家专属，事件增减，任务解锁条件）=====

## 懒加载局势表（situations.json）
func _ensure_situations() -> bool:
	if not _situation_list.is_empty():
		return true
	var f := FileAccess.open(SITUATIONS_PATH, FileAccess.READ)
	if f == null:
		push_warning("局势表加载失败: %s" % SITUATIONS_PATH)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary and data.get("situations") is Array):
		push_warning("局势表格式错误: %s" % SITUATIONS_PATH)
		return false
	_situation_list = data["situations"]
	return true


## 局势初始值（initial_stage 映射：I=10/II=30/III=50/IV=70/V=90；initial_zero 则从 0 起）
func _situation_initial(s: Dictionary) -> int:
	if bool(s.get("initial_zero", false)):
		return 0
	return [10, 30, 50, 70, 90][clampi(int(s.get("initial_stage", 1)) - 1, 0, 4)]


## 新档初始化：所有局势按初始值写入 situation_value
func _init_situations() -> void:
	if not _ensure_situations():
		return
	for s in _situation_list:
		var sid: String = str(s.get("id", ""))
		if sid != "":
			situation_value[sid] = _situation_initial(s)


## 取局势定义（无则 {}）
func get_situation(situation_id: String) -> Dictionary:
	if not _ensure_situations():
		return {}
	for s in _situation_list:
		if str(s.get("id", "")) == situation_id:
			return s
	return {}


## 玩家是否拥有该局势（scope_country 含玩家操作国；scope_high_king = 当前至高王；AI 无局势）
func player_owns_situation(situation_id: String) -> bool:
	var s := get_situation(situation_id)
	if s.is_empty():
		return false
	if bool(s.get("scope_high_king", false)):
		return player_country_id == high_king_id   # 动态拥有者：当前爱尔兰至高王（初始蒂龙）
	var scopes: Array = s.get("scope_country", [])
	return scopes.has(player_country_id)


## 设置/变更爱尔兰至高王（Master 8/14：初始蒂龙，诸部可夺取——引擎⑧ 完整选举机制接入时调用）
func set_high_king(cid: String) -> void:
	if high_king_id == cid:
		return
	high_king_id = cid
	# Master 8/14 修正：无论获得还是失去至高王，都无条件刷新局势面板——
	# 玩家获得 → 统一爱尔兰立即出现；玩家失去 → 立即消失（之前只在「仍拥有」时 emit，导致失去时残留）
	EventBus.situation_changed.emit("unify_ireland", get_situation_value("unify_ireland"))
	EventBus.organization_changed.emit(0)


## 局势当前值（0~100；未初始化补初始值）
func get_situation_value(situation_id: String) -> int:
	if not situation_value.has(situation_id):
		situation_value[situation_id] = _situation_initial(get_situation(situation_id))
	return int(situation_value[situation_id])


## 局势阶段（0~4，对应 I~V；value//20 但 100 归 V）
func get_situation_stage(situation_id: String) -> int:
	return clampi(floori(float(get_situation_value(situation_id)) / 20.0), 0, 4)


## 局势变化：仅玩家拥有者生效；clamp 0~100 + emit situation_changed（UI 即时刷新）
func change_situation(situation_id: String, delta: float) -> void:
	if not player_owns_situation(situation_id):
		return   # AI 无局势；玩家未拥有不生效
	var v := clampi(get_situation_value(situation_id) + int(delta), 0, 100)
	situation_value[situation_id] = v
	EventBus.situation_changed.emit(situation_id, v)


## 玩家拥有的局势列表（UI 面板显示用，深拷贝防篡改）
func get_player_situations() -> Array:
	var out := []
	if not _ensure_situations():
		return out
	for s in _situation_list:
		var sid: String = str(s.get("id", ""))
		if sid != "" and player_owns_situation(sid):
			out.append(s.duplicate(true))
	return out


# ===== 引擎⑦ 任务树（Master 8/14：玩家专属；程序判定 + LLM flag 兜底；三态：完成/可做/锁定）=====

## 懒加载任务表（missions.json）
func _ensure_missions() -> bool:
	if not _mission_list.is_empty():
		return true
	var f := FileAccess.open(MISSIONS_PATH, FileAccess.READ)
	if f == null:
		push_warning("任务表加载失败: %s" % MISSIONS_PATH)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary and data.get("missions") is Array):
		push_warning("任务表格式错误: %s" % MISSIONS_PATH)
		return false
	_mission_list = data["missions"]
	return true


## 取任务定义（无则 {}）
func get_mission(mission_id: String) -> Dictionary:
	if not _ensure_missions():
		return {}
	for m in _mission_list:
		if str(m.get("id", "")) == mission_id:
			return m
	return {}


## 玩家国家的任务列表（UI 渲染用）
func get_player_missions() -> Array:
	var out: Array = []
	if not _ensure_missions():
		return out
	for m in _mission_list:
		if str(m.get("country", "")) == player_country_id:
			out.append(m)
	return out


## 是否已完成（已领奖）
func is_mission_completed(mission_id: String) -> bool:
	return bool(completed_missions.get(mission_id, false))


## 前置任务是否全部完成（解锁判定）
func _mission_parents_done(m: Dictionary) -> bool:
	for p in m.get("parents", []):
		if not is_mission_completed(str(p)):
			return false
	return true


## 任务三态：completed（已完成/暗）/ available（前置完成+条件满足/金光可领）/ locked（其余/灰）
func mission_state(mission_id: String) -> String:
	var m := get_mission(mission_id)
	if m.is_empty():
		return "locked"
	if is_mission_completed(mission_id):
		return "completed"
	if not _mission_parents_done(m):
		return "locked"
	return "available" if _check_mission_requirements(m) else "locked"


## 任务 scope → 国家 id 列表（ireland_clan=爱尔兰诸部[政体tribal] / england_subject=英格兰的原附庸+受保护国[静态初始liege] / 其他=单个国家id）
func _mission_scope_ids(scope: String) -> Array:
	var out: Array = []
	match str(scope):
		"ireland_clan":
			for c in _country_list:
				if str(c.get("government", "")) == "tribal":
					out.append(str(c.get("id", "")))
		"england_subject":
			# 静态初始宗主（Master 8/14：抢走英格兰的附庸后，该附庸不再属于英格兰，
			# 故「附庸化英格兰一个原附庸」用初始 _country_liege 判定，而非运行时 _effective_liege）
			for c in _country_list:
				var cid: String = str(c.get("id", ""))
				if cid != "" and _country_liege(cid) == "England":
					out.append(cid)
		_:
			out.append(str(scope))
	return out


## 单条完成条件判定（Master 8/14：附庸化=附庸国+受保护国均算，subject 语义用「有宗主」判定）
func _check_mission_cond(cond: Dictionary) -> bool:
	if cond.has("subject_of"):
		var targets: Array = cond["subject_of"] if cond["subject_of"] is Array else [cond["subject_of"]]
		for t in targets:
			if _effective_liege(str(t)) != player_country_id:
				return false
		return true
	if cond.has("favor_greater_than"):
		var thr: float = float(cond["favor_greater_than"])
		if cond.has("target"):
			return player_favor.get(str(cond["target"]), 0.0) > thr
		# 无 target：玩家全部附庸（subject）平均好感 ≥ 阈值（群岛守护用）
		var favs: Array = []
		for c in _country_list:
			var cid: String = str(c.get("id", ""))
			if cid != "" and _effective_liege(cid) == player_country_id:
				favs.append(player_favor.get(cid, 0.0))
		if favs.is_empty():
			return false
		var total := 0.0
		for fv in favs:
			total += float(fv)
		return total / float(favs.size()) >= thr
	if cond.has("army_limit"):
		return get_army_cap(player_country_id) >= int(cond["army_limit"])
	if cond.has("vassalize_all"):
		for cid in _mission_scope_ids(str(cond["vassalize_all"])):
			if _effective_liege(cid) != player_country_id:
				return false
		return true
	if cond.has("vassalize_any"):
		for cid in _mission_scope_ids(str(cond["vassalize_any"])):
			if _effective_liege(cid) == player_country_id:
				return true
		return false
	if cond.has("situation"):
		var sid: String = str(cond["situation"])
		return player_owns_situation(sid) and get_situation_value(sid) >= int(cond.get("value_gte", 100))
	if cond.has("mission_completed"):
		return is_mission_completed(str(cond["mission_completed"]))
	if cond.has("flag_set"):
		return bool(mission_flags.get(str(cond["flag_set"]), false))
	return false   # alliance_with / war_goal 等未实现键（老同盟已改事件、进军爱尔兰已改附庸化）→ 不满足


## 任务 requirements 全判定（all 数组逐条）
func _check_mission_requirements(m: Dictionary) -> bool:
	var reqs: Variant = m.get("requirements", {})
	if not (reqs is Dictionary and reqs.get("all") is Array):
		return false
	for cond in reqs["all"]:
		if not (cond is Dictionary) or not _check_mission_cond(cond):
			return false
	return true


## 完成任务：校验可完成 → 落地奖励 → 标记完成 + emit（UI 三态刷新）
func complete_mission(mission_id: String) -> Dictionary:
	var m := get_mission(mission_id)
	if m.is_empty():
		return {"ok": false, "error": "任务不存在"}
	if is_mission_completed(mission_id):
		return {"ok": false, "error": "任务已完成"}
	if mission_state(mission_id) != "available":
		return {"ok": false, "error": "任务条件未满足或未解锁"}
	_grant_mission_rewards(m)
	completed_missions[mission_id] = true
	EventBus.mission_completed.emit(mission_id)
	return {"ok": true, "mission_id": mission_id}


## 落地任务奖励：reward_effects（grant_cb 限时 CB 统一 3 年 / prestige / gold）
func _grant_mission_rewards(m: Dictionary) -> void:
	var fx: Dictionary = m.get("reward_effects", {})
	if fx.has("prestige"):
		country_prestige[player_country_id] = maxf(0.0, country_prestige.get(player_country_id, 0.0) + float(fx["prestige"]))
	if fx.has("gold"):
		country_gold[player_country_id] = country_gold.get(player_country_id, 0.0) + float(fx["gold"])
	if fx.has("grant_cb"):
		var gc: Dictionary = fx["grant_cb"]
		var cbid: String = str(gc.get("cb", ""))
		var months: int = int(gc.get("duration_months", 36))
		for tid in _mission_scope_ids(str(gc.get("scope", ""))):
			cb_timers["%s:%s:%s" % [player_country_id, tid, cbid]] = months
			EventBus.tool_executed.emit("grant_mission_cb", {"actor": player_country_id, "target": tid, "cb_id": cbid, "months": months})


## 事件选项置位任务 flag（effects.flags，如老同盟缔结 → scotland_auld_alliance_done）
func set_mission_flag(flag: String) -> void:
	if flag == "":
		return
	mission_flags[flag] = true


# ===== 引擎⑥ 事件系统 + 临时修正（Master 8/13：历史/脉冲/随机三类 + [Root.*] 变量 + effects/modifiers）=====

## 懒加载事件表（events.json）
func _ensure_events() -> bool:
	if not _event_list.is_empty():
		return true
	var f := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_event_list = data.get("events", [])
	return not _event_list.is_empty()


## 取事件定义（无则 {}）
func get_event(event_id: String) -> Dictionary:
	if not _ensure_events():
		return {}
	for e in _event_list:
		if str(e.get("id", "")) == event_id:
			return e
	return {}


## 国家中文名 / 统治者 / 称号 / 完整称号（变量渲染用，仿 EU4 本地化）
func _country_cn(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("name", cid))
	return cid


func _country_ruler_cn(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("ruler_en", ""))
	return ""


func _country_title_cn(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("title", ""))
	return ""


func _country_full_title(cid: String) -> String:
	return "%s%s %s" % [_country_cn(cid), _country_title_cn(cid), _country_ruler_cn(cid)]


## 变量渲染（仿 EU4 [Root.GetName]）：Root=主角国，From=来源国（可选）；未知占位保留原样
func resolve_event_vars(text: String, root_cid: String, from_cid: String = "") -> String:
	var out := text
	out = out.replace("[Root.GetName]", _country_cn(root_cid))
	out = out.replace("[Root.GetRulerName]", _country_ruler_cn(root_cid))
	out = out.replace("[Root.GetRulerTitle]", _country_title_cn(root_cid))
	out = out.replace("[Root.GetFullTitle]", _country_full_title(root_cid))
	if from_cid != "":
		out = out.replace("[From.GetName]", _country_cn(from_cid))
		out = out.replace("[From.GetRulerName]", _country_ruler_cn(from_cid))
		out = out.replace("[From.GetFullTitle]", _country_full_title(from_cid))
	return out


## 该国某类型临时修正总和（army_cap / morale / income）
func country_event_modifier(cid: String, type: String) -> float:
	var total := 0.0
	for m in modifiers.get(cid, []):
		if str(m.get("type", "")) == type:
			total += float(m.get("value", 0.0))
	return total


func _add_modifier(affected_cid: String, type: String, value: float, months: int) -> void:
	if not modifiers.has(affected_cid):
		modifiers[affected_cid] = []
	modifiers[affected_cid].append({"type": type, "value": value, "months": maxi(months, 1)})


## 临时修正每月 -1；归零清除（_tick_events 调用）
func _tick_modifiers() -> void:
	for cid in modifiers:
		var keep: Array = []
		for m in modifiers[cid]:
			m["months"] = int(m["months"]) - 1
			if int(m["months"]) > 0:
				keep.append(m)
		modifiers[cid] = keep


## 日期是否已到（"年.月"；开局 1400.9）
func _date_reached(date: String) -> bool:
	var parts := date.split(".")
	if parts.size() < 2:
		return false
	return year * 12 + month >= int(parts[0]) * 12 + int(parts[1])


## 每月事件结算（_settle_month 调用）：历史/脉冲/随机 → 玩家排队逐个弹 / AI 按权重自动选
func _tick_events() -> void:
	_tick_modifiers()
	if not _ensure_events():
		return
	# 历史事件（日期到 + 未触发，一次性）
	for e in _event_list:
		if str(e.get("type", "")) != "historical":
			continue
		var eid: String = str(e.get("id", ""))
		if _fired_historical.get(eid, false):
			continue
		var t: Dictionary = e.get("trigger", {})
		if not _date_reached(str(t.get("date", ""))):
			continue
		_fired_historical[eid] = true
		_queue_or_auto(e, str(t.get("country", "")), str(t.get("from", "")))
	# 脉冲事件（month 锚定触发月，每年一次；可按 culture / government 限定，或 country 指定国）
	for e in _event_list:
		if str(e.get("type", "")) != "pulse":
			continue
		var eid: String = str(e.get("id", ""))
		var t: Dictionary = e.get("trigger", {})
		if int(t.get("month", 0)) != month:
			continue
		var key := "%d.%d" % [year, month]
		if str(_pulse_last.get(eid, "")) == key:
			continue
		_pulse_last[eid] = key
		if str(t.get("country", "")) != "":
			_queue_or_auto(e, str(t.get("country", "")), str(t.get("from", "")))
		else:
			for cid in army_count:
				if _event_applies(e, cid):
					_queue_or_auto(e, cid, str(t.get("from", "")))
	# 随机事件（每个国家按权重逐事件抽；每月可多档）
	for cid in army_count:
		for e in _event_list:
			if str(e.get("type", "")) != "random":
				continue
			var t: Dictionary = e.get("trigger", {})
			var w: int = int(t.get("weight", 0))
			if w <= 0 or not _event_applies(e, cid):
				continue
			if Dice.chance(clampf(float(w) / 100.0, 0.0, 1.0)):
				_queue_or_auto(e, cid, str(t.get("from", "")))
	# 局势事件（Master 8/14：玩家拥有局势时按权重随机触发；仅玩家，AI 无局势）
	for e in _event_list:
		if str(e.get("type", "")) != "situation":
			continue
		var st: Dictionary = e.get("trigger", {})
		var sid: String = str(st.get("situation", ""))
		if sid == "" or not player_owns_situation(sid):
			continue
		var sw: int = int(st.get("weight", 0))
		if sw <= 0:
			continue
		if Dice.chance(clampf(float(sw) / 100.0, 0.0, 1.0)):
			_queue_or_auto(e, player_country_id, str(st.get("from", "")))
	# 玩家有待处理事件 → 通知 UI 逐个显示
	if not player_event_queue.is_empty():
		EventBus.event_pending.emit()


## 国家政体（countries.json government）
func _country_government(cid: String) -> String:
	for c in _country_list:
		if c.get("id", "") == cid:
			return str(c.get("government", ""))
	return ""


## 事件是否适用于该国（trigger 的 culture / government 过滤）
func _event_applies(e: Dictionary, cid: String) -> bool:
	var t: Dictionary = e.get("trigger", {})
	var cult: String = str(t.get("culture", ""))
	if cult != "" and country_culture(cid) != cult:
		return false
	var gov: String = str(t.get("government", ""))
	if gov != "" and _country_government(cid) != gov:
		return false
	return true


## 事件入队：玩家排队显示；AI 按权重自动选
func _queue_or_auto(e: Dictionary, root_cid: String, from_cid: String) -> void:
	var eid: String = str(e.get("id", ""))
	if root_cid == "" or root_cid == player_country_id:
		player_event_queue.append({
			"event_id": eid, "root": root_cid if root_cid != "" else player_country_id, "from": from_cid,
		})
	else:
		_resolve_ai_event(e, root_cid)


## AI 按权重自动选选项并落地
func _resolve_ai_event(e: Dictionary, cid: String) -> void:
	var opts: Array = e.get("options", [])
	if opts.is_empty():
		return
	_apply_option_effects(cid, opts[_pick_weighted_option(opts)], str(e.get("id", "")))


## 加权随机选选项下标（AI 用；权重 0 永不选）
func _pick_weighted_option(opts: Array) -> int:
	var total := 0
	for o in opts:
		total += maxi(int(o.get("weight", 0)), 0)
	if total <= 0:
		return 0
	var r := Dice.d100() % total
	for i in opts.size():
		var w := maxi(int(opts[i].get("weight", 0)), 0)
		if r < w:
			return i
		r -= w
	return opts.size() - 1


## 落地选项效果（金币/威望/军队/好感/CB/发起博弈/临时修正；军队超上限由 _clamp_army_to_cap 收敛）
func _apply_option_effects(cid: String, option: Dictionary, event_id: String) -> void:
	var fx: Dictionary = option.get("effects", {})
	if fx.has("gold"):
		country_gold[cid] = country_gold.get(cid, 0.0) + float(fx["gold"])
	if fx.has("prestige"):
		country_prestige[cid] = maxf(0.0, country_prestige.get(cid, 0.0) + float(fx["prestige"]))
	if fx.has("army"):
		army_count[cid] = army_count.get(cid, 0) + int(fx["army"])
	if fx.has("favor"):
		var fv: Dictionary = fx["favor"]
		change_favor(str(fv.get("target", "")), float(fv.get("delta", 0.0)))
	if fx.has("cb"):
		grant_requirement_cb(cid, str(fx.get("cb_target", "")), str(fx["cb"]))
	if fx.has("start_play"):
		var sp: Dictionary = fx["start_play"]
		start_play(cid, str(sp.get("target", "")), str(sp.get("goal", "")), str(sp.get("cb", "")))
	# 引擎⑥-局势（Master 8/14）：effects.situations 落地，仅玩家拥有者生效
	for sit in fx.get("situations", []):
		change_situation(str(sit.get("id", "")), float(sit.get("delta", 0.0)))
	# 引擎⑦-任务（Master 8/14）：effects.flags 置位任务 flag（如老同盟「缔结」→ 完成【老同盟】任务）
	for fl in fx.get("flags", []):
		set_mission_flag(str(fl))
	for m in fx.get("modifiers", []):
		var mtarget: String = str(m.get("target", ""))
		_add_modifier(mtarget if mtarget != "" else cid, str(m.get("type", "")), float(m.get("value", 0.0)), int(m.get("months", 1)))
	_clamp_army_to_cap(cid)
	EventBus.event_resolved.emit(event_id)


## 玩家待处理事件队首（UI 显示用）；无则 {}
func peek_player_event() -> Dictionary:
	if player_event_queue.is_empty():
		return {}
	return player_event_queue[0]


## 玩家选择第 option_index 个选项 → 落地 → 若有下个事件继续通知
func resolve_player_event(option_index: int) -> Dictionary:
	if player_event_queue.is_empty():
		return {"ok": false, "error": "无待处理事件"}
	var cur: Dictionary = player_event_queue.pop_front()
	var e := get_event(str(cur.get("event_id", "")))
	var opts: Array = e.get("options", [])
	if option_index < 0 or option_index >= opts.size():
		return {"ok": false, "error": "选项越界"}
	var root: String = str(cur.get("root", ""))
	_apply_option_effects(root, opts[option_index], str(cur.get("event_id", "")))
	# 不在此重发 event_pending（UI 按 peek 队列自己驱动下一个显示，避免重复渲染）
	return {"ok": true, "event_id": cur.get("event_id", ""), "root": root}


## 防环（DAG 约束，Master 8/13 确认：宗主/附庸树应为有向无环，像 EU4 贸易图）：
## 建立 actor→target（actor 成为 target 宗主）前，若 target 已是 actor 的宗主祖先（沿宗主链上行能到 target）→ 会成环
func _would_create_liege_cycle(actor: String, target: String) -> bool:
	if actor == target:
		return true
	var cur := actor
	var seen := {}
	while cur != "":
		if cur == target:
			return true
		if seen.has(cur):
			return true   # 防御：已存在环（正常不应发生）
		seen[cur] = true
		cur = _effective_liege(cur)
	return false


## 校验宗主/附庸图是否成环（静态 + 运行时 DAG 校验；有环返回 true）
func liege_graph_has_cycle() -> bool:
	for c in _country_list:
		var cur: String = str(c.get("id", ""))
		var seen := {}
		while cur != "":
			if seen.has(cur):
				return true
			seen[cur] = true
			cur = _effective_liege(cur)
	return false


## 要求被同意 → 建立运行时关系（vassalize→附庸 / protectorate→受保护国 / personal_union→联合统治）
## 注：完整附庸税/战时立场等机制属引擎⑤，这里先落地关系数据层 + 发事件刷新 UI
func establish_requirement(actor: String, target: String, cb_id: String) -> Dictionary:
	match cb_id:
		"vassalize", "protectorate":
			if _would_create_liege_cycle(actor, target):
				return {"ok": false, "error": "建立该附庸关系会形成宗主/附庸环（DAG 约束）"}
			runtime_liege[target] = actor
			# 附庸税（Master 8/13）：附庸 -3 队上限 / 受保护国不扣；超上限直接降到上限
			runtime_vassal_type[target] = "feudal" if cb_id == "vassalize" else "protectorate"
			_clamp_army_to_cap(target)
			var rel: String = "vassal" if cb_id == "vassalize" else "protectorate"
			EventBus.diplomatic_relation_changed.emit(actor, target, rel)
			return {"ok": true, "relation": rel, "liege": actor}
		"personal_union":
			# 联合统治不是国家从属（不参与宗主树），无需防环
			runtime_union[target] = actor
			EventBus.diplomatic_relation_changed.emit(actor, target, "union")
			return {"ok": true, "relation": "union", "lead": actor}
	return {"ok": false, "error": "未知关系类型"}


## ---- 交战结算（Master 8/12：只在战争状态触发；盟友按同侧合并对敌）----

## 每月交战：按省分组 → 省内战解析（仅战争双方相遇才交战，和平/中立不参战）
func _resolve_battles() -> void:
	var by_province := {}
	for cid in army_position:
		var prov: String = army_position[cid]
		if not by_province.has(prov):
			by_province[prov] = []
		by_province[prov].append(cid)
	for prov in by_province:
		_resolve_province_battles(by_province[prov])


## 省内交战：按 (战争, 阵营) 分组，同一战争的两侧各自合并所有盟友，只交战双方
func _resolve_province_battles(list: Array) -> void:
	var war_groups := {}   # war_id -> {"A": [cid...], "B": [cid...]}
	for cid in list:
		var aff := _war_affiliation(cid)
		if aff.is_empty():
			continue   # 中立 / 未参战国：和平时期不参战
		var wid: int = int(aff["war_id"])
		if not war_groups.has(wid):
			war_groups[wid] = {"A": [], "B": []}
		war_groups[wid][aff["side"]].append(cid)
	for wid in war_groups:
		var side_a: Array = war_groups[wid]["A"]
		var side_b: Array = war_groups[wid]["B"]
		if side_a.is_empty() or side_b.is_empty():
			continue
		_resolve_battle_sides(side_a, side_b)


## 单场交战（两侧）：双方各投 D10，伤害 = max(两侧总士气) × 0.2 × (1 + 0.1 × 骰子)
## 侧总伤害按各军队占比分摊给盟友；士气归零走撤退/投降
func _resolve_battle_sides(side_a: Array, side_b: Array) -> void:
	var a_total: float = 0.0
	var b_total: float = 0.0
	for cid in side_a:
		a_total += get_total_morale(cid)
	for cid in side_b:
		b_total += get_total_morale(cid)
	var dmg_base: float = maxf(a_total, b_total) * BATTLE_FACTOR
	_apply_side_damage(side_a, dmg_base * (1.0 + DICE_MORALE * float(Dice.d10())), a_total)
	_apply_side_damage(side_b, dmg_base * (1.0 + DICE_MORALE * float(Dice.d10())), b_total)
	for cid in side_a:
		_handle_routed(cid)
	for cid in side_b:
		_handle_routed(cid)


## 按军队占比分摊侧总伤害（单军侧占比=1，与旧公式一致）
func _apply_side_damage(side: Array, dmg: float, side_total: float) -> void:
	for cid in side:
		var share: float = get_total_morale(cid) / maxf(side_total, 0.001)
		army_morale[cid] = get_morale(cid) - dmg * share


## 士气归零：战败 → 强制以首都为目标撤退（走行军推进，每月 2 格，非瞬移）；已在首都 → 即时自动投降标记
## Master 2026-08-13 纠正：之前是 army_position=首都 瞬移，应改为 army_order=首都 强制行军
func _handle_routed(cid: String) -> void:
	if get_morale(cid) > 0.0:
		return
	var cap: String = capital_province.get(cid, "")
	if cap.is_empty():
		return
	if army_position.get(cid, "") == cap:
		surrender_flag[cid] = true   # 已在首都战败 → 即时投降
	else:
		retreating[cid] = true       # 标记撤退中（命令锁定，AI/玩家不可中途改）
		army_order[cid] = cap        # 强制以首都为目标，走行军非瞬移


## 士气恢复：未投降军队每月恢复 20% 最大士气（上限 = 总士气）
func _apply_morale_recovery() -> void:
	for cid in army_count:
		if surrender_flag.get(cid, false):
			continue
		var max_m: float = get_total_morale(cid)
		army_morale[cid] = minf(get_morale(cid) + max_m * MORALE_RECOVER, max_m)


## ---- 引擎③-T4 围城（Master 8/12：驻留敌方省 + 每月破城 1/(fort+1) + 临时占领 + 地图刷新）----

## 围城破城概率（兵牌显示用）：非围城 0；无要塞 100%；有要塞 1/(fort+1)
func get_siege_chance(cid: String) -> float:
	var prov: String = army_position.get(cid, "")
	var owner: String = province_owner.get(prov, "")
	if owner.is_empty() or owner == cid or not _are_at_war(cid, owner):
		return 0.0
	var fort: int = int(province_buildings.get(prov, {}).get("fort", 0))
	return 1.0 if fort < 1 else 1.0 / float(fort + 1)


## 每月围城判定：驻留敌方省 → 标记围城 → Dice.chance(1/(fort+1)) 破城 → 临时占领
func _resolve_sieges() -> void:
	for cid in army_position:
		var prov: String = army_position[cid]
		var owner: String = province_owner.get(prov, "")
		if owner.is_empty() or owner == cid or not _are_at_war(cid, owner):
			siege_target[cid] = ""    # 非围城（本国/非敌省/中立）
			continue
		siege_target[cid] = prov      # 驻留敌方省：围城中
		var fort: int = int(province_buildings.get(prov, {}).get("fort", 0))
		var p: float = 1.0 if fort < 1 else 1.0 / float(fort + 1)
		if Dice.chance(p):
			_take_province(prov, cid, owner)


## 破城/临时占领：省份归属改攻方 + 敌首都破城即时投降标记（引擎④ 处理和约/割让）
## 引擎④-T4 ZoC 归属转变：province_owner 实时变更 → _enemy_zoc/_zoc_sources 随之翻转（破城后该要塞 ZoC 归攻方，友军通行、敌军受困）
func _take_province(prov: String, cid: String, prev_owner: String) -> void:
	province_owner[prov] = cid
	siege_target[cid] = ""
	if capital_province.get(prev_owner, "") == prov:
		surrender_flag[prev_owner] = true    # 敌方首都被攻破 → 无条件投降标记


## 首都沦陷计时：本方首都非本国所有 → 累计；收复清零；连续沦陷 ≥6 月 → 自动投降
func _update_capital_occupation() -> void:
	for cid in army_count:
		var cap: String = capital_province.get(cid, "")
		if cap.is_empty():
			continue
		if province_owner.get(cap, "") == cid:
			capital_lost_months[cid] = 0
		else:
			capital_lost_months[cid] = capital_lost_months.get(cid, 0) + 1
			if capital_lost_months[cid] >= CAPITAL_LOST_SURRENDER:
				surrender_flag[cid] = true


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


## 国家月收入：基础 5 + 该国所有省份经济建筑（farm/market/brothel）每级 0.3 ×（1 + 临时 income 修正，引擎⑥）
func get_country_income(cid: String) -> float:
	var inc := BASE_INCOME
	for province in province_owner:
		if province_owner[province] != cid:
			continue
		var b: Dictionary = province_buildings.get(province, {})
		inc += float(b.get("farm", 0)) * BUILDING_INCOME
		inc += float(b.get("market", 0)) * BUILDING_INCOME
		inc += float(b.get("brothel", 0)) * BUILDING_INCOME
	return inc * (1.0 + country_event_modifier(cid, "income"))


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


# ===== 引擎④-T4 ZoC 接入（Master 8/12：敌方要塞 ≥2 级覆盖自身+相邻圈，阻挡行军；破城后 ZoC 归属转变）=====

## 省份要塞等级（province_buildings[省].fort）
func _fort_level(prov: String) -> int:
	return int(province_buildings.get(prov, {}).get("fort", 0))


## 与 cid 交战的国家列表（引擎④-战争前置 wars 数据）
func _at_war_with(cid: String) -> Array:
	var out: Array = []
	for w in wars:
		var side_a: Array = w["attacker"]
		var side_b: Array = w["defender"]
		if side_a.has(cid):
			for e in side_b:
				if not out.has(e):
					out.append(e)
		elif side_b.has(cid):
			for e in side_a:
				if not out.has(e):
					out.append(e)
	return out


## cid 的 ZoC 源省份（要塞 ≥2 级 且 属于 cid）——只有 ≥2 级要塞产生 ZoC
func _zoc_sources(cid: String) -> Array:
	var out: Array = []
	for prov in province_owner:
		if province_owner[prov] == cid and _fort_level(prov) >= 2:
			out.append(prov)
	return out


## cid 的 ZoC 覆盖省（源要塞自身 + 相邻一圈）
func _zoc_provinces(cid: String) -> Dictionary:
	if not _ensure_adjacency():
		return {}
	var z := {}
	for src in _zoc_sources(cid):
		z[src] = true
		for nb in _adjacency.get(src, {}):
			z[nb] = true
	return z


## 对 cid 而言的敌方 ZoC（所有交战国的要塞 ZoC 并集；和平为空）
func _enemy_zoc(cid: String) -> Dictionary:
	var z := {}
	for enemy in _at_war_with(cid):
		var ez: Dictionary = _zoc_provinces(enemy)
		for p in ez:
			z[p] = true
	return z


## 省是否属于 cid 或其盟友（同国 / 同战争同侧）
func _is_side_owned(cid: String, prov: String) -> bool:
	var owner: String = province_owner.get(prov, "")
	if owner == "":
		return false
	return _are_allies(cid, owner)


## ZoC 进入规则（EU4 式，按步判断，from = 当前所在省）：
## 1) 己方/盟友省 → 可进（自家地不被敌方 ZoC 卡）
## 2) 敌方要塞省（≥2 级且交战）→ 可进（去围攻，先攻要塞清障）
## 3) 不在敌方 ZoC → 可进
## 4) 在敌方 ZoC 内 → 仅当 from 也不在敌方 ZoC 才可进（接敌逼近）；已在 ZoC 内则被围困（只能攻要塞或撤出）
func _can_enter_province(cid: String, prov: String, from: String) -> bool:
	if _is_side_owned(cid, prov):
		return true
	var owner: String = province_owner.get(prov, "")
	if owner != "" and _are_at_war(cid, owner) and _fort_level(prov) >= 2:
		return true
	var ez: Dictionary = _enemy_zoc(cid)
	if not ez.has(prov):
		return true
	return not ez.has(from)


## 覆盖 prov 的阻挡要塞（首个使 prov 处于敌方 ZoC 的 ≥2 级要塞；无则 ""）
func _zoc_source_for(prov: String, cid: String) -> String:
	if not _ensure_adjacency():
		return ""
	for enemy in _at_war_with(cid):
		for src in _zoc_sources(enemy):
			if src == prov or _adjacency.get(src, {}).has(prov):
				return src
	return ""


## ZoC 阻挡检测（AI 用）：前往 target 的最短路径上首个不可进入省 → 返回其阻挡要塞（先攻清障）；无阻挡返回 ""
func find_blocking_fort(cid: String, target: String) -> String:
	var from: String = army_position.get(cid, "")
	if from.is_empty():
		return ""
	var path := _shortest_path(from, target)
	if path.size() < 2:
		return ""
	for i in range(1, path.size()):
		var prov: String = path[i]
		if not _can_enter_province(cid, prov, path[i - 1]):
			return _zoc_source_for(prov, cid)
	return ""


# ===== 引擎④-T5 AI 军队状态机（Master 8/12：AI 军队行动走状态机，非 LLM）=====
## 状态：FREE 空闲 / MARCH_SIEGE 前往敌方首都 / SIEGING 围城中 / MARCH_RELIEF 回防解围 / REINFORCE 增援激战友军

## 该军队当前省是否有敌方军队（正在交战 → 驻留战斗，不打断）
func _in_battle_now(cid: String) -> bool:
	var prov: String = army_position.get(cid, "")
	if prov.is_empty():
		return false
	for enemy in _at_war_with(cid):
		if army_position.get(enemy, "") == prov:
			return true
	return false


## cid 的敌方首都（默认作战目标；无交战国返回 ""）
func _enemy_capital(cid: String) -> String:
	for w in wars:
		var side_a: Array = w["attacker"]
		var side_b: Array = w["defender"]
		var enemies: Array = []
		if side_a.has(cid):
			enemies = side_b
		elif side_b.has(cid):
			enemies = side_a
		else:
			continue
		if enemies.is_empty():
			return ""
		return capital_province.get(enemies[0], "")
	return ""


## 增援目标：友军所在且正与敌方交战（同省有敌兵）的省；无返回 ""
func _reinforce_target(cid: String) -> String:
	for w in wars:
		var side_a: Array = w["attacker"]
		var side_b: Array = w["defender"]
		var allies: Array = []
		var enemies: Array = []
		if side_a.has(cid):
			allies = side_a
			enemies = side_b
		elif side_b.has(cid):
			allies = side_b
			enemies = side_a
		else:
			continue
		for ally in allies:
			if ally == cid:
				continue
			var prov: String = army_position.get(ally, "")
			if prov.is_empty():
				continue
			for e in enemies:
				if army_position.get(e, "") == prov:
					return prov
	return ""


## 是否有友军正在战斗（有增援目标即视为有）
func _ally_in_battle(cid: String) -> bool:
	return _reinforce_target(cid) != ""


## AI 军队每月决策（在 _settle_month 内、行军前调用）：
## 停战→FREE；首都沦陷→解围（最高优先）；围城中→驻留；自由且友军激战→增援；默认→围敌方首都（ZoC 阻挡先攻要塞）
func _tick_ai_armies() -> void:
	for cid in army_count:
		if cid == player_country_id:
			continue   # 玩家军队由玩家 UI 控制
		if retreating.get(cid, false):
			continue   # 战败撤退中：保持强制回首都命令，AI 状态机不接管
		# 停战 / 已投降 → 回 FREE 原地待命
		if not _in_war(cid) or surrender_flag.get(cid, false):
			ai_army_state[cid] = "FREE"
			army_order[cid] = ""
			continue
		# 正在交战 → 驻留该省继续战斗（不打断）
		if _in_battle_now(cid):
			army_order[cid] = ""
			continue
		# 持续围城：已在敌方省驻留且破城判定进行中 → 不动
		if ai_army_state.get(cid, "") == "SIEGING" and siege_target.get(cid, "") != "":
			army_order[cid] = ""
			continue
		var cap: String = capital_province.get(cid, "")
		var cap_lost: bool = not cap.is_empty() and province_owner.get(cap, "") != cid
		var target := ""
		if cap_lost:
			# ① 本方首都沦陷 → 解围（最高优先）
			ai_army_state[cid] = "MARCH_RELIEF"
			target = cap
		elif _ally_in_battle(cid):
			# ② 自由且友军正在战斗 → 增援
			ai_army_state[cid] = "REINFORCE"
			target = _reinforce_target(cid)
		else:
			# ③ 默认 → 围敌方首都（ZoC 阻挡则先攻要塞清障）
			ai_army_state[cid] = "MARCH_SIEGE"
			target = _enemy_capital(cid)
			var blk := find_blocking_fort(cid, target)
			if blk != "":
				target = blk
		if target == army_position.get(cid, ""):
			ai_army_state[cid] = "SIEGING"   # 已到达目标 → 围城（驻留，破城判定交给 _resolve_sieges）
			army_order[cid] = ""
		else:
			army_order[cid] = target


## 某国军队在 max_steps 步可达的省份（不含自身；陆/海不区分——Master 定：邻接线即道路，海峡可通行）。
## 引擎④-T4 ZoC：战争时敌方要塞 ZoC 禁行（可进敌方要塞围攻）；和平无 ZoC
func get_reachable_provinces(cid: String, max_steps: int = ARMY_MOVE_STEPS) -> Array:
	if not _ensure_adjacency():
		return []
	var from: String = army_position.get(cid, "")
	if from.is_empty():
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
			if visited.has(nxt) or not _can_enter_province(cid, nxt, prov):
				continue
			visited[nxt] = true
			reached[nxt] = true
			frontier.append([nxt, d + 1])
	return reached.keys()


## BFS 可达树：{可达省: 父省}（含 1 步邻居 parent=起点），用于地图画合法移动线（沿邻接线条）。
## 陆/海不区分；引擎④-T4 ZoC：战争时敌方要塞 ZoC 禁行（可进敌方要塞围攻）
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
			if visited.has(nxt) or not _can_enter_province(cid, nxt, prov):
				continue
			visited[nxt] = true
			tree[nxt] = prov
			frontier.append([nxt, d + 1])
	return tree


## 移动合法性：目标在 2 格可达内即合法；战争时被敌方要塞 ZoC 阻挡 → 明确报错（需先攻要塞）
func can_move_to(cid: String, target: String) -> Dictionary:
	if target == army_position.get(cid, ""):
		return {"ok": true, "reason": "原地"}
	if not get_reachable_provinces(cid, ARMY_MOVE_STEPS).has(target):
		var from: String = army_position.get(cid, "")
		if not _can_enter_province(cid, target, from):
			return {"ok": false, "reason": "被敌方要塞 ZoC 阻挡，需先攻占要塞"}
		return {"ok": false, "reason": "超出可移动范围（每月 2 格）"}
	return {"ok": true, "reason": ""}


## 下移动令（玩家只能控制自己的军队；月中随时可改，月末推进）
func issue_order(cid: String, target: String) -> Dictionary:
	if cid != player_country_id:
		return {"ok": false, "error": "只能控制自己的军队"}
	if retreating.get(cid, false):
		return {"ok": false, "error": "军队正在强制撤退回首都，无法下达新命令"}
	var chk := can_move_to(cid, target)
	if not chk.get("ok", false):
		return {"ok": false, "error": chk.get("reason", "")}
	army_order[cid] = target
	return {"ok": true, "order": target}


## 公开路径查询（ZoC 感知的 BFS 最短路径），供地图画命令路线。
## 注意：勿命名 get_path_to（与 Node 内置方法冲突，签名不匹配会编译报错）
func get_army_path(cid: String, target: String) -> Array:
	var from: String = army_position.get(cid, "")
	if from.is_empty():
		return []
	return _shortest_path_zoc(cid, from, target)


## BFS 最短路径（陆/海不区分，忽略 ZoC）；无路径返回 []
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


## ZoC 感知最短路径（战争时行军用）：每步须可进入（敌方 ZoC 禁行；可进敌方要塞围攻）。
## 和平无 ZoC → 等价于 _shortest_path。被阻挡（目标不可达）返回 []
func _shortest_path_zoc(cid: String, from: String, to: String) -> Array:
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
			if visited.has(nxt) or not _can_enter_province(cid, nxt, cur):
				continue
			var np: Array = path.duplicate()
			np.append(nxt)
			if nxt == to:
				return np
			visited[nxt] = true
			frontier.append(np)
	return []


## 返回省份刷新（_settle_month 调用，Master 8/13 补全规则）：返回省份本身落入敌方 ZoC → 自动清除
func _refresh_return_provinces() -> void:
	for cid in army_position:
		var rp: String = return_province.get(cid, "")
		if rp == "":
			continue
		if _enemy_zoc(cid).has(rp):
			return_province[cid] = ""   # 返回省份已被敌方 ZoC 覆盖 → 清除


## 月末推进：各国沿命令朝目标走最多 2 格；到达后清除命令；返回省份仅离开非 ZoC 省时更新。
## 引擎④-T4 ZoC：战争时走 ZoC 感知路径，被敌方要塞阻挡 → 原地待命（AI 应改目标先攻要塞；玩家 UI 已拦截）
func _advance_army() -> void:
	for cid in army_position:
		var target: String = army_order.get(cid, "")
		if target.is_empty():
			continue
		var from: String = army_position[cid]
		if target == from:
			army_order[cid] = ""
			continue
		var path := _shortest_path_zoc(cid, from, target)
		if path.size() < 2:
			continue
		var steps := mini(path.size() - 1, ARMY_MOVE_STEPS)
		var new_pos: String = path[steps]
		if not _enemy_zoc(cid).has(from):
			return_province[cid] = from   # 仅离开非 ZoC（安全）省时更新返回省份（Master 8/13 补全）
		army_position[cid] = new_pos
		if new_pos == target:
			army_order[cid] = ""
		if retreating.get(cid, false) and army_position[cid] == capital_province.get(cid, ""):
			retreating[cid] = false   # 已撤回首都 → 撤退结束，命令解锁
