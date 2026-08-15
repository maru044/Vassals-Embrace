extends SceneTree
## 引擎⑧ 联合统治（Personal Union）冒烟测试：
## 建立（_create_union / establish_requirement personal_union）/ 查询 /
## 主导权转移（LLM 聊天要求成为攻，攻受互换）/ 战争夺取（NTR：移除+加入另一组织）/
## 吞并清理（主导被吞移交、成员被吞移除）/ 一国仅一组织 / 兼容映射 / sign_peace 条款落地
## 运行：godot --headless --path . --script res://tests/test_union.gd

const RESULT_PATH := "user://test_union_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "Scotland")
	gm.set("year", 1403)
	gm.set("month", 5)
	gm.set("army_count", {"Scotland": 9, "England": 13, "Wales": 2, "Tyrone": 7, "Ulster": 5})
	gm.set("capital_province", {"Scotland": "Lothian", "England": "London", "Wales": "Glamorgan", "Tyrone": "Tyrone", "Ulster": "Ulster"})
	gm.set("province_owner", {"Lothian": "Scotland", "London": "England", "Glamorgan": "Wales", "Tyrone": "Tyrone", "Ulster": "Ulster"})

	# ① 建立：Scotland 主导 + England 被联统
	var c1: Dictionary = gm.call("_create_union", "Scotland", "England")
	out.append("create union ok: %s" % c1.get("ok", false))
	out.append("union_of England lead=Scotland: %s" % (gm.call("union_of", "England").get("lead", "") == "Scotland"))
	out.append("is_union_lead Scotland: %s" % gm.call("is_union_lead", "Scotland"))
	out.append("is_union_member England: %s" % gm.call("is_union_member", "England"))
	out.append("members = [Scotland, England]: %s" % (str(gm.call("get_union_members", "Scotland")) == str(["Scotland", "England"])))

	# ② 一国仅一组织：主导国已在组织 → 不能再用 _create_union 另建
	var c2: Dictionary = gm.call("_create_union", "Scotland", "Wales")
	out.append("lead already in union -> rejected: %s" % (not c2.get("ok", false)))

	# ③ 兼容映射 runtime_union 同步
	out.append("runtime_union England -> Scotland: %s" % (gm.get("runtime_union").get("England", "") == "Scotland"))

	# ④ 主导权转移（攻受互换）：England 要求成为主导
	var t1: Dictionary = gm.call("transfer_union_lead", "England")
	out.append("transfer ok: %s" % t1.get("ok", false))
	out.append("new lead=England: %s" % (gm.call("union_of", "England").get("lead", "") == "England"))
	out.append("members swapped [England, Scotland]: %s" % (str(gm.call("get_union_members", "England")) == str(["England", "Scotland"])))
	out.append("old lead now member: %s" % gm.call("is_union_member", "Scotland"))

	# ⑤ 转移边界：已是主导不可再转 / 不在组织不可转
	out.append("transfer lead again rejected: %s" % (not gm.call("transfer_union_lead", "England").get("ok", false)))
	out.append("transfer non-member rejected: %s" % (not gm.call("transfer_union_lead", "Wales").get("ok", false)))

	# ⑥ 战争夺取：夺回主导 → Wales 独立并入（新建组织）
	gm.call("transfer_union_lead", "Scotland")   # Scotland 变回主导（攻受互换），org = Scotland + [England]
	var s1: Dictionary = gm.call("seize_union", "Wales", "Scotland")
	out.append("seize union (new member) ok: %s" % s1.get("ok", false))
	out.append("after seize members [Scotland, England, Wales]: %s" % (str(gm.call("get_union_members", "Scotland")) == str(["Scotland", "England", "Wales"])))

	# ⑦ 战争夺取 / NTR：从另一组织抢走成员
	gm.call("_create_union", "Tyrone", "Ulster")
	out.append("org2 Tyrone+Ulster: %s" % (str(gm.call("get_union_members", "Tyrone")) == str(["Tyrone", "Ulster"])))
	var s2: Dictionary = gm.call("seize_union", "Ulster", "Scotland")
	out.append("seize member NTR ok: %s" % s2.get("ok", false))
	out.append("Ulster now in Scotland org: %s" % (gm.call("union_of", "Ulster").get("lead", "") == "Scotland"))
	out.append("org2 dissolved after NTR (Tyrone no org): %s" % (not gm.call("in_union", "Tyrone")))

	# ⑧ 吞并清理：成员被吞移除 / 主导被吞移交
	gm.call("_annex_country", "Scotland", "England")
	out.append("England annexed removed from union: %s" % (not gm.call("in_union", "England")))
	out.append("Scotland org members after annex [Scotland, Wales, Ulster]: %s" % (str(gm.call("get_union_members", "Scotland")) == str(["Scotland", "Wales", "Ulster"])))
	gm.call("_annex_country", "Tyrone", "Scotland")   # Tyrone 吞并 Scotland（主导）
	out.append("Scotland (lead) annexed -> lead transferred to Wales: %s" % (gm.call("union_of", "Wales").get("lead", "") == "Wales"))
	out.append("Scotland no longer in any union: %s" % (not gm.call("in_union", "Scotland")))

	# ⑨ establish_requirement personal_union（走 _create_union）
	gm.set("unions", [])
	gm.set("_next_union_id", 1)
	gm.call("_sync_runtime_union")
	var e1: Dictionary = gm.call("establish_requirement", "Tyrone", "England", "personal_union")
	out.append("establish_requirement union ok: %s" % e1.get("ok", false))
	out.append("runtime_union England -> Tyrone: %s" % (gm.get("runtime_union").get("England", "") == "Tyrone"))

	# ⑩ sign_peace personal_union 条款 → 走 _apply_play_goal → _create_union
	gm.set("unions", [])
	gm.set("_next_union_id", 1)
	gm.call("_sync_runtime_union")
	var wr: Dictionary = gm.call("declare_war", "Wales", "England")
	var wid: int = int(wr.get("war_id", 0))
	var peace: Dictionary = gm.call("sign_peace", wid, "A", [{"type": "personal_union", "target": "England"}])
	out.append("sign_peace personal_union ok: %s" % peace.get("ok", false))
	out.append("peace union Wales lead: %s" % (gm.call("union_of", "England").get("lead", "") == "Wales"))

	# ⑪ 边界：自我夺取 / 无效建立 / 主导国再建新组织
	out.append("seize self rejected: %s" % (not gm.call("seize_union", "Wales", "Wales").get("ok", false)))
	out.append("create empty lead rejected: %s" % (not gm.call("_create_union", "", "England").get("ok", false)))
	out.append("create empty member rejected: %s" % (not gm.call("_create_union", "Wales", "").get("ok", false)))

	# ⑫ 调试注入（选国界面「演示联合统治」用）：玩家主导 + 两个被联统国
	gm.call("_load_countries")
	gm.set("unions", [])
	gm.set("_next_union_id", 1)
	gm.call("_sync_runtime_union")
	gm.set("player_country_id", "Scotland")
	var d1: Dictionary = gm.call("debug_inject_demo_union", "Scotland")
	out.append("debug inject ok: %s" % d1.get("ok", false))
	out.append("debug inject lead=Scotland: %s" % (gm.call("union_of", "Scotland").get("lead", "") == "Scotland"))
	out.append("debug inject 3 members (lead+2): %s" % (gm.call("get_union_members", "Scotland").size() == 3))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
