extends SceneTree
## 引擎④-CB 战争理由冒烟测试（Master 8/13）：
## 文化推导 / 通用 CB 可用性判定（附庸化/受保护国/夺取至高王/附庸独立）/ 1年CB计时 / 要求X同意后关系落地
## 运行：godot --headless --path . --script res://tests/test_cb.gd

const RESULT_PATH := "user://test_cb_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")
	gm.set("_country_list", [
		{"id": "England", "government": "monarchy"},
		{"id": "The Isles", "government": "piracy"},
		{"id": "Tyrone", "government": "tribal"},
		{"id": "Ulster", "government": "tribal"},
		{"id": "Scotland", "government": "monarchy", "liege": "England", "vassal_type": "feudal"},
		{"id": "Northumberland", "government": "monarchy", "liege": "England", "vassal_type": "feudal"},
	])
	gm.set("player_favor", {"The Isles": 90.0, "Scotland": 20.0, "Tyrone": 50.0, "Ulster": 50.0})

	# ① 文化推导（piracy=诺斯 / tribal=凯尔特 / 其余=英格兰）
	out.append("culture The Isles(norse): %s" % (gm.call("country_culture", "The Isles") == "norse"))
	out.append("culture Tyrone(celtic): %s" % (gm.call("country_culture", "Tyrone") == "celtic"))
	out.append("culture England(english): %s" % (gm.call("country_culture", "England") == "english"))

	# ② 通用 CB 可用性：Master 8/14 修正——vassalize/protectorate 不是无条件可用，
	#    需好感>80「要求」被拒获得 1 年 CB 后才可用；seize_leadership 凯尔特对凯尔特可用
	var cbs_norse: Array = gm.call("get_available_cbs", "The Isles", "England")
	out.append("norse vassalize NOT auto (before CB): %s" % (not _has_cb(cbs_norse, "vassalize")))
	gm.call("grant_requirement_cb", "The Isles", "England", "vassalize")
	var cbs_norse2: Array = gm.call("get_available_cbs", "The Isles", "England")
	out.append("norse vassalize after 1y CB: %s" % _has_cb(cbs_norse2, "vassalize"))
	var cbs_eng: Array = gm.call("get_available_cbs", "England", "The Isles")
	out.append("english protectorate NOT auto (before CB): %s" % (not _has_cb(cbs_eng, "protectorate")))
	gm.call("grant_requirement_cb", "England", "The Isles", "protectorate")
	var cbs_eng2: Array = gm.call("get_available_cbs", "England", "The Isles")
	out.append("english protectorate after 1y CB: %s" % _has_cb(cbs_eng2, "protectorate"))
	var cbs_celt: Array = gm.call("get_available_cbs", "Tyrone", "Ulster")
	out.append("celtic actor vs celtic -> seize_leadership: %s" % _has_cb(cbs_celt, "seize_leadership"))
	# ⑧ 附庸也能用通用 CB（附庸嵌套，Master 确认：英格兰 + 其附庸都能用受保护国 CB；同样需先授 CB）
	var cbs_north: Array = gm.call("get_available_cbs", "Northumberland", "Ulster")
	out.append("vassal Northumberland protectorate NOT auto: %s" % (not _has_cb(cbs_north, "protectorate")))
	gm.call("grant_requirement_cb", "Northumberland", "Ulster", "protectorate")
	var cbs_north2: Array = gm.call("get_available_cbs", "Northumberland", "Ulster")
	out.append("vassal Northumberland protectorate after CB (附庸嵌套): %s" % _has_cb(cbs_north2, "protectorate"))

	# ③ 附庸独立（Master 8/13）：独立 CB 通用，附庸随时可独立（不受好感度限制；叛乱与否交 LLM）
	gm.set("player_country_id", "Scotland")
	var cbs_lo: Array = gm.call("get_available_cbs", "Scotland", "England")
	out.append("vassal low favor -> independence: %s" % _has_cb(cbs_lo, "independence"))
	gm.set("player_favor", {"The Isles": 90.0, "England": 90.0, "Tyrone": 50.0, "Ulster": 50.0})
	var cbs_hi: Array = gm.call("get_available_cbs", "Scotland", "England")
	out.append("vassal high favor -> independence still available: %s" % _has_cb(cbs_hi, "independence"))
	gm.set("player_country_id", "England")

	# ④ personal_union（要求联合统治拒绝后 1 年）：未授予无，授予后可用
	var cbs_pu0: Array = gm.call("get_available_cbs", "Tyrone", "Ulster")
	out.append("personal_union not granted -> absent: %s" % (not _has_cb(cbs_pu0, "personal_union")))
	gm.call("grant_requirement_cb", "Tyrone", "Ulster", "personal_union")
	var cbs_pu1: Array = gm.call("get_available_cbs", "Tyrone", "Ulster")
	out.append("personal_union granted -> available: %s" % _has_cb(cbs_pu1, "personal_union"))
	out.append("has_cb true: %s" % gm.call("has_cb", "Tyrone", "Ulster", "personal_union"))

	# ⑤ 1 年 CB 计时：12 次 tick 后失效
	for i in 12:
		gm.call("_tick_cbs")
	out.append("after 12 months cb expired: %s" % (not gm.call("has_cb", "Tyrone", "Ulster", "personal_union")))

	# ⑥ 要求 X 同意 → 建立关系（附庸 / 联合统治）
	gm.call("grant_requirement_cb", "England", "The Isles", "protectorate")
	out.append("grant protectorate cb ok: %s" % gm.call("has_cb", "England", "The Isles", "protectorate"))
	var res_v: Dictionary = gm.call("establish_requirement", "The Isles", "Scotland", "vassalize")
	out.append("establish vassal: Scotland liege -> The Isles: %s" % (
		gm.get("runtime_liege").get("Scotland", "") == "The Isles" and res_v.get("ok", false)))
	var res_u: Dictionary = gm.call("establish_requirement", "Tyrone", "Ulster", "personal_union")
	out.append("establish union: Ulster -> Tyrone: %s" % (
		gm.get("runtime_union").get("Ulster", "") == "Tyrone" and res_u.get("ok", false)))

	# ⑦ 附庸税（Master 8/13）：附庸 -3 队上限 + 超上限直接降；受保护国不扣
	gm.set("runtime_liege", {})
	gm.set("runtime_vassal_type", {})
	gm.set("runtime_union", {})
	gm.set("province_owner", {})
	gm.set("army_count", {"The Isles": 5, "Scotland": 8, "Tyrone": 3, "Ulster": 8, "England": 10})
	out.append("vassal tax: Ulster cap before = %d (expect 5)" % int(gm.call("get_army_cap", "Ulster")))
	gm.call("establish_requirement", "The Isles", "Ulster", "vassalize")
	out.append("vassal tax: Ulster cap after vassal = %d (expect 2)" % int(gm.call("get_army_cap", "Ulster")))
	out.append("vassal tax: Ulster army clamped 8 -> %d (expect 2)" % int(gm.get("army_count").get("Ulster", 0)))
	gm.set("runtime_liege", {})
	gm.set("runtime_vassal_type", {})
	gm.set("army_count", {"The Isles": 5, "Scotland": 8, "Tyrone": 3, "Ulster": 8, "England": 10})
	gm.call("establish_requirement", "England", "Ulster", "protectorate")
	out.append("vassal tax: Ulster protectorate cap = %d (expect 5, 受保护国不扣)" % int(gm.call("get_army_cap", "Ulster")))

	# ⑨ 防环（DAG，Master 8/13）：宗主/附庸树应有向无环；运行时关系不能成环
	gm.set("runtime_liege", {})
	gm.set("runtime_vassal_type", {})
	gm.set("runtime_union", {})
	out.append("dag: static + empty runtime acyclic: %s" % (not gm.call("liege_graph_has_cycle")))
	gm.call("establish_requirement", "The Isles", "Scotland", "vassalize")   # 群岛→苏格兰附庸 OK
	var res_cyc: Dictionary = gm.call("establish_requirement", "Scotland", "The Isles", "vassalize")  # 苏格兰→群岛 会成环
	out.append("dag: cycle attempt (Scotland->The Isles) rejected: %s" % (not res_cyc.get("ok", true)))
	out.append("dag: still acyclic after reject: %s" % (not gm.call("liege_graph_has_cycle")))
	var res_self: Dictionary = gm.call("establish_requirement", "The Isles", "The Isles", "vassalize")
	out.append("dag: self-liege rejected: %s" % (not res_self.get("ok", true)))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()


func _has_cb(cbs: Array, cb_id: String) -> bool:
	for c in cbs:
		if str(c.get("id", "")) == cb_id:
			return true
	return false
