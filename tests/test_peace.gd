extends SceneTree
## 引擎④ 和平条约冒烟测试：sign_peace 落地各类条款 + 结束战争 + 投降标记清理 + 工具注册
## 运行：godot --headless --path . --script res://tests/test_peace.gd

const RESULT_PATH := "user://test_peace_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")
	gm.set("country_gold", {"England": 100.0, "Scotland": 200.0})
	gm.set("province_owner", {
		"Lothian": "England", "Strathclyde": "England",
		"Galloway": "Scotland", "Aberdeen": "England",
	})
	gm.set("runtime_liege", {})
	gm.set("runtime_vassal_type", {})
	gm.set("surrender_flag", {})
	gm.set("wars", [])
	gm.set("_next_war_id", 1)

	# ① 宣战 + find_war
	var dw: Dictionary = gm.call("declare_war", "Scotland", "England", "vassalize")
	var war_id: int = int(dw.get("war_id", 0))
	out.append("① declare_war ok war_id=%d: %s" % [war_id, dw.get("ok", false)])
	out.append("① find_war found: %s" % (not (gm.call("find_war", war_id) as Dictionary).is_empty()))

	# ② 白和平（空条款）→ 结束战争
	var sp0: Dictionary = gm.call("sign_peace", war_id, "A", [])
	out.append("② white peace ok + wars cleared: %s" % (
		sp0.get("ok", false) and (gm.get("wars") as Array).is_empty()))
	out.append("② find_war after peace empty: %s" % (gm.call("find_war", war_id) as Dictionary).is_empty())

	# ③ 未知战争 → 失败
	var spbad: Dictionary = gm.call("sign_peace", 999, "A", [])
	out.append("③ unknown war ok=false: %s" % (spbad.get("ok", false) == false))

	# ④ vassalize 附庸化条款：苏格兰胜 → 英格兰成附庸
	var dw4: Dictionary = gm.call("declare_war", "Scotland", "England", "vassalize")
	var wid4: int = int(dw4.get("war_id", 0))
	var spv: Dictionary = gm.call("sign_peace", wid4, "A", [{"type": "vassalize", "target": "England"}])
	out.append("④ vassalize applied: %s" % (
		spv.get("ok", false) and gm.get("runtime_liege").get("England", "") == "Scotland"
		and gm.get("runtime_vassal_type").get("England", "") == "feudal"))
	out.append("④ wars ended: %s" % (gm.get("wars") as Array).is_empty())

	# ⑤ annex 吞并条款：苏格兰吞并英格兰 → 英格兰省份全归苏格兰
	var dw5: Dictionary = gm.call("declare_war", "Scotland", "England", "annex")
	var wid5: int = int(dw5.get("war_id", 0))
	var spa: Dictionary = gm.call("sign_peace", wid5, "A", [{"type": "annex", "target": "England"}])
	var eng_left := 0
	for p in gm.get("province_owner"):
		if gm.get("province_owner")[p] == "England":
			eng_left += 1
	out.append("⑤ annex applied (England provinces left=%d): %s" % [eng_left, spa.get("ok", false) and eng_left == 0])

	# ⑥ province 割地条款：苏格兰割英格兰的 Aberdeen 省
	gm.set("province_owner", {
		"Lothian": "England", "Strathclyde": "England",
		"Galloway": "Scotland", "Aberdeen": "England",
	})
	var dw6: Dictionary = gm.call("declare_war", "Scotland", "England", "claim")
	var wid6: int = int(dw6.get("war_id", 0))
	var spp: Dictionary = gm.call("sign_peace", wid6, "A", [{"type": "province", "value": "Aberdeen"}])
	out.append("⑥ province ceded Aberdeen->Scotland: %s" % (
		spp.get("ok", false) and gm.get("province_owner").get("Aberdeen", "") == "Scotland"))

	# ⑦ gold 赔款条款：英格兰赔 50 金给苏格兰
	var dw7: Dictionary = gm.call("declare_war", "Scotland", "England", "claim")
	var wid7: int = int(dw7.get("war_id", 0))
	var spg: Dictionary = gm.call("sign_peace", wid7, "A", [{"type": "gold", "value": 50}])
	out.append("⑦ gold transfer S=250 E=50: %s" % (
		spg.get("ok", false)
		and gm.get("country_gold").get("Scotland", 0.0) == 250.0
		and gm.get("country_gold").get("England", 0.0) == 50.0))

	# ⑧ release 释放附庸条款：英格兰的附庸威尔士被释放
	gm.set("runtime_liege", {"Wales": "England", "England": ""})
	var dw8: Dictionary = gm.call("declare_war", "Scotland", "England", "claim")
	var wid8: int = int(dw8.get("war_id", 0))
	var spr: Dictionary = gm.call("sign_peace", wid8, "A", [{"type": "release", "value": "Wales"}])
	out.append("⑧ release vassal Wales: %s" % (
		spr.get("ok", false) and gm.get("runtime_liege").get("Wales", "") == ""))

	# ⑨ 战争结束清除参战方投降标记
	gm.set("surrender_flag", {"England": true, "Scotland": true})
	var dw9: Dictionary = gm.call("declare_war", "Scotland", "England", "claim")
	var wid9: int = int(dw9.get("war_id", 0))
	var sp9: Dictionary = gm.call("sign_peace", wid9, "A", [])
	out.append("⑨ surrender flags cleared after peace: %s" % (
		sp9.get("ok", false) and (gm.get("surrender_flag") as Dictionary).is_empty()))

	# ⑩ tool_executor 已注册 sign_peace 工具
	var te: Node = load("res://scripts/llm/tool_executor.gd").new()
	root.add_child(te)
	await process_frame
	var has_tool: bool = false
	for t in te.get("TOOLS"):
		var fn: Dictionary = t.get("function", {})
		if str(fn.get("name", "")) == "sign_peace":
			has_tool = true
			break
	out.append("⑩ tool_executor has sign_peace: %s" % has_tool)
	root.remove_child(te)
	te.free()

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
