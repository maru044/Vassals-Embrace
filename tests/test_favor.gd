extends SceneTree
## 引擎⑨ 好感度系统冒烟测试：
## 初始好感（默认/附庸宗主加成/特例）/ change_favor clamp 0-100 /
## can_require_favor 要求门槛（>80，附庸/受保护国/联合统治按钮绑定）
## 运行：godot --headless --path . --script res://tests/test_favor.gd

const RESULT_PATH := "user://test_favor_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.call("_load_countries")
	gm.set("player_country_id", "England")
	# 用真实 map_data 省份归属（让 _all_country_ids 覆盖 27 国 → 初始好感正确写入）
	var map_file := FileAccess.get_file_as_string("res://data/map_data.json")
	var map_data: Variant = JSON.parse_string(map_file)
	gm.set("province_owner", map_data["province_owner"])
	gm.call("start_new_game", "England")

	# ① 初始好感：默认 20；附庸/宗主 +40（60）；特例（英格兰对威尔士 10 / 曼岛 80）
	out.append("default favor = 20 (Scotland): %s" % (absf(gm.get("player_favor").get("Scotland", 0.0) - 20.0) < 0.001))
	out.append("special Wales = 10: %s" % (absf(gm.get("player_favor").get("Wales", 0.0) - 10.0) < 0.001))
	out.append("special Isle of Man = 80: %s" % (absf(gm.get("player_favor").get("Isle of Man", 0.0) - 80.0) < 0.001))

	# ② change_favor：增减 + clamp 0-100
	gm.call("change_favor", "Scotland", 30.0)
	out.append("change +30 -> 50: %s" % (absf(gm.get("player_favor").get("Scotland", 0.0) - 50.0) < 0.001))
	gm.call("change_favor", "Scotland", 100.0)
	out.append("clamp upper 100: %s" % (gm.get("player_favor").get("Scotland", 0.0) == 100.0))
	gm.call("change_favor", "Scotland", -200.0)
	out.append("clamp lower 0: %s" % (gm.get("player_favor").get("Scotland", 0.0) == 0.0))

	# ③ can_require_favor：严格 >80（80 不可用，81 可用）—— 要求附庸/受保护/联合统治按钮绑定
	gm.set("player_favor", {"Scotland": 79.0})
	out.append("require @79 = false: %s" % (not gm.call("can_require_favor", "Scotland")))
	gm.set("player_favor", {"Scotland": 80.0})
	out.append("require @80 = false (strict >80): %s" % (not gm.call("can_require_favor", "Scotland")))
	gm.set("player_favor", {"Scotland": 80.1})
	out.append("require @80.1 = true: %s" % gm.call("can_require_favor", "Scotland"))
	gm.set("player_favor", {"Scotland": 100.0})
	out.append("require @100 = true: %s" % gm.call("can_require_favor", "Scotland"))
	# 未记录国家（无好感记录）→ 按 0 处理 → 不可要求
	out.append("require unknown = false: %s" % (not gm.call("can_require_favor", "Atlantis")))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
