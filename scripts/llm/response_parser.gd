extends Node
class_name ResponseParser
## 响应解析：把 LLM 返回拆成 思考(CoT) / 正文 / 工具调用，带容错。

static func parse_response(data: Dictionary) -> Dictionary:
	## 返回 { cot, content, tool_calls }
	var result := {"cot": "", "content": "", "tool_calls": []}
	if not data.has("choices") or (data["choices"] as Array).is_empty():
		return result
	var message: Dictionary = data["choices"][0].get("message", {})

	# CoT：部分模型用 reasoning_content（如 deepseek-r1 风格）
	result["cot"] = message.get("reasoning_content", "")

	# 正文：分离 <thinking>...</thinking> 块（容错）
	var content: String = message.get("content", "")
	var ts := content.find("<thinking>")
	var te := content.find("</thinking>")
	if ts != -1 and te != -1 and te > ts:
		result["cot"] += "\n" + content.substr(ts + 11, te - ts - 11)
		content = content.substr(te + 12)
	result["content"] = content.strip_edges()

	# 工具调用
	if message.has("tool_calls"):
		result["tool_calls"] = message["tool_calls"]
	return result


static func parse_tool_call(tool_call: Dictionary) -> Dictionary:
	## 把单个 tool_call 解析为 { name, arguments }
	var fn: Dictionary = tool_call.get("function", {})
	return {
		"name": fn.get("name", ""),
		"arguments": _parse_json_arguments(fn.get("arguments", "{}")),
	}


static func _parse_json_arguments(args_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(args_text)
	if parsed is Dictionary:
		return parsed
	return {}
