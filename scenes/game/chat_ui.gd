extends CanvasLayer
class_name ChatUI
## 全局聊天面板（参考项目 ChatUI 案例，按本作羊皮纸 EU 主题重制）。
## 布局：左 = 立绘区（统治者/后宫立绘 + 深度图视差；Miku 无立绘），右 = 对话区（标题/滚动消息/输入/发送）。
## 接入 LLMClient：open_chat(kind, id, display_name) 注入对象人设 → 收发消息。

# ===== 羊皮纸主题色 =====
const _PANEL_BG := Color(0.94, 0.82, 0.58, 0.97)
const _PANEL_BORDER := Color(0.75, 0.58, 0.3, 0.6)
const _INK := Color(0.36, 0.26, 0.14)
const _GOLD := Color(0.85, 0.71, 0.45)
const _GOLD_OUTLINE := Color(0.32, 0.2, 0.07)
const _PLAYER_BUBBLE := Color(0.62, 0.5, 0.3, 0.9)
const _OTHER_BUBBLE := Color(0.85, 0.73, 0.52, 0.95)
const PORTRAIT_DIR := "res://assets/portraits/"
const PARALLAX_SHADER := "res://shaders/chat_ui_parallax.gdshader"
const LLM_CLIENT_SCRIPT := "res://scripts/llm/llm_client.gd"
const RESPONSE_PARSER_SCRIPT := "res://scripts/llm/response_parser.gd"
const TOOL_EXECUTOR_SCRIPT := "res://scripts/llm/tool_executor.gd"

var _target_kind := ""          # "country" / "harem" / "miku"
var _target_id := ""            # 国家 id / 后宫名
var _display_name := ""         # 标题/人设用名

var _shade: ColorRect
var _panel: PanelContainer
var _tachie_rect: TextureRect
var _tachie_mat: ShaderMaterial = null
var _parallax_shader: Shader = null
var _title: Label
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _input: LineEdit
var _send: Button
var _rollback_btn: Button = null   # 撤回上一条（Master 8/13 容错）
var _llm = null
var _parser_script: GDScript = null
var _tool_executor_script: GDScript = null
var _tool_executor = null
var _waiting := false
var _parallax_smooth := Vector2.ZERO
var _pending_requirement := ""        # 引擎④-CB：要求对话的 cb_id（非空=要求模式）
var _pending_requirement_label := ""  # 要求对话展示名（如 要求附庸）


func _ready() -> void:
	layer = 160
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	# LLM 客户端 + 工具执行器（好感度等引擎状态经工具落地）
	var script: GDScript = load(LLM_CLIENT_SCRIPT)
	_llm = Node.new()
	_llm.set_script(script)
	add_child(_llm)
	_llm.request_finished.connect(_on_llm_finished)
	_parser_script = load(RESPONSE_PARSER_SCRIPT)
	_tool_executor_script = load(TOOL_EXECUTOR_SCRIPT)
	_tool_executor = Node.new()
	_tool_executor.set_script(_tool_executor_script)
	add_child(_tool_executor)


func _build_ui() -> void:
	# 全屏半透明遮罩（左键点击关闭；滚轮放行给地图缩放，Master 8/13：滚向远景误关对话）
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_shade)
	_shade.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
			get_viewport().set_input_as_handled())

	# 羊皮纸面板（居中大窗）
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.08
	_panel.anchor_top = 0.06
	_panel.anchor_right = 0.92
	_panel.anchor_bottom = 0.94
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", _make_stylebox(_PANEL_BG, _PANEL_BORDER, 20))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	margin.add_child(hbox)

	# ===== 左：立绘区 =====
	_tachie_rect = TextureRect.new()
	_tachie_rect.visible = false
	_tachie_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tachie_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tachie_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tachie_rect.custom_minimum_size = Vector2(360, 0)
	_tachie_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_tachie_rect)

	# ===== 右：对话区 =====
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	var top := HBoxContainer.new()
	right.add_child(top)

	_title = Label.new()
	_title.text = "对话"
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", _GOLD)
	_title.add_theme_color_override("font_outline_color", _GOLD_OUTLINE)
	_title.add_theme_constant_override("outline_size", 3)
	top.add_child(_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.add_theme_font_size_override("font_size", 16)
	btn_close.add_theme_color_override("font_color", _INK)
	btn_close.add_theme_stylebox_override("normal", _make_stylebox(_PANEL_BG.lightened(0.06), _PANEL_BORDER, 12))
	btn_close.pressed.connect(_close)
	top.add_child(btn_close)

	# 滚动消息区
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 12)
	_scroll.add_child(_vbox)

	# 底部输入
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.custom_minimum_size = Vector2(0, 60)
	right.add_child(bottom)

	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "输入想说的话…（Enter 发送）"
	_input.add_theme_font_size_override("font_size", 18)
	_input.add_theme_color_override("font_color", _INK)
	_input.add_theme_stylebox_override("normal", _make_stylebox(Color(0.97, 0.9, 0.7, 0.9), _PANEL_BORDER, 10))
	_input.text_submitted.connect(func(_t: String) -> void: _on_send_pressed())
	bottom.add_child(_input)

	_send = Button.new()
	_send.text = "发送"
	_send.custom_minimum_size = Vector2(110, 0)
	_send.add_theme_font_size_override("font_size", 18)
	_send.add_theme_color_override("font_color", _INK)
	_send.add_theme_stylebox_override("normal", _make_stylebox(_PANEL_BG.lightened(0.08), _PANEL_BORDER, 12))
	_send.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.7, 0.66, 0.52, 0.9), _PANEL_BORDER, 12))
	_send.pressed.connect(_on_send_pressed)
	bottom.add_child(_send)

	# 撤回上一条（Master 8/13 容错：回滚历史 + 填入输入框供修改重发）
	_rollback_btn = Button.new()
	_rollback_btn.text = "↺"
	_rollback_btn.custom_minimum_size = Vector2(72, 0)
	_rollback_btn.tooltip_text = "撤回上一条"
	_rollback_btn.add_theme_font_size_override("font_size", 20)
	_rollback_btn.add_theme_color_override("font_color", _INK)
	_rollback_btn.add_theme_stylebox_override("normal", _make_stylebox(_PANEL_BG.lightened(0.04), _PANEL_BORDER, 12))
	_rollback_btn.pressed.connect(_on_rollback_pressed)
	bottom.add_child(_rollback_btn)

	_parallax_shader = load(PARALLAX_SHADER)


## 打开聊天：kind = country / harem / miku
## requirement：引擎④-CB 要求对话（cb_id），requirement_label 为展示名；非空时注入要求系统消息
func open_chat(kind: String, id: String, display_name: String, requirement := "", requirement_label := "") -> void:
	_target_kind = kind
	_target_id = id
	_display_name = display_name
	_title.text = display_name
	_clear_bubbles()
	_load_tachie(kind, id)
	visible = true
	_waiting = false
	_send.disabled = false
	_send.text = "发送"
	# 引擎④-CB：要求对话（LLM 同意→建立关系 / 拒绝→1年CB）
	_pending_requirement = requirement
	_pending_requirement_label = requirement_label
	# 重置 LLM 上下文 + 注入对象人设
	if _llm:
		_llm.reset_history()
		_llm.add_message("system", _build_system_prompt())
		if not requirement.is_empty():
			_llm.add_message("system", "（外交要求）玩家向你提出【%s】。请结合你的性格、与玩家的关系与好感，决定是否同意。你必须在回复末尾用【同意】或【拒绝】明确标注结果。" % requirement_label)


func _close() -> void:
	visible = false
	_tachie_rect.visible = false
	if _llm:
		_llm.reset_history()   # 关闭对话即销毁历史+动态注入，防上下文串味（Master 8/13，参考女仆别墅 Panel Closed）


## 立绘加载（country → rulers/<id>；harem → harem/<name>；miku 无）
func _load_tachie(kind: String, id: String) -> void:
	_tachie_rect.visible = false
	if kind == "miku" or id == "":
		return
	# 目录映射：kind "country" → 资产目录 "rulers"
	var dir := "rulers" if kind == "country" else "harem"
	var base := PORTRAIT_DIR + dir + "/" + id + ".png"
	var depth := PORTRAIT_DIR + "depth/" + dir + "/" + id + "_depth.png"
	if not ResourceLoader.exists(base):
		return
	_tachie_rect.texture = load(base)
	if _parallax_shader and ResourceLoader.exists(depth):
		_tachie_mat = ShaderMaterial.new()
		_tachie_mat.shader = _parallax_shader
		_tachie_mat.set_shader_parameter("depth_map", load(depth))
		_tachie_mat.set_shader_parameter("depth_strength", 0.05)
		_tachie_mat.set_shader_parameter("scale", 1.05)
		_tachie_rect.material = _tachie_mat
	else:
		_tachie_rect.material = null
	_tachie_rect.visible = true


func _process(delta: float) -> void:
	if _tachie_mat and _tachie_rect.visible and visible:
		var vp := get_viewport().get_visible_rect().size
		var center := vp / 2.0
		var target := (get_viewport().get_mouse_position() - center) / center
		target.x = clampf(target.x, -1.0, 1.0)
		target.y = clampf(target.y, -1.0, 1.0)
		_parallax_smooth = _parallax_smooth.lerp(target, delta * 5.0)
		_tachie_mat.set_shader_parameter("mouse_offset", _parallax_smooth)


func _on_send_pressed() -> void:
	if _waiting:
		return
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.clear()
	_add_bubble("你", text, true)
	if _llm:
		_llm.add_user_message(text)   # 修复①：合并连续 user，避免 API 400
		_waiting = true
		_send.disabled = true
		_send.text = "思考中…"
		# Master 8/13 修复：所有对话都启用工具（submit_dialogue 正文 + modify_favor 好感等），
		# 否则 Miku/harem 对话无工具 → LLM 只能把 submit_dialogue 写成 JSON 文本而非标准 tool_calls
		if _tool_executor_script:
			_llm.send_request(_tool_executor_script.TOOLS)
		else:
			_llm.send_request()


## 撤回上一条：回滚 LLM 历史到上一个 user 前，填入输入框供修改重发（Master 8/13）
func _on_rollback_pressed() -> void:
	if _waiting or _llm == null:
		return
	var last_user := str(_llm.rollback_history())
	if _vbox.get_child_count() > 0:
		_vbox.get_child(_vbox.get_child_count() - 1).queue_free()
	if not last_user.is_empty():
		_input.text = last_user
		_add_system_msg("已撤回，可修改后重发")


func _on_llm_finished(success: bool, data: Dictionary) -> void:
	_waiting = false
	_send.disabled = false
	_send.text = "发送"
	if not success:
		_add_system_msg("（网络/解析错误，请检查 API 配置）")
		return
	var parsed: Dictionary = _parser_script.parse_response(data)
	var tool_calls: Array = parsed.get("tool_calls", [])
	# Master 8/13：正文优先从 submit_dialogue 工具参数提取（不靠 <content> 标签解析，更可靠）；兜底用 content 文本
	# 注：CoT/正文/ToolCall 已由 llm_client 统一打印控制台日志（🧠CoT/💬正文/🔧ToolCall），此处不再重复
	var display_text := str(parsed.get("content", ""))
	if not tool_calls.is_empty():
		for tc in tool_calls:
			var tcall: Dictionary = _parser_script.parse_tool_call(tc)
			if str(tcall.get("name", "")) == "submit_dialogue":
				var dtext := str(tcall.get("arguments", {}).get("content", ""))
				if dtext != "":
					display_text = dtext
				break
	else:
		# 容错：LLM 可能把 submit_dialogue 写成 JSON 文本（未走标准 tool_calls）→ 提取其 content 参数
		var json_dialogue := _extract_dialogue_from_text(display_text)
		if json_dialogue != "":
			display_text = json_dialogue
	# 显示气泡（仅正文，不显示 CoT/格式——Master 8/13 反馈）
	if display_text != "":
		_add_bubble(_display_name, display_text, false)
	# 执行工具调用（含 submit_dialogue；好感度经 modify_favor 落地 → favor_changed → 外交面板即时刷新）
	if not tool_calls.is_empty() and _tool_executor and _llm:
		for tc in tool_calls:
			var call: Dictionary = _parser_script.parse_tool_call(tc)
			var tname := str(call.get("name", ""))
			var res: Dictionary = _tool_executor.execute(tname, call.get("arguments", {}))
			# 修复②：回填 tool 结果到历史（OpenAI 协议要求 tool_calls 后紧跟 role=tool，否则下次请求 400）
			_llm.add_tool_result(str(call.get("id", "")), tname, res)
			if res.get("ok", false) and tname == "modify_favor":
				var delta: int = res.get("delta", 0)
				var favor: float = res.get("favor", 0.0)
				_add_system_msg("好感 %s%d → %d（%s）" % ["+" if delta >= 0 else "", delta, int(favor), _display_name])
	# 引擎④-CB：要求对话结果落地（同意→建立关系 / 拒绝→1年CB）
	if not _pending_requirement.is_empty():
		_handle_requirement_result(display_text)
		_pending_requirement = ""
		_pending_requirement_label = ""


## 引擎④-CB：解析要求对话结果（优先【同意】/【拒绝】标签，兜底关键词）
func _handle_requirement_result(content: String) -> void:
	var actor := GameManager.player_country_id
	var target: String = _target_id
	var cb_id: String = _pending_requirement
	var label: String = _pending_requirement_label
	var accepted := content.contains("【同意】")
	var rejected := content.contains("【拒绝】")
	if not accepted and not rejected:
		var plain := content.replace("【同意】", "").replace("【拒绝】", "")
		accepted = plain.contains("同意") and not plain.contains("拒绝")
		rejected = not accepted and plain.contains("拒绝")
	if accepted:
		var res := GameManager.establish_requirement(actor, target, cb_id)
		_add_system_msg("【%s】接受了%s → %s" % [_display_name, label, "已建立关系" if res.get("ok", false) else str(res.get("error", "失败"))])
	elif rejected:
		var res := GameManager.grant_requirement_cb(actor, target, cb_id)
		_add_system_msg("【%s】拒绝了%s → 获得 1 年 CB（%d 回合）" % [_display_name, label, int(res.get("months", 0))])
	else:
		_add_system_msg("（未能从回复判断同意/拒绝，请再次明确表态）")


## 对象人设：锚定当前对话对象 + 加载 Prompts 全部提示词文件（PromptManager，按 depth 排序）
func _build_system_prompt() -> String:
	var anchor := ""
	match _target_kind:
		"miku":
			anchor = "【当前对话对象】你是 Miku（系统管理员 / 女主人 / 裁判），主持《欧陆百合风云》。玩家是 %s 的统治者，正在与你对话。用中文回复。" % _player_id_label()
		"country":
			anchor = "【当前对话对象】你是 %s 的统治者，身处「欧陆百合风云」的百合后宫世界。玩家是 %s 的统治者。当前是外交/私会场合。请保持角色人设：端庄得体、外冷内淫、识趣的玩伴姿态，用中文对话。" % [_display_name, _player_id_label()]
		"harem":
			anchor = "【当前对话对象】你是 %s 后宫中的一员，正与主人独处。温柔识趣、主动调情但不卑不亢，享受百合与侍奉，用中文对话。" % _display_name
	# 动态占位符（Format_and_Correction 的 {dice_rolls}、Dynamic_Status 的 {current_time}/{scene_context}/{target_favor} 等）
	var rolls := "%d, %d, %d, %d, %d" % [Dice.d100(), Dice.d100(), Dice.d100(), Dice.d100(), Dice.d100()]
	# 场景状态：普通对话 vs 外交要求（Master 8/13：不同按钮场景用系统提示词告知 LLM 当前状态）
	var scene := "日常场合：随意的对话 / 私会调情"
	if not _pending_requirement.is_empty():
		scene = "外交场合：玩家正在向你提出【%s】，请结合你的性格、与玩家的关系与好感决定是否同意，并在回复末尾用【同意】或【拒绝】明确标注" % _pending_requirement_label
	var extra := {
		"dice_rolls": rolls,
		"player_name": _player_id_label(),
		"target_name": _display_name,
		"current_time": "%d 年 %d 月" % [GameManager.year, GameManager.month],
		"scene_context": scene,
		"target_favor": int(GameManager.player_favor.get(_target_id, 0.0)),
	}
	# 扮演国家/后宫时不注入 Miku 人设（Jailbreak/World_Core），避免 LLM 混淆成扮演 Miku
	var exclude: Array = []
	if _target_kind != "miku":
		exclude = ["Jailbreak_Persona.md", "World_Core.md"]
	var pm := get_node("/root/PromptManager")
	var prompts: String = pm.call("build_system_context", extra, [], exclude)
	return (anchor + "\n\n" + prompts).strip_edges()


## 容错：LLM 可能把 submit_dialogue 写成 JSON 文本（未走标准 tool_calls）→ 提取其 content 参数作为正文
func _extract_dialogue_from_text(text: String) -> String:
	if text.find("submit_dialogue") == -1:
		return ""
	var re := RegEx.new()
	re.compile('"content"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"')
	var m := re.search(text)
	if m == null:
		return ""
	var raw := m.get_string(1)
	return raw.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")


## 玩家国家 id（无则回退「玩家」）
func _player_id_label() -> String:
	var pid := GameManager.player_country_id
	return pid if not pid.is_empty() else "玩家"


## 消息气泡
func _add_bubble(sender: String, text: String, is_player: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_stylebox(
		_PLAYER_BUBBLE if is_player else _OTHER_BUBBLE, _PANEL_BORDER, 14))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var name_lbl := Label.new()
	name_lbl.text = sender
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", _GOLD if is_player else Color(0.7, 0.5, 0.25))
	vbox.add_child(name_lbl)
	var rtb := RichTextLabel.new()
	rtb.bbcode_enabled = true
	rtb.fit_content = true
	rtb.selection_enabled = true
	rtb.add_theme_font_size_override("normal_font_size", 18)
	rtb.add_theme_color_override("default_color", _INK)
	rtb.text = text
	vbox.add_child(rtb)
	_vbox.add_child(panel)
	_scroll_to_bottom()


func _add_system_msg(text: String) -> void:
	var l := Label.new()
	l.text = "—— " + text + " ——"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.5, 0.42, 0.28))
	_vbox.add_child(l)


func _clear_bubbles() -> void:
	for c in _vbox.get_children():
		c.queue_free()


func _scroll_to_bottom() -> void:
	_scroll.set_deferred("scroll_vertical", 999999)


## 羊皮纸 StyleBoxFlat（边框 + 圆角）
func _make_stylebox(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = border
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_right = radius
	sb.corner_radius_bottom_left = radius
	return sb
