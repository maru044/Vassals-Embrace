extends SceneTree
## 引擎④-T5 AI 军队状态机冒烟测试（Master 8/12：AI 军队行动走状态机，非 LLM）：
## ① 停战 → FREE；② 默认 MARCH_SIEGE 围敌方首都（ZoC 阻挡先攻要塞）；③ 本方首都沦陷 → MARCH_RELIEF
## ④ 友军激战 → REINFORCE；⑤ 到达目标 → SIEGING；⑥ 停战回 FREE
## 运行：godot --headless --path . --script res://tests/test_ai_army.gd

const RESULT_PATH := "user://test_ai_army_result.txt"

var _gm: Node


func _initialize() -> void:
	var out: Array[String] = []
	_gm = load("res://scripts/core/game_manager.gd").new()
	root.add_child(_gm)
	await process_frame
	_gm.set("_adjacency", {
		"H": {"X": "land"},
		"X": {"H": "land", "F": "land"},
		"F": {"X": "land", "D": "land"},
		"D": {"F": "land", "P": "land"},
		"P": {"D": "land"},
	})
	_gm.set("army_count", {"England": 10, "Scotland": 5, "Wales": 3})
	_gm.set("capital_province", {"England": "H", "Scotland": "D", "Wales": "P"})
	_gm.set("province_owner", {"H": "England", "X": "Scotland", "F": "Scotland", "D": "Scotland", "P": "Wales"})
	_gm.set("province_buildings", {"H": {"fort": 0}, "X": {"fort": 0}, "F": {"fort": 3}, "D": {"fort": 0}, "P": {"fort": 0}})

	# ① 停战 → FREE（Wales 为玩家，跳过；England/Scotland 未参战）
	_gm.set("player_country_id", "Wales")
	_gm.set("army_position", {"England": "H", "Scotland": "X", "Wales": "P"})
	_gm.set("wars", [])
	_gm.set("ai_army_state", {"England": "MARCH_SIEGE", "Scotland": "MARCH_SIEGE"})
	_gm.set("army_order", {"England": "F", "Scotland": "D"})
	_gm.call("_tick_ai_armies")
	var st0: Dictionary = _gm.get("ai_army_state")
	var or0: Dictionary = _gm.get("army_order")
	out.append("peace: England FREE + order cleared: %s / Scotland FREE: %s" % [
		st0.get("England", "") == "FREE" and or0.get("England", "") == "",
		st0.get("Scotland", "") == "FREE"])

	# ② 战争默认：England 攻 Scotland（敌首都 D 被要塞 F ZoC 阻挡 → 先攻 F）；Scotland 攻 England（无阻挡 → H）
	_gm.set("wars", [])
	_gm.set("army_position", {"England": "H", "Scotland": "X", "Wales": "P"})
	_gm.call("declare_war", "England", "Scotland")
	_gm.call("_tick_ai_armies")
	var st1: Dictionary = _gm.get("ai_army_state")
	var or1: Dictionary = _gm.get("army_order")
	out.append("England MARCH_SIEGE + order=F (ZoC 先攻要塞): %s (order=%s)" % [
		st1.get("England", "") == "MARCH_SIEGE" and or1.get("England", "") == "F", or1.get("England", "")])
	out.append("Scotland MARCH_SIEGE + order=H (无阻挡围敌首都): %s (order=%s)" % [
		st1.get("Scotland", "") == "MARCH_SIEGE" and or1.get("Scotland", "") == "H", or1.get("Scotland", "")])

	# ③ 本方首都沦陷 → MARCH_RELIEF（England 首都 H 被占，军队在 P 避开与 Scotland 同省交战）
	_gm.set("province_owner", {"H": "Scotland", "X": "Scotland", "F": "Scotland", "D": "Scotland", "P": "Wales"})
	_gm.set("army_position", {"England": "P", "Scotland": "X", "Wales": "P"})
	_gm.call("_tick_ai_armies")
	var st2: Dictionary = _gm.get("ai_army_state")
	var or2: Dictionary = _gm.get("army_order")
	out.append("England capital lost -> MARCH_RELIEF order=H: %s (order=%s)" % [
		st2.get("England", "") == "MARCH_RELIEF" and or2.get("England", "") == "H", or2.get("England", "")])

	# ④ 友军激战 → REINFORCE（England 为玩家跳过；Scotland+Wales 同盟，Wales 在 P 与 England 交战）
	_gm.set("player_country_id", "England")
	_gm.set("province_owner", {"H": "England", "X": "Scotland", "F": "Scotland", "D": "Scotland", "P": "Wales"})
	_gm.set("wars", [])
	_gm.set("army_position", {"England": "P", "Scotland": "X", "Wales": "P"})
	var wr: Dictionary = _gm.call("declare_war", "Scotland", "England")
	_gm.call("add_war_participant", "Wales", int(wr.get("war_id", 0)), "A")
	_gm.call("_tick_ai_armies")
	var st3: Dictionary = _gm.get("ai_army_state")
	var or3: Dictionary = _gm.get("army_order")
	out.append("Scotland ally in battle -> REINFORCE order=P: %s (order=%s)" % [
		st3.get("Scotland", "") == "REINFORCE" and or3.get("Scotland", "") == "P", or3.get("Scotland", "")])

	# ⑤ 到达敌方首都 → SIEGING（Scotland 已在 H = England 首都，驻留围城）
	_gm.set("wars", [])
	_gm.set("army_position", {"England": "P", "Scotland": "H", "Wales": "P"})
	_gm.call("declare_war", "Scotland", "England")
	_gm.call("_tick_ai_armies")
	var st4: Dictionary = _gm.get("ai_army_state")
	var or4: Dictionary = _gm.get("army_order")
	out.append("Scotland at enemy capital -> SIEGING order cleared: %s (state=%s)" % [
		st4.get("Scotland", "") == "SIEGING" and or4.get("Scotland", "") == "", st4.get("Scotland", "")])

	# ⑥ 停战 → 回 FREE（end_war 后 AI 军队回 FREE 原地待命）
	_gm.set("wars", [])
	var wr6: Dictionary = _gm.call("declare_war", "Scotland", "England")
	_gm.call("end_war", int(wr6.get("war_id", 0)))
	_gm.call("_tick_ai_armies")
	var st5: Dictionary = _gm.get("ai_army_state")
	out.append("after end_war Scotland -> FREE: %s" % (st5.get("Scotland", "") == "FREE"))

	root.remove_child(_gm)
	_gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
