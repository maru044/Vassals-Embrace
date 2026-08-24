extends SceneTree
## Master 8/24 记忆链路端到端冒烟测试（贴合真实游戏时序）：
## ① ChatUI 聊天 → _close 关闭 → 从 GameManager 恢复（模拟重开/换场景）→ LLM 记得全部对话
## ② 存档 _on_save 携带完整对话历史；读档 _on_load 后 GameManager 仍有历史
## ③ LLM 使用中的历史不含 system 环境注入（环境信息可存可不存，对话记忆必须完整）
## 运行：godot --headless --path . --script res://tests/test_memory_chain.gd

const RESULT_PATH := "user://test_memory_chain_result.txt"

var _out: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gm: Node = get_root().get_node("/root/GameManager")
	gm.call("start_new_game", "Scotland")

	# ===== 阶段 1：模拟一轮完整聊天后的历史（真实 ChatUI 写入格式）=====
	var dirty_hist: Array = [
		{"role": "system", "content": "【当前对话对象】你是 Miku...（环境注入）"},
		{"role": "user", "content": "你好，还记得我们的约定吗？"},
		{"role": "assistant", "content": "当然记得，Master。之前谈过的进攻计划我会配合的。"},
		{"role": "user", "content": "好，那下个月就动手。"},
	]
	gm.set("chat_history", dirty_hist)

	# ===== 阶段 2：保存（_on_save 真实路径，含 chat_history）=====
	var sp: Node = load("res://scenes/game/save_panel.gd").new()
	get_root().add_child(sp)
	await process_frame
	sp.call("_on_save", 0)
	var loaded: Dictionary = get_root().get_node("/root/SaveManager").call("load_game_from_slot", 0)
	var saved_hist: Array = loaded.get("chat_history", [])
	_out.append("① 存档含完整对话历史(≥2): %s" % (saved_hist.size() >= 2))

	# ===== 阶段 3：读档（主菜单链路：无注入回调 → 走兜底写 GameManager）=====
	gm.call("deserialize", loaded)
	var gm_hist_after_load: Array = gm.get("chat_history")
	_out.append("② 读档后 GameManager 历史不丢: %s" % (gm_hist_after_load.size() >= 2))

	# ===== 阶段 4：重开对话（新 ChatUI，模拟跳转 game.tscn / 重开窗口）=====
	var chat: Node = load("res://scenes/game/chat_ui.gd").new()
	get_root().add_child(chat)
	await process_frame
	chat.call("set_chat_history", gm_hist_after_load)
	var llm_hist: Array = chat.get("_llm").get("history")
	_out.append("③ 重开对话 LLM 记得全部对话: %s" % (
		llm_hist.size() >= 2
		and str(llm_hist).contains("约定")
		and str(llm_hist).contains("进攻计划")))
	_out.append("④ LLM 历史无 system 环境注入: %s" % (
		not str(llm_hist).contains("环境注入")
		and not str(llm_hist).contains("当前对话对象")))

	# ===== 阶段 5：关窗重开（模拟真实中最常发生的「关闭对话再打开」）=====
	chat.call("_close")   # _close → _remove_system + _sync_memory → GameManager 干净历史
	var gm_after_close: Array = gm.get("chat_history")
	var chat2: Node = load("res://scenes/game/chat_ui.gd").new()
	get_root().add_child(chat2)
	await process_frame
	chat2.call("set_chat_history", gm_after_close)
	var llm_hist2: Array = chat2.get("_llm").get("history")
	_out.append("⑤ 关闭对话再重开记忆仍在: %s" % (
		llm_hist2.size() >= 2 and str(llm_hist2).contains("约定")))

	_out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out))
		f.close()
	print("\n".join(_out))
	quit(0)