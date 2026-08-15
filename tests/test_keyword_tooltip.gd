extends SceneTree
## KeywordTooltip 关键词悬停提示测试（Master 8/15）
## 验证：Keywords.md 解析 / 长词优先 / 高亮替换 / BBCode 防破坏 / 定义查询
## 运行：godot --headless --path . --script res://tests/test_keyword_tooltip.gd

const RESULT_PATH := "user://test_keyword_tooltip_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	var kt: Node = root.get_node_or_null("/root/KeywordTooltip")
	if kt == null:
		out.append("KeywordTooltip autoload 存在: false")
		out.append("KEYWORD_DONE")
		_finish(out)
		return
	out.append("KeywordTooltip autoload 存在: true")

	# ① 解析：从 Keywords.md 加载词条数量（应 ≥ 40）
	var count: int = kt.get_all_keywords().size()
	out.append("关键词数量 ≥ 40: %s (%d)" % [count >= 40, count])

	# ② 定义查询：典型色情术语 + 游戏机制
	out.append("查询「前贴」: %s" % (kt.get_definition("前贴") != ""))
	out.append("查询「奉仕傾向」: %s" % (kt.get_definition("奉仕傾向") != ""))
	out.append("查询「外交博弈」: %s" % (kt.get_definition("外交博弈") != ""))
	out.append("查询「联合统治」: %s" % (kt.get_definition("联合统治") != ""))
	out.append("has_keyword「肛塞」: %s" % kt.has_keyword("肛塞"))

	# ③ 长词优先：长词（联合统治）应先于短词（统治）——排序按长度降序
	var all_keys: Array = kt.get_all_keywords()
	var idx_long: int = all_keys.find("联合统治")
	var idx_short: int = all_keys.find("统治")
	out.append("长词优先排序（联合统治 > 统治）: %s" % (idx_long != -1 and (idx_short == -1 or idx_long < idx_short)))

	# ④ 高亮替换：正文中的关键词被替换为 [url=...] 标签
	var hl: String = kt.highlight_text("她的前贴是爱心形的，戴着肛塞。")
	out.append("高亮「前贴」: %s" % hl.contains("[url=前贴]"))
	out.append("高亮「肛塞」: %s" % hl.contains("[url=肛塞]"))

	# ⑤ BBCode 防破坏：已有 [url=前贴] 标签参数区不应被二次包裹成 [url=[url=前贴]（破坏标签名）
	var safe: String = kt.highlight_text("[url=前贴]前贴[/url] 正文里也有前贴")
	out.append("BBCode 防破坏（参数区不嵌套 url 标签）: %s" % (not safe.contains("[url=[url=")))
	# 标签结构完整：开始/闭合标签数量匹配
	out.append("BBCode 结构完整（[url= 与 [/url] 成对）: %s" % (safe.count("[url=") == safe.count("[/url]")))
	# LLM 常见 [b] 强调标签也不被破坏
	var bold: String = kt.highlight_text("这是[b]前贴[/b]的说明")
	out.append("BBCode 防破坏（[b] 标签保留）: %s" % (bold.contains("[b]前贴[/b]") or bold.contains("[b][url=前贴]")))

	# ⑥ 不存在的关键词不影响文本
	var plain: String = kt.highlight_text("今天天气不错")
	out.append("无关键词文本原样: %s" % (plain == "今天天气不错"))

	out.append("KEYWORD_DONE")
	_finish(out)


func _finish(out: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
