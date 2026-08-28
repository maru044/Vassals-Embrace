extends SceneTree


func _initialize() -> void:
	print("P1_HEARTBEAT opening-mission initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P1_TIMEOUT opening-mission exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SaveManager")
	if gm == null or sm == null:
		push_error("P1_FAIL required autoload missing")
		quit(2)
		return

	gm.call("start_new_game", "England")
	await process_frame
	var play_count: int = (gm.call("get_active_plays") as Array).size()
	var completed_before: bool = bool(gm.call("is_mission_completed", "england_subdue_wales"))
	var opening_state: String = str(gm.call("mission_state", "england_subdue_wales"))
	var immediate_claim: Dictionary = gm.call("complete_mission", "england_subdue_wales")

	print("P1_ASSERT opening revolt active: %s (plays=%d)" % [play_count == 1, play_count])
	print("P1_ASSERT mission not silently completed: %s" % (not completed_before))
	print("P1_ASSERT mission locked until revolt suppressed: %s (state=%s)" % [opening_state == "locked", opening_state])
	print("P1_ASSERT immediate claim rejected: %s (result=%s)" % [not bool(immediate_claim.get("ok", false)), immediate_claim])

	if play_count != 1 or completed_before or opening_state != "locked" or bool(immediate_claim.get("ok", false)):
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return

	var play_id: int = int((gm.call("get_active_plays") as Array)[0].get("id", 0))
	var backdown: Dictionary = gm.call("back_down", play_id, "A")
	var suppressed_state: String = str(gm.call("mission_state", "england_subdue_wales"))
	print("P1_ASSERT Wales backdown resolves play: %s" % bool(backdown.get("ok", false)))
	print("P1_ASSERT mission available after suppression: %s (state=%s)" % [suppressed_state == "available", suppressed_state])
	if not bool(backdown.get("ok", false)) or suppressed_state != "available":
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return

	var snapshot: Dictionary = gm.call("serialize")
	gm.set("mission_flags", {})
	gm.call("deserialize", snapshot)
	var restored_state: String = str(gm.call("mission_state", "england_subdue_wales"))
	print("P1_ASSERT suppression survives deserialize: %s (state=%s)" % [restored_state == "available", restored_state])
	if restored_state != "available":
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return

	gm.call("start_new_game", "England")
	for i in 4:
		if not (gm.call("get_active_plays") as Array).is_empty():
			gm.call("_tick_plays")
	var wars: Array = gm.get("wars")
	var revolt_war_has_cb: bool = wars.size() == 1 and str(wars[0].get("cb", "")) == "welsh_revolt"
	print("P1_ASSERT escalated revolt preserves CB: %s" % revolt_war_has_cb)
	if not revolt_war_has_cb:
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return
	var peace: Dictionary = gm.call("sign_peace", int(wars[0].get("id", 0)), "B", [])
	var peace_state: String = str(gm.call("mission_state", "england_subdue_wales"))
	print("P1_ASSERT England peace victory unlocks mission: %s (state=%s)" % [bool(peace.get("ok", false)) and peace_state == "available", peace_state])
	if not bool(peace.get("ok", false)) or peace_state != "available":
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return

	var legacy: Dictionary = gm.call("serialize")
	legacy["mission_flags"] = {}
	gm.call("deserialize", legacy)
	var migrated_state: String = str(gm.call("mission_state", "england_subdue_wales"))
	print("P1_ASSERT legacy resolved revolt migrates: %s (state=%s)" % [migrated_state == "available", migrated_state])
	if migrated_state != "available":
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return
	var saved: bool = bool(sm.call("save_game_to_slot", 2, gm.call("serialize")))
	print("P1_ASSERT restart fixture saved: %s" % saved)
	if not saved:
		print("P1_OPENING_MISSION_FAILED")
		quit(1)
		return
	print("P1_OPENING_MISSION_DONE")
	quit(0)
