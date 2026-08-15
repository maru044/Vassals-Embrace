extends SceneTree
## 引擎⑨ 存档测试：serialize/deserialize 往返（全运行态）/ 槽位存取（save/load/delete/get_slots_info）
## 运行：godot --headless --path . --script res://tests/test_save.gd

const RESULT_PATH := "user://test_save_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.call("_load_countries")
	gm.call("_ensure_situations")
	gm.call("_init_situations")
	gm.call("start_new_game", "Scotland")
	# 造一些状态
	gm.set("country_gold", {"Scotland": 123.0, "England": 50.0})
	gm.set("country_prestige", {"Scotland": 70.0, "England": 50.0})
	gm.set("army_count", {"Scotland": 15, "England": 13})
	gm.set("army_position", {"Scotland": "Lothian", "England": "London"})
	gm.call("_create_union", "Scotland", "England")
	gm.set("high_king_id", "Tyrone")
	gm.call("add_raid", 3)
	gm.set("month", 6)
	gm.set("year", 1410)
	gm.call("change_situation", "hundred_years_war", 0)  # 无操作（England 无此局势？玩家 Scotland 有）

	# ① serialize → deserialize 往返（不经文件）
	var data: Dictionary = gm.call("serialize")
	var gm2: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm2)
	await process_frame
	gm2.call("deserialize", data)
	out.append("roundtrip player: %s" % (gm2.get("player_country_id") == "Scotland"))
	out.append("roundtrip year/month: %s" % (gm2.get("year") == 1410 and gm2.get("month") == 6))
	out.append("roundtrip gold: %s" % (gm2.get("country_gold").get("Scotland", 0.0) == 123.0))
	out.append("roundtrip prestige: %s" % (gm2.get("country_prestige").get("Scotland", 0.0) == 70.0))
	out.append("roundtrip army: %s" % (gm2.get("army_count").get("Scotland", 0) == 15))
	out.append("roundtrip army_position: %s" % (gm2.get("army_position").get("Scotland", "") == "Lothian"))
	out.append("roundtrip union: %s" % (not gm2.call("union_of", "England").is_empty()))
	out.append("roundtrip high_king: %s" % (gm2.get("high_king_id") == "Tyrone"))
	out.append("roundtrip raid_count: %s" % (gm2.get("raid_count") == 3))

	# ② 槽位存取（SaveManager autoload）
	var sm: Node = root.get_node("/root/SaveManager")
	sm.call("delete_slot", 0)
	sm.call("save_game_to_slot", 0, gm2.call("serialize"))
	var info: Array = sm.call("get_slots_info")
	out.append("slot0 occupied after save: %s" % (info[0] != null))
	out.append("slots count == 6: %s" % (info.size() == 6))
	var loaded: Dictionary = sm.call("load_game_from_slot", 0)
	out.append("slot0 load player: %s" % (loaded.get("player_country_id", "") == "Scotland"))
	out.append("slot0 load gold: %s" % (loaded.get("country_gold", {}).get("Scotland", 0.0) == 123.0))
	sm.call("delete_slot", 0)
	var info2: Array = sm.call("get_slots_info")
	out.append("slot0 empty after delete: %s" % (info2[0] == null))

	root.remove_child(gm)
	gm.free()
	root.remove_child(gm2)
	gm2.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
