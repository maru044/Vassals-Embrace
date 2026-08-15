extends CanvasLayer
## 存档面板（引擎⑨）：6 槽位读/存/删；mode="load"（主菜单）/ "save"（游戏内）
## 羊皮纸风格（参考 Synthetica SaveLoadUI 布局，适配本项目全内存数据）。
## 保存 = GameManager.serialize() + 聊天历史 → SaveManager.save_game_to_slot
## 读取 = SaveManager.load_game_from_slot → GameManager.deserialize + 聊天历史 → load_completed

signal load_completed(data: Dictionary)

## 羊皮纸配色
const PARCHMENT_BASE := Color(0.86, 0.72, 0.46)
const PARCHMENT_BORDER := Color(0.55, 0.38, 0.15)
const GOLD := Color(0.96, 0.84, 0.55)
const INK := Color(0.18, 0.13, 0.08)

var _mode := "save"
var _slot_container: VBoxContainer
## 可选：取聊天历史（返回 Array[Dictionary]）；由 game.gd 注入（从 ChatDialog 的 LLMClient 取）
var get_chat_history: Callable = Callable()
var set_chat_history: Callable = Callable()


func _ready() -> void:
	layer = 150
	visible = false
	_build_ui()


func show_panel(mode: String = "load") -> void:
	_mode = mode
	visible = true
	_refresh_slot_list()


func hide_panel() -> void:
	visible = false


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 620)
	panel.add_theme_stylebox_override("panel", _make_stylebox(PARCHMENT_BASE, PARCHMENT_BORDER, 16))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "💾 存档管理"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", INK)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_slot_container = VBoxContainer.new()
	_slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_container.add_theme_constant_override("separation", 10)
	scroll.add_child(_slot_container)

	vbox.add_child(HSeparator.new())

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 44)
	close.add_theme_stylebox_override("normal", _make_stylebox(Color(0.9, 0.8, 0.58), PARCHMENT_BORDER, 8))
	close.add_theme_color_override("font_color", INK)
	close.pressed.connect(hide_panel)
	vbox.add_child(close)


func _refresh_slot_list() -> void:
	for c in _slot_container.get_children():
		c.queue_free()
	var slots := SaveManager.get_slots_info()
	for i in slots.size():
		var slot_data: Variant = slots[i]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 48)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 16)
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_theme_stylebox_override("normal", _make_stylebox(Color(0.94, 0.87, 0.72), PARCHMENT_BORDER, 6))
		if slot_data != null and slot_data is Dictionary:
			info.text = "  #%d | %s · %d年%d月 | %s" % [i + 1, _country_name(str(slot_data.get("player_country_id", ""))), int(slot_data.get("year", 0)), int(slot_data.get("month", 0)), str(slot_data.get("created_at", ""))]
			info.add_theme_color_override("font_color", INK)
		else:
			info.text = "  #%d | [ 空槽位 ]" % (i + 1)
			info.add_theme_color_override("font_color", Color(0.5, 0.45, 0.36))
		row.add_child(info)

		# 读取（有档）
		if slot_data != null and slot_data is Dictionary:
			row.add_child(_make_btn("读取", Color(0.45, 0.65, 0.45), _on_load.bind(i)))
		# 保存（save 模式，允许覆盖/新建）
		if _mode == "save":
			row.add_child(_make_btn("保存", Color(0.45, 0.55, 0.8), _on_save.bind(i)))
		# 删除（有档）
		if slot_data != null and slot_data is Dictionary:
			row.add_child(_make_btn("删除", Color(0.75, 0.45, 0.4), _on_delete.bind(i)))

		_slot_container.add_child(row)


func _make_btn(text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84, 0)
	b.add_theme_stylebox_override("normal", _make_stylebox(color, PARCHMENT_BORDER, 6))
	b.add_theme_color_override("font_color", INK)
	b.pressed.connect(cb)
	return b


func _make_stylebox(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	return sb


var _country_names: Dictionary = {}

## 国家中文名（countries.json name；无则回退 id）
func _country_name(id: String) -> String:
	if id == "":
		return "?"
	if _country_names.is_empty():
		var f := FileAccess.open("res://data/countries.json", FileAccess.READ)
		if f:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				for c in data.get("countries", []):
					_country_names[str(c.get("id", ""))] = str(c.get("name", ""))
			f.close()
	return _country_names.get(id, id)


## 保存到槽位：GameManager.serialize() + 聊天历史（可选）
func _on_save(idx: int) -> void:
	var data := GameManager.serialize()
	if get_chat_history.is_valid():
		var hist: Variant = get_chat_history.call()
		if hist is Array:
			data["chat_history"] = hist
	SaveManager.save_game_to_slot(idx, data)
	_refresh_slot_list()


## 读取槽位：GameManager.deserialize + 聊天历史（可选）→ load_completed（调用方刷新/跳转）
func _on_load(idx: int) -> void:
	var data := SaveManager.load_game_from_slot(idx)
	if data.is_empty():
		return
	GameManager.deserialize(data)
	# 主菜单读档 → 跳转 game.tscn 时跳过选国直接进入游戏（引擎⑨）
	GameManager.loaded_from_save = true
	if set_chat_history.is_valid() and data.has("chat_history"):
		set_chat_history.call(data["chat_history"])
	load_completed.emit(data)
	hide_panel()


## 删除槽位
func _on_delete(idx: int) -> void:
	SaveManager.delete_slot(idx)
	_refresh_slot_list()
