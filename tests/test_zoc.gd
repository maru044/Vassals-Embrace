extends SceneTree
## 引擎④-T4 ZoC 接入冒烟测试（Master 8/12 定）：
## ① 和平无 ZoC（路径畅通）
## ② 战争：敌方要塞 ZoC 阻挡 → 目标不可达 + find_blocking_fort 返回要塞（先攻清障）
## ③ 玩家不能下令到被阻挡目标；可下令到要塞围攻
## ④ 破城 → ZoC 归属转变：要塞归攻方后敌方 ZoC 消失，道路畅通
## ⑤ 敌军受困：敌国军队在 ZoC 内必经要塞（攻占要塞才能前进），要塞主人畅通
## 运行：godot --headless --path . --script res://tests/test_zoc.gd

const RESULT_PATH := "user://test_zoc_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")

	# 自建小地图（链式）：H(England 首都) -- X -- F(Scotland 要塞 fort=3) -- D(Scotland 首都)
	# F fort=3 → ZoC 覆盖 {F, X, D}（自身 + 相邻圈）
	gm.set("_adjacency", {
		"H": {"X": "land"},
		"X": {"H": "land", "F": "land"},
		"F": {"X": "land", "D": "land"},
		"D": {"F": "land"},
	})
	gm.set("province_owner", {"H": "England", "X": "Scotland", "F": "Scotland", "D": "Scotland"})
	gm.set("province_buildings", {"H": {"fort": 0}, "X": {"fort": 0}, "F": {"fort": 3}, "D": {"fort": 0}})
	gm.set("capital_province", {"England": "H", "Scotland": "D"})
	gm.set("army_position", {"England": "H", "Scotland": "D"})
	gm.set("wars", [])

	# ① 和平无 ZoC：最短路径 H->D 穿越 X、F、D 全程畅通；无阻挡要塞
	var p_peace: Array = gm.call("_shortest_path_zoc", "England", "H", "D")
	out.append("peace path H->D = [%s] (expect [H, X, F, D]): %s" % [", ".join(p_peace), ", ".join(p_peace) == "H, X, F, D"])
	out.append("peace find_blocking_fort = '%s' (expect ''): %s" % [
		str(gm.call("find_blocking_fort", "England", "D")), str(gm.call("find_blocking_fort", "England", "D")) == ""])

	# ② 宣战：敌方要塞 F 阻挡 → D 不可达；find_blocking_fort 返回 F（先攻要塞清障）
	gm.call("declare_war", "England", "Scotland")
	var p_war: Array = gm.call("_shortest_path_zoc", "England", "H", "D")
	out.append("war path H->D blocked (empty): %s" % p_war.is_empty())
	var blk: String = str(gm.call("find_blocking_fort", "England", "D"))
	out.append("war find_blocking_fort = '%s' (expect 'F'): %s" % [blk, blk == "F"])
	var reach: Array = gm.call("get_reachable_provinces", "England")
	reach.sort()
	out.append("war reachable(H) = [%s] (expect [F, X]; D 被 ZoC 阻挡): %s" % [
		", ".join(reach), ", ".join(reach) == "F, X"])

	# ③ 玩家不能直接下令到被阻挡的 D；可下令到要塞 F 围攻
	var r_d: Dictionary = gm.call("can_move_to", "England", "D")
	var r_f: Dictionary = gm.call("can_move_to", "England", "F")
	out.append("can_move_to D (blocked) ok=false: %s (reason=%s)" % [not r_d.get("ok", true), r_d.get("reason", "")])
	out.append("can_move_to F (fort) ok=true: %s" % r_f.get("ok", false))

	# ④ 破城 → ZoC 归属转变：F 归 England 后，敌方 ZoC 消失，H->D 畅通；阻挡清空
	gm.call("_take_province", "F", "England", "Scotland")
	out.append("ZoC flip: F owner = %s (expect England): %s" % [
		gm.get("province_owner").get("F", ""), gm.get("province_owner").get("F", "") == "England"])
	var p_after: Array = gm.call("_shortest_path_zoc", "England", "H", "D")
	out.append("after capture path H->D = [%s] open: %s" % [", ".join(p_after), not p_after.is_empty()])
	var blk2: String = str(gm.call("find_blocking_fort", "England", "D"))
	out.append("after capture find_blocking_fort = '' (expect ''): %s" % (blk2 == ""))

	# ⑤ 敌军受困：Scotland 在 D，England 占 F（ZoC 归 England）→ Scotland 必经 F（攻要塞）才能前进，England 畅通
	gm.set("army_position", {"England": "F", "Scotland": "D"})
	gm.set("wars", [])
	gm.call("declare_war", "England", "Scotland")
	var p_eng: Array = gm.call("_shortest_path_zoc", "England", "F", "H")
	var p_scot: Array = gm.call("_shortest_path_zoc", "Scotland", "D", "H")
	out.append("ally England F->H path = [%s] passes freely: %s" % [", ".join(p_eng), not p_eng.is_empty()])
	out.append("enemy Scotland D->H path = [%s] must pass fort F: %s" % [", ".join(p_scot), p_scot.has("F")])
	out.append("ZoC flip ally free / enemy forced: %s" % (not p_eng.is_empty() and p_scot.has("F")))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
