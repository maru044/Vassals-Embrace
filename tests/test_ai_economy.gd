extends SceneTree
## 引擎①-AI经营冒烟测试：AI 主动花钱——优先补兵到上限，然后升级经济建筑
## 运行：godot --headless --path . --script res://tests/test_ai_economy.gd

const RESULT_PATH := "user://test_ai_economy_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")   # 玩家 = 英格兰（不参与 AI 经营）
	# AI = Wales：1 直辖省 → 上限 = 5 + 2×1 = 7；初始 3 队、500 金
	gm.set("province_owner", {"Wales": "Wales"})
	gm.set("province_buildings", {"Wales": {"farm": 1, "market": 1, "brothel": 1}})
	gm.set("army_count", {"Wales": 3, "England": 5})
	gm.set("country_gold", {"Wales": 500.0, "England": 0.0})

	gm.call("_ai_economy")

	var army: Dictionary = gm.get("army_count")
	var gold: Dictionary = gm.get("country_gold")
	var bld: Dictionary = gm.get("province_buildings")
	var wb: Dictionary = bld.get("Wales", {})
	out.append("Wales army after AI = %d (expect 7)" % army.get("Wales", -1))
	out.append("Wales gold after AI = %d (expect 70)" % int(gold.get("Wales", -1.0)))
	out.append("Wales farm=%d market=%d brothel=%d (expect 3/2/1)" % [wb.get("farm", 0), wb.get("market", 0), wb.get("brothel", 0)])
	# 玩家不参与 AI 经营
	out.append("England army = %d gold = %d (expect 5/0)" % [army.get("England", -1), int(gold.get("England", -1.0))])

	# 补充：金币不足以补满时——只补能负担的队数（重新取最新字典）
	gm.set("army_count", {"Wales": 6, "England": 5})
	gm.set("country_gold", {"Wales": 30.0, "England": 0.0})
	gm.call("_ai_economy")
	var army2: Dictionary = gm.get("army_count")
	var gold2: Dictionary = gm.get("country_gold")
	out.append("Wales army with 30g = %d (expect 7, one more) gold = %d (expect 10)" % [army2.get("Wales", -1), int(gold2.get("Wales", -1.0))])

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
