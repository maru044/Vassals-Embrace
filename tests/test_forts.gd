extends SceneTree
## 引擎②-B3-0 初始堡垒冒烟测试：
## 规则：7 省初始 LV2 + 首都默认 +1（7 省皆为某国首都 → LV3）；其他首都 LV1；普通省 LV0
## 运行：godot --headless --path . --script res://tests/test_forts.gd

const RESULT_PATH := "user://test_forts_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var packed: PackedScene = load("res://scenes/game/game.tscn")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var pb: Dictionary = gm.get("province_buildings")

	var checks := {
		# 7 初始要塞省（皆为首都）→ LV3
		"Lothian": 3, "Northumberland": 3, "Yorkshire": 3, "Wales": 3,
		"Tyrone": 3, "Offaly": 3, "Desmond": 3,
		# 其他首都 → LV1（含爱尔兰诸部）
		"London": 1, "Durham": 1, "Westmorland": 1, "Isle of Man": 1,
		"Ulster": 1, "Munster": 1, "The Isles": 1, "Orkney": 1, "Shetland": 1,
		"Sligo": 1, "Mayo": 1, "Breifne": 1, "Leinster": 1, "Thomond": 1, "Wexford": 1,
		# 普通省（非首都）→ LV0
		"Wessex": 0, "Central": 0, "Aberdeen": 0, "Pale": 0, "Highlands": 0,
	}
	for p in checks:
		var fort: int = pb.get(p, {}).get("fort", -1)
		var ok: bool = fort == checks[p]
		out.append("[%s] fort=%d (expect %d) %s" % [p, fort, checks[p], "OK" if ok else "FAIL"])

	root.remove_child(inst)
	inst.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
