extends SceneTree
## 引擎④-T3 世界 AI 决策通道冒烟测试：世界状态打包 / 玩家保护 / LLM 动作执行 / 失败降级
## 运行：godot --headless --path . --script res://tests/test_world_ai.gd

const RESULT_PATH := "user://test_world_ai_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var wai: Node = root.get_node("WorldAI")
	gm.set("player_country_id", "England")
	gm.set("army_count", {"England": 13, "Scotland": 6, "Wales": 4})
	gm.set("country_prestige", {"England": 50.0, "Scotland": 50.0, "Wales": 40.0})
	gm.set("plays", [])
	gm.set("wars", [])

	# ① 世界状态打包非空 + 含国家与军队
	var wtext: String = wai.call("_world_state_text")
	out.append("world state non-empty: %s" % (not wtext.is_empty()))
	out.append("world state contains info: %s" % (wtext.contains("Scotland") and wtext.contains("军队")))

	# ② 玩家保护：LLM 不替玩家国家做动作
	out.append("player start_play blocked: %s" % wai.call("_is_player_action", "start_play", {"initiator": "England", "target": "Wales"}))
	out.append("AI start_play allowed: %s" % (wai.call("_is_player_action", "start_play", {"initiator": "Scotland", "target": "Wales"}) == false))

	# ③ LLM 动作执行：苏格兰发起博弈；玩家 join 被保护跳过
	var data := {"choices": [{"message": {"tool_calls": [
		{"function": {"name": "start_play", "arguments": "{\"initiator\":\"Scotland\",\"target\":\"Wales\",\"goal\":\"吞并\"}"}},
		{"function": {"name": "join_play", "arguments": "{\"play_id\":1,\"country_id\":\"England\",\"side\":\"B\"}"}},
	]}}]}
	wai.call("_on_llm_finished", true, data)
	var plays: Array = gm.get("plays")
	out.append("LLM start_play executed (plays=%d): %s" % [plays.size(), plays.size() >= 1])
	if plays.size() >= 1:
		out.append("play initiator=Scotland target=Wales: %s" % (
			str(plays[0].get("initiator", "")) == "Scotland" and str(plays[0].get("target", "")) == "Wales"))
		out.append("player join_play skipped (protected): %s" % (
			not (plays[0].get("sides", {}).get("B", []) as Array).has("England")))

	# ④ 失败降级：success=false → 不执行（plays 不变）
	var before: int = plays.size()
	wai.call("_on_llm_finished", false, {})
	out.append("failure fallback (no change): %s" % ((gm.get("plays") as Array).size() == before))

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
