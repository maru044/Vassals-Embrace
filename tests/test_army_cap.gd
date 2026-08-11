extends SceneTree
## 引擎②-B1 军队上限冒烟测试：
## 公式 5 + 2×直辖地块（附庸 -3 队，受保护国不算附庸）；初始军队 = 上限
## 运行：godot --headless --path . --script res://tests/test_army_cap.gd

const RESULT_PATH := "user://test_army_cap_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame

	# 注入省份数据（与 game.gd 一致）
	var map_file := FileAccess.get_file_as_string("res://data/map_data.json")
	var map_data: Variant = JSON.parse_string(map_file)
	gm.set("province_owner", map_data["province_owner"])
	gm.call("_load_countries")

	out.append("== get_army_cap ==")
	var cases := {
		"England": 25, "Scotland": 17,
		"Wales": 4, "Northumberland": 4, "York": 4, "Durham": 4, "Westmorland": 4,
		"Isle of Man": 7,   # protectorate 不算附庸 → 不扣 3
		"The Isles": 7, "Orkney": 7, "Shetland": 7, "Tyrone": 7,
	}
	for cid in cases:
		var got: int = gm.call("get_army_cap", cid)
		var exp: int = cases[cid]
		out.append("[%s] %s cap=%d (expect %d)" % [cid, "OK" if got == exp else "FAIL", got, exp])

	out.append("== start_new_game 初始军队 = 上限 ==")
	gm.call("start_new_game", "England")
	var army: Dictionary = gm.get("army_count")
	out.append("England army=%d (expect 25)" % army.get("England", -1))
	out.append("Scotland army=%d (expect 17)" % army.get("Scotland", -1))
	out.append("Wales army=%d (expect 4)" % army.get("Wales", -1))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
