extends SceneTree
## 引擎⑦-任务树系统冒烟测试（Master 8/14）：
## missions.json 加载 / 玩家任务列表 / 三态(completed/available/locked) / 各条件键判定
## （subject_of / favor_greater_than / flag_set / vassalize_any）/ 事件 flags 置位（老同盟）/
## complete_mission 领奖（grant_cb 限时CB 3年 + 威望/金币）/ 前置解锁 / 重复完成与未满足拒绝
## 运行：godot --headless --path . --script res://tests/test_missions.gd

const RESULT_PATH := "user://test_missions_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "Scotland")
	gm.call("_load_countries")

	# ① missions.json 加载（苏格兰 9 条任务）
	out.append("missions loaded (scotland_recover_isles): %s" % (not gm.call("get_mission", "scotland_recover_isles").is_empty()))
	out.append("missions loaded (scotland_great_britain): %s" % (not gm.call("get_mission", "scotland_great_britain").is_empty()))
	var player_missions: Array = gm.call("get_player_missions")
	out.append("Scotland player missions = 9: %s" % (player_missions.size() == 9))

	# ② 初始三态：无前置任务因条件未满足 locked；有前置任务因前置未完成也 locked
	out.append("recover_isles init locked: %s" % (gm.call("mission_state", "scotland_recover_isles") == "locked"))
	out.append("isles_guard init locked (parent): %s" % (gm.call("mission_state", "scotland_isles_guard") == "locked"))
	out.append("auld_alliance init locked (flag): %s" % (gm.call("mission_state", "scotland_auld_alliance") == "locked"))

	# ③ 附庸化判定（subject 语义：附庸+受保护国均算）：The Isles/Orkney/Shetland 成为苏格兰附庸 → 收回群岛 available
	gm.set("runtime_liege", {"The Isles": "Scotland", "Orkney": "Scotland", "Shetland": "Scotland"})
	out.append("recover_isles available after vassals: %s" % (gm.call("mission_state", "scotland_recover_isles") == "available"))

	# ④ 完成任务：收回群岛 → 领奖 → completed；重复完成被拒
	gm.set("country_prestige", {"Scotland": 50.0})
	var res_r: Dictionary = gm.call("complete_mission", "scotland_recover_isles")
	out.append("complete recover_isles ok: %s" % bool(res_r.get("ok", false)))
	out.append("recover_isles completed: %s" % gm.call("is_mission_completed", "scotland_recover_isles"))
	out.append("recover_isles state=completed: %s" % (gm.call("mission_state", "scotland_recover_isles") == "completed"))
	var res_r2: Dictionary = gm.call("complete_mission", "scotland_recover_isles")
	out.append("repeat complete rejected: %s" % (not bool(res_r2.get("ok", false))))

	# ⑤ 前置解锁 + 好感判定：群岛守护前置完成但好感未达标 → locked；达标 → available
	out.append("isles_guard unlocked but favor low -> locked: %s" % (gm.call("mission_state", "scotland_isles_guard") == "locked"))
	gm.set("player_favor", {"The Isles": 70.0, "Orkney": 70.0, "Shetland": 70.0})
	out.append("isles_guard available after favor: %s" % (gm.call("mission_state", "scotland_isles_guard") == "available"))

	# ⑥ 老同盟：事件 flag 置位 → available → 完成领威望+金币（reward_effects）
	gm.call("set_mission_flag", "scotland_auld_alliance_done")
	out.append("auld_alliance available after flag: %s" % (gm.call("mission_state", "scotland_auld_alliance") == "available"))
	gm.set("country_gold", {"Scotland": 100.0})
	var res_a: Dictionary = gm.call("complete_mission", "scotland_auld_alliance")
	out.append("complete auld_alliance ok: %s" % bool(res_a.get("ok", false)))
	out.append("auld_alliance prestige +10 (=60): %s" % (float(gm.get("country_prestige").get("Scotland", 0.0)) == 60.0))
	out.append("auld_alliance gold +25 (=125): %s" % (float(gm.get("country_gold").get("Scotland", 0.0)) == 125.0))

	# ⑦ vassalize_any（进军爱尔兰）：附庸任一爱尔兰国家 → available → 完成授爱尔兰全境附庸 CB 3年（36 月）
	gm.set("runtime_liege", {"Kildare": "Scotland"})
	out.append("march_into_ireland available after 1 vassal: %s" % (gm.call("mission_state", "scotland_march_into_ireland") == "available"))
	gm.call("complete_mission", "scotland_march_into_ireland")
	var cb_t: Dictionary = gm.get("cb_timers")
	var kildare_cb: int = int(cb_t.get("Scotland:Kildare:vassalize", 0))
	out.append("march reward grants vassalize CB 36mo: %s" % (kildare_cb == 36))
	var tyrone_cb: int = int(cb_t.get("Scotland:Tyrone:vassalize", 0))
	out.append("march reward covers all ireland_clan (Tyrone 36): %s" % (tyrone_cb == 36))

	# ⑧ 未完成条件时 complete 被拒（成立大不列颠 前置未完成 → locked）
	var res_g: Dictionary = gm.call("complete_mission", "scotland_great_britain")
	out.append("great_britain locked cannot complete: %s" % (not bool(res_g.get("ok", false))))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
