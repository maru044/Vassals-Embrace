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
	])
	gm.set("player_favor", {"The Isles": 90.0, "Scotland": 20.0, "Tyrone": 50.0, "Ulster": 50.0})

	# ① 文化推导（piracy=诺斯 / tribal=凯尔特 / 其余=英格兰）
	out.append("culture The Isles(norse): %s" % (gm.call("country_culture", "The Isles") == "norse"))
	out.append("culture Tyrone(celtic): %s" % (gm.call("country_culture", "Tyrone") == "celtic"))
	out.append("culture England(english): %s" % (gm.call("country_culture", "England") == "english"))

	# ② 通用 CB 可用性：诺斯→附庸化 / 英格兰→受保护国 / 凯尔特对凯尔特→夺取至高王
	var cbs_norse: Array = gm.call("get_available_cbs", "The Isles", "England")
	out.append("norse actor -> vassalize: %s" % _has_cb(cbs_norse, "vassalize"))
	var cbs_eng: Array = gm.call("get_available_cbs", "England", "The Isles")
	out.append("english actor -> protectorate: %s" % _has_cb(cbs_eng, "protectorate"))
	var cbs_celt: Array = gm.call("get_available_cbs", "Tyrone", "Ulster")
	out.append("celtic actor vs celtic -> seize_leadership: %s" % _has_cb(cbs_celt, "seize_leadership"))

	# ③ 附庸独立：玩家是附庸 + 对宗主好感低才有
	gm.set("player_country_id", "Scotland")
	var cbs_lo: Array = gm.call("get_available_cbs", "Scotland", "England")
	out.append("vassal low favor -> independence: %s" % _has_cb(cbs_lo, "independence"))
	gm.set("player_favor", {"The Isles": 90.0, "England": 90.0, "Tyrone": 50.0, "Ulster": 50.0})
	var cbs_hi: Array = gm.call("get_available_cbs", "Scotland", "England")
	out.append("vassal high favor -> no independence: %s" % (not _has_cb(cbs_hi, "independence")))
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
