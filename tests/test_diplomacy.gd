extends SceneTree
## 引擎④ 外交博弈冒烟测试：发起 / 站队 / 改目标 / 退缩(失威望) / 到期开战 / 限制
## 运行：godot --headless --path . --script res://tests/test_diplomacy.gd

const RESULT_PATH := "user://test_diplomacy_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")
	gm.set("army_count", {"England": 13, "Scotland": 6, "Wales": 4})
	gm.set("country_prestige", {"England": 50.0, "Scotland": 50.0, "Wales": 40.0})

	# ① 发起博弈
	var sp: Dictionary = gm.call("start_play", "Scotland", "England", "吞并 Lothian")
	out.append("start_play ok play_id=%d: %s" % [int(sp.get("play_id", 0)), sp.get("ok", false)])
	out.append("active plays = %d (expect 1)" % (gm.call("get_active_plays") as Array).size())

	# ② 站队
	var jp: Dictionary = gm.call("join_play", 1, "Wales", "A")
	out.append("join_play Wales->A ok: %s" % jp.get("ok", false))
	out.append("join_play duplicate ok=false: %s" % ((gm.call("join_play", 1, "Wales", "A") as Dictionary).get("ok", false) == false))
	out.append("join_play bad side ok=false: %s" % ((gm.call("join_play", 1, "Wales", "X") as Dictionary).get("ok", false) == false))

	# ③ 改目标
	var sg: Dictionary = gm.call("set_play_goal", 1, "Scotland", "附庸化")
	out.append("set_play_goal ok: %s" % sg.get("ok", false))
	out.append("set_play_goal non-party ok=false: %s" % ((gm.call("set_play_goal", 1, "France", "x") as Dictionary).get("ok", false) == false))

	# ④ 退缩 → 对方目标达成 + 退缩方失威望
	gm.set("country_prestige", {"England": 50.0, "Scotland": 50.0, "Wales": 40.0})
	var bd: Dictionary = gm.call("back_down", 1, "A")
	out.append("back_down A ok winner=B: %s" % (bd.get("ok", false) and str(bd.get("winner_side", "")) == "B"))
	out.append("retreater Scotland prestige 50->%d (expect 40)" % int(gm.get("country_prestige").get("Scotland", 0.0)))
	out.append("play resolved (active=0): %s" % ((gm.call("get_active_plays") as Array).size() == 0))

	# ⑤ 到期开战：新博弈 → 两次 tick → 战争 + 站队国入战
	gm.set("plays", [])
	gm.set("wars", [])
	gm.set("_next_war_id", 1)
	gm.set("_next_play_id", 1)
	gm.call("start_play", "Scotland", "England", "吞并 Lothian")
	gm.call("join_play", 1, "Wales", "A")
	gm.call("_tick_plays")
	out.append("after tick1 active plays=%d (expect 1)" % (gm.call("get_active_plays") as Array).size())
	out.append("after tick1 wars=%d (expect 0)" % (gm.get("wars") as Array).size())
	gm.call("_tick_plays")
	out.append("after tick2 active plays=%d (expect 0)" % (gm.call("get_active_plays") as Array).size())
	var wars2: Array = gm.get("wars")
	out.append("after tick2 wars=%d (expect 1)" % wars2.size())
	if wars2.size() > 0:
		var w: Dictionary = wars2[0]
		out.append("war A=[Scotland,Wales] B=[England]: %s" % (
			(w.get("attacker", []) as Array).has("Scotland") and
			(w.get("attacker", []) as Array).has("Wales") and
			(w.get("defender", []) as Array).has("England")))

	# ⑥ 限制：不能对已在战争中的国家发起博弈
	gm.set("plays", [])
	var sp2: Dictionary = gm.call("start_play", "Wales", "England", "独立")
	out.append("start_play vs at-war target ok=false: %s" % (sp2.get("ok", false) == false))
	out.append("start_play vs self ok=false: %s" % ((gm.call("start_play", "Wales", "Wales", "x") as Dictionary).get("ok", false) == false))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
