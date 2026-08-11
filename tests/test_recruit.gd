extends SceneTree
## 引擎②-B2 招募冒烟测试：
## 20 金/队；每月限 1 队（月末重置）；上限拦截；金币不足拦截；成功扣款 + 军队+1
## 运行：godot --headless --path . --script res://tests/test_recruit.gd

const RESULT_PATH := "user://test_recruit_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	var map_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_data.json"))
	gm.set("province_owner", map_data["province_owner"])
	gm.call("start_new_game", "England")

	var army: Dictionary = gm.get("army_count")
	var gold: Dictionary = gm.get("country_gold")
	var rmt: Dictionary = gm.get("recruited_this_month")
	var cap: int = gm.call("get_army_cap", "England")
	out.append("initial: England army=%d cap=%d gold=%.0f" % [army.get("England", -1), cap, gold.get("England", 0.0)])

	# 首次招募（13→14，20金）→ 成功
	var r1: Dictionary = gm.call("recruit_army")
	out.append("recruit#1       -> ok=%s army=%d gold=%.0f" % [r1.get("ok"), r1.get("army", -1), r1.get("gold", -1)])

	# 同月二次招募 → 失败（每月限 1 队）
	var r2: Dictionary = gm.call("recruit_army")
	out.append("recruit#2 same  -> ok=%s error=%s" % [r2.get("ok"), r2.get("error", "")])

	# 补金币 + 模拟月末重置 → 可再招（14→15）
	gold["England"] = 20.0
	rmt.clear()
	var r3: Dictionary = gm.call("recruit_army")
	out.append("recruit#3 next  -> ok=%s army=%d" % [r3.get("ok"), r3.get("army", -1)])

	# 上限拦截：军队设 24（差 1 到上限），补金币+重置 → 招募到 25；再重置后招 → 已达上限
	army["England"] = 24
	gold["England"] = 100.0
	rmt.clear()
	var r4: Dictionary = gm.call("recruit_army")
	rmt.clear()
	var r5: Dictionary = gm.call("recruit_army")
	out.append("recruit to cap  -> r4 ok=%s army=%d | r5 ok=%s error=%s" % [r4.get("ok"), r4.get("army", -1), r5.get("ok"), r5.get("error", "")])

	# 金币不足：军队 24、金币 5、重置 → 失败
	army["England"] = 24
	gold["England"] = 5.0
	rmt.clear()
	var r6: Dictionary = gm.call("recruit_army")
	out.append("recruit gold5   -> ok=%s error=%s" % [r6.get("ok"), r6.get("error", "")])

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
