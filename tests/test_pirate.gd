extends SceneTree
## 引擎⑧ 海盗联盟冒烟测试：
## 成员 / 沿海判定 / 成功率修正（劫掠季·要塞·富裕） / 劫掠 CD（4月）/
## do_raid 校验（非海盗/非沿海/CD中拒绝）/ 成功（金币+士气+功勋+raid_count）/ 失败（威望士气）/ CD 倒计时
## 运行：godot --headless --path . --script res://tests/test_pirate.gd

const RESULT_PATH := "user://test_pirate_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.call("_load_countries")
	gm.set("player_country_id", "The Isles")
	gm.set("month", 3)
	gm.set("year", 1401)
	gm.set("army_count", {"The Isles": 7, "England": 13, "Scotland": 9})
	gm.set("country_gold", {"The Isles": 20.0, "England": 20.0, "Scotland": 20.0})
	gm.set("country_prestige", {"The Isles": 50.0, "England": 50.0, "Scotland": 50.0})
	# 手动邻接图：The Isles/London/Lothian 沿海，Midlands 内陆
	gm.set("_adjacency", {
		"The Isles": {"Atlantic": "sea", "Lothian": "land"},
		"London": {"Thames": "sea", "Midlands": "land"},
		"Lothian": {"The Isles": "land", "North Sea": "sea"},
		"Midlands": {"London": "land"},
	})
	gm.set("province_owner", {"The Isles": "The Isles", "London": "England", "Lothian": "Scotland", "Midlands": "England"})
	gm.set("province_buildings", {
		"The Isles": {"fort": 1, "market": 1, "brothel": 1},
		"London": {"fort": 1, "market": 2, "brothel": 2},
		"Lothian": {"fort": 1, "market": 1, "brothel": 1},
		"Midlands": {"fort": 0, "market": 1, "brothel": 1},
	})
	gm.set("army_morale", {"The Isles": gm.call("get_total_morale", "The Isles"), "England": gm.call("get_total_morale", "England"), "Scotland": gm.call("get_total_morale", "Scotland")})

	# ① 成员 = 3 栖姬（piracy 政体）
	var members: Array = gm.call("get_pirate_members")
	out.append("pirate members == 3: %s" % (members.size() == 3))
	out.append("The Isles in members: %s" % members.has("The Isles"))

	# ② 沿海判定
	out.append("coastal The Isles: %s" % gm.call("_is_coastal", "The Isles"))
	out.append("coastal London: %s" % gm.call("_is_coastal", "London"))
	out.append("coastal Lothian: %s" % gm.call("_is_coastal", "Lothian"))
	out.append("NOT coastal Midlands: %s" % (not gm.call("_is_coastal", "Midlands")))

	# ③ 成功率修正：The Isles->London（fort1 不扣 + wealth4 +10%）基础 60% → 70%
	out.append("chance London = 0.70: %s" % (absf(gm.call("raid_success_chance", "The Isles", "London") - 0.70) < 0.001))
	# Midlands wealth2 不加 → 60%
	out.append("chance Midlands = 0.60: %s" % (absf(gm.call("raid_success_chance", "The Isles", "Midlands") - 0.60) < 0.001))
	# 劫掠季（9月）+15% → London 0.85
	gm.set("month", 9)
	out.append("chance raid season London = 0.85: %s" % (absf(gm.call("raid_success_chance", "The Isles", "London") - 0.85) < 0.001))
	gm.set("month", 3)

	# ④ 初始可用（CD 0）
	out.append("raid available initial: %s" % gm.call("raid_available", "The Isles"))

	# ⑤ do_raid 校验：非海盗国拒绝
	var r0: Dictionary = gm.call("do_raid", "England", "London")
	out.append("non-pirate rejected: %s" % (not r0.get("ok", false)))
	# 非沿海拒绝
	var r0b: Dictionary = gm.call("do_raid", "The Isles", "Midlands")
	out.append("non-coastal rejected: %s" % (not r0b.get("ok", false)))

	# ⑥ do_raid 执行：结构 + CD 4
	var r1: Dictionary = gm.call("do_raid", "The Isles", "London")
	out.append("do_raid ok: %s" % r1.get("ok", false))
	out.append("do_raid entered cooldown 4: %s" % (gm.call("raid_remaining", "The Isles") == 4))
	out.append("do_raid has success field: %s" % r1.has("success"))
	# 成功分支数值
	if r1.get("success", false):
		out.append("raid success gold >= 15: %s" % (gm.get("country_gold").get("The Isles", 0.0) >= 15.0))
		out.append("raid success merit +1: %s" % (gm.get("raid_merit").get("The Isles", 0) == 1))
		out.append("raid success raid_count +1: %s" % (gm.get("raid_count") == 1))
	else:
		out.append("raid fail prestige -3: %s" % (gm.get("country_prestige").get("The Isles", 0.0) == 47.0))

	# ⑦ CD 中拒绝
	var r2: Dictionary = gm.call("do_raid", "The Isles", "London")
	out.append("in cooldown rejected: %s" % (not r2.get("ok", false)))

	# ⑧ CD 倒计时：3 次 -1 后仍冷却，第 4 次归零可用
	gm.call("_tick_raid_cooldowns")
	out.append("cooldown after 1 tick = 3: %s" % (gm.call("raid_remaining", "The Isles") == 3))
	gm.call("_tick_raid_cooldowns")
	gm.call("_tick_raid_cooldowns")
	out.append("cooldown after 3 ticks = 1: %s" % (gm.call("raid_remaining", "The Isles") == 1))
	out.append("not available (cd 1): %s" % (not gm.call("raid_available", "The Isles")))
	gm.call("_tick_raid_cooldowns")
	out.append("cooldown cleared, available: %s" % (gm.call("raid_remaining", "The Isles") == 0 and gm.call("raid_available", "The Isles")))

	# ⑨ 成功分支可达（循环直到成功，70% 概率）
	var got_success := false
	for i in 100:
		gm.set("raid_cooldown", {})
		var rs: Dictionary = gm.call("do_raid", "The Isles", "London")
		if rs.get("success", false):
			got_success = true
			break
	out.append("raid success achievable: %s" % got_success)

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
