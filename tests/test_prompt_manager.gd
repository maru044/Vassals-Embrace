extends SceneTree
## 提示词管理器测试（Master 8/13）：加载 Prompts/*.md / JSON 头解析 / depth 降序 /
## 占位符替换 / include-exclude 筛选
## 运行：godot --headless --path . --script res://tests/test_prompt_manager.gd

const RESULT_PATH := "user://test_prompt_manager_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	var pm: Node = root.get_node("PromptManager")

	# ① 加载全部 system 提示词（应 ≥6：Jailbreak/World_Core/Core_Settings/Game_Mechanics/System_Tools_Manual/Format_and_Correction）
	var all: Array = pm.call("get_system_prompts")
	out.append("prompts loaded >=6: %s (%d)" % [all.size() >= 6, all.size()])

	# ② depth 降序（大→小）
	var sorted_ok := true
	for i in range(1, all.size()):
		if int(all[i - 1]["depth"]) < int(all[i]["depth"]):
			sorted_ok = false
			break
	out.append("depth descending: %s" % sorted_ok)

	# ③ 占位符替换：{dice_rolls} 注入后不再残留，且内容出现注入值
	var ctx := str(pm.call("build_system_context", {"dice_rolls": "1, 2, 3, 4, 5"}))
	out.append("placeholder {dice_rolls} replaced: %s" % (not ctx.contains("{dice_rolls}") and ctx.contains("1, 2, 3, 4, 5")))

	# ④ include 筛选：只加载 Game_Mechanics + System_Tools_Manual（WorldAI 用）
	var wctx := str(pm.call("build_system_context", {}, ["Game_Mechanics.md", "System_Tools_Manual.md"]))
	out.append("include Game_Mechanics+Tools has rules: %s" % (wctx.contains("欧陆百合风云") and wctx.contains("modify_favor")))
	out.append("include excludes World_Core persona: %s" % (not wctx.contains("青绿色双马尾")))

	# ⑤ exclude 筛选：扮演国家/后宫时排除 Miku 人设（World_Core + Jailbreak）
	var cctx := str(pm.call("build_system_context", {}, [], ["Jailbreak_Persona.md", "World_Core.md"]))
	out.append("exclude World_Core persona: %s" % (not cctx.contains("青绿色双马尾")))
	out.append("exclude Jailbreak identity: %s" % (not cctx.contains("<role>Human")))

	# ⑥ 单文件正文读取
	out.append("get_prompt_content Core_Settings non-empty: %s" % (str(pm.call("get_prompt_content", "Core_Settings.md")).length() > 10))

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit(0)
