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

	# ① PREFILL 常量：应包含 <thinking>（劫持原生思维链）
	var prefill: String = str(client.get("PREFILL_MAGIC"))
	out.append("PREFILL_MAGIC contains <thinking>: %s" % prefill.contains("<thinking>"))

	# ② reset_history / add_message
	client.call("reset_history")
	client.call("add_message", "user", "测试消息")
	out.append("history size 1: %s" % (int(client.get("history").size()) == 1))

	# ③ 成功响应：_on_request_completed(200) → request_finished(true) + assistant 带 tool_calls 入历史
	var body := JSON.stringify({
		"choices": [{"message": {"role": "assistant", "content": "思考正文", "tool_calls": [
			{"id": "call_1", "function": {"name": "submit_dialogue", "arguments": "{\"content\":\"你好\"}"}},
		]}}]
	}).to_utf8_buffer()
	var holder1 := {"ok": false}
	client.request_finished.connect(func(s: bool, _r: Dictionary) -> void: holder1["ok"] = s)
	client.call("_on_request_completed", 0, 200, PackedStringArray(), body)
	out.append("success -> finished(true): %s" % holder1["ok"])
	var hist: Array = client.get("history")
	out.append("history assistant has tool_calls: %s" % (hist.size() == 2 and (hist.back() as Dictionary).has("tool_calls")))

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

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit(0)
