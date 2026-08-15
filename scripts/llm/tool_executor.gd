extends Node
## 工具执行器（单 Agent）：定义工具 Schema，把 function calling 解析成引擎调用。
## 原则：所有状态改动经工具落地，引擎是唯一事实源。

const TOOLS: Array = [
	{
		"type": "function",
		"function": {
			"name": "modify_favor",
			"description": "调整玩家对某国的好感度",
			"parameters": {
				"type": "object",
				"properties": {
					"target_id": {"type": "string", "description": "目标国家 id（如 England / Wales）"},
					"delta": {"type": "integer", "description": "好感度增减量（简单互动成功+3/失败-3，中等成功+5，困难成功+10）"},
				},
				"required": ["target_id", "delta"],
			},
		},
	},
	# ---- 引擎④ 外交 / 战争（Master 8/13 过家家模式：AI 决策由 LLM 经工具落地）----
	{
		"type": "function",
		"function": {
			"name": "declare_war",
			"description": "国家宣战：attacker 对 defender 直接开战（引擎④战争）。一般先走外交博弈，LLM 认为时机成熟也可直接宣战。cb 为可选战争理由（通用 CB：reconquest/claim/liberation/vassalize/protectorate/seize_leadership/independence；AI 可自由选用，不受好感度限制）。",
			"parameters": {
				"type": "object",
				"properties": {
					"attacker": {"type": "string", "description": "宣战国 id（如 Scotland）"},
					"defender": {"type": "string", "description": "被宣战国 id（如 England）"},
					"cb": {"type": "string", "description": "战争理由 CB id（可选）"},
				},
				"required": ["attacker", "defender"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "join_war",
			"description": "国家加入某场战争的某侧（A=进攻方 / B=防守方），即战时并肩",
			"parameters": {
				"type": "object",
				"properties": {
					"country_id": {"type": "string", "description": "加入国家 id"},
					"war_id": {"type": "integer", "description": "战争 id"},
					"side": {"type": "string", "description": "阵营 A / B"},
				},
				"required": ["country_id", "war_id", "side"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "start_play",
			"description": "发起外交博弈：initiator 对 target 提战争目标（如 附庸化 / 吞并 X省 / 独立 / 联合统治），持续 2 个月，期间可站队/改目标/退缩。cb 为可选战争理由（通用 CB：reconquest/claim/liberation/vassalize/protectorate/seize_leadership/independence；AI 可自由选用，不受好感度限制）。",
			"parameters": {
				"type": "object",
				"properties": {
					"initiator": {"type": "string", "description": "发起国 id"},
					"target": {"type": "string", "description": "被发起国 id"},
					"goal": {"type": "string", "description": "进攻目标（如 附庸化 / 吞并 Lothian）；留空时用 cb 名"},
					"cb": {"type": "string", "description": "战争理由 CB id（可选）"},
				},
				"required": ["initiator", "target", "goal"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "join_play",
			"description": "国家加入某场外交博弈的某侧（A=发起方 / B=防守方），即战前站队",
			"parameters": {
				"type": "object",
				"properties": {
					"play_id": {"type": "integer", "description": "博弈 id"},
					"country_id": {"type": "string", "description": "站队国家 id"},
					"side": {"type": "string", "description": "阵营 A / B"},
				},
				"required": ["play_id", "country_id", "side"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "set_play_goal",
			"description": "博弈方修改自己的战争目标",
			"parameters": {
				"type": "object",
				"properties": {
					"play_id": {"type": "integer", "description": "博弈 id"},
					"country_id": {"type": "string", "description": "博弈方国家 id"},
					"goal": {"type": "string", "description": "新目标"},
				},
				"required": ["play_id", "country_id", "goal"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "back_down",
			"description": "某侧在外交博弈中退缩 → 对方不战而获目标，退缩方失威望",
			"parameters": {
				"type": "object",
				"properties": {
					"play_id": {"type": "integer", "description": "博弈 id"},
					"side": {"type": "string", "description": "退缩的阵营 A / B"},
				},
				"required": ["play_id", "side"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "sign_peace",
			"description": "签和平条约：议和双方谈妥条件后，由胜方经此工具落地条款并结束战争。winner_side 为和平赢家阵营（A=进攻方 / B=防守方）。战争分数由你（LLM）自行估算：占领敌方省份数量、敌方首都是否被攻破、敌方是否已投降（无条件）决定你能提多少条款——不能一次提出远超你军事优势的条款。玩家方战败求和建议由 AI 方裁决同意后以 AI 方为 winner_side 落地。",
			"parameters": {
				"type": "object",
				"properties": {
					"war_id": {"type": "integer", "description": "战争 id"},
					"winner_side": {"type": "string", "description": "和平赢家阵营 A / B"},
					"terms": {"type": "array", "description": "和平条款数组，每项 {type, target?, value?}：vassalize 附庸化 / protectorate 受保护国 / personal_union 联合统治 / annex 吞并（target=被吞国）/ independence 独立（target=独立方）/ province 割地（value=省名）/ gold 赔款（value=金额）/ release 释放附庸（value=附庸国）"},
				},
				"required": ["war_id", "winner_side", "terms"],
			},
		},
	},
	# ---- 引擎⑧ 联合统治（Master 8/14：被联统国 LLM 聊天要求成为主导国，攻受互换）----
	{
		"type": "function",
		"function": {
			"name": "transfer_union_lead",
			"description": "被联统国要求成为联合统治的主导国（攻受互换）：该国从被联统国变为主导国，原主导国变为被联统国。仅该国正处于联合统治且非主导时可用（对话中由被联统国公主提出、主导国同意后调用落地）。",
			"parameters": {
				"type": "object",
				"properties": {
					"country_id": {"type": "string", "description": "请求成为主导国的国家 id（被联统国）"},
				},
				"required": ["country_id"],
			},
		},
	},
	# Master 8/15：正文不再走 submit_dialogue 工具（LLM 自身行为不稳定），改走 <content> 标签 + 正则提取（参考女仆别墅项目）。
	# TOOLS 不再注册 submit_dialogue；execute() 保留容错分支，兼容旧历史/旧回复中的残留调用。
]


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"modify_favor":
			return _modify_favor(args)
		"declare_war":
			return _declare_war(args)
		"join_war":
			return _join_war(args)
		"start_play":
			return _start_play(args)
		"join_play":
			return _join_play(args)
		"set_play_goal":
			return _set_play_goal(args)
		"back_down":
			return _back_down(args)
		"sign_peace":
			return _sign_peace(args)
		"submit_dialogue":
			# 容错（Master 8/15）：旧历史/旧回复残留调用 → 仍回传正文，但新机制不再依赖
			return _submit_dialogue(args)
		"transfer_union_lead":
			return _transfer_union_lead(args)
		_:
			return {"ok": false, "error": "未知工具: %s" % tool_name}


func _modify_favor(args: Dictionary) -> Dictionary:
	var target_id: String = str(args.get("target_id", ""))
	var delta: int = args.get("delta", 0)
	GameManager.change_favor(target_id, float(delta))   # 落库玩家侧好感（即时生效 + 广播刷新）
	EventBus.tool_executed.emit("modify_favor", {"target_id": target_id, "delta": delta})
	return {"ok": true, "target_id": target_id, "delta": delta, "favor": GameManager.player_favor.get(target_id, 0.0)}


## 聊天正文输出容错（Master 8/15：新机制正文走 <content> 标签 + 正则提取；此分支仅兼容旧调用，引擎不落地）
func _submit_dialogue(args: Dictionary) -> Dictionary:
	var content := str(args.get("content", ""))
	EventBus.tool_executed.emit("submit_dialogue", {"content": content})
	return {"ok": true, "content": content}


## 引擎⑧：被联统国要求成为主导国（攻受互换；Master 8/14：LLM 聊天驱动，引擎只落地）
func _transfer_union_lead(args: Dictionary) -> Dictionary:
	var cid: String = str(args.get("country_id", ""))
	var res := GameManager.transfer_union_lead(cid)
	EventBus.tool_executed.emit("transfer_union_lead", {"country_id": cid, "result": res})
	return res


# ---- 引擎④ 外交 / 战争工具（过家家模式：AI 决策由 LLM 落地）----

func _declare_war(args: Dictionary) -> Dictionary:
	var attacker: String = str(args.get("attacker", ""))
	var defender: String = str(args.get("defender", ""))
	var cb: String = str(args.get("cb", ""))
	var res := GameManager.declare_war(attacker, defender, cb)
	EventBus.tool_executed.emit("declare_war", {"attacker": attacker, "defender": defender, "cb": cb})
	return res


func _join_war(args: Dictionary) -> Dictionary:
	var cid: String = str(args.get("country_id", ""))
	var war_id: int = args.get("war_id", 0)
	var side: String = str(args.get("side", ""))
	var res := GameManager.add_war_participant(cid, war_id, side)
	EventBus.tool_executed.emit("join_war", {"country_id": cid, "war_id": war_id, "side": side})
	return res


func _start_play(args: Dictionary) -> Dictionary:
	var initiator: String = str(args.get("initiator", ""))
	var target: String = str(args.get("target", ""))
	var goal: String = str(args.get("goal", ""))
	var cb: String = str(args.get("cb", ""))
	var res := GameManager.start_play(initiator, target, goal, cb)
	EventBus.tool_executed.emit("start_play", {"initiator": initiator, "target": target, "goal": goal, "cb": cb})
	return res


func _join_play(args: Dictionary) -> Dictionary:
	var play_id: int = args.get("play_id", 0)
	var cid: String = str(args.get("country_id", ""))
	var side: String = str(args.get("side", ""))
	var res := GameManager.join_play(play_id, cid, side)
	EventBus.tool_executed.emit("join_play", {"play_id": play_id, "country_id": cid, "side": side})
	return res


func _set_play_goal(args: Dictionary) -> Dictionary:
	var play_id: int = args.get("play_id", 0)
	var cid: String = str(args.get("country_id", ""))
	var goal: String = str(args.get("goal", ""))
	var res := GameManager.set_play_goal(play_id, cid, goal)
	EventBus.tool_executed.emit("set_play_goal", {"play_id": play_id, "country_id": cid, "goal": goal})
	return res


func _back_down(args: Dictionary) -> Dictionary:
	var play_id: int = args.get("play_id", 0)
	var side: String = str(args.get("side", ""))
	var res := GameManager.back_down(play_id, side)
	EventBus.tool_executed.emit("back_down", {"play_id": play_id, "side": side})
	return res


func _sign_peace(args: Dictionary) -> Dictionary:
	var war_id: int = args.get("war_id", 0)
	var winner_side: String = str(args.get("winner_side", ""))
	var terms: Array = args.get("terms", [])
	var res := GameManager.sign_peace(war_id, winner_side, terms)
	EventBus.tool_executed.emit("sign_peace", {"war_id": war_id, "winner_side": winner_side, "terms": terms})
	return res
