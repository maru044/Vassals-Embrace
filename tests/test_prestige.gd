extends SceneTree
## 引擎① 威望加成冒烟测试（Master 8/14：每 100 威望 +10% 士气/收入）：
## prestige_bonus / 士气公式含威望 / 收入公式含威望 / 负威望减成
## 运行：godot --headless --path . --script res://tests/test_prestige.gd

const RESULT_PATH := "user://test_prestige_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")
	gm.set("army_count", {"England": 10})
	gm.set("country_prestige", {"England": 100.0})
	gm.set("province_owner", {})   # 无地块 → 收入 = 基础 5

	# ① prestige_bonus：每 100 威望 +10%（0.1 系数）
	out.append("bonus @100 = 0.10: %s" % (absf(gm.call("prestige_bonus", "England") - 0.10) < 0.0001))
	gm.set("country_prestige", {"England": 50.0})
	out.append("bonus @50 = 0.05: %s" % (absf(gm.call("prestige_bonus", "England") - 0.05) < 0.0001))
	gm.set("country_prestige", {"England": 0.0})
	out.append("bonus @0 = 0.00: %s" % (absf(gm.call("prestige_bonus", "England")) < 0.0001))
	gm.set("country_prestige", {"England": -100.0})
	out.append("bonus @-100 = -0.10: %s" % (absf(gm.call("prestige_bonus", "England") + 0.10) < 0.0001))

	# ② 士气含威望：10 队 × 基础 10，威望 100 → 110；威望 0 → 100
	gm.set("country_prestige", {"England": 100.0})
	out.append("morale @100 = 110: %s" % (absf(gm.call("get_total_morale", "England") - 110.0) < 0.001))
	gm.set("country_prestige", {"England": 0.0})
	out.append("morale @0 = 100: %s" % (absf(gm.call("get_total_morale", "England") - 100.0) < 0.001))
	gm.set("country_prestige", {"England": -100.0})
	out.append("morale @-100 = 90: %s" % (absf(gm.call("get_total_morale", "England") - 90.0) < 0.001))

	# ③ 收入含威望：无地块基础 5，威望 100 → 5.5；威望 0 → 5
	gm.set("country_prestige", {"England": 100.0})
	out.append("income @100 = 5.5: %s" % (absf(gm.call("get_country_income", "England") - 5.5) < 0.001))
	gm.set("country_prestige", {"England": 0.0})
	out.append("income @0 = 5.0: %s" % (absf(gm.call("get_country_income", "England") - 5.0) < 0.001))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
