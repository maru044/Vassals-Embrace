extends SceneTree
## 引擎⑧ 爱尔兰至高王国冒烟测试：
## 凝聚力=统一爱尔兰局势值(unify_ireland) / 部落间联姻+5 / 召集诸部（非至高王/无博弈/凝聚力不足/成功）/
## 组织级改值（AI 至高王也生效）
## 运行：godot --headless --path . --script res://tests/test_high_kingdom.gd

const RESULT_PATH := "user://test_high_kingdom_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.call("_load_countries")
	gm.call("_ensure_situations")
	gm.call("_init_situations")
	gm.set("player_country_id", "Tyrone")
	gm.set("high_king_id", "Tyrone")
	gm.set("army_count", {"Tyrone": 7, "Ulster": 5, "Breifne": 5, "Sligo": 5, "Westmeath": 5, "England": 13})
	gm.set("capital_province", {"Tyrone": "Tyrone", "Ulster": "Ulster", "Breifne": "Breifne", "Sligo": "Sligo", "Westmeath": "Westmeath", "England": "London"})
	gm.set("province_owner", {"Tyrone": "Tyrone", "Ulster": "Ulster", "Breifne": "Breifne", "Sligo": "Sligo", "Westmeath": "Westmeath", "London": "England"})

	# ① 凝聚力 = unify_ireland（初始 0）
	out.append("cohesion initial = 0: %s" % (gm.call("get_high_kingdom_cohesion") == 0))

	# ② 成员 = 16 部（government=tribal）
	var members: Array = gm.call("get_high_kingdom_members")
	out.append("high kingdom members >= 16: %s" % (members.size() >= 16))
	out.append("Tyrone in members: %s" % members.has("Tyrone"))

	# ③ 部落间联姻 → 凝聚力 +5（Tyrone + Ulster 联统）
	gm.set("situation_value", {"unify_ireland": 0})
	gm.call("_create_union", "Tyrone", "Ulster")
	out.append("tribal union cohesion +5 (0->5): %s" % (gm.call("get_high_kingdom_cohesion") == 5))

	# ④ 非爱尔兰联统不加（Tyrone + England，England 非部落）
	gm.set("situation_value", {"unify_ireland": 5})
	gm.set("unions", [])
	gm.call("_sync_runtime_union")
	gm.call("_create_union", "Tyrone", "England")
	out.append("non-tribal union no cohesion (stays 5): %s" % (gm.call("get_high_kingdom_cohesion") == 5))

	# ⑤ 召集：非至高王拒绝
	gm.set("player_country_id", "Ulster")
	var r1: Dictionary = gm.call("call_allies_to_war", 1)
	out.append("non-high-king rejected: %s" % (not r1.get("ok", false)))
	gm.set("player_country_id", "Tyrone")

	# ⑥ 召集：无博弈拒绝
	var r2: Dictionary = gm.call("call_allies_to_war", 999)
	out.append("no play rejected: %s" % (not r2.get("ok", false)))

	# ⑦ 召集：凝聚力不足（0 → 可召 0）
	gm.set("situation_value", {"unify_ireland": 0})
	var r3: Dictionary = gm.call("call_allies_to_war", 1)
	out.append("cohesion insufficient rejected: %s" % (not r3.get("ok", false)))

	# ⑧ 召集成功：凝聚力 40（可召 4），外来者 England 对 Ulster 发起博弈
	gm.set("situation_value", {"unify_ireland": 40})
	gm.set("plays", [])
	gm.set("_next_play_id", 1)
	var sp: Dictionary = gm.call("start_play", "England", "Ulster", "附庸化", "vassalize")
	var play_id: int = int(sp.get("play_id", 0))
	var r4: Dictionary = gm.call("call_allies_to_war", play_id)
	out.append("call allies ok: %s" % r4.get("ok", false))
	var called: Array = r4.get("called", [])
	out.append("called == 4 (cohesion 40/10): %s" % (called.size() == 4))
	var play_after: Dictionary = gm.call("_find_play_by_id", play_id)
	var bside: Array = play_after.get("sides", {}).get("B", [])
	out.append("called tribes joined B side: %s" % (called.all(func(c): return bside.has(str(c)))))
	out.append("cohesion deducted 40-40=0: %s" % (gm.call("get_high_kingdom_cohesion") == 0))
	# 目标部落 Ulster 本就在 B 方（被动应战，未额外消耗）
	out.append("target Ulster already in B: %s" % bside.has("Ulster"))

	# ⑨ 组织级改值：玩家非至高王时 AI 至高王的凝聚力也能改
	gm.set("player_country_id", "Ulster")
	gm.set("high_king_id", "Tyrone")
	gm.set("situation_value", {"unify_ireland": 10})
	gm.call("_change_situation_value", "unify_ireland", 5)
	out.append("org-level change works (non-player high king): %s" % (gm.call("get_high_kingdom_cohesion") == 15))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
