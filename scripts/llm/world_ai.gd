extends Node
## 引擎④-T3：LLM 世界 AI 决策通道（Master 8/13 过家家模式）
## AI 国家的一切外交决策由 LLM 扮演：每月结算后把世界状态喂给 LLM，LLM 用已注册工具
## （declare_war / join_war / start_play / join_play / set_play_goal / back_down）
## 决定 AI 动作（谁宣战、谁站队、谁退缩、提什么目标），引擎只执行 + 结算。
## 失败降级：LLM 未配置 / 超时 / 解析失败 → 本月 AI 无动作，不阻塞玩家。

const LLM_CLIENT_SCRIPT := "res://scripts/llm/llm_client.gd"
const RESPONSE_PARSER_SCRIPT := "res://scripts/llm/response_parser.gd"
const TOOL_EXECUTOR_SCRIPT := "res://scripts/llm/tool_executor.gd"

var _llm: Node = null
var _parser: GDScript = null
var _tool_script: GDScript = null
var _tool_executor: Node = null
var _busy := false


func _ready() -> void:
	_llm = Node.new()
	_llm.set_script(load(LLM_CLIENT_SCRIPT))
	add_child(_llm)
	_llm.request_finished.connect(_on_llm_finished)
	_parser = load(RESPONSE_PARSER_SCRIPT)
	_tool_script = load(TOOL_EXECUTOR_SCRIPT)
	_tool_executor = Node.new()
	_tool_executor.set_script(_tool_script)
	add_child(_tool_executor)
	EventBus.month_advanced.connect(_on_month_advanced)


## 每月结算后触发一次世界 AI 决策（AI 过家家）；游戏未开/请求进行中则跳过
func _on_month_advanced(_m: int, _y: int) -> void:
	if _busy or not GameManager.is_running:
		return
	_busy = true
	_llm.reset_history()
	_llm.add_message("system", _system_prompt())
	_llm.add_message("user", _world_state_text())
	_llm.send_request(_tool_script.TOOLS)


func _on_llm_finished(success: bool, data: Dictionary) -> void:
	_busy = false
	if not success:
		return   # 失败降级：本月 AI 无动作
	var parsed: Dictionary = _parser.parse_response(data)
	var tool_calls: Array = parsed.get("tool_calls", [])
	var executed: Array[String] = []
	for tc in tool_calls:
		var call: Dictionary = _parser.parse_tool_call(tc)
		var tname: String = str(call.get("name", ""))
		var args: Dictionary = call.get("arguments", {})
		if _is_player_action(tname, args):
			continue   # 玩家国家由玩家自己决定，LLM 不代劳
		var res: Dictionary = _tool_executor.execute(tname, args)
		executed.append("%s%s" % [tname, "✓" if res.get("ok", false) else "✗"])
	if not executed.is_empty():
		print("世界AI：", "、".join(executed))
		EventBus.tool_executed.emit("world_ai_batch", {"actions": executed})


## 防止 LLM 替玩家国家做动作（玩家自己决定自己的外交/宣战）
func _is_player_action(tname: String, args: Dictionary) -> bool:
	var pid := GameManager.player_country_id
	if pid.is_empty():
		return false
	var actor: String = ""
	match tname:
		"declare_war":
			actor = str(args.get("attacker", ""))
		"start_play":
			actor = str(args.get("initiator", ""))
		"join_war", "join_play":
			actor = str(args.get("country_id", ""))
	return actor == pid


func _system_prompt() -> String:
	return "你是《欧陆百合风云》的「世界意志」（上帝视角），扮演所有 AI 国家的统治者（各国公主）。\
你按她们的【性格、恩怨、好感和世界局势】决定每月的【外交动作】，只通过以下工具行动：\
start_play(发起博弈+战争目标)、join_play(加入博弈某侧)、set_play_goal(改目标)、back_down(退缩认怂)、\
declare_war(直接宣战)、join_war(加入战争某侧)。\
规则：① 有正当理由（仇恨/野心/被威胁/扩张机会）才宣战或发起博弈；② 站队符合关系与利益，恩怨深才站敌对侧；\
③ 势弱、被围或目标不划算时可能退缩；④ 不要每月无脑宣战，克制、合理、有戏剧性；\
⑤ 玩家国家（标注「玩家」）由玩家自己决定，你不要替它做动作；\
⑥ 本月没有合适动作就【什么都不做】（不调用任何工具）。只调用工具，不要输出无关文字。\
⑦ 发起博弈/宣战时可用 cb 参数指定战争理由，AI 可自由选用通用 CB（附庸化/受保护国/夺取至高王/独立等），不受好感度限制。"


## 打包世界状态（各国军队/威望 + 进行中的博弈 + 战争），供 LLM 决策
func _world_state_text() -> String:
	var lines: Array[String] = []
	lines.append("当前年月：%d 年 %d 月" % [GameManager.year, GameManager.month])
	lines.append("各国概况：")
	for cid in GameManager.army_count:
		var tag: String = "（玩家）" if cid == GameManager.player_country_id else ""
		lines.append("  %s：军队 %d 队，威望 %.0f%s" % [
			cid, GameManager.army_count[cid], GameManager.country_prestige.get(cid, 0.0), tag])
	var plays: Array = GameManager.get_active_plays()
	if plays.is_empty():
		lines.append("进行中的外交博弈：无")
	else:
		lines.append("进行中的外交博弈：")
		for p in plays:
			lines.append("  博弈#%s：%s(目标:%s) vs %s(目标:%s)，剩%s月，A方%s / B方%s" % [
				str(p.get("id", "")), str(p.get("initiator", "")), str(p.get("init_goal", "")),
				str(p.get("target", "")), str(p.get("targ_goal", "")),
				str(p.get("deadline", "")), str(p.get("sides", {}).get("A", [])), str(p.get("sides", {}).get("B", []))])
	if GameManager.wars.is_empty():
		lines.append("进行中的战争：无")
	else:
		lines.append("进行中的战争：")
		for w in GameManager.wars:
			lines.append("  战争#%s：A方%s vs B方%s" % [str(w.get("id", "")), str(w.get("attacker", [])), str(w.get("defender", []))])
	# 投降告知（Master 8/13：投降不自动结束战争/割地，和平条款全交 LLM 对话，只需让 LLM 知道谁投降了）
	var surrendered: Array[String] = []
	for cid in GameManager.army_count:
		if GameManager.surrender_flag.get(cid, false):
			surrendered.append(str(cid))
	if surrendered.is_empty():
		lines.append("已投降国家：无")
	else:
		lines.append("已投降国家（已无条件投降，可谈和平条款/割地）：%s" % ", ".join(surrendered))
	lines.append("请决定本月 AI 国家的外交动作（用工具；无事可做就什么都别调）。")
	return "\n".join(lines)
