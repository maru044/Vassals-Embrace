extends SceneTree
## 多工具并发演示测试（Master 8/15 v2）：LLM 一次返回 <content> 标签正文 + 2 个数据工具（modify_favor + sign_peace）
## 验证：response_parser 正则提取 <content> 正文 → tool_executor 逐个执行 → 全部落地
## 运行：godot --headless --path . --script res://tests/test_multi_tool.gd

const RESULT_PATH := "user://test_multi_tool_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	# 工具执行走 autoload 单例 GameManager（tool_executor 内部直接引用），必须用同一实例初始化状态
	var gm: Node = root.get_node("/root/GameManager")
	await process_frame
	# 初始化玩家 + 战争（sign_peace 需要战争存在）
	gm.set("player_country_id", "England")
	gm.set("army_count", {"England": 10, "Scotland": 6})
	gm.set("country_prestige", {"England": 60.0, "Scotland": 40.0})
	gm.call("declare_war", "England", "Scotland", "vassalize")

	# 模拟 LLM 一次返回：content 字段含 <content> 标签正文 + 2 个数据 tool_calls（新机制：正文不靠工具）
	var body := {
		"choices": [{"message": {"role": "assistant", "content": "<thinking>（检定通过）</thinking>\n<content>（苏格兰公主）呜…愿赌服输，从今往后你就是我的主人了。</content>", "tool_calls": [
			{"id": "c1", "type": "function", "function": {"name": "modify_favor", "arguments": "{\"target_id\":\"Scotland\",\"delta\":5}"}},
			{"id": "c2", "type": "function", "function": {"name": "sign_peace", "arguments": "{\"war_id\":1,\"winner_side\":\"A\",\"terms\":[{\"type\":\"vassalize\",\"target\":\"Scotland\"}]}"}},
		]}}]
	}
	# ① response_parser 解析：保留 2 个 tool_calls + 正则提取 <content> 正文（并分离 CoT）
	var parser: GDScript = load("res://scripts/llm/response_parser.gd")
	var parsed: Dictionary = parser.parse_response(body)
	var calls: Array = parsed.get("tool_calls", [])
	out.append("parse_response 保留全部 tool_calls = 2: %s" % (calls.size() == 2))
	out.append("parse_tool_call[0] = modify_favor: %s" % (str(parser.parse_tool_call(calls[0]).get("name", "")) == "modify_favor"))
	out.append("parse_tool_call[1] = sign_peace: %s" % (str(parser.parse_tool_call(calls[1]).get("name", "")) == "sign_peace"))
	out.append("正文标签提取成功: %s" % (str(parsed.get("content", "")) == "（苏格兰公主）呜…愿赌服输，从今往后你就是我的主人了。"))
	out.append("CoT 分离成功: %s" % str(parsed.get("cot", "")).contains("检定通过"))

	# ② tool_executor 逐个执行（模拟 chat_ui 的 for 循环）：2 个数据工具全部落地
	var tool_node: Node = load("res://scripts/llm/tool_executor.gd").new()
	root.add_child(tool_node)
	await process_frame
	var executed: Array[String] = []
	for tc in calls:
		var call: Dictionary = parser.parse_tool_call(tc)
		var tname: String = str(call.get("name", ""))
		var res: Dictionary = tool_node.call("execute", tname, call.get("arguments", {}))
		executed.append("%s:%s" % [tname, "ok" if res.get("ok", false) else "fail"])
	out.append("2 个数据工具全部执行成功: %s" % (executed == ["modify_favor:ok", "sign_peace:ok"]))
	# 容错：submit_dialogue 已从 TOOLS 移除，但 execute 保留兼容分支（旧回复残留调用不报错）
	var compat_res: Dictionary = tool_node.call("execute", "submit_dialogue", {"content": "旧回复残留"})
	out.append("submit_dialogue 容错分支仍可用: %s" % compat_res.get("ok", false))

	# ③ 引擎落地验证：好感变化 + 附庸关系建立（autoload 单例，与工具执行同源）
	var favor: float = gm.get("player_favor").get("Scotland", 0.0)
	out.append("好感度落地（+5）: %s" % (favor == 5.0))
	var liege: String = gm.call("effective_liege", "Scotland")
	out.append("附庸关系落地（Scotland → England）: %s" % (liege == "England"))
	out.append("战争结束（sign_peace 后 wars=0）: %s" % ((gm.get("wars") as Array).size() == 0))

	out.append("MULTI_TOOL_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
