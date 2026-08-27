extends SceneTree


func _initialize() -> void:
	print("P1_HEARTBEAT opening-mission restart initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P1_TIMEOUT opening-mission restart exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SaveManager")
	if gm == null or sm == null:
		push_error("P1_FAIL required autoload missing")
		quit(2)
		return
	var saved: Dictionary = sm.call("load_game_from_slot", 2)
	if saved.is_empty():
		push_error("P1_FAIL opening-mission restart fixture missing")
		quit(3)
		return
	gm.call("deserialize", saved)
	var flag_restored: bool = bool(gm.get("mission_flags").get("england_welsh_revolt_suppressed", false))
	var state: String = str(gm.call("mission_state", "england_subdue_wales"))
	var claim: Dictionary = gm.call("complete_mission", "england_subdue_wales")
	print("P1_ASSERT restart suppression flag restored: %s" % flag_restored)
	print("P1_ASSERT restart mission available: %s (state=%s)" % [state == "available", state])
	print("P1_ASSERT restart mission claim succeeds: %s" % bool(claim.get("ok", false)))
	if not flag_restored or state != "available" or not bool(claim.get("ok", false)):
		print("P1_OPENING_MISSION_RESTART_FAILED")
		quit(1)
		return
	print("P1_OPENING_MISSION_RESTART_DONE")
	quit(0)
