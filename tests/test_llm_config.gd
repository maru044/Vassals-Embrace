extends SceneTree
## LLM 配置接入冒烟测试：
## 1) ConfigManager 预置值与参考项目 GlobalConfig.gd 一致（URL/模型/温度/topP）
## 2) apply_preset 正确切换（含 deepseek → v4-flash）
## 3) main_menu ConfigDialog 新节点存在且预设下拉已填充
## 运行：godot --headless --path . --script res://tests/test_llm_config.gd

const RESULT_PATH := "user://test_llm_config_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var cm: Node = load("res://scripts/core/config_manager.gd").new()
	root.add_child(cm)
	await process_frame  # 触发 _ready -> load_config

	out.append("== ConfigManager presets ==")
	var ref := {
		"gemini": {"url": "https://gcli.ggchan.dev/v1/chat/completions", "model": "gemini-3.1-pro-preview", "temp": 1.0, "top_p": 0.88},
		"deepseek": {"url": "https://api.deepseek.com/chat/completions", "model": "deepseek-v4-flash", "temp": 1.0, "top_p": 0.9},
		"custom": {"url": "", "model": "", "temp": 1.0, "top_p": 0.9},
	}
	var presets: Dictionary = cm.get("presets")
	for key in ["gemini", "deepseek", "custom"]:
		var p: Dictionary = presets.get(key, {})
		var r: Dictionary = ref[key]
		var ok: bool = p.get("url", "") == r["url"] and p.get("model", "") == r["model"] \
				and p.get("temp", 0.0) == r["temp"] and p.get("top_p", 0.0) == r["top_p"]
		out.append("[%s] %s url=%s model=%s temp=%s top_p=%s" % [key, "OK" if ok else "FAIL", p.get("url", ""), p.get("model", ""), p.get("temp", 0.0), p.get("top_p", 0.0)])

	out.append("== apply_preset ==")
	cm.call("apply_preset", "deepseek")
	out.append("deepseek -> model=%s temp=%s top_p=%s vision=%s" % [cm.get("model"), cm.get("api_temp"), cm.get("api_top_p"), cm.get("supports_vision")])
	cm.call("apply_preset", "gemini")
	out.append("gemini -> model=%s temp=%s top_p=%s vision=%s" % [cm.get("model"), cm.get("api_temp"), cm.get("api_top_p"), cm.get("supports_vision")])
	root.remove_child(cm)
	cm.free()

	out.append("== main_menu ConfigDialog ==")
	var packed: PackedScene = load("res://scenes/main_menu/main_menu.tscn")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var preset_opt: OptionButton = inst.get_node_or_null("ConfigDialog/Margin/VBox/PresetOption")
	var temp_input: Node = inst.get_node_or_null("ConfigDialog/Margin/VBox/TempInput")
	var top_p_input: Node = inst.get_node_or_null("ConfigDialog/Margin/VBox/TopPInput")
	out.append("PresetOption=%s TempInput=%s TopPInput=%s" % [preset_opt != null, temp_input != null, top_p_input != null])
	if preset_opt != null:
		out.append("preset item_count=%d" % preset_opt.item_count)
		var keys: Array[String] = []
		for i in preset_opt.item_count:
			keys.append(str(preset_opt.get_item_metadata(i)))
		out.append("preset keys=%s" % ", ".join(keys))
	root.remove_child(inst)
	inst.free()

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
