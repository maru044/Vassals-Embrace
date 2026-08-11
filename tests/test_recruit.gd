extends SceneTree
## 引擎②-B2 招募冒烟测试：
## 20 金/队；上限拦截；金币不足拦截；成功扣款 + 军队+1
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
	var cap: int = gm.call("get_army_cap", "England")
	out.append("initial: England army=%d cap=%d gold=%.0f" % [army.get("England", -1), cap, gold.get("England", 0.0)])

	# 满编招募 → 应失败（已达上限）
	var r1: Dictionary = gm.call("recruit_army")
	out.append("recruit@cap    -> ok=%s error=%s" % [r1.get("ok"), r1.get("error", "")])

	# 军队降到 24，金币 20 → 应成功（25/25，金币 0）
	army["England"] = 24
	var r2: Dictionary = gm.call("recruit_army")
	out.append("recruit 24/25  -> ok=%s army=%d gold=%.0f" % [r2.get("ok"), r2.get("army", -1), r2.get("gold", -1)])

	# 再招 → 满编失败
	var r3: Dictionary = gm.call("recruit_army")
	out.append("recruit@25/25  -> ok=%s" % r3.get("ok"))

	# 金币不足：军队 24，金币 5 → 失败
	army["England"] = 24
	gold["England"] = 5.0
	var r4: Dictionary = gm.call("recruit_army")
	out.append("recruit gold5  -> ok=%s error=%s" % [r4.get("ok"), r4.get("error", "")])

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
