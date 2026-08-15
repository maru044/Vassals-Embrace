extends Node
## 关键词悬停提示系统（Autoload 单例，移植自女仆别墅项目 KeywordTooltip）
##
## 加载 data/Keywords.md，按 `## 标题` 解析关键词定义。
## 提供：查询定义 + 将文本中关键词替换为 [url] 高亮标签（RichTextLabel meta 悬停）。
## Master 8/15：游戏内 tooltip（EU4 式）——聊天气泡 / 帮助手册中色情术语与游戏机制自动高亮，悬停弹解释。

const KEYWORDS_PATH := "res://data/Keywords.md"
const HIGHLIGHT_COLOR := "#B04A2A"   # 羊皮纸主题下的墨红/深棕高亮（与 _INK 协调，区别于正文）

## 关键词定义缓存 { "关键词": "定义文本" }
var _keywords: Dictionary = {}

## 按关键词长度从长到短排序的列表（用于优先匹配长词）
var _sorted_keywords: Array[String] = []

## 悬停弹窗（惰性创建，避免无关键词时占资源）
var _popup: PopupPanel = null
var _popup_label: RichTextLabel = null


func _ready() -> void:
	_load_keywords()


func _load_keywords() -> void:
	if not FileAccess.file_exists(KEYWORDS_PATH):
		push_error("[KeywordTooltip] 找不到关键词文件: %s" % KEYWORDS_PATH)
		return
	var text := FileAccess.get_file_as_string(KEYWORDS_PATH)
	_keywords = _parse_keywords(text)
	# 按关键词长度从长到短排序（长词优先匹配）
	_sorted_keywords.clear()
	for k in _keywords:
		_sorted_keywords.append(k)
	_sorted_keywords.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	print("[KeywordTooltip] 加载了 %d 个关键词" % _keywords.size())


## 从 Markdown 文本中解析 `## 标题` + 内容
func _parse_keywords(text: String) -> Dictionary:
	var result := {}
	var regex := RegEx.new()
	regex.compile("^## (.+)$")
	var current_keyword := ""
	var current_desc: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		var match := regex.search(trimmed)
		if match:
			# 保存上一个关键词
			if current_keyword != "" and current_desc.size() > 0:
				result[current_keyword] = "\n".join(current_desc).strip_edges()
			current_keyword = match.get_string(1).strip_edges()
			current_desc = []
		elif current_keyword != "" and trimmed != "":
			current_desc.append(line)
	# 保存最后一个关键词
	if current_keyword != "" and current_desc.size() > 0:
		result[current_keyword] = "\n".join(current_desc).strip_edges()
	return result


## 获取关键词的定义文本（无则空串）
func get_definition(keyword: String) -> String:
	return _keywords.get(keyword, "")


## 检查关键词是否存在
func has_keyword(keyword: String) -> bool:
	return _keywords.has(keyword)


## 获取所有关键词列表（长词在前）
func get_all_keywords() -> Array[String]:
	return _sorted_keywords.duplicate()


## 将文本中的关键词替换为 [url=keyword][color]keyword[/color][/url] 格式
## 用于 RichTextLabel 的 meta 悬停高亮（长词优先，避免「肛塞」截胡「肛塞交杯酒」）
## 实现：单遍扫描——BBCode 标签区（[...] 或 [/...]）整体跳过不替换，文本区匹配最长关键词
## （避免破坏 LLM 可能自带的 [b]/[color]/[url] 等标签结构）
func highlight_text(text: String) -> String:
	var result := ""
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		# 标签区：整体复制 [...]（含属性与闭合标签），不替换内部关键词
		if ch == "[":
			var close := text.find("]", i)
			if close != -1:
				result += text.substr(i, close - i + 1)
				i = close + 1
				continue
		# 文本区：按最长关键词优先匹配
		var matched := false
		for kw in _sorted_keywords:
			if i + kw.length() <= n and text.substr(i, kw.length()) == kw:
				result += "[url=%s][color=%s]%s[/color][/url]" % [kw, HIGHLIGHT_COLOR, kw]
				i += kw.length()
				matched = true
				break
		if not matched:
			result += ch
			i += 1
	return result


# ========== 悬停弹窗（PopupPanel，羊皮纸风格） ==========

## 创建弹窗（懒加载；样式对齐羊皮纸主题，复用 Color 常量避免硬编码差异）
func ensure_popup() -> PopupPanel:
	if _popup != null:
		return _popup
	_popup = PopupPanel.new()
	_popup.visible = false
	# 羊皮纸面板样式
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.94, 0.82, 0.58, 0.98)
	sb.border_color = Color(0.75, 0.58, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_popup.add_theme_stylebox_override("panel", sb)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.add_theme_font_size_override("normal_font_size", 16)
	lbl.add_theme_color_override("default_color", Color(0.36, 0.26, 0.14))
	lbl.custom_minimum_size = Vector2(340, 0)
	_popup.add_child(lbl)
	_popup_label = lbl
	# 全局单例节点挂到 root，避免随调用方销毁
	var root_node := get_tree().root
	if not _popup.is_inside_tree():
		root_node.add_child(_popup)
	return _popup


## 显示关键词定义弹窗（由 RichTextLabel meta_hover_started 调用）
func show_keyword_tooltip(meta: Variant, at_global_pos: Vector2 = Vector2.INF) -> void:
	var kw := str(meta)
	var desc := get_definition(kw)
	if desc == "":
		return
	var popup := ensure_popup()
	# 标题 = 关键词（加粗金色），正文 = 定义
	_popup_label.text = "[color=#8a5a1e][b]%s[/b][/color]\n%s" % [kw, desc]
	popup.reset_size()
	popup.popup()
	# 定位到鼠标附近（+16 偏移避免遮挡指针；超右/下边缘回折）
	# ⚠️ PopupPanel 无 get_global_mouse_position（非 CanvasItem 坐标方法）→ 用 viewport 全局坐标
	var pos: Vector2 = at_global_pos
	if pos == Vector2.INF:
		var vp_root := _popup.get_viewport()
		if vp_root:
			pos = vp_root.get_mouse_position()
		else:
			pos = Vector2(320, 240)
	pos += Vector2(18, 18)
	# ⚠️ PopupPanel 是 Window（非 Control），无 get_viewport_rect() → 从 viewport 取可见区域尺寸
	var vp: Vector2 = Vector2(1920, 1080)
	var vp_root := _popup.get_viewport()
	if vp_root:
		vp = vp_root.get_visible_rect().size
	var pop_size: Vector2 = popup.size
	if pos.x + pop_size.x > vp.x:
		pos.x = vp.x - pop_size.x - 8
	if pos.y + pop_size.y > vp.y:
		pos.y = vp.y - pop_size.y - 8
	popup.position = Vector2i(pos)


## 隐藏弹窗（由 meta_mouse_exited 或任意处调用）
func hide_keyword_tooltip() -> void:
	if _popup and _popup.visible:
		_popup.hide()
