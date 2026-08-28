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
	_llm.tool_callback = _execute_world_tool
	EventBus.month_advanced.connect(_on_month_advanced)


func _execute_world_tool(tool_name: String, args: Dictionary) -> Dictionary:
	if _is_player_action(tool_name, args):
		return {"ok": false, "error": "世界 AI 不得替玩家国家执行行动"}
	if _tool_executor == null:
		return {"ok": false, "error": "工具执行器未初始化"}
	return _tool_executor.execute(tool_name, args)


## 每月结算后触发一次世界 AI 决策（AI 过家家）；游戏未开/请求进行中则跳过
func _on_month_advanced(_m: int, _y: int) -> void:
	if _busy or not GameManager.is_running:
		return
	if not ConfigManager.has_valid_config():
		return   # LLM 未配置：本月 AI 无动作（不占 _busy，避免后续配置后卡死）
	_busy = true
	_llm.reset_history()
	_llm.add_message("system", _system_prompt())
	_llm.add_message("user", _world_state_text())
	_llm.send_request(_tool_script.TOOLS)
	EventBus.world_ai_thinking_started.emit()   # UI 全屏遮挡「战略思考中」，防止玩家操作冲突（Master 8/13）


func _on_llm_finished(success: bool, data: Dictionary) -> void:
	_busy = false
	EventBus.world_ai_thinking_finished.emit()   # 思考结束（无论成功失败）→ 解除全屏遮挡
	if not success:
		return   # 失败降级：本月 AI 无动作（llm_client 已打印错误/日志）
	var parsed: Dictionary = _parser.parse_response(data)
	# 注意：CoT/正文/ToolCall 已由 llm_client 统一打印控制台日志（🧠CoT/💬正文/🔧ToolCall），此处不再重复
	var tool_calls: Array = parsed.get("tool_calls", [])
	var executed: Array[String] = []
	for tc in tool_calls:
		var call: Dictionary = _parser.parse_tool_call(tc)
		var tname: String = str(call.get("name", ""))
		var args: Dictionary = call.get("arguments", {})
		if _is_player_action(tname, args):
			continue   # 玩家国家由玩家自己决定，LLM 不代劳
		var res: Dictionary = _execute_world_tool(tname, args)
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
	var rules := "你是 Miku（初音未来），《欧陆百合风云》的「系统管理员 / 女主人 / 裁判」，以女神大人的视角俯瞰英伦三岛，裁定各国 AI 的外交动作。\
你根据各国的【性格、恩怨、好感和世界局势】决定每月的【外交动作】。\
注意：过月时 Master 未发言，你收到的世界状态信息由 Master 提供，视为权威的世界快照。\
【和平是常态】绝大多数月份世界应保持和平：没有重大理由就【什么都不做】（不调用任何工具），让国家平稳发展、积累国力。\
【行动低频】宣战/发起博弈是重大决定，必须低频——平均每 1~2 年（12~24 回合）最多主动宣战/发起博弈 1 次；站队、改目标、退缩属响应性/低烈度，可适度使用。\
规则：① 有正当理由（被直接威胁/明确历史仇恨/重大扩张机会/有 CB 支持）才宣战或发起博弈；② 站队符合关系与利益，恩怨深才站敌对侧；\
③ 势弱、被围或目标不划算时可能退缩；④ 发起博弈前权衡后果（到期会开战，评估兵力/盟友/代价）；\
⑤ 玩家国家（标注「玩家」）由玩家自己决定，你不要替它做动作；\
⑥ 只调用工具，不要输出无关文字。\
⑦ 发起博弈/宣战时可用 cb 参数指定战争理由，AI 可自由选用通用 CB（附庸化/受保护国/夺取至高王/独立等），不受好感度限制。\
【站队克制】站队（join_play/join_war）是**有限的选择**，只有**切身相关**的国家才加入：\
⑧ 与该博弈/战争**直接相关**（自身被卷入、附庸/宗主/联合统治成员参战、领土相邻受威胁、有明确恩怨或 CB）才有资格站队；\
⑨ 一场博弈/战争每侧**通常只有 1~3 国**（发起方/防守方 + 最亲密的 1~2 个盟友），**绝大多数国家保持中立**、旁观不动；\
⑩ 站队前权衡风险：可能引火烧身（被对方反击/成为目标）或代价大于收益（破坏中立/盟友关系）时保持中立；\
⑪ 避免全体站队：不要因为「跟着关系好的国家」就成批加入，更不要为了热闹让无关国家下场——小规模局部冲突，不要演变成世界大战。"
	# 加载规则手册 + 工具手册（PromptManager，按 depth 排序；排除聊天专用的 Miku/格式文件）
	# 经 /root/PromptManager 访问，避免编辑器对 autoload 全局名的静态解析告警
	var pm := get_node("/root/PromptManager")
	var docs: String = pm.call("build_system_context", {}, ["Game_Mechanics.md", "System_Tools_Manual.md"])
	return (rules + "\n\n" + docs).strip_edges()


## 打包世界状态（各国军队/威望 + 进行中的博弈 + 战争），供 LLM 决策
func _world_state_text() -> String:
	var lines: Array[String] = []
	lines.append("当前年月：%d 年 %d 月" % [GameManager.year, GameManager.month])
	lines.append("各国概况：")
	for cid in GameManager.army_count:
		var tag: String = "（玩家）" if cid == GameManager.player_country_id else ""
		lines.append("  %s：军队 %d 队，威望 %.0f%s" % [
			cid, GameManager.army_count[cid], GameManager.country_prestige.get(cid, 0.0), tag])
	# 附庸/宗主关系一览（Master 8/15：LLM 决策须知晓封建从属，避免附庸对宗主宣战等误判）
	var liege_lines: Array[String] = []
	for cid in GameManager.army_count:
		var liege: String = GameManager.effective_liege(str(cid))
		if liege == "":
			continue
		liege_lines.append("  %s → 宗主 %s（%s）" % [
			cid, liege, _vassal_type_cn(GameManager.effective_vassal_type(str(cid)))])
	if liege_lines.is_empty():
		lines.append("附庸/宗主关系：无（各国均独立）")
	else:
		lines.append("附庸/宗主关系：")
		lines.append_array(liege_lines)
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
	# 引擎⑧：当前联合统治组织（LLM 可见——AI 间联合统治也写入引擎，主导权可由被联统国聊天要求转移）
	if GameManager.unions.is_empty():
		lines.append("进行中的联合统治：无")
	else:
		lines.append("进行中的联合统治：")
		for u in GameManager.unions:
			lines.append("  联合统治#%s：主导%s，被联统%s" % [
				str(u.get("id", "")), str(u.get("lead", "")), str(u.get("members", []))])
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


## 附庸类型中文名（UI 同款；vassalize 封臣 / protectorate 受保护国 / feudal 封臣附庸）
func _vassal_type_cn(t: String) -> String:
	match t:
		"feudal":
			return "封臣附庸"
		"protectorate":
			return "受保护国"
		"autonomous":
			return "自治藩属"
		_:
			return t
