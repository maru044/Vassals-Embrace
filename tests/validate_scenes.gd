extends SceneTree
## 场景加载验证：逐个加载并实例化所有场景，结果写入 user://validate_result.txt
## 运行：godot --headless --path . --script res://tests/validate_scenes.gd

const RESULT_PATH := "user://validate_result.txt"

func _initialize() -> void:
	var out: Array[String] = []
	var scenes := [
		"res://scenes/main_menu/main_menu.tscn",
		"res://scenes/country_select/country_select.tscn",
		"res://scenes/game_ui/game_ui.tscn",
		"res://scenes/chat/chat_dialog.tscn",
	]
	for s in scenes:
		var packed: PackedScene = load(s)
		if packed == null:
			out.append("FAIL load: " + s)
			continue
		var inst: Node = packed.instantiate()
		root.add_child(inst)
		# 触发 _ready / @onready
		await process_frame
		if inst.is_inside_tree():
			out.append("OK instanced: " + s + " class=" + inst.get_class())
		else:
			out.append("FAIL not in tree: " + s)
		root.remove_child(inst)
		inst.free()
	out.append("VALIDATION_DONE")

	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	quit()
