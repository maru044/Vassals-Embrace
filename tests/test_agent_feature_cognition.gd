extends SceneTree


func _initialize() -> void:
	print("P1_HEARTBEAT agent-feature cognition initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P1_TIMEOUT agent-feature cognition exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var pm: Node = root.get_node_or_null("/root/PromptManager")
	var world_ai: Node = root.get_node_or_null("/root/WorldAI")
	if gm == null or pm == null or world_ai == null:
		push_error("P1_FAIL required autoload missing")
		quit(2)
		return
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	gm.call("start_new_game", "England")
	var gold: Dictionary = gm.get("country_gold").duplicate(true)
	gold["England"] = 20.0
	gold["Scotland"] = 35.0
	gm.set("country_gold", gold)
	gm.set("loans", {})
	var loan: Dictionary = gm.call("take_loan")
	var engine_has_loan: bool = bool(loan.get("ok", false)) and float(gm.get("country_gold").get("England", 0.0)) == 30.0 and float(gm.get("loans").get("England", 0.0)) == 10.0
	print("P1_ASSERT engine loan feature exists: %s" % engine_has_loan)

	var mechanics: String = str(pm.call("get_prompt_content", "Game_Mechanics.md"))
	var tools_manual: String = str(pm.call("get_prompt_content", "System_Tools_Manual.md"))
	var prompt_knows_loan: bool = mechanics.contains("贷款") and mechanics.contains("年利率 **5%**")
	var manual_routes_loan: bool = tools_manual.contains("贷款功能已实现") and tools_manual.contains("经济面板")
	print("P1_ASSERT mechanics prompt knows loan: %s" % prompt_knows_loan)
	print("P1_ASSERT tools manual routes loan correctly: %s" % manual_routes_loan)

	var chat: Node = game.get("_chat_ui")
	var chat_state: String = str(chat.call("_world_state_text")) if chat != null else ""
	var world_state: String = str(world_ai.call("_world_state_text"))
	print("P1_OBSERVE chat state:\n%s" % chat_state)
	print("P1_OBSERVE world state:\n%s" % world_state)
	var chat_sees_loan: bool = chat_state.contains("玩家经济") and chat_state.contains("贷款 10") and chat_state.contains("金币 30")
	var world_sees_loan: bool = world_state.contains("金币 35") and world_state.contains("贷款 0") and world_state.contains("金币 30") and world_state.contains("贷款 10")
	print("P1_ASSERT chat Agent sees live loan state: %s" % chat_sees_loan)
	print("P1_ASSERT world AI sees live loan state: %s" % world_sees_loan)

	if not engine_has_loan or not prompt_knows_loan or not manual_routes_loan or not chat_sees_loan or not world_sees_loan:
		print("P1_AGENT_FEATURE_COGNITION_FAILED")
		quit(1)
		return
	print("P1_AGENT_FEATURE_COGNITION_DONE")
	quit(0)
