extends SceneTree
## 引擎③ 战斗结算器冒烟测试：士气公式 / 交战伤害 / 无减员 / 撤退 / 即时投降 / 恢复 / 首都沦陷计时
## 引擎④-战争前置：只在战争状态交战 + 盟友同侧合并对敌（Master 8/12）
## 运行：godot --headless --path . --script res://tests/test_battle.gd

const RESULT_PATH := "user://test_battle_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")
	gm.set("army_count", {"England": 13, "Scotland": 6, "Wales": 4})
	gm.set("capital_province", {"England": "London", "Scotland": "Lothian", "Wales": "Glamorgan"})
	gm.set("province_owner", {"London": "England", "Lothian": "Scotland", "Glamorgan": "Wales"})

	# ① 总士气公式：基础士气 10 × 队数
	out.append("England total morale = %d (expect 130)" % int(gm.call("get_total_morale", "England")))
	out.append("Scotland total morale = %d (expect 60)" % int(gm.call("get_total_morale", "Scotland")))

	# ② 和平时期同省不交战（Master 8/12：只有战争状态才战斗）
	gm.set("wars", [])
	gm.set("army_position", {"England": "Lothian", "Scotland": "Lothian"})
	gm.set("army_morale", {"England": 130.0, "Scotland": 60.0})
	gm.call("_resolve_battles")
	var m0: Dictionary = gm.get("army_morale")
	out.append("peace no battle (England=130 Scotland=60): %s" % (
		m0.get("England", 0.0) == 130.0 and m0.get("Scotland", 0.0) == 60.0))

	# ③ 宣战后交战：士气下降、不低于 0、无减员
	gm.set("army_position", {"England": "Lothian", "Scotland": "Lothian"})
	gm.set("army_morale", {"England": 130.0, "Scotland": 60.0})
	var war_res: Dictionary = gm.call("declare_war", "England", "Scotland")
	out.append("declare_war ok war_id=%d: %s" % [int(war_res.get("war_id", 0)), war_res.get("ok", false)])
	gm.call("_resolve_battles")
	var m1: Dictionary = gm.get("army_morale")
	var ea: float = m1.get("England", 0.0)
	var sa: float = m1.get("Scotland", 0.0)
	out.append("battle England 130->%d / Scotland 60->%d (both should drop, >=0)" % [int(ea), int(sa)])
	out.append("battle damage ok: %s" % (ea < 130.0 and sa < 60.0 and ea >= 0.0 and sa >= 0.0))
	out.append("army_count unchanged: %s" % (gm.get("army_count").get("England", 0) == 13 and gm.get("army_count").get("Scotland", 0) == 6))

	# ④ 非首都省被打败 → 撤退回首都
	gm.set("army_position", {"England": "London", "Scotland": "Wales"})
	gm.set("army_morale", {"England": 130.0, "Scotland": -5.0})
	gm.call("_handle_routed", "Scotland")
	var pos: Dictionary = gm.get("army_position")
	out.append("Scotland routed -> capital Lothian: %s (pos=%s)" % [pos.get("Scotland", "") == "Lothian", pos.get("Scotland", "")])

	# ⑤ 在本方首都被打败 → 即时自动投降
	gm.set("army_position", {"England": "London", "Scotland": "Lothian"})
	gm.set("army_morale", {"England": 130.0, "Scotland": -5.0})
	gm.call("_handle_routed", "Scotland")
	out.append("Scotland surrender at capital (instant): %s" % (gm.get("surrender_flag").get("Scotland", false) == true))

	# ⑥ 士气恢复 +20% 最大（上限 = 总士气）
	gm.set("surrender_flag", {})
	gm.set("army_morale", {"England": 65.0, "Scotland": 30.0})
	gm.call("_apply_morale_recovery")
	out.append("recover England 65->%d (expect 91)" % int(gm.get("army_morale").get("England", 0.0)))
	out.append("recover Scotland 30->%d (expect 42)" % int(gm.get("army_morale").get("Scotland", 0.0)))
	gm.set("army_morale", {"England": 130.0, "Scotland": 30.0})
	gm.call("_apply_morale_recovery")
	out.append("recover England full 130->%d (expect 130, clamp)" % int(gm.get("army_morale").get("England", 0.0)))

	# ⑦ 首都沦陷 ≥6 月 → 自动投降
	gm.set("surrender_flag", {})
	gm.set("capital_lost_months", {})
	gm.set("province_owner", {"London": "England", "Lothian": "England"})   # Scotland 首都被占
	for i in 5:
		gm.call("_update_capital_occupation")
	out.append("Scotland capital lost 5mo surrendered=%s (expect false)" % gm.get("surrender_flag").get("Scotland", false))
	gm.call("_update_capital_occupation")
	out.append("Scotland capital lost 6mo surrendered=%s (expect true)" % gm.get("surrender_flag").get("Scotland", false))

	# ⑧ 盟友同侧合并对敌、同侧不互打（England+Wales 同盟 vs Scotland，三军同省）
	gm.set("wars", [])
	gm.set("province_owner", {"London": "England", "Lothian": "Scotland", "Glamorgan": "Wales"})
	gm.set("army_position", {"England": "Lothian", "Wales": "Lothian", "Scotland": "Lothian"})
	gm.set("army_morale", {"England": 130.0, "Wales": 40.0, "Scotland": 100.0})
	var wr2: Dictionary = gm.call("declare_war", "England", "Scotland")
	gm.call("add_war_participant", "Wales", int(wr2.get("war_id", 0)), "A")
	out.append("allies England-Wales: %s (at_war=%s)" % [
		gm.call("_are_allies", "England", "Wales"), gm.call("_are_at_war", "England", "Wales")])
	out.append("at_war England-Scotland / Wales-Scotland: %s %s" % [
		gm.call("_are_at_war", "England", "Scotland"), gm.call("_are_at_war", "Wales", "Scotland")])
	gm.call("_resolve_battles")
	var m3: Dictionary = gm.get("army_morale")
	out.append("ally side England+Wales both drop: %s" % (
		m3.get("England", 0.0) < 130.0 and m3.get("Wales", 0.0) < 40.0))
	out.append("ally enemy Scotland drops: %s" % (m3.get("Scotland", 0.0) < 100.0))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
