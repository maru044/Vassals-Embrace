extends SceneTree
## 快速验证 <content> 标签三级兜底提取（Master 8/15 标签机制）
## 运行：godot --headless --path . --script res://tests/test_tag_extract.gd

const RESULT_PATH := "user://test_tag_extract_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	var parser: GDScript = load("res://scripts/llm/response_parser.gd")

	# ① 完整闭合标签
	var p1: Dictionary = parser.parse_response({"choices": [{"message": {"role": "assistant", "content": "<thinking>思考</thinking>\n<content>正文一号</content>"}}]})
	out.append("① 闭合标签提取: %s" % (str(p1.get("content", "")) == "正文一号"))
	out.append("① CoT 分离: %s" % str(p1.get("cot", "")).contains("思考"))

	# ② 未闭合标签（有 <content> 无 </content>）→ 截取到结尾
	var p2: Dictionary = parser.parse_response({"choices": [{"message": {"role": "assistant", "content": "<content>正文二号（未闭合"}}]})
	out.append("② 未闭合标签兜底: %s" % (str(p2.get("content", "")) == "正文二号（未闭合"))

	# ③ 完全无标签 → 极端兜底剥离标签痕迹用全文
	var p3: Dictionary = parser.parse_response({"choices": [{"message": {"role": "assistant", "content": "这是纯文本正文"}}]})
	out.append("③ 无标签极端兜底: %s" % (str(p3.get("content", "")) == "这是纯文本正文"))

	# ④ 内容为 null（OpenAI tool_calls 模式陷阱）→ 不崩溃，正文为空
	var p4: Dictionary = parser.parse_response({"choices": [{"message": {"role": "assistant", "content": null}}]})
	out.append("④ content=null 不崩溃: %s" % (str(p4.get("content", "")) == ""))

	# ⑤ 有 thinking 无闭合但 content 在前
	var p5: Dictionary = parser.parse_response({"choices": [{"message": {"role": "assistant", "content": "<thinking>未闭合思考<content>正文五号</content>"}}]})
	out.append("⑤ 未闭合 thinking 兜底: %s" % (str(p5.get("content", "")) == "正文五号"))

	out.append("TAG_EXTRACT_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
