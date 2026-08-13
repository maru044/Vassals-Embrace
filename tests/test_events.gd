extends SceneTree
## 引擎⑥ 事件系统冒烟测试（Master 8/13）：
## 事件表加载 / [Root.*] 变量渲染 / 历史(1400.9威尔士)与脉冲(5月至高王节日)触发排队 /
## 玩家选项落地(发起博弈+军队+临时修正) / 临时修正叠加+到期 / 军队超上限收敛
## 运行：godot --headless --path . --script res://tests/test_events.gd

const RESULT_PATH := "user://test_events_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "Wales")
	gm.set("year", 1400)
	gm.set("month", 9)
	gm.set("_country_list", [
		{"id": "England", "name": "英格兰", "title": "公主", "ruler_en": "Rosamond Lancaster", "government": "monarchy"},
		{"id": "Wales", "name": "威尔士", "title": "公主", "ruler_en": "Owena Glyndŵr", "government": "monarchy"},
		{"id": "The Isles", "name": "群岛领地", "title": "栖姬", "ruler_en": "Freya", "government": "piracy"},
		{"id": "Tyrone", "name": "蒂龙", "title": "犬姬", "ruler_en": "Niamh O'Neill", "government": "tribal"},
	])
	gm.set("army_count", {"England": 5, "Wales": 4, "The Isles": 3, "Tyrone": 3})

	# ① 事件表加载 + 变量渲染
	var ev: Dictionary = gm.call("get_event", "harvest")
	out.append("events loaded (harvest.name=丰收): %s" % (ev.get("name", "") == "丰收"))
	var txt: String = gm.call("resolve_event_vars", "[Root.GetFullTitle] 的领地迎来丰收", "Wales")
	out.append("resolve_event_vars = 威尔士公主 Owena Glyndŵr: %s" % (txt == "威尔士公主 Owena Glyndŵr 的领地迎来丰收"))

	# ② 历史事件（开局 1400.9 威尔士起义）→ 玩家排队（历史先于随机，队首=welsh_revolt）
	gm.set("player_event_queue", [])
	gm.set("_fired_historical", {})
	gm.call("_tick_events")
	var q1: Array = gm.get("player_event_queue")
	out.append("historical welsh_revolt queued @1400.9: %s" % _queue_has(q1, "welsh_revolt"))
	out.append("fired_historical welsh_revolt: %s" % (gm.get("_fired_historical").get("welsh_revolt", false) == true))
	var q1b: Dictionary = gm.call("peek_player_event")
	out.append("peek first event = welsh_revolt: %s" % (q1b.get("event_id", "") == "welsh_revolt"))

	# ④ 玩家选主选项 → 发起博弈 + 军队 +15 + 英格兰士气 -20% 修正
	gm.set("country_gold", {"Wales": 0.0})
	gm.set("country_prestige", {"Wales": 0.0})
	gm.call("resolve_player_event", 0)
	var plays: Array = gm.get("plays")
	out.append("welsh main -> play vs England: %s" % (plays.size() >= 1 and plays[0].get("target", "") == "England"))
	out.append("welsh army 4+15=19 (cap+15 mod): %s" % (gm.get("army_count").get("Wales", 0) == 19))
	out.append("England morale mod = -0.2: %s" % (absf(gm.call("country_event_modifier", "England", "morale") + 0.2) < 0.001))

	# ⑤ 临时修正叠加 + 到期清除
	gm.set("modifiers", {})
	gm.call("_add_modifier", "England", "army_cap", 15, 12)
	out.append("army_cap mod England = 15: %s" % (gm.call("country_event_modifier", "England", "army_cap") == 15.0))
	for i in 12:
		gm.call("_tick_modifiers")
	out.append("modifier expired after 12 months: %s" % (gm.call("country_event_modifier", "England", "army_cap") == 0.0))

	# ⑦ 军队超上限收敛：给 10 队但 cap=5 → 降到 5；配合 army_cap +15 → 保持 10
	gm.set("army_count", {"England": 5, "Wales": 4, "The Isles": 3, "Tyrone": 3})
	gm.set("province_owner", {})
	gm.set("modifiers", {})
	gm.call("_apply_option_effects", "Wales", {"effects": {"army": 10}}, "test")
	out.append("army 10 > cap5 -> clamped 5: %s" % (gm.get("army_count").get("Wales", 0) == 5))
	gm.set("army_count", {"England": 5, "Wales": 4, "The Isles": 3, "Tyrone": 3})
	gm.set("modifiers", {})
	gm.call("_apply_option_effects", "Wales", {"effects": {"army": 10, "modifiers": [{"type": "army_cap", "value": 15, "months": 12}]}}, "test")
	out.append("army 4+10=14 + cap+15 -> kept 14: %s" % (gm.get("army_count").get("Wales", 0) == 14))

	# ⑧ 脉冲事件（5月 至高王节日，凯尔特限定）→ 凯尔特玩家排队
	gm.set("player_event_queue", [])
	gm.set("_pulse_last", {})
	gm.set("_fired_historical", {})
	gm.set("player_country_id", "Tyrone")
	gm.set("month", 5)
	gm.call("_tick_events")
	var q2: Array = gm.get("player_event_queue")
	out.append("pulse high_king_festival queued @5月 celtic: %s" % _queue_has(q2, "high_king_festival"))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()


func _queue_has(queue: Array, event_id: String) -> bool:
	for e in queue:
		if str(e.get("event_id", "")) == event_id:
			return true
	return false
