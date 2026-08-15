extends Node
class_name ResponseParser
## 响应解析：把 LLM 返回拆成 思考(CoT) / 正文 / 工具调用，带容错。
## Master 8/15：正文改走 <content> 标签 + 正则提取（参考女仆别墅项目），不再依赖 submit_dialogue 工具。

static func parse_response(data: Dictionary) -> Dictionary:
	## 返回 { cot, content, tool_calls }
	var result := {"cot": "", "content": "", "tool_calls": []}
	if not data.has("choices") or (data["choices"] as Array).is_empty():
		return result
	var message: Dictionary = data["choices"][0].get("message", {})

	# CoT：部分模型用 reasoning_content（如 deepseek-r1 风格）
	result["cot"] = str(message.get("reasoning_content", ""))

	# 正文：先剥离 <thinking> 块（容错）→ 再在剩余文本中提取 <content>（Master 8/15 修复：
	# 参考 Synthetica——<thinking> 开标签由 PREFILL 提供，模型输出通常只有 </thinking> 闭合；
	# 若 thinking 未剥离，其中复述的 <content> 字样会被正文正则误读为正文起点）
	# ⚠️ Master 8/15 修复：OpenAI 协议下 tool_calls 模式的 content 常为 null，
	# Dictionary.get(key, default) 只在 key 缺失时返回 default——key 存在但值为 null 时返回 null！
	# 直接赋给 String 类型变量会运行时崩溃 → 必须先 null 检查，否则正文丢失 + 后续工具执行中断。
	var content: String = ""
	if message.has("content") and message["content"] != null:
		content = str(message["content"])
	# ① 完整闭合 <thinking>...</thinking>（模型自带开标签）
	var ts := content.find("<thinking>")
	var te := content.find("</thinking>")
	if ts != -1 and te != -1 and te > ts:
		# <thinking> 10 字符 / </thinking> 11 字符（Master 8/15：原 ts+11/te+12 会多跳 1 字符，修）
		result["cot"] += "\n" + content.substr(ts + 10, te - ts - 10)
		content = content.substr(te + 11)
	# ② PREFILL 式：无 <thinking> 开标签（PREFILL 已提供）但有 </thinking> 闭合 → 开头到闭合全为思考
	elif te != -1:
		result["cot"] += "\n" + content.substr(0, te)
		content = content.substr(te + 11)
	# ③ 容错：有 <thinking> 但没闭合 → 截到 <content> 前（若存在）
	elif ts != -1:
		var c_start := content.find("<content>")
		if c_start != -1 and c_start > ts:
			result["cot"] += "\n" + content.substr(ts + 10, c_start - ts - 10)
			content = content.substr(c_start)

	# 正文主路径：<content> 标签 + 正则提取（参考女仆别墅 ResponseParser，三级兜底）
	# ① 完整闭合标签：(?s) 单行模式让 . 匹配换行
	var regex_content := RegEx.new()
	regex_content.compile("(?s)<content>(.*?)</content>")
	var content_match := regex_content.search(content)
	if content_match:
		content = content_match.get_string(1).strip_edges()
	else:
		# ② 容错：有 <content> 开始但没闭合 → 截取到结尾
		var cs := content.find("<content>")
		if cs != -1:
			content = content.substr(cs + 9).replace("</content>", "").strip_edges()
		else:
			# ③ 极端兜底：模型全忘了标签 → 剥离标签痕迹，用剩余文本当正文
			var fallback := content
			fallback = fallback.replace("</think>", "").replace("<thinking>", "").replace("</thinking>", "")
			fallback = fallback.replace("<content>", "").replace("</content>", "")
			content = fallback.strip_edges()
	result["content"] = content

	# 工具调用
	if message.has("tool_calls"):
		result["tool_calls"] = message["tool_calls"]
	return result


static func parse_tool_call(tool_call: Dictionary) -> Dictionary:
	## 把单个 tool_call 解析为 { name, arguments, id }（id 用于回填 tool 结果，OpenAI 协议必需）
	var fn: Dictionary = tool_call.get("function", {})
	return {
		"name": fn.get("name", ""),
		"arguments": _parse_json_arguments(fn.get("arguments", "{}")),
		"id": str(tool_call.get("id", "")),
	}


static func _parse_json_arguments(args_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(args_text)
	if parsed is Dictionary:
		return parsed
	return {}
