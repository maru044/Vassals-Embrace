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

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit(0)
