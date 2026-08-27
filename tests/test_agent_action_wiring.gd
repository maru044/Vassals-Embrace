extends SceneTree


func _initialize() -> void:
	print("P1_HEARTBEAT agent-action wiring initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P1_TIMEOUT agent-action wiring exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var world_ai: Node = root.get_node_or_null("/root/WorldAI")
	if gm == null or world_ai == null:
		push_error("P1_FAIL required autoload missing")
		quit(2)
		return
	gm.call("start_new_game", "England")
	gm.set("wars", [])
	gm.set("plays", [])

	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var chat: Node = game.get("_chat_ui")
	var chat_llm: Node = chat.get("_llm") if chat != null else null
	var world_llm: Node = world_ai.get("_llm")
	var chat_cb: Callable = chat_llm.get("tool_callback") if chat_llm != null else Callable()
	var world_cb: Callable = world_llm.get("tool_callback") if world_llm != null else Callable()
	print("P1_ASSERT chat tool callback wired: %s" % chat_cb.is_valid())
	print("P1_ASSERT world tool callback wired: %s" % world_cb.is_valid())
	if not chat_cb.is_valid() or not world_cb.is_valid():
		print("P1_AGENT_ACTION_WIRING_FAILED")
		quit(1)
		return

	gm.set("player_favor", {"Scotland": 50.0})
	var favor_result: Dictionary = chat_cb.call("modify_favor", {"target_id": "Scotland", "delta": 5})
	var favor_changed: bool = bool(favor_result.get("ok", false)) and float(gm.get("player_favor").get("Scotland", 0.0)) == 55.0
	print("P1_ASSERT chat action changes engine state: %s" % favor_changed)

	gm.set("wars", [])
	var blocked: Dictionary = world_cb.call("declare_war", {"attacker": "England", "defender": "Scotland", "cb": "claim"})
	var player_blocked: bool = not bool(blocked.get("ok", false)) and (gm.get("wars") as Array).is_empty()
	print("P1_ASSERT world AI cannot act for player: %s" % player_blocked)
	var ai_action: Dictionary = world_cb.call("declare_war", {"attacker": "Scotland", "defender": "England", "cb": "claim"})
	var ai_changed_state: bool = bool(ai_action.get("ok", false)) and (gm.get("wars") as Array).size() == 1
	print("P1_ASSERT world AI action changes engine state: %s" % ai_changed_state)
	if not favor_changed or not player_blocked or not ai_changed_state:
		print("P1_AGENT_ACTION_WIRING_FAILED")
		quit(1)
		return

	var bare_llm: Node = Node.new()
	bare_llm.set_script(load("res://scripts/llm/llm_client.gd"))
	root.add_child(bare_llm)
	await process_frame
	var finished: Array = []
	bare_llm.request_finished.connect(func(success: bool, _data: Dictionary) -> void: finished.append(success))
	bare_llm.set("_busy", true)
	var tool_only := {
		"choices": [{"message": {"tool_calls": [{
			"id": "missing-callback",
			"type": "function",
			"function": {"name": "modify_favor", "arguments": "{\"target_id\":\"Scotland\",\"delta\":3}"}
		}]}}]
	}
	bare_llm.call("_on_request_completed", OK, 200, PackedStringArray(), JSON.stringify(tool_only).to_utf8_buffer())
	await process_frame
	var fails_observably: bool = finished.size() == 1 and finished[0] == false and not bool(bare_llm.get("_busy"))
	print("P1_ASSERT missing callback fails observably instead of hanging: %s" % fails_observably)
	if not fails_observably:
		print("P1_AGENT_ACTION_WIRING_FAILED")
		quit(1)
		return
	print("P1_AGENT_ACTION_WIRING_DONE")
	quit(0)
