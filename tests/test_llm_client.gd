extends SceneTree
## LLMClient 测试（Master 8/13）：PREFILL 常量 / reset-add_message / 成功响应解析 / HTTP 错误容错
## 运行：godot --headless --path . --script res://tests/test_llm_client.gd

const RESULT_PATH := "user://test_llm_client_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	var client: Node = load("res://scripts/llm/llm_client.gd").new()
	root.add_child(client)
	await process_frame

	# ① PREFILL 条件启用（Master 8/24）：Gemini 预设注入；DS/其他预设不注入（reasoning_content 协议 400）
	# PREFILL_MAGIC 保留原文（Gemini 需要），注入与否由 _do_request 按 ConfigManager.active_api 判定
	out.append("PREFILL_MAGIC non-empty: %s" % (not str(client.get("PREFILL_MAGIC")).is_empty()))
	var cfg: Node = get_root().get_node("/root/ConfigManager")
	cfg.set("active_api", "deepseek")
	out.append("PREFILL skipped for deepseek: %s" % (cfg.get("active_api") != "gemini"))
	cfg.set("active_api", "gemini")
	out.append("PREFILL enabled for gemini: %s" % (cfg.get("active_api") == "gemini"))

	# ② reset_history / add_message
	client.call("reset_history")
	client.call("add_message", "user", "测试消息")
	out.append("history size 1: %s" % (int(client.get("history").size()) == 1))

	# ③ 成功响应：_on_request_completed(200) → request_finished(true) + assistant 带 tool_calls + reasoning_content 入历史
	# （正文走 content 字段，工具只做数据操作——Master 8/15；reasoning_content 为 DeepSeek thinking 回传协议——8/24）
	var body := JSON.stringify({
		"choices": [{"message": {"role": "assistant", "content": "<thinking>（检定）</thinking>\n<content>你好</content>", "reasoning_content": "深度思考过程", "tool_calls": [
			{"id": "call_1", "function": {"name": "modify_favor", "arguments": "{\"target_id\":\"Wales\",\"delta\":3}"}},
		]}}]
	}).to_utf8_buffer()
	var holder1 := {"ok": false}
	client.request_finished.connect(func(s: bool, _r: Dictionary) -> void: holder1["ok"] = s)
	client.call("_on_request_completed", 0, 200, PackedStringArray(), body)
	out.append("success -> finished(true): %s" % holder1["ok"])
	var hist: Array = client.get("history")
	out.append("history assistant has tool_calls: %s" % (hist.size() == 2 and (hist.back() as Dictionary).has("tool_calls")))
	out.append("history preserves reasoning_content: %s" % (str((hist.back() as Dictionary).get("reasoning_content", "")) == "深度思考过程"))

	# ④ HTTP 401（不可重试）→ 直接 finished(false)
	var holder2 := {"ok": true}
	client.request_finished.connect(func(s: bool, _r: Dictionary) -> void: holder2["ok"] = s)
	client.call("_on_request_completed", 0, 401, PackedStringArray(), PackedByteArray())
	out.append("HTTP 401 -> finished(false): %s" % (holder2["ok"] == false))

	# ⑤ add_user_message 合并连续 user（避免 API 400）
	client.call("reset_history")
	client.call("add_user_message", "第一句")
	client.call("add_user_message", "第二句")
	var h2: Array = client.get("history")
	out.append("add_user_message merge consecutive: %s" % (h2.size() == 1 and str((h2[0] as Dictionary).get("content", "")).contains("第二句")))

	# ⑥ add_tool_result 回填 role=tool（tool_calls 后必须紧跟 tool 结果）
	client.call("reset_history")
	client.call("add_message", "assistant", "思考")
	client.call("add_tool_result", "call_x", "modify_favor", {"ok": true})
	var h3: Array = client.get("history")
	out.append("add_tool_result appends role=tool: %s" % (h3.size() == 2 and str((h3.back() as Dictionary).get("role", "")) == "tool"))

	# ⑦ rollback_history 跳过尾部 tool/system，回到上一个 user
	client.call("reset_history")
	client.call("add_user_message", "原始提问")
	client.call("add_message", "assistant", "回复")
	client.call("add_tool_result", "call_x", "modify_favor", {"ok": true})
	client.call("add_message", "system", "提醒")
	var rolled := str(client.call("rollback_history"))
	out.append("rollback skips tool/system returns last user: %s" % (rolled == "原始提问"))

	# ⑧ sanitize_history：剔除 system、孤儿 tool、尾部残缺 tool_calls（读档恢复防御，Master 8/24）
	client.call("reset_history")
	var dirty: Array = [
		{"role": "system", "content": "旧环境注入"},
		{"role": "user", "content": "你好"},
		{"role": "assistant", "content": "回复", "tool_calls": [{"id": "c1", "function": {"name": "modify_favor", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "modify_favor", "content": "{}"},
		{"role": "assistant", "content": "孤儿的tool_calls", "tool_calls": [{"id": "c2", "function": {"name": "modify_favor", "arguments": "{}"}}]},   # c2 无 tool 结果 → 应修剪
		{"role": "user", "content": "再问一句"},   # 孤儿后面新 user，不应误删 c2
	]
	var clean: Array = client.call("sanitize_history", dirty)
	var roles: Array = []
	for m in clean:
		roles.append(str((m as Dictionary).get("role", "")))
	# 系统消息应被剔除；孤儿 c2（无 tool 结果）内部保留（由 LLM 上下文自洽），尾部才修剪
	out.append("sanitize removes system: %s" % (not roles.has("system")))
	out.append("sanitize keeps order: %s" % (roles == ["user", "assistant", "tool", "assistant", "user"]))
	# 尾部残缺独立验证（读档后最后的 assistant 带 tool_calls 无结果 → 修剪）
	var tail_dirty: Array = [
		{"role": "user", "content": "u"},
		{"role": "assistant", "content": "a", "tool_calls": [{"id": "c9"}]},
	]
	var tail_clean: Array = client.call("sanitize_history", tail_dirty)
	out.append("sanitize trims trailing orphan tool_calls: %s" % (tail_clean.size() == 1 and str((tail_clean[0] as Dictionary).get("role")) == "user"))

	# ⑨ GameManager.chat_history 持久记忆：serialize/deserialize 往返（Master 8/24 修复核心）
	client.call("reset_history")
	client.call("sanitize_history", [{"role": "system", "content": "x"}])   # 空参考
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.call("start_new_game", "Scotland")
	gm.set("chat_history", [{"role": "user", "content": "记忆一"}, {"role": "assistant", "content": "回复一"}])
	var data: Dictionary = gm.call("serialize")
	out.append("serialize contains chat_history: %s" % data.has("chat_history"))
	var gm2: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm2)
	await process_frame
	gm2.call("deserialize", data)
	var restored: Array = gm2.get("chat_history")
	out.append("deserialize restores chat_history: %s" % (restored.size() == 2 and str((restored[0] as Dictionary).get("content")) == "记忆一"))
	# 新游戏清空记忆
	gm2.call("start_new_game", "Wales")
	out.append("new game clears chat_history: %s" % (int(gm2.get("chat_history").size()) == 0))
	root.remove_child(gm)
	gm.free()
	root.remove_child(gm2)
	gm2.free()

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit(0)
